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
    private var listenFD: Int32 = -1
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
        guard listen(fd, 16) == 0 else {
            let e = errno
            close(fd)
            throw Failure.socket(e)
        }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        listenFD = -1
        unlink(path.path)
    }

    private func acceptOne() {
        let conn = accept(listenFD, nil, nil)
        guard conn >= 0 else { return }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(conn, &uid, &gid) == 0, uid == getuid() else {
            close(conn)
            return
        }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(conn, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(conn, SOL_SOCKET, SO_NOSIGPIPE, [Int32(1)], socklen_t(MemoryLayout<Int32>.size))
        let handler = self.handler
        // Read off the accept queue so a slow peer can't stall other callers.
        DispatchQueue.global().async {
            let line = Self.readLine(conn)
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
            }
        }
    }

    /// Up to the first newline, at most 1 MB; nil on timeout or error.
    private static func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while data.count < 1 << 20 {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf.prefix(n))
            if let nl = data.firstIndex(of: 0x0A) { return data.prefix(upTo: nl) }
        }
        return data.isEmpty ? nil : data
    }
}
#endif
