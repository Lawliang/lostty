#if os(macOS)
import Testing
@testable import Ghostty

struct SkinModelTests {
    let home = "/Users/test"
    let arcaToml = """
    [defaults]
    texture_opacity = 0.2

    [skins.arca]
    background = "#12222B"
    foreground = "#eaf3ff"
    accent = "#46a2ff"
    logo = "~/projectrepos/arca-labs/website/assets/favicon.svg"

    [skins.prod]
    background = "#3a0f14"
    texture = "diagonal"

    [[match]]
    path = "~/projectrepos/arca"
    skin = "arca"
    """

    @Test func parsesFullConfig() throws {
        let config = try SkinConfig.parse(arcaToml, home: home, fileExists: { _ in true })
        #expect(config.textureOpacity == 0.2)
        #expect(config.auto == true)
        #expect(config.skins["arca"] == Skin(
            name: "arca",
            background: RGB(hex: "#12222b")!,
            foreground: RGB(hex: "#eaf3ff")!,
            accent: RGB(hex: "#46a2ff")!,
            texture: .logo(path: "/Users/test/projectrepos/arca-labs/website/assets/favicon.svg"),
            textureOpacity: 0.2))
        #expect(config.skins["prod"]?.texture == .builtin(.diagonal))
        #expect(config.skins["prod"]?.accent == Skin.defaultAccent(for: RGB(hex: "#3a0f14")!))
        #expect(config.matches == [SkinMatch(path: "/Users/test/projectrepos/arca", skin: "arca")])
    }

    @Test func defaultsApplyRegardlessOfOrder() throws {
        let config = try SkinConfig.parse("""
        [skins.a]
        background = "#000000"
        [defaults]
        texture_opacity = 0.3
        auto = false
        """, home: home)
        #expect(config.skins["a"]?.textureOpacity == 0.3)
        #expect(config.auto == false)
    }

    @Test func emptyTextIsEmptyConfig() throws {
        #expect(try SkinConfig.parse("", home: home) == .empty)
    }

    @Test(arguments: [
        "[skins.a]\nlogo = \"/x.svg\"\nbackground = \"#000000\"",                  // logo without accent
        "[skins.a]\nbackground = \"#000000\"\ntexture = \"grid\"\nlogo = \"/x\"\naccent = \"#ffffff\"", // both
        "[skins.a]\nbackground = \"#000000\"\ntexture = \"plaid\"",                 // unknown texture
        "[skins.a]\nbackground = \"#000000\"\ncolour = \"#000000\"",                // unknown key
        "[skins.a]\nbackground = \"red\"",                                          // bad color
        "[skins.a]\nforeground = \"#ffffff\"",                                      // missing background
        "[[match]]\npath = \"~/x\"\nskin = \"nope\"",                               // unknown skin
        "[[match]]\npath = \"~/x\"",                                                 // missing skin
        "[colors]\na = 1",                                                           // unknown table
        "k = 1",                                                                     // root key
        "[defaults]\ntexture_opacity = 2",                                           // out of range
        "[defaults]\nauto = \"yes\"",                                                // wrong type
    ])
    func rejectsInvalid(_ text: String) {
        #expect(throws: SkinConfigError.self) {
            try SkinConfig.parse(text, home: "/Users/test", fileExists: { _ in true })
        }
    }

    @Test func missingLogoFileIsAnError() {
        #expect(throws: SkinConfigError.self) {
            try SkinConfig.parse(
                "[skins.a]\nbackground = \"#000000\"\naccent = \"#ffffff\"\nlogo = \"~/gone.svg\"",
                home: "/Users/test", fileExists: { _ in false })
        }
    }

    @Test func tomlErrorsBecomeConfigErrors() {
        #expect(throws: SkinConfigError(message: "skins.toml line 1: expected key = value")) {
            try SkinConfig.parse("nonsense", home: "/Users/test")
        }
    }

    @Test func rootKeysErrorHasNoBogusLine() {
        #expect(throws: SkinConfigError(message: "skins.toml: keys must be inside a table such as [defaults] or [skins.<name>]")) {
            try SkinConfig.parse("k = 1", home: "/h")
        }
    }

    @Test func rgb() {
        #expect(RGB(hex: "#12222B")?.hex == "#12222b")
        #expect(RGB(hex: "12222b") == nil)
        #expect(RGB(hex: "#+abcde") == nil)
        #expect(RGB(hex: "#12222") == nil)
        #expect(RGB.hsl(0, 1, 0.5) == RGB(r: 255, g: 0, b: 0))
        #expect(RGB.hsl(120, 1, 0.25) == RGB(r: 0, g: 128, b: 0))
        #expect(RGB(r: 0, g: 0, b: 0).mixed(with: .white, amount: 0.5) == RGB(r: 128, g: 128, b: 128))
    }

    @Test func names() {
        #expect(SkinNames.isValid("arca-labs_2"))
        #expect(!SkinNames.isValid(""))
        #expect(!SkinNames.isValid("../etc"))
        #expect(!SkinNames.isValid("a/b"))
        #expect(!SkinNames.isValid(String(repeating: "a", count: 65)))
    }

    @Test func expand() {
        #expect(SkinConfig.expand("~", home: "/h") == "/h")
        #expect(SkinConfig.expand("~/a", home: "/h") == "/h/a")
        #expect(SkinConfig.expand("/abs", home: "/h") == "/abs")
        #expect(SkinConfig.expand("~other/a", home: "/h") == "~other/a")
    }
}
#endif
