#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct ContextHandoffCoordinatorTests {
    final class World {
        var enabled = true
        var setting = 300_000
        var replies: [String: String] = [:]
        var typed: [(UUID, [ContextHandoffKey])] = []
        var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
        var notified: [String] = []
        var changing: [UUID] = []
        var model: String? = "Opus"
        /// Hold replies back, as the live reader does (it reads off the main actor).
        var deferReplies = false
        var heldReplies: [@MainActor () -> Void] = []
    }

    let world = World()
    let pane = UUID()
    let store = ContextHandoffStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("hc-\(UUID())"))

    func make() -> ContextHandoffCoordinator {
        let world = self.world
        return ContextHandoffCoordinator(deps: .init(
            enabled: { world.enabled },
            setting: { world.setting },
            store: store,
            readReply: { path, done in
                if world.deferReplies {
                    world.heldReplies.append { done(world.replies[path]) }
                } else {
                    done(world.replies[path])
                }
            },
            type: { pane, keys in world.typed.append((pane, keys)) },
            project: { _ in "proj" },
            model: { _ in world.model },
            notify: { world.notified.append($0) },
            conversationChanging: { world.changing.append($0) },
            schedule: { delay, work in world.pending.append((delay, work)) }))
    }

    func runPending() {
        let work = world.pending
        world.pending = []
        for item in work { item.work() }
    }

    var sayFile: URL { store.panes.appendingPathComponent("\(pane.uuidString).say") }
    var startFile: URL { store.panes.appendingPathComponent("\(pane.uuidString).start") }

    let handoff = """
    Done.
    <lostty-handoff>
    ## Where we are
    Quit item committed.
    ## Active workflow
    none
    ## Next
    continue
    </lostty-handoff>
    """

    @Test func passingTheLimitArmsAndQueuesTheDirective() throws {
        let c = make()
        c.contextChanged(pane, used: 299_000, size: 1_000_000)
        #expect(!c.isArmed(pane))
        c.contextChanged(pane, used: 301_000, size: 1_000_000)
        #expect(c.isArmed(pane))
        #expect(try String(contentsOf: sayFile, encoding: .utf8).contains("301k"))
        #expect(c.line(pane) == "Will hand off at the next clean break (301k of 300k).")
    }

    @Test func remindersEach25kAndOnceAtTheCeiling() throws {
        let c = make()
        c.contextChanged(pane, used: 301_000, size: 1_000_000)
        try FileManager.default.removeItem(at: sayFile)  // the hook took it
        c.contextChanged(pane, used: 320_000, size: 1_000_000)
        #expect(!FileManager.default.fileExists(atPath: sayFile.path))
        c.contextChanged(pane, used: 326_000, size: 1_000_000)
        #expect(FileManager.default.fileExists(atPath: sayFile.path))
        try FileManager.default.removeItem(at: sayFile)
        c.contextChanged(pane, used: 400_000, size: 1_000_000)
        #expect(try String(contentsOf: sayFile, encoding: .utf8).contains("end of this turn"))
        #expect(c.panes[pane]?.level == .ceiling)
    }

    @Test func settingOffNeverArms() {
        world.enabled = false
        let c = make()
        c.contextChanged(pane, used: 500_000, size: 1_000_000)
        #expect(!c.isArmed(pane))
    }

    @Test func theFullHandoff() throws {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        #expect(c.panes[pane]?.phase == .pending)
        #expect(world.typed.isEmpty)
        runPending()  // grace
        #expect(world.typed.count == 1)
        #expect(world.typed[0].1 == [.text("/clear"), .enter])
        #expect(c.panes[pane]?.phase == .clearing)
        #expect(try String(contentsOf: startFile, encoding: .utf8).contains("Quit item committed."))
        c.signal(pane, .fresh)
        #expect(world.changing == [pane])
        world.pending.removeAll { $0.delay == ContextHandoffCoordinator.freshTimeout }
        runPending()  // continue delay
        #expect(world.typed.last?.1 == [.text("Continue from the handoff."), .enter])
        #expect(c.panes[pane] == nil)
        #expect(c.line(pane) == "Fresh window: handed off at 312k after 'Quit item committed.'")
        #expect(store.loadStates().isEmpty)
        let saved = try FileManager.default.contentsOfDirectory(atPath: store.handoffs.appendingPathComponent("proj").path)
        #expect(saved.count == 1)
    }

    @Test func theHandoffFileIsTakenOverTheReply() throws {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        try FileManager.default.createDirectory(at: store.panes, withIntermediateDirectories: true)
        try "## Where we are\nFrom the file.\n## Active workflow\nnone\n## Next\ncontinue\n"
            .write(to: store.handoffFile(pane), atomically: true, encoding: .utf8)
        c.signal(pane, .stopped(transcript: "/t1"))
        #expect(c.panes[pane]?.phase == .pending)
        #expect(c.countdowns[pane]?.summary == "From the file.")
        #expect(!FileManager.default.fileExists(atPath: store.handoffFile(pane).path))
        runPending()
        #expect(world.typed.first?.1 == [.text("/clear"), .enter])
        #expect(c.countdowns[pane] == nil)
    }

    @Test func theCountdownRunsFiveSecondsBeforeTheClear() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        #expect(world.pending.last?.delay == 5)
        let countdown = c.countdowns[pane]
        #expect(countdown?.seconds == 5)
        #expect(countdown?.summary == "Quit item committed.")
    }

    @Test func skipKeepsTheConversationAndAsksAgainAtTheNextBreak() throws {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.skip(pane)
        #expect(c.countdowns[pane] == nil)
        runPending()
        #expect(world.typed.isEmpty)
        #expect(c.panes[pane]?.phase == .armed)
        #expect(try String(contentsOf: sayFile, encoding: .utf8).contains("next clean break"))
        // The next clean break hands off again.
        world.replies["/t2"] = handoff
        c.signal(pane, .stopped(transcript: "/t2"))
        #expect(c.panes[pane]?.phase == .pending)
    }

    @Test func theHandoffButtonCountsASkippedHandoffDownAgain() throws {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.skip(pane)
        runPending()
        #expect(c.canResume(pane))
        c.resume(pane)
        #expect(c.panes[pane]?.phase == .pending)
        #expect(c.countdowns[pane]?.summary == "Quit item committed.")
        #expect(!c.canResume(pane))
        runPending()  // grace
        #expect(world.typed.first?.1 == [.text("/clear"), .enter])
        #expect(try String(contentsOf: startFile, encoding: .utf8).contains("Quit item committed."))
    }

    @Test func aSkippedHandoffGoesStaleOnceTheConversationMovesOn() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.skip(pane)
        c.signal(pane, .prompted)
        #expect(!c.canResume(pane))
        c.resume(pane)
        #expect(c.panes[pane]?.phase == .armed)
        #expect(c.countdowns[pane] == nil)
    }

    @Test func nothingToResumeWithoutASkipOrWhileTyping() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        #expect(!c.canResume(pane))
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.skip(pane)
        c.keyTyped(pane)
        #expect(!c.canResume(pane))
    }

    @Test func typingDuringTheGraceCancels() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.keyTyped(pane)
        runPending()
        #expect(world.typed.isEmpty)
        #expect(c.panes[pane]?.phase == .armed)
    }

    @Test func typingAheadHoldsTheClear() {
        world.deferReplies = true
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.keyTyped(pane)  // you start typing your next prompt
        world.heldReplies.forEach { $0() }
        runPending()
        #expect(c.panes[pane]?.phase == .armed)
        #expect(world.typed.isEmpty)
        #expect(c.line(pane)?.contains("you were typing") == true)
    }

    @Test func keysTypedWhileItWorkedHoldTheClear() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        c.signal(pane, .prompted)
        c.keyTyped(pane)  // a half-typed next message, not sent
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        #expect(world.typed.isEmpty)
    }

    @Test func aSentPromptClearsTheTypingMark() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        c.keyTyped(pane)
        c.signal(pane, .prompted)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        #expect(c.panes[pane]?.phase == .pending)
    }

    @Test func theNudgeWaitsWhileYouType() {
        let c = make()
        c.contextChanged(pane, used: 400_000, size: 1_000_000)
        c.keyTyped(pane)
        world.replies["/t1"] = "No handoff yet."
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        #expect(world.typed.isEmpty)
    }

    @Test func aStaleContextReportDoesNotReArmTheFreshWindow() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        c.signal(pane, .fresh)
        // Another pane's report republishes this pane's old figure.
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        #expect(!c.isArmed(pane))
        #expect(c.line(pane)?.hasPrefix("Fresh window") == true)
        c.contextChanged(pane, used: 9_000, size: 1_000_000)
        c.contextChanged(pane, used: 320_000, size: 1_000_000)
        #expect(c.isArmed(pane))
    }

    @Test func yourOwnClearDisarms() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        c.signal(pane, .cleared)
        #expect(!c.isArmed(pane))
        #expect(!FileManager.default.fileExists(atPath: sayFile.path))
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        #expect(!c.isArmed(pane))
    }

    @Test func aFailedSaveShowsInTheBubble() throws {
        // A file where the handoffs folder should be: saving fails.
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        try Data().write(to: store.handoffs)
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        #expect(c.isArmed(pane))
        #expect(c.line(pane)?.hasPrefix("Couldn't save the handoff") == true)
    }

    @Test func aPromptBeforeTheReplyIsReadDropsTheHandoff() {
        world.deferReplies = true
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.signal(pane, .prompted)  // the agent is working again
        world.heldReplies.forEach { $0() }
        runPending()
        #expect(c.panes[pane]?.phase == .armed)
        #expect(world.typed.isEmpty)
    }

    @Test func aPromptDuringTheGraceCancels() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.signal(pane, .prompted)
        runPending()
        #expect(world.typed.isEmpty)
    }

    @Test func ourOwnClearPromptDoesNotCancelTheFreshWindowWait() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()  // types /clear
        c.signal(pane, .prompted)
        #expect(c.panes[pane]?.phase == .clearing)
        c.signal(pane, .fresh)
        #expect(world.changing == [pane])
    }

    @Test func noFreshWindowIn15sFailsOnceAndTellsYou() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()  // types /clear
        #expect(world.pending.first?.delay == ContextHandoffCoordinator.freshTimeout)
        runPending()  // the timeout
        #expect(c.panes[pane] == nil)
        #expect(world.notified.count == 1)
        #expect(c.line(pane)?.hasPrefix("Handoff saved, but the fresh window didn't start.") == true)
        // Not again in this conversation.
        c.contextChanged(pane, used: 330_000, size: 1_000_000)
        #expect(!c.isArmed(pane))
        // A new conversation arms again.
        c.signal(pane, .stopped(transcript: "/t2"))
        c.contextChanged(pane, used: 330_000, size: 1_000_000)
        #expect(c.isArmed(pane))
    }

    @Test func aReplyWithoutAHandoffStaysArmed() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = "Still debugging."
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        #expect(c.panes[pane]?.phase == .armed)
        #expect(world.typed.isEmpty)
    }

    @Test func anIncompleteHandoffIsSentBackWithWhy() throws {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        try FileManager.default.removeItem(at: sayFile)
        world.replies["/t1"] = handoff.replacingOccurrences(of: "## Active workflow\nnone\n", with: "")
        c.signal(pane, .stopped(transcript: "/t1"))
        #expect(try String(contentsOf: sayFile, encoding: .utf8).hasPrefix("Lostty: Your handoff had no 'Active workflow'."))
    }

    @Test func theCeilingNudgeIsTypedOnceAndOnlyOnce() {
        let c = make()
        c.contextChanged(pane, used: 400_000, size: 1_000_000)
        world.replies["/t1"] = "No handoff yet."
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        #expect(world.typed.map(\.1) == [[.text(ContextHandoffDirective.nudge), .enter]])
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        #expect(world.typed.count == 1)
    }

    @Test func theButtonArmsWithTheSettingOff() throws {
        world.enabled = false
        let c = make()
        c.armByButton(pane, used: 150_000, size: 1_000_000)
        #expect(c.isArmed(pane))
        #expect(try String(contentsOf: sayFile, encoding: .utf8).contains("The user asked"))
        #expect(c.line(pane) == "Will hand off at the next clean break.")
        // A context report doesn't disarm a button's arming.
        c.contextChanged(pane, used: 160_000, size: 1_000_000)
        #expect(c.isArmed(pane))
    }

    @Test func declineDisarmsUntilTheNextConversation() {
        let c = make()
        c.signal(pane, .stopped(transcript: "/t1"))
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        c.decline(pane)
        #expect(!c.isArmed(pane))
        #expect(!FileManager.default.fileExists(atPath: sayFile.path))
        c.contextChanged(pane, used: 340_000, size: 1_000_000)
        #expect(!c.isArmed(pane))
        c.signal(pane, .stopped(transcript: "/t2"))
        c.contextChanged(pane, used: 340_000, size: 1_000_000)
        #expect(c.isArmed(pane))
    }

    @Test func turningTheSettingOffMidPendingCancels() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.settingChanged(enabled: false)
        runPending()
        #expect(world.typed.isEmpty)
        #expect(c.panes[pane] == nil)
    }

    @Test func aClosedPaneIsForgotten() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        c.signal(pane, .gone)
        #expect(c.panes[pane] == nil)
        #expect(store.loadStates().isEmpty)
    }

    @Test func aRestartPicksArmedPanesBackUpAndDropsHalfDoneOnes() {
        store.saveState(pane, ContextHandoffPane(phase: .clearing, level: .limit, byButton: false, saidAt: 300_000,
                                                 used: 312_000, size: 1_000_000, handoff: "/h.md"))
        let c = make()
        c.restore()
        #expect(c.panes[pane]?.phase == .armed)
        #expect(c.panes[pane]?.handoff == nil)
    }

    @Test func waitHandoffsTypeTheWaitLine() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff.replacingOccurrences(of: "## Next\ncontinue", with: "## Open threads\nMerge now?\n## Next\nwait")
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        c.signal(pane, .fresh)
        world.pending.removeAll { $0.delay == ContextHandoffCoordinator.freshTimeout }
        runPending()
        #expect(world.typed.last?.1 == [.text(ContextHandoffDirective.continueLine(.wait)), .enter])
    }
}

struct ContextHandoffCountdownTests {
    let countdown = ContextHandoffCountdown(start: Date(timeIntervalSince1970: 100), seconds: 5, summary: "")

    @Test func theBarEmptiesOverTheCountdown() {
        #expect(countdown.remaining(at: Date(timeIntervalSince1970: 100)) == 1)
        #expect(countdown.remaining(at: Date(timeIntervalSince1970: 102.5)) == 0.5)
        #expect(countdown.remaining(at: Date(timeIntervalSince1970: 109)) == 0)
    }

    @Test func theSecondsCountDownFromFiveAndNeverShowZero() {
        #expect(countdown.secondsLeft(at: Date(timeIntervalSince1970: 100)) == 5)
        #expect(countdown.secondsLeft(at: Date(timeIntervalSince1970: 100.2)) == 5)
        #expect(countdown.secondsLeft(at: Date(timeIntervalSince1970: 104.5)) == 1)
        #expect(countdown.secondsLeft(at: Date(timeIntervalSince1970: 106)) == 1)
    }
}
#endif
