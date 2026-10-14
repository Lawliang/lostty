# Lostty Mascot Summary and Turn Observer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping the axolotl in the terminal's corner opens a speech bubble with notes on this conversation (why you started it, what we decided, what's built, what's left) and a plain-words "Just now" of the agent's last reply, kept up to date by an observer that runs when each turn ends.

**Architecture:** The `+claude-state idle` hook adds the conversation file's path (`transcript_path` from the Stop/Notification hook input) to the LOSTTY_CLAUDE user var. `ClaudeRuntime` hands each turn's end to a new app-wide `TurnObserver`, which checks the path against Claude's and Codex's own folders, reads only the new prompts and replies (`ConversationReader`), and asks a summarizer (Claude Haiku on the Claude subscription, then Codex on ChatGPT, then Apple's on-device model) to update its in-memory notes (`ObserverPrompt`). The mascot becomes a button whose popover shows `TurnObserver.content(pane:working:)`.

**Tech Stack:** Zig 0.15 (`src/cli/claude/protocol.zig`), Swift / SwiftUI / AppKit (macOS), Swift Testing, FoundationModels (macOS 26, behind `#available`), the `claude` and `codex` CLIs run headless through `ProcessRunner`.

**Spec:** `docs/superpowers/specs/2026-10-14-lostty-mascot-observer-design.md`

## Global Constraints

- Mac-only code: every new Swift file is wrapped in `#if os(macOS)` … `#endif`. `macos/Sources` and `macos/Tests` are Xcode synchronized folders: new files join the targets by themselves, so never edit `project.pbxproj` to add a file.
- New tests go in `macos/Tests/Observer/` (Swift Testing: `import Testing`, `@testable import Lostty`, `struct …Tests`, `@Test func …`), except additions to existing suites named in a task.
- Commands: Zig tests `zig build test -Dtest-filter="claude protocol"`; engine build `zig build -Demit-macos-app=false`; one Mac suite `macos/skins-test.sh <SuiteName>`; Mac build `macos/build.nu`. `swiftlint` and `prettier` aren't installed: skip them.
- Never use an API key. Order: Claude subscription (`claude auth status` → `"loggedIn": true` and `"authMethod": "claude.ai"`) → ChatGPT sign-in (`codex login status` contains "Logged in using ChatGPT") → Apple's on-device model → none.
- Claude run: `ClaudeCLI.arguments` (`-p --model haiku --tools "" --no-session-persistence --strict-mcp-config --setting-sources ""`), prompt on stdin. Codex run: `codex exec --ignore-user-config --skip-git-repo-check --ephemeral -s read-only -c model_reasoning_effort=low -o <temp file> -`, prompt on stdin, Codex's default model. Both from the temp directory, 60-second timeout (`ClaudeCLI.timeout`).
- Limits: `transcript_max` 1,024 bytes; CLI prompts carry at most the newest 30,000 words; Apple prompts at most 1,500; at most 2 runs at once across all panes; bubble 340 points wide, at most half the terminal's height, then it scrolls.
- Copy, exactly: "Why you started this", "What we decided together", "What's built", "What's built (<progress>)", "What's left", "Just now", "Nothing to sum up yet.", "Sign in to Claude Code or Codex, or turn on Apple Intelligence, to get summaries.", "Summarize turns in the background".
- Settings key: `LosttyObserverBackground` in `UserDefaults.ghostty`, default on.
- Commits: each task commits only its own files, staged by explicit path (`git add <paths>`), message prefixed `lostty: observer:` and ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `README.md` or `macos/ship-phone.sh`. The mascot-in-the-corner change (`SidebarMascot.swift`, `ExtensionSidebarLayout.swift`, `ExtensionSidebarView.swift`, `Axolotl.swift`, `SessionsScreen.swift`) is the user's uncommitted work: before Task 8, ask the user to commit it (or to approve committing it as its own commit); never fold it into a task commit. Never push.
- Another Claude session may edit this working tree: re-read a file right before editing it, anchor edits on quoted text, never revert changes you didn't make.
- Never install a build on the Mac or phone, run `macos/install-skins.sh`, or quit Lostty unless the user asks (Quit ends every terminal session). When testing the real CLIs, keep prompts tiny: the user pays for the tokens.

## Review Focus

1. **Lostty started from a shell that has `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` set** must still summarize on the subscription, never on the key: the summarizer's environment is built from a short allow-list, not inherited. Pinned in Task 5 (`theEnvironmentLeavesOutKeysAndPaneVariables`).
2. **Esc while the bubble is open** must close the bubble and never reach the terminal, where it would interrupt Claude. Pinned in Task 8 (Esc key monitor) and checked by hand in Task 9.
3. **Clicks and text selection next to the mascot** (the terminal's last columns and rows) must still reach the terminal: only the 56-point axolotl takes clicks. Pinned in Task 8 (the overlay is sized to the mascot, its height read from a background) and checked by hand in Task 9.
4. **The first tap after a restart on a huge conversation** (tens of MB, hundreds of thousands of words) must send at most 30,000 words and never read the file on the main thread. Pinned in Task 4 (`aLongConversationIsCutToTheNewestWords`) and Task 6 (the run reads inside a nonisolated function).
5. **A FIFO, directory or other non-regular file named `*.jsonl` inside an allowed folder** must not block or crash the reader. Pinned in Task 3 (`aFifoOrFolderIsNotRead`).

## Decisions This Plan Makes That the Spec Leaves Open

- The bubble is a SwiftUI `.popover` (transient): its arrow is the tail, and a click outside closes it. It floats above open extension overlays rather than under them; opening an extension is itself a click outside, which closes it.
- A local key monitor eats Esc while the bubble is open, so Esc can't reach Claude.
- The observer, not `ClaudeRuntime`, keeps each pane's conversation path, and only paths that pass the allow-list.
- Codex's own hooks file (`~/.codex/hooks.json`) may still run under `--ignore-user-config`; it can't report to Lostty because the run's environment has no `LOSTTY_SURFACE`.
- Claude prompts with images (a content array of `text` items and no `tool_result`) count as prompts; `isCompactSummary` lines don't; any prompt starting with a lowercase tag (`<bash-input>`, `<task-notification>`, …) is the agent's wrapper, not yours.
- A failed run doesn't move the read offset, so the next run retries the same turns; it also makes the observer look for a summarizer again.

---

## File Structure

| File | Responsibility |
|---|---|
| Modify `src/cli/claude/protocol.zig` | `Detail.transcript`, `transcript_max`, `transcriptPath`; `encodeSequence` emits `"transcript"` |
| Modify `src/cli/claude_state.zig` | `idle` sends the transcript path |
| Modify `macos/Sources/Features/Claude/ClaudeMessage.swift` | `ClaudeMessage.transcript(_:)` |
| Modify `macos/Sources/Features/Claude/ClaudeRuntime.swift` | `turnEnded` callback on an `idle` with a transcript |
| Create `macos/Sources/Features/Observer/TranscriptLocation.swift` | The allow-list: which paths may be read, and which agent wrote them |
| Create `macos/Sources/Features/Observer/ConversationReader.swift` | Conversation file → prompts and replies, read from an offset |
| Create `macos/Sources/Features/Observer/ObserverPrompt.swift` | `ObserverNotes`; the prompt (with word cuts) and parsing the JSON reply |
| Modify `macos/Sources/Helpers/ProcessRunner.swift` | `inheritEnvironment:` so a run gets only the environment it is given |
| Modify `macos/Sources/Features/Branches/ClaudeCLI.swift` | `locate(command:)` finds `codex` too |
| Create `macos/Sources/Features/Observer/Summarizer.swift` | `SummarizerKind`; sign-in checks; detect; run Claude, Codex or Apple |
| Create `macos/Sources/Features/Observer/TurnObserver.swift` | Notes per conversation, scheduling, `BubbleContent`, carry/restore |
| Create `macos/Sources/Features/Observer/ObserverPreferences.swift` | The "Summarize turns in the background" switch |
| Modify `macos/Sources/Features/Settings/SettingsView.swift`, `SettingsUI.swift` | The switch in Lostty Settings |
| Modify `macos/Sources/Features/Restart/RestartHandoff.swift`, `LosttyRestart.swift` | Carry each pane's conversation path across Restart to Update |
| Modify `macos/Sources/App/macOS/AppDelegate.swift` | Wire `ClaudeRuntime.turnEnded` to the observer; start detection |
| Modify `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | Forget a closed pane |
| Create `macos/Sources/Features/Extensions/MascotBubble.swift` | The bubble's view |
| Modify `macos/Sources/Features/Extensions/SidebarMascot.swift` | The mascot as a button with the bubble popover; Esc monitor |
| Modify `macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift` | Mascot takes clicks; passes half the terminal's height |
| Tests: `macos/Tests/Observer/*.swift` (new); additions to `macos/Tests/Claude/ClaudeMessageTests.swift`, `ClaudeRuntimeTests.swift`, `macos/Tests/Helpers/ProcessRunnerTests.swift`, `macos/Tests/Branches/ClaudeCLITests.swift`, `macos/Tests/Restart/RestartHandoffTests.swift` | |

---

### Task 1: The hook sends the conversation file

**Files:**
- Modify: `src/cli/claude/protocol.zig` (the `Detail` struct near line 18, `encodeSequence` near line 263, new tests at the end)
- Modify: `src/cli/claude_state.zig:18-46`

**Interfaces:**
- Consumes: nothing new.
- Produces: the LOSTTY_CLAUDE JSON for `idle` may carry `"transcript":"<absolute path>"`, after `"permission"` when both are present: `{"v":1,"state":"idle","permission":true,"transcript":"/t.jsonl"}`. Task 2 decodes it.

- [ ] **Step 1: Write the failing tests**

Append to `src/cli/claude/protocol.zig`:

```zig
test "claude protocol: transcriptPath reads Stop and Notification input" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try t.expectEqualStrings("/Users/a/.claude/projects/p/s.jsonl", transcriptPath(
        alloc,
        "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"/Users/a/.claude/projects/p/s.jsonl\"}",
    ).?);
    try t.expectEqualStrings("/Users/a/.codex/sessions/r.jsonl", transcriptPath(
        alloc,
        "{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"transcript_path\":\"/Users/a/.codex/sessions/r.jsonl\"}",
    ).?);
    try t.expect(transcriptPath(alloc, "{\"hook_event_name\":\"Stop\"}") == null);
    try t.expect(transcriptPath(alloc, "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"  \"}") == null);
    try t.expect(transcriptPath(alloc, "{\"hook_event_name\":\"Stop\",\"transcript_path\":42}") == null);
    try t.expect(transcriptPath(alloc, "{\"hook_event_name\":\"PreToolUse\",\"transcript_path\":\"/x.jsonl\"}") == null);
    try t.expect(transcriptPath(alloc, "not json") == null);
    try t.expect(transcriptPath(alloc, "") == null);
}

test "claude protocol: transcriptPath drops an over-long path" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const at_max = "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"/" ++ "a" ** (transcript_max - 1) ++ "\"}";
    try t.expectEqual(@as(usize, transcript_max), transcriptPath(alloc, at_max).?.len);
    const over = "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"/" ++ "a" ** transcript_max ++ "\"}";
    try t.expect(transcriptPath(alloc, over) == null);
}

test "claude protocol: encodeSequence carries the transcript" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const done = try encodeSequence(alloc, .idle, .{ .transcript = "/Users/a/.claude/projects/p/s.jsonl" }, false);
    try t.expectEqualStrings(
        "{\"v\":1,\"state\":\"idle\",\"transcript\":\"/Users/a/.claude/projects/p/s.jsonl\"}",
        try decodeSequence(alloc, done),
    );
    const asks = try encodeSequence(alloc, .idle, .{ .permission = true, .transcript = "/t.jsonl" }, false);
    try t.expectEqualStrings(
        "{\"v\":1,\"state\":\"idle\",\"permission\":true,\"transcript\":\"/t.jsonl\"}",
        try decodeSequence(alloc, asks),
    );
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zig build test -Dtest-filter="claude protocol"`
Expected: compile error, `transcriptPath` / `transcript_max` undeclared and `Detail` has no field `transcript`.

- [ ] **Step 3: Implement**

In `src/cli/claude/protocol.zig`, replace the `Detail` struct and add the constant after `action_max`:

```zig
/// What a message says beyond its state.
pub const Detail = struct {
    /// `tool`: what the tool call does, as `action` words it.
    action: ?[]const u8 = null,
    /// `idle`: Claude asks permission to run the last action.
    permission: bool = false,
    /// `idle`: the conversation file the Stop or Notification hook named,
    /// for the Mac's turn observer.
    transcript: ?[]const u8 = null,
};

/// The longest action sent, in characters.
pub const action_max = 80;

/// The longest conversation file path sent, in bytes; a longer one is
/// dropped rather than cut.
pub const transcript_max = 1024;
```

Add after `isPermissionPrompt`:

```zig
/// The conversation file a Stop or Notification hook's input names
/// (`transcript_path`, which Claude Code and Codex both send). Null for
/// other events, a missing or blank path, or one longer than
/// `transcript_max` bytes. The Mac decides whether to read it.
pub fn transcriptPath(alloc: Allocator, input: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return null;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return null;
    const event = stringField(root, "hook_event_name") orelse return null;
    if (!std.mem.eql(u8, event, "Stop") and !std.mem.eql(u8, event, "Notification")) return null;
    const path = textField(root, "transcript_path") orelse return null;
    if (path.len > transcript_max) return null;
    return alloc.dupe(u8, path) catch null;
}
```

In `encodeSequence`, add the field to the struct literal and update the doc comment:

```zig
/// OSC 1337 SetUserVar carrying `{"v":1,"state":"<state>"}`, plus
/// `"action"`, `"permission":true` and `"transcript"` when `detail` has
/// them. With `tmux`, wrapped in tmux's DCS passthrough (requires
/// `allow-passthrough on`).
pub fn encodeSequence(alloc: Allocator, state: State, detail: Detail, tmux: bool) ![]u8 {
    const json = try std.json.Stringify.valueAlloc(alloc, .{
        .v = 1,
        .state = @tagName(state),
        .action = detail.action,
        .permission = if (detail.permission) true else null,
        .transcript = detail.transcript,
    }, .{ .emit_null_optional_fields = false });
```

In `src/cli/claude_state.zig`, the `.idle, .resumed` arm becomes:

```zig
        .idle, .resumed => if (hookInput(alloc)) |input| {
            state = protocol.refine(alloc, state, input) orelse return 0;
            detail.permission = state == .idle and protocol.isPermissionPrompt(alloc, input);
            if (state == .idle) detail.transcript = protocol.transcriptPath(alloc, input);
        },
```

and add to the command's doc comment, after "marks Claude asking permission.": "An `idle` also names the conversation file, for the Mac's turn observer."

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zig build test -Dtest-filter="claude protocol"`
Expected: PASS, including the existing `encodeSequence round-trips through base64` (an empty `Detail` still encodes `{"v":1,"state":"idle"}`).

- [ ] **Step 5: Build the engine and format**

Run: `zig fmt src/cli/claude/protocol.zig src/cli/claude_state.zig && zig build -Demit-macos-app=false`
Expected: no output from `zig fmt` beyond file names it changed; build succeeds.

- [ ] **Step 6: Commit**

```bash
git add src/cli/claude/protocol.zig src/cli/claude_state.zig
git commit -m "lostty: observer: the idle hook names the conversation file

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The Mac hears the turn's end with its conversation file

**Files:**
- Modify: `macos/Sources/Features/Claude/ClaudeMessage.swift`
- Modify: `macos/Sources/Features/Claude/ClaudeRuntime.swift` (`userVarChanged`, near line 51)
- Test: `macos/Tests/Claude/ClaudeMessageTests.swift`, `macos/Tests/Claude/ClaudeRuntimeTests.swift`

**Interfaces:**
- Consumes: the `"transcript"` field from Task 1.
- Produces: `ClaudeMessage.transcript(_ value: String) -> String?`; `ClaudeRuntime.turnEnded: @MainActor (UUID, String) -> Void` (pane, raw path), called after `apply` for every `idle` that carries a transcript. Task 7 sets it.

- [ ] **Step 1: Write the failing tests**

Add to `ClaudeMessageTests`:

```swift
    @Test func readsAnIdlesTranscript() {
        // Exact JSON `+claude-state idle` encodes (see protocol.zig).
        #expect(ClaudeMessage.transcript(#"{"v":1,"state":"idle","transcript":"/Users/a/.claude/projects/p/s.jsonl"}"#)
            == "/Users/a/.claude/projects/p/s.jsonl")
        #expect(ClaudeMessage.transcript(#"{"v":1,"state":"idle","permission":true,"transcript":"/t.jsonl"}"#) == "/t.jsonl")
        #expect(ClaudeMessage.decode(#"{"v":1,"state":"idle","transcript":"/t.jsonl"}"#) == .idle)
        #expect(ClaudeMessage.transcript(#"{"v":1,"state":"idle"}"#) == nil)
        #expect(ClaudeMessage.transcript(#"{"v":1,"state":"idle","transcript":""}"#) == nil)
        #expect(ClaudeMessage.transcript(#"{"v":1,"state":"busy","transcript":"/t.jsonl"}"#) == nil)
        #expect(ClaudeMessage.transcript(#"{"v":2,"state":"idle","transcript":"/t.jsonl"}"#) == nil)
    }
```

Add to `ClaudeRuntimeTests`:

```swift
    final class Ended {
        var turns: [(pane: UUID, path: String)] = []
    }

    @Test func anIdleWithATranscriptTellsTheObserver() {
        let runtime = makeRuntime()
        let ended = Ended()
        runtime.turnEnded = { ended.turns.append(($0, $1)) }
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("busy"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: #"{"v":1,"state":"idle","transcript":"/t.jsonl"}"#)
        // No transcript, or not an idle: nothing to observe.
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("idle"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: #"{"v":1,"state":"busy","transcript":"/t.jsonl"}"#)
        #expect(ended.turns.count == 1)
        #expect(ended.turns.first?.pane == pane)
        #expect(ended.turns.first?.path == "/t.jsonl")
        // The trace still saw the idle.
        #expect(runtime.phases[pane] != nil) // the last busy
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh ClaudeMessageTests`
Expected: FAIL to compile: `ClaudeMessage` has no member `transcript`.

- [ ] **Step 3: Implement**

In `ClaudeMessage.swift`, after `isPermission`:

```swift
    /// The conversation file an `idle` names (`"transcript":"…"`), for the
    /// turn observer; nil for anything else. Only a hint: anything in a pane
    /// can print this user var, so TranscriptLocation decides what is read.
    static func transcript(_ value: String) -> String? {
        guard let object = object(value), object["state"] as? String == "idle",
              let path = object["transcript"] as? String, !path.isEmpty else { return nil }
        return path
    }
```

In `ClaudeRuntime.swift`, after the `actions` property:

```swift
    /// An agent finished its turn (or stopped to ask permission) in a pane,
    /// naming its conversation file: the turn observer's cue. Set at launch.
    var turnEnded: @MainActor (UUID, String) -> Void = { _, _ in }
```

and the end of `userVarChanged` becomes:

```swift
        apply(state, to: id, permission: ClaudeMessage.isPermission(value))
        if state == .idle, let path = ClaudeMessage.transcript(value) { turnEnded(id, path) }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh ClaudeMessageTests && macos/skins-test.sh ClaudeRuntimeTests`
Expected: both `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Claude/ClaudeMessage.swift macos/Sources/Features/Claude/ClaudeRuntime.swift \
  macos/Tests/Claude/ClaudeMessageTests.swift macos/Tests/Claude/ClaudeRuntimeTests.swift
git commit -m "lostty: observer: hand each turn's end and conversation file on

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Which files may be read, and reading them

**Files:**
- Create: `macos/Sources/Features/Observer/TranscriptLocation.swift`
- Create: `macos/Sources/Features/Observer/ConversationReader.swift`
- Test: `macos/Tests/Observer/TranscriptLocationTests.swift`, `macos/Tests/Observer/ConversationReaderTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum TranscriptAgent: Equatable, Sendable { case claude, codex }`
  - `struct TranscriptLocation: Equatable, Sendable { var url: URL; var agent: TranscriptAgent; static func allowed(_ path: String, home: String = NSHomeDirectory(), environment: [String: String] = ProcessInfo.processInfo.environment) -> TranscriptLocation? }`
  - `struct ConversationEntry: Equatable, Sendable { enum Speaker { case you, agent }; var speaker: Speaker; var text: String }`
  - `struct ConversationChunk: Equatable, Sendable { var entries: [ConversationEntry]; var offset: UInt64; var restarted: Bool }`
  - `enum ConversationReader` with `parse(_ data: Data, agent: TranscriptAgent) -> (entries: [ConversationEntry], consumed: Int)`, `read(_ location: TranscriptLocation, from offset: UInt64) -> ConversationChunk?`, `append(_ new: [ConversationEntry], to entries: inout [ConversationEntry])`, `tail(_ tail: [ConversationEntry], adding new: [ConversationEntry]) -> [ConversationEntry]`, `lastReply(_ tail: [ConversationEntry]) -> String`.

- [ ] **Step 1: Write the failing allow-list tests**

`macos/Tests/Observer/TranscriptLocationTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct TranscriptLocationTests {
    /// A fake home with Claude's and Codex's folders, one conversation in
    /// each, and a secret outside them.
    struct Home {
        let root: String
        var claude: String { root + "/.claude/projects/-proj/s.jsonl" }
        var codex: String { root + "/.codex/sessions/2026/10/14/rollout-x.jsonl" }
        var secret: String { root + "/secret.jsonl" }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)").path
            for file in [root + "/.claude/projects/-proj/s.jsonl", root + "/.codex/sessions/2026/10/14/rollout-x.jsonl",
                         root + "/secret.jsonl"] {
                try FileManager.default.createDirectory(
                    atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: file, contents: Data("{}\n".utf8))
            }
        }
    }

    @Test func claudesAndCodexsConversationsAreAllowed() throws {
        let home = try Home()
        #expect(TranscriptLocation.allowed(home.claude, home: home.root, environment: [:])?.agent == .claude)
        #expect(TranscriptLocation.allowed(home.codex, home: home.root, environment: [:])?.agent == .codex)
    }

    @Test func anythingElseIsNot() throws {
        let home = try Home()
        #expect(TranscriptLocation.allowed(home.secret, home: home.root, environment: [:]) == nil)
        #expect(TranscriptLocation.allowed("/etc/passwd", home: home.root, environment: [:]) == nil)
        #expect(TranscriptLocation.allowed(".claude/projects/-proj/s.jsonl", home: home.root, environment: [:]) == nil)
        #expect(TranscriptLocation.allowed(home.root + "/.claude/projects/-proj/../../secret.jsonl",
                                           home: home.root, environment: [:]) == nil)
        #expect(TranscriptLocation.allowed(home.root + "/.claude/projects/-proj/missing.jsonl",
                                           home: home.root, environment: [:]) == nil)
        let notJSONL = home.root + "/.claude/projects/-proj/notes.txt"
        FileManager.default.createFile(atPath: notJSONL, contents: Data())
        #expect(TranscriptLocation.allowed(notJSONL, home: home.root, environment: [:]) == nil)
    }

    @Test func aSymlinkOutOfTheFoldersIsNotFollowed() throws {
        let home = try Home()
        let link = home.root + "/.claude/projects/-proj/link.jsonl"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: home.secret)
        #expect(TranscriptLocation.allowed(link, home: home.root, environment: [:]) == nil)
    }

    @Test func theAgentsOwnConfigFoldersCount() throws {
        let home = try Home()
        let custom = home.root + "/custom-claude"
        try FileManager.default.createDirectory(atPath: custom + "/projects/p", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: custom + "/projects/p/s.jsonl", contents: Data())
        #expect(TranscriptLocation.allowed(custom + "/projects/p/s.jsonl", home: home.root, environment: [:]) == nil)
        #expect(TranscriptLocation.allowed(custom + "/projects/p/s.jsonl", home: home.root,
                                           environment: ["CLAUDE_CONFIG_DIR": custom])?.agent == .claude)
    }
}
#endif
```

- [ ] **Step 2: Write the failing reader tests**

`macos/Tests/Observer/ConversationReaderTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ConversationReaderTests {
    static let claude = [
        #"{"type":"user","message":{"role":"user","content":"Fix the login bug"}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Looking at it."},{"type":"tool_use","id":"t1","name":"Read","input":{}}]}}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"SECRET FILE"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Fixed it."}]}}"#,
        #"{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>x</local-command-caveat>"}}"#,
        #"{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"}}"#,
        #"{"type":"user","message":{"role":"user","content":"<bash-input>ls</bash-input>"}}"#,
        #"{"type":"user","isSidechain":true,"message":{"role":"user","content":"subagent prompt"}}"#,
        #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"subagent reply"}]}}"#,
        #"{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued"}}"#,
        #"{"type":"attachment","attachment":{}}"#,
        #"{"type":"user","message":{"role":"user","content":"Thanks <system-reminder>noise</system-reminder>now ship it"}}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Look at this"},{"type":"image","source":{}}]}}"#,
    ].joined(separator: "\n") + "\n"

    static let codex = [
        #"{"type":"session_meta","payload":{"id":"x"}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"sandbox rules"}]}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>\n  <cwd>/tmp</cwd>\n</environment_context>"}]}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions for /tmp\n\n<INSTRUCTIONS>x</INSTRUCTIONS>"}]}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"count to 3"}]}}"#,
        #"{"type":"response_item","payload":{"type":"reasoning","summary":[]}}"#,
        #"{"type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{}"}}"#,
        #"{"type":"response_item","payload":{"type":"function_call_output","output":"SECRET"}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"1"}]}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"2, 3"}]}}"#,
        #"{"type":"event_msg","payload":{"type":"agent_message","message":"2, 3"}}"#,
    ].joined(separator: "\n") + "\n"

    @Test func claudeKeepsOnlyPromptsAndReplies() {
        let parsed = ConversationReader.parse(Data(Self.claude.utf8), agent: .claude)
        #expect(parsed.entries == [
            ConversationEntry(speaker: .you, text: "Fix the login bug"),
            ConversationEntry(speaker: .agent, text: "Looking at it.\n\nFixed it."),
            ConversationEntry(speaker: .you, text: "Thanks now ship it"),
            ConversationEntry(speaker: .you, text: "Look at this"),
        ])
        #expect(parsed.consumed == Self.claude.utf8.count)
    }

    @Test func codexKeepsOnlyPromptsAndReplies() {
        let parsed = ConversationReader.parse(Data(Self.codex.utf8), agent: .codex)
        #expect(parsed.entries == [
            ConversationEntry(speaker: .you, text: "count to 3"),
            ConversationEntry(speaker: .agent, text: "1\n\n2, 3"),
        ])
    }

    @Test func aHalfWrittenLastLineWaits() {
        let whole = #"{"type":"user","message":{"role":"user","content":"hi"}}"# + "\n"
        let data = Data((whole + #"{"type":"assistant","message":{"ro"#).utf8)
        let parsed = ConversationReader.parse(data, agent: .claude)
        #expect(parsed.entries == [ConversationEntry(speaker: .you, text: "hi")])
        #expect(parsed.consumed == whole.utf8.count)
    }

    @Test func garbageLinesAreSkipped() {
        let data = Data("not json\n[1]\n\n".utf8)
        #expect(ConversationReader.parse(data, agent: .claude).entries.isEmpty)
    }

    func file(_ text: String) throws -> TranscriptLocation {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("conv-\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: url)
        return TranscriptLocation(url: url, agent: .claude)
    }

    @Test func readingFromAnOffsetReturnsOnlyWhatsNew() throws {
        let first = #"{"type":"user","message":{"role":"user","content":"one"}}"# + "\n"
        let location = try file(first)
        let chunk = try #require(ConversationReader.read(location, from: 0))
        #expect(chunk.entries == [ConversationEntry(speaker: .you, text: "one")])
        #expect(chunk.offset == UInt64(first.utf8.count))
        #expect(!chunk.restarted)

        let handle = try FileHandle(forWritingTo: location.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((#"{"type":"user","message":{"role":"user","content":"two"}}"# + "\n").utf8))
        try handle.close()
        let next = try #require(ConversationReader.read(location, from: chunk.offset))
        #expect(next.entries == [ConversationEntry(speaker: .you, text: "two")])
    }

    @Test func aShorterFileIsReadFromTheStart() throws {
        let location = try file(#"{"type":"user","message":{"role":"user","content":"new"}}"# + "\n")
        let chunk = try #require(ConversationReader.read(location, from: 10_000))
        #expect(chunk.restarted)
        #expect(chunk.entries == [ConversationEntry(speaker: .you, text: "new")])
    }

    @Test func aFifoOrFolderIsNotRead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fifo = dir.appendingPathComponent("pipe.jsonl")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(ConversationReader.read(TranscriptLocation(url: fifo, agent: .claude), from: 0) == nil)
        let folder = dir.appendingPathComponent("folder.jsonl")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(ConversationReader.read(TranscriptLocation(url: folder, agent: .claude), from: 0) == nil)
    }

    @Test func theTailStartsAtTheLatestPrompt() {
        let you = ConversationEntry(speaker: .you, text: "go")
        let a = ConversationEntry(speaker: .agent, text: "part one")
        let b = ConversationEntry(speaker: .agent, text: "part two")
        // A permission prompt ended the first run mid-reply; the rest came later.
        let first = ConversationReader.tail([], adding: [ConversationEntry(speaker: .you, text: "old"), you, a])
        #expect(first == [you, a])
        let second = ConversationReader.tail(first, adding: [b])
        #expect(second == [you, ConversationEntry(speaker: .agent, text: "part one\n\npart two")])
        #expect(ConversationReader.lastReply(second) == "part one\n\npart two")
        #expect(ConversationReader.tail(second, adding: [ConversationEntry(speaker: .you, text: "next")])
            == [ConversationEntry(speaker: .you, text: "next")])
        #expect(ConversationReader.lastReply([ConversationEntry(speaker: .you, text: "next")]) == "")
    }
}
#endif
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `macos/skins-test.sh TranscriptLocationTests`
Expected: FAIL to compile: cannot find `TranscriptLocation`, `ConversationReader`, `ConversationEntry`.

- [ ] **Step 4: Implement `TranscriptLocation`**

`macos/Sources/Features/Observer/TranscriptLocation.swift`:

```swift
#if os(macOS)
import Foundation

/// Which agent wrote a conversation file.
enum TranscriptAgent: Equatable, Sendable {
    case claude, codex
}

/// A conversation file the turn observer may read (spec §2). Anything in a
/// pane can print a LOSTTY_CLAUDE user var, so a path from a hook is only a
/// hint: it must resolve, through any symlinks and `..`, to an existing
/// `.jsonl` file under Claude's or Codex's own folders.
struct TranscriptLocation: Equatable, Sendable {
    var url: URL
    var agent: TranscriptAgent

    static func allowed(
        _ path: String,
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TranscriptLocation? {
        guard path.hasPrefix("/"), let resolved = realPath(path), resolved.hasSuffix(".jsonl") else { return nil }
        for (root, agent) in roots(home: home, environment: environment) {
            guard let base = realPath(root) else { continue }
            if resolved.hasPrefix(base + "/") {
                return TranscriptLocation(url: URL(fileURLWithPath: resolved), agent: agent)
            }
        }
        return nil
    }

    /// Claude's projects and Codex's sessions, in their default homes and
    /// wherever Lostty's own environment moves them.
    static func roots(home: String, environment: [String: String]) -> [(String, TranscriptAgent)] {
        var roots: [(String, TranscriptAgent)] = [(home + "/.claude/projects", .claude), (home + "/.codex/sessions", .codex)]
        if let dir = environment["CLAUDE_CONFIG_DIR"], dir.hasPrefix("/") { roots.append((dir + "/projects", .claude)) }
        if let dir = environment["CODEX_HOME"], dir.hasPrefix("/") { roots.append((dir + "/sessions", .codex)) }
        return roots
    }

    /// The path with every symlink and `..` resolved; nil when it doesn't exist.
    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
#endif
```

- [ ] **Step 5: Implement `ConversationReader`**

`macos/Sources/Features/Observer/ConversationReader.swift`:

```swift
#if os(macOS)
import Foundation

/// One prompt you typed, or the agent's text for a stretch of its turn.
struct ConversationEntry: Equatable, Sendable {
    enum Speaker: Equatable, Sendable {
        case you, agent
    }

    var speaker: Speaker
    var text: String
}

/// What a read found past an offset.
struct ConversationChunk: Equatable, Sendable {
    var entries: [ConversationEntry]
    /// Where the next read starts: just past the last whole line.
    var offset: UInt64
    /// The file was shorter than the offset asked for (it was rewritten),
    /// so this chunk reads it from the start.
    var restarted: Bool
}

/// Turns a Claude Code or Codex conversation file (JSONL) into your prompts
/// and the agent's replies, without tool calls, tool output, thinking,
/// subagents or the agents' own context (spec §3).
enum ConversationReader {
    /// The entries in `data`'s whole lines, and how many bytes those lines
    /// take; a half-written last line is left for the next read.
    static func parse(_ data: Data, agent: TranscriptAgent) -> (entries: [ConversationEntry], consumed: Int) {
        var entries: [ConversationEntry] = []
        var start = data.startIndex
        var consumed = 0
        while let newline = data[start...].firstIndex(of: 0x0A) {
            let line = data[start..<newline]
            start = data.index(after: newline)
            consumed = start - data.startIndex
            guard !line.isEmpty,
                  let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let entry = agent == .claude ? claudeEntry(object) : codexEntry(object) else { continue }
            append([entry], to: &entries)
        }
        return (entries, consumed)
    }

    /// The entries after `offset` in a regular file; nil when it can't be
    /// read (or isn't a regular file: a FIFO would block).
    static func read(_ location: TranscriptLocation, from offset: UInt64) -> ConversationChunk? {
        let path = location.url.path
        guard let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType,
              type == .typeRegular,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let restarted = end < offset
        let start = restarted ? 0 : offset
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        let data = (try? handle.readToEnd()) ?? Data()
        let parsed = parse(data, agent: location.agent)
        return ConversationChunk(entries: parsed.entries, offset: start + UInt64(parsed.consumed), restarted: restarted)
    }

    /// Appends `new`, joining the agent's consecutive stretches (text, tool
    /// calls, more text) into one entry.
    static func append(_ new: [ConversationEntry], to entries: inout [ConversationEntry]) {
        for entry in new {
            if entry.speaker == .agent, let last = entries.last, last.speaker == .agent {
                entries[entries.count - 1].text = last.text + "\n\n" + entry.text
            } else {
                entries.append(entry)
            }
        }
    }

    /// Your latest prompt and everything after it, given the last tail and
    /// what's new. Without a prompt in `new`, the reply carries on.
    static func tail(_ tail: [ConversationEntry], adding new: [ConversationEntry]) -> [ConversationEntry] {
        if let index = new.lastIndex(where: { $0.speaker == .you }) { return Array(new[index...]) }
        var result = tail
        append(new, to: &result)
        return result
    }

    /// The agent's text after your latest prompt.
    static func lastReply(_ tail: [ConversationEntry]) -> String {
        tail.filter { $0.speaker == .agent }.map(\.text).joined(separator: "\n\n")
    }

    // MARK: - Claude Code

    private static func claudeEntry(_ object: [String: Any]) -> ConversationEntry? {
        guard object["isSidechain"] as? Bool != true, object["isMeta"] as? Bool != true,
              object["isCompactSummary"] as? Bool != true,
              let message = object["message"] as? [String: Any] else { return nil }
        switch object["type"] as? String {
        case "user":
            let raw: String
            if let text = message["content"] as? String {
                raw = text
            } else if let items = message["content"] as? [[String: Any]],
                      !items.contains(where: { $0["type"] as? String == "tool_result" }) {
                // A prompt with an image: its text items.
                raw = texts(items, type: "text").joined(separator: "\n")
            } else {
                return nil
            }
            let text = withoutReminders(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isWrapper(text) else { return nil }
            return ConversationEntry(speaker: .you, text: text)
        case "assistant":
            guard let items = message["content"] as? [[String: Any]] else { return nil }
            let text = texts(items, type: "text").joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : ConversationEntry(speaker: .agent, text: text)
        default:
            return nil
        }
    }

    /// `<system-reminder>…</system-reminder>` blocks Claude Code adds to prompts.
    private static func withoutReminders(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "<system-reminder>"),
              let close = result.range(of: "</system-reminder>", range: open.upperBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return result
    }

    // MARK: - Codex

    private static func codexEntry(_ object: [String: Any]) -> ConversationEntry? {
        guard object["type"] as? String == "response_item",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "message",
              let items = payload["content"] as? [[String: Any]] else { return nil }
        switch payload["role"] as? String {
        case "user":
            let text = texts(items, type: "input_text")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !isWrapper($0) }
                .joined(separator: "\n")
            return text.isEmpty ? nil : ConversationEntry(speaker: .you, text: text)
        case "assistant":
            let text = texts(items, type: "output_text").joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : ConversationEntry(speaker: .agent, text: text)
        default:
            return nil
        }
    }

    // MARK: - Shared

    private static func texts(_ items: [[String: Any]], type: String) -> [String] {
        items.compactMap { $0["type"] as? String == type ? $0["text"] as? String : nil }
    }

    /// Text the agent's program wrote into the user's turn, not a prompt:
    /// a leading tag (`<command-name>`, `<bash-input>`, `<task-notification>`,
    /// Codex's `<environment_context>`) or Codex's AGENTS.md block.
    static func isWrapper(_ text: String) -> Bool {
        text.range(of: #"^<[a-z][a-z0-9_-]*>"#, options: .regularExpression) != nil
            || text.hasPrefix("# AGENTS.md instructions")
    }
}
#endif
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `macos/skins-test.sh TranscriptLocationTests && macos/skins-test.sh ConversationReaderTests`
Expected: both `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Observer/TranscriptLocation.swift macos/Sources/Features/Observer/ConversationReader.swift \
  macos/Tests/Observer/TranscriptLocationTests.swift macos/Tests/Observer/ConversationReaderTests.swift
git commit -m "lostty: observer: read prompts and replies from allowed conversation files

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The observer's prompt and its reply

**Files:**
- Create: `macos/Sources/Features/Observer/ObserverPrompt.swift`
- Test: `macos/Tests/Observer/ObserverPromptTests.swift`

**Interfaces:**
- Consumes: `ConversationEntry` (Task 3).
- Produces:
  - `struct ObserverNotes: Encodable, Equatable, Sendable { var why: String; var asked: [String]; var decided: [String]; var built: [String]; var progress: String; var left: [String]; var justNow: String }`, with an initializer whose every argument but `justNow` defaults to empty (`ObserverNotes(built: ["a"], justNow: "b")`).
  - `enum ObserverPrompt { static let cliWords = 30_000; static let appleWords = 1_500; static func build(previous: ObserverNotes?, earlier: [ConversationEntry], lastReply: String, words: Int) -> String; static func parse(_ reply: String) -> ObserverNotes?; static func wordCount(_ text: String) -> Int }`

The notes follow the shape the user asked for (spec §4): **Why you started this** (a sentence or two, then what you asked for), **What we decided together**, **What's built** (with how far along, when clear), **What's left**, then **Just now**.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Observer/ObserverPromptTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ObserverPromptTests {
    func words(_ word: String, _ count: Int) -> String {
        Array(repeating: word, count: count).joined(separator: " ")
    }

    @Test func aFirstRunHasNoNotesYet() {
        let prompt = ObserverPrompt.build(
            previous: nil,
            earlier: [ConversationEntry(speaker: .you, text: "Fix the login bug")],
            lastReply: "Fixed it.", words: ObserverPrompt.cliWords)
        #expect(prompt.contains("Your notes so far:\n(none yet)"))
        #expect(prompt.contains("You: Fix the login bug"))
        #expect(prompt.contains("The agent's last reply:\nFixed it."))
        for key in ["why", "asked", "decided", "built", "progress", "left", "just_now"] {
            #expect(prompt.contains("\"\(key)\""))
        }
    }

    @Test func laterRunsCarryTheNotes() {
        let previous = ObserverNotes(why: "Login was broken.", built: ["Fixed the login bug"], justNow: "Fixed.")
        let prompt = ObserverPrompt.build(
            previous: previous,
            earlier: [ConversationEntry(speaker: .you, text: "Now add tests"),
                      ConversationEntry(speaker: .agent, text: "Sure")],
            lastReply: "Added two tests.", words: ObserverPrompt.cliWords)
        #expect(prompt.contains(#""built":["Fixed the login bug"]"#))
        #expect(prompt.contains(#""why":"Login was broken.""#))
        #expect(prompt.contains("You: Now add tests\n\nAgent: Sure"))
    }

    @Test func nothingNewSaysSo() {
        let prompt = ObserverPrompt.build(previous: ObserverNotes(justNow: "x"), earlier: [], lastReply: "", words: 100)
        #expect(prompt.contains("Conversation since then:\n(nothing new)"))
        #expect(prompt.contains("The agent's last reply:\n(none)"))
    }

    @Test func theOldestEntriesGoFirst() {
        // 40 words: the reply takes 10, the context the newest 30.
        let earlier = (0..<4).map { ConversationEntry(speaker: .you, text: words("alpha\($0)", 10)) }
        let prompt = ObserverPrompt.build(previous: nil, earlier: earlier, lastReply: words("reply", 10), words: 40)
        #expect(!prompt.contains("alpha0"))
        #expect(prompt.contains("alpha1") && prompt.contains("alpha2") && prompt.contains("alpha3"))
    }

    @Test func anEntryThatDoesntFitKeepsItsEnd() {
        // Tokens that never appear in the prompt's own instructions.
        let entry = ConversationEntry(speaker: .agent, text: words("qqq", 5) + " " + words("zzz", 10))
        let prompt = ObserverPrompt.build(previous: nil, earlier: [entry], lastReply: "", words: 10)
        #expect(prompt.contains("Agent: … " + words("zzz", 10)))
        #expect(!prompt.contains("qqq"))
    }

    @Test func aLongReplyTakesAtMostHalf() {
        let prompt = ObserverPrompt.build(
            previous: nil, earlier: [ConversationEntry(speaker: .you, text: "go")],
            lastReply: words("start", 50) + " " + words("end", 50), words: 100)
        #expect(prompt.contains("The agent's last reply:\n… " + words("end", 50)))
        #expect(prompt.contains("You: go"))
    }

    @Test func aLongConversationIsCutToTheNewestWords() {
        let earlier = (0..<400).map { ConversationEntry(speaker: $0.isMultiple(of: 2) ? .you : .agent, text: words("w\($0)", 100)) }
        let prompt = ObserverPrompt.build(previous: nil, earlier: earlier, lastReply: words("reply", 100),
                                          words: ObserverPrompt.cliWords)
        let header = ObserverPrompt.build(previous: nil, earlier: [], lastReply: "", words: ObserverPrompt.cliWords)
        // Plus one "You:"/"Agent:" label per entry kept (at most 300) and the "…" of a cut.
        #expect(ObserverPrompt.wordCount(prompt) <= ObserverPrompt.cliWords + ObserverPrompt.wordCount(header) + 301)
        #expect(prompt.contains("w399"))
        #expect(!prompt.contains("w0 "))
    }

    @Test func parsesTheReply() {
        let reply = #"""
        {"why":"Login was broken.","asked":["Fix login"],"decided":["Look: keep the old screen"],
         "built":["Fixed login"],"progress":"done","left":["Add tests"],"just_now":"It works now."}
        """#
        #expect(ObserverPrompt.parse(reply) == ObserverNotes(
            why: "Login was broken.", asked: ["Fix login"], decided: ["Look: keep the old screen"],
            built: ["Fixed login"], progress: "done", left: ["Add tests"], justNow: "It works now."))
    }

    @Test func parsesAFencedOrIntroducedReply() {
        // Missing keys are empty; list markers and blank bullets are dropped.
        let fenced = "```json\n{\"built\": [\"- Fixed login\", \"  \"], \"just_now\": \" It works. \"}\n```"
        #expect(ObserverPrompt.parse(fenced) == ObserverNotes(built: ["Fixed login"], justNow: "It works."))
        #expect(ObserverPrompt.parse("Here you go: {\"just_now\":\"Hi\"}") == ObserverNotes(justNow: "Hi"))
    }

    @Test func rejectsAMalformedReply() {
        #expect(ObserverPrompt.parse("not json") == nil)
        #expect(ObserverPrompt.parse(#"{"built":["a"]}"#) == nil)
        #expect(ObserverPrompt.parse(#"{"built":["a"],"just_now":"  "}"#) == nil)
        #expect(ObserverPrompt.parse(#"{"built":"a","just_now":"b"}"#) == nil)
        #expect(ObserverPrompt.parse("") == nil)
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh ObserverPromptTests`
Expected: FAIL to compile: cannot find `ObserverPrompt`, `ObserverNotes`.

- [ ] **Step 3: Implement**

`macos/Sources/Features/Observer/ObserverPrompt.swift`:

```swift
#if os(macOS)
import Foundation

/// What the observer knows about one conversation, in the bubble's order.
/// No list has a length limit.
struct ObserverNotes: Encodable, Equatable, Sendable {
    /// Why the session started, in a sentence or two.
    var why = ""
    /// What the developer asked for.
    var asked: [String] = []
    /// What the developer and the agent decided together.
    var decided: [String] = []
    /// What's done and working.
    var built: [String] = []
    /// How far along, in a few words ("about two-thirds done"); empty when unclear.
    var progress = ""
    /// What's still to do, and anything waiting on the developer.
    var left: [String] = []
    /// The agent's last reply in plain words.
    var justNow: String

    enum CodingKeys: String, CodingKey {
        case why, asked, decided, built, progress, left
        case justNow = "just_now"
    }
}

/// The prompt for one observer run, and reading its JSON reply (spec §4).
enum ObserverPrompt {
    /// The most words a Claude or Codex run carries.
    static let cliWords = 30_000
    /// Apple's on-device model reads about 4,000 tokens.
    static let appleWords = 1_500

    /// `previous`: the notes so far. `earlier`: what's new since they were
    /// written, up to and including your latest prompt. `lastReply`: the
    /// agent's text since that prompt. The reply gets up to half of
    /// `words`; the newest of `earlier` gets the rest.
    static func build(previous: ObserverNotes?, earlier: [ConversationEntry], lastReply: String, words: Int) -> String {
        let reply = keepingNewest(lastReply, words: words / 2)
        let context = cut(earlier, toWords: words - wordCount(reply))
        let notes = previous.flatMap(json) ?? "(none yet)"
        let conversation = context.isEmpty ? "(nothing new)" : context.map {
            ($0.speaker == .you ? "You: " : "Agent: ") + $0.text
        }.joined(separator: "\n\n")
        return """
        You keep notes on a coding session in a terminal, for the developer running it. Call the developer \
        "you", and the developer and the agent together "we". Below are your notes so far (JSON), the \
        conversation since then (the developer's prompts and the coding agent's replies, with tool calls left \
        out), and the agent's last reply.

        Answer with JSON only, no code fence:
        {"why": "…", "asked": ["…"], "decided": ["…"], "built": ["…"], "progress": "…", "left": ["…"], "just_now": "…"}
        - why: why the developer started this session, in a sentence or two.
        - asked: what they asked for, one short bullet each.
        - decided: what we decided together, one bullet each. Start a bullet with a short label and a colon \
        when that helps ("Look: …").
        - built: what's done and working, one bullet each.
        - progress: how far along the work is, in a few words ("about two-thirds done"), or "" when unclear.
        - left: what's still to do, and anything waiting on the developer.
        - just_now: the agent's last reply explained like the developer is five: plain words, short sentences, \
        what it means for them, and anything it needs from them.
        Keep what your notes say unless the conversation changed it, and add what's new. Merge or reword \
        bullets only when that makes a list clearer. No length limits. Leave a list empty when nothing fits it.

        Your notes so far:
        \(notes)

        Conversation since then:
        \(conversation)

        The agent's last reply:
        \(reply.isEmpty ? "(none)" : reply)
        """
    }

    /// The notes in a reply, which may be wrapped in a code fence or follow
    /// a sentence. Missing keys are empty; nil when it isn't a JSON object,
    /// a key has the wrong type, or `just_now` is empty.
    static func parse(_ reply: String) -> ObserverNotes? {
        guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close,
              let wire = try? JSONDecoder().decode(Wire.self, from: Data(reply[open...close].utf8)),
              let justNow = wire.justNow.map(trimmed), !justNow.isEmpty else { return nil }
        func list(_ items: [String]?) -> [String] { (items ?? []).map(bullet).filter { !$0.isEmpty } }
        return ObserverNotes(
            why: trimmed(wire.why ?? ""), asked: list(wire.asked), decided: list(wire.decided),
            built: list(wire.built), progress: trimmed(wire.progress ?? ""), left: list(wire.left),
            justNow: justNow)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private struct Wire: Decodable {
        var why, progress, justNow: String?
        var asked, decided, built, left: [String]?

        enum CodingKeys: String, CodingKey {
            case why, asked, decided, built, progress, left
            case justNow = "just_now"
        }
    }

    /// Compact, sorted JSON, so the model sees its own format back.
    private static func json(_ notes: ObserverNotes) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(notes)).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A bullet without the list marker a model sometimes adds.
    private static func bullet(_ text: String) -> String {
        var line = trimmed(text)
        for marker in ["- ", "• ", "* "] where line.hasPrefix(marker) {
            line = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    /// The newest entries that fit in `words`; one that straddles the cut
    /// keeps its end, after "… ".
    private static func cut(_ entries: [ConversationEntry], toWords words: Int) -> [ConversationEntry] {
        var kept: [ConversationEntry] = []
        var room = words
        for entry in entries.reversed() {
            guard room > 0 else { break }
            let count = wordCount(entry.text)
            if count <= room {
                kept.append(entry)
                room -= count
            } else {
                kept.append(ConversationEntry(speaker: entry.speaker, text: keepingNewest(entry.text, words: room)))
                room = 0
            }
        }
        return kept.reversed()
    }

    /// `text` if it has at most `words` words; otherwise "… " and its last
    /// `words` words.
    private static func keepingNewest(_ text: String, words: Int) -> String {
        let all = text.split(whereSeparator: \.isWhitespace)
        guard all.count > words else { return text }
        guard words > 0 else { return "" }
        return "… " + all.suffix(words).joined(separator: " ")
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh ObserverPromptTests`
Expected: `** TEST SUCCEEDED **`. (`aLongReplyTakesAtMostHalf`: 100 words → the reply keeps its last 50, the context has room for 50 and keeps "go".)

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Observer/ObserverPrompt.swift macos/Tests/Observer/ObserverPromptTests.swift
git commit -m "lostty: observer: the notes prompt and reading its reply

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Who writes the summary

**Files:**
- Modify: `macos/Sources/Helpers/ProcessRunner.swift` (`run`, near line 24)
- Modify: `macos/Sources/Features/Branches/ClaudeCLI.swift` (`locate`, near line 41)
- Create: `macos/Sources/Features/Observer/Summarizer.swift`
- Modify: `docs/superpowers/specs/2026-10-14-lostty-mascot-observer-design.md` (§5's environment sentence)
- Test: `macos/Tests/Helpers/ProcessRunnerTests.swift`, `macos/Tests/Branches/ClaudeCLITests.swift`, `macos/Tests/Observer/SummarizerTests.swift`

**Interfaces:**
- Consumes: `ObserverPrompt.cliWords`, `ObserverPrompt.appleWords` (Task 4); `ClaudeCLI.arguments`, `ClaudeCLI.interpret`, `ClaudeCLI.timeout`, `RunHandle`, `SummaryError` (existing, `macos/Sources/Features/Branches/`).
- Produces:
  - `ProcessRunner.run(…, environment:, inheritEnvironment: Bool = true, …)`: with `false`, the program gets exactly `environment`.
  - `ClaudeCLI.locate(command: String = "claude", shell: String = …) -> String?`
  - `enum SummarizerKind: Equatable, Sendable { case claude(String), codex(String), apple, none; var words: Int }`
  - `enum Summarizer` with `claudeSignedIn(_:) -> Bool`, `codexSignedIn(_:) -> Bool`, `environment(for:base:) -> [String: String]`, `codexArguments(output:) -> [String]`, `detect(locate:status:apple:) -> SummarizerKind` (blocking), `run(_ kind:, prompt:, handle:) async -> Result<String, SummaryError>`, `static let noSummarizer: String`.

- [ ] **Step 1: Write the failing tests**

Add to `ProcessRunnerTests`:

```swift
    @Test func canReplaceTheWholeEnvironment() throws {
        let result = try #require(ProcessRunner.run(
            "/usr/bin/env", [], environment: ["ONLY": "1"], inheritEnvironment: false, timeout: 5))
        #expect(result.stdout == "ONLY=1\n")
    }
```

Add to `ClaudeCLITests`:

```swift
    @Test func locatesOtherCommandsToo() {
        #expect(ClaudeCLI.locate(command: "sh", shell: "/bin/sh") == "/bin/sh")
    }
```

`macos/Tests/Observer/SummarizerTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct SummarizerTests {
    @Test func onlyAClaudeSubscriptionCounts() {
        #expect(Summarizer.claudeSignedIn(#"{"loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty"}"#))
        #expect(!Summarizer.claudeSignedIn(#"{"loggedIn": true, "authMethod": "api_key"}"#))
        #expect(!Summarizer.claudeSignedIn(#"{"loggedIn": false, "authMethod": "claude.ai"}"#))
        #expect(!Summarizer.claudeSignedIn("Not logged in"))
        #expect(Summarizer.claudeSignedIn("note: update available\n{\"loggedIn\": true, \"authMethod\": \"claude.ai\"}\n"))
    }

    @Test func onlyAChatGPTSignInCounts() {
        #expect(Summarizer.codexSignedIn("Logged in using ChatGPT\n"))
        #expect(!Summarizer.codexSignedIn("Logged in using an API key - sk-…\n"))
        #expect(!Summarizer.codexSignedIn("Not logged in\n"))
    }

    @Test func claudeComesFirstThenCodexThenApple() {
        let both: (String) -> String? = { "/bin/\($0)" }
        let signedIn: (String, [String]) -> String? = { path, _ in
            path.hasSuffix("claude") ? #"{"loggedIn":true,"authMethod":"claude.ai"}"# : "Logged in using ChatGPT"
        }
        #expect(Summarizer.detect(locate: both, status: signedIn, apple: { true }) == .claude("/bin/claude"))
        let codexOnly: (String, [String]) -> String? = { path, _ in
            path.hasSuffix("claude") ? #"{"loggedIn":true,"authMethod":"api_key"}"# : "Logged in using ChatGPT"
        }
        #expect(Summarizer.detect(locate: both, status: codexOnly, apple: { true }) == .codex("/bin/codex"))
        let nobody: (String, [String]) -> String? = { _, _ in "Not logged in" }
        #expect(Summarizer.detect(locate: both, status: nobody, apple: { true }) == .apple)
        #expect(Summarizer.detect(locate: { _ in nil }, status: signedIn, apple: { false }) == SummarizerKind.none)
    }

    @Test func theEnvironmentLeavesOutKeysAndPaneVariables() {
        let base = ["HOME": "/Users/me", "USER": "me", "TMPDIR": "/tmp/x", "LANG": "en_US.UTF-8",
                    "ANTHROPIC_API_KEY": "sk-ant", "OPENAI_API_KEY": "sk-oai", "CODEX_API_KEY": "k",
                    "LOSTTY_SURFACE": "abc", "LOSTTY_BIN": "/x", "TMUX": "/tmp/tmux", "PATH": "/evil",
                    "CODEX_HOME": "/Users/me/.codex"]
        let env = Summarizer.environment(for: "/Users/me/.nvm/bin/codex", base: base)
        #expect(env["HOME"] == "/Users/me" && env["USER"] == "me" && env["TMPDIR"] == "/tmp/x")
        #expect(env["CODEX_HOME"] == "/Users/me/.codex")
        #expect(env["PATH"] == "/Users/me/.nvm/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        for key in ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "CODEX_API_KEY", "LOSTTY_SURFACE", "LOSTTY_BIN", "TMUX"] {
            #expect(env[key] == nil)
        }
    }

    @Test func codexRunsLeanAndReadOnly() {
        let args = Summarizer.codexArguments(output: "/tmp/out.txt")
        #expect(args.first == "exec")
        #expect(args.contains("--ignore-user-config") && args.contains("--ephemeral") && args.contains("--skip-git-repo-check"))
        #expect(args.firstIndex(of: "-s").map { args[$0 + 1] } == "read-only")
        #expect(args.firstIndex(of: "-o").map { args[$0 + 1] } == "/tmp/out.txt")
        #expect(!args.contains("-m"))
        #expect(args.last == "-")
    }

    func script(_ name: String, _ body: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("summ-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        try "#!/bin/sh\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @Test func claudesAnswerIsWhatItPrints() async throws {
        let claude = try script("claude", "cat > /dev/null\necho '{\"built\":[],\"just_now\":\"hi\"}'")
        let result = await Summarizer.run(.claude(claude), prompt: "x", handle: RunHandle())
        #expect(result == .success(#"{"built":[],"just_now":"hi"}"#))
    }

    @Test func codexsAnswerIsItsOutputFile() async throws {
        let codex = try script("codex", """
        out=""
        while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; fi; shift; done
        cat > /dev/null
        echo "progress noise"
        echo '{"built":["a"],"just_now":"b"}' > "$out"
        """)
        let result = await Summarizer.run(.codex(codex), prompt: "x", handle: RunHandle())
        #expect(result == .success(#"{"built":["a"],"just_now":"b"}"#))
    }

    @Test func aFailingRunSaysWhy() async throws {
        let codex = try script("codex", "cat > /dev/null\necho 'Not logged in' >&2\nexit 1")
        #expect(await Summarizer.run(.codex(codex), prompt: "x", handle: RunHandle()) == .failure(.failed("Not logged in")))
        #expect(await Summarizer.run(.none, prompt: "x", handle: RunHandle()) == .failure(.failed(Summarizer.noSummarizer)))
    }

    @Test func eachKindHasItsWordLimit() {
        #expect(SummarizerKind.claude("/c").words == ObserverPrompt.cliWords)
        #expect(SummarizerKind.codex("/c").words == ObserverPrompt.cliWords)
        #expect(SummarizerKind.apple.words == ObserverPrompt.appleWords)
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh SummarizerTests`
Expected: FAIL to compile: `inheritEnvironment` is an extra argument; cannot find `Summarizer`.

- [ ] **Step 3: `ProcessRunner` can replace the environment**

In `ProcessRunner.run`, add the parameter after `environment` and replace the environment lines:

```swift
    /// nil when the program can't start or runs past `timeout`. `onStart`
    /// gets the pid, so a caller can kill a run it no longer wants.
    /// `environment` is added to Lostty's own, or with `inheritEnvironment`
    /// false is all the program gets.
    static func run(
        _ executable: String,
        _ args: [String],
        cwd: String? = nil,
        environment: [String: String] = [:],
        inheritEnvironment: Bool = true,
        stdin: String? = nil,
        timeout: TimeInterval,
        onStart: ((Int32) -> Void)? = nil
    ) -> ProcessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if !inheritEnvironment {
            process.environment = environment
        } else if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
```

- [ ] **Step 4: `ClaudeCLI.locate` finds any command**

Replace `locate` in `ClaudeCLI.swift`:

```swift
    /// Where `command` (`claude`, or the observer's `codex`) is, looked up
    /// through the user's login shell (Lostty started from the Dock has a
    /// bare PATH). Blocking, up to 5 s.
    static func locate(
        command: String = "claude",
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    ) -> String? {
        guard let result = ProcessRunner.run(shell, ["-lic", "command -v \(command)"], timeout: 5),
              result.status == 0,
              let path = parseLocate(result.stdout),
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }
```

Callers that pass `shell:` by label keep working; run `grep -rn "ClaudeCLI.locate(" macos/Sources` and confirm none passes it unlabeled.

- [ ] **Step 5: Implement `Summarizer`**

`macos/Sources/Features/Observer/Summarizer.swift`:

```swift
#if os(macOS)
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Who writes the observer's notes (spec §5), with the path of its CLI.
enum SummarizerKind: Equatable, Sendable {
    /// Claude Haiku on the Claude subscription.
    case claude(String)
    /// Codex on its default model, signed in with ChatGPT.
    case codex(String)
    /// Apple's on-device model.
    case apple
    case none

    /// The most words its prompt carries.
    var words: Int {
        self == .apple ? ObserverPrompt.appleWords : ObserverPrompt.cliWords
    }
}

/// Finds a summarizer the user is signed in to, never an API key, and runs it.
enum Summarizer {
    static let noSummarizer = "Sign in to Claude Code or Codex, or turn on Apple Intelligence, to get summaries."

    /// `claude auth status` (JSON) says the Claude subscription login.
    static func claudeSignedIn(_ status: String) -> Bool {
        guard let open = status.firstIndex(of: "{"), let close = status.lastIndex(of: "}"), open < close,
              let object = (try? JSONSerialization.jsonObject(with: Data(status[open...close].utf8))) as? [String: Any]
        else { return false }
        return object["loggedIn"] as? Bool == true && object["authMethod"] as? String == "claude.ai"
    }

    /// `codex login status` says a ChatGPT sign-in (not an API key).
    static func codexSignedIn(_ status: String) -> Bool {
        status.contains("Logged in using ChatGPT")
    }

    /// What a run gets for its environment: none of Lostty's own (no API
    /// keys, no pane variables for the agent's hooks to report with), just
    /// what finding its login takes, and PATH with the CLI's own folder
    /// first (node, for a script).
    static func environment(
        for executable: String,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let kept = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "CLAUDE_CONFIG_DIR", "CODEX_HOME"]
        var env = base.filter { kept.contains($0.key) }
        let folder = (executable as NSString).deletingLastPathComponent
        env["PATH"] = "\(folder):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return env
    }

    /// No user config (plugins, MCP servers), nothing saved, read-only,
    /// low reasoning, the prompt on stdin, the answer in `output`.
    static func codexArguments(output: String) -> [String] {
        ["exec", "--ignore-user-config", "--skip-git-repo-check", "--ephemeral", "-s", "read-only",
         "-c", "model_reasoning_effort=low", "-o", output, "-"]
    }

    /// The first summarizer the user is signed in to. Blocking (login
    /// shells, `auth status`): call it off the main thread.
    static func detect(
        locate: (String) -> String? = { ClaudeCLI.locate(command: $0) },
        status: (String, [String]) -> String? = { Summarizer.statusOutput($0, $1) },
        apple: () -> Bool = { Summarizer.appleAvailable }
    ) -> SummarizerKind {
        if let path = locate("claude"), let out = status(path, ["auth", "status"]), claudeSignedIn(out) {
            return .claude(path)
        }
        if let path = locate("codex"), let out = status(path, ["login", "status"]), codexSignedIn(out) {
            return .codex(path)
        }
        return apple() ? .apple : .none
    }

    static func statusOutput(_ path: String, _ args: [String]) -> String? {
        guard let result = ProcessRunner.run(
            path, args, cwd: NSTemporaryDirectory(), environment: environment(for: path),
            inheritEnvironment: false, timeout: 15) else { return nil }
        return result.stdout + "\n" + result.stderr
    }

    static var appleAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// The model's answer to `prompt`. `handle` cancels a CLI run; cancel
    /// the calling task for Apple's.
    static func run(_ kind: SummarizerKind, prompt: String, handle: RunHandle) async -> Result<String, SummaryError> {
        switch kind {
        case .claude(let path):
            return await Task.detached(priority: .utility) { Summarizer.runClaude(path, prompt: prompt, handle: handle) }.value
        case .codex(let path):
            return await Task.detached(priority: .utility) { Summarizer.runCodex(path, prompt: prompt, handle: handle) }.value
        case .apple:
            return await runApple(prompt)
        case .none:
            return .failure(.failed(noSummarizer))
        }
    }

    private static func runClaude(_ path: String, prompt: String, handle: RunHandle) -> Result<String, SummaryError> {
        let result = ProcessRunner.run(
            path, ClaudeCLI.arguments, cwd: NSTemporaryDirectory(), environment: environment(for: path),
            inheritEnvironment: false, stdin: prompt, timeout: ClaudeCLI.timeout, onStart: handle.started)
        return ClaudeCLI.interpret(result, cancelled: handle.isCancelled)
    }

    private static func runCodex(_ path: String, prompt: String, handle: RunHandle) -> Result<String, SummaryError> {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("lostty-observer-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: output) }
        let result = ProcessRunner.run(
            path, codexArguments(output: output.path), cwd: NSTemporaryDirectory(),
            environment: environment(for: path), inheritEnvironment: false, stdin: prompt,
            timeout: ClaudeCLI.timeout, onStart: handle.started)
        // Codex prints its progress; the answer is in the output file.
        switch ClaudeCLI.interpret(result.map { ProcessResult(status: $0.status, stdout: "-", stderr: $0.stderr) },
                                   cancelled: handle.isCancelled) {
        case .failure(let error):
            return .failure(error)
        case .success:
            let text = ((try? String(contentsOf: output, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .failure(.failed("Codex returned nothing")) : .success(text)
        }
    }

    private static func runApple(_ prompt: String) async -> Result<String, SummaryError> {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let response = try await LanguageModelSession().respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? .failure(.failed("Apple Intelligence returned nothing")) : .success(text)
            } catch is CancellationError {
                return .failure(.cancelled)
            } catch {
                return .failure(.failed("Apple Intelligence couldn't summarize this (\(error.localizedDescription))."))
            }
        }
        #endif
        return .failure(.failed(noSummarizer))
    }
}
#endif
```

Note for `runCodex`: a failed status still reports stderr's first line through `ClaudeCLI.interpret`; the success branch replaces stdout with "-" only so `interpret` doesn't call Codex's progress output "the answer".

- [ ] **Step 6: Run the tests to verify they pass**

Run: `macos/skins-test.sh SummarizerTests && macos/skins-test.sh ProcessRunnerTests && macos/skins-test.sh ClaudeCLITests && macos/skins-test.sh BranchSummarizerTests`
Expected: all four `** TEST SUCCEEDED **`.

- [ ] **Step 7: FoundationModels must not stop Lostty launching on older macOS**

Run: `macos/build.nu && otool -l macos/build/Debug/Lostty.app/Contents/MacOS/Lostty | grep -B2 -A3 FoundationModels`
Expected: the load command for `FoundationModels.framework` is `LC_LOAD_WEAK_DYLIB`. If it is `LC_LOAD_DYLIB`, add `-weak_framework FoundationModels` to the Lostty (macOS) target's `OTHER_LDFLAGS` in Xcode's build settings (keeping the existing `-lstdc++`), rebuild, and check again.

- [ ] **Step 8: Correct the spec's environment sentence**

In `docs/superpowers/specs/2026-10-14-lostty-mascot-observer-design.md` §5, replace "Both CLIs run with PATH as their only environment, from the temp directory, with a 60-second timeout." with "Both CLIs run from the temp directory with a 60-second timeout, and an environment of only HOME, USER, LOGNAME, TMPDIR, LANG, CLAUDE_CONFIG_DIR and CODEX_HOME (when set) plus a PATH that starts with the CLI's folder: never an API key or a pane variable from Lostty's own environment." In "Facts this design rests on", replace "with an environment of PATH only, so the run's own hooks can't report to Lostty." with "adding PATH to Lostty's own environment (the observer replaces it instead, §5)."

- [ ] **Step 9: Commit**

```bash
git add macos/Sources/Helpers/ProcessRunner.swift macos/Sources/Features/Branches/ClaudeCLI.swift \
  macos/Sources/Features/Observer/Summarizer.swift macos/Tests/Helpers/ProcessRunnerTests.swift \
  macos/Tests/Branches/ClaudeCLITests.swift macos/Tests/Observer/SummarizerTests.swift \
  docs/superpowers/specs/2026-10-14-lostty-mascot-observer-design.md
# Only if Step 7 changed it:
# git add macos/Lostty.xcodeproj/project.pbxproj
git commit -m "lostty: observer: summarize with Claude, Codex or Apple, never an API key

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The turn observer

**Files:**
- Create: `macos/Sources/Features/Observer/ObserverPreferences.swift`
- Create: `macos/Sources/Features/Observer/TurnObserver.swift`
- Test: `macos/Tests/Observer/ObserverPreferencesTests.swift`, `macos/Tests/Observer/TurnObserverTests.swift`

**Interfaces:**
- Consumes: `TranscriptLocation.allowed`, `ConversationReader.read/tail/lastReply`, `ConversationChunk`, `ConversationEntry` (Task 3); `ObserverPrompt.build/parse`, `ObserverNotes` (Task 4); `SummarizerKind`, `Summarizer.detect/run/noSummarizer` (Task 5); `RunHandle`, `SummaryError`.
- Produces:
  - `@MainActor final class ObserverPreferences: ObservableObject { static let shared; static let backgroundKey = "LosttyObserverBackground"; @Published var background: Bool; init(defaults: UserDefaults = .ghostty) }`
  - `enum BubbleContent: Equatable { case waiting; case notes(ObserverNotes); case message(String); case failed(String, ObserverNotes?) }`
  - `@MainActor final class TurnObserver: ObservableObject` with `static let shared`, `static let nothingYet`, `init(deps: Dependencies = .live)`, `start()`, `turnEnded(pane: UUID, path: String)`, `open(pane: UUID, working: Bool)`, `close(pane: UUID)`, `content(pane: UUID, working: Bool) -> BubbleContent`, `surfaceClosed(_ pane: UUID)`, `carry() -> [UUID: String]`, `restore(_ panes: [UUID: String])`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Observer/ObserverPreferencesTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct ObserverPreferencesTests {
    @Test func backgroundSummariesAreOnByDefaultAndRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "ObserverPreferencesTests-\(UUID().uuidString)"))
        let preferences = ObserverPreferences(defaults: defaults)
        #expect(preferences.background)
        preferences.background = false
        #expect(defaults.object(forKey: ObserverPreferences.backgroundKey) as? Bool == false)
        #expect(!ObserverPreferences(defaults: defaults).background)
        #expect(ObserverPreferences.backgroundKey == "LosttyObserverBackground")
    }
}
#endif
```

`macos/Tests/Observer/TurnObserverTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct TurnObserverTests {
    /// Conversations by path (an offset is an entry count) and a summarizer
    /// that answers only when told to.
    final class Fake: @unchecked Sendable {
        private let lock = NSLock()
        private var conversations: [String: [ConversationEntry]] = [:]
        private var waiting: [CheckedContinuation<Result<String, SummaryError>, Never>] = []
        private(set) var prompts: [String] = []
        private(set) var handles: [RunHandle] = []

        func set(_ path: String, _ entries: [ConversationEntry]) {
            lock.withLock { conversations[path] = entries }
        }

        func read(_ path: String, _ offset: UInt64) -> ConversationChunk? {
            lock.withLock {
                guard let all = conversations[path] else { return nil }
                let start = Int(offset) <= all.count ? Int(offset) : 0
                return ConversationChunk(entries: Array(all[start...]), offset: UInt64(all.count),
                                         restarted: Int(offset) > all.count)
            }
        }

        func summarize(_ prompt: String, _ handle: RunHandle) async -> Result<String, SummaryError> {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    prompts.append(prompt)
                    handles.append(handle)
                    waiting.append(continuation)
                }
            }
        }

        var started: Int { lock.withLock { prompts.count } }

        /// Answers the oldest run still waiting.
        func answer(_ result: Result<String, SummaryError>) {
            let continuation = lock.withLock { waiting.removeFirst() }
            continuation.resume(returning: result)
        }
    }

    final class Switch: @unchecked Sendable {
        var on = true
    }

    let fake = Fake()
    let toggle = Switch()
    let pane = UUID()
    let you = ConversationEntry(speaker: .you, text: "Fix the login bug")
    let agent = ConversationEntry(speaker: .agent, text: "Fixed it.")

    func makeObserver(kind: SummarizerKind = .claude("/fake/claude"), maxRunning: Int = 2) -> TurnObserver {
        let fake = self.fake
        let toggle = self.toggle
        return TurnObserver(deps: TurnObserver.Dependencies(
            enabled: { toggle.on },
            locate: { $0.hasPrefix("/ok/") ? TranscriptLocation(url: URL(fileURLWithPath: $0), agent: .claude) : nil },
            read: { fake.read($0.url.path, $1) },
            detect: { kind },
            summarize: { _, prompt, handle in await fake.summarize(prompt, handle) },
            maxRunning: maxRunning))
    }

    func reply(_ built: [String], _ justNow: String) -> Result<String, SummaryError> {
        let data = try? JSONSerialization.data(withJSONObject: ["built": built, "just_now": justNow])
        return .success(String(decoding: data ?? Data(), as: UTF8.self))
    }

    /// Waits (up to 2 s) for the observer's tasks to catch up.
    func eventually(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test func aTurnsEndUpdatesTheNotes() async {
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 1 }
        #expect(observer.content(pane: pane, working: false) == .waiting)
        #expect(fake.prompts.first?.contains("You: Fix the login bug") == true)
        #expect(fake.prompts.first?.contains("The agent's last reply:\nFixed it.") == true)
        fake.answer(reply(["Fixed login"], "It works now."))
        let notes = ObserverNotes(built: ["Fixed login"], justNow: "It works now.")
        await eventually { observer.content(pane: pane, working: false) == .notes(notes) }
        #expect(observer.content(pane: pane, working: false) == .notes(notes))
        // The agent working again: wait for its new reply.
        #expect(observer.content(pane: pane, working: true) == .waiting)
    }

    @Test func laterRunsSendOnlyWhatsNew() async {
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 1 }
        fake.answer(reply(["Fixed login"], "It works now."))
        await eventually { observer.content(pane: pane, working: false) != .waiting }

        fake.set("/ok/a", [you, agent, ConversationEntry(speaker: .you, text: "Now add tests"),
                           ConversationEntry(speaker: .agent, text: "Added two tests.")])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 2 }
        let second = fake.prompts[1]
        #expect(second.contains("- Fixed login"))
        #expect(second.contains("You: Now add tests"))
        #expect(!second.contains("Fix the login bug"))
        #expect(second.contains("The agent's last reply:\nAdded two tests."))
        fake.answer(reply(["Fixed login", "Added tests"], "Tests pass."))
    }

    @Test func turnsDuringARunQueueJustOneMore() async {
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 1 }
        // Two more turns while it runs (a run with nothing new asks nobody).
        fake.set("/ok/a", [you, agent, ConversationEntry(speaker: .you, text: "more"),
                           ConversationEntry(speaker: .agent, text: "ok")])
        observer.turnEnded(pane: pane, path: "/ok/a")
        observer.turnEnded(pane: pane, path: "/ok/a")
        fake.answer(reply(["a"], "b"))
        await eventually { fake.started == 2 }
        #expect(observer.content(pane: pane, working: false) == .waiting)
        fake.answer(reply(["a"], "c"))
        await eventually { observer.content(pane: pane, working: false) == .notes(ObserverNotes(built: ["a"], justNow: "c")) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.started == 2)
    }

    @Test func atMostTwoRunAtOnce() async {
        let observer = makeObserver()
        for name in ["a", "b", "c"] {
            fake.set("/ok/\(name)", [you, agent])
            observer.turnEnded(pane: UUID(), path: "/ok/\(name)")
        }
        await eventually { fake.started == 2 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.started == 2)
        fake.answer(reply([], "done"))
        await eventually { fake.started == 3 }
        #expect(fake.started == 3)
        fake.answer(reply([], "done"))
        fake.answer(reply([], "done"))
    }

    @Test func withTheSwitchOffOnlyATapRuns() async {
        toggle.on = false
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.started == 0)
        observer.open(pane: pane, working: false)
        await eventually { fake.started == 1 }
        #expect(fake.started == 1)
        fake.answer(reply([], "hi"))
    }

    @Test func aTapMidTurnWaitsForTheTurnToEnd() async {
        toggle.on = false
        let observer = makeObserver()
        observer.open(pane: pane, working: true)
        #expect(observer.content(pane: pane, working: true) == .waiting)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.started == 0)
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 1 }
        #expect(fake.started == 1)
        fake.answer(reply([], "hi"))
    }

    @Test func closingCancelsOnlyATapsRun() async {
        toggle.on = false
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        observer.open(pane: pane, working: false)
        await eventually { fake.started == 1 }
        observer.close(pane: pane)
        #expect(fake.handles[0].isCancelled)
        fake.answer(.failure(.cancelled))

        toggle.on = true
        let other = UUID()
        fake.set("/ok/b", [you, agent])
        observer.turnEnded(pane: other, path: "/ok/b")
        await eventually { fake.started == 2 }
        observer.open(pane: other, working: false)
        observer.close(pane: other)
        #expect(!fake.handles[1].isCancelled)
        fake.answer(reply([], "kept"))
    }

    @Test func aPathOutsideTheAllowedFoldersIsIgnored() async {
        let observer = makeObserver()
        observer.turnEnded(pane: pane, path: "/Users/me/.ssh/id_ed25519")
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.started == 0)
        #expect(observer.content(pane: pane, working: false) == .message(TurnObserver.nothingYet))
    }

    @Test func aGarbledReplyKeepsTheLastNotes() async {
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 1 }
        fake.answer(reply(["Fixed login"], "It works now."))
        await eventually { observer.content(pane: pane, working: false) != .waiting }
        fake.set("/ok/a", [you, agent, ConversationEntry(speaker: .you, text: "more"),
                           ConversationEntry(speaker: .agent, text: "ok")])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 2 }
        fake.answer(.success("not json"))
        let notes = ObserverNotes(built: ["Fixed login"], justNow: "It works now.")
        await eventually { observer.content(pane: pane, working: false) != .waiting }
        #expect(observer.content(pane: pane, working: false) == .failed(TurnObserver.garbled, notes))
    }

    @Test func anEmptyConversationHasNothingToSumUp() async {
        let observer = makeObserver()
        fake.set("/ok/a", [])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { observer.content(pane: pane, working: false) != .waiting }
        #expect(observer.content(pane: pane, working: false) == .message(TurnObserver.nothingYet))
        #expect(fake.started == 0)
    }

    @Test func noSummarizerSaysHowToGetOne() async {
        let observer = makeObserver(kind: .none)
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { observer.content(pane: pane, working: false) == .message(Summarizer.noSummarizer) }
        #expect(observer.content(pane: pane, working: false) == .message(Summarizer.noSummarizer))
        #expect(fake.started == 0)
    }

    @Test func aRestartCarriesEachPanesConversation() async {
        toggle.on = false
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        #expect(observer.carry() == [pane: "/ok/a"])

        let next = makeObserver()
        next.restore([pane: "/ok/a", UUID(): "/etc/passwd"])
        #expect(next.carry() == [pane: "/ok/a"])
        next.open(pane: pane, working: false)
        await eventually { fake.started == 1 }
        #expect(fake.started == 1)
        fake.answer(reply([], "hi"))
    }

    @Test func aClosedPaneIsForgotten() {
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        toggle.on = false
        observer.turnEnded(pane: pane, path: "/ok/a")
        observer.surfaceClosed(pane)
        #expect(observer.carry().isEmpty)
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh TurnObserverTests`
Expected: FAIL to compile: cannot find `TurnObserver`, `ObserverPreferences`, `BubbleContent`.

- [ ] **Step 3: Implement `ObserverPreferences`**

`macos/Sources/Features/Observer/ObserverPreferences.swift`:

```swift
#if os(macOS)
import Foundation

/// Lostty Settings → Mascot: whether the observer summarizes each turn as
/// it ends (on) or only when you tap the mascot (off).
@MainActor
final class ObserverPreferences: ObservableObject {
    static let shared = ObserverPreferences()
    static let backgroundKey = "LosttyObserverBackground"

    private let defaults: UserDefaults

    @Published var background: Bool {
        didSet { defaults.set(background, forKey: Self.backgroundKey) }
    }

    init(defaults: UserDefaults = .ghostty) {
        self.defaults = defaults
        background = defaults.object(forKey: Self.backgroundKey) as? Bool ?? true
    }
}
#endif
```

- [ ] **Step 4: Implement `TurnObserver`**

`macos/Sources/Features/Observer/TurnObserver.swift`:

```swift
#if os(macOS)
import Combine
import Foundation

/// What the mascot's bubble shows (spec §6).
enum BubbleContent: Equatable {
    /// "…": a summary is on its way (or the agent is still working).
    case waiting
    case notes(ObserverNotes)
    case message(String)
    /// A run failed: why, and the last good notes.
    case failed(String, ObserverNotes?)
}

/// App-wide: when an agent finishes a turn in a pane, reads that
/// conversation's new prompts and replies and has a summarizer update its
/// notes (spec §4). In memory only. The mascot's bubble is its first use;
/// later ones (recall, observing how you work) build on the same notes and
/// turn ends.
@MainActor
final class TurnObserver: ObservableObject {
    static let shared = TurnObserver()
    static let nothingYet = "Nothing to sum up yet."
    /// Read by the nonisolated run, so not main-actor bound.
    nonisolated static let garbled = "The summary came back garbled. Tap again to retry."

    struct Dependencies {
        var enabled: @MainActor () -> Bool
        var locate: @Sendable (String) -> TranscriptLocation?
        var read: @Sendable (TranscriptLocation, UInt64) -> ConversationChunk?
        var detect: @Sendable () async -> SummarizerKind
        var summarize: @Sendable (SummarizerKind, String, RunHandle) async -> Result<String, SummaryError>
        var maxRunning = 2

        static var live: Dependencies {
            Dependencies(
                enabled: { ObserverPreferences.shared.background },
                locate: { TranscriptLocation.allowed($0) },
                read: { ConversationReader.read($0, from: $1) },
                detect: { await Task.detached(priority: .utility) { Summarizer.detect() }.value },
                summarize: { await Summarizer.run($0, prompt: $1, handle: $2) })
        }
    }

    /// One conversation file's notes and where reading it got to.
    struct Conversation: Equatable, Sendable {
        var notes: ObserverNotes?
        var offset: UInt64 = 0
        /// Your latest prompt and the reply since (ConversationReader.tail).
        var tail: [ConversationEntry] = []
        /// A turn ended since the notes were written.
        var stale = true
        var queued = false
        var running = false
        /// A turn ended during the run: run once more after it.
        var again = false
        /// The last run's failure; cleared by the next success.
        var error: String?
    }

    enum RunResult: Sendable {
        case notes(ObserverNotes, offset: UInt64, tail: [ConversationEntry])
        /// Nothing new since the notes.
        case nothingNew(offset: UInt64)
        /// The conversation has nothing to sum up.
        case empty(offset: UInt64)
        case failed(SummaryError)
    }

    /// Each pane's current conversation file (allowed paths only).
    @Published private(set) var panes: [UUID: String] = [:]
    /// By conversation file.
    @Published private(set) var conversations: [String: Conversation] = [:]
    /// nil until found (and again after a failed run, to look again).
    @Published private(set) var summarizer: SummarizerKind?

    private let deps: Dependencies
    private var queue: [String] = []
    private var running = 0
    private var handles: [String: RunHandle] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    /// Runs a tap started with the switch off: closing the bubble cancels them.
    private var tapRuns: Set<String> = []
    /// Panes whose bubble opened mid-turn: their turn's end runs even with
    /// the switch off.
    private var waitingPanes: Set<UUID> = []
    private var detecting: Task<SummarizerKind, Never>?

    init(deps: Dependencies = .live) {
        self.deps = deps
    }

    /// At launch: find out which summarizer to use, so the first tap knows.
    func start() {
        Task { _ = await summarizerKind() }
    }

    // MARK: - Turn ends

    func turnEnded(pane: UUID, path: String) {
        guard deps.locate(path) != nil else { return }
        if panes[pane] != path { panes[pane] = path }
        let wanted = waitingPanes.remove(pane) != nil
        var conversation = conversations[path] ?? Conversation()
        conversation.stale = true
        conversations[path] = conversation
        let enabled = deps.enabled()
        guard enabled || wanted else { return }
        request(path, byTap: !enabled)
    }

    // MARK: - The bubble

    /// The bubble opened for `pane`: start a run if its notes are out of
    /// date, or wait for the turn's end if the agent is working.
    func open(pane: UUID, working: Bool) {
        // Look again: the user may have signed in since.
        if summarizer == SummarizerKind.none { summarizer = nil }
        if working {
            waitingPanes.insert(pane)
            return
        }
        guard let path = panes[pane] else { return }
        let conversation = conversations[path] ?? Conversation()
        guard !conversation.queued, !conversation.running, conversation.stale else { return }
        request(path, byTap: !deps.enabled())
    }

    /// The bubble closed: stop waiting, and cancel a run only it wanted.
    func close(pane: UUID) {
        waitingPanes.remove(pane)
        guard let path = panes[pane], tapRuns.remove(path) != nil else { return }
        if var conversation = conversations[path], conversation.queued {
            conversation.queued = false
            conversations[path] = conversation
            queue.removeAll { $0 == path }
        } else {
            handles[path]?.cancel()
            tasks[path]?.cancel()
        }
    }

    func content(pane: UUID, working: Bool) -> BubbleContent {
        if summarizer == SummarizerKind.none { return .message(Summarizer.noSummarizer) }
        if working { return .waiting }
        guard let path = panes[pane] else { return .message(Self.nothingYet) }
        let conversation = conversations[path] ?? Conversation()
        if conversation.queued || conversation.running { return .waiting }
        if let error = conversation.error { return .failed(error, conversation.notes) }
        if let notes = conversation.notes { return conversation.stale ? .waiting : .notes(notes) }
        return conversation.stale ? .waiting : .message(Self.nothingYet)
    }

    // MARK: - Panes

    func surfaceClosed(_ pane: UUID) {
        panes[pane] = nil
        waitingPanes.remove(pane)
    }

    /// Each pane's conversation file, for Restart to Update to hand on.
    func carry() -> [UUID: String] { panes }

    func restore(_ carried: [UUID: String]) {
        for (pane, path) in carried where deps.locate(path) != nil {
            panes[pane] = path
        }
    }

    // MARK: - Runs

    private func request(_ path: String, byTap: Bool = false) {
        var conversation = conversations[path] ?? Conversation()
        if conversation.running {
            conversation.again = true
            conversations[path] = conversation
            return
        }
        guard !conversation.queued else { return }
        conversation.queued = true
        conversations[path] = conversation
        if byTap { tapRuns.insert(path) }
        queue.append(path)
        pump()
    }

    private func pump() {
        while running < deps.maxRunning, !queue.isEmpty {
            begin(queue.removeFirst())
        }
    }

    private func begin(_ path: String) {
        var conversation = conversations[path] ?? Conversation()
        conversation.queued = false
        conversation.running = true
        conversation.again = false
        conversations[path] = conversation
        running += 1
        let handle = RunHandle()
        handles[path] = handle
        let snapshot = conversation
        let locate = deps.locate, read = deps.read, summarize = deps.summarize
        tasks[path] = Task {
            let kind = await self.summarizerKind()
            let result = await Self.run(
                path: path, conversation: snapshot, kind: kind,
                locate: locate, read: read, summarize: summarize, handle: handle)
            self.finish(path, result, kind: kind)
        }
    }

    private func finish(_ path: String, _ result: RunResult, kind: SummarizerKind) {
        running -= 1
        handles[path] = nil
        tasks[path] = nil
        tapRuns.remove(path)
        var conversation = conversations[path] ?? Conversation()
        conversation.running = false
        switch result {
        case .notes(let notes, let offset, let tail):
            conversation.notes = notes
            conversation.offset = offset
            conversation.tail = tail
            conversation.error = nil
            conversation.stale = conversation.again
        case .nothingNew(let offset):
            conversation.offset = offset
            conversation.error = nil
            conversation.stale = conversation.again
        case .empty(let offset):
            conversation.notes = nil
            conversation.tail = []
            conversation.offset = offset
            conversation.error = nil
            conversation.stale = conversation.again
        case .failed(.cancelled):
            break
        case .failed(let error):
            conversation.error = error.message
            // A lapsed sign-in shows up as a failure: look again next time.
            if kind != .none { summarizer = nil }
        }
        let again = conversation.again
        conversation.again = false
        conversations[path] = conversation
        if again { request(path) }
        pump()
    }

    private func summarizerKind() async -> SummarizerKind {
        if let summarizer { return summarizer }
        let task: Task<SummarizerKind, Never>
        if let detecting {
            task = detecting
        } else {
            let detect = deps.detect
            task = Task { await detect() }
            detecting = task
        }
        let kind = await task.value
        detecting = nil
        summarizer = kind
        return kind
    }

    /// Reads what's new and asks for updated notes. Off the main actor: a
    /// first read can be a large file.
    nonisolated private static func run(
        path: String,
        conversation: Conversation,
        kind: SummarizerKind,
        locate: @Sendable (String) -> TranscriptLocation?,
        read: @Sendable (TranscriptLocation, UInt64) -> ConversationChunk?,
        summarize: @Sendable (SummarizerKind, String, RunHandle) async -> Result<String, SummaryError>,
        handle: RunHandle
    ) async -> RunResult {
        guard kind != .none else { return .failed(.failed(Summarizer.noSummarizer)) }
        guard let location = locate(path), let chunk = read(location, conversation.offset) else {
            return .failed(.failed("Couldn't read this conversation."))
        }
        let previous = chunk.restarted ? nil : conversation.notes
        let oldTail = chunk.restarted ? [] : conversation.tail
        if chunk.entries.isEmpty {
            return chunk.restarted || conversation.notes == nil ? .empty(offset: chunk.offset) : .nothingNew(offset: chunk.offset)
        }
        let tail = ConversationReader.tail(oldTail, adding: chunk.entries)
        let earlier = chunk.entries.lastIndex { $0.speaker == .you }.map { Array(chunk.entries[...$0]) } ?? []
        let prompt = ObserverPrompt.build(
            previous: previous, earlier: earlier, lastReply: ConversationReader.lastReply(tail), words: kind.words)
        guard !handle.isCancelled, !Task.isCancelled else { return .failed(.cancelled) }
        switch await summarize(kind, prompt, handle) {
        case .success(let text):
            guard let notes = ObserverPrompt.parse(text) else { return .failed(.failed(garbled)) }
            return .notes(notes, offset: chunk.offset, tail: tail)
        case .failure(let error):
            return .failed(error)
        }
    }
}
#endif
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `macos/skins-test.sh TurnObserverTests && macos/skins-test.sh ObserverPreferencesTests`
Expected: both `** TEST SUCCEEDED **`. If a test hangs, a run is waiting on `fake.answer` that never comes: check that each test answers every run it started.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Observer/ObserverPreferences.swift macos/Sources/Features/Observer/TurnObserver.swift \
  macos/Tests/Observer/ObserverPreferencesTests.swift macos/Tests/Observer/TurnObserverTests.swift
git commit -m "lostty: observer: keep each conversation's notes up to date as turns end

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Wire the observer into Lostty

**Files:**
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (just before `LosttyRestart.resumeIfRestarted()`, near line 360)
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (the `deinit`'s `Task { @MainActor in … }`, near line 466)
- Modify: `macos/Sources/Features/Restart/RestartHandoff.swift`, `macos/Sources/Features/Restart/LosttyRestart.swift` (`restart(reason:)` near line 50, `resumeIfRestarted` near line 94)
- Modify: `macos/Sources/Features/Settings/SettingsView.swift`, `macos/Sources/Features/Settings/SettingsUI.swift:20`
- Test: `macos/Tests/Restart/RestartHandoffTests.swift`

**Interfaces:**
- Consumes: `ClaudeRuntime.turnEnded` (Task 2); `TurnObserver.shared.turnEnded/start/surfaceClosed/carry/restore`, `ObserverPreferences.shared` (Task 6).
- Produces: `RestartHandoff.transcripts: [String: String]?` (pane UUID string → conversation path; nil in handoffs from older builds); `SettingsView(sidebar:observer:)`.

- [ ] **Step 1: Write the failing tests**

Add to `RestartHandoffTests`:

```swift
    @Test func anOlderHandoffWithoutTranscriptsStillReads() throws {
        let url = RestartHandoff.url(bundleID: "com.lawliang.lostty", in: try folder())
        let json = #"{"pid":4242,"at":1999999995,"claude":{},"stayAwakeOn":false,"hookAgents":[]}"#
        try Data(json.utf8).write(to: url)
        let taken = try #require(RestartHandoff.take(from: url))
        #expect(taken.transcripts == nil)
    }

    @Test func transcriptsRoundTrip() throws {
        let url = RestartHandoff.url(bundleID: "com.lawliang.lostty", in: try folder())
        var saved = handoff()
        saved.transcripts = ["ABCDEF01-0000-4000-8000-000000000001": "/Users/a/.claude/projects/p/s.jsonl"]
        try saved.save(to: url)
        #expect(RestartHandoff.take(from: url) == saved)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh RestartHandoffTests`
Expected: FAIL to compile: `RestartHandoff` has no member `transcripts`.

- [ ] **Step 3: Carry the conversation paths across a restart**

In `RestartHandoff.swift`, after `keepWindows`:

```swift
    /// Each pane's conversation file for the turn observer, by pane UUID;
    /// nil from a build before the observer.
    var transcripts: [String: String]? = nil
```

In `LosttyRestart.restart(reason:)`, the `RestartHandoff(…)` call gains a last argument:

```swift
            keepWindows: UserDefaults.ghostty.object(forKey: keepWindowsKey) as? Bool,
            transcripts: Dictionary(uniqueKeysWithValues: TurnObserver.shared.carry().map { ($0.key.uuidString, $0.value) }))
```

In `resumeIfRestarted`, right after the `ClaudeRuntime.shared.restore(…)` call:

```swift
        TurnObserver.shared.restore(Dictionary(uniqueKeysWithValues: (handoff.transcripts ?? [:]).compactMap { key, path in
            UUID(uuidString: key).map { ($0, path) }
        }))
```

- [ ] **Step 4: Hear turn ends, forget closed panes**

In `AppDelegate.swift`, just before `LosttyRestart.resumeIfRestarted()` (and its comment):

```swift
        // The mascot's turn observer: hears each turn's end from the agent
        // hooks, and finds out which summarizer it can use. Before the
        // restart resume, which hands it each pane's conversation.
        ClaudeRuntime.shared.turnEnded = { TurnObserver.shared.turnEnded(pane: $0, path: $1) }
        TurnObserver.shared.start()
```

In `SurfaceView_AppKit.swift`'s `deinit`, add to the `Task { @MainActor in … }` block after `SessionTitleSignal.shared.surfaceClosed(closedID)`:

```swift
                TurnObserver.shared.surfaceClosed(closedID)
```

and change its comment to "Lostty Claude trace: forget this pane's trace phase, usage and conversation."

- [ ] **Step 5: The switch in Lostty Settings**

`SettingsView.swift` becomes:

```swift
#if os(macOS)
import SwiftUI

/// Lostty Settings: preferences that live in the app rather than the
/// config file.
struct SettingsView: View {
    @ObservedObject var sidebar: SidebarPreferences
    @ObservedObject var observer: ObserverPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Sidebar") {
                    Toggle("Automatically hide sidebar", isOn: $sidebar.autoHide)
                    Text("Shows when you move the pointer to the window's right edge. "
                         + "Stays open while an app is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Mascot") {
                    Toggle("Summarize turns in the background", isOn: $observer.background)
                    Text("After each turn, Claude Haiku (or Codex, or Apple Intelligence) updates what the "
                         + "mascot tells you when you tap it, using your own subscription. "
                         + "Off, it summarizes only when you tap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Text("Terminal settings live in ~/.config/lostty/config "
                 + "(Lostty → Preferences… opens it).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(
            sidebar: SidebarPreferences(defaults: UserDefaults(suiteName: "preview")!),
            observer: ObserverPreferences(defaults: UserDefaults(suiteName: "preview")!))
    }
}
#endif
```

In `SettingsUI.swift`: `NSHostingController(rootView: SettingsView(sidebar: .shared, observer: .shared))`.

- [ ] **Step 6: Run the tests and build**

Run: `macos/skins-test.sh RestartHandoffTests && macos/skins-test.sh LosttyRestartTests && macos/build.nu`
Expected: both suites `** TEST SUCCEEDED **`; `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/App/macOS/AppDelegate.swift "macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift" \
  macos/Sources/Features/Restart/RestartHandoff.swift macos/Sources/Features/Restart/LosttyRestart.swift \
  macos/Sources/Features/Settings/SettingsView.swift macos/Sources/Features/Settings/SettingsUI.swift \
  macos/Tests/Restart/RestartHandoffTests.swift
git commit -m "lostty: observer: hear turn ends, carry conversations across restarts, add the setting

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The mascot's bubble

**Before starting:** `SidebarMascot.swift` and `ExtensionSidebarLayout.swift` hold the user's uncommitted mascot-in-the-corner change. Ask the user to commit it first (or approve committing it as its own commit, "lostty: move the mascot into the terminal's corner", with `SidebarMascot.swift`, `ExtensionSidebarLayout.swift`, `ExtensionSidebarView.swift`, `Axolotl.swift` and `SessionsScreen.swift`). Don't start this task until the working tree shows those files clean.

**Files:**
- Create: `macos/Sources/Features/Extensions/MascotBubble.swift`
- Modify: `macos/Sources/Features/Extensions/SidebarMascot.swift` (the `SidebarMascot` view, lines 1-51; `PaneActivity` stays as is)
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift` (the mascot overlay, lines 33-40, and a new `@State`)

**Interfaces:**
- Consumes: `TurnObserver.shared.open/close/content`, `TurnObserver.nothingYet`, `BubbleContent`, `ObserverNotes` (Tasks 4 and 6); `ClaudeRuntime.shared.phases`; `Axolotl.Pose.happy`.
- Produces: `SidebarMascot(surfaceID:bubbleMaxHeight:)`; `MascotBubble(content:maxHeight:)`.

- [ ] **Step 1: The bubble view**

`macos/Sources/Features/Extensions/MascotBubble.swift`:

```swift
#if os(macOS)
import SwiftUI

/// The mascot's speech bubble: what the turn observer knows about the
/// focused pane's conversation (spec §6). Lives in a popover whose arrow
/// points at the axolotl; scrolls once taller than `maxHeight`.
struct MascotBubble: View {
    static let width: CGFloat = 340

    let content: BubbleContent
    let maxHeight: CGFloat

    var body: some View {
        ViewThatFits(in: .vertical) {
            inner
            ScrollView { inner }
        }
        .frame(width: Self.width)
        .frame(maxHeight: maxHeight)
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch content {
            case .waiting:
                Text("…")
                    .font(.system(size: 22, weight: .semibold))
                    .accessibilityLabel("Summarizing")
            case .message(let text):
                Text(text)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            case .notes(let notes):
                NotesView(notes: notes)
            case .failed(let error, let notes):
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let notes { NotesView(notes: notes) }
            }
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// The notes in the order the user asked for (spec §6): why you started,
/// what we decided, what's built, what's left, then the last reply in
/// plain words. An empty section is left out.
private struct NotesView: View {
    let notes: ObserverNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !notes.why.isEmpty || !notes.asked.isEmpty {
                section("Why you started this") {
                    if !notes.why.isEmpty { paragraph(notes.why) }
                    bullets(notes.asked)
                }
            }
            if !notes.decided.isEmpty {
                section("What we decided together") { bullets(notes.decided) }
            }
            if !notes.built.isEmpty {
                section(notes.progress.isEmpty ? "What's built" : "What's built (\(notes.progress))") {
                    bullets(notes.built)
                }
            }
            if !notes.left.isEmpty {
                section("What's left") { bullets(notes.left) }
            }
            section("Just now") { paragraph(notes.justNow) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullets(_ items: [String]) -> some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                Text(item).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13))
        }
    }
}
#endif
```

- [ ] **Step 2: The mascot as a button**

In `SidebarMascot.swift`, replace the imports, the doc comment and the `SidebarMascot` struct's properties and `body` (keep `state(now:)`, `state(id:now:)` and `pose(_:)` as they are) with:

```swift
#if os(macOS)
import AppKit
import Combine
import LosttyRemote
import SwiftUI

/// The axolotl standing in the terminal's bottom-right corner, doing what
/// the focused pane's terminal is doing, as the phone's rows show it:
/// waving while Claude waits on you, dancing while it works, wagging its
/// tail when ready, asleep when idle. Tap it for its bubble: what's been
/// done in this conversation and the last reply in plain words.
struct SidebarMascot: View {
    let surfaceID: UUID?
    /// The tallest the bubble gets before it scrolls: half the terminal.
    var bubbleMaxHeight: CGFloat = 400
    @ObservedObject private var claude = ClaudeRuntime.shared
    @ObservedObject private var activity = PaneActivity.shared
    @ObservedObject private var observer = TurnObserver.shared
    /// The pane whose bubble is open.
    @State private var openPane: UUID?
    /// When the bubble last closed: the click on the mascot that closes a
    /// transient popover must not open it again on mouse-up.
    @State private var closedAt = Date.distantPast
    @State private var escape = EscapeKeyMonitor()

    var body: some View {
        // Each half minute, so ready turns idle on time.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let state = state(now: context.date) {
                Button(action: toggle) {
                    Axolotl(pose: openPane != nil ? .happy : Self.pose(state)).frame(width: 56, height: 56)
                        .background(alignment: .bottom) { MascotPlatform() }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.title)
                .accessibilityHint("Shows what's been done in this terminal")
                .popover(isPresented: bubbleShown, arrowEdge: .top) {
                    MascotBubble(content: bubbleContent, maxHeight: bubbleMaxHeight)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: surfaceID.flatMap { state(id: $0, now: Date()) })
        .onAppear { activity.start() }
        // Focus moving to another pane closes the bubble.
        .onChange(of: surfaceID) { _ in close() }
        .onDisappear { close() }
    }

    private var bubbleShown: Binding<Bool> {
        Binding(get: { openPane != nil }, set: { shown in if !shown { close() } })
    }

    private var bubbleContent: BubbleContent {
        guard let id = openPane else { return .message(TurnObserver.nothingYet) }
        return observer.content(pane: id, working: claude.phases[id] != nil)
    }

    private func toggle() {
        if openPane != nil {
            close()
            return
        }
        guard Date().timeIntervalSince(closedAt) > 0.3, let id = surfaceID else { return }
        observer.open(pane: id, working: claude.phases[id] != nil)
        openPane = id
        escape.start { close() }
    }

    private func close() {
        escape.stop()
        guard let id = openPane else { return }
        openPane = nil
        closedAt = Date()
        observer.close(pane: id)
    }
```

and add, after the `SidebarMascot` struct's closing brace (before `PaneActivity`):

```swift
/// While the bubble is open, Esc closes it instead of reaching the
/// terminal, where it would interrupt Claude.
@MainActor
private final class EscapeKeyMonitor {
    private var monitor: Any?

    func start(_ onEscape: @escaping @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { onEscape() }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
```

- [ ] **Step 3: Only the axolotl takes clicks; the bubble gets half the terminal**

In `ExtensionSidebarLayout.swift`, add after `@StateObject private var autoHide = SidebarAutoHideDriver()`:

```swift
    /// The terminal's height, for the mascot's bubble (at most half).
    @State private var terminalHeight: CGFloat = 0
```

and replace the mascot overlay:

```swift
                content()
                    // Over the terminal's corner, under any open extension;
                    // clicks and selection pass through to the terminal.
                    .overlay(alignment: .bottomTrailing) {
                        SidebarMascot(surfaceID: model.focusedSurfaceID)
                            .padding(.trailing, 14)
                            .padding(.bottom, 10)
                            .allowsHitTesting(false)
                    }
```

with:

```swift
                content()
                    // Read behind the terminal, so nothing covers it.
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { terminalHeight = geo.size.height }
                            .onChange(of: geo.size.height) { terminalHeight = $0 }
                    })
                    // Over the terminal's corner, under any open extension.
                    // The overlay is only as big as the axolotl, which takes
                    // clicks (its bubble); the rest of the terminal keeps them.
                    .overlay(alignment: .bottomTrailing) {
                        SidebarMascot(surfaceID: model.focusedSurfaceID, bubbleMaxHeight: max(160, terminalHeight / 2))
                            .padding(.trailing, 14)
                            .padding(.bottom, 10)
                    }
```

- [ ] **Step 4: Build both apps**

Run: `macos/build.nu && macos/build.nu --scheme Lostty-iOS`
Expected: `** BUILD SUCCEEDED **` for both. (The iOS build only proves the Mac-only files stay out of it; if the generic iOS build fails to link the x86_64 slice, as it did on 2026-10-14, run `xcodebuild -project macos/Lostty.xcodeproj -scheme Lostty-iOS -sdk iphonesimulator ARCHS=arm64 build` instead.)

- [ ] **Step 5: Run the whole Mac suite**

Run: `macos/build.nu --action test`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Extensions/MascotBubble.swift macos/Sources/Features/Extensions/SidebarMascot.swift \
  macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift
git commit -m "lostty: observer: tap the mascot for its bubble

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: The real thing, on this Mac (with the user)

Nothing here is automated. Ask the user before installing: "The mascot bubble is built and tested. Want me to install it with `macos/install-skins.sh`? You'd then switch with menu bar → Restart to Update (Keeps Terminals)." Only after a yes:

- [ ] **Step 1: Install**

Run: `macos/install-skins.sh`, then ask the user to choose Lostty's menu bar → **Restart to Update (Keeps Terminals)**. Never Quit Lostty.

- [ ] **Step 2: Claude pane, after a turn**

In a pane, the user starts `claude` and sends a tiny prompt ("say hi"). After it answers, a tap on the mascot opens the bubble at once (the observer already ran) with its sections (at least **Why you started this** and **Just now**); the axolotl shows its happy pose.

- [ ] **Step 3: Mid-turn**

The user sends "count to 5 slowly" and taps the mascot while Claude works: the bubble shows "…", then fills a few seconds after Claude stops.

- [ ] **Step 4: Closing, and the terminal still gets its input**

With the bubble open: Esc closes it and Claude is not interrupted; clicking the terminal closes it; clicking another pane closes it. With the bubble closed, select text in the terminal's last row and last columns right next to the mascot: the selection works.

- [ ] **Step 5: Codex pane**

The same as Step 2 with `codex` and a tiny prompt.

- [ ] **Step 6: The switch off**

Lostty Settings → turn off **Summarize turns in the background**. After a new turn, a tap shows "…" and then the notes; with the switch off, closing the bubble while it shows "…" stops that run.

- [ ] **Step 7: Restart**

Restart to Update again; a tap in the same Claude pane summarizes (a first run of the whole conversation) instead of "Nothing to sum up yet."
