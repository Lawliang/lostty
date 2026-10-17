#if os(macOS)
import CryptoKit
import Darwin
import Foundation

/// The app's end of the guard socket (spec §7.5). `lostty +guard` connects,
/// sends one `GuardCheck` line and reads one `GuardReply` line. The socket
/// can only *ask*: the handler answers from the approval book, and nothing
/// a caller sends can grant. Only your own user's processes may connect.
final class GuardServer: @unchecked Sendable {
    /// Main-actor work, so a reply never waits for a free thread in Swift's
    /// shared pool (busy with blocking work in detached tasks, say).
    typealias Handler = @MainActor @Sendable (GuardCheck) async -> GuardReply

    /// Set in each pane so `+guard` asks this app, not another build's.
    static let envKey = "LOSTTY_GUARD_SOCKET"

    /// The shipped build's bundle id. It keeps the shared path older
    /// builds used, so terminal sessions started before per-build sockets
    /// (which never got LOSTTY_GUARD_SOCKET) still reach it.
    static let releaseBundleID = "com.lawliang.lostty"

    /// One socket per app build (bundle id), so a Debug and a Release
    /// Lostty each answer their own panes; the Release build uses the
    /// legacy `guard.sock`. A path too long for a socket address (104
    /// bytes with its NUL) uses a short hash of the id.
    static func path(bundleID: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let dir = home.appendingPathComponent(".config/lostty/coord")
        if bundleID == releaseBundleID { return dir.appendingPathComponent("guard.sock") }
        let named = dir.appendingPathComponent("guard-\(bundleID).sock")
        if named.path.utf8.count < maxPathBytes { return named }
        let hex = SHA256.hash(data: Data(bundleID.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("guard-\(hex).sock")
    }

    static var appPath: URL { path(bundleID: Bundle.main.bundleIdentifier ?? "lostty") }

    private static let maxPathBytes = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

    private let path: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.lawliang.lostty.guard-server")
    private let lock = NSLock()
    private var inFlight = 0
    static let maxInFlight = 32
    static let deadline: TimeInterval = 2
    private var source: DispatchSourceRead?

    init(path: URL, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    enum Failure: Error { case socket(Int32), pathTooLong, inUse }

    func start() throws {
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        // Another running copy of this build owns a socket that answers:
        // leave it alone rather than take its panes' requests.
        if Self.answers(path) { throw Failure.inUse }
        unlink(path.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(errno) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw Failure.pathTooLong
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            bytes.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let e = errno
            close(fd)
            throw Failure.socket(e)
        }
        chmod(path.path, 0o600)
        guard listen(fd, SOMAXCONN) == 0 else {
            let e = errno
            close(fd)
            throw Failure.socket(e)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAll(fd) }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    /// Something accepts connections at `path`.
    static func answers(_ path: URL) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            bytes.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        return rc == 0
    }

    func stop() {
        source?.cancel()
        source = nil
        unlink(path.path)
    }

    /// Drain every pending connection; the listen fd is non-blocking.
    private func acceptAll(_ listenFD: Int32) {
        while true {
            let conn = accept(listenFD, nil, nil)
            if conn < 0 { return }  // EAGAIN/EWOULDBLOCK (or a reset peer): nothing more now
            _ = fcntl(conn, F_SETFD, FD_CLOEXEC)
            // Darwin hands back the listener's O_NONBLOCK; reads must block so SO_RCVTIMEO applies.
            _ = fcntl(conn, F_SETFL, fcntl(conn, F_GETFL) & ~O_NONBLOCK)
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(conn, &uid, &gid) == 0, uid == getuid(), reserve() else {
                close(conn)
                continue
            }
            var one: Int32 = 1
            setsockopt(conn, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let handler = self.handler
            // Blocking reads and writes happen here, never on the global
            // pool (or the main thread). Each connection gets a serial queue
            // of its own: those always get a thread, where one shared
            // concurrent queue waited for threads behind a busy Swift pool.
            let connQueue = DispatchQueue(label: "com.lawliang.lostty.guard-conn")
            connQueue.async {
                // A missing or garbled line never needs the handler.
                guard let line = Self.readLine(conn, deadline: Self.deadline),
                      let check = try? JSONDecoder().decode(GuardCheck.self, from: line) else {
                    self.finish(conn, .deny(0))
                    return
                }
                // An isolated task starts on its actor's executor (the main
                // thread), not the pool; aBusyThreadPoolDoesNotHoldReplies pins it.
                Task { @MainActor in
                    let reply = await handler(check)
                    connQueue.async { self.finish(conn, reply) }
                }
            }
        }
    }

    /// Writes `reply` as one line and closes `conn`; runs on its queue.
    private func finish(_ conn: Int32, _ reply: GuardReply) {
        var out = (try? JSONEncoder().encode(reply)) ?? Data()
        out.append(0x0A)
        out.withUnsafeBytes { _ = write(conn, $0.baseAddress, $0.count) }
        close(conn)
        release()
    }

    private func reserve() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard inFlight < Self.maxInFlight else { return false }
        inFlight += 1
        return true
    }

    private func release() {
        lock.lock()
        inFlight -= 1
        lock.unlock()
    }

    /// Up to the first newline, at most 1 MB, within `deadline` seconds in
    /// total (monotonic); nil on timeout or error.
    private static func readLine(_ fd: Int32, deadline: TimeInterval) -> Data? {
        let end = DispatchTime.now().uptimeNanoseconds + UInt64(deadline * 1e9)
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while data.count < 1 << 20 {
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= end { return nil }
            let left = end - now
            var tv = timeval(tv_sec: Int(left / 1_000_000_000), tv_usec: Int32((left % 1_000_000_000) / 1000))
            if tv.tv_sec == 0 && tv.tv_usec == 0 { tv.tv_usec = 1 }
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let n = read(fd, &buf, buf.count)
            if n <= 0 { return nil }
            data.append(contentsOf: buf.prefix(n))
            if let nl = data.firstIndex(of: 0x0A) { return data.prefix(upTo: nl) }
        }
        return nil
    }
}
#endif
