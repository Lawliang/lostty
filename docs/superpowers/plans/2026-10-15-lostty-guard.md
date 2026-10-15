# Lostty Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Claude Code and Codex pane in Lostty stops before a critical action (an unrecoverable delete, throwing work away, leaving the Mac, merging into a protected branch, touching the guardrails, writing outside the project) and only a person, in Lostty's own UI on the Mac, can let that one action through.

**Architecture:** A new `lostty +guard` command runs as a `PreToolUse` hook for both agents. It parses the tool call (a small shell lexer for `Bash`, paths for file tools, the patch for `apply_patch`), checks git state where "can git get it back?" decides, and lets harmless calls through without contacting anything. For a critical call it asks the app over a Unix socket that can only *ask*; the app answers "allow" (consuming a one-time approval you gave) or "deny, request #N" and shows the request. You approve or deny in a detail window opened from a notification, the Branches panel or the pane's badge; Lostty then types the outcome into the agent's pane on your click.

**Tech Stack:** Zig 0.15 (`src/cli`, the `lostty` CLI inside GhosttyKit), Swift 6 / SwiftUI / AppKit (`macos/Sources`), Swift Testing, BSD sockets, UserNotifications.

**Spec:** `docs/superpowers/specs/2026-10-14-lostty-agent-coordination-design.md`, step 1 ("The guard, alone") of §9, with §7 (Guardrails), the Facts section and the Decisions table. Read §7 and the Decisions table before starting.

## Global Constraints

- Build on a fresh branch `guard` from `origin/skins` (at `9a0bb40b5` or later), in its own worktree. The `agent-coordination` worktree is older than `skins` and only holds the spec and this plan.
- After any change under `src/`: `zig build -Demit-macos-app=false`, then `macos/build.nu`. The `lostty` CLI is the app's own executable, so the Mac app must be rebuilt to pick up `+guard`.
- Zig tests: `zig build test -Dtest-filter="<prefix>"`. Every Zig test name in this plan starts with `guard ` so `-Dtest-filter="guard"` runs them all.
- Mac tests: `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project macos/Lostty.xcodeproj -scheme Lostty -configuration Debug SYMROOT=$PWD/macos/build -only-testing:LosttyTests/<Suite> test`. Tests use Swift Testing (`import Testing`), wrapped in `#if os(macOS)`.
- New Swift files go under `macos/Sources/Features/Guard/` (the project uses synchronized folders; no `.pbxproj` edits). Wrap macOS-only files in `#if os(macOS)`.
- Don't delete engine or other-platform code. Never create an issue or a PR.
- Commit messages: `lostty: guard: <what>`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Don't push, and don't install builds, unless the user asks.
- Spec values, verbatim: an approval covers "one action, the exact tool input, in one pane, for 10 minutes"; "Requests left unanswered lapse after 1 hour"; "Agents can't approve. There is no command, file, socket call or message an agent can use to approve"; "Deleting means 'git can't get it back'"; Mac notification has "**Deny** only. Approve opens the request's detail"; "No Touch ID"; "There is no 'approve all'"; "every `git push` by default"; Codex hooks can't `ask`, so "a Codex pane's critical actions stay blocked until Lostty is back"; Claude's hook returns `ask` when Lostty can't be reached.
- The guard is silent and contact-free for harmless calls: no socket, and no `git` process unless a delete, discard or merge needs one.
- Outside Lostty (`LOSTTY_SURFACE` unset) the hook does nothing.

## Decisions this plan adds (flag in review)

The spec leaves these to the build. Each is a default the user can veto:

1. **How the agent hears the outcome in step 1.** The spec delivers it through the pane's adapter, which arrives in step 2. Until then, clicking Approve or Deny also *types* one line into the agent's pane and presses Return ("Approved #42 in Lostty. Run it now, exactly as before."), and only when that pane's agent is still running. That's your click doing the typing, so it carries your authority, as Wake it will.
2. **`deletable` folders.** Without an exemption, `rm -rf node_modules` or `zig-out` would ask every time (ignored files count as unrecoverable). A config list, defaulting to `node_modules`, `.zig-cache`, `zig-cache`, `zig-out`, `.build`, `DerivedData`, `__pycache__`, lets those go. `build/` is *not* on it: it can hold anything.
3. **Writes Lostty doesn't count as "outside the project":** the temp folders (`/tmp`, `/private/tmp`, `/var/folders`, `/private/var/folders`, `$TMPDIR`) and `~/.claude/projects/` (Claude's own memory and transcripts). Everything else outside the repo (or outside the working folder, when it isn't a repo) is critical.
4. **Config file:** `~/.config/lostty/guard.json` (it sits under `~/.config/lostty/`, which the guard protects, so agents can't loosen it). Per repo: `push` (`"all"` or `"protected"`), `protectedBranches`, `commands` (scripts you list as critical), `deletable`.
5. **Socket:** `~/.config/lostty/coord/guard.sock`, mode 0600 in a 0700 folder. The app refuses a peer whose uid isn't yours.

## Review Focus

These are the inputs most likely to bite someone, which no single feature test would naturally hit. Each has a test in the task named:

1. **A commit message or heredoc that mentions `rm -rf`** (`git commit -m "$(cat <<'EOF' … rm -rf build … EOF)"`) must not be flagged. Agents write these all day. → Task 1 (`heredoc bodies aren't commands`) and Task 5 (`a commit message about rm is harmless`).
2. **Quotes that contain operators** (`echo "a; rm -rf x"`, `grep -E 'a|b'`) must not be split into commands. → Task 1.
3. **`cd` before a delete** (`cd ../other && rm -rf src`): the delete is judged from the folder `cd` moved to, and a `cd` to a variable makes later deletes critical. A subshell's `cd` doesn't leak out. → Task 5.
4. **Paths that leave the repo** (`rm ../x`, `rm ~/notes.md`, `rm /tmp/../Users/me/x`) are judged after resolving `..` and `~`. → Task 4.
5. **Lostty restarting (Restart to Update):** harmless calls keep flowing, Claude's critical calls fall back to its own prompt (`ask`), and Codex's are blocked with a reason. → Task 6.

---

## File Structure

| File | Responsibility |
| :- | :- |
| `src/cli/guard/shell.zig` (new) | Lex a shell string into simple commands: argv words, output-redirect targets, subshell depth. Quotes, `$( )`, backticks, heredocs, comments. Knows nothing about danger. |
| `src/cli/guard/config.zig` (new) | Load `~/.config/lostty/guard.json` over built-in defaults; per-repo effective settings. |
| `src/cli/guard/git.zig` (new) | `Live`, the real git probe (`repoRoot`, `branch`, `changes`, `onlyHere`, `headPushed`), and `Changes`. |
| `src/cli/guard/paths.zig` (new) | Path resolution (`~`, `..`), "inside", guardrail paths, write-exempt folders. |
| `src/cli/guard/catalog.zig` (new) | One simple command → a `Finding` (group, why, what would be lost) or null. Uses a probe passed as `anytype`. |
| `src/cli/guard/decide.zig` (new) | Hook input JSON → `Verdict` (harmless, or critical with everything the request shows). `cd` tracking, tool mapping. |
| `src/cli/guard/wire.zig` (new) | The socket request and reply, and the hook's output for each agent (allow, deny, ask). |
| `src/cli/guard.zig` (new) | The `+guard` action: read stdin, decide, ask the app, print. Never crashes open. |
| `src/cli/ghostty.zig` (modify) | Register the `guard` action. |
| `src/cli/claude/hooks.zig` (modify) | Install a `PreToolUse` guard hook for Claude and Codex; status counts it. |
| `macos/Sources/Features/Guard/GuardWire.swift` (new) | `GuardCheck` and `GuardReply`, the same JSON as `wire.zig`. |
| `macos/Sources/Features/Guard/ApprovalBook.swift` (new) | Pure request and approval logic: check, approve, deny, expire, persist. |
| `macos/Sources/Features/Guard/GuardServer.swift` (new) | The Unix socket listener: uid check, one JSON line in, one out. |
| `macos/Sources/Features/Guard/GuardRuntime.swift` (new) | App glue: owns the book and the server, posts notifications, types outcomes, tracks agent panes and hook health. |
| `macos/Sources/Features/Guard/GuardRequestView.swift` (new) | The request detail (window) and the shared row used in the Branches panel. |
| `macos/Sources/Features/Guard/GuardBadgeOverlay.swift` (new) | The pane badges: amber "Needs your approval", red "Guard disconnected". |
| `macos/Sources/Features/Guard/GuardHookWatch.swift` (new) | Watches `~/.claude` and `~/.codex` for hook-file changes and re-checks status. |
| `macos/Sources/App/macOS/AppDelegate.swift` (modify) | Start the runtime, register the notification category, route its responses. |
| `macos/Sources/Ghostty/Surface View/SurfaceView.swift` (modify) | Add `GuardBadgeOverlay` beside `ClaudeReadyOverlay`. |
| `macos/Sources/Features/Branches/BranchesPanel.swift` (modify) | An "Approvals" section at the top while any request waits. |
| `macos/Sources/Features/Claude/ClaudeRuntime.swift` (modify) | An `agentGone` callback when a pane's agent exits. |
| `SKINS.md` (modify) | A "Guard" section. |

---

### Task 1: Shell lexer

**Files:**
- Create: `src/cli/guard/shell.zig`
- Modify: `src/cli/ghostty.zig` (test block only)

**Interfaces:**
- Produces:
  ```zig
  pub const Word = struct { text: []const u8, dynamic: bool, assignment: bool = false };
  pub const Command = struct { argv: []const Word, writes: []const Word, depth: u8 };
  pub const Error = error{Unparseable} || std.mem.Allocator.Error;
  pub fn parse(alloc: Allocator, src: []const u8, home: []const u8) Error![]const Command;
  ```
  `dynamic` = the word's value isn't knowable from the text (it holds `$VAR`, `${…}`, `$( )`, backticks, `{a,b}`). `writes` = targets of `>`, `>>`, `>|`, `&>`, `N>` (not `/dev/null`, not `&N`). `depth` = nesting of `( )` subshells. Commands found inside `$( )`, backticks and `<( )` are appended as their own commands. A leading `~` or `~/` (unquoted) becomes `home`.

- [ ] **Step 1: Write the failing tests** at the bottom of `src/cli/guard/shell.zig` (create the file with only `const std = @import("std");`, `const Allocator = std.mem.Allocator;` and these tests first):

```zig
fn texts(alloc: Allocator, cmd: Command) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (cmd.argv) |w| try out.append(alloc, w.text);
    return out.toOwnedSlice(alloc);
}

fn expectArgv(cmd: Command, want: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const got = try texts(arena.allocator(), cmd);
    try std.testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try std.testing.expectEqualStrings(w, g);
}

test "guard shell: splits on operators, keeps quoted ones" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "echo \"a; rm -rf x\" && grep -E 'a|b' f; ls | wc -l & true\nfalse", "/home/me");
    try std.testing.expectEqual(@as(usize, 6), cmds.len);
    try expectArgv(cmds[0], &.{ "echo", "a; rm -rf x" });
    try expectArgv(cmds[1], &.{ "grep", "-E", "a|b", "f" });
    try expectArgv(cmds[2], &.{"ls"});
    try expectArgv(cmds[3], &.{ "wc", "-l" });
    try expectArgv(cmds[4], &.{"true"});
    try expectArgv(cmds[5], &.{"false"});
}

test "guard shell: heredoc bodies aren't commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src =
        \\git commit -m "$(cat <<'EOF'
        \\Stop rm -rf build; from running
        \\EOF
        \\)" && echo ok
    ;
    const cmds = try parse(arena.allocator(), src, "/home/me");
    // The inner cat (appended as soon as it's read), git, echo; nothing
    // from the body.
    try std.testing.expectEqual(@as(usize, 3), cmds.len);
    for (cmds) |c| {
        try std.testing.expect(!std.mem.eql(u8, c.argv[0].text, "rm"));
        try std.testing.expect(!std.mem.eql(u8, c.argv[0].text, "Stop"));
    }
    try expectArgv(cmds[0], &.{"cat"});
    try std.testing.expectEqualStrings("git", cmds[1].argv[0].text);
    try std.testing.expect(cmds[1].argv[3].dynamic); // the $( ) message
    try expectArgv(cmds[2], &.{ "echo", "ok" });
}

test "guard shell: plain heredoc with a dash and tabs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "cat <<-END > out.txt\n\trm -rf /\n\tEND\nls", "/h");
    try std.testing.expectEqual(@as(usize, 2), cmds.len);
    try expectArgv(cmds[0], &.{"cat"});
    try std.testing.expectEqualStrings("out.txt", cmds[0].writes[0].text);
    try expectArgv(cmds[1], &.{"ls"});
}

test "guard shell: command substitutions become their own commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "echo $(rm -rf x) `unlink y`", "/h");
    // Inner commands are appended as they're read, before the outer one ends.
    try std.testing.expectEqual(@as(usize, 3), cmds.len);
    try expectArgv(cmds[0], &.{ "rm", "-rf", "x" });
    try expectArgv(cmds[1], &.{ "unlink", "y" });
    try expectArgv(cmds[2], &.{ "echo", "", "" });
    try std.testing.expect(cmds[2].argv[1].dynamic);
}

test "guard shell: variables, braces and tilde" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "rm $DIR/a ${X} {a,b} ~/notes '~/lit' \"$HOME\"", "/home/me");
    const argv = cmds[0].argv;
    try std.testing.expect(argv[1].dynamic);
    try std.testing.expect(argv[2].dynamic);
    try std.testing.expect(argv[3].dynamic);
    try std.testing.expectEqualStrings("/home/me/notes", argv[4].text);
    try std.testing.expect(!argv[4].dynamic);
    try std.testing.expectEqualStrings("~/lit", argv[5].text);
    try std.testing.expect(argv[6].dynamic);
}

test "guard shell: redirects are writes, not arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "make 2>&1 >log.txt 2>/dev/null >> ~/x &> all < in.txt", "/home/me");
    try expectArgv(cmds[0], &.{"make"});
    const w = cmds[0].writes;
    try std.testing.expectEqual(@as(usize, 3), w.len);
    try std.testing.expectEqualStrings("log.txt", w[0].text);
    try std.testing.expectEqualStrings("/home/me/x", w[1].text);
    try std.testing.expectEqualStrings("all", w[2].text);
}

test "guard shell: subshells and groups set depth, keywords drop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "(cd sub && make); if test -f x; then rm x; fi; for f in *.log; do rm \"$f\"; done", "/h");
    try expectArgv(cmds[0], &.{ "cd", "sub" });
    try std.testing.expectEqual(@as(u8, 1), cmds[0].depth);
    try expectArgv(cmds[1], &.{"make"});
    try std.testing.expectEqual(@as(u8, 1), cmds[1].depth);
    try expectArgv(cmds[2], &.{ "test", "-f", "x" });
    try std.testing.expectEqual(@as(u8, 0), cmds[2].depth);
    try expectArgv(cmds[3], &.{ "rm", "x" });
    try expectArgv(cmds[4], &.{ "rm", "" });
    try std.testing.expect(cmds[4].argv[1].dynamic);
    try std.testing.expectEqual(@as(usize, 5), cmds.len);
}

test "guard shell: env assignments and comments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "FOO=1 BAR=$X git push # rm -rf /", "/h");
    try std.testing.expectEqual(@as(usize, 1), cmds.len);
    try expectArgv(cmds[0], &.{ "git", "push" });
}

test "guard shell: unbalanced quotes and case are unparseable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.Unparseable, parse(a, "echo \"oops", "/h"));
    try std.testing.expectError(error.Unparseable, parse(a, "echo $(ls", "/h"));
    try std.testing.expectError(error.Unparseable, parse(a, "case $x in a) rm y;; esac", "/h"));
    try std.testing.expectError(error.Unparseable, parse(a, "cat <<EOF\nno end", "/h"));
}
```

Add to the `test { … }` block at the end of `src/cli/ghostty.zig`:

```zig
    _ = @import("guard/shell.zig");
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zig build test -Dtest-filter="guard shell"`
Expected: compile error, `parse` / `Command` not declared.

- [ ] **Step 3: Implement** above the tests in `src/cli/guard/shell.zig`:

```zig
//! A small shell lexer for the guard: splits a command line into simple
//! commands (argv words, output-redirect targets, subshell depth). It reads
//! quotes, `$( )`, backticks, heredocs and comments the way sh does, and
//! marks any word whose value can't be known from the text as dynamic. It
//! decides nothing about danger. Anything it can't read is Unparseable,
//! which the guard treats as critical.

pub const Word = struct {
    text: []const u8,
    dynamic: bool,
    /// Written `NAME=value`: an environment assignment when it leads a
    /// command, whatever its value (`BAR=$X git push`).
    assignment: bool = false,
};

pub const Command = struct {
    argv: []const Word,
    /// Output redirect targets (`>`, `>>`, `>|`, `&>`, `N>`), except
    /// `/dev/null` and `>&N`.
    writes: []const Word,
    /// How many `( )` subshells it's inside.
    depth: u8,
};

pub const Error = error{Unparseable} || Allocator.Error;

pub fn parse(alloc: Allocator, src: []const u8, home: []const u8) Error![]const Command {
    var lx: Lexer = .{ .alloc = alloc, .src = src, .home = home };
    try lx.run();
    return lx.out.toOwnedSlice(alloc);
}

const reserved_lead = [_][]const u8{ "if", "then", "else", "elif", "do", "while", "until", "!", "time", "{" };
const reserved_alone = [_][]const u8{ "fi", "done", "esac", "}" };

fn isOneOf(s: []const u8, list: []const []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, s, x)) return true;
    return false;
}

/// The raw text at `i` starts `NAME=` (before any quoting or expansion).
fn isAssignmentAt(src: []const u8, i: usize) bool {
    var j = i;
    while (j < src.len) : (j += 1) {
        const c = src[j];
        if (c == '=') return j > i;
        const ok = c == '_' or std.ascii.isAlphabetic(c) or (j > i and std.ascii.isDigit(c));
        if (!ok) return false;
    }
    return false;
}

const Heredoc = struct { delim: []const u8, strip_tabs: bool };

const Lexer = struct {
    alloc: Allocator,
    src: []const u8,
    home: []const u8,
    i: usize = 0,
    depth: u8 = 0,
    out: std.ArrayList(Command) = .empty,
    argv: std.ArrayList(Word) = .empty,
    writes: std.ArrayList(Word) = .empty,
    heredocs: std.ArrayList(Heredoc) = .empty,
    /// The next word is a redirect target: .write, .read, or .heredoc.
    pending: enum { none, write, read, heredoc, heredoc_dash } = .none,
    /// Inside `for … in …` up to `do`: words there aren't a command.
    in_for: bool = false,

    fn run(self: *Lexer) Error!void {
        while (self.i < self.src.len) {
            const c = self.src[self.i];
            switch (c) {
                ' ', '\t' => self.i += 1,
                '\n' => {
                    try self.end();
                    self.i += 1;
                    try self.skipHeredocs();
                },
                '#' => {
                    // A comment only at the start of a word.
                    while (self.i < self.src.len and self.src[self.i] != '\n') self.i += 1;
                },
                ';', '&', '|' => try self.operator(),
                '(' => {
                    try self.end();
                    self.depth += 1;
                    self.i += 1;
                },
                ')' => {
                    try self.end();
                    if (self.depth == 0) return error.Unparseable;
                    self.depth -= 1;
                    self.i += 1;
                },
                '<', '>' => try self.redirect(),
                else => {
                    // `2>` and `&>` start with a digit or `&`, handled here.
                    if (std.ascii.isDigit(c) and self.i + 1 < self.src.len and self.src[self.i + 1] == '>') {
                        self.i += 1;
                        try self.redirect();
                        continue;
                    }
                    const w = try self.word();
                    try self.take(w);
                },
            }
        }
        if (self.pending != .none) return error.Unparseable;
        if (self.heredocs.items.len != 0) return error.Unparseable;
        if (self.depth != 0) return error.Unparseable;
        try self.end();
    }

    fn operator(self: *Lexer) Error!void {
        const c = self.src[self.i];
        if (c == '&' and self.i + 1 < self.src.len and self.src[self.i + 1] == '>') {
            self.i += 1; // `&>`: a redirect, not background.
            return self.redirect();
        }
        if (c == ';' and self.i + 1 < self.src.len and self.src[self.i + 1] == ';') return error.Unparseable;
        try self.end();
        self.i += 1;
        if (self.i < self.src.len and (self.src[self.i] == c)) self.i += 1; // && ||
    }

    fn redirect(self: *Lexer) Error!void {
        const c = self.src[self.i];
        self.i += 1;
        if (c == '<') {
            if (self.i < self.src.len and self.src[self.i] == '<') {
                self.i += 1;
                if (self.i < self.src.len and self.src[self.i] == '<') {
                    self.i += 1; // <<< here-string: next word is data
                    self.pending = .read;
                    return;
                }
                if (self.i < self.src.len and self.src[self.i] == '-') {
                    self.i += 1;
                    self.pending = .heredoc_dash;
                } else self.pending = .heredoc;
                return;
            }
            if (self.i < self.src.len and self.src[self.i] == '(') return self.processSubst();
            self.pending = .read;
            return;
        }
        // c == '>'
        if (self.i < self.src.len and (self.src[self.i] == '>' or self.src[self.i] == '|')) self.i += 1;
        if (self.i < self.src.len and self.src[self.i] == '&') {
            // >&2: a descriptor, not a file.
            self.i += 1;
            while (self.i < self.src.len and (std.ascii.isDigit(self.src[self.i]) or self.src[self.i] == '-')) self.i += 1;
            return;
        }
        if (self.i < self.src.len and self.src[self.i] == '(') return self.processSubst();
        self.pending = .write;
    }

    fn processSubst(self: *Lexer) Error!void {
        const inner = try self.balanced('(', ')');
        try self.nested(inner);
        try self.take(.{ .text = "", .dynamic = true });
    }

    /// Takes a finished word: a redirect target, a heredoc delimiter, or an
    /// argument.
    fn take(self: *Lexer, w: Word) Error!void {
        switch (self.pending) {
            .write => {
                self.pending = .none;
                if (!std.mem.eql(u8, w.text, "/dev/null")) try self.writes.append(self.alloc, w);
                return;
            },
            .read => {
                self.pending = .none;
                return;
            },
            .heredoc, .heredoc_dash => {
                try self.heredocs.append(self.alloc, .{ .delim = w.text, .strip_tabs = self.pending == .heredoc_dash });
                self.pending = .none;
                return;
            },
            .none => {},
        }
        if (self.argv.items.len == 0) {
            if (std.mem.eql(u8, w.text, "case")) return error.Unparseable;
            if (std.mem.eql(u8, w.text, "for")) {
                self.in_for = true;
                return;
            }
            if (self.in_for) {
                if (std.mem.eql(u8, w.text, "do")) self.in_for = false;
                return;
            }
            if (!w.dynamic and isOneOf(w.text, &reserved_lead)) return;
            if (w.assignment) return;
        }
        try self.argv.append(self.alloc, w);
    }

    fn end(self: *Lexer) Error!void {
        defer {
            self.argv = .empty;
            self.writes = .empty;
        }
        if (self.argv.items.len == 0 and self.writes.items.len == 0) return;
        if (self.argv.items.len == 1 and isOneOf(self.argv.items[0].text, &reserved_alone)) return;
        try self.out.append(self.alloc, .{
            .argv = try self.argv.toOwnedSlice(self.alloc),
            .writes = try self.writes.toOwnedSlice(self.alloc),
            .depth = self.depth,
        });
    }

    /// After a newline, skips the bodies of heredocs opened on that line.
    fn skipHeredocs(self: *Lexer) Error!void {
        for (self.heredocs.items) |h| {
            while (true) {
                if (self.i >= self.src.len) return error.Unparseable;
                const eol = std.mem.indexOfScalarPos(u8, self.src, self.i, '\n') orelse self.src.len;
                var line = self.src[self.i..eol];
                if (h.strip_tabs) line = std.mem.trimLeft(u8, line, "\t");
                self.i = @min(eol + 1, self.src.len);
                if (std.mem.eql(u8, line, h.delim)) break;
            }
        }
        self.heredocs.clearRetainingCapacity();
    }

    /// Reads up to the matching `close`, honouring quotes and nesting. The
    /// opening char is at self.i. Returns the text between them.
    fn balanced(self: *Lexer, open: u8, close: u8) Error![]const u8 {
        std.debug.assert(self.src[self.i] == open);
        self.i += 1;
        const start = self.i;
        var level: usize = 1;
        while (self.i < self.src.len) : (self.i += 1) {
            const c = self.src[self.i];
            if (c == '\\') {
                self.i += 1;
            } else if (c == '\'') {
                self.i = std.mem.indexOfScalarPos(u8, self.src, self.i + 1, '\'') orelse return error.Unparseable;
            } else if (c == '"') {
                self.i = try self.skipDouble(self.i + 1);
            } else if (c == '<' and self.i + 1 < self.src.len and self.src[self.i + 1] == '<' and open == '(') {
                // A heredoc inside $( ): its body may hold quotes or parens.
                self.i = try self.skipInnerHeredoc(self.i + 2);
            } else if (c == open) {
                level += 1;
            } else if (c == close) {
                level -= 1;
                if (level == 0) {
                    const inner = self.src[start..self.i];
                    self.i += 1;
                    return inner;
                }
            }
        }
        return error.Unparseable;
    }

    /// Index of the closing `"` of a double-quoted string starting at `from`.
    fn skipDouble(self: *Lexer, from: usize) Error!usize {
        var j = from;
        while (j < self.src.len) : (j += 1) {
            switch (self.src[j]) {
                '\\' => j += 1,
                '"' => return j,
                else => {},
            }
        }
        return error.Unparseable;
    }

    /// Skips `<<[-]DELIM … DELIM\n` inside a $( ); `from` is after `<<`.
    /// Returns the index of the last char of the closing delimiter line.
    fn skipInnerHeredoc(self: *Lexer, from: usize) Error!usize {
        var j = from;
        const dash = j < self.src.len and self.src[j] == '-';
        if (dash) j += 1;
        while (j < self.src.len and (self.src[j] == ' ' or self.src[j] == '\t')) j += 1;
        const dstart = j;
        while (j < self.src.len and self.src[j] != '\n' and self.src[j] != ' ' and self.src[j] != ')') j += 1;
        const delim = std.mem.trim(u8, self.src[dstart..j], "'\"");
        if (delim.len == 0) return j - 1;
        // Skip to the end of this line, then line by line to the delimiter.
        j = std.mem.indexOfScalarPos(u8, self.src, j, '\n') orelse return error.Unparseable;
        j += 1;
        while (j < self.src.len) {
            const eol = std.mem.indexOfScalarPos(u8, self.src, j, '\n') orelse self.src.len;
            var line = self.src[j..eol];
            if (dash) line = std.mem.trimLeft(u8, line, "\t");
            if (std.mem.eql(u8, line, delim)) return eol - 1;
            j = eol + 1;
        }
        return error.Unparseable;
    }

    /// Parses a $( ), backtick or <( ) body and appends its commands.
    fn nested(self: *Lexer, inner: []const u8) Error!void {
        const cmds = try parse(self.alloc, inner, self.home);
        for (cmds) |c| try self.out.append(self.alloc, .{ .argv = c.argv, .writes = c.writes, .depth = c.depth + self.depth });
    }

    /// One word, with quote removal. Stops at whitespace or an operator.
    fn word(self: *Lexer) Error!Word {
        var buf: std.ArrayList(u8) = .empty;
        var dynamic = false;
        const word_start = self.i;
        const assignment = isAssignmentAt(self.src, self.i);
        while (self.i < self.src.len) {
            const c = self.src[self.i];
            switch (c) {
                ' ', '\t', '\n', ';', '&', '|', '(', ')', '<', '>' => break,
                '\\' => {
                    if (self.i + 1 < self.src.len) {
                        if (self.src[self.i + 1] != '\n') try buf.append(self.alloc, self.src[self.i + 1]);
                        self.i += 2;
                    } else self.i += 1;
                },
                '\'' => {
                    const close = std.mem.indexOfScalarPos(u8, self.src, self.i + 1, '\'') orelse return error.Unparseable;
                    try buf.appendSlice(self.alloc, self.src[self.i + 1 .. close]);
                    self.i = close + 1;
                },
                '"' => {
                    self.i += 1;
                    while (true) {
                        if (self.i >= self.src.len) return error.Unparseable;
                        const d = self.src[self.i];
                        if (d == '"') {
                            self.i += 1;
                            break;
                        }
                        if (d == '\\' and self.i + 1 < self.src.len) {
                            try buf.append(self.alloc, self.src[self.i + 1]);
                            self.i += 2;
                        } else if (d == '$' or d == '`') {
                            dynamic = true;
                            try self.expansion();
                        } else {
                            try buf.append(self.alloc, d);
                            self.i += 1;
                        }
                    }
                },
                '$', '`' => {
                    dynamic = true;
                    try self.expansion();
                },
                '{' => {
                    // Brace expansion (`{a,b}`, `{1..3}`, no spaces inside)
                    // makes several words; we can't know them. A `{ …; }`
                    // group has spaces and is a keyword, not this.
                    if (std.mem.indexOfScalarPos(u8, self.src, self.i, '}')) |close| {
                        const inside_braces = self.src[self.i..close];
                        if (std.mem.indexOfAny(u8, inside_braces, " \t\n") == null and
                            std.mem.indexOfAny(u8, inside_braces, ",.") != null) dynamic = true;
                    }
                    try buf.append(self.alloc, c);
                    self.i += 1;
                },
                else => {
                    try buf.append(self.alloc, c);
                    self.i += 1;
                },
            }
        }
        var text = try buf.toOwnedSlice(self.alloc);
        // An unquoted leading ~ is the home folder.
        if (self.src[word_start] == '~' and (text.len == 1 or text[1] == '/')) {
            text = try std.mem.concat(self.alloc, u8, &.{ self.home, text[1..] });
        }
        if (dynamic) text = "";
        return .{ .text = text, .dynamic = dynamic, .assignment = assignment };
    }

    /// `$NAME`, `${…}`, `$( )`, `` `…` ``, `$((…))`: commands inside are
    /// parsed and appended; the value itself is unknown.
    fn expansion(self: *Lexer) Error!void {
        const c = self.src[self.i];
        if (c == '`') {
            const close = std.mem.indexOfScalarPos(u8, self.src, self.i + 1, '`') orelse return error.Unparseable;
            const inner = self.src[self.i + 1 .. close];
            self.i = close + 1;
            return self.nested(inner);
        }
        // c == '$'
        self.i += 1;
        if (self.i >= self.src.len) return;
        switch (self.src[self.i]) {
            '(' => {
                if (self.i + 1 < self.src.len and self.src[self.i + 1] == '(') {
                    _ = try self.balanced('(', ')'); // arithmetic: no commands
                    return;
                }
                const inner = try self.balanced('(', ')');
                return self.nested(inner);
            },
            '{' => _ = try self.balanced('{', '}'),
            else => while (self.i < self.src.len and (std.ascii.isAlphanumeric(self.src[self.i]) or self.src[self.i] == '_' or
                (self.i > 0 and self.src[self.i - 1] == '$' and std.mem.indexOfScalar(u8, "@*#?$!-0123456789", self.src[self.i]) != null)))
            {
                self.i += 1;
            },
        }
    }
};
```

Note: `processSubst` is entered with `self.i` at the `(`. In `word`, a `$` inside double quotes calls `expansion`, which advances `self.i` itself.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zig build test -Dtest-filter="guard shell"`
Expected: all 9 tests pass. If one fails, fix the lexer, not the test. The tests are the contract.

- [ ] **Step 5: Format and commit**

```bash
zig fmt src/cli/guard/shell.zig
git add src/cli/guard/shell.zig src/cli/ghostty.zig
git commit -m "lostty: guard: a shell lexer that finds the commands in a tool call

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Paths and config

**Files:**
- Create: `src/cli/guard/paths.zig`, `src/cli/guard/config.zig`
- Modify: `src/cli/ghostty.zig` (test block)

**Interfaces:**
- Produces (`paths.zig`):
  ```zig
  pub fn resolve(alloc: Allocator, cwd: []const u8, p: []const u8) Allocator.Error![]const u8; // absolute, `..` and `.` folded
  pub fn inside(path: []const u8, root: []const u8) bool;             // path == root or under root/
  pub fn isGuardrail(path: []const u8, home: []const u8) bool;
  pub fn isWriteExempt(path: []const u8, home: []const u8, tmpdir: ?[]const u8) bool;
  /// The nearest folder at or above `cwd` holding `.git` (a folder or a
  /// worktree's file), by looking at the filesystem only: no git process.
  /// Used where a repo is needed for every command (config lookups).
  pub fn findRepo(alloc: Allocator, cwd: []const u8) ?[]const u8;
  ```
- Produces (`config.zig`):
  ```zig
  pub const Push = enum { all, protected };
  pub const Effective = struct { push: Push, protected_branches: []const []const u8, commands: []const []const u8, deletable: []const []const u8 };
  pub const Config = struct {
      /// The parsed file, or null for defaults only.
      root: ?std.json.Value,
      pub fn load(alloc: Allocator, home: []const u8) Config;          // never fails: bad or missing file → defaults
      pub fn parse(alloc: Allocator, text: []const u8) Config;
      pub fn forRepo(self: Config, alloc: Allocator, repo: ?[]const u8) Allocator.Error!Effective;
  };
  pub const default_deletable: []const []const u8;
  ```

- [ ] **Step 1: Write the failing tests.** In `src/cli/guard/paths.zig`:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

test "guard paths: resolve folds dots and joins relative paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("/r/x", try resolve(a, "/r/sub", "../x"));
    try std.testing.expectEqualStrings("/Users/me/x", try resolve(a, "/r", "/tmp/../Users/me/x"));
    try std.testing.expectEqualStrings("/r/sub", try resolve(a, "/r/sub", "."));
    try std.testing.expectEqualStrings("/r", try resolve(a, "/r/sub/", ".."));
}

test "guard paths: inside" {
    try std.testing.expect(inside("/r/a", "/r"));
    try std.testing.expect(inside("/r", "/r"));
    try std.testing.expect(!inside("/rx/a", "/r"));
    try std.testing.expect(!inside("/", "/r"));
}

test "guard paths: guardrails" {
    const h = "/Users/me";
    try std.testing.expect(isGuardrail("/Users/me/.claude/settings.json", h));
    try std.testing.expect(isGuardrail("/Users/me/proj/.claude/settings.local.json", h));
    try std.testing.expect(isGuardrail("/Users/me/.codex/hooks.json", h));
    try std.testing.expect(isGuardrail("/Users/me/proj/.codex/config.toml", h));
    try std.testing.expect(isGuardrail("/Users/me/.config/lostty/guard.json", h));
    try std.testing.expect(isGuardrail("/Users/me/.config/lostty", h));
    try std.testing.expect(isGuardrail("/Users/me/.ssh/id_ed25519", h));
    try std.testing.expect(isGuardrail("/Applications/Lostty.app/Contents/MacOS/lostty", h));
    try std.testing.expect(!isGuardrail("/Users/me/proj/settings.json", h));
    try std.testing.expect(!isGuardrail("/Users/me/.claude/projects/x/memory/a.md", h));
}

test "guard paths: write-exempt folders" {
    const h = "/Users/me";
    try std.testing.expect(isWriteExempt("/tmp/x", h, null));
    try std.testing.expect(isWriteExempt("/private/var/folders/ab/T/x", h, null));
    try std.testing.expect(isWriteExempt("/Users/me/.claude/projects/p/memory/a.md", h, null));
    try std.testing.expect(isWriteExempt("/scratch/x", h, "/scratch/"));
    try std.testing.expect(!isWriteExempt("/Users/me/notes.md", h, null));
    try std.testing.expect(!isWriteExempt("/Users/me/.claude/settings.json", h, null));
}

test "guard paths: findRepo walks up to .git without git" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("repo/.git");
    try tmp.dir.makePath("repo/a/b");
    try tmp.dir.makePath("wt/x");
    try tmp.dir.writeFile(.{ .sub_path = "wt/.git", .data = "gitdir: /elsewhere\n" });
    const base = try tmp.dir.realpathAlloc(a, ".");
    const repo = try std.fs.path.join(a, &.{ base, "repo" });
    try std.testing.expectEqualStrings(repo, findRepo(a, try std.fs.path.join(a, &.{ repo, "a", "b" })).?);
    const wt = try std.fs.path.join(a, &.{ base, "wt" });
    try std.testing.expectEqualStrings(wt, findRepo(a, try std.fs.path.join(a, &.{ wt, "x" })).?);
    // The temp folder itself isn't in a repo.
    try std.testing.expect(findRepo(a, base) == null);
}
```

In `src/cli/guard/config.zig`:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, s)) return true;
    return false;
}

test "guard config: defaults" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = try Config.parse(a, "").forRepo(a, "/r");
    try std.testing.expectEqual(Push.all, e.push);
    try std.testing.expect(contains(e.protected_branches, "main"));
    try std.testing.expect(contains(e.protected_branches, "master"));
    try std.testing.expect(contains(e.commands, "ship-phone.sh"));
    try std.testing.expect(contains(e.deletable, "node_modules"));
    try std.testing.expect(!contains(e.deletable, "build"));
}

test "guard config: a repo adds to the global lists and can relax push" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cfg = Config.parse(a,
        \\{"protectedBranches":["release"],"commands":["deploy.sh"],
        \\ "repos":{"/r":{"push":"protected","protectedBranches":["skins"],"deletable":["build"]}}}
    );
    const r = try cfg.forRepo(a, "/r");
    try std.testing.expectEqual(Push.protected, r.push);
    try std.testing.expect(contains(r.protected_branches, "main"));
    try std.testing.expect(contains(r.protected_branches, "release"));
    try std.testing.expect(contains(r.protected_branches, "skins"));
    try std.testing.expect(contains(r.commands, "deploy.sh"));
    try std.testing.expect(contains(r.deletable, "build"));
    const other = try cfg.forRepo(a, "/other");
    try std.testing.expectEqual(Push.all, other.push);
    try std.testing.expect(!contains(other.deletable, "build"));
}

test "guard config: a broken file falls back to defaults" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = try Config.parse(a, "{ not json").forRepo(a, null);
    try std.testing.expectEqual(Push.all, e.push);
    try std.testing.expect(contains(e.protected_branches, "main"));
}
```

Add `_ = @import("guard/paths.zig");` and `_ = @import("guard/config.zig");` to the `src/cli/ghostty.zig` test block.

- [ ] **Step 2: Run to verify they fail**

Run: `zig build test -Dtest-filter="guard"`
Expected: compile errors (undeclared `resolve`, `Config`).

- [ ] **Step 3: Implement.** In `paths.zig`, above the tests:

```zig
//! Paths for the guard: resolving what a command names, and the folders
//! that are guardrails or that don't count as "outside the project".

pub fn resolve(alloc: Allocator, cwd: []const u8, p: []const u8) Allocator.Error![]const u8 {
    return std.fs.path.resolve(alloc, &.{ cwd, p });
}

pub fn inside(path: []const u8, root: []const u8) bool {
    if (!std.mem.startsWith(u8, path, root)) return false;
    if (path.len == root.len) return true;
    return root.len > 0 and (root[root.len - 1] == '/' or path[root.len] == '/');
}

fn under(path: []const u8, home: []const u8, rel: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const full = std.fmt.bufPrint(&buf, "{s}/{s}", .{ home, rel }) catch return false;
    return inside(path, full);
}

/// Files and folders whose change would loosen the guard or reach secrets.
pub fn isGuardrail(path: []const u8, home: []const u8) bool {
    const names = [_][]const u8{
        "/.claude/settings.json", "/.claude/settings.local.json",
        "/.codex/hooks.json",     "/.codex/config.toml",
    };
    for (names) |n| if (std.mem.endsWith(u8, path, n)) return true;
    if (under(path, home, ".config/lostty")) return true;
    if (under(path, home, ".ssh")) return true;
    if (inside(path, "/Applications/Lostty.app")) return true;
    return false;
}

/// Writes here don't count as leaving the project: the temp folders and
/// Claude's own memory and transcripts.
pub fn isWriteExempt(path: []const u8, home: []const u8, tmpdir: ?[]const u8) bool {
    const roots = [_][]const u8{ "/tmp", "/private/tmp", "/var/folders", "/private/var/folders" };
    for (roots) |r| if (inside(path, r)) return true;
    if (tmpdir) |t| if (inside(path, std.mem.trimRight(u8, t, "/"))) return true;
    return under(path, home, ".claude/projects");
}

pub fn findRepo(alloc: Allocator, cwd: []const u8) ?[]const u8 {
    var dir: []const u8 = cwd;
    while (true) {
        const dot_git = std.fs.path.join(alloc, &.{ dir, ".git" }) catch return null;
        if (std.fs.cwd().access(dot_git, .{})) |_| return dir else |_| {}
        dir = std.fs.path.dirname(dir) orelse return null;
    }
}
```

In `config.zig`, above the tests:

```zig
//! The guard's settings: `~/.config/lostty/guard.json` over built-in
//! defaults. The file sits under ~/.config/lostty, which the guard itself
//! protects, so an agent can't loosen it. A missing or broken file means
//! the defaults: the guard never turns itself off over a typo.
//!
//!   { "push": "all" | "protected",
//!     "protectedBranches": ["release"],
//!     "commands": ["deploy.sh"],
//!     "deletable": ["vendor"],
//!     "repos": { "/abs/path": { same keys } } }
//!
//! Lists add to the defaults (and a repo's to the global ones); `push`
//! overrides.

pub const Push = enum { all, protected };

pub const default_protected = [_][]const u8{ "main", "master" };
pub const default_commands = [_][]const u8{"ship-phone.sh"};
pub const default_deletable = [_][]const u8{ "node_modules", ".zig-cache", "zig-cache", "zig-out", ".build", "DerivedData", "__pycache__" };

pub const Effective = struct {
    push: Push,
    protected_branches: []const []const u8,
    commands: []const []const u8,
    deletable: []const []const u8,
};

pub const Config = struct {
    root: ?std.json.Value,

    pub fn load(alloc: Allocator, home: []const u8) Config {
        const path = std.fs.path.join(alloc, &.{ home, ".config", "lostty", "guard.json" }) catch return .{ .root = null };
        const text = std.fs.cwd().readFileAlloc(alloc, path, 1 << 20) catch return .{ .root = null };
        return parse(alloc, text);
    }

    pub fn parse(alloc: Allocator, text: []const u8) Config {
        const v = std.json.parseFromSliceLeaky(std.json.Value, alloc, text, .{}) catch return .{ .root = null };
        return .{ .root = if (v == .object) v else null };
    }

    pub fn forRepo(self: Config, alloc: Allocator, repo: ?[]const u8) Allocator.Error!Effective {
        var push: Push = .all;
        var protected: std.ArrayList([]const u8) = .empty;
        var commands: std.ArrayList([]const u8) = .empty;
        var deletable: std.ArrayList([]const u8) = .empty;
        try protected.appendSlice(alloc, &default_protected);
        try commands.appendSlice(alloc, &default_commands);
        try deletable.appendSlice(alloc, &default_deletable);
        const layers = [_]?std.json.Value{ self.root, self.repoLayer(repo) };
        for (layers) |layer| {
            const obj = layer orelse continue;
            if (obj != .object) continue;
            if (obj.object.get("push")) |p| if (p == .string) {
                if (std.mem.eql(u8, p.string, "protected")) push = .protected;
                if (std.mem.eql(u8, p.string, "all")) push = .all;
            };
            try addStrings(alloc, &protected, obj.object.get("protectedBranches"));
            try addStrings(alloc, &commands, obj.object.get("commands"));
            try addStrings(alloc, &deletable, obj.object.get("deletable"));
        }
        return .{
            .push = push,
            .protected_branches = try protected.toOwnedSlice(alloc),
            .commands = try commands.toOwnedSlice(alloc),
            .deletable = try deletable.toOwnedSlice(alloc),
        };
    }

    fn repoLayer(self: Config, repo: ?[]const u8) ?std.json.Value {
        const root = self.root orelse return null;
        const r = repo orelse return null;
        const repos = root.object.get("repos") orelse return null;
        if (repos != .object) return null;
        return repos.object.get(r);
    }
};

fn addStrings(alloc: Allocator, list: *std.ArrayList([]const u8), v: ?std.json.Value) Allocator.Error!void {
    const arr = v orelse return;
    if (arr != .array) return;
    for (arr.array.items) |item| if (item == .string) try list.append(alloc, item.string);
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `zig build test -Dtest-filter="guard"`
Expected: PASS (Task 1's tests too).

- [ ] **Step 5: Commit**

```bash
zig fmt src/cli/guard
git add src/cli/guard/paths.zig src/cli/guard/config.zig src/cli/ghostty.zig
git commit -m "lostty: guard: guardrail paths and the guard.json settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Git probe

**Files:**
- Create: `src/cli/guard/git.zig`
- Modify: `src/cli/ghostty.zig` (test block)

**Interfaces:**
- Produces:
  ```zig
  pub const Changes = struct {
      untracked: usize = 0, ignored: usize = 0, changed: usize = 0,
      pub fn total(self: Changes) usize;
      pub fn describe(self: Changes, alloc: Allocator) Allocator.Error![]const u8; // "3 untracked, 1 changed files"
  };
  pub const Live = struct {
      alloc: Allocator,
      pub fn repoRoot(self: Live, cwd: []const u8) ?[]const u8;
      pub fn branch(self: Live, root: []const u8) ?[]const u8;
      /// null when git fails (treated as critical by the caller).
      pub fn changes(self: Live, root: []const u8, paths: []const []const u8) ?Changes;
      /// The branch's tip is on no other local or remote branch.
      pub fn onlyHere(self: Live, root: []const u8, name: []const u8) bool;
      pub fn headPushed(self: Live, root: []const u8) bool;
  };
  pub fn parseStatus(out: []const u8) Changes; // `git status --porcelain=v1 -z` output
  ```
  Any type with these five methods works as a probe (`catalog.classify` takes `probe: anytype`), the way `protocol.findTty` takes its `ctx`.

- [ ] **Step 1: Write the failing tests** in `src/cli/guard/git.zig`:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

test "guard git: parseStatus counts each kind" {
    const out = "?? a.txt\x00?? b/c.txt\x00!! zig-out/\x00 M src/x.zig\x00M  y\x00R  new\x00old\x00";
    const c = parseStatus(out);
    try std.testing.expectEqual(@as(usize, 2), c.untracked);
    try std.testing.expectEqual(@as(usize, 1), c.ignored);
    try std.testing.expectEqual(@as(usize, 3), c.changed);
}

test "guard git: describe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const d = try (Changes{ .untracked = 3, .changed = 1 }).describe(arena.allocator());
    try std.testing.expectEqualStrings("3 untracked, 1 changed files", d);
}

fn sh(alloc: Allocator, cwd: []const u8, argv: []const []const u8) !void {
    const r = try std.process.Child.run(.{ .allocator = alloc, .argv = argv, .cwd = cwd });
    if (r.term != .Exited or r.term.Exited != 0) return error.CommandFailed;
}

test "guard git: live probe in a temp repo" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(a, ".");
    try sh(a, root, &.{ "git", "init", "-q", "-b", "main" });
    try sh(a, root, &.{ "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init" });
    try tmp.dir.writeFile(.{ .sub_path = ".gitignore", .data = "out/\n" });
    try tmp.dir.writeFile(.{ .sub_path = "kept.txt", .data = "x" });
    try sh(a, root, &.{ "git", "add", ".gitignore", "kept.txt" });
    try sh(a, root, &.{ "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "files" });
    try tmp.dir.makePath("out");
    try tmp.dir.writeFile(.{ .sub_path = "out/build.o", .data = "x" });
    try tmp.dir.writeFile(.{ .sub_path = "new.txt", .data = "x" });

    const live: Live = .{ .alloc = a };
    try tmp.dir.makePath("sub");
    const sub = try std.fs.path.join(a, &.{ root, "sub" });
    try std.testing.expectEqualStrings(root, live.repoRoot(sub).?);
    try std.testing.expectEqualStrings("main", live.branch(root).?);
    try std.testing.expectEqual(@as(usize, 0), live.changes(root, &.{"kept.txt"}).?.total());
    try std.testing.expectEqual(@as(usize, 1), live.changes(root, &.{"new.txt"}).?.untracked);
    try std.testing.expectEqual(@as(usize, 1), live.changes(root, &.{"out"}).?.ignored);
    try std.testing.expectEqual(@as(usize, 0), live.changes(root, &.{"missing.txt"}).?.total());
    try std.testing.expect(!live.headPushed(root));

    try sh(a, root, &.{ "git", "branch", "side" });
    try std.testing.expect(!live.onlyHere(root, "side")); // main has the same tip
    try sh(a, root, &.{ "git", "checkout", "-q", "-b", "solo" });
    try sh(a, root, &.{ "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "only" });
    try sh(a, root, &.{ "git", "checkout", "-q", "main" });
    try std.testing.expect(live.onlyHere(root, "solo"));
    try std.testing.expect(live.repoRoot("/") == null);
}
```

Note: on macOS `tmpDir` lives under `/private/var/folders`. `realpathAlloc` already returns that canonical form, and `git rev-parse --show-toplevel` returns the same, so the string compare holds.

Add `_ = @import("guard/git.zig");` to the `src/cli/ghostty.zig` test block.

- [ ] **Step 2: Run to verify they fail**

Run: `zig build test -Dtest-filter="guard git"`
Expected: compile error (undeclared `parseStatus`).

- [ ] **Step 3: Implement** above the tests:

```zig
//! What the guard asks git: where the repo is, what a path would lose, and
//! whether a branch or commit exists elsewhere. Only called for commands
//! that delete, discard or merge, never for harmless ones.

pub const Changes = struct {
    untracked: usize = 0,
    ignored: usize = 0,
    changed: usize = 0,

    pub fn total(self: Changes) usize {
        return self.untracked + self.ignored + self.changed;
    }

    pub fn describe(self: Changes, alloc: Allocator) Allocator.Error![]const u8 {
        var parts: std.ArrayList([]const u8) = .empty;
        if (self.untracked > 0) try parts.append(alloc, try std.fmt.allocPrint(alloc, "{d} untracked", .{self.untracked}));
        if (self.ignored > 0) try parts.append(alloc, try std.fmt.allocPrint(alloc, "{d} ignored", .{self.ignored}));
        if (self.changed > 0) try parts.append(alloc, try std.fmt.allocPrint(alloc, "{d} changed", .{self.changed}));
        const joined = try std.mem.join(alloc, ", ", parts.items);
        return std.fmt.allocPrint(alloc, "{s} files", .{joined});
    }
};

/// Counts `git status --porcelain=v1 -z` entries. A rename's second path
/// (the old name) follows its entry and isn't counted again.
pub fn parseStatus(out: []const u8) Changes {
    var c: Changes = .{};
    var it = std.mem.splitScalar(u8, out, 0);
    while (it.next()) |entry| {
        if (entry.len < 3) continue;
        const xy = entry[0..2];
        if (std.mem.eql(u8, xy, "??")) {
            c.untracked += 1;
        } else if (std.mem.eql(u8, xy, "!!")) {
            c.ignored += 1;
        } else {
            c.changed += 1;
            if (xy[0] == 'R' or xy[0] == 'C') _ = it.next();
        }
    }
    return c;
}

pub const Live = struct {
    alloc: Allocator,

    fn git(self: Live, cwd: []const u8, args: []const []const u8) ?[]const u8 {
        var argv: std.ArrayList([]const u8) = .empty;
        argv.appendSlice(self.alloc, &.{ "git", "-C", cwd }) catch return null;
        argv.appendSlice(self.alloc, args) catch return null;
        const r = std.process.Child.run(.{ .allocator = self.alloc, .argv = argv.items, .max_output_bytes = 4 << 20 }) catch return null;
        if (r.term != .Exited or r.term.Exited != 0) return null;
        return r.stdout;
    }

    pub fn repoRoot(self: Live, cwd: []const u8) ?[]const u8 {
        const out = self.git(cwd, &.{ "rev-parse", "--show-toplevel" }) orelse return null;
        return std.mem.trimRight(u8, out, "\n");
    }

    pub fn branch(self: Live, root: []const u8) ?[]const u8 {
        const out = self.git(root, &.{ "symbolic-ref", "--short", "-q", "HEAD" }) orelse return null;
        return std.mem.trimRight(u8, out, "\n");
    }

    pub fn changes(self: Live, root: []const u8, paths: []const []const u8) ?Changes {
        var args: std.ArrayList([]const u8) = .empty;
        args.appendSlice(self.alloc, &.{ "status", "--porcelain=v1", "-z", "--ignored=matching", "--untracked-files=all", "--" }) catch return null;
        args.appendSlice(self.alloc, paths) catch return null;
        const out = self.git(root, args.items) orelse return null;
        return parseStatus(out);
    }

    pub fn onlyHere(self: Live, root: []const u8, name: []const u8) bool {
        const ref = std.fmt.allocPrint(self.alloc, "refs/heads/{s}", .{name}) catch return true;
        const out = self.git(root, &.{ "for-each-ref", "--contains", ref, "--format=%(refname)", "refs/heads", "refs/remotes" }) orelse return true;
        var it = std.mem.tokenizeScalar(u8, out, '\n');
        while (it.next()) |r| if (!std.mem.eql(u8, r, ref)) return false;
        return true;
    }

    pub fn headPushed(self: Live, root: []const u8) bool {
        const out = self.git(root, &.{ "branch", "-r", "--contains", "HEAD" }) orelse return false;
        return std.mem.trim(u8, out, " \n").len > 0;
    }
};
```

- [ ] **Step 4: Run to verify they pass**

Run: `zig build test -Dtest-filter="guard git"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
zig fmt src/cli/guard/git.zig
git add src/cli/guard/git.zig src/cli/ghostty.zig
git commit -m "lostty: guard: ask git what a delete would lose

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The catalog

**Files:**
- Create: `src/cli/guard/catalog.zig`
- Modify: `src/cli/ghostty.zig` (test block)

**Interfaces:**
- Consumes: `shell.Word`, `shell.Command`, `shell.parse` (Task 1); `paths.*`, `config.Effective` (Task 2); `git.Changes` and any probe with `Live`'s methods (Task 3).
- Produces:
  ```zig
  pub const Group = enum { deleting, discarding, leaving, merging, guardrails, outside, unreadable };
  pub const Finding = struct { group: Group, why: []const u8, lost: ?[]const u8 = null };
  pub const Ctx = struct {
      alloc: Allocator,
      /// The folder the command runs in; null when a `cd` made it unknowable.
      cwd: ?[]const u8,
      home: []const u8,
      tmpdir: ?[]const u8,
      config: config.Config,
  };
  pub fn classify(ctx: Ctx, probe: anytype, cmd: shell.Command) Allocator.Error!?Finding;
  /// For file tools (Write, Edit, apply_patch): a write to `path`.
  pub fn write(ctx: Ctx, probe: anytype, path: []const u8) Allocator.Error!?Finding;
  /// For apply_patch "Delete File" and the rm family.
  pub fn deletion(ctx: Ctx, probe: anytype, words: []const shell.Word) Allocator.Error!?Finding;
  pub fn label(g: Group) []const u8; // "Deleting", "Throwing work away", …
  ```

- [ ] **Step 1: Write the failing tests** in `src/cli/guard/catalog.zig`. A fake probe stands in for git:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const shell = @import("shell.zig");
const config = @import("config.zig");
const paths = @import("paths.zig");
const git = @import("git.zig");

const Fake = struct {
    root: ?[]const u8 = "/r",
    current: ?[]const u8 = "feature",
    /// Paths (as given, relative to the root) that are untracked.
    dirty: []const []const u8 = &.{},
    /// Paths with uncommitted changes to tracked files.
    changed: []const []const u8 = &.{},
    only_here: bool = false,
    pushed: bool = false,
    git_fails: bool = false,

    pub fn repoRoot(self: Fake, cwd: []const u8) ?[]const u8 {
        const r = self.root orelse return null;
        return if (paths.inside(cwd, r)) r else null;
    }
    pub fn branch(self: Fake, _: []const u8) ?[]const u8 {
        return self.current;
    }
    pub fn changes(self: Fake, _: []const u8, ps: []const []const u8) ?git.Changes {
        if (self.git_fails) return null;
        var c: git.Changes = .{};
        for (ps) |p| {
            for (self.dirty) |d| if (std.mem.eql(u8, p, d)) {
                c.untracked += 1;
            };
            for (self.changed) |d| if (std.mem.eql(u8, p, d)) {
                c.changed += 1;
            };
        }
        return c;
    }
    pub fn onlyHere(self: Fake, _: []const u8, _: []const u8) bool {
        return self.only_here;
    }
    pub fn headPushed(self: Fake, _: []const u8) bool {
        return self.pushed;
    }
};

fn check(a: Allocator, probe: Fake, cwd: ?[]const u8, src: []const u8) !?Finding {
    const ctx: Ctx = .{ .alloc = a, .cwd = cwd, .home = "/Users/me", .tmpdir = null, .config = config.Config.parse(a, "") };
    const cmds = try shell.parse(a, src, "/Users/me");
    for (cmds) |c| if (try classify(ctx, probe, c)) |f| return f;
    return null;
}

fn group(a: Allocator, probe: Fake, src: []const u8) !?Group {
    const f = try check(a, probe, "/r", src) orelse return null;
    return f.group;
}

test "guard catalog: harmless everyday commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const harmless = [_][]const u8{
        "ls -la", "git status", "git diff HEAD~1", "zig build test", "git commit -m 'wip'",
        "git checkout main", "git stash", "git stash pop", "git worktree prune", "git reset HEAD~1",
        "git restore --staged x", "npm install", "cat a > out.txt", "git log | head",
        "echo 'rm -rf /'", "git branch -m old new",
    };
    for (harmless) |src| {
        if (try group(a, .{}, src)) |g| {
            std.debug.print("unexpected {s} for: {s}\n", .{ @tagName(g), src });
            return error.TestUnexpectedResult;
        }
    }
}

test "guard catalog: deletes are critical only when git can't restore them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "rm src/committed.zig"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{ .dirty = &.{"notes.md"} }, "rm notes.md"));
    const f = (try check(a, .{ .dirty = &.{"notes.md"} }, "/r", "rm -f notes.md")).?;
    try std.testing.expectEqualStrings("1 untracked files", f.lost.?);
    // `deletable` folders go without asking even when ignored.
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .dirty = &.{"node_modules"} }, "rm -rf node_modules"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .dirty = &.{"macos/zig-out"} }, "rm -rf macos/zig-out"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{ .dirty = &.{"build"} }, "rm -rf build"));
    // Unknown targets, failed git, and other delete tools.
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "rm -rf $DIR"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{ .git_fails = true }, "rm x"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "find . -name '*.o' -delete"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "git ls-files -o | xargs rm"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{ .dirty = &.{"a"} }, "unlink a"));
}

test "guard catalog: paths that leave the repo" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "rm ../x"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "rm ~/notes.md"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "rm /tmp/../Users/me/x"));
    try std.testing.expectEqual(@as(?Group, .deleting), (try check(a, .{ .root = null }, "/Users/me", "rm x")).?.group);
    try std.testing.expectEqual(@as(?Group, .deleting), (try check(a, .{}, null, "rm x")).?.group);
    // Writes outside the project (temp folders are fine).
    try std.testing.expectEqual(@as(?Group, .outside), try group(a, .{}, "echo hi > ~/notes.md"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "echo hi > /tmp/x"));
    try std.testing.expectEqual(@as(?Group, .outside), try group(a, .{}, "cp a ../elsewhere/"));
    try std.testing.expectEqual(@as(?Group, .outside), try group(a, .{}, "sed -i '' s/a/b/ ../x.txt"));
}

test "guard catalog: guardrails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, .guardrails), try group(a, .{}, "echo '{}' > ~/.claude/settings.json"));
    try std.testing.expectEqual(@as(?Group, .guardrails), try group(a, .{}, "rm ~/.codex/hooks.json"));
    try std.testing.expectEqual(@as(?Group, .guardrails), try group(a, .{}, "security find-generic-password -s x"));
    try std.testing.expectEqual(@as(?Group, .guardrails), try group(a, .{}, "\"$LOSTTY_BIN\" +claude-hooks remove"));
    try std.testing.expectEqual(@as(?Group, .guardrails), try group(a, .{}, "lostty +claude-hooks remove --agent=codex"));
}

test "guard catalog: git that throws work away" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git reset --hard origin/main"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git rebase -i HEAD~3"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "git rebase --continue"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{ .changed = &.{"x.zig"} }, "git checkout -- x.zig"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "git checkout -- clean.zig"));
    // Untracked files aren't touched by checkout/restore.
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .dirty = &.{"x.zig"} }, "git checkout -- x.zig"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{ .changed = &.{"."} }, "git restore ."));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git switch -f other"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{ .pushed = true }, "git commit --amend --no-edit"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .pushed = false }, "git commit --amend --no-edit"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git filter-branch --tree-filter x"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git reflog expire --expire=now --all"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "git clean -fdx"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "git clean -n"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "git stash drop"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "git tag -d v1"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{ .only_here = true }, "git branch -D solo"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .only_here = false }, "git branch -d merged"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "git worktree remove --force .claude/worktrees/x"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git -C ../other reset --hard"));
}

test "guard catalog: leaving the Mac and merging" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "git push"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "git push origin feature"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "gh pr create --fill"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "gh issue create -t x"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "gh pr view 12"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "gh api -X DELETE repos/o/r"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "npm publish"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "macos/ship-phone.sh"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "scp out.tar host:/tmp/"));
    try std.testing.expectEqual(@as(?Group, .merging), try group(a, .{ .current = "main" }, "git merge feature"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .current = "feature" }, "git merge main"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "gh pr merge 12"));
}

test "guard catalog: push relaxed to protected for a repo" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ctx: Ctx = .{ .alloc = a, .cwd = "/r", .home = "/Users/me", .tmpdir = null, .config = config.Config.parse(a,
        \\{"repos":{"/r":{"push":"protected"}}}
    ) };
    const p = Fake{ .current = "feature" };
    const run = struct {
        fn f(c: Ctx, probe: Fake, src: []const u8) !?Finding {
            const cmds = try shell.parse(c.alloc, src, "/Users/me");
            return classify(c, probe, cmds[0]);
        }
    }.f;
    try std.testing.expect((try run(ctx, p, "git push")) == null);
    try std.testing.expect((try run(ctx, p, "git push -u origin feature")) == null);
    try std.testing.expect((try run(ctx, p, "git push origin main")) != null);
    try std.testing.expect((try run(ctx, p, "git push --force")) != null);
    try std.testing.expect((try run(ctx, p, "git push --tags")) != null);
    try std.testing.expect((try run(ctx, .{ .current = "main" }, "git push")) != null);
}

test "guard catalog: wrappers, shells and unreadable commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "sudo env FOO=1 nohup git push"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "timeout 30 git push"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "bash -c 'git status && git push'"));
    try std.testing.expectEqual(@as(?Group, .unreadable), try group(a, .{}, "eval \"$CMD\""));
    try std.testing.expectEqual(@as(?Group, .unreadable), try group(a, .{}, "$TOOL --go"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "docker volume rm data"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "psql -c 'drop table users'"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "kubectl delete pod x"));
}
```

Add `_ = @import("guard/catalog.zig");` to the `src/cli/ghostty.zig` test block.

- [ ] **Step 2: Run to verify they fail**

Run: `zig build test -Dtest-filter="guard catalog"`
Expected: compile error (undeclared `classify`).

- [ ] **Step 3: Implement** above the tests:

```zig
//! The guard's catalog: which commands are critical. Spec §7.2. A command
//! is critical when it deletes what git can't get back, throws work away,
//! leaves the Mac, merges into a protected branch, touches the guardrails,
//! writes outside the project, or can't be read. Everything else returns
//! null and goes through without asking.

pub const Group = enum { deleting, discarding, leaving, merging, guardrails, outside, unreadable };

pub fn label(g: Group) []const u8 {
    return switch (g) {
        .deleting => "Deleting",
        .discarding => "Throwing work away",
        .leaving => "Leaving the Mac",
        .merging => "Merging into a protected branch",
        .guardrails => "Changing the guardrails",
        .outside => "Writing outside the project",
        .unreadable => "A command Lostty can't read",
    };
}

pub const Finding = struct { group: Group, why: []const u8, lost: ?[]const u8 = null };

pub const Ctx = struct {
    alloc: Allocator,
    cwd: ?[]const u8,
    home: []const u8,
    tmpdir: ?[]const u8,
    config: config.Config,
};

const Error = Allocator.Error;

fn base(s: []const u8) []const u8 {
    return std.fs.path.basename(s);
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn has(argv: []const shell.Word, flag: []const u8) bool {
    for (argv) |w| if (!w.dynamic and eq(w.text, flag)) return true;
    return false;
}

/// A short flag set like `-fdx` contains `c`.
fn hasShort(argv: []const shell.Word, c: u8) bool {
    for (argv) |w| {
        if (w.dynamic or w.text.len < 2 or w.text[0] != '-' or w.text[1] == '-') continue;
        if (std.mem.indexOfScalar(u8, w.text[1..], c) != null) return true;
    }
    return false;
}

fn operands(alloc: Allocator, argv: []const shell.Word) Error![]const shell.Word {
    var out: std.ArrayList(shell.Word) = .empty;
    var dashdash = false;
    for (argv) |w| {
        if (!dashdash and !w.dynamic and eq(w.text, "--")) {
            dashdash = true;
            continue;
        }
        if (!dashdash and !w.dynamic and w.text.len > 0 and w.text[0] == '-') continue;
        try out.append(alloc, w);
    }
    return out.toOwnedSlice(alloc);
}

fn finding(g: Group, why: []const u8) ?Finding {
    return .{ .group = g, .why = why };
}

pub fn classify(ctx: Ctx, probe: anytype, cmd: shell.Command) Error!?Finding {
    // Writes first: a redirect to a guardrail or outside is critical
    // whatever the command.
    for (cmd.writes) |w| if (try write(ctx, probe, w)) |f| return f;
    return command(ctx, probe, cmd.argv);
}

fn command(ctx: Ctx, probe: anytype, argv_in: []const shell.Word) Error!?Finding {
    var argv = argv_in;
    if (argv.len == 0) return null;
    // Unwrap commands that run another one.
    while (argv.len > 0 and !argv[0].dynamic) {
        const name = base(argv[0].text);
        if (eq(name, "sudo") or eq(name, "command") or eq(name, "nohup") or eq(name, "exec") or eq(name, "time")) {
            argv = argv[1..];
        } else if (eq(name, "env")) {
            argv = argv[1..];
            while (argv.len > 0 and !argv[0].dynamic and (std.mem.indexOfScalar(u8, argv[0].text, '=') != null or (argv[0].text.len > 0 and argv[0].text[0] == '-'))) argv = argv[1..];
        } else if (eq(name, "nice") or eq(name, "timeout")) {
            argv = argv[1..];
            while (argv.len > 0 and !argv[0].dynamic and argv[0].text.len > 0 and (argv[0].text[0] == '-' or std.ascii.isDigit(argv[0].text[0]))) argv = argv[1..];
        } else break;
    }
    if (argv.len == 0) return null;
    // Before the name check: `"$LOSTTY_BIN" +claude-hooks remove` has a
    // variable for a name but is plainly Lostty's hooks command.
    if (has(argv, "+claude-hooks") and (has(argv, "remove") or has(argv, "install"))) return finding(.guardrails, "changes Lostty's agent hooks, which run the guard");
    if (argv[0].dynamic) return finding(.unreadable, "runs a command named by a variable or another command's output");
    const name = base(argv[0].text);
    const args = argv[1..];

    // Scripts you listed as critical. findRepo reads the filesystem only:
    // no git process for an everyday command.
    const eff = try ctx.config.forRepo(ctx.alloc, if (ctx.cwd) |c| paths.findRepo(ctx.alloc, c) else null);
    for (eff.commands) |c| if (eq(name, base(c)) or eq(argv[0].text, c)) {
        return .{ .group = .leaving, .why = try std.fmt.allocPrint(ctx.alloc, "{s} is on your list of critical commands", .{name}) };
    };

    if (eq(name, "sh") or eq(name, "bash") or eq(name, "zsh") or eq(name, "dash")) {
        for (args, 0..) |w, i| if (!w.dynamic and eq(w.text, "-c")) {
            if (i + 1 >= args.len or args[i + 1].dynamic) return finding(.unreadable, "runs a shell string Lostty can't read");
            return inner(ctx, probe, args[i + 1].text);
        };
        return null;
    }
    if (eq(name, "eval")) {
        var parts: std.ArrayList([]const u8) = .empty;
        for (args) |w| {
            if (w.dynamic) return finding(.unreadable, "eval runs text Lostty can't read");
            try parts.append(ctx.alloc, w.text);
        }
        return inner(ctx, probe, try std.mem.join(ctx.alloc, " ", parts.items));
    }
    if (eq(name, "xargs")) {
        var i: usize = 0;
        while (i < args.len and !args[i].dynamic and args[i].text.len > 0 and args[i].text[0] == '-') : (i += 1) {
            const f = args[i].text;
            if (f.len == 2 and std.mem.indexOfScalar(u8, "nIPLsdE", f[1]) != null) i += 1; // takes a value
        }
        if (i >= args.len) return null;
        const inner_name = base(args[i].text);
        if (isRemover(inner_name)) return finding(.deleting, "xargs deletes paths it reads from its input, which Lostty can't see");
        return command(ctx, probe, args[i..]);
    }

    if (isRemover(name)) return deletion(ctx, probe, try operands(ctx.alloc, args));
    if (eq(name, "shred") or eq(name, "srm")) return finding(.deleting, "shred destroys files for good");
    if (eq(name, "find")) {
        if (has(args, "-delete")) return finding(.deleting, "find -delete removes whatever matches, which Lostty can't see");
        for (args, 0..) |w, i| if (!w.dynamic and (eq(w.text, "-exec") or eq(w.text, "-execdir") or eq(w.text, "-ok")) and i + 1 < args.len and isRemover(base(args[i + 1].text))) {
            return finding(.deleting, "find runs rm on whatever matches, which Lostty can't see");
        };
        return null;
    }
    if (eq(name, "security")) return finding(.guardrails, "security reads or changes your Keychain");
    if (eq(name, "git")) return gitCommand(ctx, probe, args);
    if (eq(name, "gh")) return ghCommand(args);
    if ((eq(name, "npm") or eq(name, "pnpm") or eq(name, "yarn") or eq(name, "cargo")) and has(args, "publish")) return finding(.leaving, "publishes a package");
    if (eq(name, "gem") and has(args, "push")) return finding(.leaving, "publishes a gem");
    if (eq(name, "twine") and has(args, "upload")) return finding(.leaving, "publishes a Python package");
    if (eq(name, "pod") and has(args, "trunk")) return finding(.leaving, "publishes a pod");
    if (eq(name, "scp") or eq(name, "rsync")) {
        for (try operands(ctx.alloc, args)) |w| if (w.dynamic or isRemote(w.text)) return finding(.leaving, "copies files to another machine");
    }
    if (eq(name, "docker") or eq(name, "podman")) {
        if (has(args, "rm") or has(args, "rmi") or has(args, "prune") or (has(args, "down") and hasShort(args, 'v'))) return finding(.deleting, "removes containers, images or volumes");
    }
    if (eq(name, "kubectl") and has(args, "delete")) return finding(.deleting, "deletes cluster resources");
    if (eq(name, "psql") or eq(name, "mysql") or eq(name, "sqlite3") or eq(name, "duckdb")) {
        for (args) |w| if (w.dynamic or sqlDestroys(ctx.alloc, w.text)) return finding(.deleting, "runs SQL that drops, truncates or deletes data");
    }
    if (eq(name, "cp") or eq(name, "mv") or eq(name, "install") or eq(name, "ln")) {
        const ops = try operands(ctx.alloc, args);
        if (ops.len >= 2) return write(ctx, probe, ops[ops.len - 1]);
        return null;
    }
    if (eq(name, "tee") or eq(name, "truncate") or eq(name, "chmod") or eq(name, "chown")) {
        for (try operands(ctx.alloc, args)) |w| if (try write(ctx, probe, w)) |f| return f;
        return null;
    }
    if ((eq(name, "sed") or eq(name, "perl")) and (has(args, "-i") or hasShort(args, 'i'))) {
        const ops = try operands(ctx.alloc, args);
        // sed's first operand is the script (unless -e gave it).
        const files = if (has(args, "-e") or ops.len == 0) ops else ops[1..];
        for (files) |w| if (try write(ctx, probe, w)) |f| return f;
        return null;
    }
    if (eq(name, "dd")) {
        for (args) |w| if (!w.dynamic and std.mem.startsWith(u8, w.text, "of=")) {
            return write(ctx, probe, .{ .text = w.text[3..], .dynamic = false });
        };
    }
    return null;
}

fn isRemover(name: []const u8) bool {
    return eq(name, "rm") or eq(name, "rmdir") or eq(name, "unlink") or eq(name, "trash");
}

fn isRemote(s: []const u8) bool {
    if (s.len == 0 or s[0] == '/' or s[0] == '.') return false;
    const colon = std.mem.indexOfScalar(u8, s, ':') orelse return false;
    return std.mem.indexOfScalar(u8, s[0..colon], '/') == null;
}

fn sqlDestroys(alloc: Allocator, s: []const u8) bool {
    const up = std.ascii.allocUpperString(alloc, s) catch return true;
    return std.mem.indexOf(u8, up, "DROP ") != null or std.mem.indexOf(u8, up, "TRUNCATE") != null or
        std.mem.indexOf(u8, up, "DELETE FROM") != null;
}

fn inner(ctx: Ctx, probe: anytype, src: []const u8) Error!?Finding {
    const cmds = shell.parse(ctx.alloc, src, ctx.home) catch |e| switch (e) {
        error.Unparseable => return finding(.unreadable, "runs a shell string Lostty can't read"),
        error.OutOfMemory => return error.OutOfMemory,
    };
    for (cmds) |c| if (try classify(ctx, probe, c)) |f| return f;
    return null;
}

/// The rm family, and apply_patch's deletes: critical unless every target
/// is inside the repo and git can restore it (or it's a `deletable` folder).
pub fn deletion(ctx: Ctx, probe: anytype, words: []const shell.Word) Error!?Finding {
    if (words.len == 0) return null;
    const cwd = ctx.cwd orelse return finding(.deleting, "deletes from a folder Lostty can't work out");
    for (words) |w| if (w.dynamic) return finding(.deleting, "deletes paths held in a variable or another command's output");
    const root = probe.repoRoot(cwd) orelse return finding(.deleting, "deletes outside any git repo, so git can't restore it");
    const eff = try ctx.config.forRepo(ctx.alloc, root);
    var rels: std.ArrayList([]const u8) = .empty;
    for (words) |w| {
        const abs = try paths.resolve(ctx.alloc, cwd, w.text);
        if (paths.isGuardrail(abs, ctx.home)) return finding(.guardrails, "deletes a file the guard depends on");
        if (!paths.inside(abs, root)) return .{ .group = .deleting, .why = try std.fmt.allocPrint(ctx.alloc, "deletes {s}, outside the repo, so git can't restore it", .{abs}) };
        const rel = if (abs.len == root.len) "." else abs[root.len + 1 ..];
        if (isDeletable(rel, eff.deletable)) continue;
        try rels.append(ctx.alloc, rel);
    }
    if (rels.items.len == 0) return null;
    const changes = probe.changes(root, rels.items) orelse return finding(.deleting, "git couldn't check what this would delete");
    if (changes.total() == 0) return null;
    return .{ .group = .deleting, .why = "deletes files git can't restore", .lost = try changes.describe(ctx.alloc) };
}

fn isDeletable(rel: []const u8, names: []const []const u8) bool {
    var it = std.mem.splitScalar(u8, rel, '/');
    while (it.next()) |part| for (names) |n| if (eq(part, n)) return true;
    return false;
}

/// A file tool's write, or a shell write: critical for guardrails and for
/// places outside the project (the repo, or the folder when there's none).
pub fn write(ctx: Ctx, probe: anytype, w: shell.Word) Error!?Finding {
    if (w.dynamic) return finding(.outside, "writes to a path held in a variable");
    if (std.mem.startsWith(u8, w.text, "/dev/") and !eq(w.text, "/dev/null") and !std.mem.startsWith(u8, w.text, "/dev/std") and !std.mem.startsWith(u8, w.text, "/dev/fd/")) {
        return finding(.outside, "writes to a device");
    }
    if (std.mem.startsWith(u8, w.text, "/dev/")) return null;
    const cwd = ctx.cwd orelse return finding(.outside, "writes from a folder Lostty can't work out");
    const abs = try paths.resolve(ctx.alloc, cwd, w.text);
    if (paths.isGuardrail(abs, ctx.home)) return finding(.guardrails, "changes a file the guard depends on");
    if (paths.isWriteExempt(abs, ctx.home, ctx.tmpdir)) return null;
    const project = probe.repoRoot(cwd) orelse cwd;
    if (paths.inside(abs, project)) return null;
    return .{ .group = .outside, .why = try std.fmt.allocPrint(ctx.alloc, "writes {s}, outside the project", .{abs}) };
}

fn gitCommand(ctx_in: Ctx, probe: anytype, args_in: []const shell.Word) Error!?Finding {
    var ctx = ctx_in;
    var args = args_in;
    // Global options before the subcommand.
    while (args.len > 0 and !args[0].dynamic and args[0].text.len > 0 and args[0].text[0] == '-') {
        if ((eq(args[0].text, "-C") or eq(args[0].text, "-c")) and args.len > 1) {
            if (eq(args[0].text, "-C")) {
                if (args[1].dynamic) return finding(.unreadable, "runs git in a folder held in a variable");
                if (ctx.cwd) |c| ctx.cwd = try paths.resolve(ctx.alloc, c, args[1].text);
            }
            args = args[2..];
        } else args = args[1..];
    }
    if (args.len == 0 or args[0].dynamic) return null;
    const sub = args[0].text;
    const rest = args[1..];
    const root: ?[]const u8 = if (ctx.cwd) |c| probe.repoRoot(c) else null;

    if (eq(sub, "push")) return push(ctx, probe, root, rest);
    if (eq(sub, "clean")) {
        if ((has(rest, "--force") or hasShort(rest, 'f')) and !has(rest, "--dry-run") and !hasShort(rest, 'n'))
            return finding(.deleting, "git clean deletes untracked files git can't restore");
        return null;
    }
    if (eq(sub, "reset") and has(rest, "--hard")) return finding(.discarding, "git reset --hard throws away uncommitted changes");
    if (eq(sub, "rebase")) {
        if (has(rest, "--continue") or has(rest, "--abort") or has(rest, "--quit")) return null;
        return finding(.discarding, "git rebase rewrites history");
    }
    if (eq(sub, "filter-branch") or eq(sub, "filter-repo")) return finding(.discarding, "rewrites the whole history");
    if (eq(sub, "reflog") and (has(rest, "expire") or has(rest, "delete"))) return finding(.discarding, "removes git's record of old commits, its safety net");
    if (eq(sub, "gc")) for (rest) |w| if (!w.dynamic and std.mem.startsWith(u8, w.text, "--prune=")) return finding(.discarding, "prunes unreachable commits for good");
    if (eq(sub, "switch") and (has(rest, "-f") or has(rest, "--force") or has(rest, "--discard-changes"))) return finding(.discarding, "switches branch and throws away changes");
    if (eq(sub, "checkout")) {
        if (has(rest, "-f") or has(rest, "--force")) return finding(.discarding, "checks out over uncommitted changes");
        var after: []const shell.Word = &.{};
        for (rest, 0..) |w, i| if (!w.dynamic and eq(w.text, "--")) {
            after = rest[i + 1 ..];
        };
        if (after.len == 0 and has(rest, ".")) after = &.{.{ .text = ".", .dynamic = false }};
        if (after.len > 0) return discards(ctx, probe, root, after);
        return null;
    }
    if (eq(sub, "restore")) {
        if (has(rest, "--staged") and !has(rest, "--worktree") and !hasShort(rest, 'W')) return null;
        return discards(ctx, probe, root, try operands(ctx.alloc, rest));
    }
    if (eq(sub, "commit") and has(rest, "--amend")) {
        const r = root orelse return null;
        if (probe.headPushed(r)) return finding(.discarding, "amends a commit that's already pushed");
        return null;
    }
    if (eq(sub, "stash") and (has(rest, "drop") or has(rest, "clear"))) return finding(.deleting, "drops stashed work");
    if (eq(sub, "tag") and (has(rest, "-d") or has(rest, "--delete"))) return finding(.deleting, "deletes a tag");
    if (eq(sub, "update-ref") and has(rest, "-d")) return finding(.deleting, "deletes a ref");
    if (eq(sub, "branch") and (has(rest, "-d") or has(rest, "-D") or has(rest, "--delete"))) {
        const r = root orelse return finding(.deleting, "deletes a branch outside any repo Lostty can check");
        for (try operands(ctx.alloc, rest)) |w| {
            if (w.dynamic) return finding(.deleting, "deletes a branch named by a variable");
            if (probe.onlyHere(r, w.text)) return .{ .group = .deleting, .why = try std.fmt.allocPrint(ctx.alloc, "deletes branch {s}, whose commits are on no other branch", .{w.text}) };
        }
        return null;
    }
    if (eq(sub, "worktree") and rest.len > 0 and !rest[0].dynamic and eq(rest[0].text, "remove")) {
        if (has(rest, "--force") or hasShort(rest[1..], 'f')) return finding(.deleting, "removes a worktree with --force, uncommitted work included");
        const ops = try operands(ctx.alloc, rest[1..]);
        if (ops.len == 0) return null;
        if (ops[0].dynamic or ctx.cwd == null) return finding(.deleting, "removes a worktree Lostty can't check");
        const wt = try paths.resolve(ctx.alloc, ctx.cwd.?, ops[0].text);
        const c = probe.changes(wt, &.{"."}) orelse return finding(.deleting, "git couldn't check the worktree");
        if (c.ignored > 0) return .{ .group = .deleting, .why = "removes a worktree and its ignored files", .lost = try c.describe(ctx.alloc) };
        return null;
    }
    if (eq(sub, "merge")) {
        if (has(rest, "--abort") or has(rest, "--continue")) return null;
        const r = root orelse return null;
        const current = probe.branch(r) orelse return null;
        const eff = try ctx.config.forRepo(ctx.alloc, r);
        for (eff.protected_branches) |b| if (eq(b, current)) {
            return .{ .group = .merging, .why = try std.fmt.allocPrint(ctx.alloc, "merges into {s}, a protected branch", .{current}) };
        };
        return null;
    }
    return null;
}

fn discards(ctx: Ctx, probe: anytype, root: ?[]const u8, targets: []const shell.Word) Error!?Finding {
    const r = root orelse return finding(.discarding, "discards changes outside any repo Lostty can check");
    const cwd = ctx.cwd orelse return finding(.discarding, "discards changes from a folder Lostty can't work out");
    var rels: std.ArrayList([]const u8) = .empty;
    for (targets) |w| {
        if (w.dynamic) return finding(.discarding, "discards changes in paths held in a variable");
        const abs = try paths.resolve(ctx.alloc, cwd, w.text);
        try rels.append(ctx.alloc, if (abs.len <= r.len) "." else abs[r.len + 1 ..]);
    }
    const c = probe.changes(r, rels.items) orelse return finding(.discarding, "git couldn't check what this would discard");
    if (c.changed == 0) return null;
    return .{ .group = .discarding, .why = "throws away uncommitted changes", .lost = try (git.Changes{ .changed = c.changed }).describe(ctx.alloc) };
}

fn push(ctx: Ctx, probe: anytype, root: ?[]const u8, rest: []const shell.Word) Error!?Finding {
    const eff = try ctx.config.forRepo(ctx.alloc, root);
    const forced = has(rest, "--force") or has(rest, "--force-with-lease") or hasShort(rest, 'f') or has(rest, "--mirror");
    if (eff.push == .all) return finding(.leaving, if (forced) "git push --force overwrites the remote" else "git push sends commits off this Mac");
    // push = protected: only force, tags, deletes, and protected branches.
    if (forced) return finding(.leaving, "git push --force overwrites the remote");
    if (has(rest, "--tags") or has(rest, "--delete") or hasShort(rest, 'd')) return finding(.leaving, "pushes tags or deletes on the remote");
    const ops = try operands(ctx.alloc, rest);
    if (ops.len >= 2) {
        for (ops[1..]) |w| {
            if (w.dynamic) return finding(.leaving, "pushes a branch named by a variable");
            const dst = if (std.mem.indexOfScalar(u8, w.text, ':')) |i| w.text[i + 1 ..] else w.text;
            const name = if (std.mem.startsWith(u8, dst, "refs/heads/")) dst["refs/heads/".len..] else dst;
            for (eff.protected_branches) |b| if (eq(b, name)) return .{ .group = .leaving, .why = try std.fmt.allocPrint(ctx.alloc, "pushes to {s}, a protected branch", .{name}) };
        }
        return null;
    }
    const r = root orelse return finding(.leaving, "git push from outside a repo Lostty can check");
    const current = probe.branch(r) orelse return finding(.leaving, "git push from a detached HEAD");
    for (eff.protected_branches) |b| if (eq(b, current)) return .{ .group = .leaving, .why = try std.fmt.allocPrint(ctx.alloc, "pushes {s}, a protected branch", .{current}) };
    return null;
}

fn ghCommand(args: []const shell.Word) ?Finding {
    if (args.len < 2 or args[0].dynamic or args[1].dynamic) return null;
    const a = args[0].text;
    const b = args[1].text;
    if (eq(a, "pr") and (eq(b, "create") or eq(b, "merge"))) return finding(.leaving, "acts on GitHub: a pull request");
    if (eq(a, "issue") and eq(b, "create")) return finding(.leaving, "creates a GitHub issue");
    if (eq(a, "release") and (eq(b, "create") or eq(b, "delete") or eq(b, "upload"))) return finding(.leaving, "changes a GitHub release");
    if (eq(a, "repo") and (eq(b, "create") or eq(b, "delete") or eq(b, "archive") or eq(b, "rename"))) return finding(.leaving, "changes a GitHub repository");
    if (eq(a, "api")) {
        for (args, 0..) |w, i| if (!w.dynamic and (eq(w.text, "-X") or eq(w.text, "--method")) and i + 1 < args.len) {
            if (!eq(args[i + 1].text, "GET")) return finding(.leaving, "changes something on GitHub through its API");
        };
    }
    return null;
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `zig build test -Dtest-filter="guard catalog"`
Expected: PASS. If a "harmless everyday" case fails, check whether the implementation or the case is wrong against spec §7.2 before changing either.

- [ ] **Step 5: Commit**

```bash
zig fmt src/cli/guard/catalog.zig
git add src/cli/guard/catalog.zig src/cli/ghostty.zig
git commit -m "lostty: guard: the catalog of critical commands

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Deciding on a hook input

**Files:**
- Create: `src/cli/guard/decide.zig`
- Modify: `src/cli/ghostty.zig` (test block)

**Interfaces:**
- Consumes: `shell.parse`, `catalog.classify` / `write` / `deletion` / `Ctx` / `Finding` / `Group`, `config.Config`, a probe.
- Produces:
  ```zig
  pub const Critical = struct {
      group: catalog.Group, why: []const u8, lost: ?[]const u8,
      tool: []const u8, input: []const u8, cwd: []const u8,
      repo: ?[]const u8, branch: ?[]const u8,
      /// The agent's own words for the call (Claude's Bash `description`).
      reason: ?[]const u8,
      session: ?[]const u8,
  };
  pub const Verdict = union(enum) { harmless, critical: Critical };
  pub const Env = struct { home: []const u8, tmpdir: ?[]const u8, config: config.Config };
  pub fn decide(alloc: Allocator, env: Env, probe: anytype, input_json: []const u8) Allocator.Error!Verdict;
  ```

Tool mapping:
- `Bash` (Claude and Codex) → `tool_input.command`. Commands run in order: a static `cd`/`pushd` moves `cwd` for later ones, `cd`/`pushd` to a variable or `-` sets `cwd = null`, and when depth drops back below a subshell's depth, the `cwd` from before it returns. The first finding wins.
- `Write`, `Edit`, `MultiEdit` → `tool_input.file_path`. `NotebookEdit` → `tool_input.notebook_path`. Both go through `catalog.write`.
- `apply_patch` (Codex), or any tool whose input holds a string beginning `*** Begin Patch` → every `*** Add File: `, `*** Update File: ` and `*** Move to: ` path goes through `write`, and every `*** Delete File: ` path through `deletion`.
- `mcp__…` tools whose last segment contains `delete`, `remove`, `drop`, `destroy`, `publish`, `deploy`, `push` or `merge` → `leaving` ("an MCP tool named like it deletes or publishes").
- Any other tool → harmless.
- Input that isn't JSON, or has no `tool_name` → critical `unreadable` with tool `"?"`.

- [ ] **Step 1: Write the failing tests** in `src/cli/guard/decide.zig` (reuse a fake probe; copy it here, since tasks may be read alone):

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const shell = @import("shell.zig");
const catalog = @import("catalog.zig");
const config = @import("config.zig");
const paths = @import("paths.zig");
const git = @import("git.zig");

const Fake = struct {
    root: ?[]const u8 = "/r",
    dirty: []const []const u8 = &.{},

    pub fn repoRoot(self: Fake, cwd: []const u8) ?[]const u8 {
        const r = self.root orelse return null;
        return if (paths.inside(cwd, r)) r else null;
    }
    pub fn branch(_: Fake, _: []const u8) ?[]const u8 {
        return "feature";
    }
    pub fn changes(self: Fake, _: []const u8, ps: []const []const u8) ?git.Changes {
        var c: git.Changes = .{};
        for (ps) |p| for (self.dirty) |d| {
            if (std.mem.eql(u8, p, d)) c.untracked += 1;
        };
        return c;
    }
    pub fn onlyHere(_: Fake, _: []const u8, _: []const u8) bool {
        return false;
    }
    pub fn headPushed(_: Fake, _: []const u8) bool {
        return false;
    }
};

fn env(a: Allocator) Env {
    return .{ .home = "/Users/me", .tmpdir = null, .config = config.Config.parse(a, "") };
}

fn bash(a: Allocator, cmd: []const u8, cwd: []const u8) ![]const u8 {
    var obj = std.json.ObjectMap.init(a);
    var ti = std.json.ObjectMap.init(a);
    try ti.put("command", .{ .string = cmd });
    try ti.put("description", .{ .string = "Clean up" });
    try obj.put("tool_name", .{ .string = "Bash" });
    try obj.put("tool_input", .{ .object = ti });
    try obj.put("cwd", .{ .string = cwd });
    try obj.put("session_id", .{ .string = "s1" });
    return std.json.Stringify.valueAlloc(a, std.json.Value{ .object = obj }, .{});
}

test "guard decide: harmless and critical Bash" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect(try decide(a, env(a), Fake{}, try bash(a, "ls", "/r")) == .harmless);
    const v = try decide(a, env(a), Fake{}, try bash(a, "git push", "/r"));
    try std.testing.expectEqual(catalog.Group.leaving, v.critical.group);
    try std.testing.expectEqualStrings("git push", v.critical.input);
    try std.testing.expectEqualStrings("Bash", v.critical.tool);
    try std.testing.expectEqualStrings("/r", v.critical.cwd);
    try std.testing.expectEqualStrings("/r", v.critical.repo.?);
    try std.testing.expectEqualStrings("feature", v.critical.branch.?);
    try std.testing.expectEqualStrings("Clean up", v.critical.reason.?);
    try std.testing.expectEqualStrings("s1", v.critical.session.?);
}

test "guard decide: a commit message about rm is harmless" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cmd =
        \\git add -A && git commit -m "$(cat <<'EOF'
        \\Stop the guard from flagging rm -rf build; it's in a message
        \\
        \\Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
        \\EOF
        \\)"
    ;
    try std.testing.expect(try decide(a, env(a), Fake{}, try bash(a, cmd, "/r")) == .harmless);
}

test "guard decide: cd moves where later commands run" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = env(a);
    // In /r, `rm x` is restorable; after `cd /elsewhere` it's outside the repo.
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "rm x", "/r")) == .harmless);
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd /elsewhere && rm x", "/r")) == .critical);
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd ../other && rm -rf src", "/r")) == .critical);
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd $X && rm y", "/r")) == .critical);
    // A subshell's cd doesn't leak out.
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "(cd /elsewhere && ls); rm x", "/r")) == .harmless);
    // cd inside the repo stays fine.
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd sub && rm x", "/r")) == .harmless);
}

test "guard decide: file tools" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inside =
        \\{"tool_name":"Write","tool_input":{"file_path":"/r/a.zig","content":"x"},"cwd":"/r"}
    ;
    const outside =
        \\{"tool_name":"Edit","tool_input":{"file_path":"/Users/me/notes.md","old_string":"a","new_string":"b"},"cwd":"/r"}
    ;
    const settings =
        \\{"tool_name":"Write","tool_input":{"file_path":"/Users/me/.claude/settings.json","content":"{}"},"cwd":"/r"}
    ;
    const memory =
        \\{"tool_name":"Write","tool_input":{"file_path":"/Users/me/.claude/projects/p/memory/x.md","content":"x"},"cwd":"/r"}
    ;
    try std.testing.expect(try decide(a, env(a), Fake{}, inside) == .harmless);
    try std.testing.expectEqual(catalog.Group.outside, (try decide(a, env(a), Fake{}, outside)).critical.group);
    try std.testing.expectEqual(catalog.Group.guardrails, (try decide(a, env(a), Fake{}, settings)).critical.group);
    try std.testing.expect(try decide(a, env(a), Fake{}, memory) == .harmless);
    try std.testing.expectEqualStrings("/Users/me/notes.md", (try decide(a, env(a), Fake{}, outside)).critical.input);
}

test "guard decide: apply_patch adds, moves and deletes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ok =
        \\{"tool_name":"apply_patch","tool_input":{"input":"*** Begin Patch\n*** Update File: src/a.zig\n@@\n-x\n+y\n*** End Patch"},"cwd":"/r"}
    ;
    const del =
        \\{"tool_name":"apply_patch","tool_input":{"input":"*** Begin Patch\n*** Delete File: notes.md\n*** End Patch"},"cwd":"/r"}
    ;
    const away =
        \\{"tool_name":"apply_patch","tool_input":{"input":"*** Begin Patch\n*** Add File: ../x.txt\n+hi\n*** End Patch"},"cwd":"/r"}
    ;
    try std.testing.expect(try decide(a, env(a), Fake{}, ok) == .harmless);
    try std.testing.expectEqual(catalog.Group.deleting, (try decide(a, env(a), Fake{ .dirty = &.{"notes.md"} }, del)).critical.group);
    try std.testing.expect(try decide(a, env(a), Fake{}, del) == .harmless);
    try std.testing.expectEqual(catalog.Group.outside, (try decide(a, env(a), Fake{}, away)).critical.group);
}

test "guard decide: mcp tools, other tools, and junk" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mcp =
        \\{"tool_name":"mcp__github__delete_branch","tool_input":{},"cwd":"/r"}
    ;
    const read =
        \\{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"},"cwd":"/r"}
    ;
    try std.testing.expectEqual(catalog.Group.leaving, (try decide(a, env(a), Fake{}, mcp)).critical.group);
    try std.testing.expect(try decide(a, env(a), Fake{}, read) == .harmless);
    try std.testing.expectEqual(catalog.Group.unreadable, (try decide(a, env(a), Fake{}, "not json")).critical.group);
    try std.testing.expectEqual(catalog.Group.unreadable, (try decide(a, env(a), Fake{}, try bash(a, "echo \"oops", "/r"))).critical.group);
}
```

Add `_ = @import("guard/decide.zig");` to the `src/cli/ghostty.zig` test block.

- [ ] **Step 2: Run to verify they fail**

Run: `zig build test -Dtest-filter="guard decide"`
Expected: compile error (undeclared `decide`).

- [ ] **Step 3: Implement** above the tests:

```zig
//! The guard's decision for one PreToolUse hook input: harmless, or
//! critical with everything the approval request shows. Tool names and
//! input fields are the same for Claude Code and Codex (`Bash` with
//! `command`); Codex adds `apply_patch`.

pub const Critical = struct {
    group: catalog.Group,
    why: []const u8,
    lost: ?[]const u8 = null,
    tool: []const u8,
    input: []const u8,
    cwd: []const u8,
    repo: ?[]const u8 = null,
    branch: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    session: ?[]const u8 = null,
};

pub const Verdict = union(enum) { harmless, critical: Critical };

pub const Env = struct { home: []const u8, tmpdir: ?[]const u8, config: config.Config };

fn str(obj: std.json.Value, key: []const u8) ?[]const u8 {
    if (obj != .object) return null;
    const v = obj.object.get(key) orelse return null;
    return if (v == .string) v.string else null;
}

pub fn decide(alloc: Allocator, env: Env, probe: anytype, input_json: []const u8) Allocator.Error!Verdict {
    const root = std.json.parseFromSliceLeaky(std.json.Value, alloc, input_json, .{}) catch
        return unreadable("?", input_json, "/");
    const tool = str(root, "tool_name") orelse return unreadable("?", input_json, "/");
    const cwd = str(root, "cwd") orelse env.home;
    const ti = if (root == .object) root.object.get("tool_input") orelse std.json.Value{ .null = {} } else std.json.Value{ .null = {} };
    const ctx: catalog.Ctx = .{ .alloc = alloc, .cwd = cwd, .home = env.home, .tmpdir = env.tmpdir, .config = env.config };

    var input: []const u8 = "";
    var found: ?catalog.Finding = null;
    if (std.mem.eql(u8, tool, "Bash")) {
        input = str(ti, "command") orelse return unreadable(tool, input_json, cwd);
        found = try bashFinding(ctx, probe, input);
    } else if (isFileTool(tool)) {
        input = str(ti, "file_path") orelse str(ti, "notebook_path") orelse return unreadable(tool, input_json, cwd);
        found = try catalog.write(ctx, probe, .{ .text = input, .dynamic = false });
    } else if (patchText(ti)) |patch| {
        input = patch;
        found = try patchFinding(ctx, probe, patch);
    } else if (std.mem.startsWith(u8, tool, "mcp__")) {
        input = tool;
        if (mcpLooksCritical(alloc, tool)) found = .{ .group = .leaving, .why = "an MCP tool named like it deletes, publishes or merges" };
    }
    const f = found orelse return .harmless;
    const repo = probe.repoRoot(cwd);
    return .{ .critical = .{
        .group = f.group,
        .why = f.why,
        .lost = f.lost,
        .tool = tool,
        .input = input,
        .cwd = cwd,
        .repo = repo,
        .branch = if (repo) |r| probe.branch(r) else null,
        .reason = str(ti, "description"),
        .session = str(root, "session_id"),
    } };
}

fn unreadable(tool: []const u8, input: []const u8, cwd: []const u8) Verdict {
    return .{ .critical = .{ .group = .unreadable, .why = "Lostty couldn't read this tool call", .tool = tool, .input = input[0..@min(input.len, 4096)], .cwd = cwd } };
}

fn isFileTool(tool: []const u8) bool {
    const names = [_][]const u8{ "Write", "Edit", "MultiEdit", "NotebookEdit" };
    for (names) |n| if (std.mem.eql(u8, tool, n)) return true;
    return false;
}

fn bashFinding(ctx_in: catalog.Ctx, probe: anytype, src: []const u8) Allocator.Error!?catalog.Finding {
    const cmds = shell.parse(ctx_in.alloc, src, ctx_in.home) catch |e| switch (e) {
        error.Unparseable => return .{ .group = .unreadable, .why = "a shell command Lostty can't read" },
        error.OutOfMemory => return error.OutOfMemory,
    };
    var ctx = ctx_in;
    // cwd before each open subshell level, to restore when it closes.
    var saved: [64]?[]const u8 = undefined;
    var depth: u8 = 0;
    for (cmds) |c| {
        while (depth < c.depth and depth < saved.len) : (depth += 1) saved[depth] = ctx.cwd;
        while (depth > c.depth) {
            depth -= 1;
            ctx.cwd = saved[depth];
        }
        if (c.argv.len > 0 and !c.argv[0].dynamic and
            (std.mem.eql(u8, c.argv[0].text, "cd") or std.mem.eql(u8, c.argv[0].text, "pushd")))
        {
            if (c.argv.len == 1) {
                ctx.cwd = ctx.home;
            } else if (c.argv[1].dynamic or std.mem.eql(u8, c.argv[1].text, "-")) {
                ctx.cwd = null;
            } else if (ctx.cwd) |cur| {
                ctx.cwd = try paths.resolve(ctx.alloc, cur, c.argv[1].text);
            }
            continue;
        }
        if (try catalog.classify(ctx, probe, c)) |f| return f;
    }
    return null;
}

/// A Codex patch: the tool_input string that starts with "*** Begin Patch".
fn patchText(ti: std.json.Value) ?[]const u8 {
    if (ti == .string and std.mem.startsWith(u8, ti.string, "*** Begin Patch")) return ti.string;
    if (ti != .object) return null;
    var it = ti.object.iterator();
    while (it.next()) |e| if (e.value_ptr.* == .string and std.mem.startsWith(u8, e.value_ptr.string, "*** Begin Patch")) return e.value_ptr.string;
    return null;
}

fn patchFinding(ctx: catalog.Ctx, probe: anytype, patch: []const u8) Allocator.Error!?catalog.Finding {
    var it = std.mem.splitScalar(u8, patch, '\n');
    while (it.next()) |line| {
        const writes = [_][]const u8{ "*** Add File: ", "*** Update File: ", "*** Move to: " };
        for (writes) |p| if (std.mem.startsWith(u8, line, p)) {
            if (try catalog.write(ctx, probe, .{ .text = std.mem.trim(u8, line[p.len..], " "), .dynamic = false })) |f| return f;
        };
        const del = "*** Delete File: ";
        if (std.mem.startsWith(u8, line, del)) {
            const w = [_]shell.Word{.{ .text = std.mem.trim(u8, line[del.len..], " "), .dynamic = false }};
            if (try catalog.deletion(ctx, probe, &w)) |f| return f;
        }
    }
    return null;
}

fn mcpLooksCritical(alloc: Allocator, tool: []const u8) bool {
    const last = tool[(std.mem.lastIndexOf(u8, tool, "__") orelse 0)..];
    const lower = std.ascii.allocLowerString(alloc, last) catch return true;
    const words = [_][]const u8{ "delete", "remove", "drop", "destroy", "publish", "deploy", "push", "merge" };
    for (words) |w| if (std.mem.indexOf(u8, lower, w) != null) return true;
    return false;
}
```

`decide` only calls the probe's `repoRoot`/`branch` for critical calls, so harmless ones never start `git` unless the catalog needed it.

- [ ] **Step 4: Run to verify they pass**

Run: `zig build test -Dtest-filter="guard"`
Expected: PASS (all guard tests).

- [ ] **Step 5: Commit**

```bash
zig fmt src/cli/guard/decide.zig
git add src/cli/guard/decide.zig src/cli/ghostty.zig
git commit -m "lostty: guard: decide on a whole tool call, cd and patches included

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The `+guard` command and its wire

**Files:**
- Create: `src/cli/guard/wire.zig`, `src/cli/guard.zig`
- Modify: `src/cli/ghostty.zig` (register the action, and the test block)

**Interfaces:**
- Consumes: `decide.decide`, `decide.Critical`, `decide.Env`, `git.Live`, `config.Config.load`, `catalog.label`.
- Produces (`wire.zig`), the socket protocol the app implements in Task 8:
  ```zig
  pub const Agent = enum { claude, codex };
  pub const Reply = union(enum) { allow, deny: u32 };
  pub fn socketPath(alloc: Allocator, home: []const u8) Allocator.Error![]const u8; // ~/.config/lostty/coord/guard.sock
  /// One line of JSON (no newline inside), the request:
  /// {"v":1,"pane":…,"agent":"claude","session":…,"tool":…,"input":…,"cwd":…,
  ///  "repo":…,"branch":…,"group":"deleting","why":…,"lost":…,"reason":…}
  /// Optional fields are omitted when null.
  pub fn encodeRequest(alloc: Allocator, pane: []const u8, agent: Agent, c: decide.Critical) Allocator.Error![]const u8;
  /// {"v":1,"decision":"allow"} or {"v":1,"decision":"deny","request":42}; anything else → null.
  pub fn parseReply(alloc: Allocator, line: []const u8) ?Reply;
  pub const Output = struct { stdout: []const u8 = "", stderr: []const u8 = "", exit: u8 = 0 };
  pub fn outputDeny(alloc: Allocator, agent: Agent, id: u32, c: decide.Critical) Allocator.Error!Output;
  pub fn outputUnreachable(alloc: Allocator, agent: Agent, c: decide.Critical) Allocator.Error!Output;
  pub fn ask(alloc: Allocator, path: []const u8, request: []const u8, timeout_ms: u32) ?Reply; // null = unreachable
  ```
- Produces (`guard.zig`): `pub const Options`, `pub fn run(gpa: Allocator) !u8`. Argument: `--agent=claude|codex` (default `claude`).

Output rules:
- **Allow or harmless:** no output, exit 0.
- **Claude deny:** stdout `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<text>"}}`, exit 0.
- **Claude unreachable:** the same JSON with `"permissionDecision":"ask"` and a reason saying Lostty can't be reached.
- **Codex deny or unreachable:** the reason on stderr, exit 2.
- **Deny text:** `Blocked by Lostty: <why> (<label>). This needs your user's approval in Lostty: request #<id>. Don't try another way to do it. Carry on with other parts of the task; your user will tell you when they decide.`
- **Codex unreachable text:** `Blocked by Lostty: <why> (<label>). Lostty isn't running, so this can't be approved right now. Don't try another way to do it.`
- **Claude ask text:** `Lostty's guard can't reach the app, so it's asking you directly: <why> (<label>).`

- [ ] **Step 1: Write the failing tests** in `src/cli/guard/wire.zig`:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const decide = @import("decide.zig");
const catalog = @import("catalog.zig");

const sample: decide.Critical = .{
    .group = .deleting, .why = "deletes files git can't restore", .lost = "2 untracked files",
    .tool = "Bash", .input = "rm -rf \"tmp dir\"", .cwd = "/r", .repo = "/r", .branch = "feature",
    .reason = null, .session = "s1",
};

test "guard wire: request is one JSON line with optional fields omitted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const line = try encodeRequest(a, "PANE-1", .codex, sample);
    try std.testing.expect(std.mem.indexOfScalar(u8, line, '\n') == null);
    const v = try std.json.parseFromSliceLeaky(std.json.Value, a, line, .{});
    try std.testing.expectEqual(@as(i64, 1), v.object.get("v").?.integer);
    try std.testing.expectEqualStrings("PANE-1", v.object.get("pane").?.string);
    try std.testing.expectEqualStrings("codex", v.object.get("agent").?.string);
    try std.testing.expectEqualStrings("deleting", v.object.get("group").?.string);
    try std.testing.expectEqualStrings("rm -rf \"tmp dir\"", v.object.get("input").?.string);
    try std.testing.expect(v.object.get("reason") == null);
}

test "guard wire: parseReply" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect(parseReply(a, "{\"v\":1,\"decision\":\"allow\"}").? == .allow);
    try std.testing.expectEqual(@as(u32, 42), parseReply(a, "{\"v\":1,\"decision\":\"deny\",\"request\":42}").?.deny);
    try std.testing.expect(parseReply(a, "{\"v\":1,\"decision\":\"grant\"}") == null);
    try std.testing.expect(parseReply(a, "garbage") == null);
    try std.testing.expect(parseReply(a, "{\"v\":1,\"decision\":\"deny\"}") == null);
}

test "guard wire: outputs per agent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cd = try outputDeny(a, .claude, 42, sample);
    try std.testing.expectEqual(@as(u8, 0), cd.exit);
    const j = try std.json.parseFromSliceLeaky(std.json.Value, a, cd.stdout, .{});
    const h = j.object.get("hookSpecificOutput").?.object;
    try std.testing.expectEqualStrings("deny", h.get("permissionDecision").?.string);
    try std.testing.expect(std.mem.indexOf(u8, h.get("permissionDecisionReason").?.string, "request #42") != null);

    const xd = try outputDeny(a, .codex, 42, sample);
    try std.testing.expectEqual(@as(u8, 2), xd.exit);
    try std.testing.expect(std.mem.indexOf(u8, xd.stderr, "request #42") != null);

    const cu = try outputUnreachable(a, .claude, sample);
    const ju = try std.json.parseFromSliceLeaky(std.json.Value, a, cu.stdout, .{});
    try std.testing.expectEqualStrings("ask", ju.object.get("hookSpecificOutput").?.object.get("permissionDecision").?.string);
    const xu = try outputUnreachable(a, .codex, sample);
    try std.testing.expectEqual(@as(u8, 2), xu.exit);
    try std.testing.expect(std.mem.indexOf(u8, xu.stderr, "isn't running") != null);
}

test "guard wire: ask talks to a socket, and an absent one is unreachable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(a, ".");
    const path = try std.fs.path.join(a, &.{ dir, "g.sock" });
    try std.testing.expect(ask(a, path, "{}", 500) == null);

    const addr = try std.net.Address.initUnix(path);
    var server = try addr.listen(.{});
    defer server.deinit();
    const T = struct {
        fn serve(s: *std.net.Server) void {
            const conn = s.accept() catch return;
            defer conn.stream.close();
            var buf: [256]u8 = undefined;
            _ = conn.stream.read(&buf) catch return;
            _ = conn.stream.writeAll("{\"v\":1,\"decision\":\"deny\",\"request\":7}\n") catch {};
        }
    };
    const th = try std.Thread.spawn(.{}, T.serve, .{&server});
    const r = ask(a, path, "{\"v\":1}", 2000);
    th.join();
    try std.testing.expectEqual(@as(u32, 7), r.?.deny);
}
```

Add `_ = @import("guard/wire.zig");` and `_ = guard;` (after importing it, below) to the `src/cli/ghostty.zig` test block.

- [ ] **Step 2: Run to verify they fail**

Run: `zig build test -Dtest-filter="guard wire"`
Expected: compile error (undeclared `encodeRequest`).

- [ ] **Step 3: Implement `wire.zig`** above the tests:

```zig
//! The guard's two conversations: with the app over a Unix socket (one
//! JSON line each way; the app can only answer "allow" for an approval you
//! already gave, or "deny, request #N"), and with the agent through the
//! hook's output.

pub const Agent = enum { claude, codex };
pub const Reply = union(enum) { allow, deny: u32 };

pub fn socketPath(alloc: Allocator, home: []const u8) Allocator.Error![]const u8 {
    return std.fs.path.join(alloc, &.{ home, ".config", "lostty", "coord", "guard.sock" });
}

pub fn encodeRequest(alloc: Allocator, pane: []const u8, agent: Agent, c: decide.Critical) Allocator.Error![]const u8 {
    var o = std.json.ObjectMap.init(alloc);
    try o.put("v", .{ .integer = 1 });
    try o.put("pane", .{ .string = pane });
    try o.put("agent", .{ .string = @tagName(agent) });
    try o.put("tool", .{ .string = c.tool });
    try o.put("input", .{ .string = c.input });
    try o.put("cwd", .{ .string = c.cwd });
    try o.put("group", .{ .string = @tagName(c.group) });
    try o.put("why", .{ .string = c.why });
    const optional = [_]struct { []const u8, ?[]const u8 }{
        .{ "session", c.session }, .{ "repo", c.repo }, .{ "branch", c.branch },
        .{ "lost", c.lost },       .{ "reason", c.reason },
    };
    for (optional) |kv| if (kv[1]) |v| try o.put(kv[0], .{ .string = v });
    return std.json.Stringify.valueAlloc(alloc, std.json.Value{ .object = o }, .{});
}

pub fn parseReply(alloc: Allocator, line: []const u8) ?Reply {
    const v = std.json.parseFromSliceLeaky(std.json.Value, alloc, line, .{}) catch return null;
    if (v != .object) return null;
    const d = v.object.get("decision") orelse return null;
    if (d != .string) return null;
    if (std.mem.eql(u8, d.string, "allow")) return .allow;
    if (!std.mem.eql(u8, d.string, "deny")) return null;
    const id = v.object.get("request") orelse return null;
    if (id != .integer or id.integer <= 0) return null;
    return .{ .deny = @intCast(id.integer) };
}

pub const Output = struct { stdout: []const u8 = "", stderr: []const u8 = "", exit: u8 = 0 };

fn claudeJson(alloc: Allocator, decision: []const u8, reason: []const u8) Allocator.Error![]const u8 {
    var h = std.json.ObjectMap.init(alloc);
    try h.put("hookEventName", .{ .string = "PreToolUse" });
    try h.put("permissionDecision", .{ .string = decision });
    try h.put("permissionDecisionReason", .{ .string = reason });
    var o = std.json.ObjectMap.init(alloc);
    try o.put("hookSpecificOutput", .{ .object = h });
    return std.json.Stringify.valueAlloc(alloc, std.json.Value{ .object = o }, .{});
}

pub fn outputDeny(alloc: Allocator, agent: Agent, id: u32, c: decide.Critical) Allocator.Error!Output {
    const text = try std.fmt.allocPrint(alloc,
        "Blocked by Lostty: {s} ({s}). This needs your user's approval in Lostty: request #{d}. " ++
            "Don't try another way to do it. Carry on with other parts of the task; your user will tell you when they decide.",
        .{ c.why, catalog.label(c.group), id });
    return switch (agent) {
        .claude => .{ .stdout = try claudeJson(alloc, "deny", text) },
        .codex => .{ .stderr = text, .exit = 2 },
    };
}

pub fn outputUnreachable(alloc: Allocator, agent: Agent, c: decide.Critical) Allocator.Error!Output {
    return switch (agent) {
        .claude => .{ .stdout = try claudeJson(alloc, "ask", try std.fmt.allocPrint(alloc,
            "Lostty's guard can't reach the app, so it's asking you directly: {s} ({s}).", .{ c.why, catalog.label(c.group) })) },
        .codex => .{ .stderr = try std.fmt.allocPrint(alloc,
            "Blocked by Lostty: {s} ({s}). Lostty isn't running, so this can't be approved right now. Don't try another way to do it.",
            .{ c.why, catalog.label(c.group) }), .exit = 2 },
    };
}

/// Sends one request line and reads one reply line. Null when the app
/// can't be reached, times out, or answers nonsense: the caller fails
/// closed.
pub fn ask(alloc: Allocator, path: []const u8, request: []const u8, timeout_ms: u32) ?Reply {
    const stream = std.net.connectUnixSocket(path) catch return null;
    defer stream.close();
    const tv: std.posix.timeval = .{ .sec = @intCast(timeout_ms / 1000), .usec = @intCast((timeout_ms % 1000) * 1000) };
    std.posix.setsockopt(stream.handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&tv)) catch return null;
    std.posix.setsockopt(stream.handle, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&tv)) catch return null;
    stream.writeAll(request) catch return null;
    stream.writeAll("\n") catch return null;
    var buf: [4096]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) {
        const n = stream.read(buf[len..]) catch return null;
        if (n == 0) break;
        len += n;
        if (std.mem.indexOfScalar(u8, buf[0..len], '\n') != null) break;
    }
    const line = std.mem.trimRight(u8, buf[0..len], "\n");
    return parseReply(alloc, line);
}
```

- [ ] **Step 4: Implement `src/cli/guard.zig`:**

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const decide = @import("guard/decide.zig");
const wire = @import("guard/wire.zig");
const config = @import("guard/config.zig");
const git = @import("guard/git.zig");

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

/// The `guard` command is run by Lostty's PreToolUse hooks for Claude Code
/// (`+guard --agent=claude`) and Codex (`+guard --agent=codex`). It reads
/// the hook input on stdin and lets a harmless tool call through silently.
/// A critical one (deleting what git can't restore, throwing work away,
/// leaving the Mac, merging into a protected branch, changing the
/// guardrails, writing outside the project) goes through only if you
/// approved exactly that call in Lostty; otherwise it's blocked and Lostty
/// shows you the request. If Lostty can't be reached, Claude asks you
/// itself and Codex stays blocked. Outside Lostty it does nothing.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const pane = std.posix.getenv("LOSTTY_SURFACE") orelse return 0;
    var agent: wire.Agent = .claude;
    const argv = std.process.argsAlloc(alloc) catch return failClosed(alloc, agent);
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--agent=codex")) agent = .codex;
    }
    return runFor(alloc, pane, agent) catch failClosed(alloc, agent);
}

fn runFor(alloc: Allocator, pane: []const u8, agent: wire.Agent) !u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    // As claude_state.hookInput reads it.
    var buf: [4096]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&buf);
    const input = try reader.interface.allocRemaining(alloc, .limited(8 << 20));
    const env: decide.Env = .{ .home = home, .tmpdir = std.posix.getenv("TMPDIR"), .config = config.Config.load(alloc, home) };
    const verdict = try decide.decide(alloc, env, git.Live{ .alloc = alloc }, input);
    const c = switch (verdict) {
        .harmless => return 0,
        .critical => |c| c,
    };
    const request = try wire.encodeRequest(alloc, pane, agent, c);
    const out = if (wire.ask(alloc, try wire.socketPath(alloc, home), request, 3000)) |reply| switch (reply) {
        .allow => return 0,
        .deny => |id| try wire.outputDeny(alloc, agent, id, c),
    } else try wire.outputUnreachable(alloc, agent, c);
    return emit(out);
}

fn emit(out: wire.Output) u8 {
    if (out.stdout.len > 0) std.fs.File.stdout().writeAll(out.stdout) catch {};
    if (out.stderr.len > 0) std.fs.File.stderr().writeAll(out.stderr) catch {};
    return out.exit;
}

/// Something failed before a decision: never let the call through silently.
fn failClosed(alloc: Allocator, agent: wire.Agent) u8 {
    const c: decide.Critical = .{ .group = .unreadable, .why = "Lostty's guard hit an error checking this call", .tool = "?", .input = "", .cwd = "/" };
    const out = wire.outputUnreachable(alloc, agent, c) catch return 2;
    return emit(out);
}
```

In `src/cli/ghostty.zig`:
- Add `const guard = @import("guard.zig");` after `const claude_usage = …`.
- Add an enum case after `@"claude-usage",`:
  ```zig
      // Lostty: the PreToolUse guard that stops critical agent actions
      // until you approve them (run by hooks).
      guard,
  ```
- Add `.guard => try guard.run(alloc),` to `runMain`, and `.guard => guard.Options,` to `options`.
- Add `_ = guard;` to the test block.

- [ ] **Step 5: Run the tests and a manual smoke**

Run: `zig build test -Dtest-filter="guard"`
Expected: PASS.

Run: `zig build -Demit-macos-app=false`, then do a smoke test (the app isn't listening yet, so a critical call takes the unreachable path):

```bash
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/tmp"}' | LOSTTY_SURFACE=x zig-out/bin/lostty +guard --agent=claude; echo "exit=$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push"},"cwd":"'"$PWD"'"}' | LOSTTY_SURFACE=x zig-out/bin/lostty +guard --agent=claude; echo "exit=$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push"},"cwd":"'"$PWD"'"}' | LOSTTY_SURFACE=x zig-out/bin/lostty +guard --agent=codex; echo "exit=$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push"},"cwd":"'"$PWD"'"}' | zig-out/bin/lostty +guard --agent=codex; echo "exit=$?"
```

Expected, in order:
1. `ls`: no output, `exit=0`.
2. Claude `git push`: an `"ask"` JSON line, `exit=0`.
3. Codex `git push`: "Blocked by Lostty … isn't running", `exit=2`.
4. No `LOSTTY_SURFACE`: no output, `exit=0`.

If the binary isn't at `zig-out/bin/lostty`, find it with `ls zig-out/bin`.

- [ ] **Step 6: Commit**

```bash
zig fmt src/cli/guard.zig src/cli/guard/wire.zig src/cli/ghostty.zig
git add src/cli/guard.zig src/cli/guard/wire.zig src/cli/ghostty.zig
git commit -m "lostty: guard: the +guard hook command and its socket wire

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Install the guard hook for Claude and Codex

**Files:**
- Modify: `src/cli/claude/hooks.zig`

**Interfaces:**
- Produces (changed): `Event` gains a `kind`, and `command` takes the agent:
  ```zig
  pub const Event = struct { name: []const u8, state: []const u8 = "", kind: Kind = .state, timeout: u32 = timeout_seconds };
  pub const Kind = enum { state, guard };
  pub fn command(alloc: Allocator, agent: Agent, e: Event) Allocator.Error![]u8;
  pub fn isLosttyCommand(cmd: []const u8) bool; // now also true for the guard command
  pub const guard_timeout_seconds = 15;
  ```
  The guard command: `[ -n "$LOSTTY_SURFACE" ] && [ -x "$LOSTTY_BIN" ] || exit 0; exec "$LOSTTY_BIN" +guard --agent=<agent>`. It uses `exec` with no trailing `exit 0`, because Codex needs the guard's exit code 2. The state command keeps its existing form.

- [ ] **Step 1: Write the failing tests.** Append to `src/cli/claude/hooks.zig`:

```zig
test "claude hooks: install adds the guard for Claude and Codex" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var c = try parseFixture(a, "{}");
    try std.testing.expect(try install(a, .claude, &c));
    const cout = try stringify(a, c);
    try std.testing.expect(std.mem.indexOf(u8, cout, "+guard --agent=claude") != null);
    try std.testing.expect(std.mem.indexOf(u8, cout, "\"timeout\": 15") != null);
    try std.testing.expectEqual(Status.installed, try status(a, .claude, c));

    var x = try parseFixture(a, "{}");
    try std.testing.expect(try install(a, .codex, &x));
    const xout = try stringify(a, x);
    try std.testing.expect(std.mem.indexOf(u8, xout, "+guard --agent=codex") != null);
    try std.testing.expect(std.mem.indexOf(u8, xout, "\"PreToolUse\"") != null);
    try std.testing.expectEqual(Status.installed, try status(a, .codex, x));
}

test "claude hooks: older hooks without the guard are partial" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a,
        \\{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"[ -n \"$LOSTTY_SURFACE\" ] && [ -x \"$LOSTTY_BIN\" ] && \"$LOSTTY_BIN\" +claude-state busy; exit 0","timeout":5}]}],
        \\"Stop":[{"hooks":[{"type":"command","command":"[ -n \"$LOSTTY_SURFACE\" ] && [ -x \"$LOSTTY_BIN\" ] && \"$LOSTTY_BIN\" +claude-state idle; exit 0","timeout":5}]}]}}
    );
    try std.testing.expectEqual(Status.partial, try status(a, .codex, root));
    try std.testing.expect(try install(a, .codex, &root));
    try std.testing.expectEqual(Status.installed, try status(a, .codex, root));
}

test "claude hooks: the guard command keeps its exit code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cmd = try command(a, .codex, .{ .name = "PreToolUse", .kind = .guard, .timeout = guard_timeout_seconds });
    try std.testing.expect(std.mem.indexOf(u8, cmd, "exec \"$LOSTTY_BIN\" +guard --agent=codex") != null);
    try std.testing.expect(!std.mem.endsWith(u8, cmd, "exit 0"));
    try std.testing.expect(isLosttyCommand(cmd));
}

test "claude hooks: remove takes out the guard too" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a, "{}");
    _ = try install(a, .codex, &root);
    try std.testing.expect(try remove(&root));
    try std.testing.expect(std.mem.indexOf(u8, try stringify(a, root), "+guard") == null);
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `zig build test -Dtest-filter="claude hooks"`
Expected: compile errors (the `Event` has no `kind`, and `command` has a new signature) or failures.

- [ ] **Step 3: Implement.** In `src/cli/claude/hooks.zig`:

1. Replace `pub const Event = struct { name: []const u8, state: []const u8 };` with:

```zig
pub const Kind = enum { state, guard };

pub const Event = struct {
    name: []const u8,
    /// The `+claude-state` argument (state hooks only).
    state: []const u8 = "",
    kind: Kind = .state,
    timeout: u32 = timeout_seconds,
};

pub const guard_timeout_seconds = 15;
```

   `timeout_seconds` must be declared before `Event` uses it as a default; move `pub const timeout_seconds = 5;` above `Event`.

2. Add the guard to both lists:

```zig
    .{ .name = "PreToolUse", .kind = .guard, .timeout = guard_timeout_seconds },
```

   This goes as the last element of `claude_events` and of `codex_events`. Update the doc comment over `codex_events`: Codex gets the guard on `PreToolUse` too (a deny holds in every approval mode; spec Facts).

3. Replace `command`:

```zig
/// The hook command for event `e`. A state hook is a no-op outside Lostty
/// (no LOSTTY_SURFACE) and when the binary is gone, and always exits 0. The
/// guard hook is a no-op in the same cases but otherwise `exec`s the guard,
/// so its exit code (2 blocks a Codex call) reaches the agent.
pub fn command(alloc: Allocator, agent: Agent, e: Event) Allocator.Error![]u8 {
    return switch (e.kind) {
        .state => std.fmt.allocPrint(
            alloc,
            "[ -n \"$LOSTTY_SURFACE\" ] && [ -x \"$LOSTTY_BIN\" ] && \"$LOSTTY_BIN\" +claude-state {s}; exit 0",
            .{e.state},
        ),
        .guard => std.fmt.allocPrint(
            alloc,
            "[ -n \"$LOSTTY_SURFACE\" ] && [ -x \"$LOSTTY_BIN\" ] || exit 0; exec \"$LOSTTY_BIN\" +guard --agent={s}",
            .{@tagName(agent)},
        ),
    };
}

/// Lostty's entries, in any version, mention LOSTTY_SURFACE and one of its
/// commands.
pub fn isLosttyCommand(cmd: []const u8) bool {
    if (std.mem.indexOf(u8, cmd, "LOSTTY_SURFACE") == null) return false;
    return std.mem.indexOf(u8, cmd, "+claude-state") != null or std.mem.indexOf(u8, cmd, "+guard") != null;
}
```

4. In `status`, an event name can now have two expected commands (Claude's `PreToolUse` has both the state hook and the guard). Replace `expectedFor` and its use:

```zig
/// Whether `cmd` (with `timeout`) is exactly one of Lostty's current
/// entries for `event_name`.
fn isCurrent(alloc: Allocator, agent: Agent, event_name: []const u8, cmd: []const u8, timeout: Value) Allocator.Error!bool {
    for (eventsFor(agent)) |e| {
        if (!std.mem.eql(u8, e.name, event_name)) continue;
        const exp = try command(alloc, agent, e);
        if (std.mem.eql(u8, cmd, exp) and isTimeout(timeout, e.timeout)) return true;
    }
    return false;
}

fn isTimeout(v: Value, want: u32) bool {
    return switch (v) {
        .integer => |i| i == want,
        .number_string => |s| (std.fmt.parseInt(u32, s, 10) catch 0) == want,
        else => false,
    };
}
```

   In `status`, replace the inner loop body from `const expected = …` down to the `current += 1` line with:

```zig
            for (entry.value_ptr.array.items) |group_value| {
                for (group_value.object.get("hooks").?.array.items) |hook| {
                    const cmd = hookCommand(hook) orelse continue;
                    if (!isLosttyCommand(cmd)) continue;
                    ours += 1;
                    if (try isCurrent(alloc, agent, entry.key_ptr.*, cmd, hook.object.get("timeout") orelse .null)) current += 1;
                }
            }
```

   Delete the old `expectedFor` and the old one-argument `isTimeout`.

5. In `group(...)`, take the event:

```zig
fn group(alloc: Allocator, agent: Agent, e: Event) Allocator.Error!Value {
    var hook = std.json.ObjectMap.init(alloc);
    try hook.put("type", .{ .string = "command" });
    try hook.put("command", .{ .string = try command(alloc, agent, e) });
    try hook.put("timeout", .{ .integer = e.timeout });
    var list = std.json.Array.init(alloc);
    try list.append(.{ .object = hook });
    var g = std.json.ObjectMap.init(alloc);
    try g.put("hooks", .{ .array = list });
    return .{ .object = g };
}
```

   Update both callers: `install` uses `try group(alloc, agent, e)`. `preview` builds each event's array by appending a group for every `Event` with that name, so `PreToolUse` gets both entries for Claude:

```zig
pub fn preview(alloc: Allocator, agent: Agent) Allocator.Error!Value {
    var hooks = std.json.ObjectMap.init(alloc);
    for (eventsFor(agent)) |e| {
        const gop = try hooks.getOrPut(e.name);
        if (!gop.found_existing) gop.value_ptr.* = .{ .array = std.json.Array.init(alloc) };
        try gop.value_ptr.array.append(try group(alloc, agent, e));
    }
    var root = std.json.ObjectMap.init(alloc);
    try root.put("hooks", .{ .object = hooks });
    if (agent == .claude) try root.put("statusLine", try statusLineValue(alloc));
    return .{ .object = root };
}
```

6. Fix the existing tests that break:
   - `"codex hooks: install adds only the busy and idle events"`: Codex now also gets `PreToolUse`. Rename it to `"codex hooks: install adds busy, idle and the guard"` and assert `PreToolUse` is present.
   - `"codex hooks: preview lists the two events"` becomes three.
   - `"claude hooks: command and detection"`: update calls to `command(a, .claude, .{ .name = "Stop", .state = "busy" })`.
   - Anything asserting `n` counts.

   Keep each test's intent; change only what the new events require.

- [ ] **Step 4: Run to verify they pass**

Run: `zig build test -Dtest-filter="claude hooks"` and `zig build test -Dtest-filter="codex hooks"`
Expected: PASS.

Check the CLI: `zig build -Demit-macos-app=false && zig-out/bin/lostty +claude-hooks preview --agent=codex` shows a `PreToolUse` entry with `+guard --agent=codex` and `"timeout": 15`.

- [ ] **Step 5: Commit**

```bash
zig fmt src/cli/claude/hooks.zig
git add src/cli/claude/hooks.zig
git commit -m "lostty: guard: install the guard as a PreToolUse hook for Claude and Codex

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The app's approval book

**Files:**
- Create: `macos/Sources/Features/Guard/GuardWire.swift`, `macos/Sources/Features/Guard/ApprovalBook.swift`
- Test: `macos/Tests/Guard/ApprovalBookTests.swift`

**Interfaces:**
- Consumes: the wire JSON from Task 6 (field names verbatim).
- Produces:
  ```swift
  struct GuardCheck: Codable, Equatable, Sendable {
      var v: Int; var pane: String; var agent: String; var session: String?
      var tool: String; var input: String; var cwd: String
      var repo: String?; var branch: String?
      var group: String; var why: String; var lost: String?; var reason: String?
      /// What makes two checks "exactly this": pane, tool, input, cwd.
      var key: String { get }
      var groupLabel: String { get }   // "Deleting", …, as catalog.label
  }
  struct GuardReply: Codable, Equatable, Sendable {
      var v = 1; var decision: String; var request: Int?
      static let allow: GuardReply
      static func deny(_ id: Int) -> GuardReply
  }
  struct GuardRequest: Codable, Equatable, Identifiable, Sendable {
      enum State: String, Codable, Sendable { case pending, approved, used, denied, expired }
      let id: Int; let check: GuardCheck; let created: Date
      var state: State; var decided: Date?
  }
  struct ApprovalBook: Codable, Equatable, Sendable {
      static let approvalLifetime: TimeInterval = 10 * 60
      static let requestLifetime: TimeInterval = 60 * 60
      static let historyLimit = 100
      private(set) var requests: [GuardRequest]
      private(set) var nextID: Int
      init()
      var pending: [GuardRequest] { get }                       // oldest first
      func request(_ id: Int) -> GuardRequest?
      /// The guard asks about a call. Returns .allow only by using up an
      /// approval you gave for exactly this call in the last 10 minutes.
      mutating func check(_ c: GuardCheck, now: Date) -> (reply: GuardReply, isNew: Bool)
      mutating func approve(_ id: Int, now: Date) -> Bool          // false unless pending
      mutating func deny(_ id: Int, now: Date) -> Bool             // false unless pending
      mutating func expire(now: Date) -> [Int]                     // ids that just lapsed
      /// What's stored: approvals don't survive a restart (back to pending).
      func persisted() -> ApprovalBook
  }
  ```

- [ ] **Step 1: Write the failing tests** in `macos/Tests/Guard/ApprovalBookTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ApprovalBookTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func check(_ input: String = "git push", pane: String = "P1") -> GuardCheck {
        GuardCheck(v: 1, pane: pane, agent: "claude", session: "s", tool: "Bash", input: input, cwd: "/r",
                   repo: "/r", branch: "feature", group: "leaving", why: "git push sends commits off this Mac",
                   lost: nil, reason: nil)
    }

    @Test func aNewCallIsDeniedWithARequest() {
        var book = ApprovalBook()
        let (reply, isNew) = book.check(check(), now: t0)
        #expect(reply == .deny(1))
        #expect(isNew)
        #expect(book.pending.map(\.id) == [1])
    }

    @Test func askingAgainReusesThePendingRequest() {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        let (reply, isNew) = book.check(check(), now: t0 + 5)
        #expect(reply == .deny(1))
        #expect(!isNew)
        #expect(book.pending.count == 1)
    }

    @Test func anApprovalLetsExactlyThatCallThroughOnce() {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        #expect(book.approve(1, now: t0 + 10))
        #expect(book.check(check("git push --force"), now: t0 + 20).reply == .deny(2))
        #expect(book.check(check(pane: "P2"), now: t0 + 20).reply == .deny(3))
        #expect(book.check(check(), now: t0 + 30).reply == .allow)
        #expect(book.request(1)?.state == .used)
        // Used up: the same call asks again.
        #expect(book.check(check(), now: t0 + 40).reply == .deny(4))
    }

    @Test func anApprovalLapsesAfterTenMinutes() {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        _ = book.approve(1, now: t0)
        #expect(book.check(check(), now: t0 + 601).reply == .deny(2))
        #expect(book.request(1)?.state == .expired)
    }

    @Test func requestsLapseAfterAnHour() {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        #expect(book.expire(now: t0 + 3599).isEmpty)
        #expect(book.expire(now: t0 + 3601) == [1])
        #expect(book.pending.isEmpty)
        #expect(!book.approve(1, now: t0 + 3602))
    }

    @Test func denyingStopsItAndOnlyPendingCanBeDecided() {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        #expect(book.deny(1, now: t0 + 1))
        #expect(!book.approve(1, now: t0 + 2))
        #expect(!book.deny(1, now: t0 + 2))
        #expect(book.check(check(), now: t0 + 3).reply == .deny(2))
    }

    @Test func approvalsDontSurviveARestart() throws {
        var book = ApprovalBook()
        _ = book.check(check(), now: t0)
        _ = book.approve(1, now: t0)
        let data = try JSONEncoder().encode(book.persisted())
        var loaded = try JSONDecoder().decode(ApprovalBook.self, from: data)
        #expect(loaded.request(1)?.state == .pending)
        #expect(loaded.check(check(), now: t0 + 1).reply == .deny(1))
    }

    @Test func historyIsCapped() {
        var book = ApprovalBook()
        for i in 0..<150 {
            _ = book.check(check("cmd \(i)"), now: t0)
            _ = book.deny(i + 1, now: t0)
        }
        #expect(book.requests.count <= ApprovalBook.historyLimit)
        #expect(book.nextID == 151)
    }

    @Test func wireDecodesTheGuardsRequest() throws {
        let line = #"{"v":1,"pane":"P","agent":"codex","tool":"Bash","input":"rm x","cwd":"/r","group":"deleting","why":"w","lost":"1 untracked files"}"#
        let c = try JSONDecoder().decode(GuardCheck.self, from: Data(line.utf8))
        #expect(c.agent == "codex")
        #expect(c.repo == nil)
        #expect(c.groupLabel == "Deleting")
        let reply = String(decoding: try JSONEncoder().encode(GuardReply.deny(3)), as: UTF8.self)
        #expect(reply.contains(#""decision":"deny""#))
        #expect(reply.contains(#""request":3"#))
    }
}
#endif
```

- [ ] **Step 2: Run to verify they fail**

Run: `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project macos/Lostty.xcodeproj -scheme Lostty -configuration Debug SYMROOT=$PWD/macos/build -only-testing:LosttyTests/ApprovalBookTests test 2>&1 | tail -20`
Expected: build fails (cannot find `ApprovalBook`).

- [ ] **Step 3: Implement.** `macos/Sources/Features/Guard/GuardWire.swift`:

```swift
#if os(macOS)
import Foundation

/// What `lostty +guard` sends for a critical tool call: one JSON line on
/// the guard socket (src/cli/guard/wire.zig). Field names are the wire's.
struct GuardCheck: Codable, Equatable, Sendable {
    var v: Int
    var pane: String
    var agent: String
    var session: String?
    var tool: String
    var input: String
    var cwd: String
    var repo: String?
    var branch: String?
    var group: String
    var why: String
    var lost: String?
    var reason: String?

    /// "Exactly this call": the same pane, tool, input and folder.
    var key: String { [pane, tool, cwd, input].joined(separator: "\u{1F}") }

    /// As the guard's catalog labels its groups.
    var groupLabel: String {
        switch group {
        case "deleting": "Deleting"
        case "discarding": "Throwing work away"
        case "leaving": "Leaving the Mac"
        case "merging": "Merging into a protected branch"
        case "guardrails": "Changing the guardrails"
        case "outside": "Writing outside the project"
        default: "A command Lostty can't read"
        }
    }

    var agentName: String { agent == "codex" ? "Codex" : "Claude" }
}

/// The app's only answers: let this one call through (an approval you gave
/// is used up), or not, with the request to show. There is no reply that
/// grants anything.
struct GuardReply: Codable, Equatable, Sendable {
    var v = 1
    var decision: String
    var request: Int?

    static let allow = GuardReply(decision: "allow", request: nil)
    static func deny(_ id: Int) -> GuardReply { GuardReply(decision: "deny", request: id) }
}
#endif
```

`macos/Sources/Features/Guard/ApprovalBook.swift`:

```swift
#if os(macOS)
import Foundation

/// One critical call the guard stopped, and what became of it.
struct GuardRequest: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case pending, approved, used, denied, expired }

    let id: Int
    let check: GuardCheck
    let created: Date
    var state: State
    /// When you approved or denied it, or when it lapsed.
    var decided: Date?
}

/// The guard's requests and approvals (spec §7.4–7.5). An approval covers
/// exactly one call, in one pane, once, for 10 minutes; a request nobody
/// answers lapses after an hour. Only `approve` grants, and only Lostty's
/// own UI calls it: nothing the guard sends can.
struct ApprovalBook: Codable, Equatable, Sendable {
    static let approvalLifetime: TimeInterval = 10 * 60
    static let requestLifetime: TimeInterval = 60 * 60
    static let historyLimit = 100

    private(set) var requests: [GuardRequest] = []
    private(set) var nextID = 1

    init() {}

    var pending: [GuardRequest] { requests.filter { $0.state == .pending } }

    func request(_ id: Int) -> GuardRequest? { requests.first { $0.id == id } }

    mutating func check(_ c: GuardCheck, now: Date) -> (reply: GuardReply, isNew: Bool) {
        _ = expire(now: now)
        if let i = requests.firstIndex(where: { $0.state == .approved && $0.check.key == c.key }) {
            requests[i].state = .used
            requests[i].decided = now
            return (.allow, false)
        }
        if let open = requests.first(where: { $0.state == .pending && $0.check.key == c.key }) {
            return (.deny(open.id), false)
        }
        let id = nextID
        nextID += 1
        requests.append(GuardRequest(id: id, check: c, created: now, state: .pending, decided: nil))
        trim()
        return (.deny(id), true)
    }

    mutating func approve(_ id: Int, now: Date) -> Bool { decide(id, .approved, now: now) }
    mutating func deny(_ id: Int, now: Date) -> Bool { decide(id, .denied, now: now) }

    private mutating func decide(_ id: Int, _ state: GuardRequest.State, now: Date) -> Bool {
        _ = expire(now: now)
        guard let i = requests.firstIndex(where: { $0.id == id }), requests[i].state == .pending else { return false }
        requests[i].state = state
        requests[i].decided = now
        return true
    }

    mutating func expire(now: Date) -> [Int] {
        var lapsed: [Int] = []
        for i in requests.indices {
            switch requests[i].state {
            case .pending where now.timeIntervalSince(requests[i].created) > Self.requestLifetime:
                lapsed.append(requests[i].id)
                requests[i].state = .expired
                requests[i].decided = now
            case .approved where now.timeIntervalSince(requests[i].decided ?? now) > Self.approvalLifetime:
                requests[i].state = .expired
                requests[i].decided = now
            default:
                break
            }
        }
        return lapsed
    }

    func persisted() -> ApprovalBook {
        var copy = self
        for i in copy.requests.indices where copy.requests[i].state == .approved {
            copy.requests[i].state = .pending
            copy.requests[i].decided = nil
        }
        return copy
    }

    /// Keeps every open request and the most recent decided ones.
    private mutating func trim() {
        let decided = requests.filter { $0.state != .pending && $0.state != .approved }
        let excess = requests.count - Self.historyLimit
        guard excess > 0 else { return }
        let drop = Set(decided.prefix(excess).map(\.id))
        requests.removeAll { drop.contains($0.id) }
    }
}
#endif
```

- [ ] **Step 4: Run to verify they pass**

Run: the Step 2 command.
Expected: `** TEST SUCCEEDED **`, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Guard/GuardWire.swift macos/Sources/Features/Guard/ApprovalBook.swift macos/Tests/Guard/ApprovalBookTests.swift
git commit -m "lostty: guard: the app's book of requests and one-time approvals

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: The guard socket in the app

**Files:**
- Create: `macos/Sources/Features/Guard/GuardServer.swift`
- Test: `macos/Tests/Guard/GuardServerTests.swift`

**Interfaces:**
- Consumes: `GuardCheck`, `GuardReply` (Task 8).
- Produces:
  ```swift
  final class GuardServer: @unchecked Sendable {
      typealias Handler = @Sendable (GuardCheck) async -> GuardReply
      static func defaultPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL  // ~/.config/lostty/coord/guard.sock
      init(path: URL, handler: @escaping Handler)
      func start() throws   // creates the folder (0700), replaces a stale socket, binds (0600), listens
      func stop()
  }
  ```
  Each connection is one request line, then one reply line, then close. A peer with a different uid is closed without a reply. A line that doesn't decode as a `GuardCheck` gets `{"v":1,"decision":"deny","request":0}`, which the guard reads as nonsense and fails closed. Reads time out after 2 seconds.

- [ ] **Step 1: Write the failing test** in `macos/Tests/Guard/GuardServerTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct GuardServerTests {
    /// Sun paths are short (104 bytes): use /tmp, not the long temp folder.
    func socketPath() -> URL {
        URL(fileURLWithPath: "/tmp/lostty-guard-test-\(UUID().uuidString.prefix(8))/g.sock")
    }

    func send(_ line: String, to path: URL) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(fd >= 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            _ = path.path.withCString { strncpy(raw.baseAddress!.assumingMemoryBound(to: CChar.self), $0, raw.count - 1) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(ok == 0)
        _ = (line + "\n").withCString { write(fd, $0, strlen($0)) }
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        return String(decoding: buf.prefix(max(n, 0)), as: UTF8.self)
    }

    @Test func answersOneLinePerConnection() throws {
        let path = socketPath()
        let server = GuardServer(path: path) { check in
            check.input == "git push" ? .deny(7) : .allow
        }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }

        let push = #"{"v":1,"pane":"P","agent":"claude","tool":"Bash","input":"git push","cwd":"/r","group":"leaving","why":"w"}"#
        #expect(try send(push, to: path).contains(#""request":7"#))
        let other = #"{"v":1,"pane":"P","agent":"claude","tool":"Bash","input":"x","cwd":"/r","group":"leaving","why":"w"}"#
        #expect(try send(other, to: path).contains(#""decision":"allow""#))
        #expect(try send("not json", to: path).contains(#""request":0"#))
    }

    @Test func socketIsPrivate() throws {
        let path = socketPath()
        let server = GuardServer(path: path) { _ in .allow }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let dir = try FileManager.default.attributesOfItem(atPath: path.deletingLastPathComponent().path)
        #expect((dir[.posixPermissions] as? Int) == 0o700)
        let sock = try FileManager.default.attributesOfItem(atPath: path.path)
        #expect((sock[.posixPermissions] as? Int) == 0o600)
    }

    @Test func replacesAStaleSocket() throws {
        let path = socketPath()
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path.path, contents: Data("stale".utf8))
        let server = GuardServer(path: path) { _ in .allow }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let ok = #"{"v":1,"pane":"P","agent":"claude","tool":"Bash","input":"x","cwd":"/r","group":"leaving","why":"w"}"#
        #expect(try send(ok, to: path).contains("allow"))
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: the Task 8 test command with `-only-testing:LosttyTests/GuardServerTests`.
Expected: build fails (cannot find `GuardServer`).

- [ ] **Step 3: Implement** `macos/Sources/Features/Guard/GuardServer.swift`:

```swift
#if os(macOS)
import Darwin
import Foundation

/// The app's end of the guard socket (spec §7.5). `lostty +guard` connects,
/// sends one `GuardCheck` line and reads one `GuardReply` line. The socket
/// can only *ask*: the handler answers from the approval book, and nothing
/// a caller sends can grant. Only your own user's processes may connect.
final class GuardServer: @unchecked Sendable {
    typealias Handler = @Sendable (GuardCheck) async -> GuardReply

    static func defaultPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".config/lostty/coord/guard.sock")
    }

    private let path: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.lawliang.lostty.guard-server")
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    init(path: URL, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    enum Failure: Error { case socket(Int32), pathTooLong }

    func start() throws {
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        unlink(path.path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(errno) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw Failure.pathTooLong
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            bytes.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let e = errno
            close(fd)
            throw Failure.socket(e)
        }
        chmod(path.path, 0o600)
        guard listen(fd, 16) == 0 else {
            let e = errno
            close(fd)
            throw Failure.socket(e)
        }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        listenFD = -1
        unlink(path.path)
    }

    private func acceptOne() {
        let conn = accept(listenFD, nil, nil)
        guard conn >= 0 else { return }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(conn, &uid, &gid) == 0, uid == getuid() else {
            close(conn)
            return
        }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(conn, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(conn, SOL_SOCKET, SO_NOSIGPIPE, [Int32(1)], socklen_t(MemoryLayout<Int32>.size))
        let line = Self.readLine(conn)
        let handler = self.handler
        Task.detached {
            let reply: GuardReply
            if let line, let check = try? JSONDecoder().decode(GuardCheck.self, from: line) {
                reply = await handler(check)
            } else {
                reply = .deny(0)
            }
            var out = (try? JSONEncoder().encode(reply)) ?? Data()
            out.append(0x0A)
            out.withUnsafeBytes { _ = write(conn, $0.baseAddress, $0.count) }
            close(conn)
        }
    }

    /// Up to the first newline, at most 1 MB; nil on timeout or error.
    private static func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while data.count < 1 << 20 {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf.prefix(n))
            if let nl = data.firstIndex(of: 0x0A) { return data.prefix(upTo: nl) }
        }
        return data.isEmpty ? nil : data
    }
}
#endif
```

- [ ] **Step 4: Run to verify it passes**

Run: the Step 2 command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Guard/GuardServer.swift macos/Tests/Guard/GuardServerTests.swift
git commit -m "lostty: guard: the app's guard socket, for your user only

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Guard runtime: requests, notifications, outcomes

**Files:**
- Create: `macos/Sources/Features/Guard/GuardRuntime.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Features/Claude/ClaudeRuntime.swift`
- Test: `macos/Tests/Guard/GuardRuntimeTests.swift`

**Interfaces:**
- Consumes: `ApprovalBook`, `GuardCheck`, `GuardReply`, `GuardServer` (Tasks 8–9); `AppDelegate.findSurface(forUUID:)`, `Ghostty.Surface.sendText(_:)` / `sendKeyEvent(_:)`, `Ghostty.Input.KeyEvent(key:action:mods:)`, `PaneFocus.focus(_:)` (existing).
- Produces:
  ```swift
  @MainActor final class GuardRuntime: ObservableObject {
      static let shared: GuardRuntime
      static let category = "com.lawliang.lostty.guard"
      static let denyAction = "com.lawliang.lostty.guard.deny"
      @Published private(set) var book: ApprovalBook
      /// Panes whose agent has asked the guard something and is still running, by agent ("claude"/"codex").
      @Published private(set) var agentPanes: [UUID: String]
      /// Agents whose guard hook is missing from their settings (Task 12 sets it).
      @Published var disconnected: Set<HookAgent>
      struct Effects {           // injectable for tests
          var post: @MainActor (GuardRequest) -> Void
          var withdraw: @MainActor (Int) -> Void
          var type: @MainActor (UUID, String) -> Bool   // typed into a pane? false when the pane is gone
          var save: @MainActor (ApprovalBook) -> Void
          var now: () -> Date
          static let live: Effects
      }
      init(book: ApprovalBook = .init(), effects: Effects = .live)
      func start()                               // load the saved book, start the server, a 60 s expiry timer
      func handle(_ c: GuardCheck) -> GuardReply // the server's handler
      func approve(_ id: Int)
      func deny(_ id: Int)
      func agentGone(_ pane: UUID)
      func pending(for pane: UUID) -> GuardRequest?
      /// Routes a notification response; true when it was a guard one.
      func handle(_ response: UNNotificationResponse) -> Bool
      static func outcomeText(_ id: Int, approved: Bool) -> String
  }
  ```
  `outcomeText(42, approved: true)` returns `"Approved #42 in Lostty. Run it now, exactly as before."`. `outcomeText(42, approved: false)` returns `"Denied #42 in Lostty. Don't run it, and don't work around it."`.

- [ ] **Step 1: Write the failing tests** in `macos/Tests/Guard/GuardRuntimeTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct GuardRuntimeTests {
    final class Log {
        var posted: [Int] = []
        var withdrawn: [Int] = []
        var typed: [(UUID, String)] = []
        var paneAlive = true
        var now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    }

    func make(_ log: Log) -> GuardRuntime {
        GuardRuntime(effects: .init(
            post: { log.posted.append($0.id) },
            withdraw: { log.withdrawn.append($0) },
            type: { pane, text in
                guard log.paneAlive else { return false }
                log.typed.append((pane, text))
                return true
            },
            save: { _ in },
            now: { log.now }
        ))
    }

    let pane = UUID()

    func check(_ input: String = "git push") -> GuardCheck {
        GuardCheck(v: 1, pane: pane.uuidString, agent: "claude", session: nil, tool: "Bash", input: input,
                   cwd: "/r", repo: nil, branch: nil, group: "leaving", why: "w", lost: nil, reason: nil)
    }

    @Test func aNewRequestIsPostedOnceAndTheAgentPaneIsRemembered() {
        let log = Log()
        let rt = make(log)
        #expect(rt.handle(check()) == .deny(1))
        #expect(rt.handle(check()) == .deny(1))
        #expect(log.posted == [1])
        #expect(rt.agentPanes[pane] == "claude")
        #expect(rt.pending(for: pane)?.id == 1)
    }

    @Test func approvingTypesTheOutcomeAndLetsTheRetryThrough() {
        let log = Log()
        let rt = make(log)
        _ = rt.handle(check())
        rt.approve(1)
        #expect(log.withdrawn == [1])
        #expect(log.typed.count == 1)
        #expect(log.typed.first?.1 == GuardRuntime.outcomeText(1, approved: true))
        #expect(rt.handle(check()) == .allow)
    }

    @Test func denyingTypesTheOutcome() {
        let log = Log()
        let rt = make(log)
        _ = rt.handle(check())
        rt.deny(1)
        #expect(log.typed.first?.1 == GuardRuntime.outcomeText(1, approved: false))
        #expect(rt.handle(check()) == .deny(2))
    }

    @Test func nothingIsTypedOnceTheAgentHasGone() {
        let log = Log()
        let rt = make(log)
        _ = rt.handle(check())
        rt.agentGone(pane)
        rt.approve(1)
        #expect(log.typed.isEmpty)
        // The approval still holds for a retry within 10 minutes.
        #expect(rt.handle(check()) == .allow)
    }

    @Test func outcomeTexts() {
        #expect(GuardRuntime.outcomeText(42, approved: true) == "Approved #42 in Lostty. Run it now, exactly as before.")
        #expect(GuardRuntime.outcomeText(42, approved: false) == "Denied #42 in Lostty. Don't run it, and don't work around it.")
    }
}
#endif
```

- [ ] **Step 2: Run to verify they fail**

Run: the Task 8 test command with `-only-testing:LosttyTests/GuardRuntimeTests`.
Expected: build fails (cannot find `GuardRuntime`).

- [ ] **Step 3: Implement** `macos/Sources/Features/Guard/GuardRuntime.swift`:

```swift
#if os(macOS)
import AppKit
import Foundation
import UserNotifications

/// The guard in the app (spec §7.4): answers the guard socket from the
/// approval book, shows each new request (a notification with Deny only,
/// the pane's badge, the Branches panel), and when you decide, tells the
/// agent by typing one line into its pane, only while that pane's agent
/// still runs. Your click does the typing, so it speaks for you.
@MainActor
final class GuardRuntime: ObservableObject {
    static let shared = GuardRuntime()
    static let category = "com.lawliang.lostty.guard"
    static let denyAction = "com.lawliang.lostty.guard.deny"

    @Published private(set) var book: ApprovalBook
    @Published private(set) var agentPanes: [UUID: String] = [:]
    @Published var disconnected: Set<HookAgent> = []

    struct Effects {
        var post: @MainActor (GuardRequest) -> Void
        var withdraw: @MainActor (Int) -> Void
        var type: @MainActor (UUID, String) -> Bool
        var save: @MainActor (ApprovalBook) -> Void
        var now: () -> Date

        static let live = Effects(
            post: { GuardRuntime.postNotification($0) },
            withdraw: { id in
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [GuardRuntime.notificationID(id)])
            },
            type: { pane, text in GuardRuntime.typeIntoPane(pane, text) },
            save: { GuardRuntime.save($0) },
            now: Date.init
        )
    }

    private let effects: Effects
    private var server: GuardServer?
    private var expiryTimer: Timer?

    init(book: ApprovalBook = .init(), effects: Effects = .live) {
        self.book = book
        self.effects = effects
    }

    // MARK: Lifecycle

    static var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty/guard-requests.json")
    }

    func start() {
        if let data = try? Data(contentsOf: Self.storeURL),
           let saved = try? JSONDecoder().decode(ApprovalBook.self, from: data) {
            book = saved
        }
        let server = GuardServer(path: GuardServer.defaultPath()) { check in
            await MainActor.run { GuardRuntime.shared.handle(check) }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            Ghostty.logger.error("guard: socket failed to start: \(String(describing: error))")
        }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { GuardRuntime.shared.tick() }
        }
    }

    private func tick() {
        for id in book.expire(now: effects.now()) { effects.withdraw(id) }
        effects.save(book.persisted())
    }

    // MARK: Requests

    func handle(_ c: GuardCheck) -> GuardReply {
        if let pane = UUID(uuidString: c.pane) { agentPanes[pane] = c.agent }
        let (reply, isNew) = book.check(c, now: effects.now())
        if isNew, let id = reply.request, let request = book.request(id) { effects.post(request) }
        effects.save(book.persisted())
        return reply
    }

    func approve(_ id: Int) { decide(id, approved: true) }
    func deny(_ id: Int) { decide(id, approved: false) }

    private func decide(_ id: Int, approved: Bool) {
        let now = effects.now()
        let ok = approved ? book.approve(id, now: now) : book.deny(id, now: now)
        guard ok, let request = book.request(id) else { return }
        effects.withdraw(id)
        effects.save(book.persisted())
        guard let pane = UUID(uuidString: request.check.pane), agentPanes[pane] != nil else { return }
        _ = effects.type(pane, Self.outcomeText(id, approved: approved))
    }

    func agentGone(_ pane: UUID) {
        agentPanes[pane] = nil
    }

    func pending(for pane: UUID) -> GuardRequest? {
        book.pending.first { $0.check.pane == pane.uuidString }
    }

    static func outcomeText(_ id: Int, approved: Bool) -> String {
        approved
            ? "Approved #\(id) in Lostty. Run it now, exactly as before."
            : "Denied #\(id) in Lostty. Don't run it, and don't work around it."
    }

    // MARK: Notifications

    static func notificationID(_ id: Int) -> String { "lostty-guard-\(id)" }

    static func postNotification(_ request: GuardRequest) {
        let content = UNMutableNotificationContent()
        content.title = "\(request.check.agentName) needs your approval · #\(request.id)"
        content.subtitle = request.check.groupLabel
        content.body = request.check.input
        content.categoryIdentifier = category
        content.sound = .default
        content.userInfo = ["lostty": "guard", "request": request.id, "surface": request.check.pane]
        let note = UNNotificationRequest(identifier: notificationID(request.id), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(note)
    }

    /// Deny straight from the banner; anything else opens the request,
    /// since approving means seeing the whole command (spec §7.4).
    func handle(_ response: UNNotificationResponse) -> Bool {
        let info = response.notification.request.content.userInfo
        guard info["lostty"] as? String == "guard", let id = info["request"] as? Int else { return false }
        switch response.actionIdentifier {
        case Self.denyAction: deny(id)
        case UNNotificationDismissActionIdentifier: break
        default: GuardRequestWindow.show(id)
        }
        return true
    }

    // MARK: Typing and saving

    static func typeIntoPane(_ pane: UUID, _ text: String) -> Bool {
        guard let surface = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: pane),
              let model = surface.surfaceModel else { return false }
        model.sendText(text)
        model.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .press, mods: []))
        model.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .release, mods: []))
        return true
    }

    static func save(_ book: ApprovalBook) {
        let url = storeURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(book) { try? data.write(to: url, options: .atomic) }
    }
}
#endif
```

If `Ghostty.Input.KeyEvent`'s initializer or `Ghostty.Input.Action` names differ from `(key:action:mods:)` / `.press` / `.release`, use the form that `macos/Sources/Features/App Intents/InputIntent.swift` uses. Before writing `typeIntoPane`, check whether one press event is enough (as `KeyEventIntent` sends), and drop the release if so.

`GuardRequestWindow.show(_:)` arrives in Task 11. Until then, add a temporary stub at the bottom of `GuardRuntime.swift` so this task builds:

```swift
@MainActor enum GuardRequestWindow { static func show(_ id: Int) {} }
```

Task 11 deletes it.

In `ClaudeRuntime.swift`, add next to `turnEnded`:

```swift
    /// A pane's agent exited (SessionEnd, or the shell reported the command
    /// finished): the guard stops typing outcomes into it. Set at launch.
    var agentGone: @MainActor (UUID) -> Void = { _ in }
```

Call `agentGone(id)` in `commandFinished(_:)` and `surfaceClosed(_:)`, and in `userVarChanged` when the decoded state is `.exit`. Put each call at the top of its function body or branch, so it runs whatever else happens.

In `AppDelegate.swift`:
1. Where the notification categories are registered (around lines 284–299, the `UNNotificationCategory` for `Ghostty.userNotificationCategory`), add a second category and pass both to `setNotificationCategories`:
   ```swift
   let guardDeny = UNNotificationAction(identifier: GuardRuntime.denyAction, title: "Deny", options: [.destructive])
   let guardCategory = UNNotificationCategory(identifier: GuardRuntime.category, actions: [guardDeny], intentIdentifiers: [], options: [.customDismissAction])
   ```
2. At the top of `userNotificationCenter(_:didReceive:withCompletionHandler:)` (around :1029):
   ```swift
   if GuardRuntime.shared.handle(response) { completionHandler(); return }
   ```
3. In `willPresent` (around :1038), before the other checks, always present guard notifications:
   ```swift
   if notification.request.content.userInfo["lostty"] as? String == "guard" {
       completionHandler([.banner, .sound, .list]); return
   }
   ```
4. Where `HookNotifications.checkAtLaunch()` is called (around :378), add:
   ```swift
   GuardRuntime.shared.start()
   ClaudeRuntime.shared.agentGone = { GuardRuntime.shared.agentGone($0) }
   ```

- [ ] **Step 4: Run to verify they pass, and that the app builds**

Run: the Step 2 command, then `macos/build.nu`.
Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Guard/GuardRuntime.swift macos/Tests/Guard/GuardRuntimeTests.swift macos/Sources/App/macOS/AppDelegate.swift macos/Sources/Features/Claude/ClaudeRuntime.swift
git commit -m "lostty: guard: answer the guard, notify, and tell the agent what you decided

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: The request window, the Branches panel section, the pane badge

**Files:**
- Create: `macos/Sources/Features/Guard/GuardRequestView.swift`, `macos/Sources/Features/Guard/GuardBadgeOverlay.swift`
- Modify: `macos/Sources/Features/Guard/GuardRuntime.swift` (remove the stub), `macos/Sources/Features/Branches/BranchesPanel.swift`, `macos/Sources/Ghostty/Surface View/SurfaceView.swift`
- Test: `macos/Tests/Guard/GuardRequestViewTests.swift`

**Interfaces:**
- Consumes: `GuardRuntime.shared` (`book`, `approve`, `deny`, `pending(for:)`, `disconnected`, `agentPanes`), `GuardRequest`, `PaneFocus.focus(_:)`.
- Produces:
  ```swift
  /// The facts a request shows, in order, as label/value pairs (pure, testable).
  struct GuardRequestFacts { static func rows(_ r: GuardRequest) -> [(label: String, value: String)] }
  struct GuardRequestView: View { let id: Int }                 // detail with Approve / Deny
  @MainActor enum GuardRequestWindow { static func show(_ id: Int) }
  struct GuardApprovalsSection: View {}                          // for the Branches panel
  struct GuardBadgeOverlay: View { let surfaceID: UUID }
  ```

Detail content, top to bottom:
- **Title:** "<Agent> wants to: <group label>" and "Request #N".
- **The exact input,** in a monospaced, selectable, scrollable box (never truncated).
- **Facts:**
  - Why ("why")
  - What would be lost (if any)
  - Folder (cwd)
  - Repo and branch (if any)
  - Pane (its name, when the pane can still be found)
  - How it came about: "You prompted it" in step 1. Messages and rules add more in step 2.
  - The agent's reason, if any, labeled **"The agent says"** and in italics, so it reads as the agent's words.
- **Buttons:** **Deny** (the cancel and default button, so Return and Escape both deny) and **Approve**, which is never the default.
- If the request is no longer pending, the buttons are replaced by its state ("Approved", "Denied", "Lapsed", "Used").

There is no "approve all" anywhere.

- [ ] **Step 1: Write the failing test** in `macos/Tests/Guard/GuardRequestViewTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct GuardRequestViewTests {
    func request(lost: String? = "3 untracked files", reason: String? = "Clear the cache", repo: String? = "/r") -> GuardRequest {
        GuardRequest(id: 4, check: GuardCheck(v: 1, pane: UUID().uuidString, agent: "claude", session: nil, tool: "Bash",
                                              input: "rm -rf cache", cwd: "/r/sub", repo: repo, branch: "feature",
                                              group: "deleting", why: "deletes files git can't restore", lost: lost, reason: reason),
                     created: Date(), state: .pending, decided: nil)
    }

    @Test func factsInOrderWithTheAgentsWordsLabeled() {
        let rows = GuardRequestFacts.rows(request())
        #expect(rows.map(\.label) == ["Why", "Would lose", "Folder", "Repo", "How it came about", "The agent says"])
        #expect(rows.first { $0.label == "Repo" }?.value == "/r · feature")
        #expect(rows.last?.value == "Clear the cache")
    }

    @Test func optionalFactsAreLeftOut() {
        let rows = GuardRequestFacts.rows(request(lost: nil, reason: nil, repo: nil))
        #expect(rows.map(\.label) == ["Why", "Folder", "How it came about"])
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: the Task 8 test command with `-only-testing:LosttyTests/GuardRequestViewTests`.
Expected: build fails (cannot find `GuardRequestFacts`).

- [ ] **Step 3: Implement** `macos/Sources/Features/Guard/GuardRequestView.swift`:

```swift
#if os(macOS)
import AppKit
import SwiftUI

enum GuardRequestFacts {
    static func rows(_ r: GuardRequest) -> [(label: String, value: String)] {
        let c = r.check
        var rows: [(String, String)] = [("Why", c.why)]
        if let lost = c.lost { rows.append(("Would lose", lost)) }
        rows.append(("Folder", c.cwd))
        if let repo = c.repo { rows.append(("Repo", [repo, c.branch].compactMap { $0 }.joined(separator: " · "))) }
        rows.append(("How it came about", "You prompted it"))
        if let reason = c.reason { rows.append(("The agent says", reason)) }
        return rows
    }
}

/// One guard request in full: what the agent wants to run, and why it's
/// critical. Deny is the default; Approve never is (spec §7.4).
struct GuardRequestView: View {
    let id: Int
    var onDone: () -> Void = {}
    @ObservedObject private var runtime = GuardRuntime.shared

    var body: some View {
        if let request = runtime.book.request(id) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(request.check.agentName) wants to: \(request.check.groupLabel)").font(.headline)
                    Text("Request #\(request.id)").font(.subheadline).foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(request.check.input)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 44, maxHeight: 160)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(Array(GuardRequestFacts.rows(request).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.label).foregroundStyle(.secondary)
                            if row.label == "The agent says" {
                                Text(row.value).italic().textSelection(.enabled)
                            } else {
                                Text(row.value).textSelection(.enabled)
                            }
                        }
                    }
                }
                .font(.callout)
                HStack {
                    Spacer()
                    if request.state == .pending {
                        Button("Approve") { runtime.approve(id); onDone() }
                        Button("Deny", role: .cancel) { runtime.deny(id); onDone() }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Text(request.state.label).foregroundStyle(.secondary)
                        Button("Close") { onDone() }.keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(16)
            .frame(width: 460)
        } else {
            Text("This request is gone.").padding(16)
        }
    }
}

extension GuardRequest.State {
    var label: String {
        switch self {
        case .pending: "Waiting"
        case .approved: "Approved"
        case .used: "Approved and used"
        case .denied: "Denied"
        case .expired: "Lapsed"
        }
    }
}

/// A small window per request, brought to the front when opened again.
@MainActor
enum GuardRequestWindow {
    private static var windows: [Int: NSWindow] = [:]

    static func show(_ id: Int) {
        NSApp.activate(ignoringOtherApps: true)
        if let w = windows[id] {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Lostty Guard · #\(id)"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: GuardRequestView(id: id) { [weak w] in w?.close() })
        w.center()
        windows[id] = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { windows[id] = nil }
        }
        w.makeKeyAndOrderFront(nil)
    }
}

/// The Branches panel's "Approvals" section: every waiting request, oldest
/// first. Open shows the detail; Deny is one click. No "approve all".
struct GuardApprovalsSection: View {
    @ObservedObject private var runtime = GuardRuntime.shared

    var body: some View {
        let pending = runtime.book.pending
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Approvals").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(pending) { r in
                    HStack(spacing: 8) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("#\(r.id) · \(r.check.groupLabel)").font(.caption.weight(.medium))
                            Text(r.check.input).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        Button("Open") { GuardRequestWindow.show(r.id) }
                        Button("Deny") { runtime.deny(r.id) }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
#endif
```

Delete the temporary `GuardRequestWindow` stub from `GuardRuntime.swift`.

`macos/Sources/Features/Guard/GuardBadgeOverlay.swift`:

```swift
#if os(macOS)
import SwiftUI

/// A pane's guard badges, top right: amber while one of its calls waits
/// for you (click to open it), red when its agent's guard hook is missing.
struct GuardBadgeOverlay: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = GuardRuntime.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let r = runtime.pending(for: surfaceID) {
                Button { GuardRequestWindow.show(r.id) } label: {
                    Label("Needs your approval · #\(r.id)", systemImage: "hand.raised.fill")
                }
                .buttonStyle(.plain)
                .badgeStyle(.orange)
            }
            if let agent = runtime.agentPanes[surfaceID], let kind = HookAgent(rawValue: agent),
               runtime.disconnected.contains(kind) {
                Label("Guard disconnected", systemImage: "exclamationmark.shield.fill").badgeStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

private extension View {
    func badgeStyle(_ color: Color) -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.9)))
    }
}
#endif
```

In `SurfaceView.swift`, right after the `ClaudeReadyOverlay(surfaceID: surfaceView.id, cellSize: surfaceView.cellSize)` line (around :245, inside the same `#if canImport(AppKit)`), add:

```swift
                GuardBadgeOverlay(surfaceID: surfaceView.id)
```

In `BranchesPanel.swift`, put `GuardApprovalsSection()` directly below `BranchesHeader` (above the `Divider()`), so waiting approvals show whatever the panel's status is.

- [ ] **Step 4: Run to verify the test passes and the app builds**

Run: the Step 2 command, then `macos/build.nu`.
Expected: `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Guard macos/Tests/Guard/GuardRequestViewTests.swift macos/Sources/Features/Branches/BranchesPanel.swift "macos/Sources/Ghostty/Surface View/SurfaceView.swift"
git commit -m "lostty: guard: the request window, the Approvals section and pane badges

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Guard hook health

**Files:**
- Create: `macos/Sources/Features/Guard/GuardHookWatch.swift`
- Modify: `macos/Sources/Features/Guard/GuardRuntime.swift` (start the watch)
- Test: `macos/Tests/Guard/GuardHookWatchTests.swift`

**Interfaces:**
- Consumes: `ClaudeHooksCLI().status(agent:) -> ClaudeHooksStatus?`, `HookAgent` (`configDirectory`), `HookNotifications.missing(_:connect:)` and `LosttyNotifications.shared.post(_:)` (existing; read `HookNotifications.swift` for the exact `missing` signature before using it), `GuardRuntime.shared.disconnected`.
- Produces:
  ```swift
  enum GuardHealth {
      /// Agents whose guard was installed before and isn't now: the ones to flag.
      static func newlyDisconnected(previous: [HookAgent: ClaudeHooksStatus], current: [HookAgent: ClaudeHooksStatus]) -> Set<HookAgent>
      /// Every agent whose hooks aren't fully installed (status other than .installed), among those present.
      static func disconnected(_ current: [HookAgent: ClaudeHooksStatus]) -> Set<HookAgent>
  }
  @MainActor final class GuardHookWatch {
      init(onChange: @escaping @MainActor () -> Void)
      func start()   // watches ~/.claude and ~/.codex folders (writes, renames), debounced 0.5 s
      func stop()
  }
  ```
  Behavior: at start and on each change, `GuardRuntime` runs `status` for each installed agent off the main thread. It then sets `disconnected = GuardHealth.disconnected(current)`. For each agent in `newlyDisconnected`, it posts the existing "hooks missing → Connect" bubble, so you can reconnect with one click. The existing launch-time check already offers Connect on launch, so don't post a second bubble at launch: only post on a change made while the app runs.

- [ ] **Step 1: Write the failing test** in `macos/Tests/Guard/GuardHookWatchTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct GuardHookWatchTests {
    @Test func flagsOnlyAgentsThatLostTheirHooks() {
        let before: [HookAgent: ClaudeHooksStatus] = [.claude: .installed, .codex: .installed]
        let after: [HookAgent: ClaudeHooksStatus] = [.claude: .partial, .codex: .installed]
        #expect(GuardHealth.newlyDisconnected(previous: before, current: after) == [.claude])
        #expect(GuardHealth.disconnected(after) == [.claude])
    }

    @Test func neverInstalledIsDisconnectedButNotNewlySo() {
        let before: [HookAgent: ClaudeHooksStatus] = [.codex: .notInstalled]
        let after: [HookAgent: ClaudeHooksStatus] = [.codex: .notInstalled]
        #expect(GuardHealth.newlyDisconnected(previous: before, current: after).isEmpty)
        #expect(GuardHealth.disconnected(after) == [.codex])
    }

    @Test func reconnectingClearsIt() {
        let after: [HookAgent: ClaudeHooksStatus] = [.claude: .installed]
        #expect(GuardHealth.disconnected(after).isEmpty)
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: the Task 8 test command with `-only-testing:LosttyTests/GuardHookWatchTests`.
Expected: build fails (cannot find `GuardHealth`).

- [ ] **Step 3: Implement** `macos/Sources/Features/Guard/GuardHookWatch.swift`:

```swift
#if os(macOS)
import Foundation

enum GuardHealth {
    static func newlyDisconnected(previous: [HookAgent: ClaudeHooksStatus], current: [HookAgent: ClaudeHooksStatus]) -> Set<HookAgent> {
        Set(current.compactMap { agent, status in
            previous[agent] == .installed && status != .installed ? agent : nil
        })
    }

    static func disconnected(_ current: [HookAgent: ClaudeHooksStatus]) -> Set<HookAgent> {
        Set(current.compactMap { $0.value == .installed ? nil : $0.key })
    }
}

/// Watches the agents' settings folders, so a guard hook that disappears
/// (an agent editing its own settings, a dotfile sync) shows at once
/// (spec §7.6). Folder-level, like SkinConfigStore's watcher, since editors
/// and the CLI replace these files by rename.
@MainActor
final class GuardHookWatch {
    private let onChange: @MainActor () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for agent in HookAgent.allCases {
            let dir = home.appendingPathComponent(agent.configDirectory).path
            let fd = open(dir, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.schedule() } }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.onChange() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
#endif
```

A folder watch fires when files in it are added, removed or renamed. That covers the atomic rename `+claude-hooks` and most editors use. An in-place write to `settings.json` doesn't change the folder, so at launch, also open each existing settings file with `O_EVTONLY` and watch it for `.write` the same way. Re-arm it after a rename or delete, as `SkinConfigStore.armFileWatcher()` does; read that function and mirror it.

In `GuardRuntime`:

```swift
    private var hookWatch: GuardHookWatch?
    private var lastStatus: [HookAgent: ClaudeHooksStatus] = [:]

    private func checkHooks(announce: Bool) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let agents = HookAgent.allCases.filter {
            FileManager.default.fileExists(atPath: home.appendingPathComponent($0.configDirectory).path)
        }
        Task.detached {
            var current: [HookAgent: ClaudeHooksStatus] = [:]
            for agent in agents { current[agent] = ClaudeHooksCLI().status(agent: agent) ?? .unreadable }
            await MainActor.run {
                let rt = GuardRuntime.shared
                let lost = GuardHealth.newlyDisconnected(previous: rt.lastStatus, current: current)
                rt.lastStatus = current
                rt.disconnected = GuardHealth.disconnected(current)
                if announce { for agent in lost { HookNotifications.announceMissing(agent) } }
            }
        }
    }
```

At the end of `start()`:

```swift
        checkHooks(announce: false)
        let watch = GuardHookWatch { GuardRuntime.shared.checkHooks(announce: true) }
        watch.start()
        hookWatch = watch
```

`HookNotifications.announceMissing(_:)` is a small new static func in `HookNotifications.swift`. It posts exactly what `checkAtLaunch` posts for one missing agent: `LosttyNotifications.shared.post(missing(agent, connect: { connect(agent) }))`. Adapt the call to `missing`'s real signature.

- [ ] **Step 4: Run to verify the tests pass and the app builds**

Run: the Step 2 command, then `macos/build.nu`.
Expected: `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Guard macos/Tests/Guard/GuardHookWatchTests.swift macos/Sources/Features/Notifications/HookNotifications.swift
git commit -m "lostty: guard: flag panes whose guard hook goes missing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Docs and the end-to-end check

**Files:**
- Modify: `SKINS.md` (a "Guard" section after "Claude Trace")

- [ ] **Step 1: Write the "Guard" section** in `SKINS.md`, after the Claude Trace section:

```markdown
## Guard

In every Claude Code and Codex pane, Lostty stops a critical action before
it runs and asks you, even when the agent skips its own permission
prompts:

- **Deleting what git can't get back:** untracked or ignored files,
  anything outside the repo, uncommitted changes, `git clean`, deleting a
  branch whose commits are nowhere else, dropping a stash. Deleting a
  committed file goes through: git can restore it.
- **Throwing work away:** `git reset --hard`, `checkout`/`restore` over
  changes, `rebase`, amending a pushed commit.
- **Leaving the Mac:** every `git push`, `gh pr/issue create`, publishing
  a package, scripts you list.
- **Merging into a protected branch** (`main`, `master`, and ones you add).
- **Changing the guardrails:** agent settings, hook files, `~/.config/lostty`,
  `~/.ssh`, the Keychain.
- **Writing outside the project** (temp folders excepted).

The agent is told it's blocked and to carry on with other work. You get a
notification (Deny right there, or click to see the whole request), an
amber badge on the pane, and the request in the Branches panel. Approve it
there, and Lostty types "Approved #N" into the agent's pane; the agent runs
that exact call once. An approval lasts 10 minutes; a request nobody
answers lapses after an hour. Agents have no way to approve.

If Lostty isn't running (say, during Restart to Update), Claude asks you in
its own prompt and Codex stays blocked until Lostty is back.

Settings live in `~/.config/lostty/guard.json`:

    {
      "push": "all",
      "protectedBranches": ["release"],
      "commands": ["deploy.sh"],
      "deletable": ["vendor"],
      "repos": {
        "/Users/you/projectrepos/app": { "push": "protected" }
      }
    }

`"push": "protected"` asks only for force pushes, tags, deletes and pushes
to protected branches. `deletable` folders (by default `node_modules`,
`zig-out`, `.zig-cache`, `DerivedData`, `.build`, `__pycache__`) can be
deleted without asking. The guard is Connect's `PreToolUse` hook; Codex
asks you to trust it the first time. It defends against mistakes and
misled agents, not a process set on getting around it: it isn't a
sandbox.
```

- [ ] **Step 2: Build everything and run all guard tests**

```bash
zig build -Demit-macos-app=false
zig build test -Dtest-filter="guard"
zig build test -Dtest-filter="claude hooks"
zig build test -Dtest-filter="codex hooks"
macos/build.nu
env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project macos/Lostty.xcodeproj -scheme Lostty -configuration Debug SYMROOT=$PWD/macos/build -only-testing:LosttyTests/ApprovalBookTests -only-testing:LosttyTests/GuardServerTests -only-testing:LosttyTests/GuardRuntimeTests -only-testing:LosttyTests/GuardRequestViewTests -only-testing:LosttyTests/GuardHookWatchTests -only-testing:LosttyTests/ClaudeHooksTests test
```

Expected: all pass. Report any failure with its output; don't skip it.

- [ ] **Step 3: Commit**

```bash
git add SKINS.md
git commit -m "lostty: guard: document the guard

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: End-to-end check (needs the user).** Ask the user before installing. When they agree:
  1. Install with `macos/install.sh`. The user switches with menu bar → **Restart to Update**, never Quit.
  2. The user clicks **Connect / Update** for both agents. Codex asks to trust the new hook.
  3. In a scratch repo, in a Lostty pane, run the tiny prompts below. Keep prompts tiny; the user pays tokens.

```bash
mkdir -p /tmp/guard-e2e && cd /tmp/guard-e2e && git init -q && echo x > untracked.txt
claude -p --model haiku --permission-mode bypassPermissions "Run: rm untracked.txt"
```

Expected:
- `untracked.txt` survives.
- Claude says it's blocked, with a request number.
- A notification appears, with an amber badge on the pane.
- Approve in the window: "Approved #N in Lostty…" is typed into the pane. In `-p` mode there's no live session to receive it, so retry by running the same prompt again; that call now goes through once.

Then run the same with Codex, and once while `/tmp/guard-e2e` has a `git push` with no remote (critical, so blocked before the network):

```bash
codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "Run: rm untracked.txt"
```

Expected: the file survives, and Codex reports Lostty blocked it.

---

## Self-Review

- **Spec coverage:**
  - §7.1 principles:
    - enforced by a hook (T6, T7)
    - bubbles up to a person (T10, T11)
    - always on, in every mode (the hook runs in all modes, per the Codex test)
    - exactly this, once, 10 minutes (T8)
    - fail closed (T6: unparseable is critical, unreachable means ask or block, errors fail closed)
    - agents can't approve (T8 and T9: no granting call)
  - §7.2 catalog: T4 and T5, including "Deleting means git can't get it back" with the git check (T3), and agents' additions (later step; the user edits guard.json).
  - §7.3 Claude and Codex hooks: T7.
  - §7.4 flow and screen:
    - the request shows the exact input, why, what would be lost, folder, repo and branch, how it came about, and the agent's reason (T11)
    - Deny-only banner (T10)
    - no Touch ID
    - list, no approve-all (T11)
    - lapse after 1 hour (T8)
    - the agent hears the outcome (T10, by typing; see Decisions 1)
  - §7.5 UI-only approvals, and approvals not surviving a restart: T8 and T9.
  - §7.6 guarding the guard: catalog entries (T4) and the hook watch with the red badge (T12).
  - §8 badges: T11. Phone approvals are step 4, out of scope here.
- **Placeholders:** none. Three places tell the implementer to check an existing API before using it:
  - `KeyEvent` init (T10)
  - `HookNotifications.missing` signature (T12)
  - `SkinConfigStore.armFileWatcher` to mirror (T12)
  These are lookups, not missing design.
- **Type consistency:**
  - `GuardCheck` fields match `wire.encodeRequest` keys.
  - `GuardReply` matches `parseReply`.
  - `decide.Critical` feeds `wire`.
  - `catalog.write`/`deletion` take `shell.Word`.
  - `Event.kind`/`timeout` are used consistently in T7.
- **Review Focus** lines each have a test:
  - heredoc: T1, T5
  - quoted operators: T1
  - cd: T5
  - leaving the repo: T4
  - unreachable app: T6 (the wire tests, plus the Step 5 smoke)
