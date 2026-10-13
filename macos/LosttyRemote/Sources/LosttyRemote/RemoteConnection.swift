import Citadel
import Foundation
import NIOCore
import NIOFoundationCompat
import NIOSSH

/// Where the Mac is and how to reach its Lostty tmux.
public struct RemoteHost: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var user: String
    /// A terminfo directory with xterm-ghostty to export as TERMINFO; nil
    /// when the Mac has it in ~/.terminfo (Phone Access copies it there).
    public var terminfoDir: String?

    public init(host: String, port: Int = 22, user: String, terminfoDir: String? = nil) {
        self.host = host
        self.port = port
        self.user = user
        self.terminfoDir = terminfoDir
    }

    /// This Mac, as the current user (the Mac debug window).
    public static func localhost(terminfoDir: String) -> RemoteHost {
        RemoteHost(host: "localhost", user: NSUserName(), terminfoDir: terminfoDir)
    }
}

/// An attached tmux client's input side.
public protocol RemoteTerminal: AnyObject, Sendable {
    func write(_ data: Data)
    func resize(cols: Int, rows: Int)
    func close()
}

@available(macOS 15, *)
public final class RemoteConnection: @unchecked Sendable {
    private let client: SSHClient
    private let host: RemoteHost

    private init(client: SSHClient, host: RemoteHost) {
        self.client = client
        self.host = host
    }

    public static func connect(to host: RemoteHost, key: RemoteKey, knownHosts: KnownHosts) async throws -> RemoteConnection {
        do {
            let client = try await SSHClient.connect(
                host: host.host,
                port: host.port,
                authenticationMethod: .custom(KeyAuth(user: host.user, key: key)),
                hostKeyValidator: .custom(PinnedHostKeys(host: host.host, port: host.port, knownHosts: knownHosts)),
                reconnect: .never)
            return RemoteConnection(client: client, host: host)
        } catch {
            throw RemoteError.mapConnectError(error)
        }
    }

    /// Connects to the first host that answers: the Mac's Tailscale name,
    /// then its address. Only "couldn't reach" moves on; a refused key, a
    /// changed host key or a cancelled Face ID stop at once.
    public static func connect(toFirstReachable hosts: [RemoteHost], key: RemoteKey, knownHosts: KnownHosts) async throws -> RemoteConnection {
        try await HostFallback.first(hosts) { try await connect(to: $0, key: key, knownHosts: knownHosts) }
    }

    /// The Mac's Lostty tmux sessions; none when no tmux server is running.
    public func sessions() async throws -> [RemoteSession] {
        do {
            let out = try await client.executeCommand(TmuxRemote.listCommand)
            return TmuxRemote.parseListing(String(buffer: out))
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 1 {
            // tmux exits 1 when no server is running; anything else is a
            // real failure.
            return []
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 127 {
            throw RemoteError.tmuxMissing
        }
    }

    /// Ends session `sessionID` (named `name`) on the Mac, noting that this
    /// phone (`device`) closed it. A session that already ended, or whose id
    /// now names another session (tmux exits 1), is left alone.
    public func killSession(_ sessionID: String, name: String, device: String) async throws {
        do {
            _ = try await client.executeCommand(try TmuxRemote.killCommand(sessionID: sessionID, name: name, device: device))
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 1 {
            return
        }
    }

    /// Names session `sessionID` (nil: back to automatic). False when it
    /// ended or its id now names another session.
    public func setLabel(_ label: String?, sessionID: String, name: String) async throws -> Bool {
        do {
            _ = try await client.executeCommand(try TmuxRemote.renameCommand(sessionID: sessionID, name: name, label: label))
            return true
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 1 {
            return false
        }
    }

    /// The models `agent` can start with: those it lists on the Mac, else
    /// its fallback ones.
    public func agentModels(_ agent: TerminalAgent) async throws -> AgentModelList {
        let listed = TmuxRemote.parseAgentModels(
            String(buffer: try await client.executeCommand(TmuxRemote.agentModelsCommand(agent))), for: agent)
        return listed.models.isEmpty ? AgentModelList(models: agent.fallbackModels, defaultModel: listed.defaultModel) : listed
    }

    /// Folders below `path` (as `folder(at:)` takes it) named like
    /// `keyword`; nil when it isn't there or can't be opened.
    public func searchFolders(in path: String?, matching keyword: String) async throws -> FolderSearch? {
        guard let command = TmuxRemote.searchFoldersCommand(in: path, matching: keyword) else { return nil }
        do {
            return TmuxRemote.parseFolderSearch(String(buffer: try await client.executeCommand(command)))
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 3 {
            return nil
        }
    }

    /// Folder `path` on the Mac (the home folder when nil); nil when it
    /// isn't there or can't be opened.
    public func folder(at path: String?) async throws -> MacFolder? {
        do {
            return TmuxRemote.parseFolder(String(buffer: try await client.executeCommand(TmuxRemote.folderCommand(path: path))))
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 3 {
            return nil
        }
    }

    /// Asks the Mac's Lostty for a new terminal. Throws `RemoteError.noLostty`
    /// when no tmux server runs there.
    public func requestNewTerminal(_ request: NewTerminalRequest) async throws {
        do {
            _ = try await client.executeCommand(TmuxRemote.requestNewTerminalCommand(request))
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 1 {
            throw RemoteError.noLostty
        }
    }

    /// The Mac's answer to request `id`, once there is one.
    public func newTerminalAnswer(id: String) async throws -> NewTerminalAnswer? {
        NewTerminalAnswer(String(buffer: try await client.executeCommand(TmuxRemote.newTerminalAnswerCommand(id: id))))
    }

    /// Withdraws request `id` and drops its answer.
    public func clearNewTerminal(id: String) async {
        _ = try? await client.executeCommand(TmuxRemote.clearNewTerminalCommand(id: id))
    }

    /// A logo's texture tile the Mac drew (`SessionSkin.Texture.Look.logo`):
    /// the PNG's bytes, or nil when `path` isn't one or can't be read.
    public func textureTile(at path: String) async throws -> Data? {
        guard let command = TmuxRemote.readTileCommand(path: path) else { return nil }
        let out = try await client.executeCommand(command)
        return Data(base64Encoded: String(buffer: out), options: .ignoreUnknownCharacters)
    }

    /// Why session `sessionID` ended: its end tag, and whether it is in
    /// fact still there. nil when the answer is unreadable.
    public func endProbe(_ sessionID: String) async throws -> EndProbe? {
        let out = try await client.executeCommand(try TmuxRemote.endProbeCommand(sessionID: sessionID))
        return TmuxRemote.parseEndProbe(String(buffer: out))
    }

    /// One event per change to the Mac's sessions (tmux's `lostty-changed`
    /// channel), on its own channel of this connection. Changes that arrive
    /// while one is unread fold into it. Ends when the Mac has no tmux
    /// server or the connection drops; closing the connection is the only
    /// way to stop it early (Citadel's stream doesn't close its channel).
    public func watchChanges() async throws -> AsyncStream<Void> {
        let output = try await client.executeCommandStream(TmuxRemote.watchCommand)
        return AsyncStream(Void.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let reader = Task {
                do {
                    for try await chunk in output {
                        if case .stdout(let buffer) = chunk, buffer.readableBytes > 0 { continuation.yield(()) }
                    }
                } catch {
                    // Exit 1 (no server) or a dropped connection: the watch ends.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }

    /// Attaches to session `sessionID` on a PTY and runs until the client
    /// ends. `onOpen` hands over the input side once the PTY is up;
    /// `onOutput` gets every received byte, from a task-group child task.
    public func attach(
        sessionID: String,
        name: String,
        cols: Int,
        rows: Int,
        onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async -> AttachEnd {
        let command: String
        do {
            command = try TmuxRemote.attachCommand(sessionID: sessionID, name: name, terminfoDir: host.terminfoDir)
        } catch {
            return .exited(1)
        }
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-ghostty",
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([:]))
        let outcome = AttachOutcome()
        do {
            try await client.withPTY(request, environment: []) { inbound, outbound in
                let (inputs, input) = AsyncStream.makeStream(of: PTYInput.self)
                let terminal = PTYTerminal(input: input)
                // Citadel's .pty mode always starts the login shell (there is
                // no PTY+exec mode), so the attach command is typed into it.
                // The leading space keeps it out of zsh history
                // (HIST_IGNORE_SPACE).
                input.yield(.data(Data((" " + command + "\n").utf8)))
                onOpen(terminal)
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        do {
                            for try await output in inbound {
                                switch output {
                                case .stdout(let buffer), .stderr(let buffer):
                                    onOutput(Data(buffer: buffer))
                                }
                            }
                            // Cancelled (the input side failed first): the
                            // stream just ends, which is not the remote ending.
                            if !Task.isCancelled { outcome.record(remoteEnded: true, exitCode: 0) }
                        } catch let failed as SSHClient.CommandFailed {
                            outcome.record(remoteEnded: true, exitCode: failed.exitCode)
                        }
                    }
                    group.addTask {
                        for await item in inputs {
                            switch item {
                            case .data(let data):
                                try await outbound.write(ByteBuffer(data: data))
                            case .resize(let cols, let rows):
                                try await outbound.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
                            case .close:
                                outcome.recordClosedLocally()
                                return
                            }
                        }
                    }
                    // Whichever side ends first (the remote exiting, or a
                    // local close) ends the channel.
                    try await group.next()
                    group.cancelAll()
                    input.finish()
                }
            }
            return outcome.end(afterError: nil)
        } catch {
            return outcome.end(afterError: error)
        }
    }

    public func close() async {
        try? await client.close()
    }
}

enum PTYInput: Sendable {
    case data(Data)
    case resize(cols: Int, rows: Int)
    case close
}

/// A terminal whose `close()` also runs `onClose` (the owner closing the whole
/// connection). Closing only the PTY channel waits for the peer's
/// CHANNEL_CLOSE, which on a dead path takes the TCP timeout.
public final class ClosingTerminal: RemoteTerminal, @unchecked Sendable {
    private let base: RemoteTerminal
    private let onClose: @Sendable () -> Void

    public init(_ base: RemoteTerminal, onClose: @escaping @Sendable () -> Void) {
        self.base = base
        self.onClose = onClose
    }

    public func write(_ data: Data) { base.write(data) }
    public func resize(cols: Int, rows: Int) { base.resize(cols: cols, rows: rows) }
    public func close() {
        base.close()
        onClose()
    }
}

/// Hands writes, resizes and close to the PTY task; never blocks the caller.
final class PTYTerminal: RemoteTerminal, @unchecked Sendable {
    private let input: AsyncStream<PTYInput>.Continuation

    init(input: AsyncStream<PTYInput>.Continuation) {
        self.input = input
    }

    func write(_ data: Data) { input.yield(.data(data)) }
    func resize(cols: Int, rows: Int) { input.yield(.resize(cols: cols, rows: rows)) }
    func close() { input.yield(.close) }
}

/// What happened inside the PTY closure. Citadel's own throw after the
/// closure is unreliable (it closes an already closed channel), so the end is
/// decided from what the closure saw.
final class AttachOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: AttachEnd?

    /// The first outcome wins.
    func record(remoteEnded: Bool, exitCode: Int?) {
        set(remoteEnded ? .exited(Int32(truncatingIfNeeded: exitCode ?? 0)) : nil)
    }

    func recordClosedLocally() {
        set(.exited(0))
    }

    private func set(_ end: AttachEnd?) {
        lock.lock()
        defer { lock.unlock() }
        if recorded == nil { recorded = end }
    }

    /// A recorded outcome beats any error thrown afterwards; `.lost` only when
    /// nothing was recorded.
    func end(afterError error: Error?) -> AttachEnd {
        lock.lock()
        defer { lock.unlock() }
        return recorded ?? .lost
    }
}

enum HostFallback {
    static func first<T>(_ hosts: [RemoteHost], _ connect: (RemoteHost) async throws -> T) async throws -> T {
        var last: Error = RemoteError.notPaired
        for host in hosts {
            do {
                return try await connect(host)
            } catch let error where RemoteError.isUnreachable(error) {
                last = error
            }
        }
        throw last
    }
}
