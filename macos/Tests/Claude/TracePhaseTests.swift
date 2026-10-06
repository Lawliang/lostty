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

    @Test func idleWhileRacingFinishes() {
        #expect(TracePhase.racing(since: t0).applying(.idle, now: at(3)) == .finishing(since: t0, at: at(3)))
    }

    @Test func exitWhileRacingFades() {
        #expect(TracePhase.racing(since: t0).applying(.exit, now: at(3)) == .fading(since: t0, at: at(3)))
    }

    @Test func busyDuringFinishResumesWithoutJump() {
        let finishing = TracePhase.finishing(since: t0, at: at(3))
        #expect(finishing.applying(.busy, now: at(3.5)) == .racing(since: t0))
    }

    @Test func busyAfterExitIsANewSession() {
        #expect(TracePhase.fading(since: t0, at: at(3)).applying(.busy, now: at(10)) == .racing(since: at(10)))
    }

    @Test func idleAndExitWhileOffStayOff() {
        #expect(TracePhase.off.applying(.idle, now: t0) == .off)
        #expect(TracePhase.off.applying(.exit, now: t0) == .off)
    }

    @Test func exitDuringFinishLetsTheFlashComplete() {
        let finishing = TracePhase.finishing(since: t0, at: at(3))
        #expect(finishing.applying(.exit, now: at(3.2)) == finishing)
    }

    @Test func settlesAfterDurations() {
        let finishing = TracePhase.finishing(since: t0, at: at(3))
        #expect(finishing.settled(now: at(3 + TraceTiming.finishTotal - 0.01)) == finishing)
        #expect(finishing.settled(now: at(3 + TraceTiming.finishTotal + 1e-6)) == .off)
        let fading = TracePhase.fading(since: t0, at: at(3))
        #expect(fading.settled(now: at(3 + TraceTiming.exitFade + 1e-6)) == .off)
        #expect(TracePhase.racing(since: t0).settled(now: at(999)) == .racing(since: t0))
    }

    @Test func racingFrameFadesInAndWraps() throws {
        let start = try #require(TraceFrame.make(.racing(since: t0), now: t0, lapSeconds: 2, length: 0.2))
        #expect(start.head == 0)
        #expect(start.intensity == 0)
        let later = try #require(TraceFrame.make(.racing(since: t0), now: at(3), lapSeconds: 2, length: 0.2))
        #expect(abs(later.head - 0.5) < 1e-9)
        #expect(later.intensity == 1)
        #expect(later.length == 0.2)
        #expect(later.pulse == 0)
    }

    @Test func finishFrameStretchesPulsesThenFades() throws {
        let phase = TracePhase.finishing(since: t0, at: at(10))
        let stretched = try #require(TraceFrame.make(
            phase, now: at(10 + TraceTiming.closeLoop), lapSeconds: 2, length: 0.2))
        #expect(abs(stretched.length - 1) < 1e-9)
        #expect(stretched.intensity == 1)
        let midPulse = try #require(TraceFrame.make(
            phase, now: at(10 + TraceTiming.closeLoop + TraceTiming.pulse / 2), lapSeconds: 2, length: 0.2))
        #expect(midPulse.pulse > 0.99)
        let end = try #require(TraceFrame.make(phase, now: at(10 + TraceTiming.finishTotal), lapSeconds: 2, length: 0.2))
        #expect(end.intensity < 1e-6)
        // The head keeps the racing pace through the flash: no jump on resume.
        let racingHead = try #require(TraceFrame.make(.racing(since: t0), now: at(10.3), lapSeconds: 2, length: 0.2)).head
        let finishHead = try #require(TraceFrame.make(phase, now: at(10.3), lapSeconds: 2, length: 0.2)).head
        #expect(racingHead == finishHead)
    }

    @Test func fadingFrameDropsToZero() throws {
        let phase = TracePhase.fading(since: t0, at: at(4))
        #expect(try #require(TraceFrame.make(phase, now: at(4), lapSeconds: 2, length: 0.2)).intensity == 1)
        #expect(try #require(TraceFrame.make(
            phase, now: at(4 + TraceTiming.exitFade), lapSeconds: 2, length: 0.2)).intensity < 1e-6)
    }

    @Test func offHasNoFrame() {
        #expect(TraceFrame.make(.off, now: t0, lapSeconds: 2, length: 0.2) == nil)
    }

    @Test func lapSecondsScalesWithPerimeterAndSpeed() {
        #expect(TraceFrame.lapSeconds(perimeter: 1000, speed: 1) == 3)
        #expect(TraceFrame.lapSeconds(perimeter: 2000, speed: 2) == 3)
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
