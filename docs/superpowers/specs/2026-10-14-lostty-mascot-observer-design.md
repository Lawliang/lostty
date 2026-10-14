# Lostty mascot summary and turn observer — design

Status: draft for review (2026-10-14)

Builds on docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md (the
`+claude-state` hooks and the LOSTTY_CLAUDE user var) and the corner mascot
(`SidebarMascot`, now over the terminal's bottom-right corner).

## Goal

Tap the axolotl in the terminal's corner and it answers in a speech bubble:
what's been done in this terminal so far, and a plain-words (ELI5) version of
the agent's last reply. No more typing "say that again, explain like I'm
five".

The summaries come from an **observer**: whenever an agent finishes a turn in
a pane, Lostty reads that conversation's new prompts and replies and updates
its notes. The mascot is the observer's first use. Later uses, not designed
here, are recalling past summaries, observing how the developer works, and
suggesting better workflows.

### Success criteria

- In a pane where Claude has finished a turn, tapping the mascot opens the
  bubble at once (the observer already ran) with notes on this conversation
  (**Why you started this**, **What we decided together**, **What's built**,
  **What's left**) and **Just now**, the last reply in plain words.
- Tapping while Claude works opens a "…" bubble that fills in a few seconds
  after Claude stops.
- The same works in a Codex pane.
- Clicks and text selection anywhere else in the terminal's corner still reach
  the terminal.
- With Settings → "Summarize turns in the background" off, Lostty runs nothing
  until you tap.
- Lostty never uses an API key and never reads a file that isn't a Claude or
  Codex conversation.

## Facts this design rests on

- Claude Code's and Codex's Stop hook input both carry `transcript_path`, the
  conversation file (JSONL). Claude's Notification input carries it too. Our
  hooks already pipe that input into `+claude-state idle`
  (`src/cli/claude_state.zig`).
- `/clear`, or quitting and starting the agent again, starts a new file.
  `claude --continue` and `/compact` keep the same one.
- Claude's file: one JSON object per line. Prompts are `type:"user"` lines
  whose `message.content` is a string. Replies are `type:"assistant"` lines
  with `text` content items. Tool calls (`tool_use`), tool results (user lines
  whose content is `tool_result` items), `thinking`, `isMeta` and
  `isSidechain` lines, and the other line types (`attachment`, `system`,
  `mode`, …) are not conversation.
- Codex's file (`~/.codex/sessions/…/rollout-*.jsonl`): conversation is
  `type:"response_item"` lines with `payload.type:"message"`, role `user`
  (`input_text`) or `assistant` (`output_text`). `developer` messages,
  `function_call`, `function_call_output`, `reasoning` and `event_msg` lines
  are not. Codex also writes its own context into user messages as tagged
  blocks (`<environment_context>`, AGENTS.md instructions).
- Measured on this Mac with a one-sentence summary: `claude -p` with Haiku and
  `ClaudeCLI.arguments` took 2.5 s; `codex exec --ignore-user-config` took
  4.9 s (7.3 s without `--ignore-user-config`, which loads every plugin and
  MCP server). Both use the subscription login: `claude auth status` reports
  `"authMethod": "claude.ai"`, `codex login status` prints "Logged in using
  ChatGPT".
- `ClaudeCLI` and `BranchSummarizer` (`macos/Sources/Features/Branches/`)
  already find `claude` through the login shell and run it headless, with an
  environment of PATH only, so the run's own hooks can't report to Lostty.
- Apple's on-device model (FoundationModels) needs macOS 26 and Apple
  Intelligence on, and reads about 4,000 tokens. Lostty's deployment target is
  older, so it is used behind `#available`.

## 1. The hook carries the conversation file

`+claude-state idle` adds `"transcript":"<path>"` to its JSON when the hook
input has a `transcript_path`, for Stop (both agents) and Notification
(Claude asking). `protocol.zig` gets a `transcript` field on `Detail`;
`encodeSequence` emits it when set. A path longer than 1,024 bytes is
dropped. Other states never send it.

`ClaudeMessage.transcript(_:)` reads it on the Mac. `ClaudeRuntime` remembers
the latest path for each pane and hands it to the observer with the turn's
end.

## 2. Which files Lostty reads

Anything running in a pane can print a LOSTTY_CLAUDE user var, so the path is
not trusted. The observer reads a file only if, after resolving symlinks, it
is a `.jsonl` file under `~/.claude/projects/` or `~/.codex/sessions/` (or
`$CLAUDE_CONFIG_DIR/projects/` and `$CODEX_HOME/sessions/` when Lostty's own
environment sets them). Any other path is ignored, as if no path came. Only
lines that parse as conversation (§3) are ever sent to a summarizer.

## 3. Reading a conversation

`ConversationReader` (pure, unit tested) turns a file into **entries**, each
`you` or `agent` with its text, in order:

- **Claude:** prompts are user lines with string content, minus `isMeta`
  lines and Claude Code's own wrappers (`<command-name>`,
  `<local-command-stdout>`, `<system-reminder>` blocks). The agent's text is
  the `text` items of assistant lines; consecutive assistant lines within
  one turn join into one entry. `isSidechain` lines (subagents) are skipped.
- **Codex:** user and assistant `message` payloads, without `developer`
  messages and without the tagged blocks Codex adds to user messages.

It reads from a byte offset and returns the new entries plus the new offset,
so the observer reads only what's been added. A half-written last line is
left for next time. **The last reply** is the agent's text after your latest
prompt.

## 4. The observer

`TurnObserver` (main actor, app-wide) keeps, per conversation file, in memory
only:

- the notes: `why` (a sentence or two) and `asked` (what you asked for),
  `decided`, `built` with `progress` ("about two-thirds done", or empty when
  unclear), and `left`,
- `justNow`: the ELI5 of the last reply,
- `offset`: how far the file has been read,
- `turn`: an identity for the last reply summarized (the offset where it
  ends), so a tap knows whether the notes are current.

**When it runs.** On every `idle` that carries a transcript (the turn ended,
or Claude stopped to ask permission), when the switch is on. `agents` (Claude
waits on its subagents) doesn't trigger a run; the `idle` after does. With
the switch off, it runs only when a tap needs it.

**What it sends.**
- First run for a file (new conversation, or after Lostty restarts): every
  entry, cut from the oldest end to the newest 30,000 words.
- Later runs: the current notes, the entries since `offset`, and the last
  reply.

It asks for JSON with one key per note, `{"why": "…", "asked": ["…"],
"decided": ["…"], "built": ["…"], "progress": "…", "left": ["…"],
"just_now": "…"}`, written to the developer as "you" and to the developer
and agent together as "we". The lists are the updated notes: no length
limits, earlier bullets merged or reworded only when that makes a list
clearer, and a decision may start with a short label ("Look: …"). `just_now`
explains the last reply in plain words, for someone who didn't read it.
Missing keys are empty; an empty `just_now` doesn't parse. The prompt lives in `ObserverPrompt`,
like `SummaryPrompt`. A reply wrapped in a code fence still parses. A reply
that doesn't parse is an error (§6), and the notes stay as they were.

**One at a time.** One run per conversation at once. A turn that ends during
a run queues one more run, which reads everything since; more turns in the
meantime still mean only one more run. At most two runs across all panes;
the rest wait in order.

**Later uses.** Recall, behavior observation and workflow help will read the
observer's notes or subscribe to its turn-end events. Nothing here builds
them; they will add their own storage if they need history beyond the
conversation files, which Claude and Codex already keep on disk.

## 5. Who writes the summary

The observer tries these in order, checking sign-in once per app run and
again after a run fails with a sign-in error:

1. **Claude subscription.** `claude auth status` reports
   `"authMethod": "claude.ai"`. Runs `claude` with `ClaudeCLI.arguments`
   (Haiku, no tools, no MCP servers, no settings) and the prompt on stdin.
2. **ChatGPT sign-in.** `codex login status` says "Logged in using ChatGPT".
   Runs `codex exec --ignore-user-config --skip-git-repo-check --ephemeral
   -s read-only -c model_reasoning_effort=low -o <temp file>` with the
   prompt on stdin, on Codex's default model. `codex` is found like `claude`.
3. **Apple's on-device model**, when available. Its input is cut to fit: the
   current notes plus the newest 1,500 words.
4. **None:** the bubble says so (§6).

Both CLIs run with PATH as their only environment, from the temp directory,
with a 60-second timeout. An API key login (`authMethod` other than
`claude.ai`, or Codex signed in with a key) counts as not signed in.

## 6. The bubble

**Tapping.** The mascot becomes a button; everything else in the corner
overlay keeps passing clicks to the terminal. Tapping opens the bubble for
the focused pane's current conversation; tapping again, Esc, a click in the
terminal, or focus moving to another pane closes it. The axolotl shows its
`happy` pose while the bubble is open.

**What it shows.**
- Notes current for the last reply, at once, in this order, each section
  left out when empty:
  - **Why you started this**: `why`, then `asked` as bullets;
  - **What we decided together**: bullets;
  - **What's built (about two-thirds done)**: bullets, the brackets holding
    `progress` and dropped when it's empty;
  - **What's left**: bullets;
  - **Just now**: the plain-words last reply.
- The agent is working, or a run for the last reply is under way: "…",
  filling in when the run finishes. With the switch off, a tap mid-turn
  waits for the turn to end and then starts the run.
- No notes yet and none coming (switch off, turn already ended): starts a
  run and shows "…".
- No conversation file known for the pane: "Nothing to sum up yet."
- No summarizer: "Sign in to Claude Code or Codex, or turn on Apple
  Intelligence, to get summaries."
- A failed run: one line saying why (from `ClaudeCLI.interpret`'s message),
  plus the last good notes if there are any.

Closing the bubble while it waits stops waiting. A run the observer started
on its own keeps going; a run the tap started (switch off) is cancelled.

**Look.** A rounded bubble above the axolotl with a tail pointing at it,
about 340 points wide and at most half the terminal's height; longer content
scrolls inside it. Text in the bubble can be selected. It sits under open
extension overlays, like the mascot.

## 7. Settings and restarts

Settings gets "Summarize turns in the background", on by default, stored in
`UserDefaults.ghostty` like the sidebar's auto-hide.

Restart to Update carries each pane's conversation path in its handoff,
alongside `ClaudeCarry`, so a tap after a restart can summarize at once (a
first run, §4) instead of saying "Nothing to sum up yet". The notes themselves
aren't carried.

## Out of scope

- The phone.
- A copy button, saving notes to disk, and the observer's later uses.
- Panes with no agent (a plain shell).

## Testing

- **Zig** (`-Dtest-filter=claude protocol`): Stop and Notification input
  with `transcript_path` encode a `transcript` field; without it, none; other
  states never carry one; an over-long path is dropped.
- **Swift unit tests** (`macos/Tests/Claude/`):
  - `ClaudeMessage.transcript` decoding.
  - The path allow-list, including symlinks out of the allowed folders.
  - `ConversationReader` against small Claude and Codex fixtures: tool calls,
    tool results, thinking, meta, sidechain, wrappers, developer messages and
    Codex's tagged blocks are dropped; reading from an offset returns only
    new entries; a half-written last line waits.
  - `ObserverPrompt` first-run cut and incremental input; reply parsing, with
    and without a code fence, and a malformed reply.
  - Scheduling: one run per conversation, one queued follow-up, at most two
    at once.
  - Summarizer choice from given `auth status` / `login status` output,
    including API-key logins.
- **By hand on the Mac:** a Claude pane and a Codex pane, each tapped after a
  turn and mid-turn; the switch off; a click in the corner still reaching the
  terminal; a restart followed by a tap.
