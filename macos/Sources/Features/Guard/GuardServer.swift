#if os(macOS)
import Darwin
import Foundation

/// The app's end of the guard socket (spec §7.5). `lostty +guard` connects,
/// sends one `GuardCheck` line and reads one `GuardReply` line. The socket
/// can only *ask*: the handler answers from the approval book, and nothing
/// a caller sends can grant. Only your own user's processes may connect.
final class GuardServer: @unchecked Sendable {
    typealias Handler = @Sendable (GuardCheck) async -> GuardReply

    static func defaultPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".config/lostty/coord/guard.sock")
    }

    private let path: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.lawliang.lostty.guard-server")
    /// Blocking reads happen here, never on the global pool.
    private let readQueue = DispatchQueue(label: "com.lawliang.lostty.guard-reads", attributes: .concurrent)
    private let lock = NSLock()
    private var inFlight = 0
    static let maxInFlight = 32
    static let deadline: TimeInterval = 2
    private var source: DispatchSourceRead?

    init(path: URL, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    enum Failure: Error { case socket(Int32), pathTooLong }

    func start() throws {
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
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
            readQueue.async {
                let line = Self.readLine(conn, deadline: Self.deadline)
                Task.detached {
                    let reply: GuardReply
                    if let line, let check = try? JSONDecoder().decode(GuardCheck.self, from: line) {
                        reply = await handler(check)
                    } else {
                        reply = .deny(0)
                    }
                    var out = (try? JSONEncoder().encode(reply)) ?? Data()
                    out.append(0x0A)
                    out.withUnsafeBytes { _ = write(conn, $0.baseAddress, $0.count) }
                    close(conn)
                    self.release()
                }
            }
        }
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
