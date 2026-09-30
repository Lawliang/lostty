#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SkinOverlayTests {
    @Test func colorOnly() {
        let skin = Skin(name: "p", background: RGB(hex: "#3a0f14")!, foreground: RGB(hex: "#eeeeee")!,
                        accent: RGB(hex: "#ffffff")!, texture: .none, textureOpacity: 0.16)
        #expect(SkinOverlay.configText(for: AppliedSkin(skin: skin, tile: nil))
            == "background = #3a0f14\nforeground = #eeeeee\n")
    }

    @Test func withTile() {
        let skin = Skin(name: "a", background: RGB(hex: "#12222b")!, foreground: nil,
                        accent: RGB(hex: "#46a2ff")!, texture: .builtin(.dots), textureOpacity: 0.2)
        let text = SkinOverlay.configText(for: AppliedSkin(skin: skin, tile: URL(fileURLWithPath: "/c/My Tiles/t.png")))
        #expect(text == """
        background = #12222b
        background-image = "/c/My Tiles/t.png"
        background-image-opacity = 0.200
        background-image-fit = none
        background-image-position = top-left
        background-image-repeat = true

        """)
    }

    @Test func presetThemeLines() {
        let skin = SkinPresets.all[0].skin
        let text = SkinOverlay.configText(for: AppliedSkin(skin: skin, tile: nil))
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines[0] == "background = #120a2a")
        #expect(lines[1] == "foreground = #f3ecff")
        #expect(lines[2] == "palette = 0=#1d1240")
        #expect(lines[17] == "palette = 15=#f3ecff")
        #expect(lines[18] == "cursor-color = #ff3df2")
        #expect(lines[19] == "selection-background = \(skin.selectionBackground!.hex)")
        #expect(lines.count == 20)
    }
}
#endif
