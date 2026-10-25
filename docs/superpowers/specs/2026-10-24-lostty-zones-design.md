# Lostty Zones — design

Date: 2026-10-24. Status: decided in four grilling rounds; built on `zones` (see the
code map's "Settled while building" for where the build differs).
Branch: `zones`, started from `UI-improvements` (`64f25ae52`).
Mockup: [Lostty Zones](https://claude.ai/artifact/2mwS6kZL7Di2aKJiYBanEp).

## 1. Goal

A **zone** is an area you draw on the canvas. The terminals and ticket
panels inside it belong to it. Its first job is to hold a **project's
context** for the agents working in it; its second is a **boundary**
that keeps those agents from reaching agents outside.

Who it's for: you, alone, running several Claude sessions across 2–4
projects at once. What it fixes:

- **Re-explaining the project.** Each new Claude session in a zone
  starts in the zone's folder and gets its brief, without pasting it.
- **Finding what belongs where.** A zone is one block on the canvas,
  with its own tickets and one status line ("2 working · 1 waiting").
- **Agents reaching the wrong project.** Agents in a zone see and
  message only the zone's agents.

Zones nest once: a **project zone** (Textberry) holds **domain zones**
for slices of the work end to end (Onboarding, Main app, Platform
integrations). A domain is a slice of the work, not of the folders: it
has its own brief and tickets, and uses the project's folder unless it
has a subfolder.

## 2. Decisions (from the owner)

- **Context first, boundary second.** The boundary is the second layer
  on top of a zone's context.
- **Membership is position.** An item is in the zone that holds its
  centre. Dragging it in joins, dragging it out leaves, and resizing a
  zone over items takes them in.
- **Two levels:** project and domain. Zones never overlap, except a
  domain zone wholly inside its project zone.
- **Canvas only.** Tabbed windows and windows off the canvas are in no
  zone.
- **For one person.** No sharing or team rules.
- **The boundary covers Lostty's own channels only.** It isn't an OS
  sandbox, and the first version keeps the one `lostty` tmux socket, so
  it doesn't cover tmux (the settings panel says so).
- **Getting past it:** "Allow Once" on the notice, nothing more. To let
  two agents talk for good, put them in the same zone.
- **Domains in one project can talk** by default.
- **Removing a zone closes nothing:** its items stay where they are, in
  no zone; its domain zones go with it; its tickets keep their keys.
- **Briefs are short and live in Lostty**, saved with the canvas, never
  written into the repo. The project brief is optional (CLAUDE.md or
  AGENTS.md already describes the project): it's for what's true on your
  desk, like "test Stripe in test mode only". Domain briefs carry the
  weight.
- **Colors:** each new zone takes the next color from a fixed set, never
  repeating inside a project, changeable in its settings. Skins are
  unchanged.
- **The phone is unchanged** in the first version.
- **Names:** "Zone" in the interface; `CanvasZone` in code (the code
  already has `TerminalSplitDropZone` for split drop targets).

## 3. What it looks like

- **A zone** is a rounded area behind the cards: a faint fill of its
  color and a solid edge (2 pt for a project, 1.5 pt for a domain).
- **Its label**, inside the top edge: the name on a pill of its color;
  for a project, its folder and its counts ("6 terminals · 2 ticket
  panels · 2 working · 1 waiting"); for a domain, the first line of
  its brief.
- **Settings**, from the label: name, color, folder (project) or
  subfolder (domain), brief, what's inside, the boundary's rules, Zoom
  to Zone, Remove Zone.
- **Notices**, a small panel at the canvas's corner: "Kept inside
  Textberry: claude — onboarding tried to message claude — lostty,
  which is outside the zone" with **Allow Once** and **Zone Settings**;
  and "claude — onboarding left Textberry" when a terminal is moved
  out.

## 4. Making and changing zones

- **Zone from Selection** in the selection bar (drag-select): a zone
  fitted around the selected cards with a margin. If they're all inside
  one project zone, it's a domain zone of that project.
- **New Zone** in the + menu: drag to draw an empty one.
- **Moving:** drag the label; the zone and everything in it move
  together (a project's domains too).
- **Resizing:** drag an edge or corner; only the zone changes, and
  membership is worked out again. A project zone can't shrink past its
  domains; a domain can't grow past its project or into a sibling.
- **Overlap:** a zone can't be drawn or moved over another, except a
  domain inside its project.

## 5. Context for agents

- **Folder.** A terminal made inside a zone (the + menu, ⌘T beside a
  card in it) starts in the domain's subfolder, else the project's
  folder. A terminal that `cd`s elsewhere stays a member.
- **Brief.** When a pane is in a zone, the app keeps the brief in the
  pane's zone file (`<PANE>.zone.json`), so every Claude session that
  starts there (new, after /clear, after compaction) gets, at
  SessionStart:

  ```
  Lostty zone: Textberry › Onboarding (~/projectrepos/textberry).
  Textberry: <project brief>
  Onboarding: <domain brief>
  Other agents in this zone: claude — main app, claude — integrations.
  ```

- **Moving in or out mid-session** queues a `say` text instead, which
  the agent gets with its next prompt: "You're now in zone Textberry ›
  Onboarding" plus the briefs, or "You've left zone Textberry". The
  change shows as a notice on the canvas.
- **Plain terminals** (not running Claude) get only the folder and the
  membership.

## 6. Tickets

- Every ticket has a zone (project or domain) or none. A ticket made in
  a panel inside a zone belongs to that zone.
- **Key prefix per project zone:** set in the project's settings,
  defaulting to its name's initials (Textberry → `TB`). Tickets in no
  zone keep `LT-`. A ticket keeps its key when its zone changes.
- **Panels show their zone's tickets:** a domain's panel, the domain's;
  a project's panel, the project's and all its domains', each tagged
  with its domain. Open for review: what a panel outside every zone
  shows (recommended: every ticket, as today).

## 7. The boundary

Applies to agents in a zone; nothing changes for terminals in no zone.

1. **`+peers` lists only the zone's agents.** Domains of one project
   count as one zone unless walled off (a later option).
2. **Messages stop at the edge.** Claude sessions message each other
   through Claude Code's own sockets, not Lostty, so Lostty's
   PreToolUse hook (`+claude-state tool`, installed for every pane)
   denies a SendMessage to an agent outside the zone, with the reason,
   and tells the app, which shows the notice.
3. **Writes stay in the folder, through the Guard**, only when you've
   turned the Guard on (it stays off by default, and zones never turn
   it on). A domain's limit is its subfolder, else the project folder.
4. **Allow Once** on the notice lets that one message through: the app
   records a single-use allowance, and queues a `say` text telling the
   agent it may retry.

Not covered, and said so in the settings: tmux (any process can still
`tmux -L lostty send-keys`), and anything outside Lostty. AppleScript
can't reach canvas cards at all, so it needs nothing.

**How the hooks know the zone:** the app writes a small file per pane in
a zone (next to the `speak` queue): the zone, the domain, the folder,
the members' agent names (as `+peers` already maps tmux sessions to
the names Claude Code's ListAgents shows) and any Allow Once
allowances. `+peers` and the PreToolUse hook read it. No file means
no zone, and they work as today.

## 8. Save and restore

`CanvasSaved` gains the zones (frame, name, color, parent, folder or
subfolder, brief, key prefix); a ticket carries its zone's id. After a
restart or Restart to Update the zones come back, panes reattach to
their tmux sessions as now, membership is worked out from position, and
the per-pane zone files are written again.

## 9. How it's built

- **Model** (`CanvasModel.swift`): `zones: [CanvasZone]` beside the
  cards; `CanvasZone { id, frame, name, color, parent: UUID?, folder,
  brief, keyPrefix }`. Pure functions: `zone(for cardFrame:)` (the
  domain holding the centre, else the project, else none), and the
  rules for drawing, moving and resizing without overlap. Unit tested.
- **Interface** (`Features/Canvas/`): `CanvasZoneView`, drawn behind
  every card in AppKit layers that only move with the canvas's
  transform; the label and its settings popover; "Zone from Selection"
  in the selection bar; "New Zone" in `CanvasAddMenu`; the notice view.
- **Membership changes** (`CanvasController`): after a card is added,
  moved, or a zone moved or resized, work out each card's zone; for
  each change, rewrite that pane's zone file, queue the `say` text and
  show the notice.
- **Agent context:** the app keeps the brief in the pane's zone file
  and queues move notes in `<PANE>.zone.say`, apart from the handoff's
  `start`/`say` queue. SessionStart prints the brief, and
  UserPromptSubmit and PostToolUse print the notes. Only the `lostty`
  binary changes; the hooks don't.
- **`+peers`** (`src/cli/peers.zig`): filter to the zone file's members.
- **SendMessage hook** (`src/cli/claude_state.zig`, `tool` state): deny
  a SendMessage whose target isn't a member and has no allowance;
  report it to the app over the pane's terminal, as `+claude-state`
  does today.
- **Guard:** use the zone's folder as the project root for panes in a
  zone.
- **Tickets** (`CanvasTicket.swift`, `TicketCardView.swift`): a `zone`
  field, the key prefix, the panel filter and domain tags.
- **Label counts:** from `CanvasWaits` and the panes' Claude states.

## 10. Build order

1. `CanvasZone` in the model, membership and the no-overlap rules, with
   tests.
2. Zone views: draw, Zone from Selection, move, resize, nested domains,
   the label (name only), remove.
3. Save and restore.
4. The folder for new terminals; the settings panel.
5. Per-pane zone files and the brief through the hooks; moving in and
   out mid-session; the notices.
6. Tickets per zone.
7. `+peers` filter, the SendMessage hook, Allow Once.
8. The Guard folder limit.
9. Counts on the label.

Steps 1–4 make zones useful as layout and folders; 5–6 deliver the
context job; 7–8 the boundary.

## 11. Testing

- Model: membership by centre, domain over project, no overlap, resize
  limits, moving a project moves its domains, removing keeps items.
- Zig: `+peers` filtered by a zone file; the hook denies SendMessage to
  a non-member, allows a member and an allowance once; no zone file
  changes nothing.
- Save and restore round trip with zones and ticket zones.
- By hand: a new Claude session in a domain gets both briefs; moving a
  terminal out mid-session; Allow Once; Restart to Update keeps zones.

## 12. Out of scope (first version)

Collapsing a zone to a tile, zone templates, walling off domains from
each other, a tmux socket per zone, zones on the phone, zones for
windows off the canvas, more kinds of items in zones, more than two
levels, and any OS-level sandboxing.

## 13. Risks

- **The SendMessage target's name.** The hook has to match the target
  Claude Code names to a pane's agent; it relies on the same mapping
  `+peers` uses. A name no Claude session file has (a subagent or
  teammate) goes through; a session outside the zone is denied.
- **The hook changes need a new `lostty` binary**, not a hook
  reinstall: the hook commands are unchanged. Running sessions pick
  the binary up once Lostty is updated and they restart.
- **The handoff's queue stays the handoff's:** zone briefs and notes
  live in their own files, so neither writer appends to the other's.
- **Drawing cost:** zones must not redraw while panning or zooming; they
  are static layers moved by the canvas's transform.
