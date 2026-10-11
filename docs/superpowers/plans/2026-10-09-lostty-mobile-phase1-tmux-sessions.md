# Lostty Mobile Phase 1: Mac Panes in tmux Sessions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Mac Lostty pane runs its shell in its own session on a private tmux (`tmux -L lostty`), with the shell signals Lostty depends on (cwd, command finished, Claude user vars) still reaching the window, so a later phase can attach the same sessions from the phone, while the desk feels exactly as it does today.

**Architecture:** When the Mac app creates a pane with no explicit command, it sets the pane's command to `'<Lostty binary>' +tmux-launch`. That Zig CLI action creates a detached session (`new-session -d`) with the pane's env vars, tags it with the pane UUID, the app's pid and the shell name (tmux user options), then `exec`s `tmux attach`. The session's zsh starts with `ZDOTDIR` pointing at a Lostty-owned `.zshenv`, which loads Ghostty's own zsh integration (its OSC 7/133 stop at tmux, harmlessly) plus `lostty-tmux.zsh`, which re-sends OSC 7, OSC 133 `C`/`D` and a `LOSTTY_PROJECT` user var through tmux's DCS passthrough and renames the session to its project via `+tmux-rename`. The Swift side ends a pane's session when the pane closes, ends all of this Lostty's sessions on quit, asks tmux (not the core) whether a pane is busy before confirming a close, offers to reopen sessions a crash left behind, and lists other sessions in the command palette.

**Tech Stack:** Zig 0.15.2 (`std.process.Child`, `std.process.execv/execve`), zsh, tmux ≥ 3.5 (Homebrew), Swift/SwiftUI/AppKit, Swift Testing (`import Testing`).

**Spec:** `docs/superpowers/specs/2026-10-09-lostty-mobile-design.md` (this plan is build-order step 1, spec §2).

## Decisions this plan adds to the spec

The spec leaves these open; the plan settles them. Executors follow them; they are not up for re-litigation mid-task.

- **Session per pane**, not per window: tabs and splits are panes, and each gets its own session (the spec's "session per window" means per surface).
- **Only OSC 133 `C` and `D` go through passthrough.** `A`, `B` and `P` make Ghostty do a fresh-line, which would move Ghostty's cursor behind tmux's back and corrupt the screen. `C`→`D` is all the core needs to fire `COMMAND_FINISHED` (`src/Surface.zig` `.start_command`/`.stop_command`).
- **Ghostty's own zsh integration is loaded inside tmux** (titles, cursor shape, sudo/ssh helpers). Its OSC 7/133 are swallowed by tmux; `lostty-tmux.zsh` adds the passthrough copies.
- **Ownership by pid.** Sessions carry `@lostty_owner` = the pid of the Lostty that shows them. A window restored after a crash keeps its pane UUID, and a debug build can run next to the app on the same socket, so every kill/orphan/busy rule matches on surface *and* owner.
- **Close confirmation asks tmux.** tmux draws in the alternate screen, where `Terminal.cursorIsAtPrompt` is always false, so the core would always ask. For tmux panes the Swift side asks tmux whether `pane_current_command` differs from the session's shell.
- **"Not Now" on the crash prompt disowns** the sessions (clears their tags): they stay running for the phone and the palette, and are not offered again.
- **"Open session…" is one palette entry per available session**, titled `Open Session: <name>`, matching the palette's existing `Focus: <title>` entries.
- **Session naming lives in Zig** (`+tmux-rename`, called in the background by the snippet when the project changes), so it is unit-tested in Zig.
- **A hidden off switch**: `UserDefaults.ghostty` bool `LosttyTmuxDisabled` makes new panes plain local shells (debugging escape hatch; not surfaced in UI).
- **The Ghostty `command` config option is not consulted**: a pane with no explicit command always gets the launcher (the user sets no `command`).

## Global Constraints

- tmux socket name: `lostty` (always `tmux -L lostty`). Config file: `<GHOSTTY_RESOURCES_DIR>/shell-integration/lostty-tmux/tmux.conf`, passed with `-f` when creating a session. The user's `~/.tmux.conf` is never read.
- tmux user options on each session: `@lostty_surface` (pane UUID, uppercase, as `UUID.uuidString`), `@lostty_owner` (Lostty app pid, decimal), `@lostty_shell` (basename of the shell the launcher started, e.g. `zsh`).
- Env vars: `LOSTTY_SURFACE`, `LOSTTY_BIN`, `GHOSTTY_SKINS_SURFACE` (existing), `LOSTTY_APP_PID` (new, set by Swift on every pane), `LOSTTY_TMUX=1` (set inside Lostty's tmux sessions only), `LOSTTY_ZDOTDIR` (the user's original `ZDOTDIR`, only when it was set).
- User var for the phone: `LOSTTY_PROJECT` = the project path (git root, else cwd), raw path, base64 on the wire like every OSC 1337 user var.
- CLI actions: `+tmux-launch [--attach=<session id>]` and `+tmux-rename [--] <path>`. `+tmux-rename` never prints and always exits 0.
- Temporary session name: `lostty-<first 8 chars of the pane UUID, lowercased>-<launcher pid>`.
- Project name rule: last path component of the project path; `.`, `:`, whitespace and control characters become `_`; home directory → `home`; `/` → `root`; duplicates get `-2`, `-3`, ….
- tmux lookup order (Zig and Swift alike): `/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`, then each `PATH` entry. Lostty started from the Dock has PATH `/usr/bin:/bin:/usr/sbin:/sbin`.
- Fallback notice lines (exact, dim, printed by the launcher before a plain login shell):
  - `Lostty: tmux not found (brew install tmux). This window runs a plain shell and can't be opened from the phone.`
  - `Lostty: tmux couldn't start a session. This window runs a plain shell and can't be opened from the phone.`
  - `Lostty: that session has ended. This window runs a plain shell.`
- Off switch: `UserDefaults.ghostty` bool key `LosttyTmuxDisabled`.
- Every new Swift source file is wrapped in `#if os(macOS)` … `#endif` (the `Sources` folder is a synchronized group shared with the iOS target). New files are picked up by Xcode automatically (`Sources` and `Tests` are synchronized groups).
- Commands: Zig tests `zig build test -Dtest-filter="<name>"`; Swift tests `macos/skins-test.sh <SuiteName>` (prints failures, exits non-zero on failure; needs `zig build -Demit-macos-app=false` run once for the xcframework). Build the Debug app with `zig build -Demit-macos-app=false && xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build`; it lands at `macos/build/Debug/Ghostty.app` (binary `Contents/MacOS/ghostty`, resources `Contents/Resources/ghostty`).
- Formatting: `zig fmt .`; Swift: `swiftlint lint --strict --fix` (from `AGENTS.md`).
- Every commit message ends with the `Co-Authored-By:` line the session's harness specifies. Stage files by path; never `git add -A` (the untracked `default.profraw` must stay out).
- Never create an issue or a PR (`AGENTS.md`).

## Review Focus

1. **The same pane UUID or socket shared by two Lostty processes**: a window restored after a crash keeps its pane UUID while the crashed Lostty's session still carries it, and a Debug build often runs next to the installed app. Closing a pane, quitting, the busy check and the crash prompt must each touch only the sessions of the Lostty doing it; a running second Lostty's sessions are never "orphans". → Task 5 tests `closingAPaneEndsOnlyThisLosttysSession`, `quitEndsOnlyOwnSessions`, `aRunningSecondLosttyIsNotAnOrphan`, `otherLosttysPaneIsIgnored`; Task 2 test `tempName is unique per launcher`.
2. **Closing a window or quitting while every pane sits at a prompt** must not ask for confirmation (the core always says "busy" for tmux panes); with Claude running it must ask; when tmux can't answer, the core's answer stands. → Task 5 tests `atThePromptIsNotBusy`, `claudeRunningIsBusy`, `unknownDefersToTheCore`; Task 8 manual checks 7–8.
3. **Project directories tmux can't use as names, and two panes in one project**: `my.app`, `a:b`, `my proj`, a trailing slash, `~`, `/`; a second pane in `idfk` must become `idfk-2`, and a rename race must retry rather than leave the temporary name. → Task 1 tests `projectName …`, `uniqueName …`, `alreadyNamed …`.
4. **Lostty launched from the Dock with a bare PATH**: both the launcher and the app must still find Homebrew's tmux. → Task 2 test `findTmux prefers Homebrew over a bare PATH`; Task 5 test `locatePrefersHomebrewOverABarePATH`.
5. **Spaces and quotes in paths**: the Lostty binary under `~/My Apps/`, a project in `~/My Projects/x`, and session ids like `$3` inside the shell string the core runs. Quoting must keep each one a single argument and stop `$3` from being expanded. → Task 5 tests `quotesSpacesAndQuotes`, `attachCommandQuotesTheSessionID`; Task 2 test `newSessionArgv keeps a cwd with spaces as one argument`; Task 3 test `reports cwd and project for a path with spaces`.

---

## File Structure

Zig (CLI, `src/cli/`):
- Create `src/cli/tmux/naming.zig`: pure session naming: `projectName`, `alreadyNamed`, `uniqueName`, `pathFromArgs`.
- Create `src/cli/tmux/session.zig`: pure tmux command lines and launcher text: constants, `Env`, `findTmux`, `tempName`, `newSessionArgv`, `tagArgv`, `attachArgv`, `attachIdFromArgs`, `isSessionId`, `noticeLine`, `pwdSequence`.
- Create `src/cli/tmux/snippet_test.zig`: runs `lostty-tmux.zsh` in a real zsh.
- Create `src/cli/tmux_launch.zig`: the `+tmux-launch` action (IO: run tmux, exec attach, fallback shell). Exports `isExecutable`, `runTmux`.
- Create `src/cli/tmux_rename.zig`: the `+tmux-rename` action (IO).
- Modify `src/cli/ghostty.zig`: register both actions and the tests.

Shipped files (installed to `share/ghostty/shell-integration/lostty-tmux/` by the existing install of `src/shell-integration`, see `src/build/GhosttyResources.zig:117-125`):
- Create `src/shell-integration/lostty-tmux/tmux.conf`
- Create `src/shell-integration/lostty-tmux/zsh/.zshenv`
- Create `src/shell-integration/lostty-tmux/zsh/lostty-tmux.zsh`

Swift (`macos/Sources/Features/Sessions/`, new folder):
- `TmuxSession.swift`: `TmuxConstants`, `TmuxSession` (+ list parsing), `TmuxOwnership`, `TmuxPane` (+ busy rule), `ProcessLiveness`.
- `TmuxClient.swift`: runs `tmux -L lostty …`; locate, list, end, disown, busy.
- `SessionLaunch.swift`: the pane command string (quoting, attach form, recognizing it).
- `SessionsUI.swift`: crash prompt, `SessionsPrompt` text, `SessionsModel` for the palette, `open`.

Swift (wiring):
- Modify `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`: launcher command, `LOSTTY_APP_PID`, `inTmuxSession`, end session on deinit, `needsConfirmQuit`.
- Modify `macos/Sources/Ghostty/Ghostty.Config.swift`: `confirmCloseSurface`.
- Modify `macos/Sources/App/macOS/AppDelegate.swift`: quit confirmation, end sessions on quit, crash prompt at launch.
- Modify `macos/Sources/Features/Command Palette/TerminalCommandPalette.swift`: `Open Session: <name>` entries.

Tests: `macos/Tests/Sessions/*.swift`; Zig `test` blocks in the new Zig files.

Script: Create `macos/lostty-tmux-smoke.sh`: end-to-end check of launcher, snippet, config and rename against real tmux (reused by later phases).

---

### Task 1: Session naming (Zig, pure)

**Files:**
- Create: `src/cli/tmux/naming.zig`
- Modify: `src/cli/ghostty.zig` (test block at the end of the file)

**Interfaces:**
- Consumes: nothing.
- Produces (used by Task 4 `tmux_rename.zig`):
  - `pub fn projectName(alloc: Allocator, path: []const u8, home: ?[]const u8) ![]u8`
  - `pub fn alreadyNamed(name: []const u8, base: []const u8) bool`
  - `pub fn uniqueName(alloc: Allocator, base: []const u8, taken: []const []const u8) ![]u8`
  - `pub fn pathFromArgs(argv: []const []const u8) ?[]const u8`

- [ ] **Step 1: Make sure tmux is installed (needed from Task 3 on)**

Run: `tmux -V || brew install tmux; tmux -V`
Expected: `tmux 3.5` or newer (spec §1 lists `brew install tmux`; the host setup phase may not have run yet).

- [ ] **Step 2: Write the failing tests**

Create `src/cli/tmux/naming.zig` with only the tests and empty stubs so it compiles:

```zig
//! Session names on Lostty's tmux: each session is named after the project
//! its shell is in, so the phone can list sessions by project. See
//! docs/superpowers/specs/2026-10-09-lostty-mobile-design.md (§2, Naming).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn projectName(alloc: Allocator, path: []const u8, home: ?[]const u8) ![]u8 {
    _ = path;
    _ = home;
    return alloc.dupe(u8, "");
}

pub fn alreadyNamed(name: []const u8, base: []const u8) bool {
    _ = name;
    _ = base;
    return false;
}

pub fn uniqueName(alloc: Allocator, base: []const u8, taken: []const []const u8) ![]u8 {
    _ = taken;
    return alloc.dupe(u8, base);
}

pub fn pathFromArgs(argv: []const []const u8) ?[]const u8 {
    _ = argv;
    return null;
}

test "lostty tmux naming: projectName uses the last path component" {
    const alloc = std.testing.allocator;
    const cases = [_]struct { path: []const u8, want: []const u8 }{
        .{ .path = "/Users/me/code/idfk", .want = "idfk" },
        .{ .path = "/Users/me/code/idfk/", .want = "idfk" },
        .{ .path = "/Users/me/code/my.app", .want = "my_app" },
        .{ .path = "/Users/me/code/a:b", .want = "a_b" },
        .{ .path = "/Users/me/code/my proj", .want = "my_proj" },
        .{ .path = "/Users/me/code/tab\there", .want = "tab_here" },
        .{ .path = "/Users/me/code/código", .want = "código" },
        .{ .path = "/Users/me", .want = "home" },
        .{ .path = "/Users/me/", .want = "home" },
        .{ .path = "/", .want = "root" },
        .{ .path = "", .want = "root" },
    };
    for (cases) |c| {
        const got = try projectName(alloc, c.path, "/Users/me");
        defer alloc.free(got);
        try std.testing.expectEqualStrings(c.want, got);
    }
}

test "lostty tmux naming: projectName without a home directory" {
    const alloc = std.testing.allocator;
    const got = try projectName(alloc, "/Users/me", null);
    defer alloc.free(got);
    try std.testing.expectEqualStrings("me", got);
}

test "lostty tmux naming: alreadyNamed accepts base and base-N only" {
    const t = std.testing;
    try t.expect(alreadyNamed("idfk", "idfk"));
    try t.expect(alreadyNamed("idfk-2", "idfk"));
    try t.expect(alreadyNamed("idfk-12", "idfk"));
    try t.expect(!alreadyNamed("idfk-", "idfk"));
    try t.expect(!alreadyNamed("idfk-x", "idfk"));
    try t.expect(!alreadyNamed("idfkx", "idfk"));
    try t.expect(!alreadyNamed("notes", "idfk"));
    // The temporary name is never mistaken for a project named "lostty".
    try t.expect(!alreadyNamed("lostty-abcdef01-4242", "lostty"));
}

test "lostty tmux naming: uniqueName picks the first free suffix" {
    const alloc = std.testing.allocator;
    const cases = [_]struct { taken: []const []const u8, want: []const u8 }{
        .{ .taken = &.{}, .want = "idfk" },
        .{ .taken = &.{"notes"}, .want = "idfk" },
        .{ .taken = &.{"idfk"}, .want = "idfk-2" },
        .{ .taken = &.{ "idfk", "idfk-2" }, .want = "idfk-3" },
        .{ .taken = &.{"idfk-2"}, .want = "idfk" },
    };
    for (cases) |c| {
        const got = try uniqueName(alloc, "idfk", c.taken);
        defer alloc.free(got);
        try std.testing.expectEqualStrings(c.want, got);
    }
}

test "lostty tmux naming: pathFromArgs" {
    const t = std.testing;
    try t.expectEqualStrings("/a b", pathFromArgs(&.{ "/x/ghostty", "+tmux-rename", "/a b" }).?);
    try t.expectEqualStrings("/a", pathFromArgs(&.{ "/x/ghostty", "+tmux-rename", "--", "/a" }).?);
    try t.expect(pathFromArgs(&.{ "/x/ghostty", "+tmux-rename" }) == null);
    try t.expect(pathFromArgs(&.{ "/x/ghostty", "+tmux-rename", "--" }) == null);
    try t.expect(pathFromArgs(&.{ "/x/ghostty", "/a" }) == null);
}
```

Register the tests: in `src/cli/ghostty.zig`, change the final test block

```zig
test {
    _ = skins;
    _ = claude_state;
    _ = claude_hooks;
    _ = claude_usage;
}
```

to

```zig
test {
    _ = skins;
    _ = claude_state;
    _ = claude_hooks;
    _ = claude_usage;
    _ = @import("tmux/naming.zig");
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `zig build test -Dtest-filter="lostty tmux naming"`
Expected: FAIL (e.g. `expected "idfk", found ""`).

- [ ] **Step 4: Implement**

Replace the four stubs in `src/cli/tmux/naming.zig` with:

```zig
/// The session name for a project directory: its last path component, with
/// '.', ':', whitespace and control characters turned into '_' (tmux
/// rewrites '.' and ':' itself, and the others read badly in a list). The
/// home directory is "home" and "/" is "root".
pub fn projectName(alloc: Allocator, path: []const u8, home: ?[]const u8) ![]u8 {
    const trimmed = std.mem.trimEnd(u8, path, "/");
    if (trimmed.len == 0) return alloc.dupe(u8, "root");
    if (home) |h| {
        if (std.mem.eql(u8, trimmed, std.mem.trimEnd(u8, h, "/"))) return alloc.dupe(u8, "home");
    }
    const out = try alloc.dupe(u8, std.fs.path.basename(trimmed));
    for (out) |*c| {
        if (c.* == '.' or c.* == ':' or c.* <= ' ' or c.* == 0x7f) c.* = '_';
    }
    return out;
}

/// True when `name` is `base` or `base-<digits>`: the session already
/// carries this project's name, so there is nothing to rename.
pub fn alreadyNamed(name: []const u8, base: []const u8) bool {
    if (std.mem.eql(u8, name, base)) return true;
    if (name.len < base.len + 2 or !std.mem.startsWith(u8, name, base)) return false;
    if (name[base.len] != '-') return false;
    for (name[base.len + 1 ..]) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

/// `base`, else `base-2`, `base-3`, …: the first name no session in
/// `taken` uses.
pub fn uniqueName(alloc: Allocator, base: []const u8, taken: []const []const u8) ![]u8 {
    if (!contains(taken, base)) return alloc.dupe(u8, base);
    var n: usize = 2;
    while (true) : (n += 1) {
        const candidate = try std.fmt.allocPrint(alloc, "{s}-{d}", .{ base, n });
        if (!contains(taken, candidate)) return candidate;
        alloc.free(candidate);
    }
}

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, s)) return true;
    }
    return false;
}

/// The path after `+tmux-rename` (a `--` before it is skipped).
pub fn pathFromArgs(argv: []const []const u8) ?[]const u8 {
    for (argv, 0..) |arg, i| {
        if (!std.mem.eql(u8, arg, "+tmux-rename")) continue;
        var j = i + 1;
        if (j < argv.len and std.mem.eql(u8, argv[j], "--")) j += 1;
        return if (j < argv.len) argv[j] else null;
    }
    return null;
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `zig build test -Dtest-filter="lostty tmux naming"`
Expected: PASS (all 5 tests).

- [ ] **Step 6: Format and commit**

```bash
zig fmt src/cli/tmux/naming.zig src/cli/ghostty.zig
git add src/cli/tmux/naming.zig src/cli/ghostty.zig
git commit -m "lostty: tmux session names from the project directory"
```

---

### Task 2: tmux command lines for the launcher (Zig, pure)

**Files:**
- Create: `src/cli/tmux/session.zig`
- Modify: `src/cli/ghostty.zig` (test block)

**Interfaces:**
- Consumes: nothing.
- Produces (used by Task 4):
  - constants `socket = "lostty"`, `opt_surface = "@lostty_surface"`, `opt_owner = "@lostty_owner"`, `opt_shell = "@lostty_shell"`, `tmux_candidates`
  - `pub const Env = struct { surface, bin, skins_surface, app_pid, shell, resources_dir, shell_features, zdotdir, path: ?[]const u8 }` with `pub fn fromProcess() Env` and `pub fn shellPath(self: Env) []const u8`
  - `pub fn findTmux(alloc: Allocator, path_env: ?[]const u8, isExecutable: *const fn ([]const u8) bool) ?[]const u8`
  - `pub fn tempName(alloc: Allocator, surface: []const u8, pid: i32) ![]u8`
  - `pub const Size = struct { cols: u16, rows: u16 }`
  - `pub const NewSession = struct { tmux, env: Env, surface, resources_dir, cwd: []const u8, pid: i32, size: ?Size = null }`
  - `pub fn newSessionArgv(alloc: Allocator, s: NewSession) ![]const []const u8` (stdout of the command is the new session id, e.g. `$3`)
  - `pub fn tagArgv(alloc: Allocator, tmux: []const u8, id: []const u8, surface: []const u8, owner: ?[]const u8, shell_name: ?[]const u8) ![]const []const u8`
  - `pub fn attachArgv(alloc: Allocator, tmux: []const u8, id: []const u8) ![]const []const u8`
  - `pub fn attachIdFromArgs(argv: []const []const u8) ?[]const u8`
  - `pub fn isSessionId(s: []const u8) bool`
  - `pub fn isZsh(shell: []const u8) bool`
  - `pub const Notice = enum { no_tmux, tmux_failed, session_gone }` and `pub fn noticeLine(n: Notice) []const u8`
  - `pub fn pwdSequence(alloc: Allocator, host: []const u8, path: []const u8) ![]u8`
  - All builders allocate freely; callers pass an arena.

- [ ] **Step 1: Write the failing tests**

Create `src/cli/tmux/session.zig` with the declarations and stubs below, followed by the tests.

```zig
//! Pure logic for Lostty's private tmux (`tmux -L lostty`): where tmux is,
//! and the tmux command lines `+tmux-launch` runs. Builders allocate
//! freely; pass an arena. See
//! docs/superpowers/specs/2026-10-09-lostty-mobile-design.md (§2).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const socket = "lostty";
pub const opt_surface = "@lostty_surface";
pub const opt_owner = "@lostty_owner";
pub const opt_shell = "@lostty_shell";

/// Homebrew's usual places come first: Lostty started from the Dock has a
/// bare PATH (/usr/bin:/bin:/usr/sbin:/sbin) without them.
pub const tmux_candidates = [_][]const u8{ "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux" };

/// What the launcher reads from its environment.
pub const Env = struct {
    surface: ?[]const u8 = null, // LOSTTY_SURFACE
    bin: ?[]const u8 = null, // LOSTTY_BIN
    skins_surface: ?[]const u8 = null, // GHOSTTY_SKINS_SURFACE
    app_pid: ?[]const u8 = null, // LOSTTY_APP_PID
    shell: ?[]const u8 = null, // SHELL
    resources_dir: ?[]const u8 = null, // GHOSTTY_RESOURCES_DIR
    shell_features: ?[]const u8 = null, // GHOSTTY_SHELL_FEATURES
    zdotdir: ?[]const u8 = null, // ZDOTDIR
    path: ?[]const u8 = null, // PATH

    pub fn fromProcess() Env {
        const get = std.posix.getenv;
        return .{
            .surface = get("LOSTTY_SURFACE"),
            .bin = get("LOSTTY_BIN"),
            .skins_surface = get("GHOSTTY_SKINS_SURFACE"),
            .app_pid = get("LOSTTY_APP_PID"),
            .shell = get("SHELL"),
            .resources_dir = get("GHOSTTY_RESOURCES_DIR"),
            .shell_features = get("GHOSTTY_SHELL_FEATURES"),
            .zdotdir = get("ZDOTDIR"),
            .path = get("PATH"),
        };
    }

    pub fn shellPath(self: Env) []const u8 {
        return self.shell orelse "/bin/zsh";
    }
};

pub const Size = struct { cols: u16, rows: u16 };

pub const NewSession = struct {
    tmux: []const u8,
    env: Env,
    surface: []const u8,
    resources_dir: []const u8,
    cwd: []const u8,
    /// The launcher's pid, which keeps temporary names unique.
    pid: i32,
    size: ?Size = null,
};

pub const Notice = enum { no_tmux, tmux_failed, session_gone };

pub fn findTmux(alloc: Allocator, path_env: ?[]const u8, isExecutable: *const fn ([]const u8) bool) ?[]const u8 {
    _ = alloc;
    _ = path_env;
    _ = isExecutable;
    return null;
}
pub fn tempName(alloc: Allocator, surface: []const u8, pid: i32) ![]u8 {
    _ = surface;
    _ = pid;
    return alloc.dupe(u8, "");
}
pub fn newSessionArgv(alloc: Allocator, s: NewSession) ![]const []const u8 {
    _ = s;
    return alloc.alloc([]const u8, 0);
}
pub fn tagArgv(alloc: Allocator, tmux: []const u8, id: []const u8, surface: []const u8, owner: ?[]const u8, shell_name: ?[]const u8) ![]const []const u8 {
    _ = .{ tmux, id, surface, owner, shell_name };
    return alloc.alloc([]const u8, 0);
}
pub fn attachArgv(alloc: Allocator, tmux: []const u8, id: []const u8) ![]const []const u8 {
    _ = .{ tmux, id };
    return alloc.alloc([]const u8, 0);
}
pub fn attachIdFromArgs(argv: []const []const u8) ?[]const u8 {
    _ = argv;
    return null;
}
pub fn isSessionId(s: []const u8) bool {
    _ = s;
    return false;
}
pub fn isZsh(shell: []const u8) bool {
    _ = shell;
    return false;
}
pub fn noticeLine(n: Notice) []const u8 {
    _ = n;
    return "";
}
pub fn pwdSequence(alloc: Allocator, host: []const u8, path: []const u8) ![]u8 {
    _ = .{ host, path };
    return alloc.dupe(u8, "");
}

// ---- tests ----

const Fake = struct {
    fn onlyUsrLocal(p: []const u8) bool {
        return std.mem.eql(u8, p, "/usr/local/bin/tmux");
    }
    fn homebrewAndUsrBin(p: []const u8) bool {
        return std.mem.eql(u8, p, "/opt/homebrew/bin/tmux") or std.mem.eql(u8, p, "/usr/bin/tmux");
    }
    fn onlyCustom(p: []const u8) bool {
        return std.mem.eql(u8, p, "/custom/bin/tmux");
    }
    fn none(_: []const u8) bool {
        return false;
    }
};

/// True when `a` is immediately followed by `b` somewhere in `argv`.
fn hasPair(argv: []const []const u8, a: []const u8, b: []const u8) bool {
    if (argv.len < 2) return false;
    for (argv[0 .. argv.len - 1], argv[1..]) |x, y| {
        if (std.mem.eql(u8, x, a) and std.mem.eql(u8, y, b)) return true;
    }
    return false;
}

fn hasArg(argv: []const []const u8, a: []const u8) bool {
    for (argv) |x| if (std.mem.eql(u8, x, a)) return true;
    return false;
}

const test_surface = "ABCDEF01-0000-4000-8000-000000000001";

test "lostty tmux session: findTmux prefers Homebrew over a bare PATH" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = std.testing;
    try t.expectEqualStrings("/opt/homebrew/bin/tmux", findTmux(a, "/usr/bin:/bin", Fake.homebrewAndUsrBin).?);
    try t.expectEqualStrings("/usr/local/bin/tmux", findTmux(a, "/usr/bin:/bin", Fake.onlyUsrLocal).?);
    try t.expectEqualStrings("/custom/bin/tmux", findTmux(a, "/usr/bin:/custom/bin", Fake.onlyCustom).?);
    try t.expect(findTmux(a, "/usr/bin:/bin", Fake.none) == null);
    try t.expect(findTmux(a, null, Fake.none) == null);
}

test "lostty tmux session: tempName is unique per launcher" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = std.testing;
    try t.expectEqualStrings("lostty-abcdef01-4242", try tempName(a, test_surface, 4242));
    // A restored window reuses its pane UUID; a different launcher pid keeps the name free.
    try t.expect(!std.mem.eql(u8, try tempName(a, test_surface, 1), try tempName(a, test_surface, 2)));
    try t.expectEqualStrings("lostty-axb-7", try tempName(a, "a.b", 7));
}

test "lostty tmux session: newSessionArgv for zsh" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = std.testing;
    const argv = try newSessionArgv(a, .{
        .tmux = "/opt/homebrew/bin/tmux",
        .env = .{
            .bin = "/Apps/Lostty.app/Contents/MacOS/ghostty",
            .skins_surface = test_surface,
            .app_pid = "4242",
            .shell = "/bin/zsh",
            .shell_features = "cursor,title",
            .zdotdir = "/Users/me/.zsh",
        },
        .surface = test_surface,
        .resources_dir = "/R",
        .cwd = "/Users/me/code/idfk",
        .pid = 77,
        .size = .{ .cols = 120, .rows = 40 },
    });
    try t.expectEqualStrings("/opt/homebrew/bin/tmux", argv[0]);
    try t.expect(hasPair(argv, "-L", "lostty"));
    try t.expect(hasPair(argv, "-f", "/R/shell-integration/lostty-tmux/tmux.conf"));
    try t.expect(hasArg(argv, "new-session"));
    try t.expect(hasArg(argv, "-d"));
    try t.expect(hasPair(argv, "-F", "#{session_id}"));
    try t.expect(hasPair(argv, "-s", "lostty-abcdef01-77"));
    try t.expect(hasPair(argv, "-c", "/Users/me/code/idfk"));
    try t.expect(hasPair(argv, "-x", "120"));
    try t.expect(hasPair(argv, "-y", "40"));
    try t.expect(hasPair(argv, "-e", "LOSTTY_TMUX=1"));
    try t.expect(hasPair(argv, "-e", "LOSTTY_SURFACE=" ++ test_surface));
    try t.expect(hasPair(argv, "-e", "GHOSTTY_SKINS_SURFACE=" ++ test_surface));
    try t.expect(hasPair(argv, "-e", "LOSTTY_BIN=/Apps/Lostty.app/Contents/MacOS/ghostty"));
    try t.expect(hasPair(argv, "-e", "LOSTTY_APP_PID=4242"));
    try t.expect(hasPair(argv, "-e", "GHOSTTY_RESOURCES_DIR=/R"));
    try t.expect(hasPair(argv, "-e", "GHOSTTY_SHELL_FEATURES=cursor,title"));
    try t.expect(hasPair(argv, "-e", "ZDOTDIR=/R/shell-integration/lostty-tmux/zsh"));
    try t.expect(hasPair(argv, "-e", "LOSTTY_ZDOTDIR=/Users/me/.zsh"));
    try t.expectEqualStrings("/bin/zsh", argv[argv.len - 2]);
    try t.expectEqualStrings("-l", argv[argv.len - 1]);
}

test "lostty tmux session: newSessionArgv keeps a cwd with spaces as one argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const argv = try newSessionArgv(arena.allocator(), .{
        .tmux = "tmux",
        .env = .{ .shell = "/bin/zsh" },
        .surface = test_surface,
        .resources_dir = "/My Apps/R",
        .cwd = "/Users/me/My Projects/x",
        .pid = 1,
    });
    try std.testing.expect(hasPair(argv, "-c", "/Users/me/My Projects/x"));
    try std.testing.expect(hasPair(argv, "-f", "/My Apps/R/shell-integration/lostty-tmux/tmux.conf"));
    // No size known: tmux picks one and the attach resizes.
    try std.testing.expect(!hasArg(argv, "-x"));
}

test "lostty tmux session: newSessionArgv leaves other shells and ZDOTDIR alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = std.testing;
    const bash = try newSessionArgv(a, .{ .tmux = "tmux", .env = .{ .shell = "/bin/bash" }, .surface = test_surface, .resources_dir = "/R", .cwd = "/", .pid = 1 });
    for (bash) |arg| try t.expect(!std.mem.startsWith(u8, arg, "ZDOTDIR="));
    try t.expectEqualStrings("/bin/bash", bash[bash.len - 2]);
    // zsh without a ZDOTDIR of its own: nothing to restore later.
    const zsh = try newSessionArgv(a, .{ .tmux = "tmux", .env = .{}, .surface = test_surface, .resources_dir = "/R", .cwd = "/", .pid = 1 });
    for (zsh) |arg| try t.expect(!std.mem.startsWith(u8, arg, "LOSTTY_ZDOTDIR="));
    try t.expect(hasPair(zsh, "-e", "ZDOTDIR=/R/shell-integration/lostty-tmux/zsh"));
    try t.expectEqualStrings("/bin/zsh", zsh[zsh.len - 2]);
}

test "lostty tmux session: tagArgv" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = std.testing;
    const full = try tagArgv(a, "tmux", "$3", test_surface, "4242", "zsh");
    const want_full = [_][]const u8{
        "tmux",       "-L",         "lostty", "set-option", "-t", "$3", "@lostty_surface", test_surface,
        ";",          "set-option", "-t",     "$3",         "@lostty_owner", "4242",
        ";",          "set-option", "-t",     "$3",         "@lostty_shell", "zsh",
    };
    try t.expectEqual(want_full.len, full.len);
    for (want_full, full) |w, g| try t.expectEqualStrings(w, g);
    // Adopting a session: no owner known, shell kept as it was.
    const bare = try tagArgv(a, "tmux", "$3", test_surface, null, null);
    try t.expectEqual(@as(usize, 8), bare.len);
}

test "lostty tmux session: attach arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const t = std.testing;
    const argv = try attachArgv(arena.allocator(), "tmux", "$3");
    const want = [_][]const u8{ "tmux", "-L", "lostty", "attach-session", "-t", "$3" };
    try t.expectEqual(want.len, argv.len);
    for (want, argv) |w, g| try t.expectEqualStrings(w, g);
    try t.expectEqualStrings("$3", attachIdFromArgs(&.{ "/x/ghostty", "+tmux-launch", "--attach=$3" }).?);
    try t.expect(attachIdFromArgs(&.{ "/x/ghostty", "+tmux-launch" }) == null);
    try t.expect(isSessionId("$3"));
    try t.expect(isSessionId("$120"));
    try t.expect(!isSessionId("$"));
    try t.expect(!isSessionId("3"));
    try t.expect(!isSessionId("$3;kill-server"));
    try t.expect(isZsh("/bin/zsh"));
    try t.expect(isZsh("/opt/homebrew/bin/zsh"));
    try t.expect(!isZsh("/bin/bash"));
}

test "lostty tmux session: notices and OSC 7" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const t = std.testing;
    try t.expectEqualStrings(
        "\x1b[2mLostty: tmux not found (brew install tmux). This window runs a plain shell and can't be opened from the phone.\x1b[0m\r\n",
        noticeLine(.no_tmux),
    );
    try t.expect(std.mem.indexOf(u8, noticeLine(.tmux_failed), "tmux couldn't start a session") != null);
    try t.expect(std.mem.indexOf(u8, noticeLine(.session_gone), "that session has ended") != null);
    try t.expectEqualStrings(
        "\x1b]7;kitty-shell-cwd://mac/Users/me/My Projects/x\x07",
        try pwdSequence(arena.allocator(), "mac", "/Users/me/My Projects/x"),
    );
}
```

Register: in `src/cli/ghostty.zig`'s final test block, add `_ = @import("tmux/session.zig");` after the naming line.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zig build test -Dtest-filter="lostty tmux session"`
Expected: FAIL (stubs return null/empty).

- [ ] **Step 3: Implement**

Replace every stub in `src/cli/tmux/session.zig` (keep the declarations above them and the tests below) with:

```zig
/// The first executable tmux: Homebrew's places, then each PATH entry.
/// `isExecutable` is injected so tests don't depend on this machine.
pub fn findTmux(
    alloc: Allocator,
    path_env: ?[]const u8,
    isExecutable: *const fn ([]const u8) bool,
) ?[]const u8 {
    for (tmux_candidates) |c| {
        if (isExecutable(c)) return c;
    }
    var it = std.mem.tokenizeScalar(u8, path_env orelse return null, ':');
    while (it.next()) |dir| {
        const candidate = std.fs.path.join(alloc, &.{ dir, "tmux" }) catch return null;
        if (isExecutable(candidate)) return candidate;
    }
    return null;
}

/// A session's name until its shell renames it to its project:
/// "lostty-", the first 8 characters of the pane's UUID (lowercased), and
/// the launcher's pid. A restored window reuses its pane UUID while the old
/// session may still exist, so the UUID alone is not unique.
pub fn tempName(alloc: Allocator, surface: []const u8, pid: i32) ![]u8 {
    const n = @min(surface.len, 8);
    var prefix: [8]u8 = undefined;
    for (surface[0..n], prefix[0..n]) |c, *o| {
        o.* = if (std.ascii.isAlphanumeric(c)) std.ascii.toLower(c) else 'x';
    }
    return std.fmt.allocPrint(alloc, "lostty-{s}-{d}", .{ prefix[0..n], pid });
}

fn integrationPath(alloc: Allocator, resources_dir: []const u8, name: []const u8) ![]u8 {
    return std.fs.path.join(alloc, &.{ resources_dir, "shell-integration", "lostty-tmux", name });
}

pub fn isZsh(shell: []const u8) bool {
    return std.mem.eql(u8, std.fs.path.basename(shell), "zsh");
}

fn appendEnv(alloc: Allocator, argv: *std.ArrayList([]const u8), name: []const u8, value: []const u8) !void {
    try argv.appendSlice(alloc, &.{ "-e", try std.fmt.allocPrint(alloc, "{s}={s}", .{ name, value }) });
}

/// The tmux command that creates the pane's session, detached, and prints
/// its id ("$3"). The session's shell gets the pane's env vars (the server's
/// own environment belongs to whichever pane started it) and, for zsh,
/// Lostty's ZDOTDIR, which loads the passthrough snippet.
pub fn newSessionArgv(alloc: Allocator, s: NewSession) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(alloc, &.{
        s.tmux,                                                  "-L",                          socket,
        "-f",                                                    try integrationPath(alloc, s.resources_dir, "tmux.conf"),
        "new-session",                                           "-d",
        "-P",                                                    "-F",
        "#{session_id}",                                         "-s",
        try tempName(alloc, s.surface, s.pid),                   "-c",
        s.cwd,
    });
    if (s.size) |size| {
        try argv.appendSlice(alloc, &.{
            "-x", try std.fmt.allocPrint(alloc, "{d}", .{size.cols}),
            "-y", try std.fmt.allocPrint(alloc, "{d}", .{size.rows}),
        });
    }
    try appendEnv(alloc, &argv, "LOSTTY_TMUX", "1");
    try appendEnv(alloc, &argv, "LOSTTY_SURFACE", s.surface);
    try appendEnv(alloc, &argv, "GHOSTTY_RESOURCES_DIR", s.resources_dir);
    if (s.env.bin) |v| try appendEnv(alloc, &argv, "LOSTTY_BIN", v);
    if (s.env.skins_surface) |v| try appendEnv(alloc, &argv, "GHOSTTY_SKINS_SURFACE", v);
    if (s.env.app_pid) |v| try appendEnv(alloc, &argv, "LOSTTY_APP_PID", v);
    if (s.env.shell_features) |v| try appendEnv(alloc, &argv, "GHOSTTY_SHELL_FEATURES", v);
    const shell = s.env.shellPath();
    if (isZsh(shell)) {
        try appendEnv(alloc, &argv, "ZDOTDIR", try integrationPath(alloc, s.resources_dir, "zsh"));
        if (s.env.zdotdir) |v| try appendEnv(alloc, &argv, "LOSTTY_ZDOTDIR", v);
    }
    try argv.appendSlice(alloc, &.{ shell, "-l" });
    return argv.toOwnedSlice(alloc);
}

/// The tmux command that tags session `id` with its pane, its Lostty
/// (`owner`, a pid) and its shell's name. Null fields are left as they are.
pub fn tagArgv(
    alloc: Allocator,
    tmux: []const u8,
    id: []const u8,
    surface: []const u8,
    owner: ?[]const u8,
    shell_name: ?[]const u8,
) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(alloc, &.{ tmux, "-L", socket, "set-option", "-t", id, opt_surface, surface });
    if (owner) |v| try argv.appendSlice(alloc, &.{ ";", "set-option", "-t", id, opt_owner, v });
    if (shell_name) |v| try argv.appendSlice(alloc, &.{ ";", "set-option", "-t", id, opt_shell, v });
    return argv.toOwnedSlice(alloc);
}

pub fn attachArgv(alloc: Allocator, tmux: []const u8, id: []const u8) ![]const []const u8 {
    return alloc.dupe([]const u8, &.{ tmux, "-L", socket, "attach-session", "-t", id });
}

/// The session id after `--attach=`, if any.
pub fn attachIdFromArgs(argv: []const []const u8) ?[]const u8 {
    const prefix = "--attach=";
    for (argv) |arg| {
        if (std.mem.startsWith(u8, arg, prefix)) return arg[prefix.len..];
    }
    return null;
}

/// tmux session ids look like "$12".
pub fn isSessionId(s: []const u8) bool {
    if (s.len < 2 or s[0] != '$') return false;
    for (s[1..]) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

/// One dim line printed above the plain shell the launcher falls back to.
pub fn noticeLine(n: Notice) []const u8 {
    return switch (n) {
        .no_tmux => "\x1b[2mLostty: tmux not found (brew install tmux). This window runs a plain shell and can't be opened from the phone.\x1b[0m\r\n",
        .tmux_failed => "\x1b[2mLostty: tmux couldn't start a session. This window runs a plain shell and can't be opened from the phone.\x1b[0m\r\n",
        .session_gone => "\x1b[2mLostty: that session has ended. This window runs a plain shell.\x1b[0m\r\n",
    };
}

/// OSC 7 for `path`, written straight to the window (not through tmux) when
/// a window adopts an existing session, so auto-skin needn't wait for the
/// next prompt. kitty-shell-cwd takes the raw path, no percent-escaping.
pub fn pwdSequence(alloc: Allocator, host: []const u8, path: []const u8) ![]u8 {
    return std.fmt.allocPrint(alloc, "\x1b]7;kitty-shell-cwd://{s}{s}\x07", .{ host, path });
}
```

(`zig fmt` will re-align the `appendSlice` literal in `newSessionArgv`; that is fine.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zig build test -Dtest-filter="lostty tmux session"`
Expected: PASS (8 tests).

- [ ] **Step 5: Format and commit**

```bash
zig fmt src/cli/tmux/session.zig src/cli/ghostty.zig
git add src/cli/tmux/session.zig src/cli/ghostty.zig
git commit -m "lostty: tmux command lines for a pane's session"
```

---

### Task 3: Lostty's tmux config and zsh snippet

**Files:**
- Create: `src/shell-integration/lostty-tmux/tmux.conf`
- Create: `src/shell-integration/lostty-tmux/zsh/.zshenv`
- Create: `src/shell-integration/lostty-tmux/zsh/lostty-tmux.zsh`
- Create: `src/cli/tmux/snippet_test.zig`
- Modify: `src/cli/ghostty.zig` (test block)

**Interfaces:**
- Consumes: env vars from Task 2's `newSessionArgv` (`LOSTTY_TMUX`, `LOSTTY_BIN`, `LOSTTY_ZDOTDIR`, `GHOSTTY_RESOURCES_DIR`, `ZDOTDIR`).
- Produces: zsh functions `_lostty_passthrough <seq>`, `_lostty_osc <body>`, `_lostty_project_of <dir>`, `_lostty_precmd`, `_lostty_preexec`; calls `"$LOSTTY_BIN" +tmux-rename -- <project path>` in the background (Task 4 implements it); files installed at `<resources>/shell-integration/lostty-tmux/{tmux.conf,zsh/.zshenv,zsh/lostty-tmux.zsh}`.

- [ ] **Step 1: Write the failing snippet tests**

Create `src/cli/tmux/snippet_test.zig`:

```zig
//! Tests for lostty-tmux.zsh (src/shell-integration/lostty-tmux/zsh/). They
//! run the snippet in a real zsh, which macOS always has; elsewhere they
//! skip.

const std = @import("std");
const snippet = @embedFile("../../shell-integration/lostty-tmux/zsh/lostty-tmux.zsh");

/// An OSC body as the snippet sends it: in tmux's DCS passthrough, with the
/// OSC's ESC doubled.
fn wrapped(comptime body: []const u8) []const u8 {
    return "\x1bPtmux;\x1b\x1b]" ++ body ++ "\x07\x1b\\";
}

/// Runs `script` in zsh right after the snippet and returns stdout.
fn runZsh(alloc: std.mem.Allocator, script: []const u8, cwd: ?[]const u8, in_lostty_tmux: bool) ![]u8 {
    std.fs.accessAbsolute("/bin/zsh", .{}) catch return error.SkipZigTest;
    var env = std.process.EnvMap.init(alloc);
    defer env.deinit();
    try env.put("PATH", "/usr/bin:/bin");
    try env.put("HOME", "/nonexistent");
    if (in_lostty_tmux) {
        try env.put("LOSTTY_TMUX", "1");
        try env.put("TMUX", "/private/tmp/tmux-test/lostty,1,0");
    }
    const full = try std.mem.concat(alloc, u8, &.{ snippet, "\n", script });
    defer alloc.free(full);
    const result = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "/bin/zsh", "-f", "-c", full },
        .env_map = &env,
        .cwd = cwd,
    });
    alloc.free(result.stderr);
    return result.stdout;
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

fn base64Alloc(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    const enc = std.base64.standard.Encoder;
    const out = try alloc.alloc(u8, enc.calcSize(s.len));
    _ = enc.encode(out, s);
    return out;
}

test "lostty tmux snippet: wraps an OSC in tmux passthrough with ESC doubled" {
    const alloc = std.testing.allocator;
    const out = try runZsh(alloc, "_lostty_osc '133;C'", null, true);
    defer alloc.free(out);
    try std.testing.expectEqualStrings(wrapped("133;C"), out);
}

test "lostty tmux snippet: does nothing outside Lostty's tmux" {
    const alloc = std.testing.allocator;
    const out = try runZsh(alloc, "print -n after", null, false);
    defer alloc.free(out);
    try std.testing.expectEqualStrings("", out);
}

test "lostty tmux snippet: reports the exit status only after a command ran" {
    const alloc = std.testing.allocator;
    const out = try runZsh(alloc, "_lostty_precmd; print -n '|'; _lostty_preexec; (exit 3); _lostty_precmd", null, true);
    defer alloc.free(out);
    const bar = std.mem.indexOfScalar(u8, out, '|').?;
    try std.testing.expect(!contains(out[0..bar], "133;D"));
    try std.testing.expect(contains(out[bar..], wrapped("133;C")));
    try std.testing.expect(contains(out[bar..], wrapped("133;D;3")));
    // Never prompt marks: Ghostty does a fresh-line on them, which would
    // move its cursor behind tmux's back.
    try std.testing.expect(!contains(out, "133;A"));
    try std.testing.expect(!contains(out, "133;B"));
    try std.testing.expect(!contains(out, "133;P"));
}

test "lostty tmux snippet: reports cwd and project for a path with spaces" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makeDir("my proj");
    const dir = try tmp.dir.realpathAlloc(alloc, "my proj");
    defer alloc.free(dir);

    const out = try runZsh(alloc, "_lostty_precmd", dir, true);
    defer alloc.free(out);
    try std.testing.expect(contains(out, "]7;kitty-shell-cwd://"));
    try std.testing.expect(contains(out, "/my proj\x07"));
    // Not a git repo: the project is the directory itself.
    const b64 = try base64Alloc(alloc, dir);
    defer alloc.free(b64);
    const want = try std.fmt.allocPrint(alloc, "]1337;SetUserVar=LOSTTY_PROJECT={s}\x07", .{b64});
    defer alloc.free(want);
    try std.testing.expect(contains(out, want));
}

test "lostty tmux snippet: the project is the git root" {
    const alloc = std.testing.allocator;
    std.fs.accessAbsolute("/usr/bin/git", .{}) catch return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("repo/sub");
    const root = try tmp.dir.realpathAlloc(alloc, "repo");
    defer alloc.free(root);
    const sub = try tmp.dir.realpathAlloc(alloc, "repo/sub");
    defer alloc.free(sub);
    const init = try std.process.Child.run(.{ .allocator = alloc, .argv = &.{ "/usr/bin/git", "init", "-q" }, .cwd = root });
    alloc.free(init.stdout);
    alloc.free(init.stderr);

    const out = try runZsh(alloc, "_lostty_precmd", sub, true);
    defer alloc.free(out);
    const b64 = try base64Alloc(alloc, root);
    defer alloc.free(b64);
    const want = try std.fmt.allocPrint(alloc, "LOSTTY_PROJECT={s}\x07", .{b64});
    defer alloc.free(want);
    try std.testing.expect(contains(out, want));
}
```

Create an empty `src/shell-integration/lostty-tmux/zsh/lostty-tmux.zsh` (so `@embedFile` compiles), and register: in `src/cli/ghostty.zig`'s final test block add `_ = @import("tmux/snippet_test.zig");`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `zig build test -Dtest-filter="lostty tmux snippet"`
Expected: FAIL (empty snippet: functions not found; only "does nothing outside" may pass).

- [ ] **Step 3: Write the snippet**

`src/shell-integration/lostty-tmux/zsh/lostty-tmux.zsh`:

```zsh
# Lostty: shell signals for panes on Lostty's private tmux (tmux -L lostty).
#
# tmux keeps OSC 7 and OSC 133 for itself, so this re-sends the ones Lostty
# relies on wrapped in tmux's DCS passthrough (Lostty's tmux.conf sets
# allow-passthrough on), which reaches every attached client: the Mac window
# and the phone alike.
#
#   OSC 7          cwd: auto-skin, new tabs/splits      every prompt
#   OSC 133 C / D  command started / finished + status  around each command
#   LOSTTY_PROJECT the project path (git root, else cwd) every prompt
#
# Everything is re-sent at every prompt because a client that attaches later
# (the phone) only sees what comes after it attaches.
#
# Never sends OSC 133 A, B or P: Ghostty does a fresh-line on those, which
# would move its cursor behind tmux's back.
#
# Sourced by .zshenv in this directory, in interactive shells.

[[ -n $LOSTTY_TMUX && -n $TMUX ]] || builtin return 0

# Wraps one escape sequence in tmux's DCS passthrough (ESC inside doubled).
_lostty_passthrough() {
    builtin local e=$'\e'
    builtin print -rn -- "${e}Ptmux;${1//$e/$e$e}${e}\\"
}

_lostty_osc() { _lostty_passthrough $'\e]'"$1"$'\a' }

# The project a directory belongs to: its git root, else the directory.
_lostty_project_of() {
    builtin local root
    root=$(command git -C "$1" rev-parse --show-toplevel 2>/dev/null)
    [[ -n $root ]] || root=$1
    builtin print -rn -- "$root"
}

builtin typeset -g _lostty_pwd= _lostty_project= _lostty_project_b64= _lostty_ran=

_lostty_precmd() {
    builtin local st=$?
    if [[ -n $_lostty_ran ]]; then
        _lostty_osc "133;D;$st"
        _lostty_ran=
    fi
    _lostty_osc "7;kitty-shell-cwd://$HOST$PWD"
    if [[ $PWD != $_lostty_pwd ]]; then
        _lostty_pwd=$PWD
        builtin local project
        project=$(_lostty_project_of "$PWD")
        if [[ $project != $_lostty_project ]]; then
            _lostty_project=$project
            _lostty_project_b64=$(builtin print -rn -- "$project" | command base64 | command tr -d '\n')
            # Name the session after the project, in the background.
            [[ -x $LOSTTY_BIN ]] && { "$LOSTTY_BIN" +tmux-rename -- "$project" >/dev/null 2>&1 &! }
        fi
    fi
    _lostty_osc "1337;SetUserVar=LOSTTY_PROJECT=$_lostty_project_b64"
}

_lostty_preexec() {
    _lostty_osc "133;C"
    _lostty_ran=1
}

builtin autoload -Uz add-zsh-hook
add-zsh-hook precmd _lostty_precmd
add-zsh-hook preexec _lostty_preexec
```

(zsh gives every precmd hook the last command's `$?`, so hook order does not matter; verified while writing this plan.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `zig build test -Dtest-filter="lostty tmux snippet"`
Expected: PASS (5 tests).

- [ ] **Step 5: Write `.zshenv` and `tmux.conf`**

`src/shell-integration/lostty-tmux/zsh/.zshenv` (same pattern as `src/shell-integration/zsh/.zshenv`):

```zsh
# Lostty: zsh startup for panes on Lostty's private tmux. `+tmux-launch`
# points ZDOTDIR here. This restores the user's ZDOTDIR and runs their
# .zshenv; in interactive shells it then loads Ghostty's own zsh integration
# (titles, cursor shape, sudo/ssh helpers; its OSC 7/133 stop at tmux) and
# lostty-tmux.zsh, which re-sends what Lostty needs through tmux.
#
# Sourced with aliases possibly enabled, so builtins are quoted.

if [[ -n "${LOSTTY_ZDOTDIR+X}" ]]; then
    'builtin' 'export' ZDOTDIR="$LOSTTY_ZDOTDIR"
    'builtin' 'unset' 'LOSTTY_ZDOTDIR'
else
    'builtin' 'unset' 'ZDOTDIR'
fi

{
    'builtin' 'typeset' _lostty_file=${ZDOTDIR-$HOME}"/.zshenv"
    [[ ! -r "$_lostty_file" ]] || 'builtin' 'source' '--' "$_lostty_file"
} always {
    if [[ -o 'interactive' ]]; then
        _lostty_file="$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
        if [[ -r "$_lostty_file" ]]; then
            'builtin' 'autoload' '-Uz' '--' "$_lostty_file"
            "${_lostty_file:t}"
            'builtin' 'unfunction' '--' "${_lostty_file:t}"
        fi
        _lostty_file="${${(%):-%x}:A:h}/lostty-tmux.zsh"
        [[ ! -r "$_lostty_file" ]] || 'builtin' 'source' '--' "$_lostty_file"
    fi
    'builtin' 'unset' '_lostty_file'
}
```

`src/shell-integration/lostty-tmux/tmux.conf`:

```tmux
# Lostty's private tmux server (tmux -L lostty). Lostty owns this file; the
# user's ~/.tmux.conf is never read. A pane here should feel like a plain
# Lostty pane, while its session outlives the window and can be attached
# from the phone. Read when the server starts (the first Lostty pane).

# No tmux UI: no status bar, no prefix key (nothing steals Ctrl-B).
set -g status off
set -g prefix None
unbind-key C-b

# Shell signals, titles and the clipboard reach every attached client.
set -g allow-passthrough on
set -s set-clipboard on
set -g set-titles on
set -g set-titles-string '#{pane_title}'

# Size follows whichever client was used last (Mac window or phone).
set -g window-size latest

# Keys and colors as the outer terminal sends them: Esc without delay,
# Shift+Enter and friends for Claude Code, truecolor, focus, hyperlinks.
set -s escape-time 0
set -s extended-keys on
set -s extended-keys-format csi-u
set -s focus-events on
set -g default-terminal 'tmux-256color'
set -as terminal-features ',xterm-ghostty:RGB:extkeys:clipboard:title:focus:strikethrough:usstyle:overline:sync:hyperlinks'

# Mouse: the wheel scrolls back through history (leaving at the bottom);
# a drag selects and copies to the clipboard and stays highlighted.
# Shift+drag still makes a Lostty selection.
set -g mouse on
set -g history-limit 100000
bind-key -T copy-mode MouseDragEnd1Pane send-keys -X copy-selection-no-clear
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-no-clear

# Each session gets its pane's variables (new-session -e); the ones left
# over from whichever pane started the server must not leak into others.
set-environment -gu LOSTTY_SURFACE
set-environment -gu GHOSTTY_SKINS_SURFACE
set-environment -gu LOSTTY_APP_PID
set-environment -gu LOSTTY_TMUX
set-environment -gu ZDOTDIR
```

- [ ] **Step 6: Check the config loads without errors**

Run:

```bash
tmux -L lostty-conftest -f /dev/null new-session -d -s t 'sleep 30' &&
tmux -L lostty-conftest source-file src/shell-integration/lostty-tmux/tmux.conf; echo "exit=$?";
tmux -L lostty-conftest kill-server
```

Expected: `exit=0` and no error lines. If tmux reports an unknown option, check `tmux -V` (needs 3.5+ for `extended-keys-format`) before changing the file.

- [ ] **Step 7: Check the files are installed**

Run: `zig build -Demit-macos-app=false && ls -a zig-out/share/ghostty/shell-integration/lostty-tmux zig-out/share/ghostty/shell-integration/lostty-tmux/zsh`
Expected: `tmux.conf`, `zsh/.zshenv`, `zsh/lostty-tmux.zsh` listed (the existing install of `src/shell-integration` copies the new folder; only `.md` files are excluded).

- [ ] **Step 8: Format and commit**

```bash
zig fmt src/cli/tmux/snippet_test.zig src/cli/ghostty.zig
git add src/shell-integration/lostty-tmux/tmux.conf src/shell-integration/lostty-tmux/zsh/.zshenv \
  src/shell-integration/lostty-tmux/zsh/lostty-tmux.zsh src/cli/tmux/snippet_test.zig src/cli/ghostty.zig
git commit -m "lostty: private tmux config and zsh passthrough snippet"
```

---

### Task 4: `+tmux-launch` and `+tmux-rename`, with an end-to-end smoke test

**Files:**
- Create: `src/cli/tmux_launch.zig`
- Create: `src/cli/tmux_rename.zig`
- Modify: `src/cli/ghostty.zig` (imports, `Action` enum, `run` switch, `options` switch, test block)
- Create: `macos/lostty-tmux-smoke.sh`

**Interfaces:**
- Consumes: Task 1 `naming.*`; Task 2 `session.*`; Task 3 shipped files.
- Produces:
  - CLI `ghostty +tmux-launch [--attach=<session id>]`: never returns normally on success (execs `tmux attach`); on failure prints a `noticeLine` and execs `$SHELL -l` with Ghostty's own zsh integration.
  - CLI `ghostty +tmux-rename [--] <path>`: renames the calling pane's session (`$TMUX_PANE`); silent; exits 0.
  - `pub fn isExecutable(path: []const u8) bool` and `pub fn runTmux(alloc: Allocator, argv: []const []const u8) ?[]u8` in `tmux_launch.zig` (used by `tmux_rename.zig`).
  - Script `macos/lostty-tmux-smoke.sh` (exit 0 and prints `PASS` on success).

- [ ] **Step 1: Write the smoke test (it fails until both actions exist)**

Create `macos/lostty-tmux-smoke.sh` and `chmod +x` it:

```sh
#!/bin/sh
# Lostty Mobile smoke test for panes in tmux sessions. Runs `+tmux-launch`
# inside a throwaway outer tmux (which gives it a terminal, as a Lostty pane
# would), then checks the session's tags and project name, the signals that
# come out of tmux passthrough, that `exit` ends the session, and the
# notice for a session that is gone. Only touches the session it creates.
# Usage: macos/lostty-tmux-smoke.sh   (after building the Debug app)
set -u
cd "$(dirname "$0")/.."
APP="$PWD/macos/build/Debug/Ghostty.app/Contents"
BIN="$APP/MacOS/ghostty"
RES="$APP/Resources/ghostty"
TMUX_BIN=$(command -v tmux || echo /opt/homebrew/bin/tmux)
SURFACE="ABCDEF01-0000-4000-8000-0000000000AA"
WORK=$(mktemp -d)
PROJECT="$WORK/my.project"
RAW="$WORK/raw"
mkdir -p "$PROJECT"
: > "$RAW"

cleanup() {
    "$TMUX_BIN" -L lostty list-sessions -F '#{session_id} #{@lostty_surface}' 2>/dev/null |
        awk -v s="$SURFACE" '$2 == s { print $1 }' |
        while read -r id; do "$TMUX_BIN" -L lostty kill-session -t "$id"; done
    "$TMUX_BIN" -L lostty-smoke kill-server 2>/dev/null
    rm -rf "$WORK"
}
fail() {
    echo "FAIL: $*"
    echo "--- outer pane:"
    "$TMUX_BIN" -L lostty-smoke capture-pane -p -t outer 2>/dev/null
    cleanup
    exit 1
}
# wait_for <what> <command…>: retries the command for up to 10 s.
wait_for() {
    what=$1
    shift
    n=0
    until "$@" >/dev/null 2>&1; do
        n=$((n + 1))
        [ "$n" -gt 50 ] && fail "timed out waiting for $what"
        sleep 0.2
    done
}
our_session() {
    "$TMUX_BIN" -L lostty list-sessions -F '#{@lostty_surface}|#{session_name}|#{@lostty_owner}|#{@lostty_shell}' 2>/dev/null |
        grep "^$SURFACE|"
}
named_and_tagged() { our_session | grep -q "^$SURFACE|my_project|$$|zsh\$"; }
gone() { ! our_session; }
saw() { grep -qF "$1" "$RAW"; }
pane_says() { "$TMUX_BIN" -L lostty-smoke capture-pane -p -t outer | grep -qF "$1"; }

[ -x "$BIN" ] || { echo "FAIL: build the Debug app first ($BIN)"; exit 1; }
[ -f "$RES/shell-integration/lostty-tmux/tmux.conf" ] ||
    { echo "FAIL: $RES has no lostty-tmux; run zig build -Demit-macos-app=false, then rebuild the app"; exit 1; }

"$TMUX_BIN" -L lostty-smoke -f /dev/null new-session -d -s outer -x 120 -y 40 -c "$PROJECT" \
    "env -u TMUX -u TMUX_PANE TERM=xterm-ghostty TERMINFO='$APP/Resources/terminfo' LOSTTY_SURFACE=$SURFACE LOSTTY_APP_PID=$$ LOSTTY_BIN='$BIN' GHOSTTY_RESOURCES_DIR='$RES' SHELL=/bin/zsh '$BIN' +tmux-launch"
"$TMUX_BIN" -L lostty-smoke set -g remain-on-exit on
"$TMUX_BIN" -L lostty-smoke pipe-pane -t outer "cat >> '$RAW'"

wait_for "the pane's session" our_session
wait_for "the session named my_project, owned by this script, shell zsh" named_and_tagged

# One command: 133;C before it, 133;D;<status> after, plus cwd and project.
"$TMUX_BIN" -L lostty-smoke send-keys -t outer 'tput colors > colors.txt' Enter
wait_for "OSC 133;D after a command" saw "]133;D;0"
saw "]133;C" || fail "no OSC 133;C"
saw "]7;kitty-shell-cwd://" || fail "no OSC 7"
saw "SetUserVar=LOSTTY_PROJECT=" || fail "no LOSTTY_PROJECT user var"
saw "]133;A" && fail "OSC 133;A reached the outer terminal"
[ "$(cat "$PROJECT/colors.txt")" = "256" ] || fail "TERM inside tmux is not a 256-color terminal"

# Leaving the shell ends the session.
"$TMUX_BIN" -L lostty-smoke send-keys -t outer 'exit' Enter
wait_for "the session to end" gone

# Adopting a session that no longer exists: one-line notice, then a shell.
"$TMUX_BIN" -L lostty-smoke respawn-pane -k -t outer \
    "env -u TMUX -u TMUX_PANE LOSTTY_SURFACE=$SURFACE LOSTTY_APP_PID=$$ GHOSTTY_RESOURCES_DIR='$RES' SHELL=/bin/zsh '$BIN' +tmux-launch '--attach=\$999999'"
wait_for "the session-gone notice" pane_says "Lostty: that session has ended"

cleanup
echo PASS
```

Run: `zig build -Demit-macos-app=false && xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build -quiet && macos/lostty-tmux-smoke.sh`
Expected: `FAIL: timed out waiting for the pane's session` (the action does not exist yet).

- [ ] **Step 2: Write `src/cli/tmux_launch.zig`**

```zig
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const session = @import("tmux/session.zig");

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

/// The `tmux-launch` command is what each new Lostty pane runs: it starts
/// the pane's shell in its own session on Lostty's private tmux (`tmux -L
/// lostty`) and attaches to it, so the shell outlives the window and can be
/// picked up from the phone. `--attach=<session id>` adopts an existing
/// session instead. If tmux is missing or fails, it prints one line saying
/// so and runs a plain login shell.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();
    const env = session.Env.fromProcess();

    const argv = std.process.argsAlloc(alloc) catch return fallback(alloc, env, .tmux_failed);
    const attach_id = session.attachIdFromArgs(argv);
    const failed: session.Notice = if (attach_id != null) .session_gone else .tmux_failed;
    const tmux = session.findTmux(alloc, env.path, isExecutable) orelse return fallback(alloc, env, .no_tmux);
    const surface = env.surface orelse return fallback(alloc, env, .tmux_failed);
    const resources = env.resources_dir orelse return fallback(alloc, env, .tmux_failed);

    const id: []const u8 = if (attach_id) |want| want else create: {
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = std.posix.getcwd(&cwd_buf) catch return fallback(alloc, env, .tmux_failed);
        const create = session.newSessionArgv(alloc, .{
            .tmux = tmux,
            .env = env,
            .surface = surface,
            .resources_dir = resources,
            .cwd = cwd,
            .pid = std.c.getpid(),
            .size = terminalSize(),
        }) catch return fallback(alloc, env, .tmux_failed);
        const out = runTmux(alloc, create) orelse return fallback(alloc, env, .tmux_failed);
        break :create std.mem.trim(u8, out, " \r\n");
    };
    if (!session.isSessionId(id)) return fallback(alloc, env, failed);

    // A new session records its shell, for "is this pane busy?" when its
    // window closes; an adopted one keeps what it has.
    const shell_name: ?[]const u8 = if (attach_id == null) std.fs.path.basename(env.shellPath()) else null;
    const tag = session.tagArgv(alloc, tmux, id, surface, env.app_pid, shell_name) catch return fallback(alloc, env, failed);
    if (runTmux(alloc, tag) == null) return fallback(alloc, env, failed);
    if (attach_id != null) reportPwd(alloc, tmux, id);

    const attach = session.attachArgv(alloc, tmux, id) catch return fallback(alloc, env, failed);
    const err = std.process.execv(alloc, attach);
    std.log.warn("lostty: could not attach to tmux: {}", .{err});
    return fallback(alloc, env, .tmux_failed);
}

pub fn isExecutable(path: []const u8) bool {
    std.posix.access(path, std.posix.X_OK) catch return false;
    return true;
}

/// Runs a tmux command; its stdout when it exits 0, else null.
pub fn runTmux(alloc: Allocator, argv: []const []const u8) ?[]u8 {
    const result = std.process.Child.run(.{ .allocator = alloc, .argv = argv }) catch return null;
    return switch (result.term) {
        .Exited => |code| if (code == 0) result.stdout else null,
        else => null,
    };
}

/// The pane's size, so the shell starts at the right width rather than
/// tmux's 80x24 until the attach resizes it.
fn terminalSize() ?session.Size {
    const TIOCGWINSZ = if (builtin.os.tag == .macos) 1074295912 else std.posix.T.IOCGWINSZ;
    var ws: std.posix.winsize = undefined;
    if (std.c.ioctl(std.posix.STDIN_FILENO, TIOCGWINSZ, @intFromPtr(&ws)) < 0) return null;
    if (ws.col == 0 or ws.row == 0) return null;
    return .{ .cols = ws.col, .rows = ws.row };
}

/// Tells the window an adopted session's directory right away.
fn reportPwd(alloc: Allocator, tmux: []const u8, id: []const u8) void {
    const out = runTmux(alloc, &.{ tmux, "-L", session.socket, "display-message", "-p", "-t", id, "#{pane_current_path}" }) orelse return;
    const path = std.mem.trim(u8, out, "\r\n");
    if (path.len == 0) return;
    var host_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const host = std.posix.gethostname(&host_buf) catch return;
    const seq = session.pwdSequence(alloc, host, path) catch return;
    std.fs.File.stdout().writeAll(seq) catch {};
}

/// Prints why, then becomes the user's login shell, with Ghostty's own zsh
/// integration as a plain Lostty pane would have.
fn fallback(alloc: Allocator, env: session.Env, notice: session.Notice) u8 {
    std.fs.File.stdout().writeAll(session.noticeLine(notice)) catch {};
    const shell = env.shellPath();
    var env_map = std.process.getEnvMap(alloc) catch return 1;
    if (env.resources_dir) |res| {
        if (session.isZsh(shell)) {
            if (env.zdotdir) |z| env_map.put("GHOSTTY_ZSH_ZDOTDIR", z) catch {};
            const dir = std.fs.path.join(alloc, &.{ res, "shell-integration", "zsh" }) catch return 1;
            env_map.put("ZDOTDIR", dir) catch {};
        }
    }
    const err = std.process.execve(alloc, &.{ shell, "-l" }, &env_map);
    std.log.err("lostty: could not start {s}: {}", .{ shell, err });
    return 1;
}

test {
    _ = @import("tmux/session.zig");
}
```

If `std.c.ioctl`'s request parameter type rejects the comptime integer, mirror `src/pty.zig:95` and `:197` (same constant, same call shape).

- [ ] **Step 3: Write `src/cli/tmux_rename.zig`**

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const session = @import("tmux/session.zig");
const naming = @import("tmux/naming.zig");
const launch = @import("tmux_launch.zig");

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

/// The `tmux-rename` command is run by Lostty's zsh snippet when the shell
/// enters another project: it renames the pane's tmux session after the
/// project (`idfk`, then `idfk-2` for a second pane there), which is how the
/// phone lists sessions. Outside Lostty's tmux it does nothing; it never
/// prints and always exits 0.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const argv = std.process.argsAlloc(alloc) catch return 0;
    const path = naming.pathFromArgs(argv) orelse return 0;
    if (std.posix.getenv("TMUX") == null) return 0;
    const pane = std.posix.getenv("TMUX_PANE") orelse return 0;
    const tmux = session.findTmux(alloc, std.posix.getenv("PATH"), launch.isExecutable) orelse return 0;
    const base = naming.projectName(alloc, path, std.posix.getenv("HOME")) catch return 0;

    // Another pane can take the same name between listing and renaming
    // (two windows opened in one project); then try the next name.
    for (0..5) |_| {
        const current = launch.runTmux(alloc, &.{ tmux, "-L", session.socket, "display-message", "-p", "-t", pane, "#{session_id}\t#{session_name}" }) orelse return 0;
        var fields = std.mem.splitScalar(u8, std.mem.trimEnd(u8, current, "\r\n"), '\t');
        const id = fields.next() orelse return 0;
        const name = fields.next() orelse return 0;
        if (naming.alreadyNamed(name, base)) return 0;

        const listed = launch.runTmux(alloc, &.{ tmux, "-L", session.socket, "list-sessions", "-F", "#{session_name}" }) orelse return 0;
        var taken: std.ArrayList([]const u8) = .empty;
        var lines = std.mem.tokenizeAny(u8, listed, "\r\n");
        while (lines.next()) |line| taken.append(alloc, line) catch return 0;

        const want = naming.uniqueName(alloc, base, taken.items) catch return 0;
        if (launch.runTmux(alloc, &.{ tmux, "-L", session.socket, "rename-session", "-t", id, want }) != null) return 0;
    }
    return 0;
}

test {
    _ = @import("tmux/naming.zig");
}
```

- [ ] **Step 4: Register both actions in `src/cli/ghostty.zig`**

After `const claude_usage = @import("claude_usage.zig");` add:

```zig
const tmux_launch = @import("tmux_launch.zig");
const tmux_rename = @import("tmux_rename.zig");
```

In the `Action` enum, after the `@"claude-usage",` entry add:

```zig
    // Lostty Mobile: run a new pane's shell in its own session on Lostty's
    // private tmux, or adopt an existing session.
    @"tmux-launch",

    // Lostty Mobile: name the pane's tmux session after its project (run
    // by the zsh snippet).
    @"tmux-rename",
```

In the `run` switch, after `.@"claude-usage" => try claude_usage.run(alloc),` add:

```zig
            .@"tmux-launch" => try tmux_launch.run(alloc),
            .@"tmux-rename" => try tmux_rename.run(alloc),
```

In the `options` switch, after `.@"claude-usage" => claude_usage.Options,` add:

```zig
                .@"tmux-launch" => tmux_launch.Options,
                .@"tmux-rename" => tmux_rename.Options,
```

In the final test block add `_ = tmux_launch;` and `_ = tmux_rename;`.

- [ ] **Step 5: Run the Zig tests (nothing regressed, actions compile)**

Run: `zig build test -Dtest-filter="lostty tmux"`
Expected: PASS (naming, session and snippet tests).

- [ ] **Step 6: Run the smoke test**

Run: `zig build -Demit-macos-app=false && xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build -quiet && macos/lostty-tmux-smoke.sh`
Expected: `PASS`.

If it fails, the script prints the outer pane. Common causes: the Debug app was not rebuilt after Task 3 (no `lostty-tmux` in Resources: the script says so); zsh startup files of the user print errors (shown in the pane); `named_and_tagged` timing out with the session still `lostty-…` means `+tmux-rename` did not run: check `LOSTTY_BIN` reached the session with `tmux -L lostty show-environment -t <id> LOSTTY_BIN`.

- [ ] **Step 7: Format and commit**

```bash
zig fmt src/cli/tmux_launch.zig src/cli/tmux_rename.zig src/cli/ghostty.zig
git add src/cli/tmux_launch.zig src/cli/tmux_rename.zig src/cli/ghostty.zig macos/lostty-tmux-smoke.sh
git commit -m "lostty: +tmux-launch and +tmux-rename put each pane in a named tmux session"
```

---

### Task 5: Session model and launch command (Swift, pure + tmux runner)

**Files:**
- Create: `macos/Sources/Features/Sessions/TmuxSession.swift`
- Create: `macos/Sources/Features/Sessions/TmuxClient.swift`
- Create: `macos/Sources/Features/Sessions/SessionLaunch.swift`
- Test: `macos/Tests/Sessions/TmuxSessionTests.swift`
- Test: `macos/Tests/Sessions/SessionLaunchTests.swift`

**Interfaces:**
- Consumes: the tmux options and CLI syntax from Tasks 2 and 4 (`@lostty_surface`, `@lostty_owner`, `@lostty_shell`, `+tmux-launch`, `--attach=`).
- Produces (used by Tasks 6–7):
  - `enum TmuxConstants { socket, surfaceOption, ownerOption, shellOption, appPIDEnvKey, disabledDefaultsKey }`
  - `struct TmuxSession: Equatable, Sendable { id: String; name: String; surface: String?; owner: Int32? }`, `static let listFormat`, `static func parseList(_: String) -> [TmuxSession]`
  - `enum TmuxOwnership { orphans(_:isAlive:), owned(by:in:), available(_:isAlive:), showing(_:ownedBy:in:) }`
  - `struct TmuxPane: Equatable { surface: String; owner: Int32?; command: String; shell: String }`, `static let listFormat`, `static func parseList(_:) -> [TmuxPane]`, `static func isBusy(_ surface: UUID, ownedBy pid: Int32, panes: [TmuxPane]) -> Bool?`
  - `enum ProcessLiveness { static func isAlive(_ pid: Int32) -> Bool }`
  - `struct TmuxClient { var tmuxPath: String?; static func locate(path:isExecutable:) -> String?; func run(_:) -> String?; func sessions() -> [TmuxSession]; func end(_:); func endSessions(showing:ownedBy:); func endSessions(ownedBy:); func disown(_:); func isBusy(surface:ownedBy:) -> Bool? }`
  - `enum SessionLaunch { action; shellQuote(_:); command(existing:binary:disabled:) -> String?; attachCommand(binary:sessionID:) -> String; isLauncher(_:) -> Bool }`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Sessions/TmuxSessionTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private let paneA = UUID(uuidString: "ABCDEF01-0000-4000-8000-000000000001")!
private let paneB = UUID(uuidString: "ABCDEF02-0000-4000-8000-000000000002")!

struct TmuxSessionTests {
    @Test func parsesList() {
        let out = "$1\tidfk\t\(paneA.uuidString)\t4242\n$2\tnotes\t\t\n$3\tmy proj\t\t\n"
        #expect(TmuxSession.parseList(out) == [
            TmuxSession(id: "$1", name: "idfk", surface: paneA.uuidString, owner: 4242),
            TmuxSession(id: "$2", name: "notes", surface: nil, owner: nil),
            TmuxSession(id: "$3", name: "my proj", surface: nil, owner: nil),
        ])
    }

    @Test func skipsMalformedLines() {
        #expect(TmuxSession.parseList("garbage\n\n1\tx\t\t\n$4\t\t\t\n").isEmpty)
    }
}

struct TmuxOwnershipTests {
    // 100 is this Lostty, 200 a Debug build running next to it, 300 crashed.
    let alive: (Int32) -> Bool = { $0 == 100 || $0 == 200 }
    let sessions = [
        TmuxSession(id: "$1", name: "a", surface: paneA.uuidString, owner: 100),
        TmuxSession(id: "$2", name: "b", surface: paneB.uuidString, owner: 200),
        // The crashed Lostty's session for a window that was restored with
        // the same pane UUID.
        TmuxSession(id: "$3", name: "c", surface: paneA.uuidString, owner: 300),
        // Made on the phone.
        TmuxSession(id: "$4", name: "d", surface: nil, owner: nil),
    ]

    @Test func orphansAreOwnedByLosttysThatAreGone() {
        #expect(TmuxOwnership.orphans(sessions, isAlive: alive).map(\.id) == ["$3"])
    }

    @Test func aRunningSecondLosttyIsNotAnOrphan() {
        #expect(!TmuxOwnership.orphans(sessions, isAlive: alive).contains { $0.id == "$2" })
    }

    @Test func quitEndsOnlyOwnSessions() {
        #expect(TmuxOwnership.owned(by: 100, in: sessions).map(\.id) == ["$1"])
    }

    @Test func availableIsWhatNoRunningLosttyShows() {
        #expect(TmuxOwnership.available(sessions, isAlive: alive).map(\.id) == ["$3", "$4"])
    }

    @Test func closingAPaneEndsOnlyThisLosttysSession() {
        #expect(TmuxOwnership.showing(paneA, ownedBy: 100, in: sessions).map(\.id) == ["$1"])
    }
}

struct TmuxPaneTests {
    @Test func atThePromptIsNotBusy() {
        let panes = TmuxPane.parseList("\(paneA.uuidString)\t100\tzsh\tzsh\n")
        #expect(TmuxPane.isBusy(paneA, ownedBy: 100, panes: panes) == false)
    }

    @Test func claudeRunningIsBusy() {
        let panes = TmuxPane.parseList("\(paneA.uuidString)\t100\tclaude\tzsh\n")
        #expect(TmuxPane.isBusy(paneA, ownedBy: 100, panes: panes) == true)
    }

    @Test func unknownDefersToTheCore() {
        // No pane for this surface, or a session without a recorded shell.
        #expect(TmuxPane.isBusy(paneA, ownedBy: 100, panes: []) == nil)
        let noShell = TmuxPane.parseList("\(paneA.uuidString)\t100\tzsh\t\n")
        #expect(TmuxPane.isBusy(paneA, ownedBy: 100, panes: noShell) == nil)
    }

    @Test func otherLosttysPaneIsIgnored() {
        let panes = TmuxPane.parseList(
            "\(paneA.uuidString)\t300\tclaude\tzsh\n\(paneA.uuidString)\t100\tzsh\tzsh\n")
        #expect(TmuxPane.isBusy(paneA, ownedBy: 100, panes: panes) == false)
    }

    @Test func skipsPanesWithoutASurface() {
        #expect(TmuxPane.parseList("\t\tzsh\tzsh\n").isEmpty)
    }
}

struct TmuxClientTests {
    @Test func locatePrefersHomebrewOverABarePATH() {
        let found = TmuxClient.locate(path: "/usr/bin:/bin") {
            $0 == "/opt/homebrew/bin/tmux" || $0 == "/usr/bin/tmux"
        }
        #expect(found == "/opt/homebrew/bin/tmux")
    }

    @Test func locateFallsBackToPATH() {
        #expect(TmuxClient.locate(path: "/usr/bin:/custom/bin") { $0 == "/custom/bin/tmux" } == "/custom/bin/tmux")
    }

    @Test func locateReportsMissingTmux() {
        #expect(TmuxClient.locate(path: "/usr/bin:/bin") { _ in false } == nil)
    }

    @Test func missingTmuxMeansNoSessionsAndNoAnswer() {
        let client = TmuxClient(tmuxPath: nil)
        #expect(client.sessions().isEmpty)
        #expect(client.isBusy(surface: paneA, ownedBy: 100) == nil)
    }
}
#endif
```

`macos/Tests/Sessions/SessionLaunchTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Ghostty

struct SessionLaunchTests {
    let bin = "/Applications/Lostty.app/Contents/MacOS/ghostty"

    @Test func wrapsAPaneWithoutACommand() {
        #expect(SessionLaunch.command(existing: nil, binary: bin, disabled: false)
            == "'/Applications/Lostty.app/Contents/MacOS/ghostty' +tmux-launch")
        #expect(SessionLaunch.command(existing: "", binary: bin, disabled: false) != nil)
    }

    @Test func keepsAnExplicitCommand() {
        #expect(SessionLaunch.command(existing: "vim notes.md", binary: bin, disabled: false) == nil)
    }

    @Test func offSwitchAndMissingBinaryLeaveThePaneAlone() {
        #expect(SessionLaunch.command(existing: nil, binary: bin, disabled: true) == nil)
        #expect(SessionLaunch.command(existing: nil, binary: nil, disabled: false) == nil)
    }

    @Test func quotesSpacesAndQuotes() {
        #expect(SessionLaunch.shellQuote("/Users/me/My Apps/it's/ghostty")
            == "'/Users/me/My Apps/it'\\''s/ghostty'")
    }

    @Test func attachCommandQuotesTheSessionID() {
        // "$3" unquoted would be expanded by the shell that runs the command.
        #expect(SessionLaunch.attachCommand(binary: "/b/ghostty", sessionID: "$3")
            == "'/b/ghostty' +tmux-launch '--attach=$3'")
    }

    @Test func recognizesItsOwnCommands() {
        #expect(SessionLaunch.isLauncher(SessionLaunch.command(existing: nil, binary: bin, disabled: false)))
        #expect(SessionLaunch.isLauncher(SessionLaunch.attachCommand(binary: bin, sessionID: "$3")))
        #expect(!SessionLaunch.isLauncher(nil))
        #expect(!SessionLaunch.isLauncher("vim"))
        #expect(!SessionLaunch.isLauncher("echo +tmux-launch"))
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh TmuxSessionTests`
Expected: FAIL (compile errors: `TmuxSession` not found).

- [ ] **Step 3: Implement `TmuxSession.swift`**

```swift
#if os(macOS)
import Foundation

/// Lostty's private tmux (`tmux -L lostty`). Each pane's shell lives in its
/// own session there, so it outlives the window and can be opened from the
/// phone. `+tmux-launch` (src/cli/tmux_launch.zig) creates and tags the
/// sessions; the Mac app lists, adopts and ends them.
enum TmuxConstants {
    static let socket = "lostty"
    static let surfaceOption = "@lostty_surface"
    static let ownerOption = "@lostty_owner"
    static let shellOption = "@lostty_shell"
    /// Set on every pane so the launcher can tag its session with this
    /// Lostty's pid.
    static let appPIDEnvKey = "LOSTTY_APP_PID"
    /// Debug escape hatch: true in `UserDefaults.ghostty` makes new panes
    /// plain local shells.
    static let disabledDefaultsKey = "LosttyTmuxDisabled"
}

/// A session on Lostty's tmux, as `list-sessions` reports it.
struct TmuxSession: Equatable, Sendable {
    var id: String
    var name: String
    /// The pane (`SurfaceView.id`) showing it on the Mac; nil when none does.
    var surface: String?
    /// Pid of the Lostty that shows it; nil when no Lostty does (made on the
    /// phone, or let go after a crash).
    var owner: Int32?

    static let listFormat = "#{session_id}\t#{session_name}\t#{@lostty_surface}\t#{@lostty_owner}"

    /// Parses `list-sessions -F listFormat`; malformed lines are skipped.
    static func parseList(_ output: String) -> [TmuxSession] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, f[0].hasPrefix("$"), !f[1].isEmpty else { return nil }
            return TmuxSession(id: f[0], name: f[1], surface: f[2].isEmpty ? nil : f[2], owner: Int32(f[3]))
        }
    }
}

/// Who a session belongs to. Several Lostty processes can share the socket
/// (a Debug build next to the app), and a window restored after a crash
/// keeps its pane UUID, so every rule checks the owner too.
enum TmuxOwnership {
    /// Owned by a Lostty that is no longer running: left behind by a crash.
    static func orphans(_ sessions: [TmuxSession], isAlive: (Int32) -> Bool) -> [TmuxSession] {
        sessions.filter { session in session.owner.map { !isAlive($0) } ?? false }
    }

    /// Owned by `pid`: ended when that Lostty quits.
    static func owned(by pid: Int32, in sessions: [TmuxSession]) -> [TmuxSession] {
        sessions.filter { $0.owner == pid }
    }

    /// Shown by no running Lostty: what "Open Session" offers.
    static func available(_ sessions: [TmuxSession], isAlive: (Int32) -> Bool) -> [TmuxSession] {
        sessions.filter { session in session.owner.map { !isAlive($0) } ?? true }
    }

    /// The session(s) showing pane `surface` in Lostty `pid`.
    static func showing(_ surface: UUID, ownedBy pid: Int32, in sessions: [TmuxSession]) -> [TmuxSession] {
        sessions.filter { $0.surface == surface.uuidString && $0.owner == pid }
    }
}

/// A pane on Lostty's tmux, for deciding whether closing its window needs
/// a confirmation.
struct TmuxPane: Equatable {
    var surface: String
    var owner: Int32?
    var command: String
    var shell: String

    static let listFormat = "#{@lostty_surface}\t#{@lostty_owner}\t#{pane_current_command}\t#{@lostty_shell}"

    /// Parses `list-panes -a -F listFormat`; panes no Lostty pane shows are skipped.
    static func parseList(_ output: String) -> [TmuxPane] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, !f[0].isEmpty else { return nil }
            return TmuxPane(surface: f[0], owner: Int32(f[1]), command: f[2], shell: f[3])
        }
    }

    /// Whether pane `surface` of Lostty `pid` runs something other than its
    /// shell. nil when tmux can't tell (no such pane, or no recorded shell);
    /// the caller then keeps the core's answer.
    static func isBusy(_ surface: UUID, ownedBy pid: Int32, panes: [TmuxPane]) -> Bool? {
        let mine = panes.filter { $0.surface == surface.uuidString && $0.owner == pid }
        guard !mine.isEmpty, mine.allSatisfy({ !$0.shell.isEmpty }) else { return nil }
        return mine.contains { $0.command != $0.shell }
    }
}

enum ProcessLiveness {
    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
#endif
```

- [ ] **Step 4: Implement `TmuxClient.swift`**

```swift
#if os(macOS)
import Foundation

/// Runs `tmux -L lostty …` synchronously. Each call takes a few
/// milliseconds; run it off the main thread except where a decision is
/// needed right away (close confirmation, quitting).
struct TmuxClient {
    /// Homebrew's places first: Lostty started from the Dock has a bare PATH.
    static let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]

    var tmuxPath: String? = TmuxClient.locate()

    static func locate(
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let fromPath = (path ?? "").split(separator: ":").map { "\($0)/tmux" }
        return (candidates + fromPath).first(where: isExecutable)
    }

    /// stdout of `tmux -L lostty <args>` when it exits 0; nil when tmux is
    /// missing, no server is running, or the command fails.
    @discardableResult
    func run(_ args: [String]) -> String? {
        guard let tmuxPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = ["-L", TmuxConstants.socket] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func sessions() -> [TmuxSession] {
        run(["list-sessions", "-F", TmuxSession.listFormat]).map(TmuxSession.parseList) ?? []
    }

    func end(_ session: TmuxSession) {
        run(["kill-session", "-t", session.id])
    }

    /// Ends the session showing pane `surface`: closing a pane ends its
    /// shell, as on a plain terminal.
    func endSessions(showing surface: UUID, ownedBy pid: Int32) {
        TmuxOwnership.showing(surface, ownedBy: pid, in: sessions()).forEach(end)
    }

    /// Ends every session Lostty `pid` shows: quitting ends its shells.
    func endSessions(ownedBy pid: Int32) {
        TmuxOwnership.owned(by: pid, in: sessions()).forEach(end)
    }

    /// Lets go of a session: no Lostty shows it any more, so it is not
    /// offered after a crash again; it stays running for the phone and
    /// for Open Session.
    func disown(_ session: TmuxSession) {
        run(["set-option", "-u", "-t", session.id, TmuxConstants.surfaceOption, ";",
             "set-option", "-u", "-t", session.id, TmuxConstants.ownerOption])
    }

    func isBusy(surface: UUID, ownedBy pid: Int32) -> Bool? {
        guard let out = run(["list-panes", "-a", "-F", TmuxPane.listFormat]) else { return nil }
        return TmuxPane.isBusy(surface, ownedBy: pid, panes: TmuxPane.parseList(out))
    }
}
#endif
```

- [ ] **Step 5: Implement `SessionLaunch.swift`**

```swift
#if os(macOS)
import Foundation

/// The command a new pane runs so its shell lives in a session on Lostty's
/// tmux (`+tmux-launch`, src/cli/tmux_launch.zig).
enum SessionLaunch {
    static let action = "+tmux-launch"

    /// The core runs a pane's command through a shell, so every argument is
    /// single-quoted.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The command for a new pane, or nil to leave the pane alone: a pane
    /// that already has a command (scripts, `-e`, Open Session) keeps it,
    /// and so does every pane while tmux sessions are turned off.
    static func command(existing: String?, binary: String?, disabled: Bool) -> String? {
        guard !disabled, (existing ?? "").isEmpty, let binary, !binary.isEmpty else { return nil }
        return "\(shellQuote(binary)) \(action)"
    }

    /// The command for a window that adopts session `sessionID` ("$3").
    static func attachCommand(binary: String, sessionID: String) -> String {
        "\(shellQuote(binary)) \(action) \(shellQuote("--attach=\(sessionID)"))"
    }

    /// True for commands built here: the pane lives in a tmux session.
    static func isLauncher(_ command: String?) -> Bool {
        command?.contains("' \(action)") ?? false
    }
}
#endif
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `macos/skins-test.sh TmuxSessionTests && macos/skins-test.sh TmuxOwnershipTests && macos/skins-test.sh TmuxPaneTests && macos/skins-test.sh TmuxClientTests && macos/skins-test.sh SessionLaunchTests`
Expected: each prints `** TEST SUCCEEDED **` (the script exits 0).

- [ ] **Step 7: Lint and commit**

```bash
swiftlint lint --strict --fix macos/Sources/Features/Sessions macos/Tests/Sessions
swiftlint lint --strict macos/Sources/Features/Sessions macos/Tests/Sessions
git add macos/Sources/Features/Sessions/TmuxSession.swift macos/Sources/Features/Sessions/TmuxClient.swift \
  macos/Sources/Features/Sessions/SessionLaunch.swift macos/Tests/Sessions/TmuxSessionTests.swift \
  macos/Tests/Sessions/SessionLaunchTests.swift
git commit -m "lostty: tmux session model, ownership rules and pane launch command"
```

---

### Task 6: Panes run in tmux sessions (Swift wiring)

**Files:**
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (init ~256–405, `needsConfirmQuit` ~174, `deinit` ~421)
- Modify: `macos/Sources/Ghostty/Ghostty.Config.swift` (next to `windowSaveState`, ~213)
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (`applicationShouldTerminate` ~434, `applicationWillTerminate` ~452)

**Interfaces:**
- Consumes: Task 5 `SessionLaunch`, `TmuxClient`, `TmuxConstants`.
- Produces: `SurfaceView.inTmuxSession: Bool` (a `let`); `Ghostty.Config.confirmCloseSurface: String` (`"true"`, `"false"` or `"always"`).

This task is wiring; its logic is tested in Task 5. Its check is the Debug app itself.

- [ ] **Step 1: Decide at init whether the pane runs in tmux**

In `SurfaceView_AppKit.swift`, add next to the other stored properties near `let id: UUID` (line ~14):

```swift
        /// Lostty Mobile: true when this pane's shell runs in a session on
        /// Lostty's tmux. A constant so `deinit` can read it.
        let inTmuxSession: Bool
```

In `init(_ app:baseConfig:uuid:)`, right after `self.id = uuid ?? .init()`, add:

```swift
            // Lostty Mobile: the pane's shell lives in its own session on
            // Lostty's tmux, so it outlives the window and can be opened
            // from the phone. Decided before super.init (deinit reads it).
            let tmuxLaunch = SessionLaunch.command(
                existing: baseConfig?.command,
                binary: Bundle.main.executableURL?.path,
                disabled: UserDefaults.ghostty.bool(forKey: TmuxConstants.disabledDefaultsKey))
            self.inTmuxSession = SessionLaunch.isLauncher(tmuxLaunch ?? baseConfig?.command)
```

Then, where the env vars are set, change

```swift
            if let bin = Bundle.main.executableURL?.path {
                surface_cfg.environmentVariables[ClaudeConstants.binEnvKey] = bin
            }
            let surface = surface_cfg.withCValue(view: self) { surface_cfg_c in
```

to

```swift
            if let bin = Bundle.main.executableURL?.path {
                surface_cfg.environmentVariables[ClaudeConstants.binEnvKey] = bin
            }
            // Lostty Mobile: the launcher tags the pane's session with this pid.
            surface_cfg.environmentVariables[TmuxConstants.appPIDEnvKey] =
                String(ProcessInfo.processInfo.processIdentifier)
            if let tmuxLaunch {
                surface_cfg.command = tmuxLaunch
            }
            let surface = surface_cfg.withCValue(view: self) { surface_cfg_c in
```

- [ ] **Step 2: Closing a pane ends its session**

In `deinit`, after the existing `Task { @MainActor in … ClaudeUsageRuntime.shared.surfaceClosed(closedID) }` block, add:

```swift
            // Lostty Mobile: closing a pane ends its tmux session, as
            // closing a plain terminal ends its shell.
            if inTmuxSession {
                let pid = ProcessInfo.processInfo.processIdentifier
                Task.detached(priority: .utility) {
                    TmuxClient().endSessions(showing: closedID, ownedBy: pid)
                }
            }
```

- [ ] **Step 3: Ask tmux whether a pane is busy**

In `Ghostty.Config.swift`, after `windowSaveState`, add:

```swift
        /// `confirm-close-surface`: "true", "false" or "always".
        var confirmCloseSurface: String {
            guard let config = self.config else { return "true" }
            var v: UnsafePointer<Int8>?
            let key = "confirm-close-surface"
            guard ghostty_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return "true" }
            guard let ptr = v else { return "true" }
            return String(cString: ptr)
        }
```

In `SurfaceView_AppKit.swift`, replace

```swift
        var needsConfirmQuit: Bool {
            guard let surface = self.surface else { return false }
            return ghostty_surface_needs_confirm_quit(surface)
        }
```

with

```swift
        var needsConfirmQuit: Bool {
            guard let surface = self.surface else { return false }
            let core = ghostty_surface_needs_confirm_quit(surface)
            // Lostty Mobile: tmux draws in the alternate screen, where the
            // core never sees a prompt and always asks. Ask tmux what the
            // pane runs instead.
            guard core, inTmuxSession, !readonly,
                  (NSApp.delegate as? AppDelegate)?.ghostty.config.confirmCloseSurface != "always"
            else { return core }
            let pid = ProcessInfo.processInfo.processIdentifier
            return TmuxClient().isBusy(surface: id, ownedBy: pid) ?? core
        }
```

- [ ] **Step 4: Quit confirmation and quitting**

In `AppDelegate.swift` `applicationShouldTerminate`, change

```swift
        // If our app says we don't need to confirm, we can exit now.
        if !ghostty.needsConfirmQuit { return .terminateNow }
```

to

```swift
        // If our app says we don't need to confirm, we can exit now.
        if !ghostty.needsConfirmQuit { return .terminateNow }

        // Lostty Mobile: the core counts every pane in a tmux session as
        // busy (tmux draws in the alternate screen); ask each pane.
        if !Self.anyPaneNeedsConfirmQuit() { return .terminateNow }
```

and add this method to `AppDelegate` (next to `applicationShouldTerminate`):

```swift
    /// Lostty Mobile: whether any open pane is running something. Panes in
    /// tmux sessions ask tmux; the others answer as the core does.
    private static func anyPaneNeedsConfirmQuit() -> Bool {
        NSApp.windows
            .compactMap { $0.windowController as? BaseTerminalController }
            .contains { $0.surfaceTree.contains(where: { $0.needsConfirmQuit }) }
    }
```

In `applicationWillTerminate`, after the `removeAllDeliveredNotifications()` line, add:

```swift
        // Lostty Mobile: quitting ends this Lostty's tmux sessions, as
        // quitting a plain terminal ends its shells. Sessions made on the
        // phone, and other Lostty processes' sessions, stay.
        TmuxClient().endSessions(ownedBy: ProcessInfo.processInfo.processIdentifier)
```

- [ ] **Step 5: Build, lint, and re-run the Swift tests**

Run:

```bash
swiftlint lint --strict --fix "macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift" macos/Sources/Ghostty/Ghostty.Config.swift macos/Sources/App/macOS/AppDelegate.swift
zig build -Demit-macos-app=false && xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build -quiet
macos/skins-test.sh TmuxSessionTests && macos/skins-test.sh SessionLaunchTests
```

Expected: build succeeds; tests pass.

- [ ] **Step 6: Check a Debug window lands in a tagged session**

Run (the Debug app runs next to the installed Lostty; they share the socket by design):

```bash
open -n macos/build/Debug/Ghostty.app
for i in $(seq 50); do PID=$(pgrep -n -f 'macos/build/Debug/Ghostty.app/Contents/MacOS/ghostty$'); [ -n "$PID" ] && tmux -L lostty list-sessions -F '#{@lostty_owner}' 2>/dev/null | grep -qx "$PID" && break; sleep 0.2; done
tmux -L lostty list-sessions -F '#{session_name} owner=#{@lostty_owner} shell=#{@lostty_shell} surface=#{@lostty_surface}'
echo "debug app pid: $PID"
```

Expected: a line for the Debug app's first window with `owner=<debug app pid> shell=zsh` and a UUID; its name is the project of the window's starting directory (`home` when it opens in `~`).

Then quit it normally: `osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to keystroke \"q\" using command down"` (or ask your human partner to press Cmd+Q in the Debug app). Expected: the app quits without a confirmation, and `tmux -L lostty list-sessions -F '#{@lostty_owner}' | grep -cx "$PID"` prints `0`.

- [ ] **Step 7: Commit**

```bash
git add "macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift" macos/Sources/Ghostty/Ghostty.Config.swift \
  macos/Sources/App/macOS/AppDelegate.swift
git commit -m "lostty: every pane runs in its own tmux session; close and quit end them"
```

---

### Task 7: Reopen sessions after a crash; Open Session in the command palette

**Files:**
- Create: `macos/Sources/Features/Sessions/SessionsUI.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (`applicationDidFinishLaunching`, after `HookNotifications.checkAtLaunch()` ~344)
- Modify: `macos/Sources/Features/Command Palette/TerminalCommandPalette.swift`
- Test: `macos/Tests/Sessions/SessionsPromptTests.swift`

**Interfaces:**
- Consumes: Task 5 `TmuxClient`, `TmuxOwnership`, `ProcessLiveness`, `SessionLaunch.attachCommand`; `TerminalController.newWindow(_:withBaseConfig:)`.
- Produces: `SessionsUI.offerOrphansAtLaunch(_ ghostty: Ghostty.App)`, `SessionsUI.open(_ session: TmuxSession, ghostty: Ghostty.App)`, `SessionsPrompt.reopen(_:) -> (title: String, body: String)`, `SessionsModel.shared` with `available: [TmuxSession]` and `refresh()`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Sessions/SessionsPromptTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Ghostty

struct SessionsPromptTests {
    @Test func oneSession() {
        let text = SessionsPrompt.reopen([TmuxSession(id: "$1", name: "idfk", surface: "S", owner: 9)])
        #expect(text.title == "Reopen 1 terminal session?")
        #expect(text.body.contains("idfk"))
    }

    @Test func severalSessionsAreNamed() {
        let text = SessionsPrompt.reopen([
            TmuxSession(id: "$1", name: "idfk", surface: "S", owner: 9),
            TmuxSession(id: "$2", name: "notes", surface: "T", owner: 9),
        ])
        #expect(text.title == "Reopen 2 terminal sessions?")
        #expect(text.body.contains("idfk, notes"))
        // Says what Not Now does.
        #expect(text.body.contains("Not Now"))
    }
}
#endif
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `macos/skins-test.sh SessionsPromptTests`
Expected: FAIL (`SessionsPrompt` not found).

- [ ] **Step 3: Implement `SessionsUI.swift`**

```swift
#if os(macOS)
import AppKit
import SwiftUI

/// Lostty Mobile on the Mac: reopening sessions a crash left running, and
/// opening sessions no window shows (started on the phone, or kept).
enum SessionsUI {
    /// After a crash, offers to reopen the sessions the previous Lostty
    /// left running. Normal quits end them, so usually there are none.
    @MainActor static func offerOrphansAtLaunch(_ ghostty: Ghostty.App) {
        Task { @MainActor in
            let orphans = await Task.detached(priority: .utility) {
                TmuxOwnership.orphans(TmuxClient().sessions(), isAlive: ProcessLiveness.isAlive)
            }.value
            guard !orphans.isEmpty else { return }
            let text = SessionsPrompt.reopen(orphans)
            let alert = NSAlert()
            alert.messageText = text.title
            alert.informativeText = text.body
            alert.addButton(withTitle: "Reopen")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                orphans.forEach { open($0, ghostty: ghostty) }
            } else {
                Task.detached(priority: .utility) {
                    let client = TmuxClient()
                    orphans.forEach(client.disown)
                }
            }
        }
    }

    /// Opens a window showing `session`. The launcher re-tags the session
    /// with the new pane and this Lostty.
    @MainActor static func open(_ session: TmuxSession, ghostty: Ghostty.App) {
        guard let binary = Bundle.main.executableURL?.path else { return }
        var config = Ghostty.SurfaceConfiguration()
        config.command = SessionLaunch.attachCommand(binary: binary, sessionID: session.id)
        _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
    }
}

enum SessionsPrompt {
    static func reopen(_ sessions: [TmuxSession]) -> (title: String, body: String) {
        let count = sessions.count
        let title = count == 1 ? "Reopen 1 terminal session?" : "Reopen \(count) terminal sessions?"
        let names = sessions.map(\.name).joined(separator: ", ")
        let body = "Lostty quit unexpectedly while these were open, and they are still running: \(names). "
            + "Not Now keeps them running; open them later from the command palette or the phone."
        return (title, body)
    }
}

/// Sessions the command palette offers ("Open Session: idfk"), refreshed
/// each time the palette opens.
@MainActor
final class SessionsModel: ObservableObject {
    static let shared = SessionsModel()

    @Published private(set) var available: [TmuxSession] = []

    func refresh() {
        Task {
            available = await Task.detached(priority: .userInitiated) {
                TmuxOwnership.available(TmuxClient().sessions(), isAlive: ProcessLiveness.isAlive)
            }.value
        }
    }
}
#endif
```

- [ ] **Step 4: Offer orphans at launch**

In `AppDelegate.swift` `applicationDidFinishLaunching`, after `HookNotifications.checkAtLaunch()`, add:

```swift

        // Lostty Mobile: after a crash, offer to reopen the tmux sessions
        // the previous Lostty left running.
        SessionsUI.offerOrphansAtLaunch(ghostty)
```

- [ ] **Step 5: Open Session entries in the command palette**

In `TerminalCommandPalette.swift`:

Add a stored property after `var updateViewModel: UpdateViewModel?` (internal, not private, so the memberwise initializer keeps working; callers don't pass it):

```swift
    /// Lostty Mobile: tmux sessions no window shows.
    @ObservedObject var sessions = SessionsModel.shared
```

In `commandOptions`, change `(jumpOptions + terminalOptions)` to `(jumpOptions + terminalOptions + sessionOptions)`.

In `.onChange(of: isPresented) { newValue in`, add as the first statement:

```swift
            if newValue { sessions.refresh() }
```

Add after `jumpOptions`:

```swift
    /// Lostty Mobile: sessions no window shows (started on the phone, or
    /// kept after a crash), opened in a new window.
    private var sessionOptions: [CommandOption] {
        guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return [] }
        return sessions.available.map { session in
            CommandOption(
                title: "Open Session: \(session.name)",
                subtitle: "tmux session on this Mac",
                leadingIcon: "terminal"
            ) {
                SessionsUI.open(session, ghostty: ghostty)
            }
        }
    }
```

(`CommandOption.init` defaults every argument except `title` and `action`; see `CommandPalette.swift:27`.)

- [ ] **Step 6: Run the tests, build, lint**

Run:

```bash
macos/skins-test.sh SessionsPromptTests
swiftlint lint --strict --fix macos/Sources/Features/Sessions "macos/Sources/Features/Command Palette/TerminalCommandPalette.swift" macos/Sources/App/macOS/AppDelegate.swift macos/Tests/Sessions
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build -quiet
```

Expected: test passes; build succeeds.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/Sessions/SessionsUI.swift macos/Tests/Sessions/SessionsPromptTests.swift \
  macos/Sources/App/macOS/AppDelegate.swift "macos/Sources/Features/Command Palette/TerminalCommandPalette.swift"
git commit -m "lostty: reopen tmux sessions after a crash; Open Session in the command palette"
```

---

### Task 8: Desk check with your human partner

No new code unless a check fails (then fix in the task that owns the code, re-run its tests, commit there). Output: the checklist results reported to your human partner, and any failures fixed or written down.

**Files:**
- Modify (only if a check needs it): files from Tasks 3–7.
- Modify: `docs/superpowers/specs/2026-10-09-lostty-mobile-design.md` (§2: one line per decision from "Decisions this plan adds", so the spec matches what was built).

- [ ] **Step 1: Run everything automated**

Run:

```bash
zig build test -Dtest-filter="lostty tmux"
for s in TmuxSessionTests TmuxOwnershipTests TmuxPaneTests TmuxClientTests SessionLaunchTests SessionsPromptTests; do macos/skins-test.sh $s || echo "FAILED $s"; done
zig build -Demit-macos-app=false && xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build -quiet && macos/lostty-tmux-smoke.sh
```

Expected: all pass; smoke prints `PASS`.

- [ ] **Step 2: Ask your human partner to run the desk checklist in the Debug app**

Send them this (they open `macos/build/Debug/Ghostty.app`; quit the installed Lostty first so the two don't get mixed up):

> Please check these in the Debug Lostty and tell me which ones fail:
> 1. Cmd+N: the window opens at a prompt. `echo $TMUX` prints something; `tmux -L lostty ls` lists a session named after the project.
> 2. `cd` into a project with a mapped skin: the skin switches (auto-skin).
> 3. New tab and new split open in the same directory.
> 4. Run `claude`, send a prompt: the trace runs, "Ready for response" appears when it finishes, the usage bar fills. Press Esc mid-answer once: the trace stops.
> 5. In Claude, Shift+Enter inserts a newline; Esc is instant.
> 6. Scroll wheel scrolls back and returns at the bottom; a drag selects and Cmd+V pastes it; Shift+drag makes a normal Lostty selection.
> 7. Close a window sitting at a prompt: no confirmation, and its session disappears from `tmux -L lostty ls`. Close one with `claude` running: a confirmation appears.
> 8. With only prompts open, Cmd+Q quits without asking; `tmux -L lostty ls` then shows none of those sessions.
> 9. The window/tab title shows the directory, and Claude's title while it runs.
> 10. `exit` in a window closes it.
> 11. Second client: with a window open, run `tmux -L lostty attach -t <its name>` in Terminal.app. Typing in either shows in both; `cd` in Terminal.app still switches the Lostty window's skin.
> 12. Crash: open two windows, run `kill -9 $(pgrep -n -f 'Debug/Ghostty.app/Contents/MacOS/ghostty$')`, relaunch: "Reopen 2 terminal sessions?" appears; Reopen shows both shells with their history, skinned right away.
> 13. Crash again, choose Not Now. Open the command palette (Cmd+Shift+P): "Open Session: <name>" entries are there and open the sessions.
> 14. `brew unlink tmux`, open a new window: one dim "Lostty: tmux not found…" line, then a normal prompt (title and cwd work). Then `brew link tmux`.

- [ ] **Step 3: Fix failures**

For each failing check: use superpowers:systematic-debugging, fix in the owning task's files, re-run that task's tests and the smoke test, and commit with a message naming the check (e.g. `lostty: tmux keeps Shift+Enter for Claude (desk check 5)`). Known levers: tmux options live in `tmux.conf` (keys: `extended-keys*`, `terminal-features`; titles: `set-titles*`; mouse: the `copy-mode` bindings); signals live in `lostty-tmux.zsh`.

A check that cannot be fixed within this phase (e.g. scroll feel, the spec's first risk) is written down for your human partner with what was observed, not silently dropped.

- [ ] **Step 4: Bring the spec up to date and commit**

In `docs/superpowers/specs/2026-10-09-lostty-mobile-design.md` §2, add a short "As built (phase 1)" list: session per pane; only OSC 133 C/D through passthrough (A/B/P fresh-line); Ghostty's zsh integration loaded inside tmux; owner pid on every session; close confirmation asks tmux; Not Now disowns; `Open Session: <name>` palette entries; `LosttyTmuxDisabled` off switch; plus any desk-check outcome your human partner wants recorded.

```bash
git add docs/superpowers/specs/2026-10-09-lostty-mobile-design.md
git commit -m "docs: Lostty Mobile spec records how phase 1 was built"
```
