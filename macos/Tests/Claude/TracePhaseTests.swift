#if os(macOS)
import Foundation
import Testing
@testable import Lostty

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
        #expect(TracePhase.racing(since: t0, subagents: true).applying(.idle, now: at(3)) == .off)
    }

    @Test func exitWhileRacingStopsAtOnce() {
        #expect(TracePhase.racing(since: t0).applying(.exit, now: at(3)) == .off)
    }

    @Test func idleAndExitWhileOffStayOff() {
        #expect(TracePhase.off.applying(.idle, now: t0) == .off)
        #expect(TracePhase.off.applying(.exit, now: t0) == .off)
    }

    // The head keeps its journey (same start) across the hand-offs.
    @Test func agentsKeepTheStartAndMarkSubagents() {
        #expect(TracePhase.racing(since: t0).applying(.agents, now: at(4)) == .racing(since: t0, subagents: true))
        #expect(TracePhase.off.applying(.agents, now: at(4)) == .racing(since: at(4), subagents: true))
    }

    @Test func resumedAndBusyLeaveSubagents() {
        let subagents = TracePhase.racing(since: t0, subagents: true)
        #expect(subagents.applying(.resumed, now: at(9)) == .racing(since: t0))
        #expect(subagents.applying(.busy, now: at(9)) == .racing(since: t0))
        #expect(TracePhase.off.applying(.resumed, now: t0) == .off)
    }

    @Test func intensityFadesIn() {
        #expect(TraceFrame.intensity(elapsed: 0) == 0)
        #expect(abs(TraceFrame.intensity(elapsed: 0.1) - 0.5) < 1e-9)
        #expect(TraceFrame.intensity(elapsed: 3) == 1)
    }

    @Test func legIsPointSixSecondsAtNormalSpeed() {
        #expect(abs(TraceFrame.legSeconds(speed: 1) - 0.6) < 1e-9)
        #expect(abs(TraceFrame.legSeconds(speed: 2) - 0.3) < 1e-9)
    }
}
#endif
