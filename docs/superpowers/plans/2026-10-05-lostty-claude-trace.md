# Lostty Claude Trace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While Claude Code works in a Lostty pane, a skin-styled light ray races around that pane's inside edge, flashes once when Claude finishes, and Lostty offers to install the Claude hooks that drive it.

**Architecture:** Claude Code hooks run `"$LOSTTY_BIN" +claude-state busy|idle|exit`, which writes an `OSC 1337 SetUserVar=LOSTTY_CLAUDE=<base64 JSON>` to `/dev/tty`. The existing user-var pipeline (Zig parser → `set_user_var` action → `Ghostty.App.swift`) delivers it to a new `ClaudeRuntime`, which keeps a per-pane `TracePhase`. A SwiftUI `Canvas` overlay in `SurfaceWrapper` draws the pane's trace style (from its skin) for that phase. `+claude-hooks` (Zig) edits `~/.claude/settings.json`; the app prompts once to run it.

**Tech Stack:** Zig 0.15.2 (`std.json`, `std.base64`), Swift/SwiftUI (`TimelineView`, `Canvas`), Swift Testing (`import Testing`), AppKit (`NSAlert`, `NSMenu`).

**Spec:** `docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md`

## Global Constraints

- Claude Code itself is never modified; only its documented hooks feature is used.
- User var name: `LOSTTY_CLAUDE`. Payload: base64 of `{"v":1,"state":"busy|idle|exit"}`. Unknown `v` or `state` is ignored.
- Per-pane env vars: `LOSTTY_SURFACE` (pane UUID) and `LOSTTY_BIN` (absolute path of the running Lostty binary).
- Hook command (exact): `[ -n "$LOSTTY_SURFACE" ] && [ -x "$LOSTTY_BIN" ] && "$LOSTTY_BIN" +claude-state <state>; exit 0`, `"timeout": 5`.
- Hook events → states: `UserPromptSubmit`→`busy`, `Stop`→`idle`, `Notification`→`idle`, `SessionEnd`→`exit`.
- `+claude-state` always exits 0 and never prints.
- Timings: fade-in 0.2s; finish = tail stretch 0.4s + pulse 0.25s + fade 0.8s; exit fade 0.3s; one lap = 3s per 1000pt of perimeter at `speed = 1`.
- Overlay inset 1.5pt; `allowsHitTesting(false)`; removed from the view tree when the phase is `.off`.
- `trace_speed` range 0.25–4 (default 1); `trace_length` range 0.05–0.5 (default 0.18).
- Unskinned panes: `beam` in `#ff7ad9` / `#7af0ff`.
- Settings backup file: `settings.json.lostty-backup`. Writes are temp-file + rename. Symlinked `settings.json` is followed.
- UserDefaults key `LosttyClaudeHooksPromptedVersion` (in `UserDefaults.ghostty`), hook format version `1`.
- Zig formatting: `zig fmt .`; Swift: `swiftlint lint --strict --fix` (from `AGENTS.md`).
- Run Zig tests with a filter: `zig build test -Dtest-filter=<name>`. Run Swift tests with `macos/skins-test.sh <SuiteName>` (it prints failures and exits non-zero on failure). Swift tests need the xcframework built once: `zig build -Demit-macos-app=false`.
- Every commit message ends with the `Co-Authored-By:` line the session's harness specifies.
- Do not touch the uncommitted skins work already in the tree (`SKINS.md`, `SkinChipView.swift`, `SkinManager.swift`, `SkinPopoverView.swift`, `SkinManagerTests.swift`, `src/cli/skins.zig`, `src/cli/skins/protocol.zig`) beyond the exact edits listed here, and never `git add -A`; stage files by path.

## Review Focus

1. **Symlinked `settings.json`** (stow/chezmoi dotfiles): install must write through to the link target and leave the symlink in place, not replace it with a plain file. → Task 11 test `claude hooks: install follows a symlink`.
2. **A Lostty hook sharing a matcher group with a user's own hook** (hand-merged file): remove must drop only Lostty's command and keep the group and the user's command. → Task 10 test `claude hooks: remove keeps a user's hook in a shared group`.
3. **`hooks` present but not an object, or an event that is not an array**: install/remove must refuse (file untouched), status must say `unreadable`, never crash or overwrite. → Task 10 test `claude hooks: malformed layouts are refused`.
4. **A pane at or near zero size** (split being created/animated): geometry and lap time must stay finite; no NaN, no division by zero, no hang. → Task 6 tests `zeroSizeIsFinite` and Task 4 test `lapSecondsNeverZero`.
5. **A pane closed mid-flash, then its delayed settle fires**: the runtime must not resurrect the pane's entry. → Task 5 test `settleAfterCloseDoesNothing`.

---

## File Structure

Zig (shared core, CLI):
- Create `src/cli/claude/protocol.zig` — `LOSTTY_CLAUDE` wire format: `State`, `parseState`, `stateFromArgs`, `encodeSequence`.
- Create `src/cli/claude_state.zig` — the `+claude-state` action (thin IO around protocol).
- Create `src/cli/claude/hooks.zig` — pure edits of a parsed settings.json: `status`, `install`, `remove`, `preview`.
- Create `src/cli/claude_hooks.zig` — the `+claude-hooks` action: path resolution, read, backup, atomic write.
- Modify `src/cli/ghostty.zig` — register both actions.

Swift (`macos/Sources/Features/Claude/`):
- `ClaudeMessage.swift` — constants, `ClaudeState`, payload decoding.
- `TracePhase.swift` — `TraceTiming`, `TracePhase` state machine, `TraceFrame` (what to draw at an instant).
- `ClaudeRuntime.swift` — per-pane phases, settle scheduling, debug cycle.
- `TraceResolver.swift` — `ResolvedTrace`, `TraceColors`.
- `EdgePath.swift` — perimeter geometry.
- `TraceOverlay.swift` — `ClaudeTraceLayer`, `TraceOverlay`, occlusion probe, finish pulse, reduced-motion glow.
- `Traces/TraceRenderer.swift` — protocol, `TraceRenderers` lookup, `TraceDraw` helpers.
- `Traces/<Style>Trace.swift` — one file per style (13).
- `ClaudeHooks.swift` — CLI runner, status, prompt policy.
- `ClaudeHooksUI.swift` — launch prompt and menu item (AppKit).

Swift (`macos/Sources/Features/Skins/`):
- Create `SkinTrace.swift` — `BuiltinTrace`, `SkinTrace`.
- Modify `SkinModel.swift` — `Skin.trace`, `SkinConfig.trace`, TOML keys.
- Modify `SkinPresets.swift` — preset styles; shadowing inherits style.

Swift (wiring):
- Modify `macos/Sources/Ghostty/Ghostty.App.swift` — dispatch user var and `command_finished`.
- Modify `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` — env vars, close cleanup.
- Modify `macos/Sources/Ghostty/Surface View/SurfaceView.swift` — add the overlay.
- Modify `macos/Sources/App/macOS/AppDelegate.swift` — prompt + menu items at launch.

Tests: `macos/Tests/Claude/*.swift` (the Tests folder is a synchronized group; new files are picked up automatically), Zig `test` blocks in the new Zig files.

Docs: `SKINS.md`, `docs/skins/skins.example.toml`.

---

### Task 1: Spike — can hooks write to /dev/tty, and does Stop fire on Esc?

Throwaway. Needs the human partner at a keyboard (interactive Claude). Output is a decision recorded in the spec, no product code.

**Files:**
- Create (temporary, deleted at the end): `~/.claude/lostty-spike.json`, `~/.claude/lostty-spike.log`
- Modify: `docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md` (§6 row "Stop missing")

- [ ] **Step 1: Write the spike settings file**

```bash
cat > ~/.claude/lostty-spike.json <<'EOF'
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "echo \"$(date +%T) UserPromptSubmit\" >> ~/.claude/lostty-spike.log; printf '\\033]2;SPIKE busy\\007' > /dev/tty; exit 0" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "echo \"$(date +%T) Stop\" >> ~/.claude/lostty-spike.log; printf '\\033]2;SPIKE idle\\007' > /dev/tty; exit 0" }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "echo \"$(date +%T) Notification\" >> ~/.claude/lostty-spike.log; exit 0" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "echo \"$(date +%T) SessionEnd\" >> ~/.claude/lostty-spike.log; exit 0" }] }]
  }
}
EOF
: > ~/.claude/lostty-spike.log
```

- [ ] **Step 2: Ask the human partner to run this in a Lostty pane and report back**

Message to send them:

> Please run `claude --settings ~/.claude/lostty-spike.json` in a Lostty pane, then:
> 1. Send a prompt that takes a while ("count slowly to 20, one line per number"). Watch the tab title: does it change to `SPIKE busy`, then `SPIKE idle` when Claude finishes?
> 2. Send the same prompt again and press **Esc** mid-answer. Does the title go back to `SPIKE idle`?
> 3. Quit Claude with `/exit`.
> Then paste the output of `cat ~/.claude/lostty-spike.log`.

- [ ] **Step 3: Interpret the result**

- Title changed to `SPIKE busy`/`SPIKE idle` → hooks can write to `/dev/tty`. If it did not change at all, STOP the plan and report to the human partner: the in-band channel does not work and the design must move to spec option C (socket).
- Log shows a `Stop` line after the Esc interrupt → interrupts are covered; no timeout needed.
- No `Stop` after Esc → add a quiet-output fallback (see Step 4).

- [ ] **Step 4: Record the decision in the spec**

Replace the §6 row that starts with `` | `Stop` missing (interrupt, crash) | `` with exactly one of:

If `Stop` fired on Esc:
```markdown
| `Stop` missing (crash) | `command_finished` → exited; `Notification` → idle; next prompt → busy. Verified 2026-10-05: `Stop` fires on Esc interrupt, so no timeout is needed |
```
If it did not:
```markdown
| `Stop` missing (interrupt, crash) | `command_finished` → exited; `Notification` → idle; next prompt → busy. Verified 2026-10-05: `Stop` does NOT fire on Esc; follow-up task: end a busy trace after 60s of no pane output |
```
If it did not fire, tell the human partner that the quiet-output timeout is a follow-up not covered by this plan, and continue.

- [ ] **Step 5: Clean up and commit**

```bash
rm ~/.claude/lostty-spike.json ~/.claude/lostty-spike.log
git add docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md
git commit -m "docs: record Claude hook spike results in trace spec"
```

---

### Task 2: `LOSTTY_CLAUDE` wire format and `+claude-state`

**Files:**
- Create: `src/cli/claude/protocol.zig`
- Create: `src/cli/claude_state.zig`
- Modify: `src/cli/ghostty.zig` (imports ~line 22, `Action` enum ~line 74, `run` switch ~line 154, `options` switch ~line 194, `test` block ~line 311)

**Interfaces:**
- Produces: `protocol.State = enum { busy, idle, exit }`; `protocol.parseState([]const u8) ?State`; `protocol.stateFromArgs([]const []const u8) ?State`; `protocol.encodeSequence(Allocator, State, tmux: bool) ![]u8`; `protocol.user_var_name = "LOSTTY_CLAUDE"`; `protocol.surface_env = "LOSTTY_SURFACE"`. CLI: `ghostty +claude-state busy|idle|exit`.

- [ ] **Step 1: Write the failing tests** — create `src/cli/claude/protocol.zig` with only the tests and the declarations they need stubbed out:

```zig
//! Pure logic for `+claude-state`: the LOSTTY_CLAUDE wire format. See
//! docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md (§2.1).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const user_var_name = "LOSTTY_CLAUDE";
pub const surface_env = "LOSTTY_SURFACE";

pub const State = enum { busy, idle, exit };

test "claude protocol: parseState" {
    const t = std.testing;
    try t.expectEqual(State.busy, parseState("busy").?);
    try t.expectEqual(State.idle, parseState("idle").?);
    try t.expectEqual(State.exit, parseState("exit").?);
    try t.expect(parseState("BUSY") == null);
    try t.expect(parseState("") == null);
}

test "claude protocol: stateFromArgs" {
    const t = std.testing;
    try t.expectEqual(State.busy, stateFromArgs(&.{ "/x/ghostty", "+claude-state", "busy" }).?);
    try t.expect(stateFromArgs(&.{ "/x/ghostty", "+claude-state" }) == null);
    try t.expect(stateFromArgs(&.{ "/x/ghostty", "+claude-state", "nope" }) == null);
    try t.expect(stateFromArgs(&.{ "/x/ghostty", "busy" }) == null);
}

test "claude protocol: encodeSequence round-trips through base64" {
    const alloc = std.testing.allocator;
    const seq = try encodeSequence(alloc, .idle, false);
    defer alloc.free(seq);
    const prefix = "\x1b]1337;SetUserVar=LOSTTY_CLAUDE=";
    try std.testing.expect(std.mem.startsWith(u8, seq, prefix));
    try std.testing.expect(std.mem.endsWith(u8, seq, "\x07"));
    const b64 = seq[prefix.len .. seq.len - 1];
    var out: [64]u8 = undefined;
    const n = try std.base64.standard.Decoder.calcSizeForSlice(b64);
    try std.base64.standard.Decoder.decode(out[0..n], b64);
    try std.testing.expectEqualStrings("{\"v\":1,\"state\":\"idle\"}", out[0..n]);
}

test "claude protocol: encodeSequence wraps for tmux" {
    const alloc = std.testing.allocator;
    const seq = try encodeSequence(alloc, .busy, true);
    defer alloc.free(seq);
    try std.testing.expect(std.mem.startsWith(u8, seq, "\x1bPtmux;\x1b\x1b]1337;SetUserVar=LOSTTY_CLAUDE="));
    try std.testing.expect(std.mem.endsWith(u8, seq, "\x07\x1b\\"));
}
```

Create `src/cli/claude_state.zig`:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("claude/protocol.zig");

pub const Options = struct {
    pub fn deinit(self: Options) void {
        _ = self;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

/// The `claude-state` command is run by Lostty's Claude Code hooks to tell
/// the pane it runs in whether Claude is working: `+claude-state busy`,
/// `+claude-state idle` or `+claude-state exit`. It never fails and never
/// prints: outside Lostty, without a terminal, or with a bad argument it
/// does nothing and exits 0, so a hook can never break Claude.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const argv = std.process.argsAlloc(alloc) catch return 0;
    var args: std.ArrayList([]const u8) = .empty;
    for (argv) |arg| args.append(alloc, arg) catch return 0;
    const state = protocol.stateFromArgs(args.items) orelse return 0;
    if (std.posix.getenv(protocol.surface_env) == null) return 0;

    const tmux = std.posix.getenv("TMUX") != null;
    const seq = protocol.encodeSequence(alloc, state, tmux) catch return 0;
    const tty = std.fs.openFileAbsolute("/dev/tty", .{ .mode = .write_only }) catch return 0;
    defer tty.close();
    tty.writeAll(seq) catch {};
    return 0;
}

test {
    _ = @import("claude/protocol.zig");
}
```

Register in `src/cli/ghostty.zig`:
- after `const skins = @import("skins.zig");` add `const claude_state = @import("claude_state.zig");`
- in `pub const Action = enum {`, after `skins,` add:
  ```zig
      // Lostty: report Claude Code's state to this pane (run by hooks).
      @"claude-state",
  ```
- in `run`'s switch after `.skins => try skins.run(alloc),` add `.@"claude-state" => try claude_state.run(alloc),`
- in `options`' switch after `.skins => skins.Options,` add `.@"claude-state" => claude_state.Options,`
- in the final `test {` block after `_ = skins;` add `_ = claude_state;`

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zig build test -Dtest-filter="claude protocol"`
Expected: compile FAIL — `use of undeclared identifier 'parseState'` (and `stateFromArgs`, `encodeSequence`).

- [ ] **Step 3: Implement** — add to `src/cli/claude/protocol.zig` above the tests:

```zig
pub fn parseState(s: []const u8) ?State {
    return std.meta.stringToEnum(State, s);
}

/// The state named right after `+claude-state` in argv, if valid.
pub fn stateFromArgs(argv: []const []const u8) ?State {
    for (argv, 0..) |arg, i| {
        if (!std.mem.eql(u8, arg, "+claude-state")) continue;
        if (i + 1 >= argv.len) return null;
        return parseState(argv[i + 1]);
    }
    return null;
}

/// OSC 1337 SetUserVar carrying `{"v":1,"state":"<state>"}`. With `tmux`,
/// wrapped in tmux's DCS passthrough (requires `allow-passthrough on`).
pub fn encodeSequence(alloc: Allocator, state: State, tmux: bool) ![]u8 {
    const json = try std.fmt.allocPrint(alloc, "{{\"v\":1,\"state\":\"{s}\"}}", .{@tagName(state)});
    defer alloc.free(json);
    const encoder = std.base64.standard.Encoder;
    const b64 = try alloc.alloc(u8, encoder.calcSize(json.len));
    defer alloc.free(b64);
    _ = encoder.encode(b64, json);
    if (tmux) {
        return std.fmt.allocPrint(alloc, "\x1bPtmux;\x1b\x1b]1337;SetUserVar={s}={s}\x07\x1b\\", .{ user_var_name, b64 });
    }
    return std.fmt.allocPrint(alloc, "\x1b]1337;SetUserVar={s}={s}\x07", .{ user_var_name, b64 });
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zig build test -Dtest-filter="claude protocol"`
Expected: PASS (4 tests).

- [ ] **Step 5: Build and smoke-test the action**

Run: `zig build -Demit-macos-app=false && LOSTTY_SURFACE=x ./zig-out/bin/ghostty +claude-state busy; echo "exit=$?"`
Expected: `exit=0`. (In a Lostty pane this writes an invisible sequence; elsewhere nothing visible happens.)
Run: `./zig-out/bin/ghostty +claude-state bogus; echo "exit=$?"`
Expected: `exit=0`, no output.

- [ ] **Step 6: Format and commit**

```bash
zig fmt src/cli/claude src/cli/claude_state.zig src/cli/ghostty.zig
git add src/cli/claude/protocol.zig src/cli/claude_state.zig src/cli/ghostty.zig
git commit -m "cli: add +claude-state, the LOSTTY_CLAUDE user var sender"
```

---

### Task 3: Payload decoding and per-pane env vars

**Files:**
- Create: `macos/Sources/Features/Claude/ClaudeMessage.swift`
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift:394-395`
- Test: `macos/Tests/Claude/ClaudeMessageTests.swift`

**Interfaces:**
- Produces: `ClaudeConstants.userVarName`, `.surfaceEnvKey`, `.binEnvKey`; `enum ClaudeState: String { case busy, idle, exit }`; `ClaudeMessage.decode(_ value: String) -> ClaudeState?`.

- [ ] **Step 1: Write the failing test** — `macos/Tests/Claude/ClaudeMessageTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct ClaudeMessageTests {
    private func b64(_ json: String) -> String { Data(json.utf8).base64EncodedString() }

    @Test func decodesEachState() {
        #expect(ClaudeMessage.decode(b64(#"{"v":1,"state":"busy"}"#)) == .busy)
        #expect(ClaudeMessage.decode(b64(#"{"v":1,"state":"idle"}"#)) == .idle)
        #expect(ClaudeMessage.decode(b64(#"{"v":1,"state":"exit"}"#)) == .exit)
    }

    @Test func ignoresExtraFields() {
        #expect(ClaudeMessage.decode(b64(#"{"v":1,"state":"busy","tokens":42}"#)) == .busy)
    }

    @Test func rejectsUnknownVersionStateAndGarbage() {
        #expect(ClaudeMessage.decode(b64(#"{"v":2,"state":"busy"}"#)) == nil)
        #expect(ClaudeMessage.decode(b64(#"{"v":1,"state":"thinking"}"#)) == nil)
        #expect(ClaudeMessage.decode(b64(#"{"state":"busy"}"#)) == nil)
        #expect(ClaudeMessage.decode(b64("[1]")) == nil)
        #expect(ClaudeMessage.decode("%%%not base64") == nil)
        #expect(ClaudeMessage.decode("") == nil)
    }

    @Test func matchesTheZigEncoder() {
        // Exact bytes produced by `+claude-state busy` (see protocol.zig).
        #expect(ClaudeMessage.decode("eyJ2IjoxLCJzdGF0ZSI6ImJ1c3kifQ==") == .busy)
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh ClaudeMessageTests`
Expected: FAIL — `cannot find 'ClaudeMessage' in scope`.

- [ ] **Step 3: Implement** — `macos/Sources/Features/Claude/ClaudeMessage.swift`:

```swift
#if os(macOS)
import Foundation

enum ClaudeConstants {
    /// The user var `+claude-state` sets (spec §2.1).
    static let userVarName = "LOSTTY_CLAUDE"
    /// Set on every pane; the hooks' "inside Lostty?" guard.
    static let surfaceEnvKey = "LOSTTY_SURFACE"
    /// Absolute path of the running Lostty binary, for the hooks to call.
    static let binEnvKey = "LOSTTY_BIN"
}

/// What a Claude Code hook reports through `+claude-state`.
enum ClaudeState: String {
    case busy, idle, exit
}

enum ClaudeMessage {
    /// Decodes a LOSTTY_CLAUDE value: base64 of `{"v":1,"state":"…"}`.
    /// Other versions, unknown states and malformed input decode to nil.
    static func decode(_ value: String) -> ClaudeState? {
        guard let data = Data(base64Encoded: value),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (object["v"] as? Int) == 1,
              let raw = object["state"] as? String else { return nil }
        return ClaudeState(rawValue: raw)
    }
}
#endif
```

In `SurfaceView_AppKit.swift`, directly after the line
`surface_cfg.environmentVariables[SkinsConstants.surfaceEnvKey] = id.uuidString` add:

```swift
            // Lostty Claude trace: Claude Code hooks check these to know
            // they run inside Lostty and where the Lostty binary is.
            surface_cfg.environmentVariables[ClaudeConstants.surfaceEnvKey] = id.uuidString
            if let bin = Bundle.main.executableURL?.path {
                surface_cfg.environmentVariables[ClaudeConstants.binEnvKey] = bin
            }
```

- [ ] **Step 4: Run to verify it passes**

Run: `macos/skins-test.sh ClaudeMessageTests`
Expected: PASS (4 tests), `** TEST SUCCEEDED **`.

- [ ] **Step 5: Lint and commit**

```bash
cd macos && swiftlint lint --strict --fix Sources/Features/Claude Tests/Claude && cd ..
git add macos/Sources/Features/Claude/ClaudeMessage.swift macos/Tests/Claude/ClaudeMessageTests.swift "macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift"
git commit -m "claude: decode LOSTTY_CLAUDE and export LOSTTY_SURFACE/LOSTTY_BIN per pane"
```

---

### Task 4: Trace phase state machine and frame math

**Files:**
- Create: `macos/Sources/Features/Claude/TracePhase.swift`
- Test: `macos/Tests/Claude/TracePhaseTests.swift`

**Interfaces:**
- Consumes: `ClaudeState` (Task 3).
- Produces:
  - `enum TraceTiming { static let fadeIn, closeLoop, pulse, finishFade, exitFade: TimeInterval; static var finishTotal: TimeInterval }`
  - `enum TracePhase: Equatable { case off; case racing(since: Date); case finishing(since: Date, at: Date); case fading(since: Date, at: Date) }` with `var isOff: Bool`, `func applying(_ state: ClaudeState, now: Date) -> TracePhase`, `func settled(now: Date) -> TracePhase`
  - `struct TraceFrame: Equatable { var head, length, intensity, pulse: Double }` with `static func make(_ phase: TracePhase, now: Date, lapSeconds: Double, length: Double) -> TraceFrame?` and `static func lapSeconds(perimeter: Double, speed: Double) -> Double`

- [ ] **Step 1: Write the failing tests** — `macos/Tests/Claude/TracePhaseTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct TracePhaseTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func busyStartsRacing() {
        #expect(TracePhase.off.applying(.busy, now: t0) == .racing(since: t0))
    }

    @Test func repeatedBusyKeepsOriginalStart() {
        #expect(TracePhase.racing(since: t0).applying(.busy, now: at(5)) == .racing(since: t0))
    }

    @Test func idleWhileRacingFinishes() {
        #expect(TracePhase.racing(since: t0).applying(.idle, now: at(3)) == .finishing(since: t0, at: at(3)))
    }

    @Test func exitWhileRacingFades() {
        #expect(TracePhase.racing(since: t0).applying(.exit, now: at(3)) == .fading(since: t0, at: at(3)))
    }

    @Test func busyDuringFinishResumesWithoutJump() {
        let finishing = TracePhase.finishing(since: t0, at: at(3))
        #expect(finishing.applying(.busy, now: at(3.5)) == .racing(since: t0))
    }

    @Test func busyAfterExitIsANewSession() {
        #expect(TracePhase.fading(since: t0, at: at(3)).applying(.busy, now: at(10)) == .racing(since: at(10)))
    }

    @Test func idleAndExitWhileOffStayOff() {
        #expect(TracePhase.off.applying(.idle, now: t0) == .off)
        #expect(TracePhase.off.applying(.exit, now: t0) == .off)
    }

    @Test func exitDuringFinishLetsTheFlashComplete() {
        let finishing = TracePhase.finishing(since: t0, at: at(3))
        #expect(finishing.applying(.exit, now: at(3.2)) == finishing)
    }

    @Test func settlesAfterDurations() {
        let finishing = TracePhase.finishing(since: t0, at: at(3))
        #expect(finishing.settled(now: at(3 + TraceTiming.finishTotal - 0.01)) == finishing)
        #expect(finishing.settled(now: at(3 + TraceTiming.finishTotal)) == .off)
        let fading = TracePhase.fading(since: t0, at: at(3))
        #expect(fading.settled(now: at(3 + TraceTiming.exitFade)) == .off)
        #expect(TracePhase.racing(since: t0).settled(now: at(999)) == .racing(since: t0))
    }

    @Test func racingFrameFadesInAndWraps() throws {
        let start = try #require(TraceFrame.make(.racing(since: t0), now: t0, lapSeconds: 2, length: 0.2))
        #expect(start.head == 0)
        #expect(start.intensity == 0)
        let later = try #require(TraceFrame.make(.racing(since: t0), now: at(3), lapSeconds: 2, length: 0.2))
        #expect(abs(later.head - 0.5) < 1e-9)
        #expect(later.intensity == 1)
        #expect(later.length == 0.2)
        #expect(later.pulse == 0)
    }

    @Test func finishFrameStretchesPulsesThenFades() throws {
        let phase = TracePhase.finishing(since: t0, at: at(10))
        let stretched = try #require(TraceFrame.make(phase, now: at(10 + TraceTiming.closeLoop), lapSeconds: 2, length: 0.2))
        #expect(abs(stretched.length - 1) < 1e-9)
        #expect(stretched.intensity == 1)
        let midPulse = try #require(TraceFrame.make(phase, now: at(10 + TraceTiming.closeLoop + TraceTiming.pulse / 2), lapSeconds: 2, length: 0.2))
        #expect(midPulse.pulse > 0.99)
        let end = try #require(TraceFrame.make(phase, now: at(10 + TraceTiming.finishTotal), lapSeconds: 2, length: 0.2))
        #expect(end.intensity == 0)
        // The head keeps the racing pace through the flash: no jump on resume.
        let racingHead = try #require(TraceFrame.make(.racing(since: t0), now: at(10.3), lapSeconds: 2, length: 0.2)).head
        let finishHead = try #require(TraceFrame.make(phase, now: at(10.3), lapSeconds: 2, length: 0.2)).head
        #expect(racingHead == finishHead)
    }

    @Test func fadingFrameDropsToZero() throws {
        let phase = TracePhase.fading(since: t0, at: at(4))
        #expect(try #require(TraceFrame.make(phase, now: at(4), lapSeconds: 2, length: 0.2)).intensity == 1)
        #expect(try #require(TraceFrame.make(phase, now: at(4 + TraceTiming.exitFade), lapSeconds: 2, length: 0.2)).intensity == 0)
    }

    @Test func offHasNoFrame() {
        #expect(TraceFrame.make(.off, now: t0, lapSeconds: 2, length: 0.2) == nil)
    }

    @Test func lapSecondsScalesWithPerimeterAndSpeed() {
        #expect(TraceFrame.lapSeconds(perimeter: 1000, speed: 1) == 3)
        #expect(TraceFrame.lapSeconds(perimeter: 2000, speed: 2) == 3)
    }

    @Test func lapSecondsNeverZero() {
        #expect(TraceFrame.lapSeconds(perimeter: 0, speed: 1) > 0)
        #expect(TraceFrame.lapSeconds(perimeter: 3, speed: 4) > 0)
        let frame = TraceFrame.make(.racing(since: t0), now: at(1), lapSeconds: TraceFrame.lapSeconds(perimeter: 0, speed: 1), length: 0.2)
        #expect(frame?.head.isFinite == true)
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh TracePhaseTests`
Expected: FAIL — `cannot find 'TracePhase' in scope`.

- [ ] **Step 3: Implement** — `macos/Sources/Features/Claude/TracePhase.swift`:

```swift
#if os(macOS)
import Foundation

/// Trace animation timings (spec §4).
enum TraceTiming {
    static let fadeIn: TimeInterval = 0.2
    /// The tail stretches until it wraps the whole edge.
    static let closeLoop: TimeInterval = 0.4
    static let pulse: TimeInterval = 0.25
    static let finishFade: TimeInterval = 0.8
    static let exitFade: TimeInterval = 0.3
    static var finishTotal: TimeInterval { closeLoop + pulse + finishFade }
}

/// One pane's trace over time. `since` is when racing began; it survives a
/// finish cancelled by a new prompt, so the head never jumps.
enum TracePhase: Equatable {
    case off
    case racing(since: Date)
    case finishing(since: Date, at: Date)
    case fading(since: Date, at: Date)

    var isOff: Bool { self == .off }

    func applying(_ state: ClaudeState, now: Date) -> TracePhase {
        switch (state, self) {
        case (.busy, .off), (.busy, .fading):
            return .racing(since: now)
        case (.busy, .finishing(let since, _)):
            return .racing(since: since)
        case (.busy, .racing):
            return self
        case (.idle, .racing(let since)):
            return .finishing(since: since, at: now)
        case (.exit, .racing(let since)):
            return .fading(since: since, at: now)
        case (.idle, _), (.exit, _):
            return self
        }
    }

    /// Returns `.off` once a flash or fade has run its course.
    func settled(now: Date) -> TracePhase {
        switch self {
        case .finishing(_, let at) where now.timeIntervalSince(at) >= TraceTiming.finishTotal:
            return .off
        case .fading(_, let at) where now.timeIntervalSince(at) >= TraceTiming.exitFade:
            return .off
        default:
            return self
        }
    }
}

/// What to draw at one instant. Positions are fractions of the perimeter,
/// clockwise from the top-left corner.
struct TraceFrame: Equatable {
    /// Head position, 0..<1.
    var head: Double
    /// Tail length, 0...1.
    var length: Double
    /// Overall opacity, 0...1.
    var intensity: Double
    /// Whole-border finish flash, 0...1.
    var pulse: Double

    static func make(_ phase: TracePhase, now: Date, lapSeconds: Double, length: Double) -> TraceFrame? {
        func elapsed(_ from: Date) -> Double { max(0, now.timeIntervalSince(from)) }
        func head(_ since: Date) -> Double {
            (elapsed(since) / lapSeconds).truncatingRemainder(dividingBy: 1)
        }

        switch phase {
        case .off:
            return nil

        case .racing(let since):
            let intensity = min(1, elapsed(since) / TraceTiming.fadeIn)
            return TraceFrame(head: head(since), length: length, intensity: intensity, pulse: 0)

        case .finishing(let since, let at):
            let t = elapsed(at)
            let close = min(1, t / TraceTiming.closeLoop)
            let eased = 1 - pow(1 - close, 3)
            let afterClose = t - TraceTiming.closeLoop
            let pulse = (0..<TraceTiming.pulse).contains(afterClose)
                ? sin(.pi * afterClose / TraceTiming.pulse) : 0
            let fadeT = afterClose - TraceTiming.pulse
            let intensity = fadeT <= 0 ? 1 : max(0, 1 - fadeT / TraceTiming.finishFade)
            return TraceFrame(
                head: head(since), length: length + (1 - length) * eased,
                intensity: intensity, pulse: pulse)

        case .fading(let since, let at):
            let intensity = max(0, 1 - elapsed(at) / TraceTiming.exitFade)
            return TraceFrame(head: head(since), length: length, intensity: intensity, pulse: 0)
        }
    }

    /// 3s per 1000pt of perimeter at speed 1, so the head moves at the same
    /// pace in every pane. Never below 0.25s, so tiny panes stay finite.
    static func lapSeconds(perimeter: Double, speed: Double) -> Double {
        max(0.25, 3 * (perimeter / 1000) / speed)
    }
}
#endif
```

- [ ] **Step 4: Run to verify it passes**

Run: `macos/skins-test.sh TracePhaseTests`
Expected: PASS (14 tests).

- [ ] **Step 5: Lint and commit**

```bash
cd macos && swiftlint lint --strict --fix Sources/Features/Claude Tests/Claude && cd ..
git add macos/Sources/Features/Claude/TracePhase.swift macos/Tests/Claude/TracePhaseTests.swift
git commit -m "claude: trace phase state machine and frame math"
```

---

### Task 5: `ClaudeRuntime` and wiring into the app

**Files:**
- Create: `macos/Sources/Features/Claude/ClaudeRuntime.swift`
- Modify: `macos/Sources/Ghostty/Ghostty.App.swift` (`userVarChanged` ~line 1727, `commandFinished` ~line 1414)
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (`deinit` ~line 416)
- Test: `macos/Tests/Claude/ClaudeRuntimeTests.swift`

**Interfaces:**
- Consumes: `ClaudeConstants`, `ClaudeMessage.decode`, `ClaudeState` (Task 3); `TracePhase`, `TraceTiming` (Task 4).
- Produces: `@MainActor final class ClaudeRuntime: ObservableObject` with `static let shared`, `@Published private(set) var phases: [UUID: TracePhase]`, `init(now:schedule:)`, `func phase(_ id: UUID) -> TracePhase`, `func userVarChanged(_ id: UUID, name: String, value: String)`, `func commandFinished(_ id: UUID)`, `func surfaceClosed(_ id: UUID)`, `func apply(_ state: ClaudeState, to id: UUID)`, `func debugCycle(_ id: UUID)`.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/Claude/ClaudeRuntimeTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct ClaudeRuntimeTests {
    final class Harness {
        var clock = Date(timeIntervalSince1970: 1_000)
        var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    }

    let harness = Harness()
    let pane = UUID()

    func makeRuntime() -> ClaudeRuntime {
        let harness = self.harness
        return ClaudeRuntime(
            now: { harness.clock },
            schedule: { delay, work in harness.pending.append((delay, work)) })
    }

    func payload(_ state: String) -> String {
        Data(#"{"v":1,"state":"\#(state)"}"#.utf8).base64EncodedString()
    }

    /// Advances the clock past every scheduled settle and runs them.
    func runPending() {
        let work = harness.pending
        harness.pending = []
        for item in work {
            harness.clock = harness.clock.addingTimeInterval(item.delay)
            item.work()
        }
    }

    @Test func busyUserVarStartsRacing() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("busy"))
        #expect(runtime.phase(pane) == .racing(since: harness.clock))
    }

    @Test func otherUserVarsAndGarbageAreIgnored() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: "GHOSTTY_SKIN", value: payload("busy"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: "garbage")
        #expect(runtime.phase(pane) == .off)
        #expect(runtime.phases.isEmpty)
    }

    @Test func idleFinishesThenSettlesOff() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        guard case .finishing = runtime.phase(pane) else { Issue.record("expected finishing"); return }
        #expect(harness.pending.count == 1)
        #expect(harness.pending[0].delay >= TraceTiming.finishTotal)
        runPending()
        #expect(runtime.phase(pane) == .off)
        #expect(runtime.phases[pane] == nil)
    }

    @Test func newPromptDuringFlashKeepsRacing() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        let start = harness.clock
        runtime.apply(.idle, to: pane)
        runtime.apply(.busy, to: pane)
        runPending()
        #expect(runtime.phase(pane) == .racing(since: start))
    }

    @Test func commandFinishedFadesARacingTrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.commandFinished(pane)
        guard case .fading = runtime.phase(pane) else { Issue.record("expected fading"); return }
        runPending()
        #expect(runtime.phase(pane) == .off)
    }

    @Test func commandFinishedOnAnIdlePaneDoesNothing() {
        let runtime = makeRuntime()
        runtime.commandFinished(pane)
        #expect(runtime.phases.isEmpty)
        #expect(harness.pending.isEmpty)
    }

    @Test func panesAreIndependent() {
        let runtime = makeRuntime()
        let other = UUID()
        runtime.apply(.busy, to: pane)
        #expect(runtime.phase(other) == .off)
    }

    @Test func settleAfterCloseDoesNothing() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        runtime.surfaceClosed(pane)
        runPending()
        #expect(runtime.phases[pane] == nil)
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh ClaudeRuntimeTests`
Expected: FAIL — `cannot find 'ClaudeRuntime' in scope`.

- [ ] **Step 3: Implement** — `macos/Sources/Features/Claude/ClaudeRuntime.swift`:

```swift
#if os(macOS)
import Foundation
import Combine

/// App-wide Claude wiring: each pane's trace phase, fed by `+claude-state`
/// hooks (as the LOSTTY_CLAUDE user var) and by the pane's shell reporting
/// that a command finished.
@MainActor
final class ClaudeRuntime: ObservableObject {
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    static let shared = ClaudeRuntime()

    /// Only panes whose phase is not `.off`.
    @Published private(set) var phases: [UUID: TracePhase] = [:]

    private let now: () -> Date
    private let schedule: Scheduler

    init(
        now: @escaping () -> Date = Date.init,
        schedule: @escaping Scheduler = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { work() }
            }
        }
    ) {
        self.now = now
        self.schedule = schedule
    }

    func phase(_ id: UUID) -> TracePhase { phases[id] ?? .off }

    func userVarChanged(_ id: UUID, name: String, value: String) {
        guard name == ClaudeConstants.userVarName else { return }
        guard let state = ClaudeMessage.decode(value) else {
            Ghostty.logger.debug("claude: rejected malformed \(ClaudeConstants.userVarName) payload")
            return
        }
        apply(state, to: id)
    }

    /// The pane's shell reported a command finished, so whatever ran there
    /// (claude included) is gone: a racing trace must not stay up.
    func commandFinished(_ id: UUID) {
        apply(.exit, to: id)
    }

    func surfaceClosed(_ id: UUID) {
        phases[id] = nil
    }

    func apply(_ state: ClaudeState, to id: UUID) {
        let next = phase(id).applying(state, now: now())
        store(next, for: id)
        switch next {
        case .finishing: settle(id, after: TraceTiming.finishTotal)
        case .fading: settle(id, after: TraceTiming.exitFade)
        case .off, .racing: break
        }
    }

    /// Debug builds: a fake 4s busy → idle cycle to review a style by eye.
    func debugCycle(_ id: UUID) {
        apply(.busy, to: id)
        schedule(4) { [weak self] in self?.apply(.idle, to: id) }
    }

    private func settle(_ id: UUID, after delay: TimeInterval) {
        // A little slack so the frame at the end of the animation is drawn.
        schedule(delay + 0.05) { [weak self] in
            guard let self, let current = self.phases[id] else { return }
            self.store(current.settled(now: self.now()), for: id)
        }
    }

    private func store(_ phase: TracePhase, for id: UUID) {
        let value: TracePhase? = phase.isOff ? nil : phase
        if phases[id] != value { phases[id] = value }
    }
}
#endif
```

Wire `Ghostty.App.swift` `userVarChanged` — replace its `MainActor.assumeIsolated { ... }` block with:

```swift
            // Ghostty Skins: requests from the `skins` CLI arrive as a user var.
            // Lostty Claude trace: hook reports arrive the same way.
            MainActor.assumeIsolated {
                SkinsRuntime.shared.userVarChanged(surfaceView, name: name, value: value)
                ClaudeRuntime.shared.userVarChanged(surfaceView.id, name: name, value: value)
            }
```

Wire `commandFinished` — in the `case GHOSTTY_TARGET_SURFACE:` branch, directly after `guard let surfaceView = self.surfaceView(from: surface) else { return }` and **before** the notification-settings checks, add:

```swift
                // Lostty Claude trace: a finished command means claude (if it
                // ran here) is gone. Before the notify settings, which return early.
                MainActor.assumeIsolated { ClaudeRuntime.shared.commandFinished(surfaceView.id) }
```

Wire close cleanup — in `SurfaceView_AppKit.swift`'s `deinit` (the one starting `// Remove all of our notificationcenter subscriptions`), add at the top:

```swift
            // Lostty Claude trace: forget this pane's trace phase.
            let closedID = id
            Task { @MainActor in ClaudeRuntime.shared.surfaceClosed(closedID) }
```

- [ ] **Step 4: Run to verify it passes**

Run: `macos/skins-test.sh ClaudeRuntimeTests`
Expected: PASS (8 tests). Then run `macos/skins-test.sh` (all suites) — expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Lint and commit**

```bash
cd macos && swiftlint lint --strict --fix Sources/Features/Claude Tests/Claude && cd ..
git add macos/Sources/Features/Claude/ClaudeRuntime.swift macos/Tests/Claude/ClaudeRuntimeTests.swift macos/Sources/Ghostty/Ghostty.App.swift "macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift"
git commit -m "claude: per-pane trace runtime fed by hooks and command_finished"
```

---

### Task 6: `EdgePath` geometry

**Files:**
- Create: `macos/Sources/Features/Claude/EdgePath.swift`
- Test: `macos/Tests/Claude/EdgePathTests.swift`

**Interfaces:**
- Produces: `struct EdgePath { struct Sample: Equatable { var point: CGPoint; var tangent: CGVector; var normal: CGVector }; let rect: CGRect; var perimeter: Double; init(size: CGSize, inset: CGFloat); func sample(at fraction: Double) -> Sample; func segment(from: Double, to: Double) -> Path; func offsetPoint(at fraction: Double, inward: CGFloat) -> CGPoint; var outline: Path }`. Fractions wrap (any real number is valid). `normal` always points into the pane.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/Claude/EdgePathTests.swift`:

```swift
#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

struct EdgePathTests {
    // 100x50 pane, inset 0 → perimeter 300. Top edge = 0..<1/3.
    let path = EdgePath(size: CGSize(width: 100, height: 50), inset: 0)

    @Test func perimeter() {
        #expect(path.perimeter == 300)
        #expect(EdgePath(size: CGSize(width: 100, height: 50), inset: 5).perimeter == 260)
    }

    @Test func walksClockwiseFromTopLeft() {
        #expect(path.sample(at: 0).point == CGPoint(x: 0, y: 0))
        #expect(path.sample(at: 50.0 / 300).point == CGPoint(x: 50, y: 0))
        #expect(path.sample(at: 125.0 / 300).point == CGPoint(x: 100, y: 25))
        #expect(path.sample(at: 200.0 / 300).point == CGPoint(x: 50, y: 50))
        #expect(path.sample(at: 275.0 / 300).point == CGPoint(x: 0, y: 25))
    }

    @Test func tangentsAndInwardNormals() {
        let top = path.sample(at: 0.1)
        #expect(top.tangent == CGVector(dx: 1, dy: 0))
        #expect(top.normal == CGVector(dx: 0, dy: 1))
        let right = path.sample(at: 125.0 / 300)
        #expect(right.tangent == CGVector(dx: 0, dy: 1))
        #expect(right.normal == CGVector(dx: -1, dy: 0))
        let bottom = path.sample(at: 200.0 / 300)
        #expect(bottom.normal == CGVector(dx: 0, dy: -1))
        let left = path.sample(at: 275.0 / 300)
        #expect(left.normal == CGVector(dx: 1, dy: 0))
    }

    @Test func fractionsWrap() {
        #expect(path.sample(at: 1.25).point == path.sample(at: 0.25).point)
        #expect(path.sample(at: -0.25).point == path.sample(at: 0.75).point)
        #expect(path.sample(at: 1).point == path.sample(at: 0).point)
    }

    @Test func offsetPointMovesInward() {
        #expect(path.offsetPoint(at: 50.0 / 300, inward: 4) == CGPoint(x: 50, y: 4))
    }

    @Test func segmentAcrossTheStartCorner() {
        let seg = path.segment(from: -0.05, to: 0.05)
        #expect(!seg.isEmpty)
        let box = seg.boundingRect
        #expect(box.minX <= 0.001 && box.maxX >= 14.9)
        #expect(box.maxY >= 14.9)
    }

    @Test func zeroSizeIsFinite() {
        let empty = EdgePath(size: .zero, inset: 1.5)
        #expect(empty.perimeter == 0)
        let s = empty.sample(at: 0.3)
        #expect(s.point.x.isFinite && s.point.y.isFinite)
        _ = empty.segment(from: 0, to: 0.5)
        let tiny = EdgePath(size: CGSize(width: 2, height: 2), inset: 1.5)
        #expect(tiny.perimeter == 0)
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh EdgePathTests`
Expected: FAIL — `cannot find 'EdgePath' in scope`.

- [ ] **Step 3: Implement** — `macos/Sources/Features/Claude/EdgePath.swift`:

```swift
#if os(macOS)
import SwiftUI

/// A pane's inside edge as one clockwise loop starting at the top-left
/// corner, in SwiftUI coordinates (y grows down). Fractions of the
/// perimeter wrap, so any real number is a valid position.
struct EdgePath {
    struct Sample: Equatable {
        var point: CGPoint
        /// Direction of travel (unit vector).
        var tangent: CGVector
        /// Points into the pane (unit vector).
        var normal: CGVector
    }

    let rect: CGRect

    var perimeter: Double { 2 * Double(rect.width + rect.height) }

    init(size: CGSize, inset: CGFloat) {
        let width = max(0, size.width - 2 * inset)
        let height = max(0, size.height - 2 * inset)
        // Degenerate panes collapse to a point so every sample stays finite.
        if width == 0 || height == 0 {
            rect = CGRect(x: inset, y: inset, width: 0, height: 0)
        } else {
            rect = CGRect(x: inset, y: inset, width: width, height: height)
        }
    }

    func sample(at fraction: Double) -> Sample {
        let total = perimeter
        guard total > 0 else {
            return Sample(point: rect.origin, tangent: CGVector(dx: 1, dy: 0), normal: CGVector(dx: 0, dy: 1))
        }
        var wrapped = fraction.truncatingRemainder(dividingBy: 1)
        if wrapped < 0 { wrapped += 1 }
        var d = CGFloat(wrapped * total)
        let w = rect.width, h = rect.height
        if d < w {
            return Sample(point: CGPoint(x: rect.minX + d, y: rect.minY),
                          tangent: CGVector(dx: 1, dy: 0), normal: CGVector(dx: 0, dy: 1))
        }
        d -= w
        if d < h {
            return Sample(point: CGPoint(x: rect.maxX, y: rect.minY + d),
                          tangent: CGVector(dx: 0, dy: 1), normal: CGVector(dx: -1, dy: 0))
        }
        d -= h
        if d < w {
            return Sample(point: CGPoint(x: rect.maxX - d, y: rect.maxY),
                          tangent: CGVector(dx: -1, dy: 0), normal: CGVector(dx: 0, dy: -1))
        }
        d -= w
        return Sample(point: CGPoint(x: rect.minX, y: rect.maxY - d),
                      tangent: CGVector(dx: 0, dy: -1), normal: CGVector(dx: 1, dy: 0))
    }

    /// The point `inward` points into the pane from the edge at `fraction`.
    func offsetPoint(at fraction: Double, inward: CGFloat) -> CGPoint {
        let s = sample(at: fraction)
        return CGPoint(x: s.point.x + s.normal.dx * inward, y: s.point.y + s.normal.dy * inward)
    }

    /// The edge between two fractions (`to` ≥ `from`), as a polyline with
    /// ~3pt resolution and the corners it passes included.
    func segment(from: Double, to: Double) -> Path {
        var path = Path()
        let span = max(0, to - from)
        guard perimeter > 0, span > 0 else { return path }
        let steps = min(800, max(2, Int(span * perimeter / 3)))
        for i in 0...steps {
            let point = sample(at: from + span * Double(i) / Double(steps)).point
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// The whole loop.
    var outline: Path { Path(rect) }
}
#endif
```

Note: with ~3pt sampling a corner can be cut by at most 3pt — invisible at trace widths. `segmentAcrossTheStartCorner` checks the bounding box reaches both edges (15pt along each, within one step).

- [ ] **Step 4: Run to verify it passes**

Run: `macos/skins-test.sh EdgePathTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Lint and commit**

```bash
cd macos && swiftlint lint --strict --fix Sources/Features/Claude Tests/Claude && cd ..
git add macos/Sources/Features/Claude/EdgePath.swift macos/Tests/Claude/EdgePathTests.swift
git commit -m "claude: EdgePath perimeter geometry for traces"
```

---

### Task 7: Trace settings in skins (model, skins.toml, presets, resolver)

**Files:**
- Create: `macos/Sources/Features/Skins/SkinTrace.swift`
- Create: `macos/Sources/Features/Claude/TraceResolver.swift`
- Modify: `macos/Sources/Features/Skins/SkinModel.swift` (`Skin` struct, `SkinConfig`, `[defaults]` parsing, `skin(name:section:...)`)
- Modify: `macos/Sources/Features/Skins/SkinPresets.swift` (`make`, every preset entry, `SkinLibrary.entries`)
- Test: `macos/Tests/Claude/TraceConfigTests.swift`

**Interfaces:**
- Consumes: `Skin`, `RGB`, `SkinConfig`, `SkinPresets`, `SkinLibrary` (existing).
- Produces:
  - `enum BuiltinTrace: String, CaseIterable { case beam, comet, sunset, datastream, sonar, ember, bubbles, bolt, tide, blade, petal, arrow, tempest }`
  - `struct SkinTrace: Hashable { var style: BuiltinTrace?; var disabled: Bool; var color: RGB?; var color2: RGB?; var speed: Double; var length: Double }`
  - `Skin.trace: SkinTrace?` (new last stored property, default nil); `SkinConfig.trace: Bool` (default true)
  - `struct ResolvedTrace: Equatable { var style: BuiltinTrace; var color: RGB; var color2: RGB; var speed: Double; var length: Double; static func resolve(skin: Skin?, enabled: Bool) -> ResolvedTrace? }`
  - `struct TraceColors { let primary: RGB; let secondary: RGB; init(primary:secondary:); init(_ trace: ResolvedTrace); var head: Color; var tail: Color; func blend(_ t: Double) -> Color; func swapped() -> TraceColors; static func color(_ rgb: RGB) -> Color }`

- [ ] **Step 1: Write the failing tests** — `macos/Tests/Claude/TraceConfigTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Ghostty

struct TraceConfigTests {
    let home = "/Users/test"

    func parse(_ toml: String) throws -> SkinConfig {
        try SkinConfig.parse(toml, home: home, fileExists: { _ in true })
    }

    @Test func skinWithoutTraceKeysHasNoTrace() throws {
        let config = try parse("[skins.a]\nbackground = \"#101820\"\n")
        #expect(config.skins["a"]?.trace == nil)
        #expect(config.trace == true)
    }

    @Test func parsesAllTraceKeys() throws {
        let config = try parse("""
        [skins.a]
        background = "#101820"
        trace = "bolt"
        trace_color = "#FF00AA"
        trace_color2 = "#00ffcc"
        trace_speed = 1.5
        trace_length = 0.2
        """)
        #expect(config.skins["a"]?.trace == SkinTrace(
            style: .bolt, disabled: false, color: RGB(hex: "#ff00aa"), color2: RGB(hex: "#00ffcc"),
            speed: 1.5, length: 0.2))
    }

    @Test func traceNoneDisables() throws {
        let config = try parse("[skins.a]\nbackground = \"#101820\"\ntrace = \"none\"\n")
        #expect(config.skins["a"]?.trace?.disabled == true)
        #expect(ResolvedTrace.resolve(skin: config.skins["a"], enabled: true) == nil)
    }

    @Test func defaultsTraceFalseTurnsAllOff() throws {
        let config = try parse("[defaults]\ntrace = false\n")
        #expect(config.trace == false)
        #expect(ResolvedTrace.resolve(skin: nil, enabled: config.trace) == nil)
    }

    @Test func rejectsBadValues() {
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace = \"laser\"\n") }
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace = 3\n") }
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace_speed = 5\n") }
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace_speed = 0.1\n") }
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace_length = 0.6\n") }
        #expect(throws: SkinConfigError.self) { try parse("[skins.a]\nbackground = \"#101820\"\ntrace_color = \"red\"\n") }
        #expect(throws: SkinConfigError.self) { try parse("[defaults]\ntrace = \"yes\"\n") }
    }

    @Test func everyPresetHasItsOwnStyle() {
        let styles = SkinPresets.all.compactMap { $0.skin.trace?.style }
        #expect(styles.count == 12)
        #expect(Set(styles).count == 12)
        #expect(!styles.contains(.beam))
        let byName = Dictionary(uniqueKeysWithValues: SkinPresets.all.map { ($0.skin.name, $0.skin.trace?.style) })
        #expect(byName["thunderhead"] == .bolt)
        #expect(byName["stormsurge"] == .tempest)
        #expect(byName["neon-arcade"] == .comet)
    }

    @Test func shadowingPresetInheritsStyleButKeepsOwnTuning() throws {
        let config = try parse("[skins.thunderhead]\nbackground = \"#000000\"\ntrace_speed = 2\n")
        let skin = try #require(SkinLibrary.skins(config: config)["thunderhead"])
        #expect(skin.trace?.style == .bolt)
        #expect(skin.trace?.speed == 2)
    }

    @Test func shadowingPresetCanPickOrDisable() throws {
        let picked = try parse("[skins.thunderhead]\nbackground = \"#000000\"\ntrace = \"tide\"\n")
        #expect(SkinLibrary.skins(config: picked)["thunderhead"]?.trace?.style == .tide)
        let off = try parse("[skins.thunderhead]\nbackground = \"#000000\"\ntrace = \"none\"\n")
        #expect(ResolvedTrace.resolve(skin: SkinLibrary.skins(config: off)["thunderhead"], enabled: true) == nil)
    }

    @Test func resolveUsesSkinColorsAndDefaults() throws {
        let preset = try #require(SkinPresets.all.first { $0.skin.name == "thunderhead" }?.skin)
        let resolved = try #require(ResolvedTrace.resolve(skin: preset, enabled: true))
        #expect(resolved.style == .bolt)
        #expect(resolved.color == preset.accent)
        #expect(resolved.color2 == preset.accent2)
        #expect(resolved.speed == 1)
        #expect(resolved.length == 0.18)
    }

    @Test func resolveWithoutAccent2DerivesSecondary() throws {
        let skin = Skin(name: "x", background: RGB(hex: "#101820")!, foreground: nil,
                        accent: RGB(hex: "#46a2ff")!, texture: .none, textureOpacity: 0.16)
        let resolved = try #require(ResolvedTrace.resolve(skin: skin, enabled: true))
        #expect(resolved.style == .beam)
        #expect(resolved.color2 == RGB(hex: "#46a2ff")!.mixed(with: .white, amount: 0.4))
    }

    @Test func unskinnedPaneGetsHologramBeam() throws {
        let resolved = try #require(ResolvedTrace.resolve(skin: nil, enabled: true))
        #expect(resolved == ResolvedTrace(style: .beam, color: RGB(hex: "#ff7ad9")!,
                                          color2: RGB(hex: "#7af0ff")!, speed: 1, length: 0.18))
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh TraceConfigTests`
Expected: FAIL — `cannot find 'SkinTrace' in scope`.

- [ ] **Step 3: Implement the model** — `macos/Sources/Features/Skins/SkinTrace.swift`:

```swift
#if os(macOS)
import Foundation

/// Built-in Claude trace styles (spec §3.1). One per preset, plus `beam`.
enum BuiltinTrace: String, CaseIterable {
    case beam, comet, sunset, datastream, sonar, ember, bubbles
    case bolt, tide, blade, petal, arrow, tempest
}

/// A skin's trace settings, from a preset or skins.toml (spec §3.2).
struct SkinTrace: Hashable {
    /// nil = not chosen: a shadowed preset's style, otherwise `beam`.
    var style: BuiltinTrace? = nil
    /// `trace = "none"`.
    var disabled = false
    /// nil = the skin's accent.
    var color: RGB? = nil
    /// nil = the skin's accent2, else the primary lightened.
    var color2: RGB? = nil
    /// Multiplier, 0.25...4.
    var speed: Double = 1
    /// Tail length as a share of the perimeter, 0.05...0.5.
    var length: Double = 0.18

    static let speedRange: ClosedRange<Double> = 0.25...4
    static let lengthRange: ClosedRange<Double> = 0.05...0.5
}
#endif
```

In `SkinModel.swift`:
- In `struct Skin`, after `var selectionBackground: RGB? = nil` add:
  ```swift
      /// Claude trace settings; nil = defaults (see ResolvedTrace).
      var trace: SkinTrace? = nil
  ```
- In `struct SkinConfig`, after `var auto: Bool = true` add `var trace: Bool = true`.
- In `parse`, the `case (["defaults"], false):` branch: change `allowed: ["texture_opacity", "auto"]` to `allowed: ["texture_opacity", "auto", "trace"]` and after the `auto` block add:
  ```swift
                  if let value = section.values["trace"] {
                      guard case .bool(let flag) = value else { throw error(section, "trace must be true or false") }
                      config.trace = flag
                  }
  ```
- In `skin(name:section:defaultOpacity:home:fileExists:)`: extend the `checkKeys` allowed set with `"trace", "trace_color", "trace_color2", "trace_speed", "trace_length"`, and change the final `return Skin(...)` to pass `trace: try skinTrace(section)` as the last argument:
  ```swift
          return Skin(
              name: name, background: background, foreground: foreground,
              accent: accent ?? Skin.defaultAccent(for: background),
              texture: texture, textureOpacity: textureOpacity,
              trace: try skinTrace(section))
  ```
- Add next to `opacity(_:_:)`:
  ```swift
      private static func skinTrace(_ section: TOMLSection) throws -> SkinTrace? {
          let keys = ["trace", "trace_color", "trace_color2", "trace_speed", "trace_length"]
          guard keys.contains(where: { section.values[$0] != nil }) else { return nil }
          var trace = SkinTrace()
          if let value = section.values["trace"] {
              guard case .string(let name) = value else { throw error(section, "trace must be a string") }
              if name == "none" {
                  trace.disabled = true
              } else if let style = BuiltinTrace(rawValue: name) {
                  trace.style = style
              } else {
                  let names = BuiltinTrace.allCases.map(\.rawValue).joined(separator: ", ")
                  throw error(section, "unknown trace '\(name)' (use \(names) or none)")
              }
          }
          trace.color = try color(section, "trace_color")
          trace.color2 = try color(section, "trace_color2")
          if let value = section.values["trace_speed"] {
              trace.speed = try number(value, section, "trace_speed", SkinTrace.speedRange)
          }
          if let value = section.values["trace_length"] {
              trace.length = try number(value, section, "trace_length", SkinTrace.lengthRange)
          }
          return trace
      }

      private static func number(
          _ value: TOMLValue, _ section: TOMLSection, _ key: String, _ range: ClosedRange<Double>
      ) throws -> Double {
          guard case .number(let number) = value, range.contains(number) else {
              throw error(section, "\(key) must be a number from \(range.lowerBound) to \(range.upperBound)")
          }
          return number
      }
  ```

In `SkinPresets.swift`:
- Add a `trace: BuiltinTrace` parameter to `make(...)` right after `texture: BuiltinTexture,` and pass it into the `Skin(...)` initializer as the last argument: `trace: SkinTrace(style: trace)` (after `selectionBackground:`).
- Add `trace: .<style>,` right after `texture: .<texture>,` in each preset call: neon-arcade `.comet`, sunset-drive `.sunset`, mint-protocol `.datastream`, deep-dive `.sonar`, lava-rush `.ember`, bubble-pop `.bubbles`, thunderhead `.bolt`, undertow `.tide`, bloodrite `.blade`, heartsease `.petal`, silverbow `.arrow`, stormsurge `.tempest`.
- In `SkinLibrary.entries`, replace `if let own = config.skins[preset.skin.name] { return Entry(skin: own, rarity: .project) }` with:
  ```swift
              if var own = config.skins[preset.skin.name] {
                  // A config skin shadowing a preset keeps the preset's trace
                  // style unless it picks its own (or turns it off).
                  if own.trace?.style == nil, own.trace?.disabled != true {
                      var trace = own.trace ?? SkinTrace()
                      trace.style = preset.skin.trace?.style
                      own.trace = trace
                  }
                  return Entry(skin: own, rarity: .project)
              }
  ```

Resolver — `macos/Sources/Features/Claude/TraceResolver.swift`:

```swift
#if os(macOS)
import SwiftUI

/// A pane's trace with every default filled in, ready to draw.
struct ResolvedTrace: Equatable {
    var style: BuiltinTrace
    var color: RGB
    var color2: RGB
    var speed: Double
    var length: Double

    /// Lostty's hologram pink and cyan, for panes with no skin.
    static let unskinnedColor = RGB(hex: "#ff7ad9")!
    static let unskinnedColor2 = RGB(hex: "#7af0ff")!

    /// nil when traces are off (`[defaults] trace = false`, `trace = "none"`).
    static func resolve(skin: Skin?, enabled: Bool) -> ResolvedTrace? {
        guard enabled else { return nil }
        guard let skin else {
            return ResolvedTrace(style: .beam, color: unskinnedColor, color2: unskinnedColor2,
                                 speed: SkinTrace().speed, length: SkinTrace().length)
        }
        let trace = skin.trace ?? SkinTrace()
        guard !trace.disabled else { return nil }
        let color = trace.color ?? skin.accent
        return ResolvedTrace(
            style: trace.style ?? .beam,
            color: color,
            color2: trace.color2 ?? skin.accent2 ?? color.mixed(with: .white, amount: 0.4),
            speed: trace.speed,
            length: trace.length)
    }
}

/// A trace's two colors as SwiftUI colors.
struct TraceColors {
    let primary: RGB
    let secondary: RGB

    init(primary: RGB, secondary: RGB) {
        self.primary = primary
        self.secondary = secondary
    }

    init(_ trace: ResolvedTrace) {
        self.init(primary: trace.color, secondary: trace.color2)
    }

    var head: Color { Self.color(primary) }
    var tail: Color { Self.color(secondary) }

    /// 0 = secondary (tail end), 1 = primary (head).
    func blend(_ t: Double) -> Color { Self.color(secondary.mixed(with: primary, amount: min(1, max(0, t)))) }

    func swapped() -> TraceColors { TraceColors(primary: secondary, secondary: primary) }

    static func color(_ rgb: RGB) -> Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}
#endif
```

- [ ] **Step 4: Run to verify it passes**

Run: `macos/skins-test.sh TraceConfigTests`
Expected: PASS (11 tests). Then `macos/skins-test.sh SkinModelTests` and `macos/skins-test.sh SkinPresetsTests` — expected PASS (no regressions from the new `Skin` field).

- [ ] **Step 5: Lint and commit**

```bash
cd macos && swiftlint lint --strict --fix Sources/Features/Claude Sources/Features/Skins/SkinTrace.swift Tests/Claude && cd ..
git add macos/Sources/Features/Skins/SkinTrace.swift macos/Sources/Features/Claude/TraceResolver.swift macos/Tests/Claude/TraceConfigTests.swift macos/Sources/Features/Skins/SkinModel.swift macos/Sources/Features/Skins/SkinPresets.swift
git commit -m "skins: per-skin Claude trace settings, preset styles, skins.toml keys"
```

Note: `SkinModel.swift` and `SkinPresets.swift` have no uncommitted changes at plan time; if `git diff` shows unrelated hunks in them, stop and ask the human partner before staging.

---

### Task 8: Overlay engine with `beam`, `bolt`, finish pulse, reduced motion, debug preview

**Files:**
- Create: `macos/Sources/Features/Claude/Traces/TraceRenderer.swift`
- Create: `macos/Sources/Features/Claude/Traces/BeamTrace.swift`
- Create: `macos/Sources/Features/Claude/Traces/BoltTrace.swift`
- Create: `macos/Sources/Features/Claude/TraceOverlay.swift`
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView.swift` (inside `SurfaceWrapper.body`'s top `ZStack`, after the progress-report block ~line 108)
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (`applicationDidFinishLaunching` — debug menu item)
- Test: `macos/Tests/Claude/TraceDrawTests.swift`

**Interfaces:**
- Consumes: `EdgePath` (Task 6), `TraceFrame`, `TracePhase` (Task 4), `ClaudeRuntime` (Task 5), `ResolvedTrace`, `TraceColors`, `BuiltinTrace` (Task 7), `SkinsRuntime.shared.manager.effectiveSkin(_:)`, `.config.trace`.
- Produces:
  - `protocol TraceRenderer { func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) }`
  - `enum TraceRenderers { static func renderer(for style: BuiltinTrace) -> any TraceRenderer }`
  - `enum TraceDraw { static func tail(...); static func glow(...); static func dot(...); static func noise(_ i: Int, _ seed: Int) -> Double }` (signatures below)
  - `struct ClaudeTraceLayer: View { let surfaceID: UUID }`

- [ ] **Step 1: Write the failing test** for the one pure helper — `macos/Tests/Claude/TraceDrawTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Ghostty

struct TraceDrawTests {
    @Test func noiseIsDeterministicAndInRange() {
        for i in 0..<200 {
            let a = TraceDraw.noise(i, 7)
            #expect(a == TraceDraw.noise(i, 7))
            #expect(a >= 0 && a < 1)
        }
        #expect(TraceDraw.noise(1, 1) != TraceDraw.noise(2, 1))
        #expect(TraceDraw.noise(1, 1) != TraceDraw.noise(1, 2))
    }

    @Test func everyStyleHasARenderer() {
        for style in BuiltinTrace.allCases {
            _ = TraceRenderers.renderer(for: style)
        }
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh TraceDrawTests`
Expected: FAIL — `cannot find 'TraceDraw' in scope`.

- [ ] **Step 3: Implement the renderer base** — `macos/Sources/Features/Claude/Traces/TraceRenderer.swift`:

```swift
#if os(macOS)
import SwiftUI

/// Draws one trace style for one frame. Implementations are stateless:
/// everything comes from the frame, the time and the colors.
protocol TraceRenderer {
    /// `time` is seconds since the reference date, for flicker and particles.
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors)
}

enum TraceRenderers {
    static func renderer(for style: BuiltinTrace) -> any TraceRenderer {
        switch style {
        case .beam: BeamTrace()
        case .bolt: BoltTrace()
        // The other styles arrive in the next task; until then they draw a beam.
        default: BeamTrace()
        }
    }
}

/// Shared drawing helpers for trace styles.
enum TraceDraw {
    /// Strokes the tail behind the head as `pieces` short segments. `t` runs
    /// 0 at the tail end to 1 at the head; opacity ramps with it.
    static func tail(
        _ ctx: inout GraphicsContext, _ path: EdgePath, frame: TraceFrame, pieces: Int = 28,
        width: (Double) -> CGFloat, color: (Double) -> Color
    ) {
        let start = frame.head - frame.length
        for i in 0..<pieces {
            let t0 = Double(i) / Double(pieces)
            let t1 = Double(i + 1) / Double(pieces)
            let seg = path.segment(from: start + frame.length * t0, to: start + frame.length * t1)
            ctx.stroke(
                seg, with: .color(color(t1).opacity(frame.intensity * t1)),
                style: StrokeStyle(lineWidth: width(t1), lineCap: .round))
        }
    }

    /// A soft blurred disc, for heads and sparks.
    static func glow(_ ctx: inout GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        var layer = ctx
        layer.addFilter(.blur(radius: radius / 2))
        layer.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                   with: .color(color.opacity(opacity)))
    }

    /// A crisp filled circle.
    static func dot(_ ctx: inout GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                 with: .color(color.opacity(opacity)))
    }

    /// Deterministic pseudo-random value in 0..<1 for particle `i`, `seed`.
    static func noise(_ i: Int, _ seed: Int) -> Double {
        var x = UInt64(bitPattern: Int64(i &* 73_856_093 ^ seed &* 19_349_663))
        x ^= x >> 33
        x &*= 0xff51afd7ed558ccd
        x ^= x >> 33
        x &*= 0xc4ceb9fe1a85ec53
        x ^= x >> 33
        return Double(x >> 11) / Double(1 << 53)
    }
}
#endif
```

`macos/Sources/Features/Claude/Traces/BeamTrace.swift`:

```swift
#if os(macOS)
import SwiftUI

/// Default: a clean light ray with a soft fading tail.
struct BeamTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.tail(&ctx, path, frame: frame, width: { 1 + 1.5 * $0 }, color: { colors.blend($0) })
        let head = path.sample(at: frame.head).point
        TraceDraw.glow(&ctx, at: head, radius: 7, color: colors.head, opacity: 0.8 * frame.intensity)
        TraceDraw.dot(&ctx, at: head, radius: 1.8, color: .white, opacity: frame.intensity)
    }
}
#endif
```

`macos/Sources/Features/Claude/Traces/BoltTrace.swift`:

```swift
#if os(macOS)
import SwiftUI

/// thunderhead: forked gold lightning that re-strikes every 80ms.
struct BoltTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let strike = Int(time / 0.08)
        let pieces = 16
        let start = frame.head - frame.length
        var bolt = Path()
        var fork = Path()
        for i in 0...pieces {
            let t = Double(i) / Double(pieces)
            // Jagged inward offsets, calmer near the head so it stays on the edge.
            let jitter = i == pieces ? 0 : CGFloat(TraceDraw.noise(i, strike)) * 9 * CGFloat(1 - t * 0.7)
            let p = path.offsetPoint(at: start + frame.length * t, inward: jitter)
            if i == 0 { bolt.move(to: p) } else { bolt.addLine(to: p) }
            if i == pieces / 2 {
                fork.move(to: p)
                let branch = path.offsetPoint(at: start + frame.length * (t - 0.08), inward: jitter + 10 + CGFloat(TraceDraw.noise(i, strike + 1)) * 8)
                fork.addLine(to: branch)
            }
        }
        let flicker = frame.intensity * (0.7 + 0.3 * TraceDraw.noise(0, strike))
        var halo = ctx
        halo.addFilter(.blur(radius: 4))
        halo.stroke(bolt, with: .color(colors.tail.opacity(0.6 * flicker)), lineWidth: 5)
        ctx.stroke(bolt, with: .color(colors.head.opacity(flicker)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .bevel))
        ctx.stroke(fork, with: .color(colors.head.opacity(0.7 * flicker)), lineWidth: 1)
        let head = path.sample(at: frame.head).point
        TraceDraw.glow(&ctx, at: head, radius: 8, color: colors.head, opacity: flicker)
        TraceDraw.dot(&ctx, at: head, radius: 2, color: .white, opacity: flicker)
    }
}
#endif
```

`macos/Sources/Features/Claude/TraceOverlay.swift`:

```swift
#if os(macOS)
import AppKit
import SwiftUI

/// The Claude trace for one pane (spec §4). Lives in SurfaceWrapper's
/// ZStack; draws nothing (and is not in the tree) while the pane is idle.
struct ClaudeTraceLayer: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = ClaudeRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager

    var body: some View {
        let phase = runtime.phase(surfaceID)
        if !phase.isOff,
           let trace = ResolvedTrace.resolve(skin: skins.effectiveSkin(surfaceID), enabled: skins.config.trace) {
            TraceOverlay(phase: phase, trace: trace)
                .allowsHitTesting(false)
        }
    }
}

struct TraceOverlay: View {
    static let inset: CGFloat = 1.5

    let phase: TracePhase
    let trace: ResolvedTrace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowVisible = true

    var body: some View {
        TimelineView(.animation(paused: !windowVisible)) { timeline in
            Canvas { ctx, size in
                let path = EdgePath(size: size, inset: Self.inset)
                let lap = TraceFrame.lapSeconds(perimeter: path.perimeter, speed: trace.speed)
                guard let frame = TraceFrame.make(phase, now: timeline.date, lapSeconds: lap, length: trace.length) else { return }
                let colors = TraceColors(trace)
                let time = timeline.date.timeIntervalSinceReferenceDate
                ctx.blendMode = .plusLighter
                if reduceMotion {
                    Self.drawCalmGlow(in: &ctx, along: path, frame: frame, time: time, colors: colors)
                } else {
                    TraceRenderers.renderer(for: trace.style).draw(in: &ctx, along: path, frame: frame, time: time, colors: colors)
                }
                if frame.pulse > 0 {
                    Self.drawPulse(in: &ctx, along: path, frame: frame, colors: colors)
                }
            }
        }
        .background(OcclusionProbe(visible: $windowVisible))
    }

    /// Finish flash: the whole border glows once.
    static func drawPulse(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, colors: TraceColors) {
        let opacity = frame.pulse * frame.intensity
        var halo = ctx
        halo.addFilter(.blur(radius: 6))
        halo.stroke(path.outline, with: .color(colors.head.opacity(opacity)), lineWidth: 6)
        ctx.stroke(path.outline, with: .color(colors.blend(0.6).opacity(opacity)), lineWidth: 2)
    }

    /// Reduce Motion: no racing; the border breathes with a 2s period.
    static func drawCalmGlow(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let breath = 0.25 + 0.35 * (0.5 + 0.5 * sin(2 * .pi * time / 2))
        ctx.stroke(path.outline, with: .color(colors.head.opacity(breath * frame.intensity)), lineWidth: 2)
    }
}

/// Reports whether the hosting window is visible (not minimized or fully
/// covered), so the animation can pause.
private struct OcclusionProbe: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> Probe {
        Probe { isVisible in
            DispatchQueue.main.async { if visible != isVisible { visible = isVisible } }
        }
    }

    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        private let onChange: (Bool) -> Void
        private var token: NSObjectProtocol?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                guard let window = self?.window else { return }
                self?.onChange(window.occlusionState.contains(.visible))
            }
            onChange(window.occlusionState.contains(.visible))
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
#endif
```

Add the layer to `SurfaceView.swift` `SurfaceWrapper.body`, in the top-level `ZStack`, directly after the `// Progress report` `if let progressReport ... { ... }` block:

```swift
#if canImport(AppKit)
                // Lostty Claude trace: a light ray around the pane while Claude works.
                ClaudeTraceLayer(surfaceID: surfaceView.id)
#endif
```

Debug preview item — in `AppDelegate.swift`, at the end of `applicationDidFinishLaunching`, add:

```swift
        #if DEBUG
        // Lostty Claude trace: preview the focused pane's trace style.
        if let menu = menuOpenConfig?.menu, let index = menuOpenConfig.map({ menu.index(of: $0) }) {
            let item = NSMenuItem(title: "Preview Claude Trace", action: #selector(previewClaudeTrace(_:)), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: index + 1)
        }
        #endif
```

and add this method to `AppDelegate`:

```swift
    #if DEBUG
    @objc private func previewClaudeTrace(_ sender: Any?) {
        guard let controller = NSApp.keyWindow?.windowController as? BaseTerminalController,
              let surface = controller.focusedSurface else { return }
        ClaudeRuntime.shared.debugCycle(surface.id)
    }
    #endif
```

- [ ] **Step 4: Run the tests**

Run: `macos/skins-test.sh TraceDrawTests`
Expected: PASS (2 tests). Then `macos/skins-test.sh` — expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Look at it**

Build and launch the Debug app (Xcode or `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build`, then open `macos/build/Debug/Ghostty.app`). In a pane:
1. Choose **Ghostty → Preview Claude Trace**. Expect a pink/cyan beam racing clockwise from the top-left for ~4s, then the tail stretches around the edge, one border flash, fade-out. Clicking and selecting text during it still works.
2. `skins set thunderhead`, preview again: expect forked gold lightning.
3. Split the pane (Cmd-D), preview in one split: only that split traces, inset from the divider.
4. Turn on System Settings → Accessibility → Display → Reduce motion, preview: the border breathes instead of racing; the flash still plays.
5. Minimize the window mid-trace; restore after 5s: no stuck trace (it finished and settled while hidden).
Ask the human partner to confirm the look before committing; adjust widths/radii if they ask.

- [ ] **Step 6: Lint and commit**

```bash
cd macos && swiftlint lint --strict --fix Sources/Features/Claude Tests/Claude && cd ..
git add macos/Sources/Features/Claude/Traces macos/Sources/Features/Claude/TraceOverlay.swift macos/Tests/Claude/TraceDrawTests.swift "macos/Sources/Ghostty/Surface View/SurfaceView.swift" macos/Sources/App/macOS/AppDelegate.swift
git commit -m "claude: trace overlay engine with beam and bolt styles"
```

---

### Task 9: The other eleven trace styles

**Files:**
- Create (one each, in `macos/Sources/Features/Claude/Traces/`): `CometTrace.swift`, `SunsetTrace.swift`, `DatastreamTrace.swift`, `SonarTrace.swift`, `EmberTrace.swift`, `BubblesTrace.swift`, `TideTrace.swift`, `BladeTrace.swift`, `PetalTrace.swift`, `ArrowTrace.swift`, `TempestTrace.swift`
- Modify: `macos/Sources/Features/Claude/Traces/TraceRenderer.swift` (`TraceRenderers.renderer(for:)`)
- Test: `macos/Tests/Claude/TraceDrawTests.swift`

**Interfaces:**
- Consumes: `TraceRenderer`, `TraceDraw`, `EdgePath`, `TraceFrame`, `TraceColors` (Tasks 6–8).
- Produces: one `struct <Name>Trace: TraceRenderer` per style; `TraceRenderers.renderer(for:)` exhaustive with no `default`.

- [ ] **Step 1: Write the failing test** — add to `TraceDrawTests`:

```swift
    @Test func eachStyleHasItsOwnRenderer() {
        let types = BuiltinTrace.allCases.map { String(describing: type(of: TraceRenderers.renderer(for: $0))) }
        #expect(Set(types).count == BuiltinTrace.allCases.count)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh TraceDrawTests`
Expected: FAIL — `eachStyleHasItsOwnRenderer` (11 styles still map to `BeamTrace`).

- [ ] **Step 3: Implement the styles.** Each file starts with `#if os(macOS)` / `import SwiftUI` and ends with `#endif` (shown once here; include it in every file).

`CometTrace.swift`:
```swift
#if os(macOS)
import SwiftUI

/// neon-arcade: magenta head, wide cyan glowing tail.
struct CometTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var halo = ctx
        halo.addFilter(.blur(radius: 5))
        TraceDraw.tail(&halo, path, frame: frame, width: { 2 + 6 * $0 }, color: { colors.blend($0) })
        TraceDraw.tail(&ctx, path, frame: frame, width: { 0.5 + 2 * $0 }, color: { colors.blend($0) })
        let head = path.sample(at: frame.head).point
        TraceDraw.glow(&ctx, at: head, radius: 12, color: colors.head, opacity: frame.intensity)
        TraceDraw.dot(&ctx, at: head, radius: 2.5, color: .white, opacity: frame.intensity)
    }
}
#endif
```

`SunsetTrace.swift`:
```swift
/// sunset-drive: a long orange→pink sweep cut into scanline bands.
struct SunsetTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var long = frame
        long.length = min(1, frame.length * 1.6)
        TraceDraw.tail(&ctx, path, frame: long, pieces: 40, width: { _ in 3 }, color: { t in
            let band = Int(t * 40) % 2 == 0 ? 1.0 : 0.35
            return colors.blend(t).opacity(band)
        })
        let head = path.sample(at: frame.head).point
        TraceDraw.glow(&ctx, at: head, radius: 9, color: colors.head, opacity: frame.intensity)
    }
}
```

`DatastreamTrace.swift`:
```swift
/// mint-protocol: segmented green packets led by yellow bits.
struct DatastreamTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let packets = 9
        let spacing = frame.length / Double(packets)
        let dash = spacing * 0.55
        for k in 0..<packets {
            let end = frame.head - Double(k) * spacing
            let seg = path.segment(from: end - dash, to: end)
            let color = k < 2 ? colors.tail : colors.head
            let fade = 1 - Double(k) / Double(packets)
            ctx.stroke(seg, with: .color(color.opacity(frame.intensity * fade)), style: StrokeStyle(lineWidth: 2.5, lineCap: .butt))
        }
        TraceDraw.glow(&ctx, at: path.sample(at: frame.head).point, radius: 6, color: colors.tail, opacity: 0.8 * frame.intensity)
    }
}
```

`SonarTrace.swift`:
```swift
/// deep-dive: a cyan beam whose head sends out rings as it travels.
struct SonarTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.tail(&ctx, path, frame: frame, width: { 1 + 1.5 * $0 }, color: { colors.blend($0) })
        let head = path.sample(at: frame.head).point
        for ring in 0..<3 {
            let phase = (time * 1.2 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
            let radius = CGFloat(3 + 16 * phase)
            let circle = Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2))
            ctx.stroke(circle, with: .color(colors.tail.opacity((1 - phase) * 0.7 * frame.intensity)), lineWidth: 1.2)
        }
        TraceDraw.glow(&ctx, at: head, radius: 7, color: colors.head, opacity: frame.intensity)
    }
}
```

`EmberTrace.swift`:
```swift
/// lava-rush: a molten head shedding embers that drift into the pane.
struct EmberTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.tail(&ctx, path, frame: frame, width: { 1.5 + 2.5 * $0 }, color: { colors.blend($0 * 0.6 + 0.4) })
        for i in 0..<14 {
            let age = (time * 0.9 + TraceDraw.noise(i, 1)).truncatingRemainder(dividingBy: 1)
            let along = frame.head - frame.length * TraceDraw.noise(i, 2) * (0.3 + age)
            let p = path.offsetPoint(at: along, inward: CGFloat(2 + 14 * age))
            TraceDraw.dot(&ctx, at: p, radius: CGFloat(1.6 * (1 - age) + 0.4), color: colors.tail, opacity: (1 - age) * frame.intensity)
        }
        let head = path.sample(at: frame.head).point
        TraceDraw.glow(&ctx, at: head, radius: 10, color: colors.head, opacity: frame.intensity)
        TraceDraw.dot(&ctx, at: head, radius: 2.5, color: colors.tail, opacity: frame.intensity)
    }
}
```

`BubblesTrace.swift`:
```swift
/// bubble-pop: a chain of pink dots; the last ones pop into yellow sparkles.
struct BubblesTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let count = 10
        for k in 0..<count {
            let t = 1 - Double(k) / Double(count)
            let along = frame.head - frame.length * (1 - t)
            let wobble = CGFloat(sin(time * 6 + Double(k))) * 1.5
            let p = path.offsetPoint(at: along, inward: 3 + wobble)
            if k >= count - 3 {
                let pop = (time * 3 + Double(k)).truncatingRemainder(dividingBy: 1)
                let r = CGFloat(2 + 4 * pop)
                var spark = Path()
                spark.move(to: CGPoint(x: p.x - r, y: p.y))
                spark.addLine(to: CGPoint(x: p.x + r, y: p.y))
                spark.move(to: CGPoint(x: p.x, y: p.y - r))
                spark.addLine(to: CGPoint(x: p.x, y: p.y + r))
                ctx.stroke(spark, with: .color(colors.tail.opacity((1 - pop) * frame.intensity)), lineWidth: 1)
            } else {
                TraceDraw.dot(&ctx, at: p, radius: CGFloat(1.2 + 2.2 * t), color: colors.head, opacity: t * frame.intensity)
            }
        }
        TraceDraw.glow(&ctx, at: path.sample(at: frame.head).point, radius: 7, color: colors.head, opacity: frame.intensity)
    }
}
```

`TideTrace.swift`:
```swift
/// undertow: a sea-foam wave that swells and recedes as it moves.
struct TideTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let swell = 4 + 3 * sin(time * 1.5)
        let steps = 48
        var wave = Path()
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let along = frame.head - frame.length * (1 - t)
            let envelope = sin(.pi * t)
            let lift = swell * envelope * (0.5 + 0.5 * sin(along * path.perimeter / 18 - time * 4))
            let p = path.offsetPoint(at: along, inward: CGFloat(lift))
            if i == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
        }
        var foam = ctx
        foam.addFilter(.blur(radius: 3))
        foam.stroke(wave, with: .color(colors.tail.opacity(0.6 * frame.intensity)), lineWidth: 5)
        ctx.stroke(wave, with: .color(colors.head.opacity(frame.intensity)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }
}
```

`BladeTrace.swift`:
```swift
/// bloodrite: a short, sharp red slash throwing orange sparks.
struct BladeTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var short = frame
        short.length = frame.length * 0.6
        TraceDraw.tail(&ctx, path, frame: short, width: { 0.5 + 3.5 * $0 }, color: { _ in colors.head })
        TraceDraw.tail(&ctx, path, frame: short, width: { 0.8 * $0 }, color: { _ in .white })
        let head = path.sample(at: frame.head)
        let burst = Int(time / 0.1)
        for i in 0..<6 {
            let angle = (TraceDraw.noise(i, burst) - 0.5) * .pi * 0.9
            let length = CGFloat(4 + 8 * TraceDraw.noise(i, burst + 7))
            let dx = head.normal.dx * cos(angle) - head.normal.dy * sin(angle)
            let dy = head.normal.dx * sin(angle) + head.normal.dy * cos(angle)
            var spark = Path()
            spark.move(to: head.point)
            spark.addLine(to: CGPoint(x: head.point.x + dx * length, y: head.point.y + dy * length))
            ctx.stroke(spark, with: .color(colors.tail.opacity(frame.intensity)), lineWidth: 1)
        }
    }
}
```

`PetalTrace.swift`:
```swift
/// heartsease: a soft rose glow trailing drifting petals.
struct PetalTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var soft = ctx
        soft.addFilter(.blur(radius: 4))
        TraceDraw.tail(&soft, path, frame: frame, width: { 2 + 5 * $0 }, color: { colors.blend($0) })
        for i in 0..<8 {
            let drift = (time * 0.5 + TraceDraw.noise(i, 3)).truncatingRemainder(dividingBy: 1)
            let along = frame.head - frame.length * (0.15 + 0.85 * TraceDraw.noise(i, 4))
            let p = path.offsetPoint(at: along, inward: CGFloat(3 + 12 * drift))
            var petal = ctx
            petal.translateBy(x: p.x, y: p.y)
            petal.rotate(by: .radians(time * 2 + Double(i)))
            let color = i.isMultiple(of: 2) ? colors.head : colors.tail
            petal.fill(Path(ellipseIn: CGRect(x: -3, y: -1.5, width: 6, height: 3)),
                       with: .color(color.opacity((1 - drift) * frame.intensity)))
        }
        TraceDraw.glow(&ctx, at: path.sample(at: frame.head).point, radius: 9, color: colors.head, opacity: 0.9 * frame.intensity)
    }
}
```

`ArrowTrace.swift`:
```swift
/// silverbow: a thin silver-green streak with a twinkling starry tail.
struct ArrowTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.tail(&ctx, path, frame: frame, width: { _ in 1.2 }, color: { colors.blend($0) })
        for i in 0..<10 {
            let along = frame.head - frame.length * TraceDraw.noise(i, 5)
            let p = path.offsetPoint(at: along, inward: CGFloat(2 + 6 * TraceDraw.noise(i, 6)))
            let twinkle = 0.5 + 0.5 * sin(time * 6 + Double(i) * 1.7)
            let r = CGFloat(1 + 1.5 * twinkle)
            var star = Path()
            star.move(to: CGPoint(x: p.x - r, y: p.y))
            star.addLine(to: CGPoint(x: p.x + r, y: p.y))
            star.move(to: CGPoint(x: p.x, y: p.y - r))
            star.addLine(to: CGPoint(x: p.x, y: p.y + r))
            ctx.stroke(star, with: .color(colors.tail.opacity(twinkle * frame.intensity)), lineWidth: 0.8)
        }
        let head = path.sample(at: frame.head)
        var tip = Path()
        let back = CGPoint(x: head.point.x - head.tangent.dx * 6, y: head.point.y - head.tangent.dy * 6)
        tip.move(to: head.point)
        tip.addLine(to: CGPoint(x: back.x + head.normal.dx * 3, y: back.y + head.normal.dy * 3))
        tip.addLine(to: CGPoint(x: back.x - head.normal.dx * 3, y: back.y - head.normal.dy * 3))
        tip.closeSubpath()
        ctx.fill(tip, with: .color(colors.head.opacity(frame.intensity)))
        TraceDraw.glow(&ctx, at: head.point, radius: 6, color: colors.head, opacity: 0.8 * frame.intensity)
    }
}
```

`TempestTrace.swift`:
```swift
/// stormsurge: a gold bolt riding a teal wave.
struct TempestTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TideTrace().draw(in: &ctx, along: path, frame: frame, time: time, colors: colors.swapped())
        var bolt = frame
        bolt.length = frame.length * 0.6
        BoltTrace().draw(in: &ctx, along: path, frame: bolt, time: time, colors: colors)
    }
}
```

Replace `TraceRenderers.renderer(for:)` with the exhaustive switch:

```swift
    static func renderer(for style: BuiltinTrace) -> any TraceRenderer {
        switch style {
        case .beam: BeamTrace()
        case .comet: CometTrace()
        case .sunset: SunsetTrace()
        case .datastream: DatastreamTrace()
        case .sonar: SonarTrace()
        case .ember: EmberTrace()
        case .bubbles: BubblesTrace()
        case .bolt: BoltTrace()
        case .tide: TideTrace()
        case .blade: BladeTrace()
        case .petal: PetalTrace()
        case .arrow: ArrowTrace()
        case .tempest: TempestTrace()
        }
    }
```

- [ ] **Step 4: Run the tests**

Run: `macos/skins-test.sh TraceDrawTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Look at every style**

In the Debug app, for each preset: `skins set <preset>`, then **Preview Claude Trace**. Check each matches the spec §3.1 description, stays inside the pane, and the finish flash plays. Ask the human partner to review the set; tweak constants (widths, radii, counts, speeds) per their notes.

- [ ] **Step 6: Lint and commit**

```bash
cd macos && swiftlint lint --strict --fix Sources/Features/Claude Tests/Claude && cd ..
git add macos/Sources/Features/Claude/Traces macos/Tests/Claude/TraceDrawTests.swift
git commit -m "claude: the eleven preset trace styles"
```

---

### Task 10: Settings editing logic (`hooks.zig`)

**Files:**
- Create: `src/cli/claude/hooks.zig`

**Interfaces:**
- Produces (all take an arena allocator; values are `std.json.Value` parsed with `.parse_numbers = false`):
  - `pub const events: [4]Event` (`Event = struct { name: []const u8, state: []const u8 }`), `pub const timeout_seconds = 5`
  - `pub fn command(alloc, state: []const u8) Allocator.Error![]u8`
  - `pub fn isLosttyCommand(cmd: []const u8) bool`
  - `pub const Status = enum { installed, partial, not_installed, unreadable }` with `fn label(Status) []const u8` (`"not-installed"` for `.not_installed`)
  - `pub const EditError = error{Malformed} || Allocator.Error`
  - `pub fn status(alloc, root: Value) Allocator.Error!Status`
  - `pub fn install(alloc, root: *Value) EditError!bool` (true = changed)
  - `pub fn remove(root: *Value) EditError!bool`
  - `pub fn preview(alloc) Allocator.Error!Value` (the `hooks` object install adds)
  - `pub fn stringify(alloc, root: Value) Allocator.Error![]u8` (2-space indent, trailing newline)

- [ ] **Step 1: Write the failing tests** — create `src/cli/claude/hooks.zig` with the header, declarations used by tests left out, and these tests:

```zig
//! Pure logic for `+claude-hooks`: reading and editing the `hooks` table of
//! Claude Code's settings.json. Values come from std.json parsed with
//! `.parse_numbers = false`; the object map keeps insertion order and
//! numbers are re-emitted as written, so a user's file keeps its layout.
//! See docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md (§5).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = std.json.Value;

fn parseFixture(alloc: Allocator, text: []const u8) !Value {
    return std.json.parseFromSliceLeaky(Value, alloc, text, .{ .parse_numbers = false });
}

test "claude hooks: status of empty and missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(Status.not_installed, try status(a, try parseFixture(a, "{}")));
    try std.testing.expectEqual(Status.not_installed, try status(a, try parseFixture(a, "{\"hooks\":{}}")));
    try std.testing.expectEqual(Status.unreadable, try status(a, try parseFixture(a, "[]")));
}

test "claude hooks: install into empty object, then idempotent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a, "{}");
    try std.testing.expect(try install(a, &root));
    try std.testing.expectEqual(Status.installed, try status(a, root));
    const once = try stringify(a, root);
    try std.testing.expect(!(try install(a, &root)));
    try std.testing.expectEqualStrings(once, try stringify(a, root));
    // Survives a write/read round trip.
    try std.testing.expectEqual(Status.installed, try status(a, try parseFixture(a, once)));
    try std.testing.expect(std.mem.indexOf(u8, once, "+claude-state busy") != null);
    try std.testing.expect(std.mem.indexOf(u8, once, "\"timeout\": 5") != null);
}

test "claude hooks: install keeps user keys, order, numbers and hooks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a,
        \\{"model":"opus","cleanupPeriodDays":30.0,"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]},"zeta":true}
    );
    try std.testing.expect(try install(a, &root));
    const out = try stringify(a, root);
    // Key order of the top level is unchanged.
    const m = std.mem.indexOf(u8, out, "\"model\"").?;
    const c = std.mem.indexOf(u8, out, "\"cleanupPeriodDays\"").?;
    const h = std.mem.indexOf(u8, out, "\"hooks\"").?;
    const z = std.mem.indexOf(u8, out, "\"zeta\"").?;
    try std.testing.expect(m < c and c < h and h < z);
    // Numbers are written back exactly as they were.
    try std.testing.expect(std.mem.indexOf(u8, out, "30.0") != null);
    // The user's Stop hook is still there, before Lostty's.
    const user = std.mem.indexOf(u8, out, "say done").?;
    const ours = std.mem.indexOf(u8, out, "+claude-state idle").?;
    try std.testing.expect(user < ours);
}

test "claude hooks: outdated entries become partial and are replaced" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a,
        \\{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"[ -n \"$LOSTTY_SURFACE\" ] && old +claude-state idle"}]}]}}
    );
    try std.testing.expectEqual(Status.partial, try status(a, root));
    try std.testing.expect(try install(a, &root));
    try std.testing.expectEqual(Status.installed, try status(a, root));
    const out = try stringify(a, root);
    try std.testing.expect(std.mem.indexOf(u8, out, "old +claude-state") == null);
}

test "claude hooks: remove takes out only Lostty entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a,
        \\{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
    );
    _ = try install(a, &root);
    try std.testing.expect(try remove(&root));
    try std.testing.expectEqual(Status.not_installed, try status(a, root));
    const out = try stringify(a, root);
    try std.testing.expect(std.mem.indexOf(u8, out, "say done") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "UserPromptSubmit") == null);
    try std.testing.expect(!(try remove(&root)));
}

test "claude hooks: remove drops an emptied hooks table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a, "{\"model\":\"opus\"}");
    _ = try install(a, &root);
    _ = try remove(&root);
    try std.testing.expectEqualStrings("{\n  \"model\": \"opus\"\n}\n", try stringify(a, root));
}

test "claude hooks: remove keeps a user's hook in a shared group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ours = try command(a, "idle");
    const text = try std.fmt.allocPrint(a,
        \\{{"hooks":{{"Stop":[{{"matcher":"","hooks":[{{"type":"command","command":"say done"}},{{"type":"command","command":{f}}}]}}]}}}}
    , .{std.json.fmt(ours, .{})});
    var root = try parseFixture(a, text);
    try std.testing.expect(try remove(&root));
    const out = try stringify(a, root);
    try std.testing.expect(std.mem.indexOf(u8, out, "say done") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"matcher\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "+claude-state") == null);
}

test "claude hooks: malformed layouts are refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bad = [_][]const u8{
        "{\"hooks\":[]}",
        "{\"hooks\":null}",
        "{\"hooks\":{\"Stop\":{}}}",
        "{\"hooks\":{\"Stop\":[1]}}",
        "{\"hooks\":{\"Stop\":[{\"hooks\":\"x\"}]}}",
    };
    for (bad) |text| {
        var root = try parseFixture(a, text);
        try std.testing.expectEqual(Status.unreadable, try status(a, root));
        try std.testing.expectError(error.Malformed, install(a, &root));
        try std.testing.expectError(error.Malformed, remove(&root));
    }
    var arr = try parseFixture(a, "[]");
    try std.testing.expectError(error.Malformed, install(a, &arr));
}

test "claude hooks: command and detection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cmd = try command(a, "busy");
    try std.testing.expectEqualStrings(
        "[ -n \"$LOSTTY_SURFACE\" ] && [ -x \"$LOSTTY_BIN\" ] && \"$LOSTTY_BIN\" +claude-state busy; exit 0",
        cmd,
    );
    try std.testing.expect(isLosttyCommand(cmd));
    try std.testing.expect(!isLosttyCommand("say done"));
    try std.testing.expect(!isLosttyCommand("echo +claude-state"));
    try std.testing.expectEqualStrings("not-installed", Status.not_installed.label());
}

test "claude hooks: preview lists the four events" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try stringify(a, try preview(a));
    for (events) |e| try std.testing.expect(std.mem.indexOf(u8, out, e.name) != null);
}
```

- [ ] **Step 2: Wire the file into the test build and run to verify it fails**

Add to the bottom of `src/cli/claude_state.zig`'s `test {}` block: `_ = @import("claude/hooks.zig");`

Run: `zig build test -Dtest-filter="claude hooks"`
Expected: compile FAIL — `use of undeclared identifier 'Status'` (and the other functions).

- [ ] **Step 3: Implement** — add above the tests in `src/cli/claude/hooks.zig`:

```zig
pub const Event = struct { name: []const u8, state: []const u8 };

/// Claude Code hook events and the `+claude-state` each one sends.
pub const events = [_]Event{
    .{ .name = "UserPromptSubmit", .state = "busy" },
    .{ .name = "Stop", .state = "idle" },
    .{ .name = "Notification", .state = "idle" },
    .{ .name = "SessionEnd", .state = "exit" },
};

pub const timeout_seconds = 5;

pub const Status = enum {
    installed,
    partial,
    not_installed,
    unreadable,

    pub fn label(self: Status) []const u8 {
        return switch (self) {
            .installed => "installed",
            .partial => "partial",
            .not_installed => "not-installed",
            .unreadable => "unreadable",
        };
    }
};

pub const EditError = error{Malformed} || Allocator.Error;

/// The hook command for `state`. It is a no-op outside Lostty (no
/// LOSTTY_SURFACE) and when the binary is gone, and always exits 0.
pub fn command(alloc: Allocator, state: []const u8) Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        alloc,
        "[ -n \"$LOSTTY_SURFACE\" ] && [ -x \"$LOSTTY_BIN\" ] && \"$LOSTTY_BIN\" +claude-state {s}; exit 0",
        .{state},
    );
}

/// Lostty's entries, in any version, mention both of these.
pub fn isLosttyCommand(cmd: []const u8) bool {
    return std.mem.indexOf(u8, cmd, "+claude-state") != null and
        std.mem.indexOf(u8, cmd, "LOSTTY_SURFACE") != null;
}

fn hookCommand(hook: Value) ?[]const u8 {
    if (hook != .object) return null;
    const c = hook.object.get("command") orelse return null;
    return if (c == .string) c.string else null;
}

fn isTimeout(v: Value) bool {
    return switch (v) {
        .integer => |i| i == timeout_seconds,
        .number_string => |s| std.mem.eql(u8, s, "5"),
        else => false,
    };
}

/// Checks `hooks.<event>` has Claude Code's documented shape: an array of
/// objects, each with a `hooks` array.
fn checkEvent(event_value: Value) EditError!void {
    if (event_value != .array) return error.Malformed;
    for (event_value.array.items) |group| {
        if (group != .object) return error.Malformed;
        const list = group.object.get("hooks") orelse return error.Malformed;
        if (list != .array) return error.Malformed;
    }
}

fn expectedFor(alloc: Allocator, event_name: []const u8) Allocator.Error!?[]const u8 {
    for (events) |e| {
        if (std.mem.eql(u8, e.name, event_name)) return try command(alloc, e.state);
    }
    return null;
}

pub fn status(alloc: Allocator, root: Value) Allocator.Error!Status {
    if (root != .object) return .unreadable;
    const hooks = root.object.get("hooks") orelse return .not_installed;
    if (hooks != .object) return .unreadable;
    var current: usize = 0;
    var ours: usize = 0;
    var it = hooks.object.iterator();
    while (it.next()) |entry| {
        checkEvent(entry.value_ptr.*) catch return .unreadable;
        const expected = try expectedFor(alloc, entry.key_ptr.*);
        for (entry.value_ptr.array.items) |group| {
            for (group.object.get("hooks").?.array.items) |hook| {
                const cmd = hookCommand(hook) orelse continue;
                if (!isLosttyCommand(cmd)) continue;
                ours += 1;
                const exp = expected orelse continue;
                if (std.mem.eql(u8, cmd, exp) and isTimeout(hook.object.get("timeout") orelse .null)) current += 1;
            }
        }
    }
    if (ours == 0) return .not_installed;
    if (current == events.len and ours == events.len) return .installed;
    return .partial;
}

/// Removes Lostty's commands under every event. Drops matcher groups and
/// event arrays that this emptied (never ones that were already empty).
/// Validates everything before changing anything.
fn strip(hooks: *std.json.ObjectMap) EditError!bool {
    for (hooks.values()) |v| try checkEvent(v);
    var changed = false;
    var i: usize = 0;
    while (i < hooks.count()) {
        const event_value = &hooks.values()[i];
        var event_changed = false;
        var g: usize = 0;
        while (g < event_value.array.items.len) {
            const list = &event_value.array.items[g].object.getPtr("hooks").?.array;
            var removed = false;
            var h: usize = 0;
            while (h < list.items.len) {
                const cmd = hookCommand(list.items[h]);
                if (cmd != null and isLosttyCommand(cmd.?)) {
                    _ = list.orderedRemove(h);
                    removed = true;
                } else {
                    h += 1;
                }
            }
            if (removed) event_changed = true;
            if (removed and list.items.len == 0) {
                _ = event_value.array.orderedRemove(g);
            } else {
                g += 1;
            }
        }
        if (event_changed) changed = true;
        if (event_changed and event_value.array.items.len == 0) {
            _ = hooks.orderedRemove(hooks.keys()[i]);
        } else {
            i += 1;
        }
    }
    return changed;
}

fn group(alloc: Allocator, state: []const u8) Allocator.Error!Value {
    var hook = std.json.ObjectMap.init(alloc);
    try hook.put("type", .{ .string = "command" });
    try hook.put("command", .{ .string = try command(alloc, state) });
    try hook.put("timeout", .{ .integer = timeout_seconds });
    var list = std.json.Array.init(alloc);
    try list.append(.{ .object = hook });
    var g = std.json.ObjectMap.init(alloc);
    try g.put("hooks", .{ .array = list });
    return .{ .object = g };
}

/// Adds Lostty's hooks, replacing older Lostty entries. Returns false when
/// already installed in the current form (nothing to write).
pub fn install(alloc: Allocator, root: *Value) EditError!bool {
    if (root.* != .object) return error.Malformed;
    if (try status(alloc, root.*) == .installed) return false;
    const gop = try root.object.getOrPut("hooks");
    if (!gop.found_existing) gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(alloc) };
    if (gop.value_ptr.* != .object) return error.Malformed;
    const hooks = &gop.value_ptr.object;
    _ = try strip(hooks);
    for (events) |e| {
        const ev = try hooks.getOrPut(e.name);
        if (!ev.found_existing) ev.value_ptr.* = .{ .array = std.json.Array.init(alloc) };
        try ev.value_ptr.array.append(try group(alloc, e.state));
    }
    return true;
}

/// Removes Lostty's hooks, and `hooks` itself if that empties it.
pub fn remove(root: *Value) EditError!bool {
    if (root.* != .object) return error.Malformed;
    const hooks = root.object.getPtr("hooks") orelse return false;
    if (hooks.* != .object) return error.Malformed;
    const changed = try strip(&hooks.object);
    if (changed and hooks.object.count() == 0) _ = root.object.orderedRemove("hooks");
    return changed;
}

/// The `hooks` object install adds, for the app's "Show changes".
pub fn preview(alloc: Allocator) Allocator.Error!Value {
    var hooks = std.json.ObjectMap.init(alloc);
    for (events) |e| {
        var list = std.json.Array.init(alloc);
        try list.append(try group(alloc, e.state));
        try hooks.put(e.name, .{ .array = list });
    }
    var root = std.json.ObjectMap.init(alloc);
    try root.put("hooks", .{ .object = hooks });
    return .{ .object = root };
}

pub fn stringify(alloc: Allocator, root: Value) Allocator.Error![]u8 {
    const body = try std.json.Stringify.valueAlloc(alloc, root, .{ .whitespace = .indent_2 });
    return std.mem.concat(alloc, u8, &.{ body, "\n" });
}
```

Note on `strip`: the `hooks.keys()[i]` lookup happens before the remove; `orderedRemove` keeps the remaining order.

- [ ] **Step 4: Run to verify it passes**

Run: `zig build test -Dtest-filter="claude hooks"`
Expected: PASS (10 tests). If `std.json.fmt` is not available in this Zig version for the shared-group fixture, build the fixture string with `std.json.Stringify.valueAlloc(a, Value{ .string = ours }, .{})` instead and splice it in.

- [ ] **Step 5: Format and commit**

```bash
zig fmt src/cli/claude
git add src/cli/claude/hooks.zig src/cli/claude_state.zig
git commit -m "cli: Claude settings.json hook editing (install/remove/status)"
```

---

### Task 11: `+claude-hooks` action (file IO)

**Files:**
- Create: `src/cli/claude_hooks.zig`
- Modify: `src/cli/ghostty.zig` (same five spots as Task 2)

**Interfaces:**
- Consumes: everything from `claude/hooks.zig` (Task 10).
- Produces: `pub const Op = enum { install, remove, status, preview }`; `pub const Outcome = union(enum) { status: hooks.Status, changed: bool, failed: []const u8, preview: []const u8 }`; `pub fn applyAt(alloc, path: []const u8, op: Op) !Outcome`. CLI: `ghostty +claude-hooks install|remove|status|preview` — stdout: `installed`/`already installed`/`removed`/`nothing to remove`/a status label/preview JSON; failures on stderr with exit 1; bad usage exit 2.

- [ ] **Step 1: Write the failing tests** — create `src/cli/claude_hooks.zig` with `Options`, the `Op`/`Outcome` types, and these tests (no `applyAt` yet):

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const hooks = @import("claude/hooks.zig");

pub const Options = struct {
    pub fn deinit(self: Options) void {
        _ = self;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

pub const Op = enum { install, remove, status, preview };

pub const Outcome = union(enum) {
    status: hooks.Status,
    changed: bool,
    failed: []const u8,
    preview: []const u8,
};

fn tmpPath(alloc: Allocator, dir: std.testing.TmpDir, name: []const u8) ![]u8 {
    const base = try dir.dir.realpathAlloc(alloc, ".");
    return std.fs.path.join(alloc, &.{ base, name });
}

fn readAll(alloc: Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(alloc, path, 1 << 20);
}

test "claude hooks file: install creates a missing file and its directory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmpPath(a, tmp, ".claude/settings.json");
    try std.testing.expectEqual(Outcome{ .status = .not_installed }, try applyAt(a, path, .status));
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, path, .install));
    try std.testing.expectEqual(Outcome{ .status = .installed }, try applyAt(a, path, .status));
    // No backup when there was no file.
    try std.testing.expectError(error.FileNotFound, readAll(a, try tmpPath(a, tmp, ".claude/settings.json.lostty-backup")));
}

test "claude hooks file: install backs up, second install is a no-op" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "settings.json", .data = "{\"model\":\"opus\"}\n" });
    const path = try tmpPath(a, tmp, "settings.json");
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, path, .install));
    try std.testing.expectEqualStrings("{\"model\":\"opus\"}\n", try readAll(a, try tmpPath(a, tmp, "settings.json.lostty-backup")));
    const after = try readAll(a, path);
    try std.testing.expectEqual(Outcome{ .changed = false }, try applyAt(a, path, .install));
    try std.testing.expectEqualStrings(after, try readAll(a, path));
    // No temp file is left behind.
    try std.testing.expectError(error.FileNotFound, readAll(a, try tmpPath(a, tmp, "settings.json.lostty-tmp")));
}

test "claude hooks file: invalid JSON is left untouched" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "settings.json", .data = "{ \"model\": // comment\n}" });
    const path = try tmpPath(a, tmp, "settings.json");
    try std.testing.expectEqual(Outcome{ .status = .unreadable }, try applyAt(a, path, .status));
    const result = try applyAt(a, path, .install);
    try std.testing.expect(result == .failed);
    try std.testing.expectEqualStrings("{ \"model\": // comment\n}", try readAll(a, path));
}

test "claude hooks file: remove on a missing file changes nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmpPath(a, tmp, "settings.json");
    try std.testing.expectEqual(Outcome{ .changed = false }, try applyAt(a, path, .remove));
    try std.testing.expectError(error.FileNotFound, readAll(a, path));
}

test "claude hooks: install follows a symlink" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("dotfiles");
    try tmp.dir.writeFile(.{ .sub_path = "dotfiles/settings.json", .data = "{}" });
    try tmp.dir.symLink("dotfiles/settings.json", "settings.json", .{});
    const link = try tmpPath(a, tmp, "settings.json");
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, link, .install));
    // The link is still a link, and the target got the hooks.
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    _ = try tmp.dir.readLink("settings.json", &buf);
    const target = try readAll(a, try tmpPath(a, tmp, "dotfiles/settings.json"));
    try std.testing.expect(std.mem.indexOf(u8, target, "+claude-state busy") != null);
}

test "claude hooks file: preview needs no file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const result = try applyAt(a, "/nonexistent/settings.json", .preview);
    try std.testing.expect(std.mem.indexOf(u8, result.preview, "SessionEnd") != null);
}
```

Register in `src/cli/ghostty.zig`: `const claude_hooks = @import("claude_hooks.zig");`; enum case after `@"claude-state",`:
```zig
    // Lostty: install or remove the Claude Code hooks that drive the trace.
    @"claude-hooks",
```
`run` switch: `.@"claude-hooks" => try claude_hooks.run(alloc),`; `options` switch: `.@"claude-hooks" => claude_hooks.Options,`; test block: `_ = claude_hooks;`.

- [ ] **Step 2: Run to verify it fails**

Run: `zig build test -Dtest-filter="claude hooks"`
Expected: compile FAIL — `use of undeclared identifier 'applyAt'` (and `run`).

- [ ] **Step 3: Implement** — add to `src/cli/claude_hooks.zig` between the types and the tests:

```zig
const usage =
    \\usage: +claude-hooks install   add Lostty's hooks to ~/.claude/settings.json
    \\       +claude-hooks remove    take them out again
    \\       +claude-hooks status    installed | partial | not-installed | unreadable
    \\       +claude-hooks preview   print the JSON that install adds
    \\
;

/// The `claude-hooks` command installs, removes or reports Lostty's Claude
/// Code hooks in `~/.claude/settings.json`: `+claude-hooks install`,
/// `+claude-hooks remove`, `+claude-hooks status` or `+claude-hooks preview`.
/// It backs the file up to `settings.json.lostty-backup` before changing it,
/// never touches a file it cannot parse, and only edits Lostty's own entries.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    const argv = try std.process.argsAlloc(alloc);
    var op: ?Op = null;
    for (argv, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "+claude-hooks") and i + 1 < argv.len) {
            op = std.meta.stringToEnum(Op, argv[i + 1]);
            break;
        }
    }
    const chosen = op orelse {
        try stderr.writeAll(usage);
        return 2;
    };

    const home = std.posix.getenv("HOME") orelse {
        try stderr.writeAll("claude-hooks: HOME is not set\n");
        return 1;
    };
    const path = try std.fs.path.join(alloc, &.{ home, ".claude", "settings.json" });

    switch (try applyAt(alloc, path, chosen)) {
        .status => |s| try stdout.print("{s}\n", .{s.label()}),
        .preview => |json| try stdout.writeAll(json),
        .changed => |changed| try stdout.writeAll(switch (chosen) {
            .install => if (changed) "installed\n" else "already installed\n",
            else => if (changed) "removed\n" else "nothing to remove\n",
        }),
        .failed => |msg| {
            try stderr.print("claude-hooks: {s}\n", .{msg});
            return 1;
        },
    }
    return 0;
}

/// Runs `op` on the settings file at `path` (absolute).
pub fn applyAt(alloc: Allocator, path: []const u8, op: Op) !Outcome {
    if (op == .preview) return .{ .preview = try hooks.stringify(alloc, try hooks.preview(alloc)) };

    // Follow a symlinked settings.json (dotfile managers) so the rename
    // replaces the real file and the link stays a link.
    const real = std.fs.realpathAlloc(alloc, path) catch |err| switch (err) {
        error.FileNotFound => try alloc.dupe(u8, path),
        else => return .{ .failed = "cannot resolve the settings file path" },
    };
    const bytes: ?[]u8 = std.fs.cwd().readFileAlloc(alloc, real, 16 << 20) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return .{ .failed = "cannot read the settings file" },
    };

    var root: std.json.Value = if (bytes) |b|
        std.json.parseFromSliceLeaky(std.json.Value, alloc, b, .{ .parse_numbers = false }) catch {
            if (op == .status) return .{ .status = .unreadable };
            return .{ .failed = "settings file is not valid JSON; left untouched" };
        }
    else
        .{ .object = std.json.ObjectMap.init(alloc) };

    if (op == .status) {
        return .{ .status = if (bytes == null) .not_installed else try hooks.status(alloc, root) };
    }

    const changed = (switch (op) {
        .install => hooks.install(alloc, &root),
        .remove => hooks.remove(&root),
        .status, .preview => unreachable,
    }) catch |err| switch (err) {
        error.Malformed => return .{ .failed = "settings file has an unexpected hooks layout; left untouched" },
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (!changed) return .{ .changed = false };

    if (std.fs.path.dirname(real)) |dir| try std.fs.cwd().makePath(dir);
    if (bytes) |b| {
        const backup = try std.fmt.allocPrint(alloc, "{s}.lostty-backup", .{real});
        try std.fs.cwd().writeFile(.{ .sub_path = backup, .data = b });
    }
    const tmp = try std.fmt.allocPrint(alloc, "{s}.lostty-tmp", .{real});
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = try hooks.stringify(alloc, root) });
    std.fs.renameAbsolute(tmp, real) catch |err| {
        std.fs.cwd().deleteFile(tmp) catch {};
        return err;
    };
    return .{ .changed = true };
}
```

Remove the `_ = @import("claude/hooks.zig");` line added to `claude_state.zig` in Task 10 and instead add at the bottom of `claude_hooks.zig`:

```zig
test {
    _ = @import("claude/hooks.zig");
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `zig build test -Dtest-filter="claude hooks"`
Expected: PASS (all `claude hooks` and `claude hooks file` tests).

- [ ] **Step 5: Smoke-test against a copy of a real file**

```bash
zig build -Demit-macos-app=false
mkdir -p /tmp/lostty-hooks-home/.claude && cp ~/.claude/settings.json /tmp/lostty-hooks-home/.claude/ 2>/dev/null || true
HOME=/tmp/lostty-hooks-home ./zig-out/bin/ghostty +claude-hooks status
HOME=/tmp/lostty-hooks-home ./zig-out/bin/ghostty +claude-hooks install
diff /tmp/lostty-hooks-home/.claude/settings.json.lostty-backup /tmp/lostty-hooks-home/.claude/settings.json
HOME=/tmp/lostty-hooks-home ./zig-out/bin/ghostty +claude-hooks remove
HOME=/tmp/lostty-hooks-home ./zig-out/bin/ghostty +claude-hooks status
rm -rf /tmp/lostty-hooks-home
```
Expected: `not-installed` → `installed` → a diff showing only added hook entries (plus whitespace normalization if the original was not 2-space indented) → `removed` → `not-installed`. Report the diff to the human partner if it shows any change beyond added entries and indentation.

- [ ] **Step 6: Format and commit**

```bash
zig fmt src/cli/claude_hooks.zig src/cli/claude_state.zig src/cli/ghostty.zig
git add src/cli/claude_hooks.zig src/cli/claude_state.zig src/cli/ghostty.zig
git commit -m "cli: add +claude-hooks to install/remove Lostty's Claude hooks"
```

---

### Task 12: First-launch prompt and Claude Integration menu

**Files:**
- Create: `macos/Sources/Features/Claude/ClaudeHooks.swift`
- Create: `macos/Sources/Features/Claude/ClaudeHooksUI.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (`applicationDidFinishLaunching`)
- Test: `macos/Tests/Claude/ClaudeHooksTests.swift`

**Interfaces:**
- Consumes: `+claude-hooks` CLI (Task 11).
- Produces: `enum ClaudeHooksStatus: String { case installed, partial, notInstalled = "not-installed", unreadable }`; `struct ClaudeHooksCLI { var binary: URL?; func run(_ op: String) -> ClaudeHooksCLI.Result; func status() -> ClaudeHooksStatus? }`; `enum ClaudeHooksPrompt { static let hookVersion = 1; static let defaultsKey = "LosttyClaudeHooksPromptedVersion"; static func shouldPrompt(claudeDirExists: Bool, status: ClaudeHooksStatus?, promptedVersion: Int) -> Bool }`; `@MainActor enum ClaudeHooksUI { static func promptAtLaunchIfNeeded(); static func installMenuItem(after: NSMenuItem?); }`.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/Claude/ClaudeHooksTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct ClaudeHooksTests {
    @Test func promptsOnlyForClaudeUsersWithMissingOrOldHooks() {
        #expect(ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .notInstalled, promptedVersion: 0))
        #expect(ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .partial, promptedVersion: 0))
        #expect(!ClaudeHooksPrompt.shouldPrompt(claudeDirExists: false, status: .notInstalled, promptedVersion: 0))
        #expect(!ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .installed, promptedVersion: 0))
        #expect(!ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .unreadable, promptedVersion: 0))
        #expect(!ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: nil, promptedVersion: 0))
    }

    @Test func answeredPromptIsNotRepeatedForTheSameVersion() {
        let v = ClaudeHooksPrompt.hookVersion
        #expect(!ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .notInstalled, promptedVersion: v))
        #expect(ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .partial, promptedVersion: v - 1))
    }

    @Test func parsesStatusOutput() {
        #expect(ClaudeHooksStatus(cliOutput: "installed\n") == .installed)
        #expect(ClaudeHooksStatus(cliOutput: "not-installed\n") == .notInstalled)
        #expect(ClaudeHooksStatus(cliOutput: "partial") == .partial)
        #expect(ClaudeHooksStatus(cliOutput: "unreadable\n") == .unreadable)
        #expect(ClaudeHooksStatus(cliOutput: "") == nil)
    }

    @Test func runReportsAMissingBinary() {
        let cli = ClaudeHooksCLI(binary: URL(fileURLWithPath: "/nonexistent/ghostty"))
        let result = cli.run("status")
        #expect(result.exitCode != 0)
        #expect(cli.status() == nil)
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh ClaudeHooksTests`
Expected: FAIL — `cannot find 'ClaudeHooksPrompt' in scope`.

- [ ] **Step 3: Implement the logic** — `macos/Sources/Features/Claude/ClaudeHooks.swift`:

```swift
#if os(macOS)
import Foundation

/// `+claude-hooks status` output.
enum ClaudeHooksStatus: String {
    case installed, partial, notInstalled = "not-installed", unreadable

    init?(cliOutput: String) {
        self.init(rawValue: cliOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Runs the bundled binary's `+claude-hooks` (the editing logic lives in
/// Zig: src/cli/claude_hooks.zig).
struct ClaudeHooksCLI {
    struct Result {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    var binary: URL? = Bundle.main.executableURL

    func run(_ op: String) -> Result {
        guard let binary else { return Result(exitCode: -1, stdout: "", stderr: "Lostty binary not found") }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["+claude-hooks", op]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return Result(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    func status() -> ClaudeHooksStatus? {
        let result = run("status")
        guard result.exitCode == 0 else { return nil }
        return ClaudeHooksStatus(cliOutput: result.stdout)
    }
}

enum ClaudeHooksPrompt {
    /// Bump when the hook command format changes, to offer an update once.
    static let hookVersion = 1
    static let defaultsKey = "LosttyClaudeHooksPromptedVersion"

    /// Ask once per hook version, only people who use Claude (~/.claude
    /// exists) and only when install would help. An unreadable settings
    /// file is reported from the menu, never at launch.
    static func shouldPrompt(claudeDirExists: Bool, status: ClaudeHooksStatus?, promptedVersion: Int) -> Bool {
        guard claudeDirExists, promptedVersion < hookVersion else { return false }
        return status == .notInstalled || status == .partial
    }
}
#endif
```

- [ ] **Step 4: Run to verify it passes**

Run: `macos/skins-test.sh ClaudeHooksTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Implement the UI** — `macos/Sources/Features/Claude/ClaudeHooksUI.swift`:

```swift
#if os(macOS)
import AppKit

/// The first-launch offer and the Claude Integration menu item (spec §5.2).
@MainActor
enum ClaudeHooksUI {
    static func promptAtLaunchIfNeeded() {
        let claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        let defaults = UserDefaults.ghostty
        let prompted = defaults.integer(forKey: ClaudeHooksPrompt.defaultsKey)
        let claudeDirExists = FileManager.default.fileExists(atPath: claudeDir.path)
        guard claudeDirExists, prompted < ClaudeHooksPrompt.hookVersion else { return }

        DispatchQueue.global(qos: .utility).async {
            let status = ClaudeHooksCLI().status()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard ClaudeHooksPrompt.shouldPrompt(
                        claudeDirExists: claudeDirExists, status: status, promptedVersion: prompted) else { return }
                    defaults.set(ClaudeHooksPrompt.hookVersion, forKey: ClaudeHooksPrompt.defaultsKey)
                    offerInstall(update: status == .partial)
                }
            }
        }
    }

    static func installMenuItem(after anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Claude Integration…", action: #selector(MenuTarget.open(_:)), keyEquivalent: "")
        item.target = MenuTarget.shared
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
    }

    /// Install / Not now / Show changes.
    static func offerInstall(update: Bool) {
        let alert = NSAlert()
        alert.messageText = update ? "Update Lostty's Claude hooks?" : "Show a trace while Claude is working?"
        alert.informativeText = update
            ? "Your Claude hooks are from an older Lostty. Lostty will update its 4 hooks in ~/.claude/settings.json (a backup is saved first)."
            : "Lostty will add 4 hooks to ~/.claude/settings.json (a backup is saved first). They do nothing outside Lostty. You can remove them from Lostty → Claude Integration…"
        alert.addButton(withTitle: update ? "Update" : "Install")
        alert.addButton(withTitle: "Not now")
        alert.addButton(withTitle: "Show changes")
        switch alert.runModal() {
        case .alertFirstButtonReturn: run("install")
        case .alertThirdButtonReturn: showChanges(update: update)
        default: break
        }
    }

    static func showChanges(update: Bool) {
        let alert = NSAlert()
        alert.messageText = "Lostty adds these hooks"
        alert.informativeText = "Added to the \"hooks\" section of ~/.claude/settings.json. Your other settings and hooks are kept."
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 260)
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.string = ClaudeHooksCLI().run("preview").stdout
        }
        alert.accessoryView = scroll
        alert.addButton(withTitle: update ? "Update" : "Install")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { run("install") }
    }

    static func showManager() {
        let status = ClaudeHooksCLI().status()
        let alert = NSAlert()
        alert.messageText = "Claude Integration"
        switch status {
        case .installed?:
            alert.informativeText = "Lostty's Claude hooks are installed. The trace shows while Claude works."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Close")
            if alert.runModal() == .alertFirstButtonReturn { run("remove") }
        case .partial?:
            alert.informativeText = "Lostty's Claude hooks are out of date or incomplete."
            alert.addButton(withTitle: "Update")
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Close")
            switch alert.runModal() {
            case .alertFirstButtonReturn: run("install")
            case .alertSecondButtonReturn: run("remove")
            default: break
            }
        case .notInstalled?:
            offerInstall(update: false)
        case .unreadable?:
            alert.informativeText = "~/.claude/settings.json could not be read as JSON, so Lostty will not change it. Fix the file, then try again."
            alert.addButton(withTitle: "Close")
            alert.runModal()
        case nil:
            alert.informativeText = "Could not check the Claude hooks (the Lostty command-line tool did not run)."
            alert.addButton(withTitle: "Close")
            alert.runModal()
        }
    }

    private static func run(_ op: String) {
        let result = ClaudeHooksCLI().run(op)
        guard result.exitCode != 0 else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Lostty could not \(op) the Claude hooks"
        alert.informativeText = result.stderr.isEmpty ? "Unknown error." : result.stderr
        alert.runModal()
    }

    @MainActor
    final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        @objc func open(_ sender: Any?) { ClaudeHooksUI.showManager() }
    }
}
#endif
```

In `AppDelegate.applicationDidFinishLaunching`, at the end (before the `#if DEBUG` preview item from Task 8, so the order is Settings… → Claude Integration… → Preview Claude Trace), add:

```swift
        // Lostty Claude trace: menu item and the one-time hook offer.
        ClaudeHooksUI.installMenuItem(after: menuOpenConfig)
        ClaudeHooksUI.promptAtLaunchIfNeeded()
```

and change the debug item's insertion index in Task 8's block from `index + 1` to `index + 2`.

- [ ] **Step 6: Manual check against a throwaway home**

Run the Debug app with a temporary HOME so a real `~/.claude` is not touched:
```bash
mkdir -p /tmp/lostty-ui-home/.claude && echo '{"model":"opus"}' > /tmp/lostty-ui-home/.claude/settings.json
defaults delete com.mitchellh.ghostty.debug LosttyClaudeHooksPromptedVersion 2>/dev/null || true
HOME=/tmp/lostty-ui-home open -n macos/build/Debug/Ghostty.app --env HOME=/tmp/lostty-ui-home
```
(If the bundle id differs, find it with `defaults read macos/build/Debug/Ghostty.app/Contents/Info.plist CFBundleIdentifier` and use that domain; `UserDefaults.ghostty` may use a suite name — check `UserDefaults.ghostty`'s definition and delete the key in that domain.)
Expected: the offer appears once. **Show changes** shows 4 hook entries. **Install** writes `/tmp/lostty-ui-home/.claude/settings.json` and `.lostty-backup`. Relaunch: no prompt. **Ghostty → Claude Integration…** says installed and offers Remove. Then `rm -rf /tmp/lostty-ui-home`.

- [ ] **Step 7: Lint and commit**

```bash
cd macos && swiftlint lint --strict --fix Sources/Features/Claude Tests/Claude && cd ..
git add macos/Sources/Features/Claude/ClaudeHooks.swift macos/Sources/Features/Claude/ClaudeHooksUI.swift macos/Tests/Claude/ClaudeHooksTests.swift macos/Sources/App/macOS/AppDelegate.swift
git commit -m "claude: first-launch hook offer and Claude Integration menu"
```

---

### Task 13: Docs and end-to-end check

**Files:**
- Modify: `SKINS.md` (has uncommitted user edits — add a new section at the end only; stage with `git add -p SKINS.md` and select only the new section's hunk)
- Modify: `docs/skins/skins.example.toml`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Add the docs.** Append to `SKINS.md` (before `## Updating from upstream Ghostty` if present; otherwise at the end):

```markdown
## Claude Trace

While Claude Code is working in a pane, a light ray races around that
pane's edge. When Claude finishes, the ray wraps the whole edge, flashes
once, and fades. Each preset has its own trace; panes without a skin get a
pink-and-cyan beam.

On first launch Lostty offers to add four hooks to
`~/.claude/settings.json` (it saves `settings.json.lostty-backup` first).
The hooks do nothing outside Lostty. Manage them from
**Lostty → Claude Integration…**, or run `ghostty +claude-hooks install`,
`remove`, `status` or `preview`.

Custom skins pick a trace in `skins.toml`:

    [skins.my-skin]
    background = "#101820"
    trace = "bolt"            # beam comet sunset datastream sonar ember bubbles
                              # bolt tide blade petal arrow tempest, or none
    trace_color = "#ff00aa"   # default: the skin's accent
    trace_color2 = "#00ffcc"  # default: accent2, or a lighter accent
    trace_speed = 1.5         # 0.25–4
    trace_length = 0.2        # 0.05–0.5

A skin with the same name as a preset keeps the preset's trace unless it
sets `trace`. `[defaults] trace = false` turns traces off. With Reduce
Motion on, the border glows gently instead of racing.
```

Append to `docs/skins/skins.example.toml`:

```toml

# Claude trace (shown while Claude Code works in a pane). Optional per skin:
# trace = "bolt"           # or beam, comet, sunset, datastream, sonar, ember,
#                          # bubbles, tide, blade, petal, arrow, tempest, none
# trace_color = "#ffd84a"
# trace_color2 = "#7fc8ff"
# trace_speed = 1.0        # 0.25–4
# trace_length = 0.18      # 0.05–0.5
# Turn traces off everywhere with `trace = false` under [defaults].
```

- [ ] **Step 2: End-to-end check with real Claude**

Build and install (`macos/install-skins.sh`), launch Lostty, accept the hook offer (or run `ghostty +claude-hooks install`), open a new pane, and run `claude`:
1. Send a prompt: the trace starts within a second.
2. Claude finishes: wrap, flash, fade.
3. A prompt needing permission: the trace stops when the prompt appears (v1 behavior).
4. Two splits with Claude in each, one busy: only that split traces.
5. Inside `tmux` with `set -g allow-passthrough on`: the trace still works.
6. `/exit` mid-answer: the trace fades without a flash.
7. Run `claude` in another terminal app: no hook errors shown.
Report each result to the human partner.

- [ ] **Step 3: Run all tests**

Run: `zig build test -Dtest-filter="claude"` — expected PASS.
Run: `macos/skins-test.sh` — expected `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -p SKINS.md   # select only the "Claude Trace" section hunk
git add docs/skins/skins.example.toml
git commit -m "docs: Claude trace and hooks"
```
