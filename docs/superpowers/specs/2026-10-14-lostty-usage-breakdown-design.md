# Lostty usage breakdown — design

Status: draft for review (2026-10-14)

Builds on the usage bar (`ClaudeUsageBar`, `ClaudeUsageRuntime`,
`src/cli/claude/usage.zig`) and needs the conversation path that
docs/superpowers/specs/2026-10-14-lostty-mascot-observer-design.md §1 adds to
the `idle` hook message.

## Goal

Clicking the usage bar already lists the plan limits (Current session,
Weekly · all models, Weekly · Fable). Under each limit it should also show
roughly how much of it went to each part of your setup, so you can see where
your plan goes, and whether Lostty's own background work costs much.

There are two parts for now:

- **Claude Code**: your conversations in Lostty panes, their subagents
  included.
- **Lostty**: Claude runs Lostty starts by itself: the turn observer and
  mascot summaries, and branch summaries.

### Success criteria

- With Session at 42%, the popover shows under Current session
  "Claude Code ≈ 41 · Lostty ≈ 1", and the two always add up to the
  limit's number.
- The same under Weekly · all models, for the week.
- Turning the observer on for a day makes the Lostty number grow; turning it
  off stops it growing.
- Opening the popover never stalls the window, even with a week of large
  conversations.

## Facts this design rests on

- The limits come only as percentages, for the whole account: Claude Code's
  status line input has `rate_limits.five_hour` and `rate_limits.seven_day`,
  each a `used_percentage` and `resets_at`. Nothing breaks them down.
- Each reply in a Claude conversation file (`~/.claude/projects/…/*.jsonl`)
  is an assistant line with a `timestamp`, `message.model`, and
  `message.usage`: `input_tokens`, `output_tokens`,
  `cache_creation_input_tokens`, `cache_read_input_tokens`.
- One reply is written on several lines (one per content item), each with
  the same `message.id`, `requestId` and usage. In this repo's conversation
  file, 1,174 assistant lines are 565 replies. Counting lines would count
  replies up to four times.
- Subagents write their own files, in `<conversation id>/subagents/*.jsonl`
  next to the conversation's file.
- Lostty's own runs (`ClaudeCLI.arguments`) pass `--no-session-persistence`,
  so they leave no file. `claude -p --output-format json` prints the reply in
  `result`, with the run's `usage` and per-model `modelUsage`.
- Weekly · Fable shows "Not available" today; Lostty gets no number for it.

## 1. How the numbers are made

For a limit with percentage `P` and window `[start, now]`, where `start` is
`resetsAt − 5 hours` for the session and `resetsAt − 7 days` for the week:

1. Add up the **weighted tokens** of every Claude Code reply and every
   Lostty run whose time falls in the window.
2. Each part's number is `P × its weighted tokens ÷ both parts' weighted
   tokens`, shown rounded with ≈, or "<1" below 0.5.

Use outside these two parts (Claude Code elsewhere, claude.ai) gets folded
into them, so the numbers are estimates. The popover says so in one line:
"Estimated from Claude use in Lostty."

**Weighted tokens** stand in for how fast each reply uses up a limit, which
tracks API price. They're weighted by type and by model:

- input × 1, output × 5, cache writes × 1.25, cache reads × 0.1;
- Haiku × 1, Sonnet × 3, Opus × 5, Fable × 5, and any other model × 5.

The weights live in one table (`UsageWeights`) and only the ratios matter.
They're a guess where Anthropic publishes no exact figure: Fable is weighted
like Opus until better known.

Without a limit report, or with nothing counted in the window, the limit
shows no breakdown.

## 2. Which conversations are Claude Code in Lostty

`UsageLedger` keeps the conversation files that Lostty panes reported (the
`transcript` in `idle` messages), with when each was last reported. The paths
pass the same allow-list as the observer (spec §2 there) and are saved on
disk, since the week outlasts restarts. A file not reported in 8 days is
dropped.

A file's subagents count with it: every `.jsonl` in
`<file without .jsonl>/subagents/`.

## 3. Lostty's own runs

`ClaudeCLI.arguments` adds `--output-format json`. `ClaudeCLI.interpret`
returns the `result` text as before, plus the run's usage. Each run then
appends one record to the ledger: time, source (`observer` or
`branchSummary`), and its tokens per model from `modelUsage`. Records older
than 8 days are dropped. A run whose output can't be parsed as JSON records
nothing.

The observer's Codex and Apple fallbacks don't use Claude's plan and aren't
recorded.

## 4. Counting without stalling

`UsageCounter` reads files off the main thread. For each file it remembers
the offset it has read to and the replies it has counted (time, model,
tokens, keyed by `message.id` and `requestId`), so reopening the popover
reads only what was added. A half-written last line waits for next time. The
first count after Lostty starts reads each reported file once.

The popover asks for a count when it opens. Until it's done it shows the
limits as today, with "Counting…" where the breakdown goes. Counts are
reused for one minute.

## 5. The popover

Under the Current session and Weekly · all models rows, in the row's
secondary style:

```
Current session                ▓▓▓▓░░░░░░ 42%
Resets in 2h 14m
Claude Code ≈ 41 · Lostty ≈ 1
```

Weekly · Fable stays as it is. The footnote line sits at the bottom of the
popover. Rows keep working as today: clicking one tracks it in the bar.

## Out of scope

- Claude Code outside Lostty and claude.ai as their own parts.
- Codex and ChatGPT limits.
- Per-pane or per-project rows, and history charts.

## Testing

- **Swift unit tests** (`macos/Tests/Claude/`):
  - Reply counting from a fixture: repeated lines of one reply count once;
    replies outside the window don't count; subagent files count with their
    conversation; a half-written last line waits.
  - Weighting by token type and model, including an unknown model.
  - The split: the parts add up to `P`; "<1"; no breakdown with nothing
    counted or no limit report.
  - `ClaudeCLI.interpret` on JSON output: the text and the usage; plain or
    broken output gives the text and no usage, as today.
  - Ledger: recording a run, dropping records and files older than 8 days,
    the allow-list, and saving and loading.
- **By hand on the Mac:** open the popover with a few busy panes and check
  the numbers add up; run a branch summary and see the Lostty number grow.
