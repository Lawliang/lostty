# Lostty Skins

Lostty gives every pane a background color and texture based on the project
it is in.

- `cd` into a project and the pane re-skins; leave and it reverts.
- Split panes are skinned independently.
- Git repos you have not configured get a stable automatic skin.
- Override any pane from Skins in the bottom bar's apps (the 2x2 grid button) or the `skins` command.

## Install

    macos/install.sh --stable   # builds and installs /Applications/Lostty.app

Requires Xcode (with the Metal Toolchain component:
`xcodebuild -downloadComponent MetalToolchain`), `brew install zig@0.15 nushell`.
Its config lives in `~/.config/lostty/config`; an existing
`~/.config/ghostty/config` is still read.

## Configure

Copy `docs/skins/skins.example.toml` to `~/.config/lostty/skins/skins.toml`.
(Lostty still reads an older `~/.config/ghostty-skins/` folder.)
Errors never break the terminal: the last good config stays active and the
Skins icon in the bottom bar's apps shows a yellow dot.

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

Open Skins from the bottom bar's apps, then go to the Custom tab (the
terminal `skins` picker has no Custom tab). The "Any color" row lets you pick
any background color with a native color panel or type a hex code. Click Save
to add it to your saved swatches. Saved colors live in
`~/.config/lostty/skins/state/saved-colors.json` and are shared across all
Lostty windows (max 24).

## Override

- Click the 2x2 grid in the bottom bar, then Skins: the picker fills the
  terminal area. Pick a skin, color, or texture and it applies to the pane
  you were last in right away, and stays. Click the icon again (or the
  close button) to go back to the terminal. **Reset** undoes it.
- Or in any pane: `skins` (interactive picker), `skins set <name>`,
  `skins color '#3a0f14'`, `skins texture grid`, `skins opacity 0.5`,
  `skins reset`, `skins list` (shows name, background, texture, rarity), `skins current`.

Overrides last until reset or until the pane closes. zsh and bash get the
`skins` function from Lostty's shell integration; other shells can run
`lostty +skins`. In tmux, enable `set -g allow-passthrough on`.

## Known limitations

- Quick Terminal panes are not skinned.
- fish, nushell, and other non-zsh/bash shells do not get the `skins`
  shell function; run `lostty +skins` directly instead.
- Launching Lostty from inside another Lostty or Ghostty pane (e.g. via
  `open -a Lostty`, or double-clicking from within a terminal)
  inherits that parent app's `GHOSTTY_RESOURCES_DIR`, which breaks the
  `skins` shell function in every new pane. Launch it from Finder, the
  Dock, or Spotlight instead.

## Claude Trace

While Claude Code is working in a pane, a light ray races around that
pane's edge. The moment Claude finishes (or you interrupt it), the ray
disappears. If Claude finishes (or asks for permission) while you are in
another pane or app, the whole window (every pane, the icon row and the
bottom bar, but not the title bar) dims and shows **Ready for response**
until you click that pane. Each preset has its own trace; panes without a skin get a
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
`lostty +claude-hooks install`, `remove`, `status` or `preview`.

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

**Lostty → Claude Trace Style → Window Light** swaps the pane traces for
the website's light: while Claude or Codex works in any pane of a window,
one thin light circles that whole window's edge (title bar included), a
lap every 3.2 seconds, its tail running from the skin's second trace color
into its first and a white-hot tip, with a soft glow just inside the edge.
It takes the focused pane's skin when that pane is working, otherwise
another working pane's; panes without a skin give it the website's pink
and cyan. A pane whose trace is off doesn't light it. A pane where only
subagents or background shells still work keeps its bottom-edge glow,
and the window light goes out. Claude Trace Path doesn't apply (it's
greyed out), the Quick Terminal keeps its pane traces, and with Reduce
Motion the window's edge breathes instead. **Skin Traces** goes back.

## Guard

The guard is part of Lostty's agent coordination, which is off unless
`~/.config/lostty/guard.json` says `"enabled": true` (anything else, or no
file, is off). Off, Lostty behaves as if it were never built: Connect and
updates install only the trace hooks and take out a guard hook left from
before, and the app starts no guard, shows no guard badge or approvals, and
its hook messages don't mention the guard. After turning it on or off,
restart Lostty, then update the hooks (**Lostty → Claude Integration…**).

When it's on, in every Claude Code and Codex pane, Lostty stops a critical
action before it runs and asks you, even when the agent skips its own
permission prompts:

- **Deleting what git can't get back:** untracked or ignored files,
  anything outside the repo, uncommitted changes, `git clean`, deleting a
  branch whose commits are nowhere else, dropping a stash. Deleting a
  committed file goes through: git can restore it.
- **Throwing work away:** `git reset --hard`, `checkout`/`restore` over
  changes, `rebase`, amending a pushed commit.
- **Leaving the Mac:** force pushes, tags, branch deletes on the remote and
  pushes to protected branches (every push if you set `"push": "all"`),
  `gh pr/issue create`, publishing a package, scripts you list.
- **Merging into a protected branch** (`main`, `master`, and ones you add).
- **Changing the guardrails:** agent settings, hook files, `~/.config/lostty`,
  `~/.ssh`, the Keychain.
- **Writing outside the project** (temp folders excepted).

The agent is told it's blocked and to carry on with other work. You get a
notification (Deny right there, or click to see the whole request), an
amber badge on the pane, and the request in the Branches panel. In the
request window, Return and Escape deny. Approve it there, and if the agent
is still running, Lostty types "Approved #N" into its pane. The agent runs
that exact call once. An approval lasts 10 minutes; a request nobody
answers lapses after an hour. Agents have no way to approve.

A red **Guard disconnected** badge means an agent's guard hook isn't
installed. That includes an agent you never connected. Fix it from
**Lostty → Claude Integration…** by installing or updating the hooks.

If Lostty isn't running (say, during Restart to Update) or its app was moved
or deleted, Claude asks you in its own prompt and Codex stays blocked until
Lostty is back.

Settings live in `~/.config/lostty/guard.json`:

    {
      "push": "protected",
      "protectedBranches": ["release"],
      "commands": ["deploy.sh"],
      "deletable": ["vendor"],
      "repos": {
        "/Users/you/projectrepos/app": { "push": "all" }
      }
    }

By default (`"push": "protected"`) Lostty asks only for force pushes
(including `+ref`, `--force-with-lease`), tags, deletes on the remote and
pushes to protected branches. `"push": "all"`, globally or for one repo,
asks for every `git push`. `deletable` folders (by default `node_modules`,
`zig-out`, `.zig-cache`, `zig-cache`, `DerivedData`, `.build`, `__pycache__`)
can be deleted without asking.

Connecting an agent (the bubble at launch, or **Lostty → Claude
Integration…**) sets up its guard along with the trace. Agents already
running pick up new hooks only after you restart them. Codex asks you once
to trust Lostty's hooks; until you do, its guard doesn't run.

The guard defends against mistakes and misled agents, not a process set on
getting around it: it isn't a sandbox.

## Project Pill

At the right of the title bar, a pill names the focused pane's project and
branch, as the phone's terminal list does: `> lostty/skins`. It wears the
pane's skin (its background and text, the accent for the `>` and the
edge), follows focus between panes and splits, and catches a checkout
within a couple of seconds. A worktree shows its repo's name. Outside a git
repo (or in a home folder under git) there is no pill.

## Apps

The 2x2 grid button in the bottom bar, left of the mute button, swaps the
bar's Claude usage for Lostty's apps, from the left: Branches (beta) and
Skins. Click one to open it, and again (or its close button) to close it.
Skins fills the terminal area; Branches covers the whole window below the
title bar until you close it (or press Escape). Click the grid again to put
the usage back; an open app stays open.

## Claude Usage Bar

A bar along the bottom of each window, as tall as the title bar and the
same color as it, shows in the terminal's font the focused
pane's Claude model, a block meter for the context with the tokens in the
window (to the nearest thousand, e.g. `50K`), and a block meter with a
percentage for one plan limit:

    ✳ Opus 5.5   Context ▓░░░░░░░░░ 50K   Session ▓░░░░░░░░░ 2%

You don't need `/context` or `/usage`, and the numbers read `0K` and `0%`
until Claude reports them. The limit meter tracks your current session (the
5-hour limit) by default. Click the bar to see every limit (current session,
weekly) and when it resets, and click one to track it in the bar instead.
Meters turn amber at 70% and red at 90%. When the focused pane has no
Claude session, the bar is empty; it appears when Claude starts, with the
model at the left and the two meters centered in the bar.

The speaker button at the far right of the bar mutes the terminal's
sounds: the bell (including a `notify-on-command-finish` bell) and the
sound of desktop notifications such as "Command Finished". It stays muted
until you click it again, across restarts. Sounds your own Claude hooks
play (e.g. `afplay`) are not Lostty's and keep playing.

The numbers come from Claude Code's status line: Connect (or
`lostty +claude-hooks install`) sets `statusLine` in
`~/.claude/settings.json` to Lostty's `+claude-usage`, which prints
nothing. If you already have your own status line, Lostty leaves it alone
and the bar stays empty. Plan limits show for Pro and Max plans after
Claude's first reply. Claude Code doesn't share the weekly Fable limit, so
that row shows as unavailable.

## Updating from upstream Ghostty

See `UPGRADING.md`.
