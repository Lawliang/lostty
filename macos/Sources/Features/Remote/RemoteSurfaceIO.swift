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
            // Called on the main thread (see `reportExit`).
            exited: { ghostty_surface_io_exited($0, $1) })
    }

    private let attacher: RemoteAttacher
    private let calls: SurfaceCalls
    private let delays: @Sendable (TimeInterval) async throws -> Void
    private let onMain: @Sendable (@escaping @Sendable () -> Void) -> Void

    // Two locks, never nested while waiting on each other:
    // - `surfaceLock` guards only `surface`. It is held across a feed (the
    //   core may block in it until its IO thread drains replies, which come
    //   back through `write`), so `write` and `resize` must never take it.
    // - `stateLock` guards everything else and is only held briefly.
    // `detach` takes `stateLock`, releases it, then takes `surfaceLock`.
    private let surfaceLock = NSLock()
    private var surface: ghostty_surface_t?

    private let stateLock = NSLock()
    private var terminal: RemoteTerminal?
    private var size = (cols: 80, rows: 24)
    private var detached = false
    private var didOpen = false
    /// The size the current attach started with.
    private var attachedSize = (cols: 80, rows: 24)
    private var task: Task<Void, Never>?
    /// Set by `restart()`: the current attach's end is a restart, not an
    /// exit or a drop.
    private var restartRequested = false
    /// The backoff wait in progress, so `restart()` can cut it short.
    private var delay: Task<Void, Error>?

    init(
        attacher: RemoteAttacher,
        surfaceCalls: SurfaceCalls = .live,
        delays: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        onMain: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
    ) {
        self.attacher = attacher
        self.calls = surfaceCalls
        self.delays = delays
        self.onMain = onMain
    }

    // MARK: Ghostty.RemoteIO

    func write(_ bytes: UnsafeRawBufferPointer) {
        let data = Data(bytes)
        // Typing while not attached (connecting, reconnecting) is dropped.
        stateLock.withLock { terminal }?.write(data)
    }

    func resize(cols: UInt16, rows: UInt16, widthPx: UInt32, heightPx: UInt32) {
        let open: RemoteTerminal? = stateLock.withLock {
            size = (Int(cols), Int(rows))
            return terminal
        }
        open?.resize(cols: Int(cols), rows: Int(rows))
    }

    func attach(to surface: ghostty_surface_t) {
        // The surface is set before the loop can feed it.
        surfaceLock.withLock { self.surface = surface }
        let start: Bool = stateLock.withLock {
            guard !detached, task == nil else { return false }
            task = Task { [self] in await run() }
            return true
        }
        // A refused attach (detached, or a second one) leaves the surface as
        // it was; only a detached one clears it.
        if !start, stateLock.withLock({ detached }) { surfaceLock.withLock { self.surface = nil } }
    }

    func detach() {
        let open: RemoteTerminal? = stateLock.withLock {
            detached = true
            task?.cancel()
            defer { terminal = nil }
            return terminal
        }
        // Waits for a feed in flight; none starts after this.
        surfaceLock.withLock { surface = nil }
        open?.close()
    }

    /// Drops the connection and attaches again at once. For the phone
    /// coming back to the foreground or changing networks, when the old
    /// connection may be dead without anyone having noticed. Does nothing
    /// before `attach(to:)` or after `detach()`.
    func restart() {
        let open: RemoteTerminal? = stateLock.withLock {
            guard !detached, task != nil else { return nil }
            restartRequested = true
            delay?.cancel()
            return terminal
        }
        open?.close()
    }

    /// Waits for the session loop to end (tests).
    func finished() async {
        await stateLock.withLock { task }?.value
    }

    // MARK: Session loop

    private func run() async {
        var policy = ReconnectPolicy()
        while !Task.isCancelled {
            let (cols, rows) = stateLock.withLock {
                didOpen = false
                attachedSize = size
                return size
            }
            let end: AttachEnd
            do {
                end = try await attacher.attach(
                    cols: cols,
                    rows: rows,
                    onOpen: { [self] terminal in opened(terminal) },
                    onOutput: { [self] data in received(data) })
            } catch let error as RemoteError {
                // Host key changed, key refused, no Secure Enclave, Touch ID
                // cancelled: say why and stop; retrying cannot help. No exit
                // is reported: that would close the pane and the message with
                // it. Closing the pane never asks (remote panes don't confirm).
                received(Data("\r\n\u{1b}[31m\(error.message)\u{1b}[0m\r\n".utf8))
                return
            } catch {
                // Could not connect (or the pane closed mid-attach): try
                // again unless the pane is gone.
                closed()
                if Task.isCancelled { return }
                if takeRestart() { policy.reset(); continue }
                guard await pause(policy.nextDelay()) else { return }
                continue
            }
            if Task.isCancelled { return }
            closed()
            if takeRestart() { policy.reset(); continue }
            switch end {
            case .exited(let code):
                reportExit(UInt32(bitPattern: code))
                return
            case .lost:
                // A connection that worked starts the backoff over.
                if stateLock.withLock({ didOpen }) { policy.reset() }
                withSurface { calls.disconnected($0) }
                guard await pause(policy.nextDelay()) else { return }
            }
        }
    }

    /// Waits `seconds` (the backoff), ending early on `restart()`. False
    /// when the pane is gone.
    private func pause(_ seconds: TimeInterval) async -> Bool {
        let wait = Task { try await delays(seconds) }
        // A restart that came in since the last check ends the wait before
        // it starts.
        let skip: Bool = stateLock.withLock {
            if restartRequested { restartRequested = false; return true }
            delay = wait
            return false
        }
        if skip {
            wait.cancel()
            return !Task.isCancelled
        }
        // Closing the pane cancels this loop; the wait must end with it.
        await withTaskCancellationHandler {
            _ = try? await wait.value
        } onCancel: {
            wait.cancel()
        }
        // A restart during the wait has done its job by ending it.
        stateLock.withLock { delay = nil; restartRequested = false }
        return !Task.isCancelled
    }

    /// Consumes a pending restart request.
    private func takeRestart() -> Bool {
        stateLock.withLock {
            defer { restartRequested = false }
            return restartRequested
        }
    }

    /// The core handles exits on the main thread, and the view frees the
    /// surface there, so the check for a still-attached surface happens on
    /// main too: `detach` (view deinit) cannot run between check and call.
    private func reportExit(_ code: UInt32) {
        onMain { [self] in withSurface { calls.exited($0, code) } }
    }

    private func opened(_ terminal: RemoteTerminal) {
        // A resize while connecting only updated `size`; tell tmux now.
        let (keep, stale): (Bool, (cols: Int, rows: Int)?) = stateLock.withLock {
            // A restart asked for while connecting drops this connection.
            guard !detached, !restartRequested else { return (false, nil) }
            self.terminal = terminal
            didOpen = true
            let differs = size != attachedSize
            return (true, differs ? size : nil)
        }
        if !keep { terminal.close() }
        if let stale { terminal.resize(cols: stale.cols, rows: stale.rows) }
    }

    private func closed() {
        stateLock.withLock { terminal = nil }
    }

    /// Received bytes go to the surface while it exists. The lock is held
    /// across the call so `detach` (before the surface is freed) waits for
    /// a feed in flight.
    private func received(_ data: Data) {
        surfaceLock.lock()
        defer { surfaceLock.unlock() }
        guard let surface else { return }
        calls.feed(surface, data)
    }

    private func withSurface(_ body: (ghostty_surface_t) -> Void) {
        surfaceLock.lock()
        defer { surfaceLock.unlock() }
        guard let surface else { return }
        body(surface)
    }
}

/// Attaches over SSH: a fresh connection per attempt, so a dropped network
/// reconnects from scratch.
@available(macOS 15, iOS 17, *)
struct SSHAttacher: RemoteAttacher {
    let host: RemoteHost
    /// The key, fetched for each attempt: the phone replaces its key (and
    /// Face ID context) after the app has been in the background.
    let key: @Sendable () async throws -> RemoteKey
    let knownHosts: KnownHosts
    let sessionID: String

    func attach(
        cols: Int,
        rows: Int,
        onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws -> AttachEnd {
        let connection = try await RemoteConnection.connect(to: host, key: try await key(), knownHosts: knownHosts)
        let end = await connection.attach(
            sessionID: sessionID, cols: cols, rows: rows, onOpen: onOpen, onOutput: onOutput)
        await connection.close()
        return end
    }
}
