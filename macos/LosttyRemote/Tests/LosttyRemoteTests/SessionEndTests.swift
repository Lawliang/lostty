import Testing
@testable import LosttyRemote

struct SessionEndTests {
    func gone(_ tag: String?) -> EndProbe { EndProbe(exists: false, tag: tag) }

    @Test func eachTagSaysWhy() {
        #expect(SessionEnd.decide(probe: gone("mac-close"), endedHere: false, typedRecently: false) == .closed("Closed on your Mac"))
        #expect(SessionEnd.decide(probe: gone("mac-quit"), endedHere: false, typedRecently: false) == .closed("Lostty quit on your Mac"))
        #expect(SessionEnd.decide(probe: gone("phone:iPad Pro"), endedHere: false, typedRecently: false) == .closed("Closed from iPad Pro"))
    }

    @Test func noTagAndRecentTypingIsYouTypingExit() {
        #expect(SessionEnd.decide(probe: gone(nil), endedHere: false, typedRecently: true) == .backToList)
    }

    @Test func noTagAndNoTypingIsTheShellExiting() {
        #expect(SessionEnd.decide(probe: gone(nil), endedHere: false, typedRecently: false) == .closed("The shell exited"))
    }

    @Test func closingFromHereGoesStraightBack() {
        #expect(SessionEnd.decide(probe: gone("phone:iPhone 15 Pro"), endedHere: true, typedRecently: false) == .backToList)
        #expect(SessionEnd.decide(probe: nil, endedHere: true, typedRecently: false) == .backToList)
    }

    @Test func aSessionStillThereWasOnlyDetached() {
        #expect(SessionEnd.decide(probe: EndProbe(exists: true, tag: "mac-close"), endedHere: false, typedRecently: false) == .stillRunning)
    }

    @Test func unreadableSaysTheTerminalWasClosed() {
        #expect(SessionEnd.decide(probe: nil, endedHere: false, typedRecently: true) == .closed("This terminal was closed"))
        #expect(SessionEnd.decide(probe: gone("something-new"), endedHere: false, typedRecently: false) == .closed("This terminal was closed"))
        #expect(SessionEnd.decide(probe: gone("phone:"), endedHere: false, typedRecently: false) == .closed("This terminal was closed"))
    }

    @Test func aTagBeatsRecentTyping() {
        #expect(SessionEnd.decide(probe: gone("mac-close"), endedHere: false, typedRecently: true) == .closed("Closed on your Mac"))
    }

    @Test func anotherPhoneOfTheSameModelStillGetsTheOverlay() {
        // This phone is also an "iPhone 15 Pro", but it didn't close it.
        #expect(SessionEnd.decide(probe: gone("phone:iPhone 15 Pro"), endedHere: false, typedRecently: false)
            == .closed("Closed from iPhone 15 Pro"))
    }
}
