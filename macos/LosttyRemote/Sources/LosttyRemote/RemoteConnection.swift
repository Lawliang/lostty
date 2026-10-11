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
    /// Lostty.app's Contents/Resources/terminfo on the Mac (xterm-ghostty).
    public var terminfoDir: String

    public init(host: String, port: Int = 22, user: String, terminfoDir: String) {
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
        let client = try await SSHClient.connect(
            host: host.host,
            port: host.port,
            authenticationMethod: .custom(KeyAuth(user: host.user, key: key)),
            hostKeyValidator: .custom(PinnedHostKeys(host: host.host, port: host.port, knownHosts: knownHosts)),
            reconnect: .never)
        return RemoteConnection(client: client, host: host)
    }

    /// The Mac's Lostty tmux sessions; none when no tmux server is running.
    public func sessions() async throws -> [RemoteSession] {
        do {
            let out = try await client.executeCommand(TmuxRemote.listCommand)
            return TmuxRemote.parse(String(buffer: out))
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 1 {
            // tmux exits 1 when no server is running; anything else
            // (127: tmux missing, …) is a real failure.
            return []
        }
    }

    /// Attaches to session `sessionID` on a PTY and runs until the client
    /// ends. `onOpen` hands over the input side once the PTY is up;
    /// `onOutput` gets every received byte, from a task-group child task.
    public func attach(
        sessionID: String,
        cols: Int,
        rows: Int,
        onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async -> AttachEnd {
        let command: String
        do {
            command = try TmuxRemote.attachCommand(sessionID: sessionID, terminfoDir: host.terminfoDir)
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
                            outcome.record(remoteEnded: true, exitCode: 0)
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
        set(remoteEnded ? .exited(Int32(exitCode ?? 0)) : nil)
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
