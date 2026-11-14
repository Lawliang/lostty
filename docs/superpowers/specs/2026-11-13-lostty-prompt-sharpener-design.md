# Lostty prompt sharpener — design

Date: 2026-11-13. Status: approved by the owner, not built.
Branch: `prompt-rewriter`. Visual version:
https://claude.ai/artifact/N9P2KT6bwxZbdRH6T8xUXR

## 1. Goal

The owner writes sloppy prompts: the goal is buried in backstory, there is
no done check, the prompt is padded with dictation filler, and sometimes it
says how to do the work or guesses the cause. They want each sloppy prompt
rewritten the way a senior engineer would type it before Claude (Opus or
Fable) sees it. They also want to see their original next to the rewrite in
Lostty, so they learn from it as they work.

Success: in a Lostty pane, a sloppy prompt reaches the model rewritten. A
strip under the terminal shows the original and the rewrite side by side,
with what was fixed. A clean prompt goes through untouched after the quick check
(a second or two; skipped prompts don't wait at all), and every prompt is
logged.

## 2. Decisions (from the owner)

- **The rewrite is natural language, not a structured format.** It reads
  like a message from a senior engineer: short, lowercase, goal first, one
  done check, the proof wanted, limits as plain phrases. It has no
  headings, labels or bullets. The voice comes from pstack's own example
  prompts (§6).
- **Rules first, then Haiku decides.** Simple rules let obvious cases
  through with no model call (§4). Haiku 5.5 judges every other prompt:
  sloppy or not. Sonnet 5.5 rewrites only the prompts Haiku flags.
- **Replace, don't attach.** The model sees only the rewrite. This needs a
  Claude Code mod (`prompt.submit`), because settings hooks can only add
  context or block.
- **Auto-send.** No review step. The strip shows what changed after the
  prompt is sent.
- **A strip in the pane** shows the latest rewrite. A coach card with
  habits over time is out of scope for now.
- **Log every prompt**, passed or rewritten, for metrics and history later.
- **On for every Lostty user.** It goes in Core (`main`), not an edition,
  and is on by default. The check and rewrite use each user's own Claude
  login. The log stays on their Mac. Builder call: the strip carries a
  "Turn off" control, so a user can switch it off where they first see it.

Ruled out:

- An attach-only settings hook: the slop still reaches the model.
- A review gate: it adds an Enter to every sloppy prompt.
- A structured rewrite (Goal:/Done:/Limits:): the owner rejected it as
  unlike how people talk to agents.
- Rule-only slop detection: too crude for free text. Rules only skip
  prompts that obviously need no check.

## 3. Pipeline

```
you type ⏎ in a Lostty pane
  → Claude Code fires prompt.submit
  → Lostty's mod runs  $LOSTTY_BIN +sharpen  (prompt on stdin)
      rules: skip?            → print the prompt unchanged
      Haiku: sloppy?   no     → print the prompt unchanged
                       yes    → Sonnet rewrites → print the rewrite
      every path: append a log line; on a rewrite, signal the pane
  → the mod swaps in stdout as the prompt text
  → Opus / Fable gets it
```

Any failure (timeout, bad exit, empty output, `claude` missing, not
signed in) sends the original unchanged. The sharpener must never block
or lose a prompt.

## 4. Rules that skip the model

These prompts go out as typed with no model call. Each is logged with
verdict `skipped` and its rule:

| Rule | Example |
|---|---|
| Slash command | `/commit`, `/loop 5m …` |
| Short follow-up (≤ 4 words) | `do it`, `continue`, `yes go` |
| `raw:` prefix | `raw: anything` — the prefix is removed |
| Claude Code's own notices | `<task-notification>…` prompts |
| Sharpener off | the menu toggle (§8) |
| Outside Lostty | no `LOSTTY_SURFACE` |
| Long paste (builder call: over ~4,000 characters) | a pasted log or file |

Images and other attachments are never touched: the mod changes only
`text` and passes the rest of the event through (`next({ ...e, text })`).

The word limit and the exact rule list are builder tuning. Keep them to
this table's intent.

## 5. The check (Haiku 5.5)

Haiku answers one question: is this prompt sloppy? It returns a verdict
and the tells it found. The six tells:

| Tell | Looks like |
|---|---|
| goal buried | "so I've been noticing… anyway what I want is…" |
| no done check | "make it better", "clean it up", "look into it" |
| filler | "go ahead and", "essentially", "you know", "like" |
| says the how | "first make a file called X, then add a struct…" |
| cause as fact | "it's broken, it's the gesture code" |
| tangled asks | "fix the tests and also maybe clean up and also…" |

Clean examples it must pass: "why did BranchesModelTests fail on the last
run?", "merge main into this branch and rerun the build". When unsure, it
passes.

## 6. The rewrite (Sonnet 5.5)

Rubric, from pstack (`poteto-help/references/prompting.md`, `sharpen`,
`in-your-own-words`, and the recipes in `poteto-help/references/recipes.md`):

- Put in: the goal, a done check that can fail, the proof to show, what
  the owner already knows (symptom, log, link), and real limits ("repro
  first", "don't change code yet", "let me review before you build").
- Leave out: the how, step lists, the owner's guess at the cause, filler,
  backstory.
- Never add a fact the owner didn't say. Choices that are the owner's stay
  open. If the intent can't be read, pass the original.
- Voice: lowercase, short sentences, no headings or bullets, a few
  sentences at most. Style guide: a dozen real lines from pstack's recipes,
  such as "investigate why <symptom>. give me what we know, what data you
  used, and your best hypotheses. don't change any code yet."

The rewrite also returns short labels for what it fixed ("goal first",
"done check", "−cause guess"), which the strip shows as chips.

Context: the rewrite gets the conversation's last two turns, so "fix it"
still knows what "it" is. The mod passes the session id and cwd. The
transcript is at `~/.claude/projects/<cwd slug>/<session id>.jsonl`.

Worked examples (they go into the rewrite prompt and the tests):

| Typed | Sent |
|---|---|
| the scroll thing is broken again can you look, i think its the gesture code | scrolling over a card stopped moving its terminal again. repro first, then fix it and show me a recording of it working. |
| can you make the canvas faster its kind of laggy when theres a lot of cards, maybe cache stuff or something | panning the canvas lags with a lot of cards open. measure it with 30 cards, fix the measured cause, and show me before and after. |
| ok so basically i want you to go through all the tests and like make sure they're good and fix whatever's broken and also maybe clean up the old ones | run the mac test suite and fix what fails. show me the passing run. list the tests you think are dead, but don't delete any yet. |
| add dark mode to settings, first make a file called SettingsTheme.swift then add a struct with the colors then wire it into the view | settings should use the app's dark palette, same colors as the canvas. show me a screenshot. |

## 7. Parts

1. **`lostty +sharpen`** (Zig, `src/cli/`). Reads the prompt on stdin and
   takes the pane id, session id and cwd as arguments. Runs the rules, the
   check and the rewrite, prints the prompt to send, appends the log line,
   and on a rewrite signals the pane. Model calls are
   `claude -p --safe-mode --model <haiku|sonnet> --tools ""` with a
   system prompt. `--safe-mode` turns off mods, hooks, plugins and
   CLAUDE.md, so the inner calls can't fire the sharpener or Lostty's
   hooks, and they still use the owner's Claude login. Unset
   `LOSTTY_SURFACE` for the child as well.
   Time caps: check ~4 s, rewrite ~10 s. Past a cap, the prompt is sent as
   typed (exact numbers are builder tuning).
2. **The mod** (bundled in the app's resources, like `lostty-skills`):
   `.claude-plugin/plugin.json`, `hooks/hooks.json` naming
   `./register.js`, and `hooks/register.js`:
   `on('prompt.submit', async ($, e, next) => …)` runs
   `$.process.run([bin, '+sharpen', …])` with the prompt, and calls
   `next({ ...e, text: stdout })` on success, else `next(e)`. Time inside
   `$.process.run` doesn't count against the hook's 10 s limit. A throw
   sends the original.
3. **Loading the mod only in Lostty panes**: the Mac app sets
   `CLAUDE_CODE_PLUGIN_DIRS` in each pane's environment, next to
   `LOSTTY_SURFACE` (`SurfaceView_AppKit.swift`), appending to any value
   already there. Nothing changes outside Lostty, and global settings are
   left alone. Panes run through tmux, which forwards env vars by name
   (`src/cli/tmux/session.zig`): add this one to that list. Builder call:
   Claude sessions already running don't get the mod; new or restarted
   ones do. Needs Claude Code ≥ 2.1.287 (installed: 2.1.325).
4. **The pane strip** (Swift, `macos/Sources/Features/Claude/`): a new
   `sharpened` message on the existing `LOSTTY_CLAUDE` OSC channel carries
   only the log entry id, because the OSC limit is 2048 bytes and prompts
   can be longer. The app reads the entry from the log. The strip shows
   "Sharpened" plus chips, and opens to yours and the rewrite side by side.
   It shows the latest rewrite only. Builder call: it clears on the pane's
   next `busy` (any new prompt), so it never shows a stale rewrite next to
   a clean prompt.
5. **The prompt log**: `~/Library/Application Support/Lostty/sharpener/log.jsonl`,
   one JSON line per prompt: time, pane, session, cwd, original, sent,
   verdict (`skipped`/`clean`/`rewritten`/`failed`), rule or tells,
   fixed-labels, models, check ms, rewrite ms. Append-only, never sent
   anywhere.
6. **On/off**: a Lostty menu toggle, on by default once built.
   `+sharpen` reads it from a flag file next to the log. Off means every
   prompt is sent as typed and logged as `skipped`.

## 8. First step: prove the mod swaps the text

Before building the rest, a throwaway mod that uppercases the prompt,
loaded with `--plugin-dir` in a Debug pane: check that the model receives
the new text, how the transcript shows it, and that `CLAUDE_CODE_PLUGIN_DIRS`
in the pane env loads it. If replacing doesn't work, fall back to a
`UserPromptSubmit` hook that attaches the rewrite as `additionalContext`,
and tell the owner first. Builder call: in that mode the log verdict is
`attached` and the strip says "Attached", not "Sharpened".

The same test measures the wait the check adds (cold `claude -p` plus
Haiku). Builder call: if it's well over 3 s, report it to the owner
before going on; a faster path (an API key or a long-lived process) is a
later change.

## 9. Not in this version

A coach card with habits over time, Codex panes, showing rewrites on the
iPhone, and learning the owner's own style. The log keeps what each of
these would need.

## 10. Left to the builder

Exact prompts for the check and the rewrite (within §5–6), the word limit
and time caps, the strip's look (dark palette, matching the pane's existing
task strip), how the toggle is stored, and test fixtures drawn from §5–6.
