#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct TracePhaseTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func busyStartsRacing() {
        #expect(TracePhase.off.applying(.busy, now: t0) == .racing(since: t0))
    }

    @Test func repeatedBusyKeepsOriginalStart() {
        #expect(TracePhase.racing(since: t0).applying(.busy, now: at(5)) == .racing(since: t0))
    }

    @Test func idleWhileRacingStopsAtOnce() {
        #expect(TracePhase.racing(since: t0).applying(.idle, now: at(3)) == .off)
    }

    @Test func exitWhileRacingStopsAtOnce() {
        #expect(TracePhase.racing(since: t0).applying(.exit, now: at(3)) == .off)
    }

    @Test func idleAndExitWhileOffStayOff() {
        #expect(TracePhase.off.applying(.idle, now: t0) == .off)
        #expect(TracePhase.off.applying(.exit, now: t0) == .off)
    }

    @Test func racingFrameFadesInAndWraps() throws {
        let start = try #require(TraceFrame.make(.racing(since: t0), now: t0, lapSeconds: 2, length: 0.2))
        #expect(start.head == 0)
        #expect(start.intensity == 0)
        let later = try #require(TraceFrame.make(.racing(since: t0), now: at(3), lapSeconds: 2, length: 0.2))
        #expect(abs(later.head - 0.5) < 1e-9)
        #expect(later.intensity == 1)
        #expect(later.length == 0.2)
    }

    @Test func offHasNoFrame() {
        #expect(TraceFrame.make(.off, now: t0, lapSeconds: 2, length: 0.2) == nil)
    }

    @Test func lapSecondsScalesWithPerimeterAndSpeed() {
        // ~2500pt/s: a typical 3200pt pane edge laps in about 1.3s.
        #expect(TraceFrame.lapSeconds(perimeter: 2500, speed: 1) == 1)
        #expect(TraceFrame.lapSeconds(perimeter: 5000, speed: 2) == 1)
        #expect(abs(TraceFrame.lapSeconds(perimeter: 3200, speed: 1) - 1.28) < 1e-9)
    }

    @Test func lapSecondsNeverZero() {
        #expect(TraceFrame.lapSeconds(perimeter: 0, speed: 1) > 0)
        #expect(TraceFrame.lapSeconds(perimeter: 3, speed: 4) > 0)
        let frame = TraceFrame.make(
            .racing(since: t0), now: at(1),
            lapSeconds: TraceFrame.lapSeconds(perimeter: 0, speed: 1), length: 0.2)
        #expect(frame?.head.isFinite == true)
    }
}
#endif
