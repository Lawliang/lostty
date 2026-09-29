#if os(macOS)
import Testing
@testable import Ghostty

struct AutoSkinTests {
    @Test func deterministicAndCaseInsensitive() {
        let a = AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16)
        #expect(a == AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16))
        #expect(a.background == AutoSkin.skin(forRepo: "milo", textureOpacity: 0.16).background)
        #expect(a.name == "Milo")
        #expect(a.textureOpacity == 0.16)
        if case .builtin = a.texture {} else { Issue.record("auto skins use a built-in texture") }
    }

    @Test func differentReposDiffer() {
        let names = ["Milo", "Tabletake", "fewdy", "songslice", "Grain-app"]
        let backgrounds = Set(names.map { AutoSkin.skin(forRepo: $0, textureOpacity: 0.16).background })
        #expect(backgrounds.count == names.count)
    }

    @Test func backgroundsAreDark() {
        for name in ["Milo", "Tabletake", "fewdy", "songslice", "x"] {
            let bg = AutoSkin.skin(forRepo: name, textureOpacity: 0.16).background
            let luminance = (0.2126 * Double(bg.r) + 0.7152 * Double(bg.g) + 0.0722 * Double(bg.b)) / 255
            #expect(luminance < 0.2, "\(name) background \(bg.hex) is too light")
        }
    }

    @Test func fnvIsStable() {
        #expect(AutoSkin.fnv1a("") == 0xcbf29ce484222325)
        #expect(AutoSkin.fnv1a("a") == 0xaf63dc4c8601ec8c)
    }

    @Test func autoTexturesUnchanged() {
        #expect(AutoSkin.autoTextures == [.dots, .grid, .diagonal, .cross, .waves, .noise])
        for name in ["Milo", "Tabletake", "fewdy", "songslice", "Grain-app"] {
            let hash = AutoSkin.fnv1a(name.lowercased())
            let expected = AutoSkin.autoTextures[Int((hash >> 16) % 6)]
            #expect(AutoSkin.skin(forRepo: name, textureOpacity: 0.16).texture == .builtin(expected))
        }
    }
}
#endif
