#if os(macOS)
import Foundation
import Testing
@testable import Lostty

/// The cases where sleep's `/exit` hit a terminal still in use: Claude had
/// asked the owner something, another agent had just woken it, or the Mac
/// itself had been asleep.
struct SleepSignalsTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func idle(minutes: Double) -> SleepCandidate {
        SleepCandidate(agent: .claude, idleSince: now.addingTimeInterval(-minutes * 60))
    }

    @Test func aReplyAsksTheOwnerWhenItsLastLineIsAQuestion() {
        #expect(SleepSignals.asksOwner("Installed.\nWant me to merge it into main?"))
        #expect(SleepSignals.asksOwner("Which one do you want?\n\n"))
        #expect(SleepSignals.asksOwner("Next: **should I install it?**"))
        #expect(!SleepSignals.asksOwner("Why did it fail? The path was wrong.\nFixed and pushed."))
        #expect(!SleepSignals.asksOwner(""))
    }

    @Test func theLastReplyIsClaudesOwnLastText() {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"First reply."}]}}"#,
            #"{"type":"user","message":{"content":"ok"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Shall I go on?"},{"type":"tool_use","name":"Bash"}]}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"A subagent's words."}]}}"#,
            #"{"type":"system","subtype":"away_summary","content":"mentions \"assistant\""}"#,
        ]
        #expect(SleepSignals.lastReply(in: lines.joined(separator: "\n")) == "Shall I go on?")
        #expect(SleepSignals.lastReply(in: "") == nil)
    }

    @Test func aCardThatAsksTheOwnerWaitsTwoHoursForTheAnswer() {
        var card = idle(minutes: 45)
        card.asksOwner = true
        #expect(!card.qualifies(now: now, minutes: 20))
        card.idleSince = now.addingTimeInterval(-121 * 60)
        #expect(card.qualifies(now: now, minutes: 20))
        // A longer setting still holds.
        #expect(!card.qualifies(now: now, minutes: 180))
    }

    @Test func aCardAnotherAgentWokeStaysUpForAnHour() {
        var card = idle(minutes: 45)
        card.wokenByWork = now.addingTimeInterval(-30 * 60)
        #expect(!card.qualifies(now: now, minutes: 20))
        card.wokenByWork = now.addingTimeInterval(-61 * 60)
        #expect(card.qualifies(now: now, minutes: 20))
    }

    @Test func timeTheMacSleptIsNotIdleTime() {
        var card = idle(minutes: 8 * 60)
        card.macWokeAt = now.addingTimeInterval(-5 * 60)
        #expect(!card.qualifies(now: now, minutes: 20))
        card.macWokeAt = now.addingTimeInterval(-25 * 60)
        #expect(card.qualifies(now: now, minutes: 20))
    }
}
#endif
