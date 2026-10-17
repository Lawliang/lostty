#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct GuardServerTests {
    /// Sun paths are short (104 bytes): use /tmp, not the long temp folder.
    func socketPath() -> URL {
        URL(fileURLWithPath: "/tmp/lostty-guard-test-\(UUID().uuidString.prefix(8))/g.sock")
    }

    func send(_ line: String, to path: URL, timeout: Int = 0) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(fd >= 0)
        defer { close(fd) }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
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

    @Test func aSocketAnotherCopyAnswersIsLeftAlone() throws {
        let path = socketPath()
        let first = GuardServer(path: path) { _ in .deny(1) }
        try first.start()
        defer { first.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let second = GuardServer(path: path) { _ in .allow }
        #expect(throws: GuardServer.Failure.self) { try second.start() }
        // The first copy still answers its panes.
        let ok = #"{"v":1,"pane":"P","agent":"claude","tool":"Bash","input":"x","cwd":"/r","group":"leaving","why":"w"}"#
        #expect(try send(ok, to: path).contains(#""request":1"#))
    }

    @Test func eachBuildHasItsOwnSocket() {
        let home = URL(fileURLWithPath: "/Users/me")
        let release = GuardServer.path(bundleID: "com.lawliang.lostty", home: home)
        let debug = GuardServer.path(bundleID: "com.lawliang.lostty.debug", home: home)
        // The shipped build keeps the old shared path, so terminal sessions
        // started before per-build sockets still reach it.
        #expect(release.path == "/Users/me/.config/lostty/coord/guard.sock")
        #expect(debug.path == "/Users/me/.config/lostty/coord/guard-com.lawliang.lostty.debug.sock")
        #expect(release != debug)
        // A path too long for a socket address falls back to a short hash.
        let longHome = URL(fileURLWithPath: "/Users/" + String(repeating: "x", count: 40))
        let long = GuardServer.path(bundleID: "com.lawliang.lostty.debug", home: longHome)
        #expect(longHome.appendingPathComponent(".config/lostty/coord/guard-com.lawliang.lostty.debug.sock").path.utf8.count >= 104)
        #expect(long.path.utf8.count < 104)
        #expect(long.lastPathComponent.hasPrefix("guard-"))
        #expect(long != GuardServer.path(bundleID: "com.lawliang.lostty", home: longHome))
        #expect(long != GuardServer.path(bundleID: "com.lawliang.lostty.other", home: longHome))
        #expect(GuardRuntime.storeURL(bundleID: "a").lastPathComponent == "guard-requests-a.json")
        #expect(GuardRuntime.storeURL(bundleID: "a") != GuardRuntime.storeURL(bundleID: "b"))
    }

    func connectRaw(_ path: URL) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            _ = path.path.withCString { strncpy(raw.baseAddress!.assumingMemoryBound(to: CChar.self), $0, raw.count - 1) }
        }
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        return fd
    }

    /// Seconds until the server closes `fd` (reads EOF), polling writes of `trickle` bytes.
    func timeToClose(_ fd: Int32, trickle: Bool) -> Double {
        let start = Date()
        var buf = [UInt8](repeating: 0, count: 64)
        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        while Date().timeIntervalSince(start) < 6 {
            if trickle { var b: UInt8 = 0x20; _ = write(fd, &b, 1) }
            let n = read(fd, &buf, buf.count)
            if n == 0 { break }
        }
        return Date().timeIntervalSince(start)
    }

    @Test func aSlowStarterIsStillAnswered() throws {
        let path = socketPath()
        let server = GuardServer(path: path) { _ in .allow }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let fd = connectRaw(path)
        defer { close(fd) }
        Thread.sleep(forTimeInterval: 0.3)
        let ok = #"{"v":1,"pane":"P","agent":"claude","tool":"Bash","input":"x","cwd":"/r","group":"leaving","why":"w"}"# + "\n"
        _ = ok.withCString { write(fd, $0, strlen($0)) }
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        #expect(String(decoding: buf.prefix(max(n, 0)), as: UTF8.self).contains("allow"))
    }

    @Test func silentPeerIsClosedWithinTheDeadline() throws {
        let path = socketPath()
        let server = GuardServer(path: path) { _ in .allow }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let fd = connectRaw(path)
        defer { close(fd) }
        let t = timeToClose(fd, trickle: false)
        #expect(t >= 1.5 && t < 4, "closed after \(t)s")
    }

    @Test func trickleDoesNotExtendTheDeadline() throws {
        let path = socketPath()
        let server = GuardServer(path: path) { _ in .allow }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let fd = connectRaw(path)
        defer { close(fd) }
        let t = timeToClose(fd, trickle: true)
        #expect(t >= 1.5 && t < 4, "closed after \(t)s")
    }

    @Test func idleConnectionsDontBlockARealRequest() throws {
        let path = socketPath()
        let server = GuardServer(path: path) { _ in .allow }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let idle = (0..<20).map { _ in connectRaw(path) }
        defer { idle.forEach { close($0) } }
        let ok = #"{"v":1,"pane":"P","agent":"claude","tool":"Bash","input":"x","cwd":"/r","group":"leaving","why":"w"}"#
        let start = Date()
        let reply = try send(ok, to: path)
        #expect(reply.contains("allow"))
        #expect(Date().timeIntervalSince(start) < 1, "took \(Date().timeIntervalSince(start))s, reply \(reply)")
    }

    /// Blocks the calling thread (a pool thread, in a task) until `gate` opens.
    static func hold(started: DispatchSemaphore, until gate: DispatchSemaphore) {
        started.signal()
        gate.wait()
    }

    /// Swift's shared thread pool can be busy (a full test run; in the app,
    /// blocking work in detached tasks): replies still go out on time.
    @Test(.timeLimit(.minutes(1))) func aBusyThreadPoolDoesNotHoldReplies() throws {
        let path = socketPath()
        // Main-actor work, like the live handler.
        let server = GuardServer(path: path) { @MainActor _ in .allow }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        // Hold every pool thread until the checks are done. The test itself
        // may hold one already, so not every task may start: wait at most 2 s.
        let width = ProcessInfo.processInfo.activeProcessorCount
        let started = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        for _ in 0..<width {
            Task.detached { Self.hold(started: started, until: gate) }
        }
        defer { for _ in 0..<width { gate.signal() } }
        let waitUntil = DispatchTime.now() + 2
        var running = 0
        while running < width, started.wait(timeout: waitUntil) == .success { running += 1 }
        let connected = Date()
        let silent = connectRaw(path)
        defer { close(silent) }
        let ok = #"{"v":1,"pane":"P","agent":"claude","tool":"Bash","input":"x","cwd":"/r","group":"leaving","why":"w"}"#
        let start = Date()
        // Waiting for the pool, a reply would never come: give up at 3 s.
        let reply = try send(ok, to: path, timeout: 3)
        let took = Date().timeIntervalSince(start)
        #expect(reply.contains("allow"))
        #expect(took < 1, "took \(took)s, reply \(reply)")
        _ = timeToClose(silent, trickle: false)
        let t = Date().timeIntervalSince(connected)
        #expect(t >= 1.5 && t < 4, "closed after \(t)s")
    }
}
#endif
