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
        // A failed connect never opens a channel or produces output.
        let end = try next.get()
        let terminal = FakeTerminal()
        lock.withLock { _terminals.append(terminal) }
        onOpen(terminal)
        onOutput(output)
        return end
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

/// Opens a terminal, waits until released, then delivers output and ends.
private final class GatedAttacher: RemoteAttacher, @unchecked Sendable {
    private let lock = NSLock()
    private var _open = false
    private var _released = false
    var isOpen: Bool { lock.withLock { _open } }
    func release() { lock.withLock { _released = true } }

    func attach(cols: Int, rows: Int,
                onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
                onOutput: @escaping @Sendable (Data) -> Void) async throws -> AttachEnd {
        onOpen(FakeTerminal())
        lock.withLock { _open = true }
        while !lock.withLock({ _released }) { try? await Task.sleep(for: .milliseconds(5)) }
        onOutput(Data("late".utf8))
        return .lost
    }
}

/// Runs `beforeOpen` (a resize from the core) after the attach started at
/// the old size and before the terminal opens.
private final class ResizingAttacher: RemoteAttacher, @unchecked Sendable {
    private let lock = NSLock()
    private var _sizes: [String] = []
    private var _terminal: FakeTerminal?
    var sizes: [String] { lock.withLock { _sizes } }
    var terminal: FakeTerminal? { lock.withLock { _terminal } }
    nonisolated(unsafe) var io: RemoteSurfaceIO?
    let beforeOpen: @Sendable (RemoteSurfaceIO) -> Void

    init(beforeOpen: @escaping @Sendable (RemoteSurfaceIO) -> Void) { self.beforeOpen = beforeOpen }

    func attach(cols: Int, rows: Int,
                onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
                onOutput: @escaping @Sendable (Data) -> Void) async throws -> AttachEnd {
        lock.withLock { _sizes.append("\(cols)x\(rows)") }
        if let io { beforeOpen(io) }
        let terminal = FakeTerminal()
        lock.withLock { _terminal = terminal }
        onOpen(terminal)
        return .exited(0)
    }
}

private final class DelayLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [TimeInterval] = []
    var values: [TimeInterval] { lock.withLock { _values } }
    func add(_ v: TimeInterval) { lock.withLock { _values.append(v) } }
}

/// Each attach opens a terminal and stays attached until that terminal is
/// closed, then returns `.exited(0)` — as a real channel does on a local
/// close. Records how many attaches ran.
private final class CloseEndsAttacher: RemoteAttacher, @unchecked Sendable {
    private let lock = NSLock()
    private var _attaches = 0
    var attaches: Int { lock.withLock { _attaches } }
    /// Runs on each attach just before the terminal opens (a restart that
    /// arrives while connecting).
    var beforeOpen: (@Sendable (Int) -> Void)?

    final class Terminal: RemoteTerminal, @unchecked Sendable {
        let onClose: @Sendable () -> Void
        init(onClose: @escaping @Sendable () -> Void) { self.onClose = onClose }
        func write(_ data: Data) {}
        func resize(cols: Int, rows: Int) {}
        func close() { onClose() }
    }

    func attach(cols: Int, rows: Int,
                onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
                onOutput: @escaping @Sendable (Data) -> Void) async throws -> AttachEnd {
        let n = lock.withLock { _attaches += 1; return _attaches }
        beforeOpen?(n)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let once = OnceFlag()
            onOpen(Terminal { if once.claim() { done.resume() } })
        }
        return .exited(0)
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool { lock.withLock { defer { used = true }; return !used } }
}

private final class StatusLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [RemoteLinkStatus] = []
    var values: [RemoteLinkStatus] { lock.withLock { _values } }
    func add(_ s: RemoteLinkStatus) { lock.withLock { _values.append(s) } }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSince1970: 1_000)
    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now = _now.addingTimeInterval(seconds) } }
}

private func waitUntil(_ condition: @escaping () -> Bool) async throws {
    for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
}

private let fakeSurface = UnsafeMutableRawPointer(bitPattern: 0x1)!

struct RemoteSurfaceIOTests {
    @Test func statusFollowsTheConnection() async {
        struct Down: Error {}
        let log = SurfaceLog()
        let statuses = StatusLog()
        var calls = log.calls
        calls.status = { statuses.add($0) }
        let attacher = ScriptedAttacher([.failure(Down()), .success(.lost), .success(.exited(3))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(statuses.values == [.lost, .attached, .lost, .attached, .exited(3)])
        #expect(log.events == ["disconnected", "exited 3"])
    }

    @Test func aStopWithAMessageSaysStopped() async {
        let statuses = StatusLog()
        var calls = SurfaceLog().calls
        calls.status = { statuses.add($0) }
        let attacher = ScriptedAttacher([.failure(RemoteError.hostKeyChanged(host: "h", pinned: "A", offered: "B"))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(statuses.values == [.stopped])
    }

    @Test func thePhoneShowsNoLineAndKeepsThePaneOnExit() async {
        let log = SurfaceLog()
        let statuses = StatusLog()
        var calls = RemoteSurfaceIO.SurfaceCalls.overlaid(status: { statuses.add($0) })
        calls.feed = log.calls.feed
        let attacher = ScriptedAttacher([.success(.lost), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(log.events.isEmpty, "no disconnected line, no exit to the core")
        #expect(log.fed == Data("hihi".utf8))
        #expect(statuses.values == [.attached, .lost, .attached, .exited(0)])
    }

    @Test func typingCountsAsRecentForThreeSeconds() async throws {
        let clock = TestClock()
        let statuses = StatusLog()
        var calls = SurfaceLog().calls
        calls.status = { statuses.add($0) }
        let attacher = HoldingAttacher()
        let io = RemoteSurfaceIO(
            attacher: attacher, surfaceCalls: calls, delays: { _ in }, onMain: { $0() },
            now: { clock.now })
        Data("x".utf8).withUnsafeBytes { io.write($0) }
        #expect(!io.wroteRecently(within: 3), "nothing was attached to send it to")
        io.attach(to: fakeSurface)
        // `.attached` is reported after the IO holds the terminal.
        try await waitUntil { statuses.values.contains(.attached) }
        Data("exit\r".utf8).withUnsafeBytes { io.write($0) }
        clock.advance(2)
        #expect(io.wroteRecently(within: 3))
        clock.advance(2)
        #expect(!io.wroteRecently(within: 3))
        io.detach()
        await io.finished()
    }

    @Test func noStatusAfterThePaneCloses() async throws {
        let statuses = StatusLog()
        var calls = SurfaceLog().calls
        calls.status = { statuses.add($0) }
        let attacher = GatedAttacher()
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        try await waitUntil { attacher.isOpen }
        io.detach()
        attacher.release()
        await io.finished()
        #expect(statuses.values == [.attached])
    }

    @Test func attachesAtTheSizeTheCoreReportedAndFeedsOutput() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
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
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
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
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes.count == 3)
        #expect(log.events.last == "exited 0")
    }

    @Test func aHostKeyChangeStopsWithAMessageInsteadOfRetrying() async {
        let log = SurfaceLog()
        let changed = RemoteError.hostKeyChanged(host: "localhost", pinned: "A", offered: "B")
        let attacher = ScriptedAttacher([.failure(changed), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes.count == 1)
        #expect(String(decoding: log.fed, as: UTF8.self).contains("host key"))
        // The pane stays open showing why; it is not closed by an exit.
        #expect(log.events.isEmpty)
    }

    @Test func aSecondAttachIsIgnored() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.exited(0)), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        await io.finished()
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes.count == 1)
    }

    @Test func aResizeDuringConnectReachesTheTerminalWhenItOpens() async {
        let log = SurfaceLog()
        let attacher = ResizingAttacher { io in io.resize(cols: 120, rows: 40, widthPx: 0, heightPx: 0) }
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        attacher.io = io
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes == ["80x24"])
        #expect(attacher.terminal?.sizes == ["120x40"])
    }

    @Test func typingGoesToTheOpenTerminalAndResizesFollow() async throws {
        let log = SurfaceLog()
        let attacher = HoldingAttacher()
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
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
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        io.detach()
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(log.fed.isEmpty)
        #expect(log.events.isEmpty)
    }

    @Test func detachingMidAttachSilencesLateOutputAndTheEnd() async throws {
        let log = SurfaceLog()
        let attacher = GatedAttacher()
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        for _ in 0..<100 where !attacher.isOpen { try await Task.sleep(for: .milliseconds(10)) }
        #expect(attacher.isOpen)
        io.detach()
        attacher.release()
        await io.finished()
        #expect(log.fed.isEmpty)
        #expect(log.events.isEmpty)
    }

    @Test func aDropAfterAGoodSessionRetriesQuicklyEvenAfterEarlierFailures() async {
        struct Down: Error {}
        let log = SurfaceLog()
        let waits = DelayLog()
        let attacher = ScriptedAttacher([.failure(Down()), .failure(Down()), .success(.lost), .success(.exited(0))])
        let io = RemoteSurfaceIO(
            attacher: attacher, surfaceCalls: log.calls,
            delays: { waits.add($0) }, onMain: { $0() })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(waits.values == [0.5, 1, 0.5])
    }

    @Test func restartWhileAttachedReattachesWithoutClosingThePane() async throws {
        let log = SurfaceLog()
        let attacher = CloseEndsAttacher()
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        try await waitUntil { attacher.attaches == 1 }
        io.restart()
        try await waitUntil { attacher.attaches == 2 }
        #expect(attacher.attaches == 2)
        #expect(log.events.isEmpty, "a restart is neither an exit nor a disconnect")
        io.detach()
        await io.finished()
    }

    @Test func restartDuringBackoffAttachesNow() async throws {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.lost), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in
            try await Task.sleep(for: .seconds(60))
        }, onMain: { $0() })
        io.attach(to: fakeSurface)
        try await waitUntil { log.events == ["disconnected"] }
        io.restart()
        await io.finished()
        #expect(attacher.sizes.count == 2)
        #expect(log.events == ["disconnected", "exited 0"])
    }

    @Test func restartWhileConnectingDropsThatConnectionAndReattaches() async throws {
        let log = SurfaceLog()
        let attacher = CloseEndsAttacher()
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        attacher.beforeOpen = { n in if n == 1 { io.restart() } }
        io.attach(to: fakeSurface)
        try await waitUntil { attacher.attaches == 2 }
        #expect(attacher.attaches == 2)
        #expect(log.events.isEmpty, "a restart is neither an exit nor a disconnect")
        io.detach()
        await io.finished()
    }

    @Test func restartBeforeAttachIsIgnored() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        io.restart()
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(log.events == ["exited 0"])
    }

    @Test func restartAfterDetachDoesNothing() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in }, onMain: { $0() })
        io.detach()
        io.restart()
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes.isEmpty)
    }
}
#endif
