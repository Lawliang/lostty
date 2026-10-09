# Lostty

A fork of [Ghostty](https://github.com/ghostty-org/ghostty) that gives every
pane a background color and texture based on the project it is in.

- `cd` into a project and the pane re-skins; leave and it reverts.
- Split panes are skinned independently.
- Git repos you have not configured get a stable automatic skin.
- Override any pane from the Skins icon in the sidebar or the `skins` command.

## Install

    macos/install-skins.sh      # builds and installs /Applications/Lostty.app

Requires Xcode (with the Metal Toolchain component:
`xcodebuild -downloadComponent MetalToolchain`), `brew install zig@0.15 nushell`.
It reads your normal Ghostty config.

## Configure

Copy `docs/skins/skins.example.toml` to `~/.config/ghostty-skins/skins.toml`.
Errors never break the terminal: the last good config stays active and the
Skins icon in the sidebar shows a yellow dot.

## Presets

Lostty ships with twelve built-in preset skins that restyle your background, text
color, texture, 16-color ANSI palette, cursor, and selection. Each preset has
a rarity label and a defined accent color.

The arcade pack:

- **neon-arcade** (legendary) — Bright magenta and cyan on a dark purple.
- **sunset-drive** (epic) — Warm orange and pink on a dark plum with scanlines.
- **mint-protocol** (rare) — Neon green and yellow on a dark teal.
- **deep-dive** (rare) — Bright cyan and purple on a dark blue.
- **lava-rush** (epic) — Warm orange and yellow on a dark brown with diagonal texture.
- **bubble-pop** (common) — Hot pink and yellow on a purple with sparkle texture.

The Olympian boon pack, each offered by a patron god:

- **thunderhead** (epic, Zeus) — Thunder gold on storm navy with lightning.
- **undertow** (rare, Poseidon) — Sea-foam on abyssal teal with tide lines.
- **bloodrite** (heroic, Ares) — Battle red on dried blood with blade marks.
- **heartsease** (common, Aphrodite) — Rose pink on dusk rose with petals.
- **silverbow** (legendary, Artemis) — Hunter green on night forest with a starfield.
- **stormsurge** (duo, Zeus & Poseidon) — Gold lightning over teal swells.

The Skins picker shows every skin as a boon you can choose. Use
`skins set <id>` to equip any preset. A skin defined in `skins.toml` with
the same name as a preset overrides it and appears in the picker tagged PROJECT.

## Folder Defaults

If your `skins.toml` maps a folder with `[[match]]`, a pane in that folder
shows its mapped skin by default. You can still change it from the picker or
with `skins set`, `skins color`, or `skins texture`. Overrides belong to the
pane, so a pick made in a mapped folder stays when you `cd` elsewhere, and a
pick made elsewhere carries into a mapped folder. `skins reset` drops the
override and brings the mapped skin back.

## Saved Colors

Click the Skins icon in the sidebar, then go to the Custom tab (the
terminal `skins` picker has no Custom tab). The "Any color" row lets you pick
any background color with a native color panel or type a hex code. Click Save
to add it to your saved swatches. Saved colors live in
`~/.config/ghostty-skins/state/saved-colors.json` and are shared across all
Lostty windows (max 24).

## Override

- Click the Skins icon in the sidebar on the right: the picker fills the
  terminal area. Pick a skin, color, or texture and it applies to the pane
  you were last in right away, and stays. Click the icon again (or the
  close button) to go back to the terminal. **Reset** undoes it.
- Or in any pane: `skins` (interactive picker), `skins set <name>`,
  `skins color '#3a0f14'`, `skins texture grid`, `skins opacity 0.5`,
  `skins reset`, `skins list` (shows name, background, texture, rarity), `skins current`.

Overrides last until reset or until the pane closes. zsh and bash get the
`skins` function from Ghostty's shell integration; other shells can run
`ghostty +skins`. In tmux, enable `set -g allow-passthrough on`.

## Known limitations

- Quick Terminal panes are not skinned.
- fish, nushell, and other non-zsh/bash shells do not get the `skins`
  shell function; run `ghostty +skins` directly instead.
- Launching Lostty from inside another Ghostty pane (e.g. via
  `open -a Lostty`, or double-clicking from within a terminal)
  inherits that parent app's `GHOSTTY_RESOURCES_DIR`, which breaks the
  `skins` shell function in every new pane. Launch it from Finder, the
  Dock, or Spotlight instead.

## Claude Trace

While Claude Code is working in a pane, a light ray races around that
pane's edge. The moment Claude finishes (or you interrupt it), the ray
disappears. If Claude finishes (or asks for permission) while you are in
another pane or app, that pane dims and shows **Ready for response** until
you look at it. Each preset has its own trace; panes without a skin get a
pink-and-cyan beam.

Codex works the same way: the trace runs while Codex works and stops when
it finishes or you interrupt it. Codex panes don't show **Ready for
response** while Codex waits for an approval, only when it finishes.

Each time Lostty opens, a notification in the top-right corner of the
window tells you about each installed agent (Claude, Codex) whose hooks
aren't set up. **Connect** adds Lostty's hooks to `~/.claude/settings.json`
or `~/.codex/hooks.json` (it saves a `.lostty-backup` of the file first).
Notifications fade after a few seconds; hovering keeps them. Codex asks you to approve
Lostty's hooks the first time it sees them. The hooks do nothing outside
Lostty. Manage them from **Lostty → Claude Integration…**, or run
`ghostty +claude-hooks install`, `remove`, `status` or `preview`.

Custom skins pick a trace in `skins.toml`:

    [skins.my-skin]
    background = "#101820"
    trace = "bolt"            # beam comet sunset datastream sonar ember bubbles
                              # bolt tide blade petal arrow tempest, or none
    trace_color = "#ff00aa"   # default: the skin's accent
    trace_color2 = "#00ffcc"  # default: accent2, or a lighter accent
    trace_speed = 1.5         # 0.25–4
    trace_length = 0.2        # 0.05–0.5

A skin with the same name as a preset keeps the preset's trace unless it
sets `trace`. `[defaults] trace = false` turns traces off. With Reduce
Motion on, the border glows gently instead of racing.

## Claude Usage Bar

A bar along the bottom of each window, as tall as the title bar and the
same color as it and the sidebar, shows in the terminal's font the focused
pane's Claude model, a block meter for the context with the tokens in the
window (to the nearest thousand, e.g. `50K`), and a block meter with a
percentage for one plan limit:

    ✳ Opus 5.5   Context ▓░░░░░░░░░ 50K   ·········   Session ▓░░░░░░░░░ 2%

You don't need `/context` or `/usage`, and the numbers read `0K` and `0%`
until Claude reports them. The limit meter tracks your current session (the
5-hour limit) by default. Click the bar to see every limit (current session,
weekly) and when it resets, and click one to track it in the bar instead.
Meters turn amber at 70% and red at 90%. When the focused pane has no
Claude session, the bar is empty; it appears when Claude starts.

The numbers come from Claude Code's status line: Connect (or
`ghostty +claude-hooks install`) sets `statusLine` in
`~/.claude/settings.json` to Lostty's `+claude-usage`, which prints
nothing. If you already have your own status line, Lostty leaves it alone
and the bar stays empty. Plan limits show for Pro and Max plans after
Claude's first reply. Claude Code doesn't share the weekly Fable limit, so
that row shows as unavailable.

## Updating from upstream Ghostty

See `UPGRADING.md`.
