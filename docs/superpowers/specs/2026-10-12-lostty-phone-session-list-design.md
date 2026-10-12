# Lostty phone session list: labels, live updates, closed-session overlay — design

Status: draft for review (2026-10-12)

Builds on docs/superpowers/specs/2026-10-09-lostty-mobile-design.md (the phone
attaches to the Mac's `tmux -L lostty` sessions over SSH) and
docs/superpowers/specs/2026-10-12-lostty-menu-bar-stay-awake-design.md (the
menu bar's Sessions list).

## Goal

On the phone, it is obvious what each session is, the list is always current,
and a session that ends while you're in it says so instead of vanishing.

### Success criteria

- A Claude session reads as its task ("Lostty UI redesign plan"), with its
  project and whether it is waiting for you; no row reads only `lostty-2`.
- Closing a Mac tab removes its row from an open phone list within about a
  second, without pulling to refresh.
- A phone attached to a session that is closed on the Mac shows a dark overlay
  saying why, over the dimmed last screen, until you tap Back to Sessions.
- Typing `exit` on the phone goes straight back to the list.
- A dropped connection shows "Connection lost — reconnecting…" and clears
  itself when the phone is back.
- The menu bar's Sessions list uses the same labels and order.

## Facts this design rests on

- Each Lostty pane is its own tmux session. Closing a pane or tab ends its
  session (`TmuxClient.endSessions(showing:ownedBy:)`); quitting Lostty ends
  every session it shows (`endSessions(ownedBy:)`). The phone's Close Session
  runs `kill-session` over SSH (`TmuxRemote.killCommand`).
- Session names come from the shell's project (`naming.projectName`: the git
  root's folder, `home` for `~`), renamed only when the shell changes project
  at a prompt, with `-2`, `-3` for repeats. A program that changes directory
  (Claude entering a worktree) does not rename it.
- `#{pane_title}` is the title the Mac tab shows (`set-titles on`): Claude
  Code's task with a spinner glyph ("✳ Lostty UI redesign plan"), or a shell's
  folder ("~/projectrepos/lostty"). `#{pane_current_path}` is the running
  program's folder; `#{pane_current_command}` reports Claude Code as its
  version ("2.1.296"). `#{session_activity}` is the last activity time.
- The phone lists sessions with one SSH command (`TmuxRemote.listCommand`,
  format id, name, `@lostty_surface`, `@lostty_owner`) only when the list
  appears, on pull to refresh, and after a terminal closes.
- An attach ends as `AttachEnd.exited(code)` (tmux exited: the session ended
  or the client was detached) or `.lost` (the connection broke; the phone
  reconnects with backoff). Today `.exited` posts `losttySurfaceClosed`, and
  `TerminalScreen` dismisses itself at once.
- tmux 3.8 has hooks `session-created`, `session-closed`, `session-renamed`,
  `client-attached`, `client-detached`, but none for pane title changes.
  `wait-for -S <channel>` wakes every client waiting on the channel; a signal
  with no waiter is kept, so the next `wait-for` returns at once.
- The Mac knows each pane's title and Claude state (`ClaudeRuntime.phases`,
  `.awaiting`, keyed by surface UUID); `@lostty_surface` maps a session to its
  surface. A focused waiting pane counts as seen.
- The Mac tab's "Rename Tab…" (`TerminalWindow.renameTabFromContextMenu`)
  overrides the tab title.

## Decisions

| Question | Decision |
|---|---|
| Where the new labels show | The phone's session list and the menu bar's Sessions list. Mac tabs keep the live title unless renamed. |
| Row main line | A name you typed, else the cleaned title of a Claude session, else the project |
| Row second line | Project · "shell" or "claude" · "Open on Mac" |
| Row right side | "Waiting" (accent) or "Working" (muted) for Claude sessions open on the Mac; else last used ("5m ago") |
| Order | Waiting first, then most recently used; sessions not open on the Mac in a dimmed bottom section, swipe to close (existing confirm) |
| Worktrees | `.../<repo>/.claude/worktrees/<name>` shows as `<repo>/<name>` |
| Renaming | One name everywhere: "Rename Tab…" on the Mac and Rename on the phone set it; empty clears it |
| Seen | Attaching from the phone clears a waiting badge, here and in the menu bar |
| List freshness | Live while the list is on screen (one watching connection) |
| Session ends while attached, not by you | Dark overlay over the dimmed last screen, says why, stays until Back to Sessions |
| You ended it from this phone | Straight back to the list (as Close Session does today) |
| Ended while the app was in the background | The overlay, on return |
| Connection drops | Same overlay style: "Connection lost — reconnecting…", clears itself; Back to Sessions after 30 s |

## Architecture

### Session metadata in tmux

All new per-session state lives in tmux user options, so the phone reads it
with the one list command and nothing new runs on the Mac at attach time.
Session ids and names are unchanged: the phone's name guard before attach and
kill keeps working.

| Option | Scope | Set by | Value |
|---|---|---|---|
| `@lostty_label` | session | Mac "Rename Tab…", phone Rename | The name you typed; unset when cleared |
| `@lostty_claude` | session | Mac (`ClaudeRuntime` changes) | `waiting`, `working`, or unset |
| `@lostty_end_<n>` | global | Whoever ends session `$n`, just before `kill-session` | `mac-close`, `mac-quit`, or `phone:<device name>` |

`@lostty_end_<n>` outlives its session so a phone whose attach just ended can
read why. Ids restart only with the tmux server, which drops the options too;
a stale entry for a reused id is overwritten by the next end. A session that
ends with no tag ended by itself: its shell exited.

### Change signal

One wait-for channel, `lostty-changed`, signalled:

- by tmux hooks in `lostty-tmux/tmux.conf`: `session-created`,
  `session-closed`, `session-renamed`, `client-attached`, `client-detached`,
  each `wait-for -S lostty-changed`;
- by the Mac app after it changes `@lostty_label` or `@lostty_claude`, and
  when a Claude session's cleaned title changes (spinner frames are not
  changes), at most once per second;
- by the phone after Rename.

The Mac app also re-applies the hooks at launch (`set-hook -g`), so a tmux
server started before this version gets them without a restart.

### Phone: live list (`LosttyRemote`, `MobileStore`)

- `TmuxRemote.listFormat` adds `@lostty_label`, `@lostty_claude`,
  `#{pane_title}`, `#{pane_current_path}`, `#{pane_current_command}`,
  `#{session_activity}`; `RemoteSession` gains matching fields.
- `RemoteConnection.watchChanges()` runs, on its own SSH channel,
  `while tmux -L lostty wait-for lostty-changed; do echo; done` and yields one
  event per line. It ends when tmux has no server (wait-for exits 1) or the
  connection drops.
- While `SessionsScreen` is visible and the app is active, `MobileStore` holds
  one connection with the watch running and re-lists on each event, at most
  every 300 ms. When the watch ends it re-lists, waits with `ReconnectPolicy`
  and starts again. Leaving the list or backgrounding the app closes it.

### Labels (`LosttyRemote/SessionLabel.swift`, shared by phone and Mac)

A pure function turns a `RemoteSession` into a row:

- **Main line:** `label`, else the title with a leading Claude spinner or
  "✳" glyph and space removed when the session is Claude, else the project.
- **Claude:** `@lostty_claude` is set, or the command looks like a Claude Code
  version (digits and dots).
- **Project:** from `pane_current_path`: a path containing
  `/.claude/worktrees/<name>` gives `<repo folder>/<name>`; otherwise the
  session name without a trailing `-<digits>`.
- **Second line:** project, "claude" or "shell", "Open on Mac" when `owner`
  is set.
- **Right side:** "Waiting"/"Working" from `@lostty_claude`, else relative
  `session_activity` ("now", "5m ago", "2h ago", "3d ago").
- **Order:** waiting first, then `session_activity` descending; owned
  sessions before unowned, which form the "Not open on Mac" section.

`SessionsScreen` rows use it (`TmuxRemote` names never show). The menu bar's
Sessions list uses the same function on the Mac's own list
(`TmuxClient.sessions()` with the same format).

### Renaming

- **Phone:** swipe → Rename (and the terminal's ⋯ menu) sets or clears
  `@lostty_label` over SSH, behind the same name guard as kill, then signals.
- **Mac:** "Rename Tab…" sets or clears `@lostty_label` on the focused pane's
  session as well as the tab title. The Mac reads labels on each change event
  (its own `wait-for` watcher thread) and shows a pane's label as its tab title
  override when the pane is focused, so a phone rename appears on the Mac.

### Claude state and "seen"

- The Mac writes `@lostty_claude` for every session it shows whenever
  `ClaudeRuntime` changes, then signals.
- On `client-attached`, the Mac's watcher checks the clients (as
  `AttachedPhones` does); a phone client on a waiting session clears that
  surface's waiting state, exactly like focusing it.

### Ends, reasons and the overlay (`TerminalScreen`, `RemoteSurfaceIO`)

- **Tagging:** `TmuxClient.endSessions(showing:)` tags `mac-close`,
  `endSessions(ownedBy:)` tags `mac-quit`, and the phone's kill tags
  `phone:<this phone's name>` (in the same SSH command, after the name
  guard), each as `set-option -g @lostty_end_<n> <reason> ; kill-session`.
- **On `.exited` while attached:** instead of dismissing, the phone reads
  `show-options -gqv @lostty_end_<n>` and whether the session still exists,
  then:
  - this phone ended it (its own Close Session; or no tag and this phone sent
    input in the last 3 s, i.e. you typed `exit` or Ctrl-D): dismiss, as now;
  - tag `mac-close`: overlay "Closed on your Mac";
  - tag `mac-quit`: "Lostty quit on your Mac";
  - tag `phone:<other>`: "Closed from <other>";
  - no tag, not this phone: "The shell exited";
  - the session still exists (this client was detached): dismiss and refresh
    the list, as now.
- **Overlay:** the terminal stops taking input and dims to ~35 %; a centred
  card shows the reason, the session's main-line label, and **Back to
  Sessions**. It stays until tapped.
- **Background:** if the attach ended while the app was in the background, or
  the reattach on return finds the session gone, the same overlay shows when
  the app becomes active.
- **Connection lost (`.lost`):** the same dark overlay reads "Connection lost
  — reconnecting…" with a spinner, and disappears when the attach is back.
  After 30 s it also offers Back to Sessions. It replaces the in-terminal
  "disconnected" line on the phone.

## Error handling

| Case | Behavior |
|---|---|
| No tmux server (no sessions) | Watch ends at once; list shows the empty state; watch retries with backoff |
| Watch connection drops | Re-list when it reconnects; the list keeps its last rows meanwhile |
| Reading the end reason fails | "This terminal was closed" |
| Rename fails (session gone, name guard) | Message on the list; the row is already gone or unchanged |
| An older Mac Lostty without the new options | Rows fall back to title/project; no Waiting badges; ends read "The shell exited" |
| Many events at once (closing a window of tabs) | Re-list at most every 300 ms |

## Testing

- `SessionLabel` unit tests: main-line precedence (label, Claude title with
  each spinner glyph and "✳", project), Claude detection, worktree project
  paths (nested folders, trailing slash, no worktree), `-N` stripping, relative
  activity text, ordering and sections.
- `TmuxRemote` tests: the longer list format parses (tabs, empty options,
  titles with spaces and emoji), rename and kill commands quote and tag
  correctly, the reason command.
- End-reason decision tests: each tag, no tag with recent and old input,
  session still present.
- Mac: `TmuxClient` builds the tagged kill commands; `@lostty_claude` writes
  follow `ClaudeRuntime` changes; spinner-only title changes don't signal.
- tmux.conf: hooks are present (string test like the existing config tests).
- Desk checks (MacBook + iPhone):
  1. Phone list open; close a Mac tab → its row disappears within ~1 s.
  2. Open a Mac tab → a row appears.
  3. Attached on the phone; close that tab on the Mac → overlay "Closed on
     your Mac" over the dimmed screen; Back to Sessions returns to the list.
  4. Quit Lostty on the Mac while attached → "Lostty quit on your Mac".
  5. Type `exit` on the phone → straight back to the list.
  6. Background the phone app, close the tab on the Mac, return → overlay.
  7. Turn the phone's Wi-Fi off and on while attached → "Connection lost —
     reconnecting…", then it clears.
  8. A Claude waiting on the Mac shows "Waiting" first in the list; attaching
     from the phone clears it and the menu bar dot.
  9. Rename on the phone → the Mac tab shows it when focused; Rename Tab… on
     the Mac → the phone row shows it; clearing restores the automatic label.
  10. A Claude in `.claude/worktrees/stay-awake` reads `lostty/stay-awake`.

## Out of scope

- Push notifications when a session ends or a Claude waits (the "Lostty phone
  push" spec).
- Renaming the tmux session names themselves.
- Git worktrees outside `.claude/worktrees/`.

## Risks

- `RemoteConnection` has no streaming command yet; the watch needs the SSH
  library's streaming exec (Citadel `executeCommandStream`). If it can't
  stream, the fallback is re-listing every 3 s while the list is visible.
- Several Mac Lostty processes (the test build next to the installed app)
  write `@lostty_claude` only for sessions they own, so they don't fight;
  both signal `lostty-changed`, which is harmless.
- Claude Code's title format may change; a title that doesn't start with a
  known glyph is shown as is.
