# Observer Context Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Past a context limit (or on a tap), Lostty tells the Claude Code agent in a pane to hand off at its next clean break, then clears the window and starts the fresh agent from the handoff.

**Architecture:** The Mac app queues text per pane in files under
`~/Library/Application Support/Lostty/handoff/panes/`; Lostty's Claude hooks
(`+claude-state`, Zig) take that text and print it as Claude's
`additionalContext`. A `@MainActor` coordinator watches the usage feed and
the hooks' signals, reads the agent's `<lostty-handoff>` block from the
conversation file, saves it, types `/clear`, and types the continue line once
the start hook reports the fresh window loaded it. Pure pieces (policy,
directive, extraction, restore lines) carry the logic and the tests.

**Tech Stack:** Zig 0.15.2 (`src/cli`), Swift 6 / SwiftUI / Swift Testing (`macos/Sources`, `macos/Tests`), Xcode synchronized groups (new files join the project by themselves).

**Spec:** `docs/superpowers/specs/2026-10-16-observer-handoff-design.md`

## Global Constraints

- Beta only: everything runs behind `LosttyChannel.current.showsMascot`.
- Claude Code only; panes open in a Mac window only.
- Setting "Hand off long conversations" defaults **off**; "Hand off after" offers 200k, 300k, 400k, 500k, 600k, default **300k**.
- Effective limit = setting, at most 70% of the window; ceiling = limit + 100k, at most 90% of the window; reminders every 25k.
- Grace before typing: 3 s. No fresh window within 15 s of `/clear` = failure.
- Handoff under 8,000 characters; a hook's `additionalContext` is capped by Claude at 10,000; the start text over 9,000 keeps the first 7,500 characters of the handoff plus a pointer to the file.
- Directive under 4,000 characters.
- Saved handoffs: `~/Library/Application Support/Lostty/handoffs/<project>/<yyyy-MM-dd HHmm>.md`, last 50 per project.
- Lostty types only `/clear`, the restore lines, the continue line and the one ceiling nudge, each followed by Return, only into the pane the handoff came from.
- Nothing is written into the user's repo.
- Hooks never fail and never block: no state file means no output, exit 0.
- Copy (exact strings) is in Task 3 and Task 5; don't reword it.
- Commit messages: `lostty: handoff: …`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never delete engine code or other-platform code.

## Commands

- **Zig tests:** `zig build test -Dtest-filter="<prefix>"` (prefixes: `claude speak`, `claude hooks`, `claude protocol`).
- **Swift test, one suite** (call this `SWIFT_TEST <Suite>`):
  `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project macos/Lostty.xcodeproj -scheme Lostty -configuration Debug SYMROOT="$PWD/macos/build" -skip-testing LosttyUITests -only-testing:LosttyTests/<Suite> test > /tmp/handoff-test.log 2>&1; tail -25 /tmp/handoff-test.log`
  (executors with a scratchpad: write the log there instead of `/tmp`).
- **Swift full suite:** `macos/build.nu --action test` (redirect to a log, read the tail).
- **Engine build after Zig changes:** `zig build -Demit-macos-app=false`.

## Review Focus

1. A subagent's tool call taking the directive meant for Claude: the PostToolUse hook must stay silent when the input names `agent_id` (Task 1 test `claude speak: a subagent's tool call is not spoken to`).
2. `/clear` itself or Lostty's own typed lines firing `UserPromptSubmit` and cancelling Lostty's own work: `prompted` must only cancel in the `pending` phase (Task 5 test `ourOwnClearPromptDoesNotCancelTheFreshWindowWait`).
3. A hostile `LOSTTY_SURFACE` (`../../x`) steering the hook to another file: only an uppercase UUID is accepted (Task 1 test `claude speak: pane ids`).
4. Two hooks firing at once both printing the directive: taking the queued file is a rename, so one wins (Task 1 test `claude speak: take is once`).
5. A handoff block quoted inside a code fence (the agent explaining the format) being taken as a real handoff (Task 3 test `aBlockInsideACodeFenceIsNotAHandoff`).
6. A prompt arriving while the reply is still being read, so `/clear` would land on a working agent; and a key typed right after a turn ends throwing that turn's handoff away (Task 5 tests `aPromptBeforeTheReplyIsReadDropsTheHandoff`, `typingRightAfterAStopDoesNotLoseTheHandoff`).

---

### Task 1: The hooks speak (Zig)

**Files:**
- Create: `src/cli/claude/speak.zig`
- Modify: `src/cli/claude/protocol.zig` (State enum, line 16)
- Modify: `src/cli/claude_state.zig` (`run`, test block)
- Modify: `src/cli/claude/hooks.zig` (`claude_events`, lines 21-28)

**Interfaces:**
- Produces (on disk, consumed by Task 4): the hook takes `$HOME/Library/Application Support/Lostty/handoff/panes/<PANE>.say` on `UserPromptSubmit` (`+claude-state busy`) and `PostToolUse` (`+claude-state done`), and `<PANE>.start` on `SessionStart` with `source:"clear"` (`+claude-state start`). `<PANE>` is `LOSTTY_SURFACE` (an uppercase UUID string).
- Produces (wire, consumed by Task 6): after taking `<PANE>.start` the hook sends `LOSTTY_CLAUDE` = `{"v":1,"state":"fresh"}`.
- Produces (stdout): `{"hookSpecificOutput":{"hookEventName":"<event>","additionalContext":"<text>"}}`.

- [ ] **Step 1: Write the failing tests** — create `src/cli/claude/speak.zig` with only the tests and stub declarations so it compiles to failures:

```zig
//! Pure logic for the context handoff's hook output: what `+claude-state`
//! prints for Claude Code to add to its context. See
//! docs/superpowers/specs/2026-10-16-observer-handoff-design.md (§4, §6).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Which queued text a hook takes: `say` (the directive) on
/// UserPromptSubmit and PostToolUse, `start` (the handoff for the fresh
/// window) on SessionStart after /clear.
pub const Kind = enum { say, start };

/// Under $HOME: where the Mac app queues each pane's text.
pub const panes_dir = "Library/Application Support/Lostty/handoff/panes";

/// The most a queued text may hold; Claude caps it at 10,000 characters.
pub const text_max = 64 << 10;

pub fn isPaneId(s: []const u8) bool {
    _ = s;
    return true;
}

pub fn queuedPath(alloc: Allocator, home: []const u8, pane: []const u8, kind: Kind) Allocator.Error![]u8 {
    _ = home;
    _ = pane;
    _ = kind;
    return alloc.dupe(u8, "");
}

pub fn output(alloc: Allocator, event: []const u8, text: []const u8) Allocator.Error![]u8 {
    _ = event;
    _ = text;
    return alloc.dupe(u8, "");
}

pub fn isSubagent(alloc: Allocator, input: []const u8) bool {
    _ = alloc;
    _ = input;
    return false;
}

pub fn sessionSource(alloc: Allocator, input: []const u8) ?[]const u8 {
    _ = alloc;
    _ = input;
    return null;
}

/// Takes the file at `path` (renaming it first, so of two hooks running at
/// once only one gets it), returns its text and deletes it. Null when
/// there is none.
pub fn take(alloc: Allocator, path: []const u8) ?[]u8 {
    _ = alloc;
    _ = path;
    return null;
}

test "claude speak: pane ids" {
    const t = std.testing;
    try t.expect(isPaneId("0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6"));
    try t.expect(!isPaneId("0f8c2a5e-1b2c-4d3e-8f90-a1b2c3d4e5f6"));
    try t.expect(!isPaneId("../../../../etc/passwd-0000-0000-000000"));
    try t.expect(!isPaneId("0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F"));
    try t.expect(!isPaneId(""));
}

test "claude speak: queued path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings(
        "/Users/me/Library/Application Support/Lostty/handoff/panes/0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6.say",
        try queuedPath(a, "/Users/me", "0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6", .say),
    );
}

test "claude speak: output is Claude's additionalContext JSON" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try output(a, "PostToolUse", "Hand off \"soon\"\nplease");
    try std.testing.expectEqualStrings(
        \\{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Hand off \"soon\"\nplease"}}
    , out);
}

test "claude speak: a subagent's tool call is not spoken to" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect(isSubagent(a,
        \\{"hook_event_name":"PostToolUse","agent_id":"a7","tool_name":"Read"}
    ));
    try std.testing.expect(!isSubagent(a,
        \\{"hook_event_name":"PostToolUse","tool_name":"Read"}
    ));
    try std.testing.expect(!isSubagent(a,
        \\{"hook_event_name":"PostToolUse","agent_id":"","tool_name":"Read"}
    ));
    try std.testing.expect(!isSubagent(a, "not json"));
}

test "claude speak: session source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("clear", sessionSource(a,
        \\{"hook_event_name":"SessionStart","source":"clear"}
    ).?);
    try std.testing.expect(sessionSource(a,
        \\{"hook_event_name":"Stop","source":"clear"}
    ) == null);
    try std.testing.expect(sessionSource(a, "{}") == null);
}

test "claude speak: take is once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "P.say", .data = "the directive" });
    const dir = try tmp.dir.realpathAlloc(a, ".");
    const path = try std.fmt.allocPrint(a, "{s}/P.say", .{dir});
    try std.testing.expectEqualStrings("the directive", take(a, path).?);
    try std.testing.expect(take(a, path) == null);
    // Nothing left behind.
    try std.testing.expectError(error.FileNotFound, tmp.dir.access("P.say.taken", .{}));
}
```

And in `src/cli/claude_state.zig`'s test block, add the import:

```zig
test {
    _ = @import("claude/protocol.zig");
    _ = @import("claude/speak.zig");
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `zig build test -Dtest-filter="claude speak"`
Expected: FAIL — `pane ids` (accepts lowercase), `queued path` (empty string), `output`, `subagent`, `session source`, `take is once` all fail on their first `expect`.

- [ ] **Step 3: Implement** — replace the stubs in `speak.zig`:

```zig
/// A pane id as Lostty sets LOSTTY_SURFACE (`UUID.uuidString`): uppercase
/// hex in 8-4-4-4-12. Anything else is refused, so the variable can't
/// name another file.
pub fn isPaneId(s: []const u8) bool {
    if (s.len != 36) return false;
    for (s, 0..) |c, i| {
        if (i == 8 or i == 13 or i == 18 or i == 23) {
            if (c != '-') return false;
            continue;
        }
        if (!((c >= '0' and c <= '9') or (c >= 'A' and c <= 'F'))) return false;
    }
    return true;
}

pub fn queuedPath(alloc: Allocator, home: []const u8, pane: []const u8, kind: Kind) Allocator.Error![]u8 {
    return std.fmt.allocPrint(alloc, "{s}/{s}/{s}.{s}", .{ home, panes_dir, pane, @tagName(kind) });
}

/// Claude Code's hook output that adds `text` to the model's context.
pub fn output(alloc: Allocator, event: []const u8, text: []const u8) Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(alloc, .{
        .hookSpecificOutput = .{ .hookEventName = event, .additionalContext = text },
    }, .{});
}

/// Whether a tool hook's input comes from one of Claude's subagents (it
/// names a non-empty `agent_id`): the directive is for Claude itself.
pub fn isSubagent(alloc: Allocator, input: []const u8) bool {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const id = parsed.value.object.get("agent_id") orelse return false;
    return id == .string and id.string.len > 0;
}

/// A SessionStart hook's `source` ("startup", "resume", "clear",
/// "compact" or "fork"); null for other events.
pub fn sessionSource(alloc: Allocator, input: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return null;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return null;
    const event = root.object.get("hook_event_name") orelse return null;
    if (event != .string or !std.mem.eql(u8, event.string, "SessionStart")) return null;
    const source = root.object.get("source") orelse return null;
    if (source != .string) return null;
    return alloc.dupe(u8, source.string) catch null;
}

pub fn take(alloc: Allocator, path: []const u8) ?[]u8 {
    const taken = std.fmt.allocPrint(alloc, "{s}.taken", .{path}) catch return null;
    std.fs.renameAbsolute(path, taken) catch return null;
    defer std.fs.deleteFileAbsolute(taken) catch {};
    return std.fs.cwd().readFileAlloc(alloc, taken, text_max) catch null;
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `zig build test -Dtest-filter="claude speak"`
Expected: PASS (6 tests).

- [ ] **Step 5: Wire the states** — in `src/cli/claude/protocol.zig` replace the `State` doc and enum:

```zig
/// `agents`: Claude finished its turn but its subagents are still working,
/// so it carries on by itself when they finish. `resumed`: the last of
/// them finished, so Claude itself works again. `tool`: Claude (or one of
/// its subagents) is about to run a tool; it carries the action, not a
/// change of state. `done` (PostToolUse) and `start` (SessionStart) only
/// speak the context handoff's queued text; `fresh` says a fresh window
/// took the handoff (sent after `start`).
pub const State = enum { busy, idle, exit, agents, resumed, tool, done, start, fresh };
```

In `src/cli/claude_state.zig`, add `const speak = @import("claude/speak.zig");` under the protocol import, extend the doc comment's last sentences to read "It never fails, and prints only the context handoff's queued text (`busy`, `done`, `start`): outside Lostty, without a terminal, or with a bad argument it does nothing and exits 0, so a hook can never break Claude.", and replace the body from `var state = …` through the `switch`:

```zig
    var state = protocol.stateFromArgs(args.items) orelse return 0;
    const pane = std.posix.getenv(protocol.surface_env) orelse return 0;
    var detail: protocol.Detail = .{};
    switch (state) {
        // A prompt: give Claude the directive queued for it, then say busy.
        .busy => _ = speakQueued(alloc, pane, .say, "UserPromptSubmit"),
        // After a tool call: only speak (Claude's own calls, not a subagent's).
        .done => {
            if (hookInput(alloc)) |input| if (speak.isSubagent(alloc, input)) return 0;
            _ = speakQueued(alloc, pane, .say, "PostToolUse");
            return 0;
        },
        // A fresh window after /clear: hand it the handoff, then say so.
        .start => {
            const input = hookInput(alloc) orelse return 0;
            const source = speak.sessionSource(alloc, input) orelse return 0;
            if (!std.mem.eql(u8, source, "clear")) return 0;
            if (!speakQueued(alloc, pane, .start, "SessionStart")) return 0;
            state = .fresh;
        },
        .idle, .resumed => if (hookInput(alloc)) |input| {
            state = protocol.refine(alloc, state, input) orelse return 0;
            detail.permission = state == .idle and protocol.isPermissionPrompt(alloc, input);
            if (state == .idle) detail.transcript = protocol.transcriptPath(alloc, input);
        },
        .tool => detail.action = protocol.action(alloc, hookInput(alloc) orelse return 0) orelse return 0,
        else => {},
    }
```

and add, after `run`:

```zig
/// Prints the text the Mac app queued for this pane as Claude Code's
/// additionalContext for `event`. False when nothing was queued (or the
/// pane id isn't one Lostty sets).
fn speakQueued(alloc: Allocator, pane: []const u8, kind: speak.Kind, event: []const u8) bool {
    if (!speak.isPaneId(pane)) return false;
    const home = std.posix.getenv("HOME") orelse return false;
    const path = speak.queuedPath(alloc, home, pane, kind) catch return false;
    const text = speak.take(alloc, path) orelse return false;
    const out = speak.output(alloc, event, text) catch return false;
    std.fs.File.stdout().writeAll(out) catch return false;
    return true;
}
```

- [ ] **Step 6: Install the two new hooks** — write the failing test first, in `src/cli/claude/hooks.zig` after `"claude hooks: preview lists every event"`:

```zig
test "claude hooks: the handoff's events are installed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a, "{}");
    try std.testing.expect(try install(a, .claude, &root));
    const out = try stringify(a, root);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"PostToolUse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "+claude-state done") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"SessionStart\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "+claude-state start") != null);
    // An install from before the handoff is partial, so Settings offers the update.
    var old = try parseFixture(a, "{}");
    try std.testing.expect(try install(a, .claude, &old));
    _ = old.object.getPtr("hooks").?.object.orderedRemove("PostToolUse");
    try std.testing.expectEqual(Status.partial, try status(a, .claude, old));
}
```

Run: `zig build test -Dtest-filter="claude hooks"`
Expected: FAIL on `"PostToolUse"` not found.

Then in `claude_events` add two lines after PreToolUse, and extend its doc comment with "PostToolUse (`done`) and SessionStart (`start`) only speak the context handoff's queued text.":

```zig
    .{ .name = "PostToolUse", .state = "done" },
    .{ .name = "SessionStart", .state = "start" },
```

Run: `zig build test -Dtest-filter="claude hooks"` then `zig build test -Dtest-filter="claude protocol"` then `zig build test -Dtest-filter="claude speak"`
Expected: all PASS. If an older `claude hooks` test counted events and fails, update its expected count to the new `eventsFor(.claude).len` and say so in the commit message.

- [ ] **Step 7: Build the engine**

Run: `zig build -Demit-macos-app=false`
Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git add src/cli/claude/speak.zig src/cli/claude/protocol.zig src/cli/claude_state.zig src/cli/claude/hooks.zig
git commit -m "lostty: handoff: hooks speak the queued directive and handoff

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Settings values and the policy (Swift, pure)

**Files:**
- Create: `macos/Sources/Features/Handoff/ContextHandoffPreferences.swift`
- Create: `macos/Sources/Features/Handoff/ContextHandoffPolicy.swift`
- Test: `macos/Tests/Handoff/ContextHandoffPolicyTests.swift`

**Interfaces:**
- Produces: `enum ContextHandoffLevel: String, Codable { case limit, ceiling }`
- Produces: `enum ContextHandoffPolicy { static let reminderStep = 25_000; static let ceilingMargin = 100_000; static func limit(setting: Int, size: Int) -> Int; static func ceiling(setting: Int, size: Int) -> Int; static func level(used: Int, size: Int, setting: Int) -> ContextHandoffLevel? }`
- Produces: `final class ContextHandoffPreferences: ObservableObject { static let shared; static let limits: [Int]; @Published var enabled: Bool; @Published var limit: Int; var setting: Int }` (`setting` = the Debug override or `limit`).

- [ ] **Step 1: Write the failing test** — `macos/Tests/Handoff/ContextHandoffPolicyTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ContextHandoffPolicyTests {
    @Test func aOneMillionWindowUsesTheSetting() {
        #expect(ContextHandoffPolicy.limit(setting: 300_000, size: 1_000_000) == 300_000)
        #expect(ContextHandoffPolicy.ceiling(setting: 300_000, size: 1_000_000) == 400_000)
    }

    @Test func aSmallWindowCapsTheLimitAt70AndTheCeilingAt90Percent() {
        #expect(ContextHandoffPolicy.limit(setting: 300_000, size: 200_000) == 140_000)
        #expect(ContextHandoffPolicy.ceiling(setting: 300_000, size: 200_000) == 180_000)
    }

    @Test func levels() {
        #expect(ContextHandoffPolicy.level(used: 299_999, size: 1_000_000, setting: 300_000) == nil)
        #expect(ContextHandoffPolicy.level(used: 300_000, size: 1_000_000, setting: 300_000) == .limit)
        #expect(ContextHandoffPolicy.level(used: 400_000, size: 1_000_000, setting: 300_000) == .ceiling)
    }

    @Test func anUnknownWindowNeverArms() {
        #expect(ContextHandoffPolicy.level(used: 900_000, size: 0, setting: 300_000) == nil)
    }

    @Test func preferencesDefaultOffAt300k() {
        let defaults = UserDefaults(suiteName: "handoff-prefs-\(UUID())")!
        let prefs = ContextHandoffPreferences(defaults: defaults)
        #expect(prefs.enabled == false)
        #expect(prefs.limit == 300_000)
        prefs.enabled = true
        prefs.limit = 500_000
        let again = ContextHandoffPreferences(defaults: defaults)
        #expect(again.enabled)
        #expect(again.limit == 500_000)
    }

    @Test func anUnlistedSavedLimitFallsBackTo300k() {
        let defaults = UserDefaults(suiteName: "handoff-prefs-\(UUID())")!
        defaults.set(123, forKey: ContextHandoffPreferences.limitKey)
        #expect(ContextHandoffPreferences(defaults: defaults).limit == 300_000)
    }

    #if DEBUG
    @Test func theDebugOverrideReplacesTheSetting() {
        let defaults = UserDefaults(suiteName: "handoff-prefs-\(UUID())")!
        defaults.set(20_000, forKey: ContextHandoffPreferences.overrideKey)
        #expect(ContextHandoffPreferences(defaults: defaults).setting == 20_000)
    }
    #endif
}
#endif
```

- [ ] **Step 2: Run it to see it fail**

Run: `SWIFT_TEST ContextHandoffPolicyTests`
Expected: build FAILS — `cannot find 'ContextHandoffPolicy' in scope`.

- [ ] **Step 3: Implement** — `ContextHandoffPolicy.swift`:

```swift
#if os(macOS)
import Foundation

/// How urgent a pane's handoff is: past the limit (hand off at the next
/// clean break) or at the ceiling (hand off at the end of this turn).
enum ContextHandoffLevel: String, Codable, Equatable {
    case limit, ceiling
}

/// When a conversation is long enough to hand off (spec §2): the user's
/// setting, capped at 70% of the pane's window; the ceiling 100k past it,
/// capped at 90%. The directive is repeated each 25k.
enum ContextHandoffPolicy {
    static let reminderStep = 25_000
    static let ceilingMargin = 100_000

    static func limit(setting: Int, size: Int) -> Int {
        min(setting, size * 70 / 100)
    }

    static func ceiling(setting: Int, size: Int) -> Int {
        min(limit(setting: setting, size: size) + ceilingMargin, size * 90 / 100)
    }

    /// Nil below the limit, or while the window's size is unknown.
    static func level(used: Int, size: Int, setting: Int) -> ContextHandoffLevel? {
        guard size > 0 else { return nil }
        if used >= ceiling(setting: setting, size: size) { return .ceiling }
        if used >= limit(setting: setting, size: size) { return .limit }
        return nil
    }
}
#endif
```

`ContextHandoffPreferences.swift`:

```swift
#if os(macOS)
import Foundation

/// Lostty Settings → Mascot: whether long conversations hand off, and
/// after how many tokens (spec §2).
@MainActor
final class ContextHandoffPreferences: ObservableObject {
    static let shared = ContextHandoffPreferences()
    static let enabledKey = "LosttyHandoffEnabled"
    static let limitKey = "LosttyHandoffLimit"
    /// Debug builds only: a limit in tokens for desk checks (20000).
    static let overrideKey = "LosttyHandoffLimitOverride"
    static let limits = [200_000, 300_000, 400_000, 500_000, 600_000]
    static let defaultLimit = 300_000

    private let defaults: UserDefaults

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }

    @Published var limit: Int {
        didSet { defaults.set(limit, forKey: Self.limitKey) }
    }

    init(defaults: UserDefaults = .ghostty) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
        let saved = defaults.integer(forKey: Self.limitKey)
        limit = Self.limits.contains(saved) ? saved : Self.defaultLimit
    }

    /// The limit the policy uses: the Debug override, else the setting.
    var setting: Int {
        #if DEBUG
        let override = defaults.integer(forKey: Self.overrideKey)
        if override > 0 { return override }
        #endif
        return limit
    }
}
#endif
```

- [ ] **Step 4: Run it to see it pass**

Run: `SWIFT_TEST ContextHandoffPolicyTests`
Expected: `** TEST SUCCEEDED **`, 7 tests (6 in Release-style builds without DEBUG).

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Handoff macos/Tests/Handoff
git commit -m "lostty: handoff: the limit, ceiling and settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The directive, the handoff block and the restore lines (Swift, pure)

**Files:**
- Create: `macos/Sources/Features/Handoff/ContextHandoffDirective.swift`
- Create: `macos/Sources/Features/Handoff/ContextHandoffExtract.swift`
- Create: `macos/Sources/Features/Handoff/ContextHandoffAgent.swift`
- Test: `macos/Tests/Handoff/ContextHandoffDirectiveTests.swift`, `macos/Tests/Handoff/ContextHandoffExtractTests.swift`

**Interfaces:**
- Consumes: `ContextHandoffLevel` (Task 2).
- Produces: `enum ContextHandoffDirective { static func text(level:used:limit:ceiling:byButton:problem:) -> String; static func freshStart(handoff:path:used:) -> String; static func continueLine(_ next: ContextHandoff.Next) -> String; static let nudge: String; static func k(_ tokens: Int) -> String }`
- Produces: `struct ContextHandoff: Equatable { enum Next: String, Codable { case continueWork, wait }; var text: String; var next: Next; var summary: String }`, `enum ContextHandoffProblem: Error, Equatable { case none; case missing(String) }`, `enum ContextHandoffExtract { static func find(in reply: String) -> Result<ContextHandoff, ContextHandoffProblem> }`
- Produces: `enum ContextHandoffAgent { static var keepsModel: Bool; static func modelAlias(_ display: String?) -> String?; static func restoreLines(model: String?) -> [String] }`

- [ ] **Step 1: Write the failing tests** — `ContextHandoffExtractTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ContextHandoffExtractTests {
    func block(next: String = "continue", workflow: String? = "none", threads: String? = nil) -> String {
        var lines = ["<lostty-handoff>", "## Goal", "Quit item in the menu bar.",
                     "## Where we are", "Quit committed as c52b00ef5; next: tests.", ""]
        if let threads { lines += ["## Open threads", threads] }
        if let workflow { lines += ["## Active workflow", workflow] }
        lines += ["## Next", next, "</lostty-handoff>"]
        return lines.joined(separator: "\n")
    }

    @Test func aValidBlockAtTheEndOfTheReply() throws {
        let found = try ContextHandoffExtract.find(in: "All done.\n\n" + block()).get()
        #expect(found.next == .continueWork)
        #expect(found.summary == "Quit committed as c52b00ef5; next: tests.")
        #expect(found.text.hasPrefix("## Goal"))
        #expect(!found.text.contains("lostty-handoff"))
    }

    @Test func noBlockIsNone() {
        #expect(ContextHandoffExtract.find(in: "Just a reply.") == .failure(.none))
    }

    @Test func aBlockInsideACodeFenceIsNotAHandoff() {
        let reply = "The format is:\n```\n" + block() + "\n```\nThat's it."
        #expect(ContextHandoffExtract.find(in: reply) == .failure(.none))
    }

    @Test func theLastOfTwoBlocksWins() throws {
        let reply = block(next: "wait", threads: "Merge now?") + "\n\n" + block(next: "continue")
        #expect(try ContextHandoffExtract.find(in: reply).get().next == .continueWork)
    }

    @Test func aMissingActiveWorkflowIsNamed() {
        #expect(ContextHandoffExtract.find(in: block(workflow: nil)) == .failure(.missing("Active workflow")))
    }

    @Test func aMissingNextMeansWaitAndNeedsOpenThreads() {
        let noNext = block().replacingOccurrences(of: "## Next\ncontinue\n", with: "")
        #expect(ContextHandoffExtract.find(in: noNext) == .failure(.missing("Open threads")))
        let withThreads = block(threads: "Shall I merge?").replacingOccurrences(of: "## Next\ncontinue\n", with: "")
        #expect(try ContextHandoffExtract.find(in: withThreads).get().next == .wait)
    }

    @Test func waitWithoutOpenThreadsIsRefused() {
        #expect(ContextHandoffExtract.find(in: block(next: "wait")) == .failure(.missing("Open threads")))
    }

    @Test func anUnclosedBlockIsNone() {
        let open = block().replacingOccurrences(of: "</lostty-handoff>", with: "")
        #expect(ContextHandoffExtract.find(in: open) == .failure(.none))
    }
}
#endif
```

`ContextHandoffDirectiveTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct ContextHandoffDirectiveTests {
    @Test func theLimitDirectiveCarriesTheNumbersAndTheFormat() {
        let text = ContextHandoffDirective.text(level: .limit, used: 312_400, limit: 300_000, ceiling: 400_000,
                                                byButton: false, problem: nil)
        #expect(text.contains("312k"))
        #expect(text.contains("300k"))
        #expect(text.contains("next clean break"))
        #expect(text.contains("<lostty-handoff>"))
        #expect(text.contains("## Active workflow"))
        #expect(text.count < 4_000)
    }

    @Test func theCeilingDirectiveSaysThisTurn() {
        let text = ContextHandoffDirective.text(level: .ceiling, used: 401_000, limit: 300_000, ceiling: 400_000,
                                                byButton: false, problem: nil)
        #expect(text.contains("end of this turn"))
        #expect(text.contains("400k"))
        #expect(text.count < 4_000)
    }

    @Test func theButtonDirectiveSaysTheUserAsked() {
        let text = ContextHandoffDirective.text(level: .limit, used: 150_000, limit: 300_000, ceiling: 400_000,
                                                byButton: true, problem: nil)
        #expect(text.contains("The user asked"))
        #expect(!text.contains("300k"))
    }

    @Test func aProblemLeadsTheDirective() {
        let text = ContextHandoffDirective.text(level: .limit, used: 320_000, limit: 300_000, ceiling: 400_000,
                                                byButton: false, problem: "Your handoff had no 'Active workflow'.")
        #expect(text.hasPrefix("Lostty: Your handoff had no 'Active workflow'."))
    }

    @Test func theFreshStartFitsUnderClaudesCap() {
        let small = ContextHandoffDirective.freshStart(handoff: "## Goal\nX", path: "/h.md", used: 312_000)
        #expect(small.contains("/h.md"))
        #expect(small.contains("312k"))
        #expect(small.hasSuffix("## Goal\nX"))
        let big = ContextHandoffDirective.freshStart(handoff: String(repeating: "a", count: 12_000),
                                                     path: "/h.md", used: 312_000)
        #expect(big.count <= 9_000)
        #expect(big.contains("The full handoff is at /h.md. Read it before acting."))
    }

    @Test func continueLines() {
        #expect(ContextHandoffDirective.continueLine(.continueWork) == "Continue from the handoff.")
        #expect(ContextHandoffDirective.continueLine(.wait)
                == "Read the handoff, restate the open question word for word, and wait for me.")
    }

    @Test func thousands() {
        #expect(ContextHandoffDirective.k(312_999) == "312k")
        #expect(ContextHandoffDirective.k(999) == "0k")
    }

    @Test func restoreLinesOnlyWhenTheModelIsDropped() {
        #expect(ContextHandoffAgent.modelAlias("Opus 4.7 (1M context)") == "opus")
        #expect(ContextHandoffAgent.modelAlias("Sonnet") == "sonnet")
        #expect(ContextHandoffAgent.modelAlias("Mystery") == nil)
        #expect(ContextHandoffAgent.modelAlias(nil) == nil)
        let kept = ContextHandoffAgent.keepsModel
        defer { ContextHandoffAgent.keepsModel = kept }
        ContextHandoffAgent.keepsModel = true
        #expect(ContextHandoffAgent.restoreLines(model: "Opus") == [])
        ContextHandoffAgent.keepsModel = false
        #expect(ContextHandoffAgent.restoreLines(model: "Opus") == ["/model opus"])
        #expect(ContextHandoffAgent.restoreLines(model: "Mystery") == [])
    }
}
#endif
```

- [ ] **Step 2: Run them to see them fail**

Run: `SWIFT_TEST ContextHandoffExtractTests`
Expected: build FAILS — `cannot find 'ContextHandoffExtract' in scope`.

- [ ] **Step 3: Implement** — `ContextHandoffExtract.swift`:

```swift
#if os(macOS)
import Foundation

/// The handoff an agent wrote at a clean break (spec §1).
struct ContextHandoff: Equatable {
    /// `continueWork`: the fresh agent carries on. `wait`: it was waiting
    /// on the user, so the fresh agent restates the question and waits.
    enum Next: String, Codable, Equatable {
        case continueWork, wait
    }

    /// The block's contents, without its tags.
    var text: String
    var next: Next
    /// The first line of "Where we are", for the bubble.
    var summary: String
}

/// Why a reply's handoff wasn't taken: there was none, or it lacked a
/// required section (its name, for the next directive).
enum ContextHandoffProblem: Error, Equatable {
    case none
    case missing(String)
}

/// Finds the `<lostty-handoff>` block at the end of an agent's reply.
enum ContextHandoffExtract {
    static let open = "<lostty-handoff>"
    static let close = "</lostty-handoff>"
    static let summaryMax = 80

    /// The last block outside a code fence, if it has every required
    /// section: Where we are, Active workflow, Next (missing = wait), and
    /// with wait, Open threads.
    static func find(in reply: String) -> Result<ContextHandoff, ContextHandoffProblem> {
        guard let body = lastBlock(reply) else { return .failure(.none) }
        let sections = sections(body)
        for name in ["Where we are", "Active workflow"] where (sections[name] ?? "").isEmpty {
            return .failure(.missing(name))
        }
        let nextWord = (sections["Next"] ?? "").lowercased()
        let next: ContextHandoff.Next = nextWord.hasPrefix("continue") ? .continueWork : .wait
        if next == .wait, (sections["Open threads"] ?? "").isEmpty { return .failure(.missing("Open threads")) }
        let firstLine = (sections["Where we are"] ?? "").split(separator: "\n").first.map(String.init) ?? ""
        return .success(ContextHandoff(text: body, next: next, summary: String(firstLine.prefix(summaryMax))))
    }

    /// The text between the last open and close tag lines that sit outside
    /// a ``` fence; nil without a closed block.
    private static func lastBlock(_ reply: String) -> String? {
        var fenced = false
        var current: [Substring]?
        var last: [Substring]?
        for line in reply.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if current != nil {
                if trimmed == close {
                    last = current
                    current = nil
                } else {
                    current?.append(line)
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                fenced.toggle()
            } else if !fenced, trimmed == open {
                current = []
            }
        }
        return last.map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// "## Name" headings and the trimmed text under each.
    private static func sections(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        var name: String?
        var lines: [Substring] = []
        func flush() {
            if let name { result[name] = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                flush()
                name = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                lines = []
            } else {
                lines.append(line)
            }
        }
        flush()
        return result
    }
}
#endif
```

`ContextHandoffDirective.swift`:

```swift
#if os(macOS)
import Foundation

/// What Lostty tells the agent (spec §1): the directive past the limit,
/// the fresh window's start, and the lines it types.
enum ContextHandoffDirective {
    /// The start text Claude keeps whole (its cap is 10,000).
    static let startMax = 9_000
    /// Of a longer handoff, how much the start text carries.
    static let startKeep = 7_500

    static let nudge = "Write your handoff now: this window is at the Lostty context ceiling."

    /// "312k".
    static func k(_ tokens: Int) -> String { "\(tokens / 1_000)k" }

    static func text(level: ContextHandoffLevel, used: Int, limit: Int, ceiling: Int,
                     byButton: Bool, problem: String?) -> String {
        var lead: String
        if byButton {
            lead = "Lostty: The user asked for a handoff at the next clean break in this conversation."
        } else if level == .ceiling {
            lead = "Lostty: this conversation's context is at \(k(used)) tokens, at the \(k(ceiling)) ceiling set "
                + "in Lostty. Hand off at the end of this turn, even without a clean break: finish the step "
                + "you're on, then write a fuller handoff."
        } else {
            lead = "Lostty: this conversation's context is at \(k(used)) tokens, past the \(k(limit)) handoff "
                + "limit set in Lostty. Keep working, and hand off at the next clean break in the work. Don't "
                + "stop early to do it."
        }
        if let problem { lead = "Lostty: \(problem) Write it again with every required section.\n\n" + lead }
        return lead + "\n\n" + practice
    }

    private static let practice = """
    Clean breaks: a feature or plan task just finished and committed, tests green; you just asked the user \
    a question or handed something back; the working tree is clean, or holds only changes you can describe \
    in a sentence.
    Not a break: mid-debugging with hypotheses open; a half-made edit; tests failing for a reason you don't \
    yet understand; partway through reading code to understand something; a background job, build or \
    subagent still running.

    To hand off, end your turn with this block as the last thing in your reply. Under 8,000 characters; \
    only what git and the files can't tell the next agent; no code dumps.

    <lostty-handoff>
    ## Goal
    (what we're building and why, 2-3 sentences)
    ## Where we are
    (done, with commits; in progress; the exact next step)
    ## Decisions
    (rulings made and options ruled out, with why)
    ## Your instructions
    (the user's instructions from this conversation)
    ## Open threads
    (questions waiting on the user, word for word; hand tests pending)
    ## Gotchas
    (traps found: sandbox refusals, flaky tests, wrong paths)
    ## Pointers
    (branch, worktree, spec, plan, key files)
    ## Active workflow
    (the skill or process you're following and where it stands, or "none")
    ## Next
    continue (or "wait" if you're waiting on the user)
    </lostty-handoff>

    Lostty then clears this window and starts a fresh one from your handoff. You don't need to mention \
    this message to the user.
    """

    /// What the start hook gives the fresh window.
    static func freshStart(handoff: String, path: String, used: Int) -> String {
        let lead = "Lostty: you're continuing from a handoff Lostty saved at \(path) when the last window "
            + "reached \(k(used)) tokens. First re-enter the Active workflow it names (invoke that skill again, "
            + "read its ledger). Check the branch and `git status` against the handoff before acting. If "
            + "anything disagrees, say so and wait.\n\n"
        let whole = lead + handoff
        guard whole.count > startMax else { return whole }
        return lead + String(handoff.prefix(startKeep))
            + "\n\n(The full handoff is at \(path). Read it before acting.)"
    }

    static func continueLine(_ next: ContextHandoff.Next) -> String {
        switch next {
        case .continueWork: "Continue from the handoff."
        case .wait: "Read the handoff, restate the open question word for word, and wait for me."
        }
    }
}
#endif
```

`ContextHandoffAgent.swift`:

```swift
#if os(macOS)
import Foundation

/// What a fresh Claude window needs typed back after /clear (spec §4
/// step 6). The desk check (Task 8) settles what /clear keeps.
@MainActor
enum ContextHandoffAgent {
    /// Whether /clear keeps the model; false types `/model <alias>`.
    static var keepsModel = true

    /// `/model`'s alias for the usage feed's display name ("Opus 4.7" → "opus").
    nonisolated static func modelAlias(_ display: String?) -> String? {
        guard let first = display?.split(separator: " ").first?.lowercased() else { return nil }
        return ["opus", "sonnet", "haiku", "fable"].contains(first) ? first : nil
    }

    static func restoreLines(model: String?) -> [String] {
        guard !keepsModel, let alias = modelAlias(model) else { return [] }
        return ["/model \(alias)"]
    }
}
#endif
```

- [ ] **Step 4: Run them to see them pass**

Run: `SWIFT_TEST ContextHandoffExtractTests` then `SWIFT_TEST ContextHandoffDirectiveTests`
Expected: both `** TEST SUCCEEDED **` (8 and 8 tests).

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Handoff macos/Tests/Handoff
git commit -m "lostty: handoff: the directive, the handoff block and what to type back

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The store and the last reply (Swift)

**Files:**
- Create: `macos/Sources/Features/Handoff/ContextHandoffStore.swift`
- Create: `macos/Sources/Features/Handoff/ContextHandoffReply.swift`
- Test: `macos/Tests/Handoff/ContextHandoffStoreTests.swift`

**Interfaces:**
- Consumes: `ContextHandoffLevel` (Task 2), `ContextHandoff.Next` (Task 3), the Zig file names (Task 1: `<PANE>.say`, `<PANE>.start` under `handoff/panes`).
- Produces: `struct ContextHandoffPane: Codable, Equatable { enum Phase: String, Codable { case armed, pending, clearing }; var phase: Phase; var level: ContextHandoffLevel; var byButton: Bool; var saidAt: Int; var used: Int; var size: Int; var nudged: Bool; var handoff: String?; var next: ContextHandoff.Next?; var summary: String? }`
- Produces: `struct ContextHandoffStore: Sendable { let root: URL; static let standard; static let keep = 50; func saveHandoff(_:project:at:) throws -> URL; func writeSay(_:_:); func writeStart(_:_:); func removeSay(_:); func saveState(_:_:); func loadStates() -> [UUID: ContextHandoffPane]; func removeAll(_:) }`
- Produces: `enum ContextHandoffReply { static func last(_ path: String) -> String?; static func last(in url: URL, agent: TranscriptAgent) -> String? }`

- [ ] **Step 1: Write the failing test** — `ContextHandoffStoreTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ContextHandoffStoreTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("handoff-\(UUID())")
    var store: ContextHandoffStore { ContextHandoffStore(root: root) }
    let pane = UUID()

    @Test func theHookFilesAreWhereTheZigHookLooks() throws {
        store.writeSay(pane, "say this")
        store.writeStart(pane, "start this")
        let dir = root.appendingPathComponent("handoff/panes")
        #expect(try String(contentsOf: dir.appendingPathComponent("\(pane.uuidString).say"), encoding: .utf8) == "say this")
        #expect(try String(contentsOf: dir.appendingPathComponent("\(pane.uuidString).start"), encoding: .utf8) == "start this")
        store.removeSay(pane)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(pane.uuidString).say").path))
        store.removeAll(pane)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(pane.uuidString).start").path))
    }

    @Test func statesRoundTrip() {
        let state = ContextHandoffPane(phase: .armed, level: .limit, byButton: false, saidAt: 300_000,
                                       used: 310_000, size: 1_000_000)
        store.saveState(pane, state)
        #expect(store.loadStates() == [pane: state])
        store.removeAll(pane)
        #expect(store.loadStates().isEmpty)
    }

    @Test func handoffsAreNamedByProjectAndTimeAndNeverOverwritten() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try store.saveHandoff("one", project: "lostty-beta", at: date)
        let second = try store.saveHandoff("two", project: "lostty-beta", at: date)
        #expect(first.deletingLastPathComponent().lastPathComponent == "lostty-beta")
        #expect(first.pathExtension == "md")
        #expect(first != second)
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")
        #expect(try String(contentsOf: second, encoding: .utf8) == "two")
    }

    @Test func aSlashInTheProjectNameCantLeaveTheFolder() throws {
        let url = try store.saveHandoff("x", project: "../evil/name", at: Date())
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().path
                == root.appendingPathComponent("handoffs").path)
    }

    @Test func onlyTheLast50PerProjectAreKept() throws {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<52 {
            _ = try store.saveHandoff("h\(i)", project: "p", at: date)
            date += 60
        }
        let dir = root.appendingPathComponent("handoffs/p")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names.count == 50)
        #expect(try String(contentsOf: dir.appendingPathComponent(names.last!), encoding: .utf8) == "h51")
    }

    @Test func theLastReplyIsReadFromTheFilesEnd() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("t.jsonl")
        let lines = [
            #"{"type":"user","message":{"content":"Build it"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Working."}]}}"#,
            #"{"type":"user","message":{"content":"Now the tests"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Done.\n<lostty-handoff>"}]}}"#,
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(ContextHandoffReply.last(in: url, agent: .claude) == "Done.\n<lostty-handoff>")
    }
}
#endif
```

- [ ] **Step 2: Run it to see it fail**

Run: `SWIFT_TEST ContextHandoffStoreTests`
Expected: build FAILS — `cannot find 'ContextHandoffStore' in scope`.

- [ ] **Step 3: Implement** — `ContextHandoffStore.swift`:

```swift
#if os(macOS)
import Foundation

/// A pane's handoff as the coordinator holds it, saved so a Restart to
/// Update picks it up again (spec §4).
struct ContextHandoffPane: Codable, Equatable {
    /// `armed`: waiting for the agent's handoff. `pending`: saved, in the
    /// grace before /clear. `clearing`: /clear typed, waiting for the
    /// fresh window to take the handoff.
    enum Phase: String, Codable { case armed, pending, clearing }

    var phase: Phase
    var level: ContextHandoffLevel
    var byButton: Bool
    /// The context size when the directive was last queued.
    var saidAt: Int
    var used: Int
    var size: Int
    /// The ceiling nudge was typed (once per arming).
    var nudged = false
    /// The saved handoff, while pending or clearing.
    var handoff: String?
    var next: ContextHandoff.Next?
    var summary: String?
}

/// Lostty's handoff files under Application Support (spec §3, §4): each
/// pane's state and the texts its hooks take (`+claude-state`, which reads
/// `handoff/panes/<PANE>.say` and `.start`), and the saved handoffs.
struct ContextHandoffStore: Sendable {
    static let standard = ContextHandoffStore(root: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lostty"))
    static let keep = 50

    let root: URL

    var panes: URL { root.appendingPathComponent("handoff/panes") }
    var handoffs: URL { root.appendingPathComponent("handoffs") }

    private func file(_ pane: UUID, _ ext: String) -> URL {
        panes.appendingPathComponent("\(pane.uuidString).\(ext)")
    }

    private func write(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The directive the next prompt or tool call gives Claude.
    func writeSay(_ pane: UUID, _ text: String) { write(text, to: file(pane, "say")) }
    /// The handoff the fresh window's start hook gives Claude.
    func writeStart(_ pane: UUID, _ text: String) { write(text, to: file(pane, "start")) }
    func removeSay(_ pane: UUID) { try? FileManager.default.removeItem(at: file(pane, "say")) }

    func saveState(_ pane: UUID, _ state: ContextHandoffPane) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: panes, withIntermediateDirectories: true)
        try? data.write(to: file(pane, "json"), options: .atomic)
    }

    func loadStates() -> [UUID: ContextHandoffPane] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: panes.path)) ?? []
        var result: [UUID: ContextHandoffPane] = [:]
        for name in names where name.hasSuffix(".json") {
            guard let pane = UUID(uuidString: String(name.dropLast(5))),
                  let data = try? Data(contentsOf: panes.appendingPathComponent(name)),
                  let state = try? JSONDecoder().decode(ContextHandoffPane.self, from: data) else { continue }
            result[pane] = state
        }
        return result
    }

    /// The pane's state and both hook texts.
    func removeAll(_ pane: UUID) {
        for ext in ["json", "say", "start"] { try? FileManager.default.removeItem(at: file(pane, ext)) }
    }

    /// Saves a handoff as `handoffs/<project>/<yyyy-MM-dd HHmm>.md` (with
    /// " 2", " 3"… when that minute is taken) and keeps the newest 50.
    func saveHandoff(_ text: String, project: String, at date: Date) throws -> URL {
        let safe = project.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let dir = handoffs.appendingPathComponent(safe.isEmpty ? "Terminal" : safe)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let stem = formatter.string(from: date)
        var url = dir.appendingPathComponent("\(stem).md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(stem) \(n).md")
            n += 1
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        prune(dir)
        return url
    }

    private func prune(_ dir: URL) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "md" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
            }
        for url in files.dropLast(Self.keep) { try? fm.removeItem(at: url) }
    }
}
#endif
```

Note for the executor: the prune test saves 52 files within one test run; creation dates may tie, which is why ties fall back to the name (`yyyy-MM-dd HHmm` sorts by time).

`ContextHandoffReply.swift`:

```swift
#if os(macOS)
import Foundation

/// The agent's reply since your latest prompt, from the end of its
/// conversation file: where a handoff block is.
enum ContextHandoffReply {
    /// How much of the file's end is read.
    static let window = 1 << 20

    /// For a conversation file a hook named (TranscriptLocation decides).
    static func last(_ path: String) -> String? {
        guard let location = TranscriptLocation.allowed(path) else { return nil }
        return last(in: location.url, agent: location.agent)
    }

    static func last(in url: URL, agent: TranscriptAgent) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(window) ? end - UInt64(window) : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        var data = (try? handle.readToEnd()) ?? Data()
        // Mid-file: the first line is cut, so start at the next one.
        if start > 0, let newline = data.firstIndex(of: 0x0A) { data = Data(data[data.index(after: newline)...]) }
        let entries = ConversationReader.parse(data, agent: agent).entries
        return ConversationReader.lastReply(ConversationReader.tail([], adding: entries))
    }
}
#endif
```

- [ ] **Step 4: Run it to see it pass**

Run: `SWIFT_TEST ContextHandoffStoreTests`
Expected: `** TEST SUCCEEDED **`, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Handoff macos/Tests/Handoff
git commit -m "lostty: handoff: where handoffs and the hooks' texts live

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The coordinator (Swift)

**Files:**
- Create: `macos/Sources/Features/Handoff/ContextHandoffCoordinator.swift`
- Test: `macos/Tests/Handoff/ContextHandoffCoordinatorTests.swift`

**Interfaces:**
- Consumes: Tasks 2-4 (`ContextHandoffPolicy`, `ContextHandoffLevel`, `ContextHandoffDirective`, `ContextHandoffExtract`, `ContextHandoff`, `ContextHandoffAgent`, `ContextHandoffStore`, `ContextHandoffPane`).
- Produces: `enum ContextHandoffSignal: Equatable { case stopped(transcript: String), prompted, fresh, gone }`, `enum ContextHandoffKey: Equatable { case text(String), enter }`
- Produces: `final class ContextHandoffCoordinator: ObservableObject` with `static let shared`, `static let grace: TimeInterval = 3`, `static let freshTimeout: TimeInterval = 15`, `static let continueDelay: TimeInterval = 1`, `struct Dependencies`, `init(deps:)`, `@Published private(set) var panes: [UUID: ContextHandoffPane]`, `func line(_ pane: UUID) -> String?`, `func isArmed(_ pane: UUID) -> Bool`, `func contextChanged(_ pane: UUID, used: Int, size: Int)`, `func signal(_ pane: UUID, _ signal: ContextHandoffSignal)`, `func keyTyped(_ pane: UUID)`, `func armByButton(_ pane: UUID, used: Int, size: Int)`, `func decline(_ pane: UUID)`, `func settingChanged(enabled: Bool)`, `func restore()`.

- [ ] **Step 1: Write the failing test** — `ContextHandoffCoordinatorTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct ContextHandoffCoordinatorTests {
    final class World {
        var enabled = true
        var setting = 300_000
        var replies: [String: String] = [:]
        var typed: [(UUID, [ContextHandoffKey])] = []
        var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
        var notified: [String] = []
        var changing: [UUID] = []
        var model: String? = "Opus"
        /// Hold replies back, as the live reader does (it reads off the main actor).
        var deferReplies = false
        var heldReplies: [@MainActor () -> Void] = []
    }

    let world = World()
    let pane = UUID()
    let store = ContextHandoffStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("hc-\(UUID())"))

    func make() -> ContextHandoffCoordinator {
        let world = self.world
        return ContextHandoffCoordinator(deps: .init(
            enabled: { world.enabled },
            setting: { world.setting },
            store: store,
            readReply: { path, done in
                if world.deferReplies {
                    world.heldReplies.append { done(world.replies[path]) }
                } else {
                    done(world.replies[path])
                }
            },
            type: { pane, keys in world.typed.append((pane, keys)) },
            project: { _ in "proj" },
            model: { _ in world.model },
            notify: { world.notified.append($0) },
            conversationChanging: { world.changing.append($0) },
            schedule: { delay, work in world.pending.append((delay, work)) }))
    }

    func runPending() {
        let work = world.pending
        world.pending = []
        for item in work { item.work() }
    }

    var sayFile: URL { store.panes.appendingPathComponent("\(pane.uuidString).say") }
    var startFile: URL { store.panes.appendingPathComponent("\(pane.uuidString).start") }

    let handoff = """
    Done.
    <lostty-handoff>
    ## Where we are
    Quit item committed.
    ## Active workflow
    none
    ## Next
    continue
    </lostty-handoff>
    """

    @Test func passingTheLimitArmsAndQueuesTheDirective() throws {
        let c = make()
        c.contextChanged(pane, used: 299_000, size: 1_000_000)
        #expect(!c.isArmed(pane))
        c.contextChanged(pane, used: 301_000, size: 1_000_000)
        #expect(c.isArmed(pane))
        #expect(try String(contentsOf: sayFile, encoding: .utf8).contains("301k"))
        #expect(c.line(pane) == "Will hand off at the next clean break (301k of 300k).")
    }

    @Test func remindersEach25kAndOnceAtTheCeiling() throws {
        let c = make()
        c.contextChanged(pane, used: 301_000, size: 1_000_000)
        try FileManager.default.removeItem(at: sayFile)  // the hook took it
        c.contextChanged(pane, used: 320_000, size: 1_000_000)
        #expect(!FileManager.default.fileExists(atPath: sayFile.path))
        c.contextChanged(pane, used: 326_000, size: 1_000_000)
        #expect(FileManager.default.fileExists(atPath: sayFile.path))
        try FileManager.default.removeItem(at: sayFile)
        c.contextChanged(pane, used: 400_000, size: 1_000_000)
        #expect(try String(contentsOf: sayFile, encoding: .utf8).contains("end of this turn"))
        #expect(c.panes[pane]?.level == .ceiling)
    }

    @Test func settingOffNeverArms() {
        world.enabled = false
        let c = make()
        c.contextChanged(pane, used: 500_000, size: 1_000_000)
        #expect(!c.isArmed(pane))
    }

    @Test func theFullHandoff() throws {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        #expect(c.panes[pane]?.phase == .pending)
        #expect(world.typed.isEmpty)
        runPending()  // grace
        #expect(world.typed.count == 1)
        #expect(world.typed[0].1 == [.text("/clear"), .enter])
        #expect(c.panes[pane]?.phase == .clearing)
        #expect(try String(contentsOf: startFile, encoding: .utf8).contains("Quit item committed."))
        c.signal(pane, .fresh)
        #expect(world.changing == [pane])
        world.pending.removeAll { $0.delay == ContextHandoffCoordinator.freshTimeout }
        runPending()  // continue delay
        #expect(world.typed.last?.1 == [.text("Continue from the handoff."), .enter])
        #expect(c.panes[pane] == nil)
        #expect(c.line(pane) == "Fresh window: handed off at 312k after 'Quit item committed.'")
        #expect(store.loadStates().isEmpty)
        let saved = try FileManager.default.contentsOfDirectory(atPath: store.handoffs.appendingPathComponent("proj").path)
        #expect(saved.count == 1)
    }

    @Test func typingDuringTheGraceCancels() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.keyTyped(pane)
        runPending()
        #expect(world.typed.isEmpty)
        #expect(c.panes[pane]?.phase == .armed)
    }

    @Test func typingRightAfterAStopDoesNotLoseTheHandoff() {
        world.deferReplies = true
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.keyTyped(pane)  // you start typing your next prompt
        world.heldReplies.forEach { $0() }
        #expect(c.panes[pane]?.phase == .pending)
    }

    @Test func aPromptBeforeTheReplyIsReadDropsTheHandoff() {
        world.deferReplies = true
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.signal(pane, .prompted)  // the agent is working again
        world.heldReplies.forEach { $0() }
        runPending()
        #expect(c.panes[pane]?.phase == .armed)
        #expect(world.typed.isEmpty)
    }

    @Test func aPromptDuringTheGraceCancels() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.signal(pane, .prompted)
        runPending()
        #expect(world.typed.isEmpty)
    }

    @Test func ourOwnClearPromptDoesNotCancelTheFreshWindowWait() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()  // types /clear
        c.signal(pane, .prompted)
        #expect(c.panes[pane]?.phase == .clearing)
        c.signal(pane, .fresh)
        #expect(world.changing == [pane])
    }

    @Test func noFreshWindowIn15sFailsOnceAndTellsYou() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()  // types /clear
        #expect(world.pending.first?.delay == ContextHandoffCoordinator.freshTimeout)
        runPending()  // the timeout
        #expect(c.panes[pane] == nil)
        #expect(world.notified.count == 1)
        #expect(c.line(pane)?.hasPrefix("Handoff saved, but the fresh window didn't start.") == true)
        // Not again in this conversation.
        c.contextChanged(pane, used: 330_000, size: 1_000_000)
        #expect(!c.isArmed(pane))
        // A new conversation arms again.
        c.signal(pane, .stopped(transcript: "/t2"))
        c.contextChanged(pane, used: 330_000, size: 1_000_000)
        #expect(c.isArmed(pane))
    }

    @Test func aReplyWithoutAHandoffStaysArmed() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = "Still debugging."
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        #expect(c.panes[pane]?.phase == .armed)
        #expect(world.typed.isEmpty)
    }

    @Test func anIncompleteHandoffIsSentBackWithWhy() throws {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        try FileManager.default.removeItem(at: sayFile)
        world.replies["/t1"] = handoff.replacingOccurrences(of: "## Active workflow\nnone\n", with: "")
        c.signal(pane, .stopped(transcript: "/t1"))
        #expect(try String(contentsOf: sayFile, encoding: .utf8).hasPrefix("Lostty: Your handoff had no 'Active workflow'."))
    }

    @Test func theCeilingNudgeIsTypedOnceAndOnlyOnce() {
        let c = make()
        c.contextChanged(pane, used: 400_000, size: 1_000_000)
        world.replies["/t1"] = "No handoff yet."
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        #expect(world.typed.map(\.1) == [[.text(ContextHandoffDirective.nudge), .enter]])
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        #expect(world.typed.count == 1)
    }

    @Test func theButtonArmsWithTheSettingOff() throws {
        world.enabled = false
        let c = make()
        c.armByButton(pane, used: 150_000, size: 1_000_000)
        #expect(c.isArmed(pane))
        #expect(try String(contentsOf: sayFile, encoding: .utf8).contains("The user asked"))
        #expect(c.line(pane) == "Will hand off at the next clean break.")
        // A context report doesn't disarm a button's arming.
        c.contextChanged(pane, used: 160_000, size: 1_000_000)
        #expect(c.isArmed(pane))
    }

    @Test func declineDisarmsUntilTheNextConversation() {
        let c = make()
        c.signal(pane, .stopped(transcript: "/t1"))
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        c.decline(pane)
        #expect(!c.isArmed(pane))
        #expect(!FileManager.default.fileExists(atPath: sayFile.path))
        c.contextChanged(pane, used: 340_000, size: 1_000_000)
        #expect(!c.isArmed(pane))
        c.signal(pane, .stopped(transcript: "/t2"))
        c.contextChanged(pane, used: 340_000, size: 1_000_000)
        #expect(c.isArmed(pane))
    }

    @Test func turningTheSettingOffMidPendingCancels() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff
        c.signal(pane, .stopped(transcript: "/t1"))
        c.settingChanged(enabled: false)
        runPending()
        #expect(world.typed.isEmpty)
        #expect(c.panes[pane] == nil)
    }

    @Test func aClosedPaneIsForgotten() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        c.signal(pane, .gone)
        #expect(c.panes[pane] == nil)
        #expect(store.loadStates().isEmpty)
    }

    @Test func aRestartPicksArmedPanesBackUpAndDropsHalfDoneOnes() {
        store.saveState(pane, ContextHandoffPane(phase: .clearing, level: .limit, byButton: false, saidAt: 300_000,
                                                 used: 312_000, size: 1_000_000, handoff: "/h.md"))
        let c = make()
        c.restore()
        #expect(c.panes[pane]?.phase == .armed)
        #expect(c.panes[pane]?.handoff == nil)
    }

    @Test func waitHandoffsTypeTheWaitLine() {
        let c = make()
        c.contextChanged(pane, used: 312_000, size: 1_000_000)
        world.replies["/t1"] = handoff.replacingOccurrences(of: "## Next\ncontinue", with: "## Open threads\nMerge now?\n## Next\nwait")
        c.signal(pane, .stopped(transcript: "/t1"))
        runPending()
        c.signal(pane, .fresh)
        world.pending.removeAll { $0.delay == ContextHandoffCoordinator.freshTimeout }
        runPending()
        #expect(world.typed.last?.1 == [.text(ContextHandoffDirective.continueLine(.wait)), .enter])
    }
}
#endif
```

- [ ] **Step 2: Run it to see it fail**

Run: `SWIFT_TEST ContextHandoffCoordinatorTests`
Expected: build FAILS — `cannot find 'ContextHandoffCoordinator' in scope`.

- [ ] **Step 3: Implement** — `ContextHandoffCoordinator.swift`:

```swift
#if os(macOS)
import Combine
import Foundation

/// What a pane's Claude hooks say that the handoff cares about.
enum ContextHandoffSignal: Equatable {
    /// A turn ended waiting for the user (not a permission prompt).
    case stopped(transcript: String)
    /// A prompt was submitted.
    case prompted
    /// The fresh window's start hook took the handoff after /clear.
    case fresh
    /// The pane's command finished or the pane closed.
    case gone
}

/// What Lostty types into a pane.
enum ContextHandoffKey: Equatable {
    case text(String)
    case enter
}

/// Each pane's context handoff (spec §4): arms past the limit or on the
/// bubble's button, queues the directive for the hooks, takes the agent's
/// handoff at a turn's end, and after a grace clears the window and starts
/// the fresh one from it.
@MainActor
final class ContextHandoffCoordinator: ObservableObject {
    static let shared = ContextHandoffCoordinator()
    static let grace: TimeInterval = 3
    static let freshTimeout: TimeInterval = 15
    /// After the start hook, before typing: the fresh window settles.
    static let continueDelay: TimeInterval = 1

    struct Dependencies {
        var enabled: @MainActor () -> Bool
        var setting: @MainActor () -> Int
        var store: ContextHandoffStore
        /// The agent's last reply in a conversation file, handed back on
        /// the main actor.
        var readReply: @MainActor (String, @escaping @MainActor (String?) -> Void) -> Void
        var type: @MainActor (UUID, [ContextHandoffKey]) -> Void
        /// The pane's working directory's last component.
        var project: @MainActor (UUID) -> String
        /// The usage feed's model name for the pane.
        var model: @MainActor (UUID) -> String?
        var notify: @MainActor (String) -> Void
        /// The observer: this pane's conversation file changes on purpose.
        var conversationChanging: @MainActor (UUID) -> Void
        var schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
        var now: () -> Date = Date.init
    }

    @Published private(set) var panes: [UUID: ContextHandoffPane] = [:]
    /// The bubble's last word on a pane: done, or failed.
    @Published private(set) var notes: [UUID: String] = [:]

    private let deps: Dependencies
    /// Each pane's latest conversation file, from its turn ends.
    private var conversations: [UUID: String] = [:]
    /// Panes not to arm until their conversation changes ("" = the one
    /// under way, not yet named).
    private var declined: [UUID: String] = [:]
    /// Bumped to drop scheduled work for a pane.
    private var generation: [UUID: Int] = [:]
    /// Panes whose agent works: a prompt since its last turn end.
    private var working: Set<UUID> = []
    /// Panes with the ceiling nudge waiting out its grace.
    private var nudgeWaiting: Set<UUID> = []

    init(deps: Dependencies) {
        self.deps = deps
    }

    func isArmed(_ pane: UUID) -> Bool { panes[pane] != nil }

    /// The bubble's line for a pane.
    func line(_ pane: UUID) -> String? {
        if let state = panes[pane] {
            if state.byButton { return "Will hand off at the next clean break." }
            let limit = ContextHandoffPolicy.limit(setting: deps.setting(), size: state.size)
            return "Will hand off at the next clean break (\(ContextHandoffDirective.k(state.used)) of "
                + "\(ContextHandoffDirective.k(limit)))."
        }
        return notes[pane]
    }

    // MARK: - Arming

    func contextChanged(_ pane: UUID, used: Int, size: Int) {
        if var state = panes[pane] {
            state.used = used
            state.size = size
            panes[pane] = state
            guard state.phase == .armed, !state.byButton else { return persist(pane) }
            let level = ContextHandoffPolicy.level(used: used, size: size, setting: deps.setting())
            guard deps.enabled(), let level else { return disarm(pane) }
            if level == .ceiling, state.level == .limit {
                state.level = .ceiling
                state.saidAt = used
                panes[pane] = state
                say(pane, problem: nil)
            } else if used >= state.saidAt + ContextHandoffPolicy.reminderStep {
                state.saidAt = used
                panes[pane] = state
                say(pane, problem: nil)
            }
            return persist(pane)
        }
        guard declined[pane] == nil, deps.enabled(),
              let level = ContextHandoffPolicy.level(used: used, size: size, setting: deps.setting()) else { return }
        arm(pane, level: level, used: used, size: size, byButton: false)
    }

    func armByButton(_ pane: UUID, used: Int, size: Int) {
        declined[pane] = nil
        guard panes[pane] == nil else { return }
        arm(pane, level: .limit, used: used, size: size, byButton: true)
    }

    func decline(_ pane: UUID) {
        disarm(pane)
        declined[pane] = conversations[pane] ?? ""
    }

    func settingChanged(enabled: Bool) {
        guard !enabled else { return }
        for pane in Array(panes.keys) { disarm(pane) }
    }

    /// After a restart: panes armed before it are armed again; one caught
    /// mid-handoff goes back to armed (its saved handoff stays saved).
    func restore() {
        for (pane, var state) in deps.store.loadStates() {
            state.phase = .armed
            state.handoff = nil
            state.next = nil
            state.summary = nil
            panes[pane] = state
            persist(pane)
        }
    }

    private func arm(_ pane: UUID, level: ContextHandoffLevel, used: Int, size: Int, byButton: Bool) {
        notes[pane] = nil
        panes[pane] = ContextHandoffPane(phase: .armed, level: level, byButton: byButton, saidAt: used,
                                         used: used, size: size)
        say(pane, problem: nil)
        persist(pane)
    }

    private func say(_ pane: UUID, problem: String?) {
        guard let state = panes[pane] else { return }
        let setting = deps.setting()
        deps.store.writeSay(pane, ContextHandoffDirective.text(
            level: state.level, used: state.used,
            limit: ContextHandoffPolicy.limit(setting: setting, size: state.size),
            ceiling: ContextHandoffPolicy.ceiling(setting: setting, size: state.size),
            byButton: state.byButton, problem: problem))
    }

    private func disarm(_ pane: UUID) {
        bump(pane)
        nudgeWaiting.remove(pane)
        panes[pane] = nil
        deps.store.removeAll(pane)
    }

    private func persist(_ pane: UUID) {
        if let state = panes[pane] { deps.store.saveState(pane, state) }
    }

    @discardableResult
    private func bump(_ pane: UUID) -> Int {
        let next = (generation[pane] ?? 0) + 1
        generation[pane] = next
        return next
    }

    // MARK: - Signals

    func signal(_ pane: UUID, _ signal: ContextHandoffSignal) {
        switch signal {
        case .stopped(let path): stopped(pane, path)
        case .prompted:
            working.insert(pane)
            interrupted(pane)
        case .fresh: fresh(pane)
        case .gone:
            disarm(pane)
            conversations[pane] = nil
            declined[pane] = nil
            notes[pane] = nil
            working.remove(pane)
        }
    }

    /// A key typed in an armed pane (the app forwards those).
    func keyTyped(_ pane: UUID) { interrupted(pane) }

    /// You typed or prompted: a pending clear or a waiting nudge is off.
    /// A reply still being read is not: typing your next prompt right
    /// after a turn ends mustn't lose its handoff (a prompt drops it
    /// instead, through `working`). Not while clearing: /clear and
    /// Lostty's own lines prompt too.
    private func interrupted(_ pane: UUID) {
        guard var state = panes[pane], state.phase != .clearing else { return }
        nudgeWaiting.remove(pane)
        guard state.phase == .pending else { return }
        bump(pane)
        state.phase = .armed
        state.handoff = nil
        state.saidAt = state.used
        panes[pane] = state
        persist(pane)
    }

    private func stopped(_ pane: UUID, _ path: String) {
        if let declinedPath = declined[pane] {
            if declinedPath.isEmpty { declined[pane] = path } else if declinedPath != path { declined[pane] = nil }
        }
        conversations[pane] = path
        working.remove(pane)
        guard panes[pane]?.phase == .armed else { return }
        let gen = bump(pane)
        deps.readReply(path) { [weak self] reply in
            guard let self, self.generation[pane] == gen else { return }
            self.replied(pane, reply ?? "")
        }
    }

    private func replied(_ pane: UUID, _ reply: String) {
        // A prompt came in while the reply was read: the agent works again.
        guard var state = panes[pane], state.phase == .armed, !working.contains(pane) else { return }
        switch ContextHandoffExtract.find(in: reply) {
        case .success(let handoff):
            do {
                let url = try deps.store.saveHandoff(handoff.text, project: deps.project(pane), at: deps.now())
                state.phase = .pending
                state.handoff = url.path
                state.next = handoff.next
                state.summary = handoff.summary
                panes[pane] = state
                persist(pane)
                let gen = bump(pane)
                deps.schedule(Self.grace) { [weak self] in self?.clear(pane, gen) }
            } catch {
                notes[pane] = "Couldn't save the handoff: \(error.localizedDescription)"
            }
        case .failure(.missing(let section)):
            say(pane, problem: "Your handoff had no '\(section)'.")
        case .failure(.none):
            guard state.level == .ceiling, !state.nudged, !state.byButton else { return }
            state.nudged = true
            panes[pane] = state
            persist(pane)
            nudgeWaiting.insert(pane)
            deps.schedule(Self.grace) { [weak self] in
                guard let self, self.nudgeWaiting.remove(pane) != nil, self.panes[pane]?.phase == .armed,
                      !self.working.contains(pane) else { return }
                self.deps.type(pane, [.text(ContextHandoffDirective.nudge), .enter])
            }
        }
    }

    private func clear(_ pane: UUID, _ gen: Int) {
        guard generation[pane] == gen, var state = panes[pane], state.phase == .pending,
              let path = state.handoff, let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        deps.store.removeSay(pane)
        deps.store.writeStart(pane, ContextHandoffDirective.freshStart(handoff: text, path: path, used: state.used))
        state.phase = .clearing
        panes[pane] = state
        persist(pane)
        deps.type(pane, [.text("/clear"), .enter])
        let wait = bump(pane)
        deps.schedule(Self.freshTimeout) { [weak self] in self?.freshTimedOut(pane, wait) }
    }

    private func fresh(_ pane: UUID) {
        guard let state = panes[pane], state.phase == .clearing else { return }
        deps.conversationChanging(pane)
        let lines = ContextHandoffAgent.restoreLines(model: deps.model(pane))
            + [ContextHandoffDirective.continueLine(state.next ?? .wait)]
        let keys = lines.flatMap { [ContextHandoffKey.text($0), .enter] }
        deps.schedule(Self.continueDelay) { [weak self] in self?.deps.type(pane, keys) }
        disarm(pane)
        notes[pane] = "Fresh window: handed off at \(ContextHandoffDirective.k(state.used)) after "
            + "'\(state.summary ?? "")'"
    }

    private func freshTimedOut(_ pane: UUID, _ gen: Int) {
        guard generation[pane] == gen, let state = panes[pane], state.phase == .clearing else { return }
        disarm(pane)
        declined[pane] = conversations[pane] ?? ""
        let message = "Handoff saved, but the fresh window didn't start. It's at \(state.handoff ?? "")."
        notes[pane] = message
        deps.notify(message)
    }
}
#endif
```

`static let shared` needs live dependencies; until Task 7 adds them, give it a placeholder-free minimal live set here so the file compiles. Add below the class:

```swift
extension ContextHandoffCoordinator.Dependencies {
    /// The app's: files under Application Support, the real clock and
    /// main-queue scheduling. Typing, the model and notifications are
    /// connected by `ContextHandoffWiring` (Task 7).
    static var live: Self {
        Self(
            enabled: { ContextHandoffPreferences.shared.enabled },
            setting: { ContextHandoffPreferences.shared.setting },
            store: .standard,
            readReply: { path, done in
                Task.detached(priority: .utility) {
                    let reply = ContextHandoffReply.last(path)
                    await MainActor.run { done(reply) }
                }
            },
            type: { _, _ in },
            project: { _ in "Terminal" },
            model: { ClaudeUsageRuntime.shared.models[$0] },
            notify: { _ in },
            conversationChanging: { _ in },
            schedule: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
            })
    }
}
```

and change the `shared` line to `static let shared = ContextHandoffCoordinator(deps: .live)`. Task 7 replaces `type`, `project`, `notify` and `conversationChanging` in `.live` with the real ones.

- [ ] **Step 4: Run it to see it pass**

Run: `SWIFT_TEST ContextHandoffCoordinatorTests`
Expected: `** TEST SUCCEEDED **`, 19 tests. If `theFullHandoff`'s pending list holds the timeout before the continue work, the `removeAll` line drops it; don't reorder the coordinator to suit the test.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Handoff macos/Tests/Handoff
git commit -m "lostty: handoff: arm, take the handoff, clear and continue

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Hook signals reach the coordinator (Swift)

**Files:**
- Modify: `macos/Sources/Features/Claude/ClaudeMessage.swift` (add `isFresh`)
- Modify: `macos/Sources/Features/Claude/ClaudeRuntime.swift` (`handoffSignal`, `userVarChanged`, `commandFinished`, `surfaceClosed`)
- Modify: `macos/Sources/Features/Observer/TurnObserver.swift` (add `conversationChanging`)
- Modify: `macos/Sources/Features/Notifications/LosttyNotifications.swift` (Kind `.handoff`)
- Test: `macos/Tests/Claude/ClaudeRuntimeTests.swift`, `macos/Tests/Observer/TurnObserverTests.swift`

**Interfaces:**
- Consumes: `ContextHandoffSignal` (Task 5); the wire `{"v":1,"state":"fresh"}` (Task 1).
- Produces: `ClaudeRuntime.handoffSignal: @MainActor (UUID, ContextHandoffSignal) -> Void`; `ClaudeMessage.isFresh(_:) -> Bool`; `TurnObserver.conversationChanging(_ pane: UUID)`; `LosttyNotification.Kind.handoff(UUID)`.

- [ ] **Step 1: Write the failing tests** — append to `ClaudeRuntimeTests` (inside the struct):

```swift
    @Test func handoffSignals() {
        let runtime = makeRuntime()
        var signals: [ContextHandoffSignal] = []
        runtime.handoffSignal = { _, signal in signals.append(signal) }
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName, value: payload("busy"))
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName,
                               value: #"{"v":1,"state":"idle","transcript":"/t.jsonl"}"#)
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName, value: payload("fresh"))
        runtime.commandFinished(pane)
        #expect(signals == [.prompted, .stopped(transcript: "/t.jsonl"), .fresh, .gone])
    }

    @Test func aPermissionPromptIsNoHandoffStop() {
        let runtime = makeRuntime()
        var signals: [ContextHandoffSignal] = []
        runtime.handoffSignal = { _, signal in signals.append(signal) }
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName, value: payload("busy"))
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName,
                               value: #"{"v":1,"state":"idle","permission":true,"transcript":"/t.jsonl"}"#)
        #expect(signals == [.prompted])
    }

    @Test func freshChangesNoPhase() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName, value: payload("fresh"))
        #expect(runtime.phases[pane] == nil)
    }
```

Append to `TurnObserverTests`:

```swift
    @Test func aDeliberateConversationChangeIsNotHeldOff() {
        toggle.on = false
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        fake.set("/ok/b", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        observer.conversationChanging(pane)
        observer.turnEnded(pane: pane, path: "/ok/b")
        #expect(observer.carry() == [pane: "/ok/b"])
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `SWIFT_TEST ClaudeRuntimeTests`
Expected: build FAILS — `value of type 'ClaudeRuntime' has no member 'handoffSignal'`.

- [ ] **Step 3: Implement**

`ClaudeMessage.swift`, after `transcript(_:)`:

```swift
    /// `{"v":1,"state":"fresh"}`: a fresh window's start hook took the
    /// context handoff after /clear. Not a ClaudeState: it changes no phase.
    static func isFresh(_ value: String) -> Bool {
        object(value)?["state"] as? String == "fresh"
    }
```

`ClaudeRuntime.swift`: after the `turnEnded` property add

```swift
    /// What the context handoff hears: turn ends, prompts, a fresh window
    /// after /clear, and the pane's agent going away. Set at launch.
    var handoffSignal: @MainActor (UUID, ContextHandoffSignal) -> Void = { _, _ in }
```

In `userVarChanged`, right after `guard name == … else { return }`:

```swift
        if ClaudeMessage.isFresh(value) {
            handoffSignal(id, .fresh)
            return
        }
```

and replace its last two lines (`apply(...)` and `if state == .idle …`) with:

```swift
        let permission = ClaudeMessage.isPermission(value)
        apply(state, to: id, permission: permission)
        if state == .busy { handoffSignal(id, .prompted) }
        if state == .idle, turnUnderWay, let path = ClaudeMessage.transcript(value) {
            turnEnded(id, path)
            if !permission { handoffSignal(id, .stopped(transcript: path)) }
        }
```

In `commandFinished(_:)` add `handoffSignal(id, .gone)` after `apply(.exit, to: id)`; in `surfaceClosed(_:)` add `handoffSignal(id, .gone)` as its last line.

`TurnObserver.swift`, after `surfaceClosed(_:)`:

```swift
    /// The context handoff cleared this pane's window on purpose: its next
    /// conversation file is taken at once, not held off for `switchInterval`.
    func conversationChanging(_ pane: UUID) {
        switchedAt[pane] = nil
    }
```

`LosttyNotifications.swift`: in `Kind` add

```swift
        /// A context handoff didn't reach its fresh window.
        case handoff(UUID)
```

and in `slot`'s switch add `case .handoff(let pane): "handoff-\(pane.uuidString)"`.

- [ ] **Step 4: Run them to see them pass**

Run: `SWIFT_TEST ClaudeRuntimeTests` then `SWIFT_TEST TurnObserverTests`
Expected: both `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Claude macos/Sources/Features/Observer macos/Sources/Features/Notifications macos/Tests/Claude macos/Tests/Observer
git commit -m "lostty: handoff: the hooks' signals reach the coordinator

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Wiring and the UI (Swift)

**Files:**
- Create: `macos/Sources/Features/Handoff/ContextHandoffWiring.swift`
- Create: `macos/Sources/Features/Handoff/ContextHandoffBubbleRow.swift`
- Modify: `macos/Sources/Features/Handoff/ContextHandoffCoordinator.swift` (`.live`: real typing, project, notify, observer)
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (after the `TurnObserver.shared.start()` line, ~365)
- Modify: `macos/Sources/Features/Extensions/SidebarMascot.swift` (popover content)
- Modify: `macos/Sources/Features/Claude/ClaudeUsageBar.swift` (`line`)
- Modify: `macos/Sources/Features/Settings/SettingsView.swift`, `macos/Sources/Features/Settings/SettingsUI.swift`
- Test: `macos/Tests/Handoff/ContextHandoffWiringTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `enum ContextHandoffWiring { static func start(); static func project(pwd: String?) -> String; static func showsRow(channel: LosttyChannel, isClaude: Bool) -> Bool; static func surface(_:) -> Ghostty.SurfaceView?; static func type(_:_:) }`

- [ ] **Step 1: Write the failing test** — `ContextHandoffWiringTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct ContextHandoffWiringTests {
    @Test func theProjectIsTheWorkingDirectorysLastComponent() {
        #expect(ContextHandoffWiring.project(pwd: "/Users/me/projectrepos/lostty") == "lostty")
        #expect(ContextHandoffWiring.project(pwd: nil) == "Terminal")
        #expect(ContextHandoffWiring.project(pwd: "/") == "Terminal")
    }

    @Test func onlyBetaClaudePanesGetTheBubbleRow() {
        #expect(ContextHandoffWiring.showsRow(channel: .beta, isClaude: true))
        #expect(!ContextHandoffWiring.showsRow(channel: .beta, isClaude: false))
        #expect(!ContextHandoffWiring.showsRow(channel: .stable, isClaude: true))
    }
}
#endif
```

Run: `SWIFT_TEST ContextHandoffWiringTests`
Expected: build FAILS — `cannot find 'ContextHandoffWiring' in scope`.

- [ ] **Step 2: Implement the wiring** — `ContextHandoffWiring.swift`:

```swift
#if os(macOS)
import AppKit
import Combine
import Foundation

/// Connects the context handoff to the app (beta only): the usage feed,
/// the hooks' signals, the setting, typing into panes, and keys typed
/// while a handoff is pending.
@MainActor
enum ContextHandoffWiring {
    private static var watchers: Set<AnyCancellable> = []
    private static var keyMonitor: Any?

    static func project(pwd: String?) -> String {
        guard let pwd, !pwd.isEmpty else { return "Terminal" }
        let last = (pwd as NSString).lastPathComponent
        return last.isEmpty || last == "/" ? "Terminal" : last
    }

    static func showsRow(channel: LosttyChannel, isClaude: Bool) -> Bool {
        channel.showsMascot && isClaude
    }

    static func surface(_ pane: UUID) -> Ghostty.SurfaceView? {
        (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: pane)
    }

    /// Types into the pane's terminal; Return as a key press, so Claude's
    /// prompt takes it as Enter rather than pasted text.
    static func type(_ pane: UUID, _ keys: [ContextHandoffKey]) {
        guard let surface = surface(pane)?.surfaceModel else { return }
        for key in keys {
            switch key {
            case .text(let text): surface.sendText(text)
            case .enter:
                surface.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .press, mods: []))
                surface.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .release, mods: []))
            }
        }
    }

    static func start() {
        guard LosttyChannel.current.showsMascot, watchers.isEmpty else { return }
        let coordinator = ContextHandoffCoordinator.shared
        coordinator.restore()
        ClaudeRuntime.shared.handoffSignal = { pane, signal in coordinator.signal(pane, signal) }
        ClaudeUsageRuntime.shared.$contexts
            .sink { contexts in
                for (pane, context) in contexts { coordinator.contextChanged(pane, used: context.used, size: context.size) }
            }
            .store(in: &watchers)
        ContextHandoffPreferences.shared.$enabled
            .dropFirst()
            .sink { coordinator.settingChanged(enabled: $0) }
            .store(in: &watchers)
        // A key typed in a pane with a handoff pending (or a nudge waiting)
        // calls it off. The key still reaches the terminal.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if let view = NSApp.keyWindow?.firstResponder as? Ghostty.SurfaceView,
                   coordinator.isArmed(view.id) {
                    coordinator.keyTyped(view.id)
                }
            }
            return event
        }
    }
}
#endif
```

In `ContextHandoffCoordinator.swift`'s `.live`, replace the four stand-ins:

```swift
            type: { ContextHandoffWiring.type($0, $1) },
            project: { ContextHandoffWiring.project(pwd: ContextHandoffWiring.surface($0)?.pwd) },
            model: { ClaudeUsageRuntime.shared.models[$0] },
            notify: { message in
                LosttyNotifications.shared.post(LosttyNotification(
                    kind: .handoff(UUID()), style: .failure, title: "Handoff didn't finish", detail: message))
            },
            conversationChanging: { TurnObserver.shared.conversationChanging($0) },
```

and update `.live`'s doc comment to "The app's: files under Application Support, typing into the pane's terminal, the observer and notification bubbles."

Note: `keyTyped` for an `armed` pane only drops a waiting nudge; a reply being read still counts (Task 5 test `typingRightAfterAStopDoesNotLoseTheHandoff`).

In `AppDelegate.swift`, after `if LosttyChannel.current.showsMascot { TurnObserver.shared.start() }` add:

```swift
        // The context handoff (beta): before the restart resume's hook
        // reinstall, which brings in the handoff's hook events.
        ContextHandoffWiring.start()
```

- [ ] **Step 3: The bubble row** — `ContextHandoffBubbleRow.swift`:

```swift
#if os(macOS)
import SwiftUI

/// Under the mascot's bubble in a Claude pane (spec §2, §3): what the
/// context handoff is doing, and the button to arm or call it off.
struct ContextHandoffBubbleRow: View {
    let pane: UUID
    @ObservedObject private var coordinator = ContextHandoffCoordinator.shared
    @ObservedObject private var usage = ClaudeUsageRuntime.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = coordinator.line(pane) {
                Text(line)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if coordinator.isArmed(pane) {
                    Button("Don't hand off this conversation") { coordinator.decline(pane) }
                } else {
                    Button("Hand off at next break") {
                        let context = usage.contexts[pane]
                        coordinator.armByButton(pane, used: context?.used ?? 0, size: context?.size ?? 0)
                    }
                }
                Spacer()
                Button("Handoffs Folder") {
                    let url = ContextHandoffStore.standard.handoffs
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: MascotBubble.width, alignment: .leading)
    }
}
#endif
```

In `SidebarMascot.swift`, replace the popover's content:

```swift
                .popover(isPresented: bubbleShown, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        MascotBubble(content: bubbleContent, maxHeight: bubbleMaxHeight)
                        if let id = openPane, ContextHandoffWiring.showsRow(
                            channel: .current, isClaude: ClaudeUsageRuntime.shared.sessions.contains(id)) {
                            ContextHandoffBubbleRow(pane: id)
                        }
                    }
                }
```

- [ ] **Step 4: The usage bar's mark** — in `ClaudeUsageBar.swift` add `@ObservedObject private var handoff = ContextHandoffCoordinator.shared` with the other observed objects, and change `line` to:

```swift
    private var line: some View {
        let context = pane.flatMap { usage.contexts[$0] }
        let metric = usage.tracked
        let limit = usage.percent(metric) ?? 0
        let armed = pane.map { handoff.isArmed($0) } ?? false

        return (Text("Context ").foregroundColor(ink.opacity(0.6))
            + ClaudeUsageBlocks.text(context?.percent ?? 0, accent: accent, empty: ink.opacity(0.28))
            + Text(" " + ClaudeUsageFormat.thousands(context?.used ?? 0)).foregroundColor(ink.opacity(0.9))
            + (armed ? Text(" ") + Text(Image(systemName: "arrow.triangle.2.circlepath")).foregroundColor(accent)
                : Text(""))
            + Text("   " + metric.shortTitle + " ").foregroundColor(ink.opacity(0.6))
            + ClaudeUsageBlocks.text(limit, accent: accent, empty: ink.opacity(0.28))
            + Text(" " + ClaudeUsageFormat.percent(limit)).foregroundColor(ink.opacity(0.9)))
            .help(armed ? "Will hand off at the next clean break" : "")
    }
```

- [ ] **Step 5: Settings** — in `SettingsView.swift` add `@ObservedObject var handoff: ContextHandoffPreferences` after `observer`, and inside `Section("Mascot")` after the observer's caption:

```swift
                        Toggle("Hand off long conversations", isOn: $handoff.enabled)
                        Picker("Hand off after", selection: $handoff.limit) {
                            ForEach(ContextHandoffPreferences.limits, id: \.self) { limit in
                                Text(ContextHandoffDirective.k(limit)).tag(limit)
                            }
                        }
                        .disabled(!handoff.enabled)
                        Text("Past this, Claude hands off at its next clean break and Lostty starts a fresh "
                             + "window from the handoff, in terminals open on this Mac. On 200k models: "
                             + "\(ContextHandoffDirective.k(ContextHandoffPolicy.limit(setting: handoff.limit, size: 200_000))).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
```

Update the preview to pass `handoff: ContextHandoffPreferences(defaults: UserDefaults(suiteName: "preview")!)`, and `SettingsUI.swift` line 20 to `SettingsView(sidebar: .shared, observer: .shared, handoff: .shared)`.

- [ ] **Step 6: Run the tests and the full suite**

Run: `SWIFT_TEST ContextHandoffWiringTests`
Expected: `** TEST SUCCEEDED **`, 2 tests.

Run: `macos/build.nu --action test` (log to a file, read the tail)
Expected: `** TEST SUCCEEDED **`, 0 failures.

Run: `cd macos/LosttyRemote && swift test` (the phone package is untouched; this confirms it)
Expected: all pass.

Run: `swiftlint lint --strict` on the changed Swift files
Expected: no violations (fix any it reports).

- [ ] **Step 7: Commit**

```bash
git add macos/Sources macos/Tests
git commit -m "lostty: handoff: wire it into the app, the bubble, the usage bar and Settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Desk check (needs the owner's go-ahead)

This edits `~/.claude/settings.json` (the hook install) and runs a Debug Lostty, both outside the worktree: **ask the owner before starting**. It settles the spec's open facts.

- [ ] **Step 1:** Build Debug: `macos/build.nu` (after `zig build -Demit-macos-app=false`). Launch `macos/build/Debug/Lostty.app` (shows as Lostty[DEBUG]; the installed Lostty keeps running).
- [ ] **Step 2:** In Lostty[DEBUG] → Claude Integration, update the hooks; confirm `~/.claude/settings.json` has `PostToolUse` → `+claude-state done` and `SessionStart` → `+claude-state start`.
- [ ] **Step 3:** `defaults write com.lawliang.lostty.debug LosttyHandoffLimitOverride -int 20000` (use the Debug build's bundle id from its Info.plist), turn on Settings → Mascot → "Hand off long conversations".
- [ ] **Step 4:** In a Debug pane, start `claude --permission-mode acceptEdits --model sonnet` in a scratch repo (`git init` in the scratchpad). Ask it to write a small script in two steps with a commit between. Check:
  - past 20k the usage bar shows the mark and the bubble says "Will hand off…";
  - the agent doesn't hand off mid-edit; after the commit it ends with a `<lostty-handoff>` block;
  - 3 s later `/clear` is typed and runs (note whether the slash menu needed an extra Return);
  - the fresh window gets the handoff and "Continue from the handoff." and carries on;
  - after `/clear`: is the mode still accept-edits? is the model still Sonnet? is a folder added before with `/add-dir` still there? (Run `/status`.)
  - a file appears in `~/Library/Application Support/Lostty/handoffs/<project>/`.
- [ ] **Step 5:** Record the answers in the spec's Facts section. If the model was dropped, change `ContextHandoffAgent.keepsModel`'s default to `false` (`restoreLinesOnlyWhenTheModelIsDropped` sets both values itself, so it stays valid). If `/clear` needed a second Return, change `clear(_:_:)` to type `[.text("/clear"), .enter, .enter]` and update `theFullHandoff`. If the mode was dropped, add "Accept-edits and bypass modes don't survive the fresh window." to the Settings caption; if `/add-dir` folders were dropped, add "Folders added with /add-dir don't carry over." Rerun `macos/build.nu --action test`.
- [ ] **Step 6:** Remove the override (`defaults delete … LosttyHandoffLimitOverride`), quit Lostty[DEBUG], commit:

```bash
git add docs/superpowers/specs/2026-10-16-observer-handoff-design.md macos/Sources macos/Tests
git commit -m "lostty: handoff: what the desk check found about /clear

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
