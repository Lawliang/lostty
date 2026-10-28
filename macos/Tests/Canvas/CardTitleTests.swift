#if os(macOS)
import Testing
@testable import Lostty

struct CardTitleTests {
    @Test func theSessionLeadsTheTerminalsTitle() {
        #expect(CardController.title("✳ Handoff open question", session: "more-UI-improvements")
            == "more-UI-improvements · ✳ Handoff open question")
    }

    @Test func aTitleThatStartsWithTheSessionKeepsItOnce() {
        #expect(CardController.title("zones-2", session: "zones-2") == "zones-2")
        #expect(CardController.title("zones-2: vim", session: "zones-2") == "zones-2: vim")
    }

    @Test func noSessionLeavesTheTitle() {
        #expect(CardController.title("✳ Handoff pickup", session: nil) == "✳ Handoff pickup")
        #expect(CardController.title("✳ Handoff pickup", session: "") == "✳ Handoff pickup")
    }

    @Test func anEmptyTitleIsTheSession() {
        #expect(CardController.title("", session: "gold-drop") == "gold-drop")
    }
}
#endif
