import Foundation
import Testing
@testable import Ghostty

struct PairingProgressTests {
    @Test func eachPhaseHasOneCurrentStepAndEarlierStepsDone() {
        #expect(PairingStep.allCases.map { PairingProgress.notStarted.state(of: $0) } == [.pending, .pending, .pending])
        #expect(PairingStep.allCases.map { PairingProgress.finding.state(of: $0) } == [.current, .pending, .pending])
        #expect(PairingStep.allCases.map { PairingProgress.waitingForAllow.state(of: $0) } == [.done, .current, .pending])
        #expect(PairingStep.allCases.map { PairingProgress.testing.state(of: $0) } == [.done, .done, .current])
        #expect(PairingStep.allCases.map { PairingProgress.finished.state(of: $0) } == [.done, .done, .done])
    }

    @Test func stepTitles() {
        #expect(PairingStep.allCases.map(\.title) == ["Find your Mac", "Allow on Mac", "Connect"])
    }
}

struct PairingCountdownTests {
    let expires = Date(timeIntervalSince1970: 1_000)

    @Test func fullAtTheStartEmptyAtTheEnd() {
        #expect(PairingCountdown.fraction(now: expires.addingTimeInterval(-120), expires: expires) == 1)
        #expect(PairingCountdown.fraction(now: expires.addingTimeInterval(-60), expires: expires) == 0.5)
        #expect(PairingCountdown.fraction(now: expires, expires: expires) == 0)
    }

    @Test func neverOutsideZeroToOne() {
        #expect(PairingCountdown.fraction(now: expires.addingTimeInterval(-500), expires: expires) == 1)
        #expect(PairingCountdown.fraction(now: expires.addingTimeInterval(30), expires: expires) == 0)
        #expect(PairingCountdown.fraction(now: expires, expires: expires, total: 0) == 0)
    }
}

struct StepPulseTests {
    @Test func pulsesOverOnePointTwoSeconds() {
        let values = stride(from: 0.0, through: 1.2, by: 0.05).map { StepPulse.opacity(at: $0, reduceMotion: false) }
        #expect(values.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(values.contains { $0 > 0.95 })
        #expect(values.contains { $0 < 0.05 })
    }

    @Test func reduceMotionIsSteady() {
        for time in [0.0, 0.3, 0.9] {
            #expect(StepPulse.opacity(at: time, reduceMotion: true) == 1)
        }
    }
}
