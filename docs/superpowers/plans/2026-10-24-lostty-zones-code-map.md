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
- Zone layer: a view as the document's first subview, `CanvasStacked` with `stackIndex = Int.min` (else `restack()` ties it with the back card). Its `hitTest` returns nil except label and edges, or the marquee breaks. Edge widths divide by zoom like the selection ring (`CanvasSelection.swift:90`; `canvasMoved` at `CanvasController.swift:620`).
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
