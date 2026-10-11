#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Ghostty

/// Records what the bridge does to the surface; never touches a real one.
private final class SurfaceLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _fed = Data()
    private var _events: [String] = []
    var fed: Data { lock.withLock { _fed } }
    var events: [String] { lock.withLock { _events } }
    func feed(_ d: Data) { lock.withLock { _fed.append(d) } }
    func event(_ e: String) { lock.withLock { _events.append(e) } }

    var calls: RemoteSurfaceIO.SurfaceCalls {
        .init(
            feed: { [self] _, data in feed(data) },
            disconnected: { [self] _ in event("disconnected") },
            exited: { [self] _, code in event("exited \(code)") })
    }
}

private final class FakeTerminal: RemoteTerminal, @unchecked Sendable {
    private let lock = NSLock()
    private var _written = Data()
    private var _sizes: [String] = []
    private var _closed = false
    var closed: Bool { lock.withLock { _closed } }
    var written: Data { lock.withLock { _written } }
    var sizes: [String] { lock.withLock { _sizes } }
    func write(_ data: Data) { lock.withLock { _written.append(data) } }
    func resize(cols: Int, rows: Int) { lock.withLock { _sizes.append("\(cols)x\(rows)") } }
    func close() { lock.withLock { _closed = true } }
}

/// Plays a script of attach results; each attach opens a FakeTerminal,
/// sends `output`, then ends with the next result.
private final class ScriptedAttacher: RemoteAttacher, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<AttachEnd, Error>]
    private var _terminals: [FakeTerminal] = []
    private var _sizes: [String] = []
    var terminals: [FakeTerminal] { lock.withLock { _terminals } }
    var sizes: [String] { lock.withLock { _sizes } }
    let output: Data

    init(_ results: [Result<AttachEnd, Error>], output: Data = Data("hi".utf8)) {
        self.results = results
        self.output = output
    }

    func attach(cols: Int, rows: Int,
                onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
                onOutput: @escaping @Sendable (Data) -> Void) async throws -> AttachEnd {
        let next: Result<AttachEnd, Error> = lock.withLock {
            _sizes.append("\(cols)x\(rows)")
            return results.isEmpty ? .success(.exited(0)) : results.removeFirst()
        }
        let terminal = FakeTerminal()
        lock.withLock { _terminals.append(terminal) }
        onOpen(terminal)
        onOutput(output)
        return try next.get()
    }
}

/// Opens a terminal and stays attached until cancelled (the pane closing).
private final class HoldingAttacher: RemoteAttacher, @unchecked Sendable {
    private let lock = NSLock()
    private var _terminal: FakeTerminal?
    var terminal: FakeTerminal? { lock.withLock { _terminal } }

    func attach(cols: Int, rows: Int,
                onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
                onOutput: @escaping @Sendable (Data) -> Void) async throws -> AttachEnd {
        let terminal = FakeTerminal()
        lock.withLock { _terminal = terminal }
        onOpen(terminal)
        try await Task.sleep(for: .seconds(60))
        return .exited(0)
    }
}

private let fakeSurface = UnsafeMutableRawPointer(bitPattern: 0x1)!

struct RemoteSurfaceIOTests {
    @Test func attachesAtTheSizeTheCoreReportedAndFeedsOutput() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.resize(cols: 100, rows: 30, widthPx: 1000, heightPx: 600)
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes == ["100x30"])
        #expect(log.fed == Data("hi".utf8))
        #expect(log.events == ["exited 0"])
    }

    @Test func aLostConnectionShowsReconnectingAndAttachesAgain() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.lost), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.resize(cols: 80, rows: 24, widthPx: 0, heightPx: 0)
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes == ["80x24", "80x24"])
        #expect(log.events == ["disconnected", "exited 0"])
    }

    @Test func aFailedConnectRetriesUntilItAttaches() async {
        struct Down: Error {}
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.failure(Down()), .failure(Down()), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes.count == 3)
        #expect(log.events.last == "exited 0")
    }

    @Test func aHostKeyChangeStopsWithAMessageInsteadOfRetrying() async {
        let log = SurfaceLog()
        let changed = RemoteError.hostKeyChanged(host: "localhost", pinned: "A", offered: "B")
        let attacher = ScriptedAttacher([.failure(changed), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes.count == 1)
        #expect(String(decoding: log.fed, as: UTF8.self).contains("host key"))
        #expect(log.events == ["exited 1"])
    }

    @Test func typingGoesToTheOpenTerminalAndResizesFollow() async throws {
        let log = SurfaceLog()
        let attacher = HoldingAttacher()
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.attach(to: fakeSurface)
        var terminal: FakeTerminal?
        for _ in 0..<50 where terminal == nil {
            try await Task.sleep(for: .milliseconds(20))
            terminal = attacher.terminal
        }
        let open = try #require(terminal)
        Data("ls\r".utf8).withUnsafeBytes { io.write($0) }
        io.resize(cols: 90, rows: 20, widthPx: 0, heightPx: 0)
        io.detach()
        await io.finished()
        #expect(open.written == Data("ls\r".utf8))
        #expect(open.sizes == ["90x20"])
        #expect(open.closed)
        #expect(log.events.isEmpty, "closing the pane is not an exit or a disconnect")
    }

    @Test func afterDetachNothingReachesTheSurface() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.lost), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.detach()
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(log.fed.isEmpty)
        #expect(log.events.isEmpty)
    }
}
#endif
