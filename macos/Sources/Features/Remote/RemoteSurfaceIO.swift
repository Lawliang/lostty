#if os(macOS)
import Foundation
import GhosttyKit
import LosttyRemote

/// Attaches to one remote session; implemented over SSH by
/// `SSHAttacher` and by fakes in tests.
protocol RemoteAttacher: Sendable {
    func attach(
        cols: Int,
        rows: Int,
        onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws -> AttachEnd
}

/// Joins a remote surface to a remote tmux session: the core's writes and
/// resizes go to the session, received bytes go to the core, and a dropped
/// connection shows "reconnecting…" and attaches again with backoff. The
/// session ending closes the pane. Closing the pane closes only the channel.
final class RemoteSurfaceIO: Ghostty.RemoteIO, @unchecked Sendable {
    /// The surface calls this makes; tests replace them.
    struct SurfaceCalls: Sendable {
        var feed: @Sendable (ghostty_surface_t, Data) -> Void
        var disconnected: @Sendable (ghostty_surface_t) -> Void
        var exited: @Sendable (ghostty_surface_t, UInt32) -> Void

        static let live = SurfaceCalls(
            feed: { surface, data in
                data.withUnsafeBytes { raw in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                    ghostty_surface_io_feed(surface, base, raw.count)
                }
            },
            disconnected: { ghostty_surface_io_disconnected($0) },
            exited: { surface, code in
                DispatchQueue.main.async { ghostty_surface_io_exited(surface, code) }
            })
    }

    private let attacher: RemoteAttacher
    private let calls: SurfaceCalls
    private let delays: @Sendable (TimeInterval) async throws -> Void

    private let lock = NSLock()
    private var surface: ghostty_surface_t?
    private var terminal: RemoteTerminal?
    private var size = (cols: 80, rows: 24)
    private var detached = false
    private var task: Task<Void, Never>?

    init(
        attacher: RemoteAttacher,
        surfaceCalls: SurfaceCalls = .live,
        delays: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.attacher = attacher
        self.calls = surfaceCalls
        self.delays = delays
    }

    // MARK: Ghostty.RemoteIO

    func write(_ bytes: UnsafeRawBufferPointer) {
        let data = Data(bytes)
        // Typing while not attached (connecting, reconnecting) is dropped.
        lock.withLock { terminal }?.write(data)
    }

    func resize(cols: UInt16, rows: UInt16, widthPx: UInt32, heightPx: UInt32) {
        let open: RemoteTerminal? = lock.withLock {
            size = (Int(cols), Int(rows))
            return terminal
        }
        open?.resize(cols: Int(cols), rows: Int(rows))
    }

    func attach(to surface: ghostty_surface_t) {
        lock.withLock {
            guard !detached else { return }
            self.surface = surface
            task = Task { [self] in await run() }
        }
    }

    func detach() {
        let open: RemoteTerminal? = lock.withLock {
            detached = true
            surface = nil
            task?.cancel()
            defer { terminal = nil }
            return terminal
        }
        open?.close()
    }

    /// Waits for the session loop to end (tests).
    func finished() async {
        await lock.withLock { task }?.value
    }

    // MARK: Session loop

    private func run() async {
        var policy = ReconnectPolicy()
        while !Task.isCancelled {
            let (cols, rows) = lock.withLock { size }
            let end: AttachEnd
            do {
                end = try await attacher.attach(
                    cols: cols,
                    rows: rows,
                    onOpen: { [self] terminal in opened(terminal) },
                    onOutput: { [self] data in received(data) })
            } catch let error as RemoteError {
                // Host key changed, key refused, no Secure Enclave: say why
                // and stop; retrying cannot help.
                received(Data("\r\n\u{1b}[31m\(error.message)\u{1b}[0m\r\n".utf8))
                withSurface { calls.exited($0, 1) }
                return
            } catch {
                // Could not connect (or the pane closed mid-attach): try
                // again unless the pane is gone.
                closed()
                if Task.isCancelled { return }
                guard (try? await delays(policy.nextDelay())) != nil else { return }
                continue
            }
            if Task.isCancelled { return }
            closed()
            switch end {
            case .exited(let code):
                withSurface { calls.exited($0, UInt32(bitPattern: code)) }
                return
            case .lost:
                withSurface { calls.disconnected($0) }
                guard (try? await delays(policy.nextDelay())) != nil else { return }
            }
            policy.reset()
        }
    }

    private func opened(_ terminal: RemoteTerminal) {
        let keep: Bool = lock.withLock {
            guard !detached else { return false }
            self.terminal = terminal
            return true
        }
        if !keep { terminal.close() }
    }

    private func closed() {
        lock.withLock { terminal = nil }
    }

    /// Received bytes go to the surface while it exists. The lock is held
    /// across the call so `detach` (before the surface is freed) waits for
    /// a feed in flight.
    private func received(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard let surface else { return }
        calls.feed(surface, data)
    }

    private func withSurface(_ body: (ghostty_surface_t) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let surface else { return }
        body(surface)
    }
}

/// Attaches over SSH: a fresh connection per attempt, so a dropped network
/// reconnects from scratch.
@available(macOS 15, *)
struct SSHAttacher: RemoteAttacher {
    let host: RemoteHost
    let key: RemoteKey
    let knownHosts: KnownHosts
    let sessionID: String

    func attach(
        cols: Int,
        rows: Int,
        onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws -> AttachEnd {
        let connection = try await RemoteConnection.connect(to: host, key: key, knownHosts: knownHosts)
        let end = await connection.attach(
            sessionID: sessionID, cols: cols, rows: rows, onOpen: onOpen, onOutput: onOutput)
        await connection.close()
        return end
    }
}
#endif
