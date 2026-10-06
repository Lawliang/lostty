# Lostty Claude Trace — Design

Date: 2026-10-05
Status: Draft, awaiting review
Builds on: `2026-09-28-ghostty-skins-design.md`, `2026-09-29-lostty-picker-v2-design.md`
and the shipped skins feature

## 1. Goal

While Claude Code (the `claude` CLI) is working in a Lostty pane, a light
ray races around the inside edge of that pane, styled by the pane's skin.
When Claude finishes its turn, the trace closes its loop and flashes once,
then fades. This is the first feature on a general Claude → Lostty channel
that later features (context/token meter, "needs you" state) will reuse.

Success criteria:

- Sending a prompt to `claude` in a Lostty pane starts that pane's trace;
  Claude finishing the turn plays the finish flash and stops the trace.
- If `claude` exits or crashes while busy, the trace fades without a flash
  and never stays stuck.
- Each of the 12 preset skins has its own trace style; unskinned panes and
  custom skins without a trace setting get the default `beam` style.
- Custom skins in `skins.toml` can pick any built-in style and tune its
  colors, speed and length.
- A friend who installs Lostty and uses Claude is offered the hook install
  once on first launch; accepting makes the trace work with no other setup.
- Claude itself is never modified, and the hooks are harmless outside
  Lostty, including after Lostty is uninstalled.

Out of scope for v1: "needs you" visual state, token/context meter, trace
previews in the picker, `skins trace` pane overrides, user-authored trace
styles (shaders/images), Quick Terminal panes, a shell-wrapper hook path.

## 2. Architecture

```
┌─ Claude CLI (stock) ───────────────────────────────────────────┐
│ UserPromptSubmit ─► hook: busy                                  │
│ Stop             ─► hook: idle      (turn finished)             │
│ Notification     ─► hook: idle      (v1: waiting = stopped)     │
│ SessionEnd       ─► hook: exit                                  │
└──────────────┬─────────────────────────────────────────────────┘
               │ [ -n "$LOSTTY_SURFACE" ] && [ -x "$LOSTTY_BIN" ] && "$LOSTTY_BIN" +claude-state <event>; exit 0
               ▼
  ghostty +claude-state   (new CLI action)
     writes OSC 1337 SetUserVar=LOSTTY_CLAUDE=<base64 {"v":1,"state":"busy"}> to /dev/tty
               │
               ▼  existing path, unchanged: Zig OSC parser → set_user_var action → Ghostty.App.swift
  ClaudeRuntime.userVarChanged(view, name, value)   ◄── command_finished on that pane ⇒ "exited"
               │
               ▼
  ClaudeSessionState per pane: idle → busy → idle / exited
               │
               ▼
  TraceOverlay on that pane: races while busy, finish flash on busy → idle
```

Units, one job each:

1. **`+claude-state` CLI action (Zig).** Maps an event name to the
   `LOSTTY_CLAUDE` escape sequence (tmux DCS-wrapped when `$TMUX` is set)
   and writes it to `/dev/tty`. Claude Code runs hooks without a
   controlling terminal (verified 2026-10-05), so when `/dev/tty` fails it
   walks up the process tree (`ps -o ppid=,tty=`) to the nearest ancestor
   with a terminal, which is `claude` in the pane (or its tmux pane), and
   writes there. Mirrors `src/cli/skins.zig` and
   `src/cli/skins/protocol.zig`.
2. **Per-pane environment.** `SurfaceView_AppKit.swift` already sets
   `GHOSTTY_SKINS_SURFACE`; next to it Lostty also sets `LOSTTY_SURFACE`
   (the pane UUID) and `LOSTTY_BIN` (absolute path of the running Lostty
   binary). These are the hooks' "inside Lostty?" guard and binary lookup.
3. **`ClaudeRuntime` + `ClaudeSessionState` (Swift,
   `macos/Sources/Features/Claude/`).** Per-pane state machine with no UI
   code. `Ghostty.App.swift`'s `userVarChanged` dispatches `LOSTTY_CLAUDE`
   here, alongside the existing `GHOSTTY_SKIN` dispatch; the existing
   `command_finished` action for a pane forces `exited`.
4. **`TraceOverlay` (Swift).** Draws one pane's trace from its state and
   resolved trace config.
5. **Hook installer.** `ghostty +claude-hooks install|remove|status` (Zig)
   plus the first-launch prompt and menu item (Swift). See §5.

Skins and Claude stay decoupled: the trace overlay asks the skins side for
the pane's resolved trace config; neither runtime otherwise depends on the
other.

### 2.1 Wire format

User var name `LOSTTY_CLAUDE`; value is base64 of compact JSON:

```json
{"v":1,"state":"busy"}
```

`state` is one of `busy`, `idle`, `exit`. Event → state mapping in the
hook commands: `UserPromptSubmit` → `busy`, `Stop` → `idle`,
`Notification` → `idle`, `SessionEnd` → `exit`. Messages carry no queue
semantics; the latest message wins. Unknown `v` or `state` values are
ignored, so older Lostty builds tolerate newer hooks. Later features add
fields (e.g. tokens) under the same name.

## 3. Trace styles and skins

### 3.1 Built-in styles

| Style | Preset | Look |
|---|---|---|
| `beam` | default | Clean light ray with a soft fading tail |
| `comet` | neon-arcade | Magenta head, cyan glowing tail |
| `sunset` | sunset-drive | Orange→pink gradient sweep with scanline banding |
| `datastream` | mint-protocol | Segmented green packets with yellow leading bits |
| `sonar` | deep-dive | Cyan pulse that rings outward slightly as it travels |
| `ember` | lava-rush | Molten orange head shedding yellow embers |
| `bubbles` | bubble-pop | A chain of pink dots popping into yellow sparkles |
| `bolt` | thunderhead | Forked gold lightning that jumps ahead in strikes |
| `tide` | undertow | Sea-foam wave that swells and recedes as it moves |
| `blade` | bloodrite | Sharp red slash with orange sparks |
| `petal` | heartsease | Soft rose glow trailing drifting petals |
| `arrow` | silverbow | Thin silver-green streak with a starry tail |
| `tempest` | stormsurge | Two heads: a gold bolt riding a teal wave |

Colors default to the skin's `accent` (primary) and `accent2` (secondary).
When a skin has no `accent2`, the secondary is the primary mixed 40% toward
white. Panes with no skin at all use Lostty's hologram pink `#ff7ad9` and
cyan `#7af0ff`.

### 3.2 Model

`Skin` gains a `trace: SkinTrace?` field:

```swift
enum BuiltinTrace: String, CaseIterable { case beam, comet, sunset, datastream, sonar,
    ember, bubbles, bolt, tide, blade, petal, arrow, tempest }

struct SkinTrace: Hashable {
    var style: BuiltinTrace?        // nil = "none" (disabled)
    var color: RGB?                 // nil = skin accent
    var color2: RGB?                // nil = accent2 / derived
    var speed: Double = 1           // 0.25...4
    var length: Double = 0.18       // 0.05...0.5, share of the perimeter
}
```

Each `SkinPreset` sets its style from the table above. A `Skin` with
`trace == nil` resolves to `beam` with default parameters.

### 3.3 skins.toml

```toml
[defaults]
trace = false                 # optional; turns traces off everywhere (default true)

[skins.my-skin]
background = "#101820"
trace = "bolt"                # any style name, or "none"
trace_color = "#ff00aa"       # optional
trace_color2 = "#00ffcc"      # optional
trace_speed = 1.5             # optional, 0.25–4
trace_length = 0.2            # optional, 0.05–0.5
```

- `SkinConfig.checkKeys` allows the new keys; `[defaults]` allows `trace`
  as a bool.
- A config skin that shadows a preset inherits the preset's trace style
  unless it sets `trace`; any `trace_*` keys it sets apply on top.
- Invalid values (unknown style, out-of-range numbers, bad hex) are config
  errors handled like today: last good config stays active, chip warns.

## 4. Drawing and animation

**Placement.** A SwiftUI overlay on each pane inside `SurfaceWrapper`
(`macos/Sources/Ghostty/Surface View/SurfaceView.swift`), above the
terminal, `allowsHitTesting(false)`, inset 1.5pt from the pane's edge so it
does not sit on split dividers. When the pane is idle (and not mid-flash)
the overlay is not in the view tree.

**Engine.** `TimelineView(.animation)` + `Canvas`, active only while
busy/finishing/fading.

- `EdgePath` turns the pane rect into one closed clockwise loop starting
  at the top-left corner. `sample(at: d)` returns position, tangent and
  inward normal for a distance `d` along the perimeter, wrapping around
  corners and past the end.
- `TraceStyleRenderer` protocol, one file per style under
  `macos/Sources/Features/Claude/Traces/`:
  `func draw(in: inout GraphicsContext, along: EdgePath, head: Double,
  time: Double, colors: TraceColors, length: Double, intensity: Double)`.
- Glow: additive blending (`.plusLighter`) plus a soft blur layer on the
  head.
- Speed: one lap takes 3s at `speed = 1` for a 1000pt perimeter, scaled so
  the head's linear speed is the same in any pane size, divided by
  `speed`.

**State → animation.**

| Transition | Visual |
|---|---|
| idle → busy | Fade in (0.2s) at the top-left corner; race |
| busy → idle | Finish flash: the head keeps moving while the tail stretches until it wraps the whole edge (0.4s), whole-border pulse (0.25s), fade out (0.8s) |
| busy during flash/fade | Cancel, resume racing; the head never jumps because it moves at the same speed during the flash |
| busy → exited | 0.3s fade, no flash |

**Reduce Motion** (`accessibilityReduceMotion`): no racing; the whole
border glows with a slow pulse (2s period) while busy. The finish flash
stays.

**Occlusion.** While the window's `occlusionState` lacks `.visible` or it
is minimized, the timeline is paused.

## 5. Hook installer

### 5.1 CLI: `ghostty +claude-hooks install | remove | status | preview`

Implemented in Zig (`src/cli/claude_hooks.zig`) because `std.json`'s
object map preserves key order, so a user's file keeps its layout apart
from the added entries; numbers are kept as written. Operates on
`~/.claude/settings.json`, following a symlink to the real file so dotfile
managers keep working.

Entry added under `hooks.<Event>` for each of `UserPromptSubmit`, `Stop`,
`Notification`, `SessionEnd`:

```json
{ "hooks": [{ "type": "command", "timeout": 5,
  "command": "[ -n \"$LOSTTY_SURFACE\" ] && [ -x \"$LOSTTY_BIN\" ] && \"$LOSTTY_BIN\" +claude-state busy; exit 0" }] }
```

(with `idle`/`idle`/`exit` for the other events). No paths are stored in
the file. Lostty identifies its entries as hook commands containing both
`+claude-state` and `LOSTTY_SURFACE`.

- **install:** missing file → created with only the hooks. Unparseable
  file → exit non-zero with the parse error, file untouched. Existing
  Lostty entries are removed and the current form is appended to each
  event's list; other entries are untouched. Before any write, the current file is copied to
  `settings.json.lostty-backup`. Writes go to a temp file in the same
  directory and are renamed over the original. Re-running is a no-op when
  already current (no write, no backup).
- **remove:** deletes only Lostty entries; drops matcher groups and event
  arrays left empty; drops `hooks` if it becomes empty. Same backup and
  atomic write.
- **preview:** prints the JSON that install adds, for the app's "Show
  changes" view.
- **status:** prints one of `installed` (all four current), `partial`
  (some missing or outdated form), `not-installed`, `unreadable`.

### 5.2 App prompt and menu (Swift)

- At launch, if `~/.claude` exists, status is `not-installed` or
  `partial` (an `unreadable` file is only reported from the menu), and the
  user has not answered the prompt for this hook version (UserDefaults
  `LosttyClaudeHooksPromptedVersion`), show a sheet: "Show a trace while
  Claude is working? Lostty will add 4 hooks to ~/.claude/settings.json."
  Buttons: **Install**, **Not now**, **Show changes** (reveals the exact
  JSON). `partial` shows **Update** wording instead.
- The app runs its own binary with `+claude-hooks` and shows any error
  text.
- Menu item **Lostty → Claude Integration…** shows status with
  Install/Update/Remove, regardless of earlier answers.
- Docs: a "Claude integration" section in `SKINS.md` covering what is
  added, the backup, removal and the manual command.

## 6. Error handling

| Situation | Behavior |
|---|---|
| Hook outside Lostty / Lostty uninstalled | Guard fails; hook exits 0; Claude shows nothing |
| `/dev/tty` unavailable (e.g. `claude -p` headless) | `+claude-state` exits 0 silently |
| Malformed or unknown `LOSTTY_CLAUDE` payload | Ignored with a debug log |
| `Stop` missing (interrupt, crash) | Verified 2026-10-05: Esc sends no `Stop` and no `Notification`. Claude titles the pane `✳ …` when idle and with a spinner while working, so a racing pane whose title stays `✳` for 2.5s fades out without a flash. `command_finished` → exited; next prompt → busy |
| Pane closes while busy | State and overlay discarded with the pane |
| Bad trace keys in skins.toml | Existing config-error path |
| settings.json unreadable / invalid JSON | Install refuses, shows error, file untouched |

## 7. Testing

- **Zig:** `+claude-state` encoding (plain and tmux-wrapped, each state);
  `+claude-hooks` on fixtures: missing file, empty object, existing user
  hooks on the same events, already installed, outdated Lostty entries,
  invalid JSON. Asserts key order preserved, idempotent install, remove
  touches only Lostty entries, status values.
- **Swift (`macos/Tests/Claude/`):** `ClaudeSessionState` transitions
  (busy→idle finish, busy→exited fade, re-busy during flash,
  `command_finished` override); payload decoding; `skins.toml` trace keys
  (defaults, ranges, `none`, `[defaults] trace = false`, shadowed presets
  inheriting style); `EdgePath` sampling (corners, wrap-around, tangents,
  inward normals).
- **Manual:** real Claude in single and split panes and in tmux; Esc
  interrupt; Reduce Motion; install prompt against a copy of a real
  settings file.
- **Visual:** a debug-build menu item runs a fake busy→idle cycle on the
  focused pane using its skin's trace; equip presets with `skins set` to
  review each style by eye.

## 8. Build order

1. Spike: confirm hooks can write `/dev/tty` and whether `Stop` fires on
   Esc interrupt (decides the quiet-output timeout).
2. `+claude-state` + per-pane env vars + `ClaudeRuntime` state machine.
3. `EdgePath`, overlay engine, `beam` and `bolt`, finish flash, debug
   preview item.
4. Trace config in `Skin`/`skins.toml`; preset assignments.
5. Remaining 11 styles.
6. `+claude-hooks` CLI, then the app prompt and menu item, then docs.
