# Lostty Zones: code map

Read with the spec, `docs/superpowers/specs/2026-10-24-lostty-zones-design.md`.
Mapped on 2026-10-24 at `84113c526` (zones with more-UI-improvements merged in).

## Decided since the spec

- A tickets panel outside every zone lists every ticket, as today.

## Where the spec doesn't match the code

- Only one tickets panel exists (`TicketBoard.id` fixed, `ticketsView` optional). Per-zone panels mean turning those into collections; `view(_:)`, `ticketClicked`, `ticketWillFocus` assume one.
- `TicketCardView.swift` is gone: the panel is `TicketBoard.swift`, `TicketBoardView.swift`, `TicketBoardContent.swift`, `TicketList.swift`.
- `.start` is only printed at SessionStart when `source == "clear"` (`src/cli/claude_state.zig:52-56`), so a new Claude session never gets it. The brief needs a hook change, kept apart from the handoff's `fresh`/`cleared` signal.
- Nothing appends to the queue: `ContextHandoffStore.writeSay` replaces `.say`, and `removeSay`/`removeAll` delete `.say`/`.start` (`macos/Sources/Features/Handoff/ContextHandoffStore.swift:38-54,90-92`). Both writers must change.
- `.say` is also taken by PostToolUse (no `agent_id`), so a zone `say` can arrive mid-turn.
- No agent-name mapping exists. `+peers` (`src/cli/peers.zig`) is git-only and keys terminals by tmux location. Claude Code's `~/.claude/sessions/<pid>.json` holds `tmux`, `name`, `sessionId`. SendMessage's `tool_input` field and value format are unconfirmed: capture one live before writing the hook.
- `CanvasTicket.prefix` is static, `number(of:)` parses only `LT-`, and one app-wide counter lives in UserDefaults (`CanvasController.swift:43,601`).
- `CanvasSaved.isEmpty` and `CanvasController.isEmpty` would drop a canvas holding only zones.

## Canvas (macos/Sources/Features/Canvas/)

- `CanvasModel.cards` holds terminal cards and the tickets panel, back to front. Keep zones in a separate list so `card(at:)` hit tests stay card-only.
- Add: every path reaches private `add(_:frame:)` (`CanvasController.swift:262`); the panel uses `openTickets` (463).
- Move and resize end in `cardFrameDidSettle()` (`CanvasController.swift:374`): the membership hook. Removal: `retire` (394), `closeTickets` (481).
- Zone layer: a view as the document's first subview, `CanvasStacked` with `stackIndex = Int.min` (else `restack()` ties it with the back card). Its `hitTest` returns nil except on edges, or the marquee breaks. Labels (pill and caption) sit in `CanvasZoneLayer.labels`, the document's second subview, over the zones and under every card; `CanvasDocumentView.restack()` keeps it there and `floats(at:)` counts a label only where no card covers it. `show(zones)` drives both layers. Edge widths divide by zoom like the selection ring (`CanvasSelection.swift:90`; `canvasMoved` at `CanvasController.swift:620`).
- Selection bar: `CanvasSelectionBar.body` (`CanvasSelection.swift:146-160`), closures in `updateSelectionBar` (277).
- + menu: `CanvasAddMenuView.Item` (`CanvasAddMenu.swift:10`), handled in `CanvasController.swift:172-177`.
- New terminal folder: the + menu passes no `baseConfig`; ⌘T builds it in `AppDelegate.newTab` (`AppDelegate.swift:1190`), then `NewWindowChoice.ask` may restart the shell. The frame is chosen after the surface exists, so place first, then set `baseConfig.workingDirectory`.
- Card to panes: `CardController.surfaceTree`; pane to card: `card(holding:)` (281). Pane to tmux: `@lostty_surface` via `TmuxOwnership.showing` (`Features/Sessions/TmuxSession.swift:69`).
- Notices: `LosttyNotification` (`Features/Notifications/LosttyNotifications.swift:27`), shown by `CanvasNotificationsView`. A new float must join `CanvasSurfaceView.floats(at:)` (`CanvasSurface.swift:297`).
- No popovers exist in the canvas. Patterns to reuse are NSMenu in code (`TicketBoard.menu`) and `CardRenameOverlay` (`CardView.swift:180`).
- Save: `restorableState()` (`CanvasController+Restore.swift:7`); restore (24). Decode new lists with `decodeEach`, new fields with `decodeIfPresent`; keep memberwise init defaults (tests build `CanvasSaved` directly).

## Agent channels (src/cli/)

- Queue files: `~/Library/Application Support/Lostty/handoff/panes/<PANE-UUID>.say|.start`, plain text, 64 KB max, read once by `speak.take()` (`src/cli/claude/speak.zig`). The pane id is `LOSTTY_SURFACE`. Name a zone file `<UUID>.zone.json`, never `<UUID>.json` (handoff state).
- Hooks: `src/cli/claude/hooks.zig:33-42`. PreToolUse runs `+claude-state tool` for every tool. The command string is unchanged by a deny, so a new binary needs no hook reinstall.
- Deny: put the SendMessage check before `.tool`'s early return on a null `action()`. Print the `permissionDecision` JSON to stdout; `guard/wire.zig:73-81` already builds it. Read files only (5 s timeout).
- Report to the app: OSC 1337 `LOSTTY_CLAUDE` (`claude/protocol.zig`), received in `ClaudeRuntime.userVarChanged` (`Features/Claude/ClaudeRuntime.swift:72-118`). An unknown state decodes to nil, so a "denied" report needs a new field.
- Guard root: `projectRoot` in `src/cli/guard/catalog.zig:107-110`. Runs only with `"enabled": true` in `~/.config/lostty/guard.json`.

## Tests

- Swift: `macos/skins-test.sh <Suite>` (Swift Testing structs), full `macos/build.nu --action test`.
- Zig: `zig build test -Dtest-filter="claude speak"`, `"claude protocol"`, `"guard"`, `"worktrees"`. Put new logic in pure helpers under `src/cli/claude/`.

## Settled while building (2026-10-24)

### Step 5: the brief comes from the zone file, not the `start` queue

The `start` queue is read once and shared with the handoff, so a brief
queued there reaches one session and can be eaten by, or eat, a handoff.
The zone file is the current truth, so the hook reads the brief from it:

- `<PANE>.zone.json` (beside the queue) holds `"start"`, the rendered
  brief. The app rewrites it whenever the pane's zone, the zone's
  settings or its members change, and deletes it when the pane leaves
  every zone. Step 7 adds the members' agent names to the same file.
- SessionStart with source `startup`, `clear` or `compact` prints it,
  with the handoff's `.start` text after /clear as today. `resume` and
  `fork` already have it. The `fresh`/`cleared` signal is unchanged.
- Moving in or out mid-session queues `<PANE>.zone.say`, its own file,
  so neither writer appends to the other's (`ContextHandoffStore` keeps
  replacing `.say`). UserPromptSubmit takes `.say` and `.zone.say` and
  prints them as one additionalContext. PostToolUse takes only `.say`,
  so a zone note waits for the next prompt instead of landing mid-turn.
- SessionStart already runs for every source (`hooks.zig`), so only the
  `lostty` binary changes. No hook reinstall.

### Step 7: a real PreToolUse SendMessage payload

Captured from this session on 2026-10-24 with a capture hook, sending to
a name no agent has:

```json
{
  "session_id": "…", "transcript_path": "…", "cwd": "…",
  "hook_event_name": "PreToolUse",
  "tool_name": "SendMessage",
  "tool_input": {
    "to": "zones-capture-nobody",
    "summary": "capture PreToolUse SendMessage payload",
    "message": "…",
    "type": "message",
    "recipient": "zones-capture-nobody",
    "recipient_kind": "name",
    "content": "…"
  },
  "tool_use_id": "toolu_…"
}
```

The target is `tool_input.to` (also `recipient`). SendMessage's own docs
allow a bare name, `"name [ref]"`, `"main"`, or a subagent's agentId, so
the hook strips a trailing ` [ref]` and lets `main` and agentIds through
(they stay inside the session).

### Step 7: names to panes, through tmux

Claude Code's `~/.claude/sessions/<pid>.json` holds each session's
`name` (what ListAgents shows) and `tmux` location (`zones-2:@12.%12`,
the same form `+peers` prints). Lostty's panes run in tmux sessions on
the `lostty` socket, so the tmux session name is the join key:

- The zone file gains `"members"`: the tmux session names of every pane
  in the sender's project zone, its domains included (domains of one
  project can talk). The app knows each pane's session
  (`TmuxOwnership`).
- The PreToolUse hook, on `tool_name == "SendMessage"` with a zone
  file: strip a trailing ` [ref]` from `tool_input.to`, find the
  session file whose `name` matches. Allowed: `main`, no matching
  session file (an in-process subagent or teammate, or a name that
  fails anyway), or a session whose tmux session is a member. Denied:
  any other match, including a session outside tmux. This turns the
  spec's "an unknown target is treated as outside" around, because
  in-process subagents have names too and must keep working.
- Allow Once: the app writes `<PANE>.zone.allow` holding the target
  name; the hook takes it (rename, like `speak.take`) only when it
  names this target. The latest Allow Once wins.
- The brief's "Other agents in this zone" line is rendered by the hook
  at SessionStart from the members and the session files, so names are
  current without the app tracking them.
- `+peers` with a zone file lists only rows whose tmux session is a
  member. Superseded 2026-10-25: the filter hid same-repo terminals a
  merge check must ask. `+peers` now lists every row and labels each
  with its zone, found through the session's `@lostty_surface`, and
  the hook lets a SendMessage through to an agent whose session file's
  `cwd` is in a worktree of the same repo.
