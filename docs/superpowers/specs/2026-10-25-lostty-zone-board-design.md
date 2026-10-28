# Lostty zone board — design

Date: 2026-10-25. Status: decided in two grilling rounds, not built.
Branch: `zones`. Builds on zones (`2026-10-24-lostty-zones-design.md`).

## 1. Goal

The owner runs one Claude terminal per feature of a product: onboarding
UI, the main app flow, landing and login, each end to end. Today every
task is typed into the right terminal by hand. The board lets the owner
write tasks in one place, or ask one manager agent to write them, and
Lostty hands each task to the right feature's agent when it's free.

What it fixes:

- **Typing tasks into each terminal.** Tasks go on the project's board.
  Lostty types each one into its feature's agent.
- **Splitting a request across features.** A manager agent turns "add
  Google sign-in" into one ticket per feature.
- **Knowing where work stands.** Every ticket shows queued, working,
  review, done or blocked, and which agent has it.

## 2. Decisions (from the owner)

- **A feature is a domain.** One domain zone per feature, one Claude
  terminal in it. Its brief says what the feature covers.
- **Auto-start is a per-project switch** in the project's settings. On:
  a queued ticket starts as soon as its agent is free. Off: it waits for
  the owner's Start.
- **Delivery is a typed prompt.** Lostty enters the ticket into the
  agent's terminal as if the owner had typed it, so the terminal shows
  exactly what was asked.
- **States:** queued, working, review, done, and blocked (with a
  reason). The agent moves a ticket to review or blocked; only the owner
  moves it to done.
- **A manager agent** writes tickets from the owner's requests and puts
  them straight into feature queues. It never writes code. The auto-start
  switch still decides whether they run.
- **The manager is a role** the owner sets in the project's settings: one
  terminal in the project.
- **A blocked ticket** is shown on the board with its reason, and the
  manager gets a note with its next message.
- **Unassigned tickets** (no feature) wait for the owner or the manager
  to assign them. No agent claims work on its own.

## 3. What it looks like

- **The board** is the project's tickets panel, grouped by feature: each
  feature's queue in order, its agent's current ticket on top, then
  "To assign" for tickets with no feature.
- **A ticket row:** key, summary, state chip (queued, working, review,
  done, blocked), and the agent's name while it's working.
- **Start** on a queued ticket when auto-start is off; **Done** and
  **Send back** on a ticket in review.
- **The agent card** shows its current ticket key in its title bar.
- **Settings:** "Start tickets automatically" and "Manager" (a menu of the
  project's terminals) in the project zone's settings.

## 4. The flow

1. The owner writes a ticket on the board, or asks the manager.
2. The ticket joins its feature's queue (state queued).
3. When the feature's agent is idle (ClaudeRuntime: not working, not
   waiting on the owner) and the switch is on, or the owner presses
   Start, Lostty types the delivery prompt into the agent's terminal and
   the ticket becomes working.
4. The agent works, then runs `lostty +ticket review TB-7 "what changed"`
   or `lostty +ticket blocked TB-7 "why"`.
5. Review: the owner checks, then Done (the next ticket can start) or
   Send back (typed to the agent with the owner's note, working again).
6. Blocked: the board shows the reason; the manager's next prompt carries
   a note naming the ticket and reason.

One ticket per agent is working at a time. The next one can start as
soon as the current one leaves working (review, blocked or done), so a
review never holds up the queue. Send back puts the ticket at the front
of its feature's queue.

## 5. The delivery prompt

```
TB-7 · Login: Add a "Continue with Google" button and the OAuth callback at /auth/google.

<details, if any>

When it's done, run: lostty +ticket review TB-7 "<one line on what changed>"
If you can't go on, run: lostty +ticket blocked TB-7 "<why>"
```

Typed with `Ghostty.Surface.sendText` and a Return, the path context
handoffs and the Guard's merge turns already use.

## 6. `lostty +ticket`

Run inside a Lostty pane. It writes an OSC 1337 report to its terminal,
as `+claude-state` does, so the app knows which pane, and so which zone
and role, sent it. The app checks the role and applies it.

- `review <key> <note>`, `blocked <key> <reason>`: the ticket's agent.
- `add <feature> <summary> [details]`, `assign <key> <feature>`: the owner
  or the manager. Feature is a domain name in the project.
- `list`: reads the project's board file, which the app writes beside the
  zone files (`<project>.board.json`): each feature's queue and states.

`add` can't print the new key (the report is one-way); it prints "sent"
and the key shows on the board and in the next `list`.

## 7. The manager

A Claude terminal in the project, picked in settings. Its brief adds:

```
You're the manager of Textberry. You don't write code.
Turn the owner's requests into tickets, one per feature, with lostty +ticket add.
Features:
  Login: the landing and login pages, end to end (textberry-3f)
  Onboarding: signup steps and first run (textberry-a1)
  Main app: everything after onboarding (textberry-9c)
Check lostty +ticket list first, so you don't repeat a ticket.
```

The feature lines come from the domain names, the first line of each
domain's brief, and its agent. Ticket quality depends on those briefs.

## 8. Model and save

`CanvasTicket` gains: `state` (queued, working, review, done, blocked;
replaces `status`, mapped from it on load), `note` (the last review or
blocked line), `order` within its feature's queue. `CanvasZone` gains
`autoStart: Bool` and `manager: UUID?` (a pane). Saved with the canvas,
decoded forgivingly like today's fields.

## 9. Build order

1. Prototype: one ticket typed into one idle agent; `+ticket review`
   moves it to review. Owner tries it before the rest.
2. States, queues and the board view; Start, Done, Send back.
3. The auto-start switch.
4. `+ticket add`, `assign`, `list`, the board file.
5. The manager role, its brief, blocked notes.

## 10. Out of scope (first version)

Agents claiming unassigned work, more than one ticket in flight per
agent, priorities across features, the phone, an always-on supervisor
that watches the agents, and overlap warnings (planned separately: a
note when two features change the same file).

## 11. Risks

- **Typing into a busy terminal.** Delivery waits for idle as Lostty
  sees it; if the owner is typing in that terminal, typed text could mix.
  Deliver only when the terminal's input line is empty, or skip and retry.
- **Agents forget `+ticket review`.** The ticket stays working. The board
  shows how long; the owner can move it by hand.
- **Token cost.** The manager only runs when the owner talks to it or a
  blocked note arrives; nothing polls.
