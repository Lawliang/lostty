#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct GuardServerTests {
    /// Sun paths are short (104 bytes): use /tmp, not the long temp folder.
    func socketPath() -> URL {
        URL(fileURLWithPath: "/tmp/lostty-guard-test-\(UUID().uuidString.prefix(8))/g.sock")
    }

    func send(_ line: String, to path: URL) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(fd >= 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            _ = path.path.withCString { strncpy(raw.baseAddress!.assumingMemoryBound(to: CChar.self), $0, raw.count - 1) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(ok == 0)
        _ = (line + "\n").withCString { write(fd, $0, strlen($0)) }
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        return String(decoding: buf.prefix(max(n, 0)), as: UTF8.self)
    }

    @Test func answersOneLinePerConnection() throws {
        let path = socketPath()
        let server = GuardServer(path: path) { check in
            check.input == "git push" ? .deny(7) : .allow
        }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }

        let push = #"{"v":1,"pane":"P","agent":"claude","tool":"Bash","input":"git push","cwd":"/r","group":"leaving","why":"w"}"#
        #expect(try send(push, to: path).contains(#""request":7"#))
        let other = #"{"v":1,"pane":"P","agent":"claude","tool":"Bash","input":"x","cwd":"/r","group":"leaving","why":"w"}"#
        #expect(try send(other, to: path).contains(#""decision":"allow""#))
        #expect(try send("not json", to: path).contains(#""request":0"#))
    }

    @Test func socketIsPrivate() throws {
        let path = socketPath()
        let server = GuardServer(path: path) { _ in .allow }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let dir = try FileManager.default.attributesOfItem(atPath: path.deletingLastPathComponent().path)
        #expect((dir[.posixPermissions] as? Int) == 0o700)
        let sock = try FileManager.default.attributesOfItem(atPath: path.path)
        #expect((sock[.posixPermissions] as? Int) == 0o600)
    }

    @Test func replacesAStaleSocket() throws {
        let path = socketPath()
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path.path, contents: Data("stale".utf8))
        let server = GuardServer(path: path) { _ in .allow }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let ok = #"{"v":1,"pane":"P","agent":"claude","tool":"Bash","input":"x","cwd":"/r","group":"leaving","why":"w"}"#
        #expect(try send(ok, to: path).contains("allow"))
    }
}
#endif
