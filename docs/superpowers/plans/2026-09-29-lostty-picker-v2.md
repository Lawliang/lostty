# Lostty Picker v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the redesigned skin picker, a built-in gamified preset pack with full terminal themes, saved custom colors, and locked (skins.toml-mapped) folders.

**Architecture:** Presets live in code (`SkinPresets.swift`) and merge with `skins.toml` skins into a library (config shadows built-ins). `Skin` gains optional theme fields that `SkinOverlay` turns into Ghostty `palette`/`cursor-color`/`selection-background` lines. `SkinManager` gets a locked layer that beats preview/override for mapped folders and exposes it in `catalog.json`; the Zig CLI refuses picks there. The SwiftUI popover is rewritten to the approved mockup.

**Tech Stack:** Swift 5 mode / SwiftUI / AppKit / CoreGraphics, Swift Testing; Zig 0.15.2.

**Spec:** `docs/superpowers/specs/2026-09-29-lostty-picker-v2-design.md` (approved). Visual reference: the "Lostty Skin Picker" design artifact.

## Global Constraints

- Repo `/Users/lawliang/projectrepos/ghostty-skins`, branch `skins`. Push only to `origin`; never `upstream`.
- Zig: prefix `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" &&`. Swift tests: `macos/skins-test.sh [Suite]`. App build: `macos/build.nu --scheme Ghostty --configuration Debug --action build`. Builds/tests take minutes (timeouts up to 600000 ms).
- New Swift files: wrap in `#if os(macOS)` … `#endif`; import every module used (member-import-visibility is on). New files under `macos/Sources` / `macos/Tests` join targets automatically.
- Commits end with a `Co-Authored-By:` trailer naming the model that wrote them. Never commit `spike-shots/`, `macos/build/`, `default.profraw`.
- No screenshots by implementers; no writes to the user's real Ghostty config; no `/Applications` copy; no push (the controller does install/push/screenshots).
- Preset ids/colors/rarities, texture names, file paths, and messages are exactly as in the spec and this plan.
- Upstream-file edits must be listed in `UPGRADING.md` (only Task 7 touches one: none expected).

## Review Focus

1. **A pane that already has an override `cd`s into a mapped folder.** Expected: the mapped skin shows; leaving restores the override. Pinned by `SkinManagerTests.overrideSurvivesLockedFolder` (Task 4).
2. **A `skins.toml` skin named like a built-in (e.g. `neon-arcade`).** Expected: the config skin wins everywhere (grid, CLI, requests). Pinned by `SkinPresetsTests.configShadowsBuiltin` (Task 2) and `SkinManagerTests.requestUsesShadowedPreset` (Task 4).
3. **`saved-colors.json` hand-edited into garbage or with duplicates/200 entries.** Expected: loads what's valid, dedupes, caps at 24, never crashes. Pinned by `SavedColorsStoreTests` (Task 5).
4. **Existing automatic skins after adding textures.** Expected: every repo keeps its previous texture. Pinned by `AutoSkinTests.autoTexturesUnchanged` (Task 1).
5. **`skins set` from a locked pane when the catalog is stale/missing.** Expected: locked → exit 1 with message; missing catalog → best-effort send (the app still ignores it). Pinned by Zig `skins: lockedMessage` tests (Task 6) and Task 4's locked rejection test.

---

## File Structure

| File | Change |
|---|---|
| `macos/Sources/Features/Skins/SkinModel.swift` | `Skin` theme fields; 3 new `BuiltinTexture` cases |
| `macos/Sources/Features/Skins/AutoSkin.swift` | fixed auto texture list |
| `macos/Sources/Features/Skins/TextureStore.swift` | render scanlines/sparkle/rings |
| `macos/Sources/Features/Skins/SkinPresets.swift` (new) | preset pack, `SkinRarity`, `SkinLibrary` |
| `macos/Sources/Features/Skins/SkinsRuntime.swift` | overlay theme lines; `savedColors` store |
| `macos/Sources/Features/Skins/SkinManager.swift` | library lookups, locked layer, catalog fields, queries |
| `macos/Sources/Features/Skins/SavedColorsStore.swift` (new) | persisted saved colors |
| `macos/Sources/Features/Skins/SkinPopoverView.swift` | full rewrite |
| `macos/Sources/Features/Skins/SkinChipView.swift` | lock glyph, "Equipped" flash, pass saved colors |
| `src/cli/skins/protocol.zig`, `src/cli/skins.zig` | catalog `rarity`/`locked`, locked refusal |
| `SKINS.md` | docs |
| tests under `macos/Tests/Skins/` and `src/cli/skins/` | as listed per task |

---

### Task 1: Theme fields, new textures, stable auto textures

**Files:**
- Modify: `macos/Sources/Features/Skins/SkinModel.swift` (`BuiltinTexture` line ~55, `Skin` line ~65)
- Modify: `macos/Sources/Features/Skins/AutoSkin.swift`
- Modify: `macos/Sources/Features/Skins/TextureStore.swift` (`renderBuiltin` switch ~line 135)
- Test: `macos/Tests/Skins/AutoSkinTests.swift`, `macos/Tests/Skins/SkinModelTests.swift`

**Interfaces:**
- Produces: `BuiltinTexture` cases `dots, grid, diagonal, cross, waves, noise, scanlines, sparkle, rings` (in that order); `Skin` new stored properties with defaults: `var accent2: RGB? = nil`, `var palette: [RGB]? = nil`, `var cursor: RGB? = nil`, `var selectionBackground: RGB? = nil` (memberwise init stays source-compatible); `AutoSkin.autoTextures: [BuiltinTexture]`.

- [ ] **Step 1: Failing tests.** Append to `AutoSkinTests`:

```swift
    @Test func autoTexturesUnchanged() {
        #expect(AutoSkin.autoTextures == [.dots, .grid, .diagonal, .cross, .waves, .noise])
        for name in ["Milo", "Tabletake", "fewdy", "songslice", "Grain-app"] {
            let hash = AutoSkin.fnv1a(name.lowercased())
            let expected = AutoSkin.autoTextures[Int((hash >> 16) % 6)]
            #expect(AutoSkin.skin(forRepo: name, textureOpacity: 0.16).texture == .builtin(expected))
        }
    }
```

Append to `SkinModelTests`:

```swift
    @Test func newTexturesParse() throws {
        for name in ["scanlines", "sparkle", "rings"] {
            let config = try SkinConfig.parse("[skins.a]\nbackground = \"#000000\"\ntexture = \"\(name)\"", home: "/h")
            #expect(config.skins["a"]?.texture == .builtin(BuiltinTexture(rawValue: name)!))
        }
    }

    @Test func themeFieldsDefaultToNil() {
        let s = Skin(name: "x", background: RGB(r: 0, g: 0, b: 0), foreground: nil,
                     accent: RGB(r: 1, g: 1, b: 1), texture: .none, textureOpacity: 0.1)
        #expect(s.palette == nil && s.cursor == nil && s.selectionBackground == nil && s.accent2 == nil)
    }
```

- [ ] **Step 2: Run** `macos/skins-test.sh AutoSkinTests; macos/skins-test.sh SkinModelTests` → FAIL (unknown members).

- [ ] **Step 3: Implement.**

`SkinModel.swift`:

```swift
enum BuiltinTexture: String, CaseIterable {
    case dots, grid, diagonal, cross, waves, noise, scanlines, sparkle, rings
}
```

In `struct Skin`, after `var textureOpacity: Double`:

```swift
    /// Optional terminal theme (built-in presets set these).
    var accent2: RGB? = nil
    /// 16 ANSI colors, index 0–15.
    var palette: [RGB]? = nil
    var cursor: RGB? = nil
    var selectionBackground: RGB? = nil
```

`AutoSkin.swift`: add `static let autoTextures: [BuiltinTexture] = [.dots, .grid, .diagonal, .cross, .waves, .noise]` with a comment "Fixed so adding textures never reshuffles existing repos' looks.", and replace `let textures = BuiltinTexture.allCases` with `let textures = autoTextures`.

`TextureStore.renderBuiltin` — add cases (same `step`, `size`, `center(_:_:)` helpers as existing cases):

```swift
        case .scanlines:
            // 40 lines per tile (5.5 px apart) keeps the repeat seamless.
            for i in 0..<40 {
                let y = CGFloat(i) * (size / 40) + 0.5
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: size, y: y))
            }
            ctx.setLineWidth(1)
            ctx.strokePath()
        case .sparkle:
            for i in 0..<8 {
                for j in 0..<8 {
                    let c = center(i, j)
                    ctx.fillEllipse(in: CGRect(x: c.x - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4))
                }
            }
            for i in 0..<4 {
                for j in 0..<4 {
                    let c = CGPoint(x: CGFloat(i) * size / 4 + step, y: CGFloat(j) * size / 4 + step)
                    ctx.fillEllipse(in: CGRect(x: c.x - 2.4, y: c.y - 2.4, width: 4.8, height: 4.8))
                }
            }
        case .rings:
            for i in 0..<4 {
                for j in 0..<4 {
                    let c = CGPoint(x: (CGFloat(i) + 0.5) * size / 4, y: (CGFloat(j) + 0.5) * size / 4)
                    ctx.strokeEllipse(in: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
                }
            }
```

(The existing `builtinTilesRender` test is parameterized over `BuiltinTexture.allCases`, so it covers the new cases.)

- [ ] **Step 4: Run** `macos/skins-test.sh` (full suite) → `** TEST SUCCEEDED **`.
- [ ] **Step 5: Commit** `skins: theme fields on Skin, scanlines/sparkle/rings textures, stable auto textures`.

---

### Task 2: Preset pack and skin library

**Files:**
- Create: `macos/Sources/Features/Skins/SkinPresets.swift`
- Test: `macos/Tests/Skins/SkinPresetsTests.swift`

**Interfaces:**
- Consumes: Task 1's `Skin` fields and textures.
- Produces: `enum SkinRarity: String { case legendary, epic, rare, common, project }`; `struct SkinPreset { let skin: Skin; let rarity: SkinRarity }`; `enum SkinPresets { static let all: [SkinPreset] }` (order: neon-arcade, sunset-drive, mint-protocol, deep-dive, lava-rush, bubble-pop); `enum SkinLibrary { struct Entry { let skin: Skin; let rarity: SkinRarity }; static func entries(config: SkinConfig) -> [Entry]; static func skins(config: SkinConfig) -> [String: Skin] }` — `entries`: built-ins in pack order (each replaced by a same-named config skin, rarity then `.project`), then remaining config skins sorted by name with `.project`.

- [ ] **Step 1: Failing tests** `macos/Tests/Skins/SkinPresetsTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Ghostty

struct SkinPresetsTests {
    @Test func packMatchesSpec() {
        #expect(SkinPresets.all.map(\.skin.name) == ["neon-arcade", "sunset-drive", "mint-protocol", "deep-dive", "lava-rush", "bubble-pop"])
        #expect(SkinPresets.all.map(\.rarity) == [.legendary, .epic, .rare, .rare, .epic, .common])
        let neon = SkinPresets.all[0].skin
        #expect(neon.background == RGB(hex: "#120a2a"))
        #expect(neon.foreground == RGB(hex: "#f3ecff"))
        #expect(neon.accent == RGB(hex: "#ff3df2"))
        #expect(neon.accent2 == RGB(hex: "#28e7ff"))
        #expect(neon.texture == .builtin(.grid))
    }

    @Test func everyPresetHasAFullTheme() {
        for preset in SkinPresets.all {
            #expect(preset.skin.palette?.count == 16, "\(preset.skin.name)")
            #expect(preset.skin.cursor == preset.skin.accent)
            #expect(preset.skin.selectionBackground == preset.skin.background.mixed(with: preset.skin.accent, amount: 0.35))
        }
    }

    @Test func libraryAppendsConfigSkinsAsProject() throws {
        let config = try SkinConfig.parse("[skins.arca]\nbackground = \"#12222b\"", home: "/h")
        let entries = SkinLibrary.entries(config: config)
        #expect(entries.map(\.skin.name) == ["neon-arcade", "sunset-drive", "mint-protocol", "deep-dive", "lava-rush", "bubble-pop", "arca"])
        #expect(entries.last?.rarity == .project)
        #expect(SkinLibrary.skins(config: config).count == 7)
    }

    @Test func configShadowsBuiltin() throws {
        let config = try SkinConfig.parse("[skins.neon-arcade]\nbackground = \"#000000\"", home: "/h")
        let entries = SkinLibrary.entries(config: config)
        #expect(entries.count == 6)
        #expect(entries[0].skin.background == RGB(hex: "#000000"))
        #expect(entries[0].rarity == .project)
        #expect(SkinLibrary.skins(config: config)["neon-arcade"]?.palette == nil)
    }
}
#endif
```

- [ ] **Step 2: Run** `macos/skins-test.sh SkinPresetsTests` → FAIL.

- [ ] **Step 3: Implement** `macos/Sources/Features/Skins/SkinPresets.swift`:

```swift
#if os(macOS)
import Foundation

enum SkinRarity: String {
    case legendary, epic, rare, common, project
}

struct SkinPreset {
    let skin: Skin
    let rarity: SkinRarity
}

/// The built-in preset pack (spec §3). Palettes are hand-tuned: 0/8 dark,
/// 7/15 light, 1–6 and 9–14 vivid and readable on the preset's background.
enum SkinPresets {
    static let all: [SkinPreset] = [
        make("neon-arcade", .legendary, bg: "#120a2a", fg: "#f3ecff", accent: "#ff3df2", accent2: "#28e7ff", texture: .grid,
             palette: ["#1d1240", "#ff4f7b", "#3dffb0", "#ffd84d", "#7b8cff", "#ff3df2", "#28e7ff", "#d9ccff",
                       "#4a3a7a", "#ff7a9c", "#7dffcb", "#ffe68a", "#a5b1ff", "#ff7af6", "#7af0ff", "#f3ecff"]),
        make("sunset-drive", .epic, bg: "#1c0b24", fg: "#ffe9f5", accent: "#ff7a3d", accent2: "#ff4fa3", texture: .scanlines,
             palette: ["#2b1436", "#ff4f5e", "#9dff6a", "#ffb347", "#8f7bff", "#ff4fa3", "#5ee7ff", "#f0d4e6",
                       "#5a3a66", "#ff7a86", "#bfff96", "#ffcf7f", "#b3a6ff", "#ff85c0", "#8ff0ff", "#ffe9f5"]),
        make("mint-protocol", .rare, bg: "#04140f", fg: "#d8ffe9", accent: "#2cff9a", accent2: "#b6ff3b", texture: .dots,
             palette: ["#0b2219", "#ff5c7a", "#2cff9a", "#b6ff3b", "#3fb8ff", "#d38bff", "#3dffe0", "#bfe8d2",
                       "#2e5445", "#ff8aa0", "#7dffc0", "#d4ff85", "#7fd1ff", "#e3b3ff", "#8affec", "#d8ffe9"]),
        make("deep-dive", .rare, bg: "#041a2e", fg: "#dff4ff", accent: "#25c4ff", accent2: "#9b87ff", texture: .waves,
             palette: ["#0b2a45", "#ff5c8a", "#3dffa8", "#ffd166", "#25c4ff", "#9b87ff", "#3de8ff", "#c4e4f5",
                       "#2f5575", "#ff8aac", "#85ffc8", "#ffe199", "#7ad8ff", "#bfb3ff", "#8af0ff", "#dff4ff"]),
        make("lava-rush", .epic, bg: "#1d0806", fg: "#fff0e8", accent: "#ff5a2c", accent2: "#ffc53d", texture: .diagonal,
             palette: ["#2e110c", "#ff5a2c", "#b8ff4d", "#ffc53d", "#6fa8ff", "#ff5fb0", "#4de3ff", "#f2d9cc",
                       "#5e3228", "#ff8a66", "#d2ff8a", "#ffd97f", "#9cc4ff", "#ff8fca", "#8aecff", "#fff0e8"]),
        make("bubble-pop", .common, bg: "#230a24", fg: "#ffeefe", accent: "#ff6ad5", accent2: "#ffd84d", texture: .sparkle,
             palette: ["#36143a", "#ff5c8a", "#6dffb3", "#ffd84d", "#7ea8ff", "#ff6ad5", "#5cf2ff", "#f2d6f0",
                       "#663b68", "#ff8aab", "#9dffcc", "#ffe68a", "#a8c4ff", "#ff9be4", "#92f6ff", "#ffeefe"]),
    ]

    /// Display name for a preset id ("neon-arcade" → "Neon Arcade").
    static func displayName(_ id: String) -> String {
        id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func make(
        _ id: String, _ rarity: SkinRarity, bg: String, fg: String, accent: String, accent2: String,
        texture: BuiltinTexture, palette: [String]
    ) -> SkinPreset {
        let background = RGB(hex: bg)!
        let accentRGB = RGB(hex: accent)!
        return SkinPreset(
            skin: Skin(
                name: id, background: background, foreground: RGB(hex: fg)!, accent: accentRGB,
                texture: .builtin(texture), textureOpacity: 0.22,
                accent2: RGB(hex: accent2)!, palette: palette.map { RGB(hex: $0)! },
                cursor: accentRGB, selectionBackground: background.mixed(with: accentRGB, amount: 0.35)),
            rarity: rarity)
    }
}

/// Built-in presets merged with skins.toml skins; config skins shadow built-ins.
enum SkinLibrary {
    struct Entry {
        let skin: Skin
        let rarity: SkinRarity
    }

    static func entries(config: SkinConfig) -> [Entry] {
        var result = SkinPresets.all.map { preset -> Entry in
            if let own = config.skins[preset.skin.name] { return Entry(skin: own, rarity: .project) }
            return Entry(skin: preset.skin, rarity: preset.rarity)
        }
        let builtinNames = Set(SkinPresets.all.map(\.skin.name))
        for skin in config.skins.values.sorted(by: { $0.name < $1.name }) where !builtinNames.contains(skin.name) {
            result.append(Entry(skin: skin, rarity: .project))
        }
        return result
    }

    static func skins(config: SkinConfig) -> [String: Skin] {
        Dictionary(uniqueKeysWithValues: entries(config: config).map { ($0.skin.name, $0.skin) })
    }
}
#endif
```

- [ ] **Step 4: Run** `macos/skins-test.sh SkinPresetsTests` → PASS.
- [ ] **Step 5: Commit** `skins: built-in preset pack with terminal themes and skin library`.

---

### Task 3: Overlay emits the terminal theme

**Files:**
- Modify: `macos/Sources/Features/Skins/SkinsRuntime.swift` (`SkinOverlay.configText`)
- Test: `macos/Tests/Skins/SkinOverlayTests.swift`

**Interfaces:**
- Consumes: Task 1 fields. Produces: overlay lines `palette = N=#rrggbb` (N 0–15), `cursor-color = #…`, `selection-background = #…`, each only when set, after `foreground`.

- [ ] **Step 1: Failing test** (append to `SkinOverlayTests`):

```swift
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
```

(The existing `colorOnly` and `withTile` tests prove nothing is emitted for skins without a theme.)

- [ ] **Step 2: Run** `macos/skins-test.sh SkinOverlayTests` → FAIL.
- [ ] **Step 3: Implement** in `configText`, directly after the `foreground` block:

```swift
        if let palette = applied.skin.palette {
            for (index, color) in palette.prefix(16).enumerated() {
                lines.append("palette = \(index)=\(color.hex)")
            }
        }
        if let cursor = applied.skin.cursor {
            lines.append("cursor-color = \(cursor.hex)")
        }
        if let selection = applied.skin.selectionBackground {
            lines.append("selection-background = \(selection.hex)")
        }
```

- [ ] **Step 4: Run** `macos/skins-test.sh SkinOverlayTests` → PASS. Also verify Ghostty accepts the lines: build the Debug app (`macos/build.nu …`), write the preset overlay text to `spike-shots/overlay-check.ghostty` and run `macos/build/Debug/Ghostty.app/Contents/MacOS/ghostty +validate-config --config-file=spike-shots/overlay-check.ghostty` → exit 0. Report the output.
- [ ] **Step 5: Commit** `skins: overlay emits preset palette, cursor and selection colors`.

---

### Task 4: SkinManager — library, locked folders, catalog

**Files:**
- Modify: `macos/Sources/Features/Skins/SkinManager.swift`
- Test: `macos/Tests/Skins/SkinManagerTests.swift`

**Interfaces:**
- Consumes: `SkinLibrary`, `SkinRarity` (Task 2).
- Produces: `var library: [SkinLibrary.Entry]` (computed from `config`); `func isLocked(_ id: UUID) -> Bool`; `func lockedSkinName(_ id: UUID) -> String?`; `func equippedName(_ id: UUID) -> String?` (the override's name); catalog `SkinEntry.rarity: String`, `PaneEntry.locked: Bool`. Behavior per spec §2.

- [ ] **Step 1: Update existing tests that assumed overrides beat mapped folders.** In `SkinManagerTests`, these tests currently put the pane in `\(root)/arca` (a mapped folder) and then preview/override. Change each to use `\(root)/Milo` (automatic) and replace expectations of `arca` as the base with `milo`, where `let milo = AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16)`:
  - `overridePersistsAcrossCdUntilReset`: start in Milo; after reset expect `effectiveSkin == milo` and the last applied skin to be `milo`; the "cd to plain keeps override" step stays.
  - `previewAndCancel`: base `milo` (texture-preview keeps `milo.background`; after cancel expect `milo`).
  - `previewExpires`: base `milo`.
  - `colorOverrideRecomputesBuiltinAccent`: start in Milo.
  - `writesCatalog`: its skin-name assertion becomes `#expect(skins?.map { $0["name"] } == ["neon-arcade", "sunset-drive", "mint-protocol", "deep-dive", "lava-rush", "bubble-pop", "arca", "prod"])` (built-ins now listed first; decode skins as `[[String: String]]` — every field incl. `rarity` is a string). Start in Milo; expected pane entry `["skin": "prod", "source": "override", "background": "#3a0f14", "locked": false]` — decode the pane as `[String: Any]` and compare fields individually since `locked` is a Bool.
  - `catalogUpdatesWhenPreviewExpires`: start in Milo; after expiry expect skin `"Milo"`, source `"auto"`, `locked == false`.
  - `rejectsUnknownNames`: keep in arca but it now also passes trivially; move it to Milo so it still tests name rejection.
  Keep every other test unchanged. Add `prod`/`arca` config as today.

- [ ] **Step 2: New failing tests** (append):

```swift
    @Test func lockedFolderIgnoresPreviewAndSet() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        #expect(m.isLocked(id))
        #expect(m.lockedSkinName(id) == "arca")
        let calls = h.calls.count
        m.handle(SkinRequest(op: .preview, skin: "prod"), for: id)
        m.handle(SkinRequest(op: .set, skin: "prod"), for: id)
        m.setPreview(id, prod)
        m.setOverride(id, prod)
        #expect(m.effectiveSkin(id) == arca)
        #expect(m.panes[id]?.override == nil)
        #expect(h.calls.count == calls)
        #expect(m.sourceLabel(id) == "Locked: arca")
    }

    @Test func overrideSurvivesLockedFolder() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .set, skin: "prod"), for: id)
        m.pwdChanged(id, pwd: "\(root)/arca/app")
        #expect(m.effectiveSkin(id) == arca)
        #expect(m.equippedName(id) == "prod")
        m.pwdChanged(id, pwd: "\(root)/plain")
        #expect(m.effectiveSkin(id) == prod)
    }

    @Test func resetStillWorksWhileLocked() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .set, skin: "prod"), for: id)
        m.pwdChanged(id, pwd: "\(root)/arca")
        m.handle(SkinRequest(op: .reset), for: id)
        m.pwdChanged(id, pwd: "\(root)/plain")
        #expect(m.effectiveSkin(id) == nil)
    }

    @Test func requestsCanNameBuiltinPresets() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .set, skin: "neon-arcade"), for: id)
        #expect(m.effectiveSkin(id)?.palette?.count == 16)
        #expect(h.calls.last?.1?.skin.name == "neon-arcade")
    }

    @Test func requestUsesShadowedPreset() {
        var cfg = config
        cfg.skins["neon-arcade"] = Skin(name: "neon-arcade", background: RGB(hex: "#000000")!, foreground: nil,
                                        accent: RGB(hex: "#ffffff")!, texture: .none, textureOpacity: 0.16)
        let h = Harness()
        let m = SkinManager(config: cfg, textures: TextureStore(cacheDir: URL(fileURLWithPath: root).appendingPathComponent("cache")),
                            catalogURL: nil, home: "/nonexistent-home", now: { h.clock },
                            apply: { id, a in h.calls.append((id, a)); return true })
        let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .set, skin: "neon-arcade"), for: id)
        #expect(m.effectiveSkin(id)?.background == RGB(hex: "#000000"))
        #expect(m.effectiveSkin(id)?.palette == nil)
    }

    @Test func catalogListsLibraryAndLockedPanes() throws {
        let h = Harness()
        let url = URL(fileURLWithPath: root).appendingPathComponent("state/catalog.json")
        let m = makeManager(h, catalog: url); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let skins = object?["skins"] as? [[String: String]]
        #expect(skins?.first(where: { $0["name"] == "neon-arcade" })?["rarity"] == "legendary")
        #expect(skins?.first(where: { $0["name"] == "arca" })?["rarity"] == "project")
        let pane = (object?["panes"] as? [String: [String: Any]])?[id.uuidString]
        #expect(pane?["locked"] as? Bool == true)
        #expect(pane?["source"] as? String == "config")
        #expect(pane?["skin"] as? String == "arca")
    }
```

- [ ] **Step 3: Run** `macos/skins-test.sh SkinManagerTests` → new tests FAIL (and edited ones may fail).

- [ ] **Step 4: Implement** in `SkinManager.swift`:

  - Add queries:

```swift
    /// Built-in presets merged with skins.toml skins (config shadows built-ins).
    var library: [SkinLibrary.Entry] { SkinLibrary.entries(config: config) }

    /// A folder mapped in skins.toml always shows its mapped skin (spec §2).
    func isLocked(_ id: UUID) -> Bool { lockedSkinName(id) != nil }

    func lockedSkinName(_ id: UUID) -> String? {
        guard case .configured(let name)? = panes[id]?.source, config.skins[name] != nil else { return nil }
        return name
    }

    /// The pane's sticky pick, kept even while a locked folder hides it.
    func equippedName(_ id: UUID) -> String? { panes[id]?.override?.name }
```

  - `effectiveSkin`: `guard let pane = panes[id] else { return nil }; if let locked = lockedSkinName(id) { return config.skins[locked] }; return pane.preview ?? pane.override ?? autoSkin(for: pane.source)`.
  - `handle(_:for:)`: at the top of the `.preview` and `.set` cases add `if isLocked(id) { Ghostty.logger.debug("skins: ignored \(request.op.rawValue) in a locked folder"); return }`. `.cancel`/`.reset` unchanged.
  - `setPreview` and `setOverride`: at the top, `if skin != nil, isLocked(id) { return }`.
  - `sourceLabel`: first line after the guard: `if let locked = lockedSkinName(id) { return "Locked: \(locked)" }`.
  - `sourceKind`: first line after the guard: `if isLocked(id) { return "config" }`.
  - `skin(from:base:)`: replace both `config.skins[...]` lookups with `SkinLibrary.skins(config: config)[...]` (compute once at the top: `let library = SkinLibrary.skins(config: config)`).
  - `skin(from:base:)` background branch: recompute the accent only for skins without a theme: `if case .builtin = skin.texture, skin.palette == nil { skin.accent = Skin.defaultAccent(for: background) }`.
  - Catalog: `SkinEntry` gains `let rarity: String`; `PaneEntry` gains `let locked: Bool`. Build skins from `library`: `library.map { Catalog.SkinEntry(name: $0.skin.name, background: $0.skin.background.hex, texture: Self.textureName($0.skin.texture), rarity: $0.rarity.rawValue) }` (keep library order; drop the old sort). Pane entries: `.init(skin: skin.name, source: sourceKind(id), background: skin.background.hex, locked: isLocked(id))`.
  - Update the class doc comment's layer list to the spec §2 order.

- [ ] **Step 5: Run** `macos/skins-test.sh SkinManagerTests` then the full `macos/skins-test.sh` → `** TEST SUCCEEDED **`.
- [ ] **Step 6: Commit** `skins: mapped folders lock their skin; library-backed requests; catalog rarity/locked`.

---

### Task 5: Saved colors store

**Files:**
- Create: `macos/Sources/Features/Skins/SavedColorsStore.swift`
- Modify: `macos/Sources/Features/Skins/SkinsRuntime.swift` (add `let savedColors: SavedColorsStore`, created in `init` with `Self.configDir.appendingPathComponent("state/saved-colors.json")`)
- Test: `macos/Tests/Skins/SavedColorsStoreTests.swift`

**Interfaces:**
- Produces: `@MainActor final class SavedColorsStore: ObservableObject { static let maxColors = 24; @Published private(set) var colors: [RGB]; init(fileURL: URL?); func contains(_: RGB) -> Bool; func add(_: RGB); func remove(_: RGB) }`; `SkinsRuntime.shared.savedColors`.

- [ ] **Step 1: Failing tests:**

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SavedColorsStoreTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("skins-saved-\(UUID().uuidString)/saved-colors.json")
    }

    @Test func addPersistsAndDedupes() {
        let url = tempFile()
        let store = SavedColorsStore(fileURL: url)
        store.add(RGB(hex: "#2a0f3d")!)
        store.add(RGB(hex: "#2a0f3d")!)
        store.add(RGB(hex: "#101010")!)
        #expect(store.colors.map(\.hex) == ["#2a0f3d", "#101010"])
        #expect(SavedColorsStore(fileURL: url).colors.map(\.hex) == ["#2a0f3d", "#101010"])
    }

    @Test func removePersists() {
        let url = tempFile()
        let store = SavedColorsStore(fileURL: url)
        store.add(RGB(hex: "#2a0f3d")!)
        store.remove(RGB(hex: "#2a0f3d")!)
        #expect(SavedColorsStore(fileURL: url).colors.isEmpty)
    }

    @Test func capsAtMaxKeepingNewest() {
        let store = SavedColorsStore(fileURL: tempFile())
        for i in 0..<30 { store.add(RGB(r: UInt8(i), g: 0, b: 0)) }
        #expect(store.colors.count == SavedColorsStore.maxColors)
        #expect(store.colors.first == RGB(r: 6, g: 0, b: 0))
        #expect(store.colors.last == RGB(r: 29, g: 0, b: 0))
    }

    @Test func malformedFileLoadsValidEntries() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"version":1,"colors":["#ff0000","nope","#FF0000","#00ff00"]}"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(SavedColorsStore(fileURL: url).colors.map(\.hex) == ["#ff0000", "#00ff00"])
        try "garbage".write(to: url, atomically: true, encoding: .utf8)
        #expect(SavedColorsStore(fileURL: url).colors.isEmpty)
    }
}
#endif
```

- [ ] **Step 2: Run** `macos/skins-test.sh SavedColorsStoreTests` → FAIL.
- [ ] **Step 3: Implement** `SavedColorsStore.swift`:

```swift
#if os(macOS)
import Combine
import Foundation

/// Background colors the user saved from the picker's "Any color" row
/// (spec §6). Stored in state/saved-colors.json, never in skins.toml.
@MainActor
final class SavedColorsStore: ObservableObject {
    static let maxColors = 24

    @Published private(set) var colors: [RGB] = []
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    func contains(_ color: RGB) -> Bool { colors.contains(color) }

    func add(_ color: RGB) {
        guard !colors.contains(color) else { return }
        colors.append(color)
        if colors.count > Self.maxColors { colors.removeFirst(colors.count - Self.maxColors) }
        save()
    }

    func remove(_ color: RGB) {
        colors.removeAll { $0 == color }
        save()
    }

    private struct File: Codable {
        var version: Int
        var colors: [String]
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            colors = []
            return
        }
        var unique: [RGB] = []
        for color in file.colors.compactMap(RGB.init(hex:)) where !unique.contains(color) {
            unique.append(color)
        }
        colors = Array(unique.suffix(Self.maxColors))
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(File(version: 1, colors: colors.map(\.hex)))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Ghostty.logger.warning("skins: failed to save colors: \(String(describing: error))")
        }
    }
}
#endif
```

  In `SkinsRuntime`: add `let savedColors: SavedColorsStore` and in `init` (before other stored-property use) `self.savedColors = SavedColorsStore(fileURL: Self.configDir.appendingPathComponent("state/saved-colors.json"))`.

- [ ] **Step 4: Run** `macos/skins-test.sh SavedColorsStoreTests` → PASS; build the app.
- [ ] **Step 5: Commit** `skins: persist saved custom background colors`.

---

### Task 6: CLI — rarity, locked refusal

**Files:**
- Modify: `src/cli/skins/protocol.zig` (Catalog, new `lockedMessage`), `src/cli/skins.zig` (`.send`, `.picker`, `.list`)
- Test: in `src/cli/skins/protocol.zig`

**Interfaces:**
- Consumes: catalog `rarity` (per skin) and `locked` (per pane) from Task 4.
- Produces: `Catalog.SkinEntry.rarity: []const u8 = "project"`, `Catalog.PaneEntry.locked: bool = false`; `pub fn lockedMessage(catalog: Catalog, surface_id: []const u8, req: Request) ?[]const u8` returning `skins: this folder is locked to "<skin>" by skins.toml` when the pane is locked and `req.op` is `.set` or `.preview`, else null.

- [ ] **Step 1: Failing tests** (append to protocol.zig; follow the file's existing test style):

```zig
test "skins: lockedMessage" {
    const alloc = std.testing.allocator;
    const json =
        \\{"version":1,"skins":[{"name":"arca","background":"#12222b","texture":"rings","rarity":"project"}],
        \\ "textures":["dots"],
        \\ "panes":{"A":{"skin":"arca","source":"config","background":"#12222b","locked":true},
        \\          "B":{"skin":"Milo","source":"auto","background":"#16262d","locked":false}}}
    ;
    const parsed = try parseCatalog(alloc, json);
    defer parsed.deinit();
    const msg = lockedMessage(parsed.value, "A", .{ .op = .set, .skin = "arca" }).?;
    try std.testing.expectEqualStrings("skins: this folder is locked to \"arca\" by skins.toml", msg);
    try std.testing.expect(lockedMessage(parsed.value, "A", .{ .op = .reset }) == null);
    try std.testing.expect(lockedMessage(parsed.value, "B", .{ .op = .set, .skin = "arca" }) == null);
    try std.testing.expect(lockedMessage(parsed.value, "missing", .{ .op = .set, .skin = "arca" }) == null);
}

test "skins: catalog without rarity/locked still parses" {
    const alloc = std.testing.allocator;
    const json =
        \\{"version":1,"skins":[{"name":"a","background":"#000000","texture":"none"}],"textures":[],
        \\ "panes":{"A":{"skin":"a","source":"override","background":"#000000"}}}
    ;
    const parsed = try parseCatalog(alloc, json);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("project", parsed.value.skins[0].rarity);
    try std.testing.expect(!parsed.value.panes.map.get("A").?.locked);
}
```

- [ ] **Step 2: Run** `zig build test -Demit-macos-app=false -Dtest-filter="skins:"` → compile FAIL.
- [ ] **Step 3: Implement.**
  - `SkinEntry` add `rarity: []const u8 = "project",`; `PaneEntry` add `locked: bool = false,`.
  - Add, next to `validateAgainstCatalog` (reuse its static message buffer pattern):

```zig
/// Non-null when `req` would change the look of a pane whose folder is
/// locked by skins.toml (spec §2/§8). reset/cancel are always allowed.
pub fn lockedMessage(catalog: Catalog, surface_id: []const u8, req: Request) ?[]const u8 {
    if (req.op != .set and req.op != .preview) return null;
    const pane = catalog.panes.map.get(surface_id) orelse return null;
    if (!pane.locked) return null;
    return std.fmt.bufPrint(&validate_error_buf, "skins: this folder is locked to \"{s}\" by skins.toml", .{pane.skin}) catch
        "skins: this folder is locked by skins.toml";
}
```

  - `skins.zig` `.send`: inside `if (tryLoadCatalog(alloc)) |catalog| {`, before `validateAgainstCatalog`, add:

```zig
                if (protocol.lockedMessage(catalog, surface_id, req)) |msg| {
                    try stderr.print("{s}\n", .{msg});
                    return 1;
                }
```

  - `.picker`: after loading the catalog, if `catalog.panes.map.get(surface_id)` exists and `.locked`, print `skins: this folder is locked to "<skin>" by skins.toml — edit ~/.config/ghostty-skins/skins.toml to change it` to stdout and `return 0` (no TUI, no preview).
  - `.list`: print `name\tbackground\ttexture\trarity`.

- [ ] **Step 4: Run** the `skins:` filter → PASS; rebuild the xcframework and app (`zig build -Demit-macos-app=false -Doptimize=ReleaseFast` then `macos/build.nu …`).
- [ ] **Step 5: Commit** `cli/skins: refuse picks in locked folders; show rarity in list`.

---

### Task 7: New picker UI and chip

**Files:**
- Rewrite: `macos/Sources/Features/Skins/SkinPopoverView.swift`
- Modify: `macos/Sources/Features/Skins/SkinChipView.swift`

**Interfaces:**
- Consumes: `SkinManager.library/isLocked/lockedSkinName/equippedName/effectiveSkin/setPreview/setOverride/reset/thumbnailImage/configError/textureError/panes`, `SavedColorsStore`, `SkinsRuntime.configDir`, `SkinPresets.displayName`.
- Produces: `SkinPopoverView(surfaceID:manager:savedColors:onEquipped:)`.

- [ ] **Step 1: Rewrite `SkinPopoverView.swift`** with this content:

```swift
#if os(macOS)
import AppKit
import SwiftUI

/// Lostty's skin picker (spec §7): Presets / Custom, live preview, Equip.
struct SkinPopoverView: View {
    let surfaceID: UUID
    @ObservedObject var manager: SkinManager
    @ObservedObject var savedColors: SavedColorsStore
    var onEquipped: (String) -> Void

    private enum Tab: Hashable { case presets, custom }

    @State private var tab: Tab = .presets
    @State private var draft: Skin?
    @State private var committed = false
    @State private var hex = ""

    private static let panel = Color(red: 0.09, green: 0.09, blue: 0.14)
    private static let card = Color.white.opacity(0.06)

    private var base: Skin { manager.effectiveSkin(surfaceID) ?? Skin.fallback }
    private var current: Skin { draft ?? base }
    private var accent: Color { Color(rgb: current.accent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let locked = manager.lockedSkinName(surfaceID) {
                lockedCard(locked)
            } else {
                Picker("", selection: $tab) {
                    Text("Presets").tag(Tab.presets)
                    Text("Custom").tag(Tab.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if tab == .presets { presetGrid } else { customPanel }
                problems
                footer
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(Self.panel)
        .environment(\.colorScheme, .dark)
        .onAppear { hex = current.background.hex }
        .onDisappear { if !committed { manager.setPreview(surfaceID, nil) } }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Skins").font(.system(size: 20, weight: .bold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var subtitle: String {
        if let locked = manager.lockedSkinName(surfaceID) { return "Locked · \(locked) from skins.toml" }
        let pwd = manager.panes[surfaceID]?.pwd ?? ""
        let home = NSHomeDirectory()
        return pwd.hasPrefix(home) ? "This pane · ~" + pwd.dropFirst(home.count) : "This pane · \(pwd)"
    }

    private func lockedCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(accent)
                Text("Locked to \(name)").font(.system(size: 14, weight: .semibold))
            }
            Text("This folder is mapped in skins.toml, so it always shows its own skin. Edit the [[match]] entry to change it; your picks still apply in other folders.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Reveal skins.toml in Finder") {
                let file = SkinsRuntime.configDir.appendingPathComponent("skins.toml")
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Self.card))
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(manager.library, id: \.skin.name) { entry in
                presetCard(entry)
            }
        }
    }

    private func presetCard(_ entry: SkinLibrary.Entry) -> some View {
        let skin = entry.skin
        let selected = current.name == skin.name
        let equipped = manager.equippedName(surfaceID) == skin.name
        let ring = Color(rgb: skin.accent)
        return Button { preview(skin) } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(Color(rgb: skin.background))
                    if let image = manager.thumbnailImage(for: skin) {
                        Image(decorative: image, scale: 2)
                            .resizable(resizingMode: .tile)
                            .opacity(min(1, skin.textureOpacity * 3))
                    }
                    Text("❯ _")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(ring)
                        .padding(10)
                    if equipped {
                        Text("EQUIPPED")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(8)
                    }
                }
                .frame(height: 64)
                .clipped()
                HStack(spacing: 6) {
                    Text(title(for: skin)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    rarityPill(entry.rarity)
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
            }
            .background(Self.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? ring : .clear, lineWidth: 2))
            .shadow(color: selected ? ring.opacity(0.45) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .help(title(for: skin))
    }

    private var customPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("BACKGROUND")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10), count: 8), alignment: .leading, spacing: 10) {
                ForEach(SkinPresets.all.map(\.skin.background), id: \.self) { color in swatch(color, removable: false) }
                ForEach(savedColors.colors, id: \.self) { color in swatch(color, removable: true) }
            }
            HStack(spacing: 10) {
                ColorPicker("", selection: colorBinding, supportsOpacity: false).labelsHidden()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Any color").font(.system(size: 13, weight: .semibold))
                    Text("Full color picker").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("#rrggbb", text: $hex)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 84)
                    .onSubmit { if let rgb = RGB(hex: hex.lowercased()) { setBackground(rgb) } }
                let saved = savedColors.contains(current.background)
                    || SkinPresets.all.contains { $0.skin.background == current.background }
                Button(saved ? "Saved" : "Save") { savedColors.add(current.background) }
                    .disabled(saved)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Self.card))
            sectionLabel("TEXTURE")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                textureTile(.none, label: "None")
                ForEach(BuiltinTexture.allCases, id: \.self) { texture in
                    textureTile(.builtin(texture), label: texture.rawValue.capitalized)
                }
            }
        }
    }

    private var problems: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = manager.configError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let error = manager.textureError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { reset() } label: {
                Text("Reset to project").font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            Button { equip() } label: {
                Text("Equip").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(onAccent)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(accent))
                    .shadow(color: accent.opacity(0.45), radius: 10)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(draft == nil)
            .opacity(draft == nil ? 0.5 : 1)
        }
    }

    // MARK: Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).kerning(0.5)
    }

    private func rarityPill(_ rarity: SkinRarity) -> some View {
        let style: (String, Color, Color) = switch rarity {
        case .legendary: ("LEGENDARY", Color(red: 1, green: 0.85, blue: 0.3), Color(red: 0.16, green: 0.1, blue: 0))
        case .epic: ("EPIC", Color(red: 0.7, green: 0.42, blue: 1), .white)
        case .rare: ("RARE", Color(red: 0.18, green: 0.7, blue: 1), Color(red: 0, green: 0.07, blue: 0.12))
        case .common: ("COMMON", Color.white.opacity(0.16), .white)
        case .project: ("PROJECT", .white, Color(red: 0.07, green: 0.13, blue: 0.17))
        }
        return Text(style.0)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(style.2)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(style.1))
    }

    private func swatch(_ color: RGB, removable: Bool) -> some View {
        Button { setBackground(color) } label: {
            Circle().fill(Color(rgb: color))
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(current.background == color ? accent : Color.white.opacity(0.14),
                                               lineWidth: current.background == color ? 3 : 1))
        }
        .buttonStyle(.plain)
        .help(color.hex)
        .overlay(alignment: .topTrailing) {
            if removable {
                Button { savedColors.remove(color) } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 14, height: 14).background(Circle().fill(.white))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .help("Remove \(color.hex)")
            }
        }
    }

    private func textureTile(_ texture: SkinTexture, label: String) -> some View {
        var sample = current
        sample.texture = texture
        let selected = current.texture == texture
        return Button { edit { $0.texture = texture } } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color(rgb: current.background))
                    if texture != .none, let image = manager.thumbnailImage(for: sample) {
                        Image(decorative: image, scale: 2).resizable(resizingMode: .tile).opacity(0.8)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(height: 34)
                Text(label).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Self.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func title(for skin: Skin) -> String {
        SkinPresets.all.contains { $0.skin.name == skin.name } ? SkinPresets.displayName(skin.name) : skin.name
    }

    private var onAccent: Color {
        let a = current.accent
        let luminance = 0.2126 * Double(a.r) + 0.7152 * Double(a.g) + 0.0722 * Double(a.b)
        return luminance > 140 ? Color(red: 0.04, green: 0.04, blue: 0.07) : .white
    }

    private func preview(_ skin: Skin) {
        committed = false
        draft = skin
        hex = skin.background.hex
        manager.setPreview(surfaceID, skin)
    }

    private func edit(_ change: (inout Skin) -> Void) {
        var skin = current
        skin.name = "custom"
        change(&skin)
        preview(skin)
    }

    private func setBackground(_ color: RGB) {
        edit { skin in
            skin.background = color
            if case .builtin = skin.texture, skin.palette == nil { skin.accent = Skin.defaultAccent(for: color) }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(rgb: current.background) },
            set: { newValue in
                guard let c = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                func byte(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
                setBackground(RGB(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent)))
            })
    }

    private func equip() {
        guard let draft else { return }
        committed = true
        manager.setOverride(surfaceID, draft)
        onEquipped(title(for: draft))
    }

    private func reset() {
        committed = true
        draft = nil
        manager.reset(surfaceID)
    }
}
#endif
```

- [ ] **Step 2: Update `SkinChipView.swift`.**
  - Add `@State private var flash: String?`.
  - In the label `HStack`, replace `Text(skin?.name ?? "skins")` with:

```swift
                if let flash {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    Text("Equipped").font(.system(size: 11, weight: .semibold))
                        .help(flash)
                } else {
                    Text(chipTitle(skin)).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
                if let id, manager.isLocked(id) {
                    Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                }
```

    and add the helper `private func chipTitle(_ skin: Skin?) -> String { guard let skin else { return "skins" }; return SkinPresets.all.contains { $0.skin.name == skin.name } ? SkinPresets.displayName(skin.name) : skin.name }`.
  - Change the popover content to:

```swift
                SkinPopoverView(
                    surfaceID: id, manager: manager, savedColors: SkinsRuntime.shared.savedColors,
                    onEquipped: { name in
                        showingPopover = false
                        flash = name
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { flash = nil }
                    }
                ).id(id)
```

    (keep the existing `.id(id)` comment block above it).

- [ ] **Step 3: Build** (`macos/build.nu …`) and run the full `macos/skins-test.sh` → both succeed. Fix any compile errors with the smallest change and list them in the report.
- [ ] **Step 4: E2E without screenshots:** launch the Debug build (`env -u GHOSTTY_RESOURCES_DIR -u GHOSTTY_BIN_DIR -u GHOSTTY_SHELL_FEATURES -u GHOSTTY_SKINS_SURFACE open -n <abs app path>`), open a window in `~/projectrepos/arca` and one in `~/projectrepos/Milo` via AppleScript; in the Milo pane run `skins set neon-arcade` (input text + separate `send key "enter"`), then confirm `~/.config/ghostty-skins/state/catalog.json` shows that pane as `neon-arcade`/override/locked false and the arca pane as arca/config/locked true, and that the Milo pane's overlay file under `~/Library/Caches/ghostty-skins/overlays/` contains 16 `palette =` lines. In the arca pane run `skins set neon-arcade > ~/projectrepos/ghostty-skins/spike-shots/e2e-locked.txt 2>&1; echo $? >> …` and confirm exit 1 + the locked message. Quit the app.
- [ ] **Step 5: Commit** `skins: new picker UI (presets, custom colors, locked state) and chip flash`.

---

### Task 8: Docs

**Files:** Modify `SKINS.md`.

- [ ] **Step 1:** Update SKINS.md: add a "Presets" section (the six ids, their rarity, and that they restyle palette/cursor/selection); document that folders mapped in `skins.toml` are locked (picker shows Locked; `skins set` exits 1 there; picks apply elsewhere and return when you leave); document saved colors (`state/saved-colors.json`, max 24); remove any mention of `texture_opacity` from the picker (the config key still works); update `skins list` columns (adds rarity).
- [ ] **Step 2: Commit** `docs: Lostty presets, locked folders, saved colors`.

(Controller, after the final review: user-permitted screenshots of the picker in an unlocked and a locked pane, `macos/install-skins.sh`, push.)
