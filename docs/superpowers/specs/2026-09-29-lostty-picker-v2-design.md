# Lostty Picker v2 — Design

Date: 2026-09-29
Status: Draft, awaiting review
Builds on: `2026-09-28-ghostty-skins-design.md` (rev 2) and the shipped app
Visual reference: the "Lostty Skin Picker" design artifact (interactive mockup)

## 1. Goal

Replace the skin popover with a modern, iOS-clean, vibrant picker; ship a
built-in pack of gamified presets that restyle the whole terminal; let users
pick any background color and save it; and make folders mapped in
`skins.toml` always show their mapped skin.

Success criteria:

- In a folder matched by `[[match]]` in `skins.toml`, the pane always shows
  that skin; the picker shows a Locked state; `skins set/color/texture`
  there exits 1 with a clear message.
- Everywhere else (automatic git-repo skins, plain folders) the user can
  preview and equip any preset or custom look.
- Built-in presets change background, foreground, texture, the 16-color
  ANSI palette, cursor and selection colors.
- Custom tab: preset swatches, saved swatches, any color (native color
  panel + hex field) with Save-to-swatches, texture grid.
- No texture-intensity control in the UI.

## 2. Priority order (replaces spec rev 2 §6.1 layering)

For a pane, first match wins:

1. **Mapped skin** — the pane's folder resolves to `.configured(name)` via
   `[[match]]`. Locked: previews and overrides are ignored for display.
2. **Preview** (picker browsing / `skins` TUI).
3. **Override** (Equip / `skins set|color|texture`), until Reset or the
   pane closes.
4. **Automatic** git-repo skin.
5. Default look.

An override set while unlocked is kept when the pane enters a mapped folder
and shows again when it leaves. Requests that arrive while locked
(`preview`, `set`) are rejected and not stored; `cancel` and `reset` still
clear state. `catalog.json` pane entries gain `"locked": true|false`; the
reported `skin`/`source` are the effective (mapped) ones.

## 3. Built-in preset pack

Shipped in code (`SkinPresets.swift`), not in `skins.toml`:

| id | Name | Rarity | bg | fg | accent | accent2 | texture |
|---|---|---|---|---|---|---|---|
| neon-arcade | Neon Arcade | legendary | #120a2a | #f3ecff | #ff3df2 | #28e7ff | grid |
| sunset-drive | Sunset Drive | epic | #1c0b24 | #ffe9f5 | #ff7a3d | #ff4fa3 | scanlines |
| mint-protocol | Mint Protocol | rare | #04140f | #d8ffe9 | #2cff9a | #b6ff3b | dots |
| deep-dive | Deep Dive | rare | #041a2e | #dff4ff | #25c4ff | #9b87ff | waves |
| lava-rush | Lava Rush | epic | #1d0806 | #fff0e8 | #ff5a2c | #ffc53d | diagonal |
| bubble-pop | Bubble Pop | common | #230a24 | #ffeefe | #ff6ad5 | #ffd84d | sparkle |

Each preset also carries a hand-tuned 16-entry palette (ANSI 0–15), a cursor
color (= accent) and a selection background (accent at ~30% over bg),
defined as literal hex values in `SkinPresets.swift`. Palette rules: 0/8 are
bg-derived darks/greys, 7/15 are fg-derived lights, and red, green, yellow,
blue, magenta, cyan (1–6, 9–14) are vivid, readable on that preset's bg, and
lean toward its accents (e.g. Neon Arcade's magenta = accent, cyan = accent2).

- `skins.toml` skins join the picker grid with rarity **project** and no
  palette (unchanged behavior). A config skin whose name equals a built-in
  id shadows it.
- `rarity` is display-only.
- `catalog.json` `skins` includes built-ins; each entry gains `"rarity"`.
  `skins list`, `skins set <id>` and the terminal picker therefore include
  built-ins with no CLI protocol change.

## 4. Textures

Existing textures: dots, grid, diagonal, cross, waves, noise. Add
`scanlines`, `sparkle`, `rings` to `BuiltinTexture` and `TextureStore`
(seamless 220-px tiles). `AutoSkin` switches from `BuiltinTexture.allCases`
to an explicit list of the original six in their original order, so every
existing repo keeps its current automatic texture.

## 5. Terminal theme in the overlay

`Skin` gains optional `palette: [RGB]?` (16), `cursor: RGB?`,
`selectionBackground: RGB?`. `SkinOverlay.configText` emits, when present:
`palette = N=#rrggbb` (16 lines), `cursor-color = #…`,
`selection-background = #…`. Custom looks derived from a preset keep its
theme; custom looks derived from an automatic/default skin have none.

## 6. Saved colors

`SavedColorsStore` persists user-saved background colors in
`~/.config/ghostty-skins/state/saved-colors.json` (`{"version":1,"colors":["#rrggbb",…]}`),
deduplicated, max 24, shared by all windows, loaded at launch. Malformed file
→ treated as empty and rewritten on the next save. Never written into
`skins.toml`.

## 7. Picker UI (SwiftUI, replaces `SkinPopoverView`)

Matches the mockup:

- Header: "Skins", subtitle with the pane's folder, close button.
- Segmented control: Presets | Custom.
- **Presets**: 2-column cards — mini preview (bg + texture + accent prompt
  glyph), name, rarity pill (legendary gold, epic purple, rare blue, common
  grey, project white), accent-colored ring + glow when selected,
  EQUIPPED badge on the pane's current override/effective preset.
- **Custom**: BACKGROUND — preset background swatches then saved swatches
  (saved ones show an × to remove); "Any color" row with the native color
  panel (SwiftUI `ColorPicker`), a hex field (accepts `#rrggbb`), and
  Save / Saved (disabled when already present). TEXTURE — grid of all nine
  textures plus None, previewed in the current background.
- Footer: Reset to project · Equip (accent-filled). Browsing previews live;
  Equip sets the override; closing without Equip cancels the preview.
- Confirmation: the title-bar chip briefly shows "Equipped" with a check
  (no terminal overlay, so no new upstream hooks).
- **Locked state** (mapped folder): header subtitle "Locked · <skin> from
  skins.toml", a lock card explaining to edit `~/.config/ghostty-skins/skins.toml`
  (with a Reveal in Finder button), grid and Custom disabled, Equip hidden.
- Chip: unchanged placement/labels; shows a small lock glyph when locked.
- Thumbnails use `SkinManager.thumbnailImage(for:)` (in-memory; no disk
  writes during view updates).

## 8. CLI

- `skins set|color|texture` in a pane whose catalog entry has
  `"locked": true` → `skins: this folder is locked to "<skin>" by skins.toml`
  on stderr, exit 1. `skins reset` still allowed.
- The TUI picker shows a one-line locked notice and exits 0 without
  previewing when locked.

## 9. Error handling

- Unknown preset/texture names: rejected exactly as today.
- Palette on a skin with no palette: overlay omits palette lines, so the
  user's own Ghostty palette applies.
- Saved-colors write failure: logged; the color still applies for the session.

## 10. Testing

- SkinManager: locked folder ignores preview/set; override survives
  entering/leaving a mapped folder; reset/cancel while locked; catalog
  `locked` flag and effective source.
- Presets: lookup, config shadowing, catalog includes built-ins with rarity,
  palettes have 16 valid entries.
- Overlay: palette/cursor/selection lines emitted only when present.
- TextureStore: waves/sparkle/rings render seamless non-empty tiles;
  AutoSkin texture choice unchanged for sample repos.
- SavedColorsStore: add/dedupe/cap/remove/persist/malformed file.
- Zig CLI: locked catalog → set/color/texture exit 1 with message; reset ok.
- E2E (screenshots with user permission): picker in an unlocked and a
  locked pane; a preset applied with its palette visible in `ls --color`.
- Then install to `/Applications/Lostty.app` and push.

## 11. Out of scope

Editing presets in-app, custom accent/palette pickers, gameplay beyond
rarity labels, texture intensity UI, terminal-overlay toast.
