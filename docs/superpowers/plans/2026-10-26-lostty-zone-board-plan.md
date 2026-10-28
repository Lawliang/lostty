# Lostty zone board: implementation plan

Date: 2026-10-26. Spec: `docs/superpowers/specs/2026-10-25-lostty-zone-board-design.md`.
Designed in an architect bakeoff (two candidates, one cross-judge). Base: candidate 1, with grafts
from candidate 2 and the judge's fixes. The candidates' sketches were throwaway scratch files.

## Changes to the spec

- **Delivery types raw text, not `sendText`.** `sendText` is a bracketed paste, and Claude Code
  records it as `<pasted_content>` (text from elsewhere). Lostty types the §5 prompt with Ghostty's
  `text:` binding action (`Ghostty.Surface.perform(action:)`), waits about 300 ms, then sends an
  Enter key press and release. Measured in the prototype: Enter at 0 ms was swallowed; at 150 or
  500 ms it submitted 3/3; newlines inside the text stay newlines.
- **No `order` field.** A feature's queue is its queued tickets in `CanvasController.tickets` array
  order. Priority stays a label and no longer sorts a queue.
- **No separate board file.** `+ticket list` prints a `board` text field in the pane's zone file.

## Data

- `CanvasTicket`
  - `status` becomes `private(set) var state: State` (queued, working, review, done, blocked).
    Only `move(to:note:by:)` changes it, and it checks one table, `State.allows(_:by:)`.
  - `note: String?`: the last review or blocked line, or the owner's Send back note.
  - `agentPane: UUID?`: the pane Lostty typed it into, for the row and the card title.
  - Decoding: `state` if present, else the legacy `status` (toDo→queued, inProgress→working,
    done→done). Encoding writes `state` and also the legacy `status` (done→done,
    working→inProgress, others→toDo), so an older build keeps finished tickets finished.
- `CanvasZone`: `autoStart: Bool?` and `manager: UUID?` (a pane), read on projects only. Optional, so the
  synthesized decoder still reads old saves.

## Lifecycle (`State.allows`)

| actor | moves |
|---|---|
| Lostty (with the agent pane) | queued → working |
| an agent pane in the ticket's domain | working → review, working → blocked |
| the owner (the board) | any → any except → working; Send back is review or blocked → queued |
| the project's manager | no state moves; it adds and assigns |

A same-state move is refused, so a repeated report changes nothing.

## Queue rules (pure, one module, `TicketQueue`)

- One working ticket per feature. The next queued ticket may start once the current one leaves working.
- Send back puts the ticket in front of its feature's first queued ticket. Assign and add go to the back.
  Done goes to the end of the array, as today.
- `next(in domain)`: the first queued ticket, if no ticket in that domain is working, and only if the
  project's auto-start is on or the ticket was started by hand (`startedByHand: Set<String>`, in memory).

## Roles

`CanvasModel.ticketRole(of pane:, panes:)`: the project's manager while it sits inside the project,
else any pane in a domain is that domain's agent. Role checks live in one pure function that applies a
`TicketReport` from a role to the tickets. The CLI checks only the verb and argument count.

## Delivery

- `TicketDelivery.prompt(for:)`: the §5 text. `textAction(_:)`: strips ESC and other control characters
  except newline, then escapes `\`, `"` and newline for the `text:` action.
- `TicketDelivery.input(in screen:) -> .none | .empty | .typed`: a line starting with `❯` directly under a
  full-width `─` rule is Claude's input line; anything else is `.none` (a shell, or a permission menu,
  which hides the box). A fresh session's dim `Try "…"` placeholder counts as empty.
- A pane is free when `ClaudeRuntime.phase(pane) == .off` and a fresh screen read (not
  `cachedVisibleContents`' 500 ms cache) gives `.empty`.
- The agent is the first free pane in the domain, in card order, not the manager.
- `CanvasController.deliverReadyTickets()`, behind a debounce, runs on ticket, zone, membership and
  `ClaudeRuntime.$phases` changes, and every 2 s while a ticket is ready but no pane can take it.
  It types first and moves the ticket to working (with `agentPane`) only if typing succeeded, in the
  same main-actor turn. Nothing typed: the ticket stays queued and is tried again.
- Undo is not registered for moves that type into a terminal.

## Reports (`lostty +ticket`)

- `src/cli/ticket.zig`, registered in `src/cli/ghostty.zig`. Verbs: `review <key> <note>`,
  `blocked <key> <reason>`, `add <feature> <summary> [details]`, `assign <key> <feature>`, `list`.
- It sends `LOSTTY_TICKET=<base64 JSON array of its arguments>` to its own terminal with
  `claude_state.openTerminal` and the tmux passthrough wrapper `+claude-state` uses, and prints `sent`.
  `list` prints the `board` field of its pane's zone file (`LOSTTY_SURFACE`).
- `Ghostty.App.userVarChanged` routes `LOSTTY_TICKET` to the canvas, which parses it into `TicketReport`
  at once and applies it by the sender's role through `setTickets`.

## Manager

- Settings on the tickets panel (its title bar's settings button), for the project it's in: "Start tickets
  automatically" and "Manager" (a menu of the project's terminals). Each feature's section header names the
  terminals its tickets go to, or warns that it has none.
- The manager's brief (spec §7) is added to its zone file's `start` text and said once through `zone.say`
  when it's picked. A blocked report appends `TB-8 · Onboarding is blocked: <reason>` to its `zone.say`.

## Build order (each unit builds, tests pass, commit)

1. Fields: `State`, `allows`, `move`, `note`, `agentPane`, legacy decode and encode; zone `autoStart`, `manager`.
   Rename the `status` call sites. Tests: lifecycle table, old saves, newer save read with defaults.
2. `TicketQueue` and `TicketReport`: pure. Tests: one in flight, Send back to the front, assign to the back,
   done last, role refusals, repeated report is a no-op.
3. Board view: sections by feature, state chip, agent name, note, Start, Done, Send back with a note, Feature menu.
4. Delivery: `TicketDelivery`, `deliverReadyTickets`; Start types. Tests on captured screens (empty, typed,
   multi-line, placeholder, permission menu, zsh `❯`, working). Live: Start types a ticket into an idle Claude.
5. `+ticket review|blocked` and the app route. Zig tests. Live: review and blocked move the ticket.
6. Auto-start switch. Live: two queued tickets go in one after the other across a review.
7. `+ticket add|assign|list` and the zone file `board` field.
8. Manager: settings menu, brief, blocked note.
9. The card title shows the agent's current ticket key.

## Risks accepted

- Delivery depends on Claude Code's prompt layout (rule, `❯`, rule). If it changes, nothing is typed and
  tickets stay queued.
- A crash between typing and the debounced save can type a ticket twice.
- Start is forgotten on relaunch.
- Old in-progress tickets load as working with no agent and hold their feature until the owner moves them.
