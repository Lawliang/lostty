# Lostty Prompt Sharpener Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In a Lostty pane, a sloppy prompt is rewritten in plain senior-engineer words before Claude sees it, the pane shows yours next to the rewrite, and every prompt is logged.

**Architecture:** A Claude Code mod (bundled in the app, loaded only in Lostty panes through `CLAUDE_CODE_PLUGIN_DIRS`) hands each submitted prompt to `lostty +sharpen`. `+sharpen` runs skip rules, a Haiku check and a Sonnet rewrite through `claude -p --safe-mode`, appends a log line, signals the pane over the existing `LOSTTY_CLAUDE` user var, and prints the text to send. The Mac app shows a strip under the usage bar.

**Tech Stack:** Zig (CLI, `src/cli/`), JavaScript (the mod), Swift/SwiftUI (`macos/Sources/Features/Claude/`).

**Spec:** `docs/superpowers/specs/2026-11-13-lostty-prompt-sharpener-design.md`

## Global Constraints

- Never block or lose a prompt: every failure prints the original text and exits 0.
- Models: check `--model haiku`, rewrite `--model sonnet`; both `claude -p --safe-mode --tools ""`, child env without `LOSTTY_SURFACE`.
- Time caps: check 4 s, rewrite 10 s.
- Skip rules: slash command, ≤ 4 words, `raw:` prefix (removed), `<task-notification>`, over 4,000 characters, off flag, no `LOSTTY_SURFACE`.
- Log: `~/Library/Application Support/Lostty/sharpener/log.jsonl`; off flag: `…/sharpener/off`.
- Verdicts: `skipped`, `clean`, `rewritten`, `failed`.
- Rewrite voice: lowercase, short sentences, no headings/labels/bullets, never adds facts.
- Core (`main`), on by default. Commit titles `lostty: sharpener: <what is now true>`.
- Claude Code ≥ 2.1.287.

## Review Focus

- A prompt with a pasted image: the image still reaches Claude (mod passes `...e`). Checked in Task 7's live run.
- `claude` not on PATH or not signed in: original sent, verdict `failed`. Test in Task 3.
- Model returns prose instead of JSON: original sent, verdict `failed`. Test in Task 2.
- Two panes submitting at once: log lines don't interleave (one `write` per line, `O_APPEND`). Test in Task 3.
- A prompt with quotes, newlines and unicode: logged and returned byte-exact when passed. Test in Task 2.

---

### Task 1: Spike — prove the mod swaps the prompt (throwaway)

**Files:** scratchpad only; nothing committed.

- [ ] **Step 1:** Write a mod in the scratchpad (`.claude-plugin/plugin.json`, `hooks/hooks.json` with `"modules": ["./register.js"]`, `hooks/register.js`) whose `prompt.submit` handler runs `$.process.run(['/bin/echo', 'SAY ONLY: swapped'])` and calls `next({ ...e, text: stdout.trim() })`.
- [ ] **Step 2:** In a detached tmux session, run `claude --plugin-dir <spike>` and send `hi`. Expected: Claude replies "swapped"; note what the transcript shows.
- [ ] **Step 3:** Repeat with `CLAUDE_CODE_PLUGIN_DIRS=<spike>` in the env instead of `--plugin-dir`. Expected: same result, no trust prompt (note it if there is one).
- [ ] **Step 4:** Find how the handler can pass text to a child: stdin option on `$.process.run`, or argv. Read `$.env.get('LOSTTY_SURFACE')`. Record the answers in this plan under Task 4.
- [ ] **Step 5:** Time `claude -p --safe-mode --model haiku --tools "" "reply ok"` three times. If well over 3 s, tell the owner before going on.

If Step 2 fails, stop and tell the owner (fallback: attach via `UserPromptSubmit`).

### Task 2: Sharpener logic (pure Zig)

**Files:**
- Create: `src/cli/sharpen/rules.zig`, `src/cli/sharpen/prompts.zig`, `src/cli/sharpen/log.zig`

**Interfaces:**
- Produces:
  - `rules.skip(text: []const u8) ?Skip` where `Skip = struct { rule: []const u8, send: []const u8 }` (`send` is `text` with `raw:` removed for that rule).
  - `prompts.check_system: []const u8`, `prompts.rewrite_system: []const u8` (the rubric, the six tells, the pstack style lines and the four worked examples from spec §5–6, embedded as text).
  - `prompts.checkInput(alloc, prompt, context) ![]u8`, `prompts.rewriteInput(alloc, prompt, context, tells) ![]u8`.
  - `prompts.parseCheck(alloc, out) ?Check` where `Check = struct { slop: bool, tells: []const []const u8 }`; model output `{"slop":bool,"tells":[…]}`, tolerating a fenced block.
  - `prompts.parseRewrite(alloc, out) ?Rewrite` where `Rewrite = struct { prompt: []const u8, fixed: []const []const u8 }`; output `{"prompt":"…","fixed":[…]}`; empty prompt → null.
  - `log.Entry` (fields per spec §7.5: `id, time, pane, session, cwd, original, sent, verdict, rule, tells, fixed, check_ms, rewrite_ms`) and `log.line(alloc, Entry) ![]u8` (one JSON line ending `\n`).
  - `log.lastTurns(alloc, transcript_jsonl: []const u8, n: usize, max_chars: usize) ![]u8` (the last `n` user/assistant text turns, each cut to `max_chars`).
  - `log.transcriptPath(alloc, home, cwd, session) ![]u8` (`~/.claude/projects/<cwd with / and . as ->/<session>.jsonl`).

- [ ] **Step 1: Write failing tests** in each file:
  - `skip("/commit")` → rule `slash`; `skip("do it")` → `short`; `skip("raw: fix the thing now please")` → `raw`, send `fix the thing now please`; `skip("<task-notification>…")` → `notice`; 4,001 chars → `long`; `skip("the scroll thing is broken again can you look")` → null.
  - `parseCheck` on `{"slop":true,"tells":["filler"]}`, on a ```json fenced copy, and on `Sure! It is sloppy.` → null.
  - `parseRewrite` with `{"prompt":"","fixed":[]}` → null.
  - `log.line` round-trips an original containing `"`, `\n` and `é` byte-exact through `std.json.parseFromSlice`.
  - `lastTurns` on a 4-line fixture transcript returns the last 2 turns' text only.
  - `prompts.rewrite_system` contains "never add" and none of "Goal:", "Done:".
- [ ] **Step 2:** Run `zig build test -Dtest-filter=sharpen` — expect FAIL.
- [ ] **Step 3:** Implement. Hook the three files into the test build the way `src/cli/claude/*.zig` are.
- [ ] **Step 4:** Run `zig build test -Dtest-filter=sharpen` — expect PASS.
- [ ] **Step 5:** Commit `lostty: sharpener: rules, prompts and log lines for the prompt sharpener`.

### Task 3: `lostty +sharpen` command

**Files:**
- Create: `src/cli/sharpen.zig`
- Modify: `src/cli/ghostty.zig` (add `@"sharpen"` next to `@"claude-state"`, run + Options)
- Modify: `src/cli/claude/protocol.zig` (add state `sharpened` carrying `{"id":"<entry id>"}`)

**Interfaces:**
- Consumes: everything Task 2 produces; `claude_state.openTerminal`, `claude_state.writeWhole`, `protocol.encodeSequence`.
- Produces: CLI `lostty +sharpen --pane=<uuid> --session=<id> --cwd=<path>`, prompt on stdin (or `--prompt-file=` per Task 1's answer). Prints the text to send on stdout, always exits 0. OSC payload `{"v":1,"state":"sharpened","id":"<entry id>"}`, only on `rewritten`.

- [ ] **Step 1: Write failing tests** (with an injectable runner instead of spawning `claude`):
  - runner returns `{"slop":false,"tells":[]}` → stdout is the original, verdict `clean`, no OSC.
  - runner returns slop then `{"prompt":"repro first.","fixed":["repro first"]}` → stdout `repro first.`, verdict `rewritten`, OSC with the entry's id.
  - runner fails to spawn (`error.FileNotFound`) → original, verdict `failed`.
  - runner exceeds the cap → original, verdict `failed`.
  - off flag present → original, verdict `skipped`, rule `off`, no model call.
  - two entries appended from two threads → two whole lines.
  - `encodeSequence(.sharpened, …)` decodes to the payload above.
- [ ] **Step 2:** Run `zig build test -Dtest-filter=sharpen` — expect FAIL.
- [ ] **Step 3:** Implement: rules → check → rewrite, each child `claude -p --safe-mode --model … --tools "" --system-prompt <…>` with `LOSTTY_SURFACE` removed from its env and a kill after the cap; append the log line with one `O_APPEND` write (create the folder); OSC on `rewritten`.
- [ ] **Step 4:** Run the tests — expect PASS. Then `zig build -Demit-macos-app=false` and a live run: `echo "ok so basically can you like make the tests better" | LOSTTY_SURFACE=x zig-out/bin/ghostty +sharpen --pane=x --session=none --cwd=$PWD` prints a lowercase rewrite; `tail -1` of the log shows `rewritten`.
- [ ] **Step 5:** Commit `lostty: sharpener: +sharpen checks a prompt and rewrites a sloppy one`.

### Task 4: The bundled mod

**Files:**
- Create: `mods/lostty-sharpener/.claude-plugin/plugin.json`, `mods/lostty-sharpener/hooks/hooks.json`, `mods/lostty-sharpener/hooks/register.js`, `mods/README.md`
- Modify: `src/build/GhosttyResources.zig` (install `mods/` to `share/ghostty/lostty-mods`, next to `lostty-skills`)

**Interfaces:**
- Consumes: Task 3's CLI. Task 1's answers on passing text and reading env.
- Produces: `<resources>/ghostty/lostty-mods/lostty-sharpener` (the plugin dir Task 5 points at).

- [ ] **Step 1:** Write `register.js`: on `prompt.submit`, read `LOSTTY_BIN` and `LOSTTY_SURFACE` from `$.env`; if either is missing, `next(e)`. Otherwise run `+sharpen` with the pane, `$.session.id` and `$.session.cwd`, a 20 s process timeout; on exit 0 with non-empty stdout, `next({ ...e, text: stdout })`, else `next(e)`.
- [ ] **Step 2:** `zig build -Demit-macos-app=false`; check `zig-out/share/ghostty/lostty-mods/lostty-sharpener/hooks/register.js` exists.
- [ ] **Step 3:** Live: tmux pane with `LOSTTY_SURFACE=x LOSTTY_BIN=$PWD/zig-out/bin/ghostty claude --plugin-dir zig-out/share/ghostty/lostty-mods/lostty-sharpener`, send a sloppy prompt; Claude's transcript shows the rewrite. Send `do it`; it passes unchanged.
- [ ] **Step 4:** Commit `lostty: sharpener: a bundled Claude Code mod sends each prompt through +sharpen`.

### Task 5: Load the mod in every Lostty pane

**Files:**
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (set `CLAUDE_CODE_PLUGIN_DIRS` next to `LOSTTY_BIN`)
- Modify: `macos/Sources/Features/Claude/ClaudeMessage.swift` (`ClaudeConstants.pluginDirsEnvKey`, `ClaudeConstants.sharpenerModPath(resources:existing:) -> String?`)
- Modify: `src/cli/tmux/session.zig` (`Env.plugin_dirs`, forwarded like `bin`)
- Test: `macos/Tests/Claude/ClaudeMessageTests.swift`, tests in `session.zig`

**Interfaces:**
- Produces: panes have `CLAUDE_CODE_PLUGIN_DIRS` = existing value (if any) + `:` + the mod path. Check the separator the docs give; if the spike showed `CLAUDE_CODE_PLUGIN_DIRS` doesn't load a mod, stop and report.

- [ ] **Step 1: Failing tests:** `sharpenerModPath(resources: "/A/Resources", existing: nil)` → `/A/Resources/ghostty/lostty-mods/lostty-sharpener`; with `existing: "/x"` → `/x:` + that path; with existing already containing it → unchanged. Zig: a session argv with `plugin_dirs` set contains `CLAUDE_CODE_PLUGIN_DIRS=`.
- [ ] **Step 2:** Run (`macos/build.nu --action test` filtered to ClaudeMessageTests; `zig build test -Dtest-filter=tmux`) — expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run — expect PASS.
- [ ] **Step 5:** Commit `lostty: sharpener: Lostty panes load the sharpener mod`.

### Task 6: The pane strip and the on/off toggle

**Files:**
- Create: `macos/Sources/Features/Claude/PaneSharpens.swift` (model), `macos/Sources/Features/Claude/SharpenStrip.swift` (view), `macos/Sources/Features/Claude/SharpenerLog.swift` (read entry by id, off flag)
- Modify: `ClaudeMessage.swift` (`static func sharpened(_ value: String) -> String?` entry id), `ClaudeRuntime.swift` (`userVarChanged`: on `sharpened`, `PaneSharpens.shared.show(id, entryID)`; on `busy`, `PaneSharpens.shared.clear(id)`), `ExtensionSidebarLayout.swift` (strip under `ClaudeUsageBar`), the Lostty app menu (toggle "Sharpen Prompts")
- Test: `macos/Tests/Claude/PaneSharpensTests.swift`

**Interfaces:**
- Produces: `SharpenerLog.entry(id: String, logURL: URL) -> SharpenEntry?` (`original, sent, fixed`), scanning from the file's end; `SharpenerLog.isOn` / `setOn(_:)` (off flag file); `PaneSharpens.shared.entries: [UUID: SharpenEntry]`.

- [ ] **Step 1: Failing tests:** `ClaudeMessage.sharpened("{\"v\":1,\"state\":\"sharpened\",\"id\":\"a1\"}")` → `"a1"`; malformed → nil. `SharpenerLog.entry` finds `a1` in a 3-line fixture, nil for a missing id. `setOn(false)` creates the flag file, `setOn(true)` removes it. `PaneSharpens`: `show` then a `busy` clear leaves no entry for the pane.
- [ ] **Step 2:** Run — expect FAIL.
- [ ] **Step 3:** Implement. Strip: dark palette like `PaneTaskStrip`; "Sharpened" + chips from `fixed`; click opens yours | sent side by side; a "Turn off" button calls `setOn(false)`. Menu toggle mirrors `isOn`.
- [ ] **Step 4:** Run — expect PASS.
- [ ] **Step 5:** Commit `lostty: sharpener: the pane shows yours next to the rewrite`.

### Task 7: Prove it in a Debug app, then install

- [ ] **Step 1:** `macos/build.nu` Debug with its own bundle ID; open a pane, run `claude`, send a sloppy prompt. Screenshot: the strip with chips, opened to yours | sent; Claude's transcript shows the rewrite. Send `do it`: no strip, log says `skipped`. Paste an image with a sloppy prompt: the image still reaches Claude.
- [ ] **Step 2:** Merge `main` into the branch; full suites: `zig build test`, `macos/build.nu --action test` (rerun `BranchesModelTests`/`NotesFolderTests` once if they fail).
- [ ] **Step 3:** `lostty +peers`; message `ask`/`conflict` peers and wait.
- [ ] **Step 4:** `macos/install.sh` (the owner asked for this install), matching the installed build's channel. Tell the owner to use Restart to Update.

Skipped here: PR and push. AGENTS.md: no PRs; merging into `main` waits for the owner.
