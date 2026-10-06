#if os(macOS)
import Testing
@testable import Ghostty

struct TraceConfigTests {
    let home = "/Users/test"

    func parse(_ toml: String) throws -> SkinConfig {
        try SkinConfig.parse(toml, home: home, fileExists: { _ in true })
    }

    @Test func skinWithoutTraceKeysHasNoTrace() throws {
        let config = try parse("[skins.a]\nbackground = \"#101820\"\n")
        #expect(config.skins["a"]?.trace == nil)
        #expect(config.trace == true)
    }

    @Test func parsesAllTraceKeys() throws {
        let config = try parse("""
        [skins.a]
        background = "#101820"
        trace = "bolt"
        trace_color = "#FF00AA"
        trace_color2 = "#00ffcc"
        trace_speed = 1.5
        trace_length = 0.2
        """)
        #expect(config.skins["a"]?.trace == SkinTrace(
            style: .bolt, disabled: false, color: RGB(hex: "#ff00aa"), color2: RGB(hex: "#00ffcc"),
            speed: 1.5, length: 0.2))
    }

    @Test func traceNoneDisables() throws {
        let config = try parse("[skins.a]\nbackground = \"#101820\"\ntrace = \"none\"\n")
        #expect(config.skins["a"]?.trace?.disabled == true)
        #expect(ResolvedTrace.resolve(skin: config.skins["a"], enabled: true) == nil)
    }

    @Test func defaultsTraceFalseTurnsAllOff() throws {
        let config = try parse("[defaults]\ntrace = false\n")
        #expect(config.trace == false)
        #expect(ResolvedTrace.resolve(skin: nil, enabled: config.trace) == nil)
    }

    @Test func rejectsBadValues() {
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace = \"laser\"\n") }
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace = 3\n") }
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace_speed = 5\n") }
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace_speed = 0.1\n") }
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace_length = 0.6\n") }
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace_color = \"red\"\n") }
        #expect(throws: SkinConfigError.self) { try parse("[defaults]\ntrace = \"yes\"\n") }
    }

    @Test func everyPresetHasItsOwnStyle() {
        let styles = SkinPresets.all.compactMap { $0.skin.trace?.style }
        #expect(styles.count == 12)
        #expect(Set(styles).count == 12)
        #expect(!styles.contains(.beam))
        let byName = Dictionary(uniqueKeysWithValues: SkinPresets.all.map { ($0.skin.name, $0.skin.trace?.style) })
        #expect(byName["thunderhead"] == .bolt)
        #expect(byName["stormsurge"] == .tempest)
        #expect(byName["neon-arcade"] == .comet)
    }

    @Test func shadowingPresetInheritsStyleButKeepsOwnTuning() throws {
        let config = try parse("[skins.thunderhead]\nbackground = \"#000000\"\ntrace_speed = 2\n")
        let skin = try #require(SkinLibrary.skins(config: config)["thunderhead"])
        #expect(skin.trace?.style == .bolt)
        #expect(skin.trace?.speed == 2)
    }

    @Test func shadowingPresetCanPickOrDisable() throws {
        let picked = try parse("[skins.thunderhead]\nbackground = \"#000000\"\ntrace = \"tide\"\n")
        #expect(SkinLibrary.skins(config: picked)["thunderhead"]?.trace?.style == .tide)
        let off = try parse("[skins.thunderhead]\nbackground = \"#000000\"\ntrace = \"none\"\n")
        #expect(ResolvedTrace.resolve(skin: SkinLibrary.skins(config: off)["thunderhead"], enabled: true) == nil)
    }

    @Test func resolveUsesSkinColorsAndDefaults() throws {
        let preset = try #require(SkinPresets.all.first { $0.skin.name == "thunderhead" }?.skin)
        let resolved = try #require(ResolvedTrace.resolve(skin: preset, enabled: true))
        #expect(resolved.style == .bolt)
        #expect(resolved.color == preset.accent)
        #expect(resolved.color2 == preset.accent2)
        #expect(resolved.speed == 1)
        #expect(resolved.length == 0.18)
    }

    @Test func resolveWithoutAccent2DerivesSecondary() throws {
        let skin = Skin(name: "x", background: RGB(hex: "#101820")!, foreground: nil,
                        accent: RGB(hex: "#46a2ff")!, texture: .none, textureOpacity: 0.16)
        let resolved = try #require(ResolvedTrace.resolve(skin: skin, enabled: true))
        #expect(resolved.style == .beam)
        #expect(resolved.color2 == RGB(hex: "#46a2ff")!.mixed(with: .white, amount: 0.4))
    }

    @Test func unskinnedPaneGetsHologramBeam() throws {
        let resolved = try #require(ResolvedTrace.resolve(skin: nil, enabled: true))
        #expect(resolved == ResolvedTrace(style: .beam, color: RGB(hex: "#ff7ad9")!,
                                          color2: RGB(hex: "#7af0ff")!, speed: 1, length: 0.18))
    }
}
#endif
