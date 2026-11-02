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
        let prompt = NewWindowPrompt(repo: repo, window: window, noun: "card", takesKeys: { true }) { _ in }
        #expect(prompt.take(key("3", in: window)))
        #expect(prompt.stage == .projects)
    }

    @Test func returnMakesANewWorktree() {
        let window = makeWindow()
        let prompt = NewWindowPrompt(repo: repo, window: window, noun: "window") { _ in }
        #expect(prompt.take(key("\r", in: window)))
        #expect(prompt.stage == .working)
    }

    @Test func threeListsProjectsAndEscGoesBack() {
        let window = makeWindow()
        let prompt = NewWindowPrompt(repo: repo, window: window, noun: "window") { _ in }
        #expect(prompt.take(key("3", in: window)))
        #expect(prompt.stage == .projects)
        #expect(prompt.shown.last?.isHome == true)
        prompt.query = "zzz-none"
        #expect(prompt.shown.isEmpty)
        #expect(prompt.take(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!))
        #expect(prompt.stage == .choosing)
    }

    @Test func withNoRepoItStartsOnTheProjectsAndEscKeepsTheTerminal() {
        let window = makeWindow()
        var picked: String??
        let prompt = NewWindowPrompt(repo: nil, projectsIn: "/nowhere", window: window) { picked = $0 }
        #expect(prompt.stage == .projects)
        #expect(prompt.shown.map(\.isHome) == [true])
        prompt.back()
        #expect(picked == .some(nil))
    }

    @Test func aTerminalOutsideAnyRepoLooksBesideTheZonesFolders() {
        #expect(NewWindowProject.folder(near: ["/nowhere/x", NSTemporaryDirectory()])
            == (NSTemporaryDirectory() as NSString).deletingLastPathComponent)
    }

    @Test func projectsAreTheReposBesideTheTerminalsMostRecentFirst() throws {
        let files = FileManager.default
        let dir = files.temporaryDirectory.appendingPathComponent("NewWindowProjects-\(UUID().uuidString)").path
        defer { try? files.removeItem(atPath: dir) }
        for (name, age) in [("old", 100.0), ("new", 10.0), ("here", 0.0)] {
            try files.createDirectory(atPath: "\(dir)/\(name)/.git", withIntermediateDirectories: true)
            try files.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: "\(dir)/\(name)/.git")
        }
        try files.createDirectory(atPath: "\(dir)/notes", withIntermediateDirectories: true)
        let names = NewWindowProject.list(near: "\(dir)/here").map(\.name)
        #expect(names == ["new", "old", "Home folder"])
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
