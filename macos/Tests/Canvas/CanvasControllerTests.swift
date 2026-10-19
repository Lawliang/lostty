#if os(macOS)
import AppKit
import Testing
@testable import Lostty

struct CardFocusTests {
    @Test func onlyTheActiveCardsFocusedPaneHasFocus() {
        #expect(CardController.paneIsFocused(windowIsKey: true, cardIsFocused: true, paletteShowing: false, isFocusedPane: true))
        #expect(!CardController.paneIsFocused(windowIsKey: true, cardIsFocused: false, paletteShowing: false, isFocusedPane: true))
        #expect(!CardController.paneIsFocused(windowIsKey: false, cardIsFocused: true, paletteShowing: false, isFocusedPane: true))
        #expect(!CardController.paneIsFocused(windowIsKey: true, cardIsFocused: true, paletteShowing: true, isFocusedPane: true))
        #expect(!CardController.paneIsFocused(windowIsKey: true, cardIsFocused: true, paletteShowing: false, isFocusedPane: false))
    }

    @Test func closedCardsAreKeptForUndoButNotForever() {
        #expect(CanvasController.retiredLimit == 10)
    }
}

@MainActor
struct CanvasMenuTests {
    private func windowMenu() -> (NSMenu, NSMenuItem) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Minimize", action: nil, keyEquivalent: "m")
        let anchor = menu.addItem(withTitle: "Bring All to Front", action: nil, keyEquivalent: "")
        return (menu, anchor)
    }

    @Test func stableHasNoCanvasItems() {
        let (menu, anchor) = windowMenu()
        CanvasMenu.install(before: anchor, channel: .stable)
        #expect(menu.items.map(\.title) == ["Minimize", "Bring All to Front"])
    }

    @Test func theBetaOpensTheCanvasWithControlCommandK() throws {
        let (menu, anchor) = windowMenu()
        CanvasMenu.install(before: anchor, channel: .beta)
        let item = try #require(menu.items.first { $0.title == "Canvas" })
        #expect(item.keyEquivalent == "k")
        #expect(item.keyEquivalentModifierMask == [.control, .command])
        #expect(menu.items.last === anchor)
        #expect(menu.items[menu.items.count - 2].isSeparatorItem)
    }

    @Test func theCanvasShortcutsStayClearOfTheTerminals() throws {
        let (menu, anchor) = windowMenu()
        CanvasMenu.install(before: anchor, channel: .beta)
        func item(_ title: String) throws -> NSMenuItem { try #require(menu.items.flatMap { [$0] + ($0.submenu?.items ?? []) }.first { $0.title == title }) }
        #expect(try item("Jump to What Needs You").keyEquivalent == "j")
        #expect(try item("Jump to What Needs You").keyEquivalentModifierMask == [.control, .command])
        #expect(try item("Zoom to Fit").keyEquivalent == "0")
        #expect(try item("Zoom Card to 100%").keyEquivalent == "1")
        let left = try item("Select Card Left")
        #expect(left.keyEquivalentModifierMask == [.control, .option, .command])
        #expect(left.keyEquivalent == String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
    }
}

struct CanvasRestoreTests {
    @Test func theCanvasNeverOverwritesTheQuickTerminalsState() {
        #expect(CanvasRestorableState.selfKey != QuickTerminalRestorableState.selfKey)
        #expect(CanvasRestorableState.versionKey != QuickTerminalRestorableState.versionKey)
        #expect(CanvasRestorableState.version == 1)
    }
}
#endif
