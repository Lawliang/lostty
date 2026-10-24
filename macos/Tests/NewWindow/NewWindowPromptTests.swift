#if os(macOS)
import AppKit
import Testing
@testable import Lostty

@MainActor
struct NewWindowPromptTests {
    let repo = NewWindowRepo(root: "/r/app", checkout: "/r/app", commonDir: "/r/app/.git", branch: "main")

    private func makeWindow() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled],
                 backing: .buffered, defer: false)
    }

    private func key(_ characters: String, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
            keyCode: 0)!
    }

    @Test func aFocusedCardsQuestionTakesItsKeys() {
        let window = makeWindow()
        var picked: String??
        let prompt = NewWindowPrompt(repo: repo, window: window, noun: "card", takesKeys: { true }) { picked = $0 }
        #expect(prompt.take(key("3", in: window)))
        #expect(picked == .some(NSHomeDirectory()))
    }

    @Test func anotherCardsQuestionLeavesTheKeysToTheFocusedCard() {
        let window = makeWindow()
        var picked: String??
        let prompt = NewWindowPrompt(repo: repo, window: window, noun: "card", takesKeys: { false }) { picked = $0 }
        #expect(!prompt.take(key("3", in: window)))
        #expect(picked == nil)
    }
}
#endif
