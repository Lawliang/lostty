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
}
#endif
