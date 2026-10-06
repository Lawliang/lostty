# Lostty

A fork of [Ghostty](https://github.com/ghostty-org/ghostty) that gives every
pane a background color and texture based on the project it is in.

- `cd` into a project and the pane re-skins; leave and it reverts.
- Split panes are skinned independently.
- Git repos you have not configured get a stable automatic skin.
- Override any pane from the title-bar chip or the `skins` command.

## Install

    macos/install-skins.sh      # builds and installs /Applications/Lostty.app

Requires Xcode (with the Metal Toolchain component:
`xcodebuild -downloadComponent MetalToolchain`), `brew install zig@0.15 nushell`.
It reads your normal Ghostty config.

## Configure

Copy `docs/skins/skins.example.toml` to `~/.config/ghostty-skins/skins.toml`.
Errors never break the terminal: the last good config stays active and the
title-bar chip shows a warning.

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

The title-bar picker shows every skin as a boon you can choose. Use
`skins set <id>` to equip any preset. A skin defined in `skins.toml` with
the same name as a preset overrides it and appears in the picker tagged PROJECT.

## Locked Folders

If your `skins.toml` maps a folder with `[[match]]`, that folder's pane always
shows its mapped skin and cannot be overridden. The picker shows a Locked card
explaining that the folder is configured. `skins set`, `skins color`, and
`skins texture` exit with `skins: this folder is locked to "<skin>" by skins.toml` (exit 1);
`skins reset` still works. When you leave a locked folder, your previous override (if any)
returns.

## Saved Colors

Click the chip to open the title-bar picker, then go to the Custom tab (the
terminal `skins` picker has no Custom tab). The "Any color" row lets you pick
any background color with a native color panel or type a hex code. Click Save
to add it to your saved swatches. Saved colors live in
`~/.config/ghostty-skins/state/saved-colors.json` and are shared across all
Lostty windows (max 24).

## Override

- Click the chip at the right of the title bar: preview a skin, color, or
  texture (live), then **Equip** to keep it. **Reset** undoes it. The chip
  briefly shows "Equipped" after you apply.
- Or in any pane: `skins` (interactive picker), `skins set <name>`,
  `skins color '#3a0f14'`, `skins texture grid`, `skins opacity 0.5`,
  `skins reset`, `skins list` (shows name, background, texture, rarity), `skins current`.

Overrides last until reset or until the pane closes. zsh and bash get the
`skins` function from Ghostty's shell integration; other shells can run
`ghostty +skins`. In tmux, enable `set -g allow-passthrough on`.

## Known limitations

- The title-bar chip is not shown when `macos-titlebar-style = hidden`.
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
disappears. Each preset has its own trace; panes without a skin get a
pink-and-cyan beam.

On first launch Lostty offers to add four hooks to
`~/.claude/settings.json` (it saves `settings.json.lostty-backup` first).
The hooks do nothing outside Lostty. Manage them from
**Lostty → Claude Integration…**, or run `ghostty +claude-hooks install`,
`remove`, `status` or `preview`.

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

## Updating from upstream Ghostty

See `UPGRADING.md`.
