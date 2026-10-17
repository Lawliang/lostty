# Lostty observer handoff — design

Status: approved in conversation and grilled; for review (2026-10-16)

Builds on docs/superpowers/specs/2026-10-14-lostty-mascot-observer-design.md
(the turn observer and the mascot's bubble),
docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md (the
`+claude-state` hooks) and the usage bar's context feed (`+claude-usage`,
`ClaudeUsageRuntime`). Beta only, like the rest of the observer.

## Goal

Long conversations make an agent worse. Past a limit the user sets (say
300k tokens), Lostty tells the Claude Code agent in that pane to hand off at
the next **clean break** in its work: write a handoff, after which Lostty
clears the window and the fresh agent picks up where the old one stopped.

The limit only arms the handoff; the work decides when. At a seam (a feature
committed, a question asked) a fresh window loses nothing. Mid-workflow, a
handoff has to squeeze everything the agent gathered into a summary, which
breaks the context. So the agent, which knows where it is in its work,
judges the moment against a checklist Lostty gives it, and Lostty does what
the agent can't: clearing the window and starting the fresh one.

Why the owner wants it: mainly quality, also avoiding auto-compact firing at
a bad moment, and usage.

### Success criteria

- With the setting on and a limit of 300k, a Claude pane past 300k shows the
  handoff mark, and the agent gets the directive within its next tool call
  or prompt, even mid-run.
- At the next clean break the agent ends its turn with a handoff in its
  reply; within a few seconds Lostty clears the pane and the fresh agent
  continues the work (or waits, if the handoff says it was waiting on the
  user), with no typing from the user.
- Mid-debugging, with a half-made edit, or while a build or subagent runs,
  the agent does not hand off.
- Typing in the pane during the grace period cancels the clear.
- "Hand off at next break" in the bubble arms any Claude pane at once, with
  the setting on or off; "Don't hand off this conversation" disarms it.
- At the ceiling, a turn that ends idle without a handoff gets one typed
  nudge, and the agent hands off in that short turn.
- A fresh agent re-enters the workflow the old one was in (the skill it was
  following, its ledger), and after a waiting break restates the open
  question word for word.
- Nothing is written into the user's repo. The old conversation stays on
  disk (`claude --resume` reaches it); every handoff is kept in Lostty's
  handoffs folder.
- Setting off (the default): nothing changes from today.

## Scope

- **Claude Code only.** The pieces that know about Claude (the context feed,
  the hook output, `/clear`, the start hook) sit behind an agent adapter so
  Codex can be a second adapter later (it would read `token_count` from its
  conversation file, start fresh with `/new`, and has no after-tool or
  session-start hook). Codex is not built here.
- Beta only (`LosttyChannel.current.showsMascot`).
- Only panes open in a window on this Mac: hooks reach the app through the
  pane's terminal, so a tmux session with no Mac window attached (one
  started from the phone and never opened here) never arms. Settings says
  "in terminals open on this Mac".
- Nothing new on the phone in v1. A failed handoff leaves Claude waiting,
  which the phone's existing Waiting on You note already reports.
- Needs Lostty's Claude hooks installed (the existing Settings check) and
  the usage feed (the `+claude-usage` status line). A pane without either
  never arms.

## Facts this design rests on

Checked against Claude Code's hooks documentation
(https://code.claude.com/docs/en/hooks), 2026-10-16:

- `UserPromptSubmit`, `PostToolUse` and `SessionStart` hooks can add text to
  Claude's context: JSON stdout
  `{"hookSpecificOutput":{"hookEventName":"<event>","additionalContext":"…"}}`
  (`hookEventName` required). For `PostToolUse` it lands next to the tool
  result, so it reaches the agent mid-turn. It reaches Claude as a system
  reminder, not as a chat message. `PostToolUse` runs after successful tool
  calls only; an omitted matcher or `"*"` matches every tool.
- `/clear` fires `SessionStart` with `source: "clear"`. Its
  `additionalContext` is "added to Claude's context at the start of the
  conversation, before the first prompt".
- Each `additionalContext` string is capped at **10,000 characters**. Over
  it, Claude gets a file path and a 2,000-character preview, and is not told
  to read the file.
- Auto-compact: at the model's window; for 1M-window models at about 967k by
  default. Not something Lostty changes.
- `/clear` "starts a new conversation with empty context … while keeping
  project memory"; the previous conversation is saved and `/resume` reaches
  it (https://code.claude.com/docs/en/commands.md, …/sessions.md).
- Settled by the desk check (§9), Claude Code 2.1.302, 2026-10-17: `/clear`
  typed into the pane and one Return runs it (no extra Return for the
  slash-command menu). It keeps the permission mode (accept-edits), the
  model (Sonnet, started with `--model sonnet`) and `/add-dir` folders, so
  §4 step 6 types no `/model` and the Settings caption needs no warning.
- Also from the desk check: at a permission prompt Claude's title stops
  spinning, so Lostty's trace ends before the Notification hook reports the
  prompt, and Claude carries on after you approve with no new prompt. Which
  turn a Stop ends is therefore tracked from the hooks alone (a prompt or a
  tool start opens it, a Stop closes it), not from the trace.
- Claude's own context in a fresh window is about 45k here (system prompt,
  tools, memory, skills). A limit below that re-arms every fresh window at
  once and hands off in a loop; the 200k minimum keeps real settings clear of
  it, but a Debug override must stay above it (use 60000).

And in Lostty today (beta branch, main `c52b00ef5`):

- `+claude-usage` (status line) reports each pane's context as `used` (input
  + cache creation + cache read tokens) and `size` (`context_window_size`).
  `ClaudeUsageRuntime.shared.contexts[pane]` holds it, updated after each
  reply.
- Hooks run `"$LOSTTY_BIN" +claude-state <state>` with `LOSTTY_SURFACE` set
  to the pane's id. `+claude-state` never prints today. Installed events:
  UserPromptSubmit, Stop, SubagentStop, Notification, SessionEnd, PreToolUse.
- A Stop with a transcript path reaches the app as a turn end
  (`ClaudeRuntime.turnEnded` → `TurnEnd`), and the observer knows each
  pane's conversation file (`TurnObserver.panes`), switching a pane's file
  at most every 30 s.
- `Ghostty.Surface.sendText` and `sendKeyEvent` type into a pane.
- Restart to Update carries `ClaudeRuntime` and `TurnObserver` state across.

## 1. The practice (what the agent is told)

### When to hand off

Passing the limit arms a handoff. From then on the agent looks for the next
clean break:

**Clean breaks**
- A feature or plan task just finished and committed, tests green.
- It just asked the user a question or handed something back, and is waiting.
- The working tree is clean, or holds only changes it can describe in a
  sentence.

**Not a break**
- Mid-debugging, with hypotheses still open.
- A half-made edit, or tests failing for a reason it doesn't yet understand.
- Partway through reading code to understand something (most of that
  understanding lives only in the context).
- A background job, build or subagent still running.

**The ceiling** (§2): at it, hand off at the end of this turn even without a
clean break, with a fuller handoff. A deliberate handoff still beats an
auto-compact.

### What goes in the handoff

Only what git can't tell the next agent, under 8,000 characters:

1. **Goal**: what we're building and why, in two or three sentences.
2. **Where we are**: what's done (with commits), what's in progress, the
   exact next step.
3. **Decisions**: rulings made and options ruled out, with why, so the next
   agent doesn't reopen them.
4. **The user's instructions** from this conversation (for example "don't
   install on the phone", "ask before pushing", how they answer).
5. **Open threads**: a question waiting on the user, a hand test pending.
6. **Gotchas**: traps found (sandbox refusals, a flaky test, a wrong path).
7. **Pointers**: branch, worktree, spec, plan, key files.
8. **Active workflow**: the skill or process it was following and where it
   stood (for example "superpowers:executing-plans on <plan>, ledger at
   <path>, Task 3 next"), or "none". Required: without it the fresh agent
   carries on the work but drops the discipline (TDD gates, ledger lines,
   approval gates).

No code dumps, nothing `git log` or the files already say.

### The format

The agent ends its turn with the handoff as the last thing in its reply:

```
<lostty-handoff>
## Goal
…
## Where we are
…
## Decisions
…
## Your instructions
…
## Open threads
…
## Gotchas
…
## Pointers
…
## Active workflow
…
## Next
continue | wait
</lostty-handoff>
```

`Next` is `continue` (the fresh agent carries on with the next step) or
`wait` (it was waiting on the user; the fresh agent loads the handoff and
waits). Missing or unknown means `wait`. With `wait`, **Open threads** must
hold the open question word for word.

### What the fresh agent is told

The start hook gives it the handoff, prefixed: "You're continuing from a
handoff Lostty saved at <path> when the last window reached <used>. First
re-enter the Active workflow (invoke that skill again, read its ledger).
Check the branch and `git status` against the handoff before acting. If
anything disagrees, say so and wait." Then Lostty types
`Continue from the handoff.` (for `continue`) or
`Read the handoff, restate the open question word for word, and wait for me.`
(for `wait`).

## 2. Limits

Settings → Mascot (beta), under the observer's switch:

- **"Hand off long conversations"**: on/off, default **off** (it types into
  terminals; the user opts in).
- **"Hand off after"**: 200k, 300k, 400k, 500k, 600k; default **300k**.

Per pane, from the reported `size`:

- **Effective limit** = the setting, but no more than 70% of `size`. On a
  200k model a 300k setting is 140k; the setting's footnote says so ("On
  200k models: 140k").
- **Ceiling** = effective limit + 100k, but no more than 90% of `size`.
- **Reminders**: the directive goes in once on arming, again each 25k past
  the last time it was given, and in its ceiling wording once at the ceiling
  (then each 25k).

A Debug-only defaults key (`LosttyHandoffLimitOverride`, tokens) replaces the
setting for desk checks; release builds ignore it.

**On demand.** The bubble of any Claude pane (that qualifies, §Scope) shows
**"Hand off at next break"**, whether the setting is on or off: it arms the
pane at the limit level now, whatever its size. It has no ceiling and no
reminders after the first; the agent still picks the break. An armed pane's
bubble shows **"Don't hand off this conversation"** instead: it disarms the
pane until its conversation ends (the next conversation file), whichever way
it was armed.

## 3. What the user sees

- **Armed**: the usage bar's context figure gets a small handoff mark
  (tooltip "Will hand off at the next clean break"); the bubble adds a line:
  "Will hand off at the next clean break (312k of 300k)."
- **The handoff** is the agent's last reply, in the terminal.
- **Afterwards**: the bubble says "Fresh window: handed off at 312k after
  '<first line of Where we are>'", and the usage bar drops to the fresh
  window's size.
- **Saved**: each handoff is kept at
  `~/Library/Application Support/Lostty/handoffs/<project>/<yyyy-MM-dd HHmm>.md`
  (`<project>` is the pane's working directory's last component). The last
  50 per project are kept; older ones are deleted when a new one is saved.
  The bubble links to the folder.
- **Buttons**: "Hand off at next break" / "Don't hand off this
  conversation" (§2).
- **Failure**: "Handoff saved, but the fresh window didn't start. It's at
  <path>." in the bubble, and a Mac notification with the same words and the
  terminal's name (§4 step 7). Handoffs that work notify nothing.

## 4. How it runs

Per pane, the coordinator holds one state:

`idle → armed(level: limit | ceiling) → pending(handoff) → clearing → idle`

1. **Arm.** On each context report, the policy (§6) decides the level. On
   arming, the coordinator writes the pane's **state file**
   `~/Library/Application Support/Lostty/handoff/panes/<pane>.json`:
   (`panes/<pane>.json`: phase, level, whether the button armed it, the size
   when the directive was last queued, used, size, nudged, the saved
   handoff's path; the app's own record, which the hook never reads). Disarming (setting off, or the context
   dropping below the limit) deletes it.
2. **Directive.** The app decides when to speak (on arming, each 25k past
   the last time, and when the level rises) and then queues the directive
   (§1, ceiling wording at the ceiling) as `panes/<pane>.say`. On
   `UserPromptSubmit` and `PostToolUse` (Claude's own calls, not a
   subagent's), `+claude-state` takes that file (renaming it, so only one
   hook gets it) and prints it as `additionalContext`. No file: it prints
   nothing, as today.
3. **Handoff.** On a turn end (`Stop` with a transcript path) in an armed
   pane, the coordinator reads that turn's last assistant reply and looks for
   one `<lostty-handoff>` block (§6). Found and valid: it saves the handoff
   (§3) and moves to `pending`. Not found: stays armed, except at the
   ceiling (below).
   - **Ceiling nudge.** At the ceiling level, the first turn that ends idle
     without a handoff gets one typed prompt (after the same grace as
     step 4): `Write your handoff now: this window is at the Lostty context
     ceiling.` and Return. Once per arming; if that turn ends without a
     handoff too, nothing more is typed.
4. **Grace.** 3 s. Any key typed in that pane, or a new `UserPromptSubmit`,
   cancels: back to armed; the next reminder 25k later. And Lostty never
   types into a pane with keys typed since its last prompt (its prompt may
   hold half a message): a handoff then isn't taken; the bubble says
   "Didn't hand off: you were typing…" and the directive is queued again.
   The same holds for the ceiling nudge.
5. **Clear.** The coordinator queues the fresh window's text (the handoff,
   prefixed, §1) as `panes/<pane>.start`, then types `/clear` and Return
   into the pane.
6. **Fresh window.** `SessionStart` with `source: "clear"` runs
   `+claude-state`, which takes `panes/<pane>.start`, prints it as
   `additionalContext`, and reports `fresh` through `LOSTTY_CLAUDE`. Over
   9,000 characters: the first 7,500 plus "The full handoff is at <path>.
   Read it before acting." The coordinator then types, each followed by
   Return, `/model <alias>` if the desk check showed `/clear` drops the model
   (alias from the usage feed's model name), then the continue line (§1). It
   deletes the pane's files and goes back to idle. If the desk check shows
   the permission mode or `/add-dir` folders don't survive `/clear`, that is
   stated in Settings as a known limitation; Lostty does not try to restore
   them. The observer is
   told the pane's conversation file is changing on purpose, so the 30 s
   switch limit doesn't hold the pane on the old file.
7. **No fresh window.** No `SessionStart` report within 15 s of typing
   `/clear`: back to idle, state file deleted, the failure line in the bubble
   (§3). No retry in that conversation; it re-arms only in a new one.

At the ceiling the agent is told to hand off at the end of this turn. If it
still doesn't, nothing more happens: Lostty never interrupts or kills a
turn, and Claude's auto-compact stays the last resort.

Restart to Update carries each pane's state (its state file; a pane caught mid-handoff
comes back armed) like the observer's.

## 5. Safety rules

- Lostty types only into the pane the handoff came from, only after a Stop,
  and only `/clear`, the restore commands of §4 step 6, the continue line,
  and the one ceiling nudge, each followed by Return.
- Never while the agent is waiting on a permission prompt (the Notification
  state) or has subagents working (`agents`).
- One handoff per arming; no retries after a failed fresh window.
- The hook reads only `panes/<LOSTTY_SURFACE>.say` or `.start`, and only
  when `LOSTTY_SURFACE` is an uppercase UUID; never a path from elsewhere.
- Setting off: the coordinator deletes every state file and goes idle. The
  hooks with nothing queued print nothing.
- The hook stays fast and never fails: a missing or unreadable queued file is
  silence; it still exits 0 within the existing 5 s timeout.

## 6. Pieces

Each has one job and is tested alone.

- **`HandoffPolicy`** (Swift, pure): `(used, size, settings, last) →`
  level (none / limit / ceiling), effective limit, ceiling, and whether to
  speak. The 70% and 90% caps, the 25k reminder step.
- **`HandoffDirective`** (Swift, pure): the directive text for each level,
  with the checklist, the contents list and the format (§1), filled with the
  numbers. Kept under 4,000 characters. Queued as `panes/<pane>.say` so the
  Zig hook only copies it.
- **`HandoffExtract`** (Swift, pure): the last `<lostty-handoff>` block in a
  reply that is not inside a code fence; requires `Where we are`,
  `Active workflow` and `Next` (other sections may be missing; with
  `wait`, `Open threads` too); reads `Next`; returns the text or why not.
- **`HandoffStore`** (Swift): saves handoffs (§3), keeping the last 50 per
  project, and reads/writes/deletes state files, atomically.
- **`HandoffCoordinator`** (Swift, `@MainActor`, app): per-pane states (§4).
  Watches `ClaudeUsageRuntime.contexts`, turn ends and the hook reports;
  runs grace, clear, restore, continue and the ceiling nudge through an
  injected typist and clock; takes the bubble's two buttons; updates the
  bubble and the usage bar's mark; posts the failure notification. Agent-specific steps go
  through a `ContextHandoffAgent` adapter (Claude: `/clear`, the continue lines,
  the context source).
- **`+claude-state` speak path** (Zig): `busy` (UserPromptSubmit) and the
  new `done` (PostToolUse) take `panes/<pane>.say`; the new `start`
  (SessionStart, source `clear`) takes `panes/<pane>.start`. Each prints
  `hookSpecificOutput` JSON with the right `hookEventName`; `start` then
  reports `fresh` through `LOSTTY_CLAUDE`. Pure parts tested in Zig.
- **Hook install** (Zig): adds `PostToolUse` (`done`) and
  `SessionStart` (`start`); `UserPromptSubmit` keeps `busy` and
  speaks too. The Settings hooks check counts the new events, so an older
  install shows as "partial" and offers the update.
- **Settings** (Swift): the two controls in the Mascot section (§2).

## 7. Errors

| Case | What happens |
| --- | --- |
| No usage feed or hooks in the pane | Never arms. |
| Handoff block invalid (no `Where we are` or `Active workflow`, or `wait` with no `Open threads`) | Not taken; stays armed; the next directive says why ("Your handoff had no 'Active workflow'"). |
| Ceiling turn ends idle without a handoff | One typed nudge (§4 step 3); never a second. |
| "Don't hand off this conversation" while pending | Cancels the clear; nothing typed; disarmed until the next conversation. |
| Two blocks in one reply | The last one outside a code fence. |
| Saving the handoff fails | Stays armed, no clear; bubble: "Couldn't save the handoff: <reason>." |
| User types during grace | Cancelled; re-arms 25k later. |
| User typed (unsent) before the turn ended | Not taken; "Didn't hand off: you were typing…"; asked again at the next break. |
| Your own `/clear` in an armed pane | The start hook reports `cleared`; disarmed; the old window's context figure doesn't arm the new one. |
| After a handoff, the old context figure comes back | Ignored until the fresh window reports a new one. |
| `/clear` typed, no fresh window in 15 s | Idle, failure line, no retry in this conversation. |
| Pane closed or agent exits while pending | Idle; the saved handoff stays. |
| Handoff over the 10k hook cap | First 7,500 characters + "read the full one at <path>". |
| Setting turned off mid-pending | Cancels; nothing typed. |

## 8. Out of scope

Codex (adapter later); tmux sessions with no Mac window attached; the
phone showing the armed mark or handoffs (later, from the same data);
choosing a different limit per project or model; editing a handoff before
it's used; adding the observer's notes to a handoff; showing past handoffs
inside Lostty (the folder is enough); restoring a permission mode `/clear`
dropped; changing Claude's auto-compact settings.

## 9. Testing

- **Unit (Swift):** `HandoffPolicy` (300k on a 1M window, 300k on 200k →
  140k, ceiling caps, reminder steps, dropping below the limit);
  `HandoffDirective` (both levels, numbers, length); `HandoffExtract` (valid,
  missing sections, `Next` missing → wait, two blocks, a block inside a code
  fence, missing Active workflow, `wait` without Open threads);
  `HandoffStore` (keeps 50 per project); `HandoffCoordinator` with a fake
  typist and clock (arm → pending → grace → clear → loaded → restore →
  continue; typing cancels; no fresh window in 15 s → notification;
  setting off mid-pending; pane closed; the button arms with the setting
  off; "Don't hand off" disarms until the next conversation; the ceiling
  nudge is typed once and only once).
- **Unit (Zig):** the hook output's JSON; pane ids (an uppercase UUID only);
  taking a queued file once; a subagent's tool call left silent; the
  session source; the installer's new events and the partial status. (The
  9,000-character cap is applied by the app, tested in Swift.)
- **Desk check (real pane, Debug override at 20k):** run a small task to
  past 20k, see the mark and the directive; see it not hand off mid-edit;
  let it finish and commit; watch the handoff, `/clear`, and the fresh agent
  continue. This settles how the TUI takes the typed `/clear`, and whether
  `/clear` keeps the permission mode (start the agent in accept-edits), the
  model (pick a non-default one) and an `/add-dir` folder; record the
  answers in this spec's Facts and wire §4 step 6 to them.
