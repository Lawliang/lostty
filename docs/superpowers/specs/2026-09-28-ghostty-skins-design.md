# Ghostty Skins — Design

Date: 2026-09-28
Status: Approved 2026-09-28 (rev. 2: CLI as `ghostty +skins`, in-repo TOML parser)
Base: Ghostty v1.3.1 (`332b2ae`), branch `skins`

## 1. Problem and goal

Many terminal windows are open at once across different projects, and it is
hard to tell at a glance which project a window or pane belongs to.

Goal: every Ghostty pane automatically shows a background color and texture
that identify its project, updates live as the shell changes directory, and
can be temporarily overridden from a title-bar UI or from a `skins` CLI.

Success criteria:

- A pane in `~/projectrepos/arca` (or any subdirectory) shows the Arca skin
  (ink `#12222b`, tiled Arca logo in `#46a2ff`) within ~1s of the `cd`.
- Leaving the project reverts the pane to the matching skin for its new
  directory (another project's skin, or the default look).
- Split panes in the same window are skinned independently.
- Unconfigured git repos get a distinct, stable automatic skin with no setup.
- A user can override any pane's skin from the title-bar chip or `skins`, and
  the override persists until reset or the pane closes.

## 2. Feasibility (verified)

A throwaway spike on v1.3.1 (patch kept at `spike-shots/spike-hook.patch`,
not committed) confirmed:

- `ghostty_surface_update_config` applies `background`, `foreground` and
  `background-image*` to a single surface.
- The macOS `pwdChanged` action fires on every `cd` via Ghostty's zsh shell
  integration (OSC 7).
- Per-split skinning works; revert on leaving the directory works.
- Build: Zig 0.15.2, Nushell, Xcode 26.3 with the Metal Toolchain component,
  `zig build -Demit-macos-app=false -Dxcframework-target=native`, then
  `macos/build.nu`.
- The Ghostty config path is derived from the compile-time
  `build_config.bundle_id` (`src/build_config.zig:58`), so changing the app's
  bundle identifier keeps reading the user's existing Ghostty config.

## 3. Decisions

| Topic | Decision |
|---|---|
| Delivery | Personal fork of Ghostty, not an external overlay tool |
| Override UI | Title-bar color chip + popover, and a `skins` CLI |
| `skins` with no args | Interactive TUI picker with live preview |
| Override lifetime | Until `skins reset` / Reset button, or the pane closes |
| Project definition | Central config + automatic skins for unlisted git repos |
| Branded textures | Generated from a logo file (SVG/PNG) + accent color |
| Config format | TOML subset, parsed by a small in-repo Swift parser (no third-party dependency, no Xcode package edits) |
| CLI → app transport | `OSC 1337 ; SetUserVar=GHOSTTY_SKIN=<base64 JSON>` |
| CLI implementation | `ghostty +skins` action in Zig (vaxis TUI, modeled on `+list-themes`), exposed as `skins` by a shell-integration function |
| CLI data source | `catalog.json` written by the app; the CLI never parses TOML |

Out of scope: Linux/GTK, menu-bar overview of all terminals, "save override
as project default", non-Ghostty terminals, chip with hidden title bar.

## 4. Architecture

New code lives in new files. Existing upstream files receive small hooks only.

### 4.1 Swift components (`macos/Sources/Features/Skins/`)

1. **SkinConfig** — loads and validates
   `~/.config/ghostty-skins/skins.toml`; watches the file and reloads on
   save. On a parse or validation error it keeps the last good config and
   exposes the error for the UI.
2. **ProjectResolver** — maps a working directory to a skin source:
   (1) longest configured `[[match]].path` that equals or is an ancestor of
   the directory, compared by path components after `~` expansion and symlink
   resolution; else (2) the enclosing git root (nearest ancestor containing
   `.git`) → automatic skin; else (3) none (user's normal look).
3. **AutoSkin** — deterministic skin from a repo name: a stable hash selects a
   hue at fixed dark lightness/low chroma (legible as a terminal background)
   and one built-in texture.
4. **TextureStore** — produces tile PNGs at 2x: renders a logo as a staggered
   tile in the accent color (the logo's shape is the set of pixels that differ
   from its background, so an opaque square favicon background drops out), or draws a built-in pattern
   (dots, grid, diagonal, noise, waves, …). Cached under
   `~/Library/Caches/ghostty-skins/`, keyed by a hash of inputs.
5. **SkinManager** — the only component that mutates surface appearance.
   Holds per-surface state with three layers; the first non-nil wins:
   `preview` (transient) → `override` (sticky) → `auto` (resolved from pwd).
   Applies the effective skin by building a config (user's default files +
   skin overlay) and calling `ghostty_surface_update_config`. Skips the call
   when the effective skin is unchanged. Re-applies all surfaces after an
   app-wide config reload and after a SkinConfig reload. Drops state for
   surfaces that no longer exist. Publishes changes for the UI and writes
   `~/.config/ghostty-skins/state/catalog.json` (skins, built-in textures,
   and each pane's current skin keyed by pane UUID) for the CLI.
6. **SkinChip + SkinPopover (SwiftUI)** — see §6.

### 4.2 Zig core change

7. Implement the `SetUserVar` key of OSC 1337 (currently parsed and
   discarded in `src/terminal/osc/parsers/iterm2.zig`). Surface it to the
   apprt as a new action carrying `name` and `value` (bounded length). The
   macOS app forwards `GHOSTTY_SKIN` values to SkinManager and ignores others.

### 4.3 `skins` CLI

8. A new Ghostty CLI action, `ghostty +skins` (`src/cli/skins.zig`), with a
   vaxis TUI modeled on `+list-themes`. The app binary's directory is already
   on every pane's `PATH` (`src/termio/Exec.zig`), and a `skins` shell
   function added by Ghostty's zsh and bash shell integration calls it. The
   CLI reads `catalog.json` for skin names and the current skin; it never
   parses TOML. Each pane gets `GHOSTTY_SKINS_SURFACE=<pane UUID>` in its
   environment so the CLI can find its own entry in the catalog.

### 4.4 Existing files touched

- `macos/Sources/Ghostty/Ghostty.App.swift` — call SkinManager from
  `pwdChanged`, from config reload, and from the new user-var action.
- Title-bar view(s) for the default and tabbed styles — host the chip.
- `src/terminal/osc/parsers/iterm2.zig`, stream handler, apprt action enum,
  `include/ghostty.h` — SetUserVar plumbing.
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` — inject
  `GHOSTTY_SKINS_SURFACE` into each new surface's environment.
- `macos/Sources/Features/Terminal/BaseTerminalController.swift` — tell the
  window's chip which surface is focused.
- `src/cli/ghostty.zig` — register the `+skins` action.
- `src/shell-integration/{zsh,bash}` — define the `skins` function.
- `macos/Ghostty-Info.plist` / build settings — name, bundle ID, Sparkle off.

## 5. Configuration

`~/.config/ghostty-skins/skins.toml` (optional; absent file = automatic
skins only):

```toml
[defaults]
texture_opacity = 0.16      # 0–1
auto = true                 # automatic skins for unlisted git repos

[skins.arca]
background = "#12222b"
foreground = "#eaf3ff"      # optional
accent     = "#46a2ff"      # logo stroke color
logo       = "~/projectrepos/arca-labs/website/assets/favicon.svg"
# texture  = "grid"         # built-in pattern instead of a logo

[skins.prod]                # unbound skin, used for overrides
background = "#3a0f14"
texture    = "diagonal"

[[match]]
path = "~/projectrepos/arca"
skin = "arca"

[[match]]
path = "~/projectrepos/arca-labs"
skin = "arca"
```

Rules:

- A skin has `background` (required), optional `foreground`, and at most one
  of `logo` (+ `accent`, required with `logo`) or `texture`. Neither means no
  texture. Optional per-skin `texture_opacity` overrides the default.
- Matching is by path component: `~/projectrepos/arca-labs` never matches
  `~/projectrepos/arca`.
- Unknown keys, bad colors, missing logo files, or unknown skin references
  are validation errors (whole file rejected; last good config kept).

## 6. User interfaces

### 6.1 Title-bar chip and popover

- Pill at the leading edge of the title: color swatch, tiny texture sample,
  label (skin or repo name). An override shows a small dot; a config error
  shows a warning dot.
- Reflects the focused surface; follows focus between splits.
- Popover: source line (`Config: arca` / `Auto: Milo` / `Override`), named
  skins, 8 preset colors + color picker, texture thumbnails (built-ins, named
  skins' logos, None), opacity slider, "Reset to project". Hovering or
  dragging previews live; committing sets the override on the focused
  surface; closing without committing cancels the preview.
- Supported title-bar styles: default and tabs. Hidden title bar: no chip.

### 6.2 `skins` CLI

- `skins` — full-screen TUI list: named skins, built-in textures, Reset.
  ↑/↓ sends `preview`; Enter sends `set`; Esc / Ctrl-C / SIGTERM sends
  `cancel` and restores the terminal. If the process dies without sending
  `cancel`, the preview is still dropped when any later `set`/`reset`/`cancel`
  arrives, and SkinManager expires a preview older than 60s with no update.
- `skins set <name>`, `skins color <#hex>`, `skins texture <name|none>`,
  `skins opacity <0-1>`, `skins reset`, `skins list`, `skins current`.
- Exit non-zero with a message when not running inside Ghostty Skins
  (`GHOSTTY_SKINS_SURFACE` unset) or on invalid input.
- Shell function coverage: zsh and bash. fish/nushell users can run
  `ghostty +skins` directly.

### 6.3 Wire protocol

`ESC ] 1337 ; SetUserVar=GHOSTTY_SKIN=<base64(JSON)> BEL`

```json
{"v":1,"op":"preview|set|cancel|reset","skin":"arca",
 "background":"#rrggbb","texture":"grid|<skin-name>|none","opacity":0.2}
```

Security rule: terminal-originated messages may reference only named skins
from the user's config, built-in texture names, colors, and opacity. They can
never carry file paths. Unknown fields, unknown names, or malformed payloads
are logged and ignored. Payload size is capped (4 KiB).

tmux: the CLI wraps the sequence in tmux passthrough when `$TMUX` is set;
requires `allow-passthrough on`. Documented, not otherwise handled.

## 7. Error handling

- Config errors: keep last good config, warning dot on chip with message in
  the popover; never block terminal use.
- Texture generation failure (unreadable logo): skin applies color only;
  error surfaced in popover.
- `ghostty_surface_update_config` is called only on the main thread.
- Invalid CLI messages: ignored, logged at debug level.

## 8. Fork maintenance and distribution

- App name "Ghostty Skins", bundle ID `com.lawliang.ghostty-skins`; installs
  beside official Ghostty. Reads the existing Ghostty config (§2).
- Sparkle auto-update disabled.
- Git: branch `skins` from tag `v1.3.1`; remote `upstream` =
  `ghostty-org/ghostty`. `UPGRADING.md` lists every touched upstream line.
  Upgrade = fetch new tag, merge into `skins`, resolve hooks, rebuild, test.
- Install script: Release build, ad-hoc codesign, copy to `/Applications`.
- Publishing a GitHub fork is deferred to the user.

## 9. Testing

- Zig: unit tests for SetUserVar parsing (valid, malformed, oversized),
  via `zig build test -Dtest-filter=...`.
- Swift (`macos/Tests`): ProjectResolver (longest match, component
  boundaries, symlinks, git roots), SkinConfig (valid, invalid → last good,
  `~` expansion), AutoSkin determinism, SkinManager layering / reset /
  reapply-after-reload / close cleanup, protocol validation rejecting paths
  and unknown names.
- CLI: message encoding per subcommand; cancel on Esc, Ctrl-C and SIGTERM.
- End-to-end: scripted via the fork's AppleScript support (panes in `arca`,
  an unconfigured repo, and `~`; `cd` transitions; `skins set`); screenshots
  require temporary Screen Recording permission, requested each time.
- Lint: `swiftlint lint --strict` per upstream guidance.

## 10. Open items to verify during implementation

- NSImage SVG rendering fidelity for logo tiles on the target macOS; fall back
  to rasterizing via WebKit or requiring PNG if inadequate.
- Where exactly the chip mounts in each supported title-bar style.
- Whether `ghostty_surface_update_config` resets any runtime state beyond
  colors (e.g. program-set OSC colors) in ways users would notice.
