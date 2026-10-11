# Lostty Mobile Phase 2: Remote Backend and LosttyRemote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Lostty surface can be driven by bytes from the app instead of a local process, and a debug-only Mac window uses that to open one of the Mac's own tmux sessions over SSH to `localhost`, proving the core backend and the SSH layer before any iOS work.

**Architecture:** The core gains a second termio backend, `remote` (`src/termio/Remote.zig`): it spawns nothing, sends the terminal's output (keystrokes, pastes, replies) and size changes to the app through two C callbacks, and takes received bytes through `ghostty_surface_io_feed`, which runs them through the same `Termio.processOutput` path the exec backend's read thread uses. A local Swift package, `LosttyRemote` (`macos/LosttyRemote`), does SSH with Citadel: a Secure Enclave P-256 key, host keys pinned on first use, `tmux -L lostty list-sessions`, and a PTY channel running `tmux attach -t '$N'`. In the app, `RemoteSurfaceIO` joins the two, reconnecting with backoff, and a DEBUG menu item opens a window on a chosen session.

**Tech Stack:** Zig 0.15.2 (core), Swift 5 language mode (app, package), Citadel 0.12.1 (SSH, on the Wellz26 swift-nio-ssh fork), CryptoKit Secure Enclave, Swift Testing, Xcode project `macos/Ghostty.xcodeproj`.

**Spec:** `docs/superpowers/specs/2026-10-09-lostty-mobile-design.md` (§3 core backend, §4 LosttyRemote, Build order step 2, and the "As built (phase 1)" notes in §2).

## Global Constraints

- Core changes stay self-contained for upstream merges: the new file `src/termio/Remote.zig` plus small switch arms in `src/termio/backend.zig`, `src/Surface.zig`, `src/apprt/embedded.zig` and additions at the end of structs/sections in `include/ghostty.h`. Every core edit outside `Remote.zig` carries a `// Lostty Mobile:` comment.
- C API, exactly: surface config gains an IO mode (`GHOSTTY_SURFACE_IO_LOCAL = 0` default, `GHOSTTY_SURFACE_IO_REMOTE = 1`) and two callbacks, `write(userdata, bytes, len)` and `resize(userdata, cols, rows, width_px, height_px)`; new functions `ghostty_surface_io_feed(surface, bytes, len)` (thread-safe), `ghostty_surface_io_disconnected(surface)` (quiet "reconnecting…", not "process exited") and `ghostty_surface_io_exited(surface, exit_code)` (main thread).
- The remote backend skips termios polling, shell-integration injection and child-pid cwd lookup (it has no process).
- SSH: Citadel, pinned `exact: "0.12.1"`. Never add apple/swift-nio-ssh beside it (Citadel uses a fork with the same product name).
- Auth: an ECDSA P-256 key in the Secure Enclave, used behind user presence (Touch ID on the Mac, Face ID later on the phone). Host key pinned on first connect; a mismatch is a hard stop with a clear message, never a silent accept.
- tmux over SSH: always `-L lostty`; sessions targeted by id `$N` (single-quoted in shell commands); never `attach -d` (it would close the Mac window and kill the session); the viewer never starts a tmux server. SSH commands run with a minimal PATH, so every command prefixes `PATH=/opt/homebrew/bin:/usr/local/bin:$PATH`.
- Attach runs `tmux -u` with `TERM=xterm-ghostty` (from the PTY request) and `TERMINFO` set to Lostty.app's `Contents/Resources/terminfo`.
- Closing a remote window closes only the SSH channel: the tmux session keeps running (it belongs to its Mac window, or to the phone later).
- The Mac app's deployment target rises from 13.0 to 14.0 (Citadel's floor). Citadel's PTY API needs macOS 15 at runtime, so remote code is `@available(macOS 15, *)` and the debug menu checks `#available(macOS 15, *)`.
- The debug window is DEBUG-only (`#if DEBUG`) and connects to `localhost:22` as the current user.
- Scope: spec §4's "reconnect on app foreground and network change" is the iPhone app's job (phase 3: scene phase and `NWPathMonitor` call into the same reconnect loop). Phase 2 reconnects on a dropped connection with backoff, which is what the Mac debug window needs.
- Tests: Zig `zig build test -Dtest-filter="lostty remote"`; package `cd macos/LosttyRemote && swift test`; app suites `macos/skins-test.sh <Suite>` (needs `zig build -Demit-macos-app=false` first for the xcframework). Debug app build: `zig build -Demit-macos-app=false && xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build`.
- Commits: stage files by path (never `default.profraw`); end each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never create a PR or issue. swiftlint is not installed; match the surrounding style by eye.

## Review Focus

1. **tmux not on the SSH PATH.** A non-interactive SSH command gets `/usr/bin:/bin:/usr/sbin:/sbin`, and tmux lives in `/opt/homebrew/bin`; a reasonable person expects the session list and attach to work anyway. Pinned by `TmuxRemoteTests` (Task 3): both commands start with the Homebrew PATH.
2. **Session id is shell syntax.** `$3` unquoted is expanded by the remote shell to an empty string and attaches to the wrong session; ids must be single-quoted and anything that is not `$<digits>` refused. Pinned by `TmuxRemoteTests` (Task 3).
3. **No tmux server / no sessions.** `list-sessions` exits 1 with "no server running"; the user expects "no sessions to open", not an error. `RemoteConnection.sessions` maps a failed command to `[]` (Task 4, code — Citadel's error type can't be built in a unit test), `TmuxRemoteTests.emptyOrGarbageListIsNoSessions` pins the parse side (Task 3), and the debug menu says "No Lostty tmux sessions are running" (Task 6).
4. **The session ends while the viewer is attached** (`exit` in the shell, on the Mac or here): the window should close, not loop on "reconnecting…". A dropped connection, by contrast, should show "reconnecting…", retry with backoff, and reattach the same session. Pinned by `AttachEndTests` (Task 3) and `RemoteSessionRunnerTests` (Task 5).
5. **Host key changed.** The user expects a hard stop naming the problem, and the old key kept, never a silent re-pin. Pinned by `KnownHostsTests` (Task 3) and `PinnedHostKeysTests` (Task 4).

---

## File Structure

| File | Responsibility |
|---|---|
| `src/termio/Remote.zig` (new) | The `remote` termio backend: callbacks out, notice text, runtime for exits. |
| `src/termio/backend.zig` | `Kind.remote` and switch arms. |
| `src/termio.zig` | Exports `Remote`. |
| `src/apprt/embedded.zig` | Surface options gain the IO fields; `termioRemote()`; the three `ghostty_surface_io_*` exports. |
| `src/Surface.zig` | Picks the remote backend when the runtime asks for it; abnormal-exit text arm. |
| `include/ghostty.h` | The C declarations. |
| `macos/LosttyRemote/` (new package) | SSH and tmux-over-SSH, shared with the future iPhone app. No GhosttyKit dependency. |
| `…/Sources/LosttyRemote/TmuxRemote.swift` | Shell commands for listing and attaching; session-list parsing. |
| `…/Sources/LosttyRemote/KnownHosts.swift` | Host-key pinning store (file-backed). |
| `…/Sources/LosttyRemote/AttachEnd.swift` | How an attach ended, and the reconnect backoff. |
| `…/Sources/LosttyRemote/RemoteKey.swift` | Secure Enclave key, its `authorized_keys` line, the auth delegate. |
| `…/Sources/LosttyRemote/RemoteConnection.swift` | Citadel connection: pinning, `sessions()`, `attach(…)`, `RemoteTerminal`. |
| `macos/Sources/Ghostty/Surface View/SurfaceView.swift` | `Ghostty.RemoteIO` protocol; `SurfaceConfiguration.remoteIO` → C fields. |
| `macos/Sources/Ghostty/Ghostty.Surface.swift` | `keepAlive` holds the remote IO until the C surface is freed. |
| `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | Remote panes skip the tmux launcher, attach/detach the IO, never ask to close. |
| `macos/Sources/Features/Remote/RemoteSurfaceIO.swift` (new) | Bridges a surface and a remote session: feed, write, resize, reconnect loop. |
| `macos/Sources/Features/Remote/RemoteDebugUI.swift` (new, DEBUG) | "Open Remote Session…" and "Copy Remote Key" menu items. |
| `macos/Tests/Remote/RemoteSurfaceIOTests.swift` (new) | Bridge and runner tests with fakes. |
| `macos/Ghostty.xcodeproj/project.pbxproj` | Links the local package; deployment target 14.0. |

---

### Task 1: The `remote` termio backend

**Files:**
- Create: `src/termio/Remote.zig`
- Modify: `src/termio/backend.zig`, `src/termio.zig`

**Interfaces:**
- Produces: `termio.Remote` with `pub const WriteFn`, `pub const ResizeFn`, `pub const Config = struct { userdata: ?*anyopaque, write: WriteFn, resize: ResizeFn }`, `pub const disconnected_notice: []const u8`, `pub fn init(Config) !Remote`, `pub fn runtimeMs(*const Remote) u64`, the backend methods (`deinit`, `initTerminal`, `threadEnter`, `threadExit`, `focusGained`, `resize`, `queueWrite`, `childExitedAbnormally`), and `pub const ThreadData`. `termio.backend.Kind` becomes `enum { exec, remote }`.

- [ ] **Step 1: Write the failing tests**

Create `src/termio/Remote.zig` with only the tests and the minimal declarations they reference commented out — simplest is to write the whole file from Step 3 but with the bodies of `queueWrite` and `resize` empty (`_ = …;`), so the tests compile and fail. The tests (append at the end of `src/termio/Remote.zig`):

```zig
const TestSink = struct {
    written: std.ArrayList(u8) = .empty,
    cols: u16 = 0,
    rows: u16 = 0,
    width_px: u32 = 0,
    height_px: u32 = 0,
    resizes: usize = 0,

    fn write(ud: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) void {
        const self: *TestSink = @ptrCast(@alignCast(ud.?));
        self.written.appendSlice(std.testing.allocator, bytes[0..len]) catch unreachable;
    }

    fn resize(ud: ?*anyopaque, cols: u16, rows: u16, width_px: u32, height_px: u32) callconv(.c) void {
        const self: *TestSink = @ptrCast(@alignCast(ud.?));
        self.cols = cols;
        self.rows = rows;
        self.width_px = width_px;
        self.height_px = height_px;
        self.resizes += 1;
    }

    fn config(self: *TestSink) Config {
        return .{ .userdata = self, .write = write, .resize = resize };
    }
};

test "lostty remote: typed bytes go to the write callback unchanged" {
    var sink: TestSink = .{};
    defer sink.written.deinit(std.testing.allocator);
    var remote = try Remote.init(sink.config());
    try remote.queueWrite(std.testing.allocator, undefined, "ls\r\x1b[A", false);
    try std.testing.expectEqualStrings("ls\r\x1b[A", sink.written.items);
}

test "lostty remote: linefeed mode sends each CR as CRLF" {
    var sink: TestSink = .{};
    defer sink.written.deinit(std.testing.allocator);
    var remote = try Remote.init(sink.config());
    try remote.queueWrite(std.testing.allocator, undefined, "a\rb\r", true);
    try std.testing.expectEqualStrings("a\r\nb\r\n", sink.written.items);
}

test "lostty remote: an empty write calls nothing" {
    var sink: TestSink = .{};
    defer sink.written.deinit(std.testing.allocator);
    var remote = try Remote.init(sink.config());
    try remote.queueWrite(std.testing.allocator, undefined, "", false);
    try std.testing.expectEqual(@as(usize, 0), sink.written.items.len);
}

test "lostty remote: resize reports cells and pixels" {
    var sink: TestSink = .{};
    var remote = try Remote.init(sink.config());
    try remote.resize(.{ .columns = 120, .rows = 40 }, .{ .width = 1200, .height = 800 });
    try std.testing.expectEqual(@as(u16, 120), sink.cols);
    try std.testing.expectEqual(@as(u16, 40), sink.rows);
    try std.testing.expectEqual(@as(u32, 1200), sink.width_px);
    try std.testing.expectEqual(@as(u32, 800), sink.height_px);
}

test "lostty remote: initTerminal reports the starting size" {
    var sink: TestSink = .{};
    var remote = try Remote.init(sink.config());
    var t = try terminal.Terminal.init(std.testing.allocator, .{ .cols = 80, .rows = 24 });
    defer t.deinit(std.testing.allocator);
    t.width_px = 640;
    t.height_px = 480;
    remote.initTerminal(&t);
    try std.testing.expectEqual(@as(usize, 1), sink.resizes);
    try std.testing.expectEqual(@as(u16, 80), sink.cols);
    try std.testing.expectEqual(@as(u16, 24), sink.rows);
    try std.testing.expectEqual(@as(u32, 640), sink.width_px);
}

test "lostty remote: the disconnected notice shows on screen" {
    const alloc = std.testing.allocator;
    var t = try terminal.Terminal.init(alloc, .{ .cols = 40, .rows = 5 });
    defer t.deinit(alloc);
    var s = t.vtStream();
    defer s.deinit();
    try s.nextSlice("$ claude");
    try s.nextSlice(disconnected_notice);
    const screen = try t.plainString(alloc);
    defer alloc.free(screen);
    try std.testing.expect(std.mem.indexOf(u8, screen, "$ claude") != null);
    try std.testing.expect(std.mem.indexOf(u8, screen, "reconnecting") != null);
}

test "lostty remote: runtime counts from creation" {
    var sink: TestSink = .{};
    const remote = try Remote.init(sink.config());
    try std.testing.expect(remote.runtimeMs() < 5_000);
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Add `pub const Remote = @import("termio/Remote.zig");` to `src/termio.zig` (next to `pub const Exec = …`) so the tests are reached through `refAllDecls`.

Run: `zig build test -Dtest-filter="lostty remote"`
Expected: FAIL — "typed bytes go to the write callback unchanged" (nothing written) and "resize reports cells and pixels".

- [ ] **Step 3: Write `src/termio/Remote.zig`**

```zig
//! Remote is the termio backend for a terminal whose program runs on
//! another machine (Lostty Mobile: a tmux session reached over SSH). It
//! starts no process and owns no pty, so there is no termios polling, no
//! shell-integration injection and no child-pid cwd lookup. The app pushes
//! what it receives in with `ghostty_surface_io_feed`; what the terminal
//! sends (keystrokes, pastes, replies to queries) and its size go out
//! through the app's callbacks.
//!
//! Lostty-only: kept to this file plus small switch arms, so upstream
//! Ghostty merges stay easy.
const Remote = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");
const termio = @import("../termio.zig");

/// Bytes for the remote program. Called on the termio thread; the app
/// must copy them before returning and must not block.
pub const WriteFn = *const fn (
    userdata: ?*anyopaque,
    bytes: [*]const u8,
    len: usize,
) callconv(.c) void;

/// The terminal's size in cells and pixels. Called once while the surface
/// is created (before the app has the surface pointer), then on the termio
/// thread.
pub const ResizeFn = *const fn (
    userdata: ?*anyopaque,
    cols: u16,
    rows: u16,
    width_px: u32,
    height_px: u32,
) callconv(.c) void;

pub const Config = struct {
    userdata: ?*anyopaque,
    write: WriteFn,
    resize: ResizeFn,
};

/// Written to the screen when the connection drops. When the app attaches
/// again tmux redraws the whole screen, which replaces it.
pub const disconnected_notice = "\x1b[0m\r\n\x1b[2mreconnecting\u{2026}\x1b[0m";

config: Config,

/// When the surface was created: an exit reports how long it ran.
created: std.time.Instant,

pub fn init(config: Config) !Remote {
    return .{ .config = config, .created = try std.time.Instant.now() };
}

pub fn deinit(self: *Remote) void {
    _ = self;
}

/// Tells the app the starting size, so it can ask the remote end for a pty
/// that big.
pub fn initTerminal(self: *Remote, term: *terminal.Terminal) void {
    self.resize(.{
        .columns = term.cols,
        .rows = term.rows,
    }, .{
        .width = term.width_px,
        .height = term.height_px,
    }) catch unreachable;
}

pub fn threadEnter(
    self: *Remote,
    alloc: Allocator,
    io: *termio.Termio,
    td: *termio.Termio.ThreadData,
) !void {
    _ = self;
    _ = alloc;
    _ = io;
    td.backend = .{ .remote = .{} };
}

pub fn threadExit(self: *Remote, td: *termio.Termio.ThreadData) void {
    _ = self;
    _ = td;
}

/// Nothing to do: there is no local pty whose termios to watch.
pub fn focusGained(
    self: *Remote,
    td: *termio.Termio.ThreadData,
    focused: bool,
) !void {
    _ = self;
    _ = td;
    _ = focused;
}

pub fn resize(
    self: *Remote,
    grid_size: renderer.GridSize,
    screen_size: renderer.ScreenSize,
) !void {
    self.config.resize(
        self.config.userdata,
        grid_size.columns,
        grid_size.rows,
        screen_size.width,
        screen_size.height,
    );
}

pub fn queueWrite(
    self: *Remote,
    alloc: Allocator,
    td: *termio.Termio.ThreadData,
    data: []const u8,
    linefeed: bool,
) !void {
    _ = td;
    if (data.len == 0) return;
    if (!linefeed) {
        self.config.write(self.config.userdata, data.ptr, data.len);
        return;
    }

    // As the exec backend does in linefeed mode: each CR goes out as CRLF.
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alloc);
    try buf.ensureTotalCapacity(alloc, data.len * 2);
    for (data) |ch| {
        buf.appendAssumeCapacity(ch);
        if (ch == '\r') buf.appendAssumeCapacity('\n');
    }
    self.config.write(self.config.userdata, buf.items.ptr, buf.items.len);
}

/// The app reports exits itself (`ghostty_surface_io_exited`); there is no
/// local command whose failure to explain.
pub fn childExitedAbnormally(
    self: *Remote,
    gpa: Allocator,
    t: *terminal.Terminal,
    exit_code: u32,
    runtime_ms: u64,
) !void {
    _ = self;
    _ = gpa;
    _ = t;
    _ = exit_code;
    _ = runtime_ms;
}

/// Milliseconds since the surface was created.
pub fn runtimeMs(self: *const Remote) u64 {
    const now = std.time.Instant.now() catch return 0;
    return now.since(self.created) / std.time.ns_per_ms;
}

/// Nothing lives on the termio thread for a remote surface.
pub const ThreadData = struct {
    pub fn deinit(self: *ThreadData, alloc: Allocator) void {
        _ = self;
        _ = alloc;
    }
};
```

Then the tests from Step 1 below it.

- [ ] **Step 4: Wire it into `src/termio/backend.zig`**

Change `Kind`, `Config`, `Backend` and `ThreadData` so each switch has a `remote` arm. The full edits:

```zig
/// The kinds of backends.
/// Lostty Mobile: `remote` drives the terminal from app-supplied bytes.
pub const Kind = enum { exec, remote };

/// Configuration for the various backend types.
pub const Config = union(Kind) {
    /// Exec uses posix exec to run a command with a pty.
    exec: termio.Exec.Config,
    remote: termio.Remote.Config,
};
```

In `Backend`, add the field `remote: termio.Remote,` after `exec: termio.Exec,`, and in every method add the arm alongside `.exec`:

```zig
            .remote => |*remote| remote.deinit(),                                   // deinit
            .remote => |*remote| remote.initTerminal(t),                            // initTerminal
            .remote => |*remote| try remote.threadEnter(alloc, io, td),             // threadEnter
            .remote => |*remote| remote.threadExit(td),                             // threadExit
            .remote => |*remote| try remote.focusGained(td, focused),               // focusGained
            .remote => |*remote| try remote.resize(grid_size, screen_size),         // resize
            .remote => |*remote| try remote.queueWrite(alloc, td, data, linefeed),  // queueWrite
            .remote => |*remote| try remote.childExitedAbnormally(                  // childExitedAbnormally
                gpa,
                t,
                exit_code,
                runtime_ms,
            ),
```

In `ThreadData`, add the field `remote: termio.Remote.ThreadData,` and in `deinit` the arm `.remote => |*remote| remote.deinit(alloc),`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `zig build test -Dtest-filter="lostty remote"`
Expected: PASS (7 tests). Then confirm nothing else broke in the termio module: `zig build test -Dtest-filter="termio"` → PASS.

- [ ] **Step 6: Format and commit**

```bash
zig fmt src/termio/Remote.zig src/termio/backend.zig src/termio.zig
git add src/termio/Remote.zig src/termio/backend.zig src/termio.zig
git commit -m "lostty: remote termio backend (bytes in from the app, writes and size out through callbacks)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Surface wiring and the C API

**Files:**
- Modify: `src/apprt/embedded.zig` (Surface struct, `Surface.Options`, `Surface.init`, new exports after `ghostty_surface_text`)
- Modify: `src/Surface.zig:620-662` (backend selection), `src/Surface.zig:1299-1301` (abnormal-exit arm)
- Modify: `include/ghostty.h` (types after `ghostty_surface_context_e`; struct fields; function declarations after `ghostty_surface_text`)

**Interfaces:**
- Consumes: `termio.Remote.Config`, `termio.Remote.init`, `termio.Remote.disconnected_notice`, `Remote.runtimeMs()` (Task 1).
- Produces (C): `ghostty_surface_io_mode_e`, `ghostty_surface_io_write_cb`, `ghostty_surface_io_resize_cb`; `ghostty_surface_config_s` fields `io_mode`, `io_userdata`, `io_write`, `io_resize`; `void ghostty_surface_io_feed(ghostty_surface_t, const uint8_t*, size_t)`, `void ghostty_surface_io_disconnected(ghostty_surface_t)`, `void ghostty_surface_io_exited(ghostty_surface_t, uint32_t)`. Swift sees the callbacks as `@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int) -> Void` and `@convention(c) (UnsafeMutableRawPointer?, UInt16, UInt16, UInt32, UInt32) -> Void`.

- [ ] **Step 1: Write the failing test**

In `src/apprt/embedded.zig`, add near the other imports (after `const configpkg = …`):

```zig
const termio = @import("../termio.zig");
```

and, at the end of the file, this test:

```zig
fn testWrite(_: ?*anyopaque, _: [*]const u8, _: usize) callconv(.c) void {}
fn testResize(_: ?*anyopaque, _: u16, _: u16, _: u32, _: u32) callconv(.c) void {}

test "lostty remote: surface options ask for the remote backend only when complete" {
    const t = std.testing;
    // Default: a local process.
    try t.expect(remoteConfig(.{}) == null);
    // Remote mode with both callbacks.
    var ud: u8 = 0;
    const cfg = remoteConfig(.{
        .io_mode = 1,
        .io_userdata = &ud,
        .io_write = testWrite,
        .io_resize = testResize,
    }).?;
    try t.expect(cfg.userdata == @as(?*anyopaque, &ud));
    // Remote mode missing a callback falls back to local.
    try t.expect(remoteConfig(.{ .io_mode = 1, .io_write = testWrite }) == null);
    // An unknown mode is local.
    try t.expect(remoteConfig(.{ .io_mode = 7, .io_write = testWrite, .io_resize = testResize }) == null);
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `zig build test -Dtest-filter="lostty remote: surface options"`
Expected: FAIL to compile — `remoteConfig` undeclared, `io_mode` not a field.

- [ ] **Step 3: Add the options, the runtime hook and `remoteConfig`**

In `pub const Options = extern struct { … }`, after `context: apprt.surface.NewSurfaceContext = .window,` (it must stay last-but-these, matching the header order):

```zig
        /// Lostty Mobile: 0 runs a local process (the default); 1 makes this
        /// a remote surface (termio/Remote.zig) whose bytes come from
        /// `ghostty_surface_io_feed` and go out through these callbacks.
        io_mode: c_int = 0,
        io_userdata: ?*anyopaque = null,
        io_write: ?termio.Remote.WriteFn = null,
        io_resize: ?termio.Remote.ResizeFn = null,
```

In the `Surface` struct fields (after `title: ?[:0]const u8 = null,`):

```zig
    /// Lostty Mobile: set when the app created a remote surface; the core
    /// surface reads it through `termioRemote` to pick its backend.
    remote_io: ?termio.Remote.Config = null,
```

In `Surface.init`, inside `self.* = .{ … }` add `.remote_io = remoteConfig(opts),`.

After `defaultTermioEnv` add:

```zig
    /// Lostty Mobile: the remote IO the app asked for, or null for a local
    /// process. Read by the core surface when it starts its termio.
    pub fn termioRemote(self: *const Surface) ?termio.Remote.Config {
        return self.remote_io;
    }
```

And at file scope (before the C API exports block, near `pub const Surface = struct` is fine — put it right after the `Surface` struct ends):

```zig
/// Lostty Mobile: the remote backend's config from surface options, or null
/// for a local process (the default, an unknown mode, or a missing callback).
fn remoteConfig(opts: Surface.Options) ?termio.Remote.Config {
    if (opts.io_mode != 1) return null;
    return .{
        .userdata = opts.io_userdata,
        .write = opts.io_write orelse return null,
        .resize = opts.io_resize orelse return null,
    };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `zig build test -Dtest-filter="lostty remote"`
Expected: PASS (Task 1's 7 tests plus this one).

- [ ] **Step 5: Let the core surface pick the backend**

In `src/Surface.zig`, replace the block from `var env = rt_surface.defaultTermioEnv() catch |err| env: {` through `errdefer io_exec.deinit();` (inside the `// Start our IO implementation` braces) with:

```zig
        // Lostty Mobile: a surface whose program runs elsewhere gets the
        // remote backend (termio/Remote.zig) instead of a local process.
        const remote_io: ?termio.Remote.Config = if (comptime @hasDecl(
            apprt.runtime.Surface,
            "termioRemote",
        )) rt_surface.termioRemote() else null;

        var backend: termio.Backend = if (remote_io) |r| .{
            .remote = try termio.Remote.init(r),
        } else .{ .exec = exec: {
            var env = rt_surface.defaultTermioEnv() catch |err| env: {
                // If an error occurs, we don't want to block surface startup.
                log.warn("error getting env map for surface err={}", .{err});
                break :env internal_os.getEnvMap(alloc) catch
                    std.process.EnvMap.init(alloc);
            };
            errdefer env.deinit();

            // don't leak GHOSTTY_LOG to any subprocesses
            env.remove("GHOSTTY_LOG");

            // Initialize our IO backend
            break :exec try termio.Exec.init(alloc, .{
                .command = command,
                .env = env,
                .env_override = config.env,
                .shell_integration = config.@"shell-integration",
                .shell_integration_features = config.@"shell-integration-features",
                .cursor_blink = config.@"cursor-style-blink",
                .working_directory = if (config.@"working-directory") |wd| wd.value() else null,
                .resources_dir = global_state.resources_dir.host(),
                .term = config.term,
                .rt_pre_exec_info = .init(config),
                .rt_post_fork_info = .init(config),
            });
        } };
        errdefer backend.deinit();
```

(Keep the exec arguments exactly as they are in the file today — copy them from the removed block if they differ from the above.) Then in the `termio.Termio.init(&self.io, alloc, .{ … })` call change `.backend = .{ .exec = io_exec },` to `.backend = backend,`.

In `childExitedAbnormally` (around line 1299), add the arm:

```zig
    const command = try std.mem.join(alloc, " ", switch (self.io.backend) {
        .exec => |*exec| exec.subprocess.args,
        // Lostty Mobile: no local command to show.
        .remote => &[_][:0]const u8{"remote session"},
    });
```

- [ ] **Step 6: Add the three exports**

In `src/apprt/embedded.zig`, right after `export fn ghostty_surface_text(…) { … }`:

```zig
    /// Lostty Mobile: bytes received for a remote surface, processed as a
    /// local process's output would be. Safe from any thread. Ignored for
    /// local surfaces.
    export fn ghostty_surface_io_feed(
        surface: *Surface,
        ptr: [*]const u8,
        len: usize,
    ) void {
        if (surface.core_surface.io.backend != .remote) return;
        surface.core_surface.io.processOutput(ptr[0..len]);
    }

    /// Lostty Mobile: a remote surface lost its connection; shows a quiet
    /// "reconnecting…" line. Safe from any thread.
    export fn ghostty_surface_io_disconnected(surface: *Surface) void {
        if (surface.core_surface.io.backend != .remote) return;
        surface.core_surface.io.processOutput(termio.Remote.disconnected_notice);
    }

    /// Lostty Mobile: a remote surface's program ended (the tmux session
    /// is gone); handled as a local process exit, so the surface closes
    /// unless it waits after commands. Main thread only.
    export fn ghostty_surface_io_exited(surface: *Surface, exit_code: u32) void {
        const remote = switch (surface.core_surface.io.backend) {
            .remote => |*r| r,
            else => return,
        };
        surface.core_surface.handleMessage(.{ .child_exited = .{
            .exit_code = exit_code,
            .runtime_ms = remote.runtimeMs(),
        } }) catch |err| {
            log.warn("error handling remote exit err={}", .{err});
        };
    }
```

- [ ] **Step 7: Declare them in `include/ghostty.h`**

After the `ghostty_surface_context_e` typedef:

```c
// Lostty Mobile: a remote surface's program runs elsewhere (termio/Remote.zig).
typedef enum {
  GHOSTTY_SURFACE_IO_LOCAL = 0,
  GHOSTTY_SURFACE_IO_REMOTE = 1,
} ghostty_surface_io_mode_e;

typedef void (*ghostty_surface_io_write_cb)(void*, const uint8_t*, size_t);
typedef void (*ghostty_surface_io_resize_cb)(void*,
                                             uint16_t,
                                             uint16_t,
                                             uint32_t,
                                             uint32_t);
```

In `ghostty_surface_config_s`, after `ghostty_surface_context_e context;`:

```c
  // Lostty Mobile: remote IO (see ghostty_surface_io_mode_e).
  ghostty_surface_io_mode_e io_mode;
  void* io_userdata;
  ghostty_surface_io_write_cb io_write;
  ghostty_surface_io_resize_cb io_resize;
```

After `void ghostty_surface_text(ghostty_surface_t, const char*, uintptr_t);`:

```c
// Lostty Mobile: remote surfaces.
void ghostty_surface_io_feed(ghostty_surface_t, const uint8_t*, size_t);
void ghostty_surface_io_disconnected(ghostty_surface_t);
void ghostty_surface_io_exited(ghostty_surface_t, uint32_t);
```

- [ ] **Step 8: Verify the core and the app still build and behave**

Run:
```bash
zig fmt src/apprt/embedded.zig src/Surface.zig
zig build test -Dtest-filter="lostty" && echo ZIG-OK
zig build -Demit-macos-app=false && xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build 2>&1 | grep -E '\*\* BUILD|error:'
sh macos/lostty-tmux-smoke.sh | tail -1
```
Expected: `ZIG-OK`, `** BUILD SUCCEEDED **`, `PASS` (local panes unchanged; the smoke test runs the real launcher through the rebuilt app).

- [ ] **Step 9: Commit**

```bash
git add src/apprt/embedded.zig src/Surface.zig include/ghostty.h
git commit -m "lostty: surfaces can use the remote backend; C API to feed bytes and report disconnect or exit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `LosttyRemote` package and its pure logic

**Files:**
- Create: `macos/LosttyRemote/Package.swift`
- Create: `macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift`
- Create: `macos/LosttyRemote/Sources/LosttyRemote/KnownHosts.swift`
- Create: `macos/LosttyRemote/Sources/LosttyRemote/AttachEnd.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/TmuxRemoteTests.swift`, `KnownHostsTests.swift`, `AttachEndTests.swift`
- Modify: `.gitignore` (add `macos/LosttyRemote/.build/` and `macos/LosttyRemote/.swiftpm/`)

**Interfaces:**
- Produces:
  - `public struct RemoteSession: Equatable, Sendable { id, name: String; surface: String?; owner: Int32? }`
  - `public enum TmuxRemote { static let pathPrefix: String; static let listFormat: String; static var listCommand: String; static func attachCommand(sessionID: String, terminfoDir: String) throws -> String; static func parse(_ output: String) -> [RemoteSession]; static func shellQuote(_ s: String) -> String }`, `public enum TmuxRemoteError: Error, Equatable { case badSessionID(String) }`
  - `public final class KnownHosts { init(fileURL: URL); func verdict(host: String, port: Int, key: String) -> Verdict; func trust(host: String, port: Int, key: String) throws }`, `public enum Verdict: Equatable { case trusted, unknown, changed(pinned: String) }`
  - `public enum AttachEnd: Equatable, Sendable { case exited(Int32), lost }` with `static func from(finished: Bool, exitCode: Int?) -> AttachEnd`
  - `public struct ReconnectPolicy: Sendable { mutating func nextDelay() -> TimeInterval; mutating func reset() }`

- [ ] **Step 1: Create the package manifest and git-ignore its build output**

`macos/LosttyRemote/Package.swift`:

```swift
// swift-tools-version: 5.9
// LosttyRemote: SSH and tmux-over-SSH for Lostty Mobile, shared by the Mac
// debug window and the iPhone app. No GhosttyKit dependency.
import PackageDescription

let package = Package(
    name: "LosttyRemote",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LosttyRemote", targets: ["LosttyRemote"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel", exact: "0.12.1"),
    ],
    targets: [
        .target(
            name: "LosttyRemote",
            dependencies: [.product(name: "Citadel", package: "Citadel")]
        ),
        .testTarget(
            name: "LosttyRemoteTests",
            dependencies: ["LosttyRemote"]
        ),
    ]
)
```

Append to `.gitignore`:

```
# Lostty Mobile: LosttyRemote package build output
macos/LosttyRemote/.build/
macos/LosttyRemote/.swiftpm/
```

- [ ] **Step 2: Write the failing tests**

`macos/LosttyRemote/Tests/LosttyRemoteTests/TmuxRemoteTests.swift`:

```swift
import Testing
@testable import LosttyRemote

struct TmuxRemoteTests {
    @Test func listFindsTmuxOnAMinimalSSHPath() {
        #expect(TmuxRemote.listCommand.hasPrefix("PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -L lostty list-sessions -F "))
    }

    @Test func attachQuotesTheSessionIDAndNeverDetachesOthers() throws {
        let cmd = try TmuxRemote.attachCommand(sessionID: "$3", terminfoDir: "/Applications/Lostty.app/Contents/Resources/terminfo")
        #expect(cmd == "exec env LANG=\"${LANG:-en_US.UTF-8}\" TERMINFO='/Applications/Lostty.app/Contents/Resources/terminfo' "
            + "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -u -L lostty attach-session -t '$3'")
        #expect(!cmd.contains(" -d"))
    }

    @Test func attachRefusesAnythingButASessionID() {
        for bad in ["3", "$", "$3;kill-server", "main", "$3 -d", "'$3'"] {
            #expect(throws: TmuxRemoteError.badSessionID(bad)) {
                try TmuxRemote.attachCommand(sessionID: bad, terminfoDir: "/t")
            }
        }
    }

    @Test func attachQuotesATerminfoPathWithAQuote() throws {
        let cmd = try TmuxRemote.attachCommand(sessionID: "$1", terminfoDir: "/Users/o'brien/Lostty.app/Contents/Resources/terminfo")
        #expect(cmd.contains("TERMINFO='/Users/o'\\''brien/Lostty.app/Contents/Resources/terminfo'"))
    }

    @Test func parsesTheSessionList() {
        let out = "$1\tlostty\tABCD-1\t4242\n$2\tnotes\t\t\n$3\tmy proj\t\t\n"
        #expect(TmuxRemote.parse(out) == [
            RemoteSession(id: "$1", name: "lostty", surface: "ABCD-1", owner: 4242),
            RemoteSession(id: "$2", name: "notes", surface: nil, owner: nil),
            RemoteSession(id: "$3", name: "my proj", surface: nil, owner: nil),
        ])
    }

    @Test func emptyOrGarbageListIsNoSessions() {
        #expect(TmuxRemote.parse("").isEmpty)
        #expect(TmuxRemote.parse("no server running on /private/tmp/tmux-501/lostty\n").isEmpty)
        #expect(TmuxRemote.parse("1\tx\t\t\n").isEmpty)
    }
}
```

`macos/LosttyRemote/Tests/LosttyRemoteTests/KnownHostsTests.swift`:

```swift
import Foundation
import Testing
@testable import LosttyRemote

struct KnownHostsTests {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("lostty-known-hosts-\(UUID().uuidString)")

    @Test func firstKeyIsUnknownThenTrusted() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let hosts = KnownHosts(fileURL: file)
        #expect(hosts.verdict(host: "localhost", port: 22, key: "ecdsa-sha2-nistp256 AAAA1") == .unknown)
        try hosts.trust(host: "localhost", port: 22, key: "ecdsa-sha2-nistp256 AAAA1")
        #expect(hosts.verdict(host: "localhost", port: 22, key: "ecdsa-sha2-nistp256 AAAA1") == .trusted)
    }

    @Test func aDifferentKeyIsChangedAndThePinIsKept() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        try KnownHosts(fileURL: file).trust(host: "mac", port: 22, key: "ssh-ed25519 OLD")
        let reloaded = KnownHosts(fileURL: file)
        #expect(reloaded.verdict(host: "mac", port: 22, key: "ssh-ed25519 NEW") == .changed(pinned: "ssh-ed25519 OLD"))
        #expect(reloaded.verdict(host: "mac", port: 22, key: "ssh-ed25519 OLD") == .trusted)
    }

    @Test func pinsArePerHostAndPort() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let hosts = KnownHosts(fileURL: file)
        try hosts.trust(host: "mac", port: 22, key: "K1")
        #expect(hosts.verdict(host: "mac", port: 2222, key: "K1") == .unknown)
        #expect(hosts.verdict(host: "other", port: 22, key: "K1") == .unknown)
    }

    @Test func trustingAgainDoesNotOverwriteAPin() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let hosts = KnownHosts(fileURL: file)
        try hosts.trust(host: "mac", port: 22, key: "K1")
        try hosts.trust(host: "mac", port: 22, key: "K2")
        #expect(hosts.verdict(host: "mac", port: 22, key: "K1") == .trusted)
    }
}
```

`macos/LosttyRemote/Tests/LosttyRemoteTests/AttachEndTests.swift`:

```swift
import Testing
@testable import LosttyRemote

struct AttachEndTests {
    @Test func aChannelThatFinishesIsAnExit() {
        #expect(AttachEnd.from(finished: true, exitCode: nil) == .exited(0))
        #expect(AttachEnd.from(finished: true, exitCode: 1) == .exited(1))
    }

    @Test func aChannelThatBrokeIsLost() {
        #expect(AttachEnd.from(finished: false, exitCode: nil) == .lost)
    }

    @Test func backoffGrowsToACapAndResets() {
        var policy = ReconnectPolicy()
        let delays = (0..<8).map { _ in policy.nextDelay() }
        #expect(delays == [0.5, 1, 2, 4, 8, 15, 15, 15])
        policy.reset()
        #expect(policy.nextDelay() == 0.5)
    }
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `cd macos/LosttyRemote && swift test 2>&1 | tail -5`
Expected: FAIL to compile — `TmuxRemote`, `KnownHosts`, `AttachEnd`, `ReconnectPolicy` not found. (The first run also resolves Citadel from GitHub; that is expected.)

- [ ] **Step 4: Write `TmuxRemote.swift`**

```swift
import Foundation

/// A session on the Mac's Lostty tmux (`tmux -L lostty`).
public struct RemoteSession: Equatable, Sendable {
    public var id: String
    public var name: String
    /// The Mac pane showing it, if any.
    public var surface: String?
    /// The Mac Lostty's pid, if a Mac window shows it.
    public var owner: Int32?

    public init(id: String, name: String, surface: String?, owner: Int32?) {
        self.id = id
        self.name = name
        self.surface = surface
        self.owner = owner
    }
}

public enum TmuxRemoteError: Error, Equatable {
    case badSessionID(String)
}

/// Shell commands run over SSH against the Mac's Lostty tmux, and parsing
/// their output. Sessions are always targeted by id ("$3"), never by name
/// (tmux prefix-matches names), and attach never passes -d (that would close
/// the Mac window, which ends the session).
public enum TmuxRemote {
    /// SSH commands get a minimal PATH; tmux is usually in Homebrew's.
    public static let pathPrefix = "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH"

    /// id, name, Mac pane, Mac Lostty pid — tab separated.
    public static let listFormat = "#{session_id}\t#{session_name}\t#{@lostty_surface}\t#{@lostty_owner}"

    public static var listCommand: String {
        "\(pathPrefix) tmux -L lostty list-sessions -F \(shellQuote(listFormat))"
    }

    /// The command the PTY's shell replaces itself with. `-u` and LANG keep
    /// tmux in UTF-8 when the SSH session has no locale; TERMINFO lets tmux
    /// find xterm-ghostty.
    public static func attachCommand(sessionID: String, terminfoDir: String) throws -> String {
        guard isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        return "exec env LANG=\"${LANG:-en_US.UTF-8}\" TERMINFO=\(shellQuote(terminfoDir)) "
            + "\(pathPrefix) tmux -u -L lostty attach-session -t \(shellQuote(sessionID))"
    }

    public static func parse(_ output: String) -> [RemoteSession] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, isSessionID(fields[0]) else { return nil }
            return RemoteSession(
                id: fields[0],
                name: fields[1],
                surface: fields[2].isEmpty ? nil : fields[2],
                owner: Int32(fields[3]))
        }
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isSessionID(_ s: String) -> Bool {
        s.count >= 2 && s.first == "$" && s.dropFirst().allSatisfy(\.isASCII) && s.dropFirst().allSatisfy(\.isNumber)
    }
}
```

- [ ] **Step 5: Write `KnownHosts.swift`**

```swift
import Foundation

/// Host keys pinned on first connect ("trust on first use"). One line per
/// host: "<host>:<port> <key in OpenSSH form>". A key that differs from the
/// pin is reported, never re-pinned: the user removes the line by hand if
/// the Mac's key really changed.
public final class KnownHosts: @unchecked Sendable {
    public enum Verdict: Equatable {
        case trusted
        case unknown
        case changed(pinned: String)
    }

    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func verdict(host: String, port: Int, key: String) -> Verdict {
        lock.lock()
        defer { lock.unlock() }
        guard let pinned = load()[Self.label(host, port)] else { return .unknown }
        return pinned == key ? .trusted : .changed(pinned: pinned)
    }

    /// Pins `key` for the host unless a key is already pinned.
    public func trust(host: String, port: Int, key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var pins = load()
        let label = Self.label(host, port)
        guard pins[label] == nil else { return }
        pins[label] = key
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = pins.keys.sorted().map { "\($0) \(pins[$0]!)" }.joined(separator: "\n") + "\n"
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func label(_ host: String, _ port: Int) -> String { "\(host):\(port)" }

    private func load() -> [String: String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [:] }
        var pins: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let space = line.firstIndex(of: " ") else { continue }
            pins[String(line[..<space])] = String(line[line.index(after: space)...])
        }
        return pins
    }
}
```

The tests refer to `KnownHosts.Verdict` as `.unknown` etc. through type inference; they compile against the nested enum above.

- [ ] **Step 6: Write `AttachEnd.swift`**

```swift
import Foundation

/// How an attached tmux client ended.
public enum AttachEnd: Equatable, Sendable {
    /// The channel finished: tmux exited (the session ended, or someone
    /// detached this client). The window should close.
    case exited(Int32)
    /// The connection broke. Show "reconnecting…" and attach again.
    case lost

    /// `finished`: the channel closed normally, with `exitCode` if the
    /// remote reported one.
    public static func from(finished: Bool, exitCode: Int?) -> AttachEnd {
        finished ? .exited(Int32(exitCode ?? 0)) : .lost
    }
}

/// Delays between reconnect attempts: quick at first, then every 15 s.
public struct ReconnectPolicy: Sendable {
    private static let delays: [TimeInterval] = [0.5, 1, 2, 4, 8, 15]
    private var attempt = 0

    public init() {}

    public mutating func nextDelay() -> TimeInterval {
        let delay = Self.delays[min(attempt, Self.delays.count - 1)]
        attempt += 1
        return delay
    }

    public mutating func reset() {
        attempt = 0
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd macos/LosttyRemote && swift test 2>&1 | tail -5`
Expected: all `TmuxRemoteTests`, `KnownHostsTests`, `AttachEndTests` pass.

- [ ] **Step 8: Commit**

```bash
git add .gitignore macos/LosttyRemote/Package.swift macos/LosttyRemote/Package.resolved \
  macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift macos/LosttyRemote/Sources/LosttyRemote/KnownHosts.swift \
  macos/LosttyRemote/Sources/LosttyRemote/AttachEnd.swift macos/LosttyRemote/Tests/LosttyRemoteTests
git commit -m "lostty: LosttyRemote package: tmux-over-SSH commands, session list, host-key pins, reconnect policy

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(If `swift test` did not produce `Package.resolved`, drop it from `git add`.)

---

### Task 4: SSH with Citadel — key, pinning, sessions, attach

**Files:**
- Create: `macos/LosttyRemote/Sources/LosttyRemote/RemoteKey.swift`
- Create: `macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/RemoteKeyTests.swift`

**Interfaces:**
- Consumes: `TmuxRemote`, `KnownHosts`, `AttachEnd` (Task 3).
- Produces:
  - `public struct RemoteKey: @unchecked Sendable { public let publicKeyLine: String; public static func secureEnclave(storedAt: URL) throws -> RemoteKey; public init(software: P256.Signing.PrivateKey) }`
  - `public enum RemoteError: Error, Equatable { case secureEnclaveUnavailable, hostKeyChanged(host: String, pinned: String, offered: String), keyRejected }` with `public var message: String`
  - `public struct RemoteHost: Sendable, Equatable { host: String; port: Int; user: String; terminfoDir: String }` with `public static func localhost(terminfoDir: String) -> RemoteHost`
  - `public protocol RemoteTerminal: AnyObject, Sendable { func write(_ data: Data); func resize(cols: Int, rows: Int); func close() }`
  - `@available(macOS 15, *) public final class RemoteConnection: @unchecked Sendable { static func connect(to: RemoteHost, key: RemoteKey, knownHosts: KnownHosts) async throws -> RemoteConnection; func sessions() async throws -> [RemoteSession]; func attach(sessionID: String, cols: Int, rows: Int, onOpen: @escaping @Sendable (RemoteTerminal) -> Void, onOutput: @escaping @Sendable (Data) -> Void) async -> AttachEnd; func close() async }`

Citadel 0.12.1 API this task uses (verify the exact spelling in the resolved checkout at `macos/LosttyRemote/.build/checkouts/Citadel/Sources/Citadel/` before writing; if a name differs, use Citadel's and keep the shapes below):
- `SSHClient.connect(host:port:authenticationMethod:hostKeyValidator:reconnect:)` → `SSHClient`; `client.close()`.
- `SSHAuthenticationMethod.custom(_ delegate: NIOSSHClientUserAuthenticationDelegate)`.
- `SSHHostKeyValidator.custom(_ delegate: NIOSSHClientServerAuthenticationDelegate)`.
- `client.executeCommand(_:) async throws -> ByteBuffer`, throwing `SSHClient.CommandFailed` (has `exitCode`) on a non-zero exit.
- `@available(macOS 15) client.withPTY(_ request: SSHChannelRequestEvent.PseudoTerminalRequest, environment: [SSHChannelRequestEvent.EnvironmentRequest], perform: (TTYOutput, TTYStdinWriter) async throws -> Void) async throws`; inbound yields `.stdout(ByteBuffer)` / `.stderr(ByteBuffer)`; `outbound.write(ByteBuffer)`; `outbound.changeSize(cols:rows:pixelWidth:pixelHeight:)`. A non-zero exit throws `CommandFailed`; a clean exit ends the inbound sequence.

- [ ] **Step 1: Write the failing tests**

`macos/LosttyRemote/Tests/LosttyRemoteTests/RemoteKeyTests.swift`:

```swift
import Crypto
import Foundation
import NIOCore
import NIOEmbedded
import NIOSSH
import Testing
@testable import LosttyRemote

struct RemoteKeyTests {
    @Test func publicKeyLineIsAnAuthorizedKeysLine() {
        let key = RemoteKey(software: P256.Signing.PrivateKey())
        let parts = key.publicKeyLine.split(separator: " ")
        #expect(parts.count == 3)
        #expect(parts[0] == "ecdsa-sha2-nistp256")
        #expect(parts[2] == "lostty-mobile")
        #expect((try? NIOSSHPublicKey(openSSHPublicKey: "\(parts[0]) \(parts[1])")) != nil)
    }
}

struct PinnedHostKeysTests {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("lostty-pins-\(UUID().uuidString)")

    func validate(_ pins: PinnedHostKeys, _ key: NIOSSHPublicKey) -> Result<Void, Error> {
        let loop = EmbeddedEventLoop()
        let promise = loop.makePromise(of: Void.self)
        pins.validateHostKey(hostKey: key, validationCompletePromise: promise)
        var result: Result<Void, Error>?
        promise.futureResult.whenComplete { result = $0 }
        loop.run()
        return result!
    }

    @Test func firstConnectPinsThenAcceptsTheSameKey() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let pins = PinnedHostKeys(host: "localhost", port: 22, knownHosts: KnownHosts(fileURL: file))
        let key = NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey()).publicKey
        #expect((try? validate(pins, key).get()) != nil)
        #expect((try? validate(pins, key).get()) != nil)
    }

    @Test func aChangedKeyIsAHardStop() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let pins = PinnedHostKeys(host: "localhost", port: 22, knownHosts: KnownHosts(fileURL: file))
        _ = validate(pins, NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey()).publicKey)
        let result = validate(pins, NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey()).publicKey)
        guard case .failure(let error) = result, case .hostKeyChanged? = error as? RemoteError else {
            Issue.record("expected hostKeyChanged, got \(result)")
            return
        }
    }
}
```

Add the test target's extra dependencies in `Package.swift` (the products come in through Citadel's graph):

```swift
        .testTarget(
            name: "LosttyRemoteTests",
            dependencies: [
                "LosttyRemote",
                .product(name: "Citadel", package: "Citadel"),
            ]
        ),
```

The library sources import `NIOCore`, `NIOSSH`, `NIOFoundationCompat` (for `Data(buffer:)` and `ByteBuffer(data:)`) and `Crypto`; add `import NIOFoundationCompat` to `RemoteConnection.swift`. If any of `NIOCore`, `NIOSSH`, `NIOFoundationCompat`, `NIOEmbedded` or `Crypto` does not resolve through Citadel (in the library or the test target), add the packages Citadel itself depends on at the exact versions in `macos/LosttyRemote/Package.resolved` (`swift-nio`, the Wellz26 `swift-nio-ssh` fork, `swift-crypto`) as dependencies and use their products — never apple/swift-nio-ssh.

- [ ] **Step 2: Run them to verify they fail**

Run: `cd macos/LosttyRemote && swift test 2>&1 | tail -5`
Expected: FAIL to compile — `RemoteKey`, `PinnedHostKeys`, `RemoteError` not found.

- [ ] **Step 3: Write `RemoteKey.swift`**

```swift
import Citadel
import Crypto
import CryptoKit
import Foundation
import NIOCore
import NIOSSH

public enum RemoteError: Error, Equatable {
    case secureEnclaveUnavailable
    case hostKeyChanged(host: String, pinned: String, offered: String)
    case keyRejected

    public var message: String {
        switch self {
        case .secureEnclaveUnavailable:
            "This Mac has no Secure Enclave to keep the Lostty Mobile key in."
        case .hostKeyChanged(let host, let pinned, _):
            "The SSH host key for \(host) changed since it was first trusted (pinned \(pinned.prefix(40))…). "
                + "Lostty will not connect. If the Mac's key really changed, remove its line from known_hosts in "
                + "Application Support/Lostty."
        case .keyRejected:
            "The Mac refused Lostty's key. Add the line from \"Copy Remote Key\" to ~/.ssh/authorized_keys."
        }
    }
}

/// The SSH key: an ECDSA P-256 key in the Secure Enclave (which does not do
/// ed25519), used behind user presence. Only the Secure Enclave's wrapped
/// handle is stored on disk; it is useless on any other device.
public struct RemoteKey: @unchecked Sendable {
    let privateKey: NIOSSHPrivateKey

    /// "ecdsa-sha2-nistp256 AAAA… lostty-mobile", for authorized_keys.
    public let publicKeyLine: String

    public init(software key: P256.Signing.PrivateKey) {
        self.init(NIOSSHPrivateKey(p256Key: key))
    }

    init(_ key: NIOSSHPrivateKey) {
        privateKey = key
        publicKeyLine = String(openSSHPublicKey: key.publicKey) + " lostty-mobile"
    }

    /// Loads the key whose handle is at `url`, creating it on first use.
    public static func secureEnclave(storedAt url: URL) throws -> RemoteKey {
        guard SecureEnclave.isAvailable else { throw RemoteError.secureEnclaveUnavailable }
        if let data = try? Data(contentsOf: url) {
            return RemoteKey(NIOSSHPrivateKey(secureEnclaveP256Key:
                try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)))
        }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error)
        else { throw error!.takeRetainedValue() as Error }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try key.dataRepresentation.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return RemoteKey(NIOSSHPrivateKey(secureEnclaveP256Key: key))
    }
}

/// Offers the key once; a second request means the server refused it.
final class KeyAuth: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let user: String
    private let key: NIOSSHPrivateKey
    private var offered = false

    init(user: String, key: RemoteKey) {
        self.user = user
        self.key = key.privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !offered, availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(RemoteError.keyRejected)
            return
        }
        offered = true
        nextChallengePromise.succeed(.init(
            username: user, serviceName: "", offer: .privateKey(.init(privateKey: key))))
    }
}

/// Pins the host key on first connect; a different key later is a hard stop.
final class PinnedHostKeys: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let knownHosts: KnownHosts

    init(host: String, port: Int, knownHosts: KnownHosts) {
        self.host = host
        self.port = port
        self.knownHosts = knownHosts
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let offered = String(openSSHPublicKey: hostKey)
        switch knownHosts.verdict(host: host, port: port, key: offered) {
        case .trusted:
            validationCompletePromise.succeed(())
        case .unknown:
            do {
                try knownHosts.trust(host: host, port: port, key: offered)
                validationCompletePromise.succeed(())
            } catch {
                validationCompletePromise.fail(error)
            }
        case .changed(let pinned):
            validationCompletePromise.fail(RemoteError.hostKeyChanged(host: host, pinned: pinned, offered: offered))
        }
    }
}
```

- [ ] **Step 4: Write `RemoteConnection.swift`**

```swift
import Citadel
import Foundation
import NIOCore
import NIOSSH

/// Where the Mac is and how to reach its Lostty tmux.
public struct RemoteHost: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var user: String
    /// Lostty.app's Contents/Resources/terminfo on the Mac (xterm-ghostty).
    public var terminfoDir: String

    public init(host: String, port: Int = 22, user: String, terminfoDir: String) {
        self.host = host
        self.port = port
        self.user = user
        self.terminfoDir = terminfoDir
    }

    /// This Mac, as the current user (the Mac debug window).
    public static func localhost(terminfoDir: String) -> RemoteHost {
        RemoteHost(host: "localhost", user: NSUserName(), terminfoDir: terminfoDir)
    }
}

/// An attached tmux client's input side.
public protocol RemoteTerminal: AnyObject, Sendable {
    func write(_ data: Data)
    func resize(cols: Int, rows: Int)
    func close()
}

@available(macOS 15, *)
public final class RemoteConnection: @unchecked Sendable {
    private let client: SSHClient
    private let host: RemoteHost

    private init(client: SSHClient, host: RemoteHost) {
        self.client = client
        self.host = host
    }

    public static func connect(to host: RemoteHost, key: RemoteKey, knownHosts: KnownHosts) async throws -> RemoteConnection {
        let client = try await SSHClient.connect(
            host: host.host,
            port: host.port,
            authenticationMethod: .custom(KeyAuth(user: host.user, key: key)),
            hostKeyValidator: .custom(PinnedHostKeys(host: host.host, port: host.port, knownHosts: knownHosts)),
            reconnect: .never)
        return RemoteConnection(client: client, host: host)
    }

    /// The Mac's Lostty tmux sessions; none when no tmux server is running.
    public func sessions() async throws -> [RemoteSession] {
        do {
            let out = try await client.executeCommand(TmuxRemote.listCommand)
            return TmuxRemote.parse(String(buffer: out))
        } catch is SSHClient.CommandFailed {
            return []
        }
    }

    /// Attaches to session `sessionID` on a PTY and runs until the client
    /// ends. `onOpen` hands over the input side once the PTY is up;
    /// `onOutput` gets every received byte, on Citadel's event loop.
    public func attach(
        sessionID: String,
        cols: Int,
        rows: Int,
        onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async -> AttachEnd {
        let command: String
        do {
            command = try TmuxRemote.attachCommand(sessionID: sessionID, terminfoDir: host.terminfoDir)
        } catch {
            return .exited(1)
        }
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-ghostty",
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([:]))
        do {
            try await client.withPTY(request, environment: []) { inbound, outbound in
                let (inputs, input) = AsyncStream.makeStream(of: PTYInput.self)
                let terminal = PTYTerminal(input: input)
                input.yield(.data(Data((command + "\n").utf8)))
                onOpen(terminal)
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await output in inbound {
                            switch output {
                            case .stdout(let buffer), .stderr(let buffer):
                                onOutput(Data(buffer: buffer))
                            }
                        }
                    }
                    group.addTask {
                        for await item in inputs {
                            switch item {
                            case .data(let data):
                                try await outbound.write(ByteBuffer(data: data))
                            case .resize(let cols, let rows):
                                try await outbound.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
                            case .close:
                                return
                            }
                        }
                    }
                    // Whichever side ends first (the remote exiting, or a
                    // local close) ends the channel.
                    try await group.next()
                    group.cancelAll()
                    input.finish()
                }
            }
            return .from(finished: true, exitCode: nil)
        } catch let failed as SSHClient.CommandFailed {
            return .from(finished: true, exitCode: failed.exitCode)
        } catch {
            return .from(finished: false, exitCode: nil)
        }
    }

    public func close() async {
        try? await client.close()
    }
}

enum PTYInput: Sendable {
    case data(Data)
    case resize(cols: Int, rows: Int)
    case close
}

/// Hands writes, resizes and close to the PTY task; never blocks the caller.
final class PTYTerminal: RemoteTerminal, @unchecked Sendable {
    private let input: AsyncStream<PTYInput>.Continuation

    init(input: AsyncStream<PTYInput>.Continuation) {
        self.input = input
    }

    func write(_ data: Data) { input.yield(.data(data)) }
    func resize(cols: Int, rows: Int) { input.yield(.resize(cols: cols, rows: rows)) }
    func close() { input.yield(.close) }
}
```

Note on `close()`: when the local side closes (`.close`), the input task returns, `group.next()` completes, the `perform` closure returns, Citadel closes the channel, and `attach` returns `.exited(0)` — the caller (who asked to close) ignores it.

- [ ] **Step 5: Run the tests and build**

Run: `cd macos/LosttyRemote && swift build 2>&1 | grep -E 'error|warning: unre|Compiling|Build complete' | tail -5 && swift test 2>&1 | tail -5`
Expected: `Build complete!`, all tests pass (Task 3's plus `RemoteKeyTests`, `PinnedHostKeysTests`).

If Citadel names differ from the ones listed in this task's Interfaces, fix them to Citadel's actual API (read the checkout) without changing `RemoteConnection`'s public shape, and say so in the report.

- [ ] **Step 6: Commit**

```bash
git add macos/LosttyRemote/Package.swift macos/LosttyRemote/Package.resolved \
  macos/LosttyRemote/Sources/LosttyRemote/RemoteKey.swift macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift \
  macos/LosttyRemote/Tests/LosttyRemoteTests/RemoteKeyTests.swift
git commit -m "lostty: LosttyRemote SSH: Secure Enclave key, pinned host keys, session list and PTY attach over Citadel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Remote surfaces in the Mac app

**Files:**
- Modify: `macos/Ghostty.xcodeproj/project.pbxproj` (link the package; deployment target 14.0 for the Ghostty app's Debug, Release and ReleaseLocal)
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView.swift` (`RemoteIO` protocol, `SurfaceConfiguration.remoteIO`, C fields in `withCValue`)
- Modify: `macos/Sources/Ghostty/Ghostty.Surface.swift` (`keepAlive`)
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (skip the launcher; attach/detach; `needsConfirmQuit`)
- Create: `macos/Sources/Features/Remote/RemoteSurfaceIO.swift`
- Test: `macos/Tests/Remote/RemoteSurfaceIOTests.swift`

**Interfaces:**
- Consumes: the C API (Task 2); `LosttyRemote` (Tasks 3–4).
- Produces:
  - `Ghostty.RemoteIO` (protocol, `AnyObject`): `write(_ bytes: UnsafeRawBufferPointer)`, `resize(cols: UInt16, rows: UInt16, widthPx: UInt32, heightPx: UInt32)`, `attach(to surface: ghostty_surface_t)`, `detach()`.
  - `Ghostty.SurfaceConfiguration.remoteIO: Ghostty.RemoteIO?`
  - `Ghostty.Surface.keepAlive: AnyObject?`
  - `protocol RemoteAttacher: Sendable { func attach(cols: Int, rows: Int, onOpen: @escaping @Sendable (RemoteTerminal) -> Void, onOutput: @escaping @Sendable (Data) -> Void) async throws -> AttachEnd }`
  - `final class RemoteSurfaceIO: Ghostty.RemoteIO` with `init(attacher: RemoteAttacher, surfaceCalls: SurfaceCalls = .live, delays: @escaping @Sendable (TimeInterval) async throws -> Void = …)` and `func finished() async`, where `struct SurfaceCalls { feed, disconnected, exited }` are closures over `ghostty_surface_t`.
  - `@available(macOS 15, *) struct SSHAttacher: RemoteAttacher { host: RemoteHost; key: RemoteKey; knownHosts: KnownHosts; sessionID: String }`

- [ ] **Step 1: Link the package and raise the deployment target**

Edit `macos/Ghostty.xcodeproj/project.pbxproj` with these exact additions (IDs below are new; first confirm with `grep -c 4C5A0001 macos/Ghostty.xcodeproj/project.pbxproj` that they print `0`):

1. In `/* Begin PBXBuildFile section */`, after the `Sparkle in Frameworks` line:
```
		4C5A00012F7A000000C0FFEE /* LosttyRemote in Frameworks */ = {isa = PBXBuildFile; productRef = 4C5A00022F7A000000C0FFEE /* LosttyRemote */; };
```
2. In the Ghostty target's Frameworks phase (`A5B3052E299BEAAA0047F10C /* Frameworks */`), after `A51BFC272B30F1B800E92F16 /* Sparkle in Frameworks */,`:
```
				4C5A00012F7A000000C0FFEE /* LosttyRemote in Frameworks */,
```
3. In the Ghostty target's `packageProductDependencies`, after `A51BFC262B30F1B800E92F16 /* Sparkle */,`:
```
				4C5A00022F7A000000C0FFEE /* LosttyRemote */,
```
4. In the project's `packageReferences`, after the Sparkle reference:
```
				4C5A00032F7A000000C0FFEE /* XCLocalSwiftPackageReference "LosttyRemote" */,
```
5. Before `/* Begin XCRemoteSwiftPackageReference section */`:
```
/* Begin XCLocalSwiftPackageReference section */
		4C5A00032F7A000000C0FFEE /* XCLocalSwiftPackageReference "LosttyRemote" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = LosttyRemote;
		};
/* End XCLocalSwiftPackageReference section */

```
6. In `/* Begin XCSwiftPackageProductDependency section */`, after the Sparkle entry:
```
		4C5A00022F7A000000C0FFEE /* LosttyRemote */ = {
			isa = XCSwiftPackageProductDependency;
			package = 4C5A00032F7A000000C0FFEE /* XCLocalSwiftPackageReference "LosttyRemote" */;
			productName = LosttyRemote;
		};
```
7. Deployment target 13.0 → 14.0 for the Ghostty app's three build configurations only (IDs `A5B30541299BEAAB0047F10C` Debug, `A5B30542299BEAAB0047F10C` Release, `3B39CAA32B33946300DABEB8` ReleaseLocal):
```bash
python3 - <<'EOF'
import re
p = 'macos/Ghostty.xcodeproj/project.pbxproj'
s = open(p).read()
for cid in ['A5B30541299BEAAB0047F10C', 'A5B30542299BEAAB0047F10C', '3B39CAA32B33946300DABEB8']:
    m = re.search(r'\t\t' + cid + r' /\* \w+ \*/ = \{.*?\n\t\t\};', s, re.S)
    block = m.group(0)
    assert 'MACOSX_DEPLOYMENT_TARGET = 13.0;' in block, cid
    s = s.replace(block, block.replace('MACOSX_DEPLOYMENT_TARGET = 13.0;', 'MACOSX_DEPLOYMENT_TARGET = 14.0;'))
open(p, 'w').write(s)
EOF
```

Verify: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build 2>&1 | grep -E '\*\* BUILD|error:'` → `** BUILD SUCCEEDED **` (the package resolves and links; nothing uses it yet).

- [ ] **Step 2: Write the failing tests**

`macos/Tests/Remote/RemoteSurfaceIOTests.swift`:

```swift
#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Ghostty

/// Records what the bridge does to the surface; never touches a real one.
private final class SurfaceLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _fed = Data()
    private var _events: [String] = []
    var fed: Data { lock.withLock { _fed } }
    var events: [String] { lock.withLock { _events } }
    func feed(_ d: Data) { lock.withLock { _fed.append(d) } }
    func event(_ e: String) { lock.withLock { _events.append(e) } }

    var calls: RemoteSurfaceIO.SurfaceCalls {
        .init(
            feed: { [self] _, data in feed(data) },
            disconnected: { [self] _ in event("disconnected") },
            exited: { [self] _, code in event("exited \(code)") })
    }
}

private final class FakeTerminal: RemoteTerminal, @unchecked Sendable {
    private let lock = NSLock()
    private var _written = Data()
    private var _sizes: [String] = []
    private var _closed = false
    var closed: Bool { lock.withLock { _closed } }
    var written: Data { lock.withLock { _written } }
    var sizes: [String] { lock.withLock { _sizes } }
    func write(_ data: Data) { lock.withLock { _written.append(data) } }
    func resize(cols: Int, rows: Int) { lock.withLock { _sizes.append("\(cols)x\(rows)") } }
    func close() { lock.withLock { _closed = true } }
}

/// Plays a script of attach results; each attach opens a FakeTerminal,
/// sends `output`, then ends with the next result.
private final class ScriptedAttacher: RemoteAttacher, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<AttachEnd, Error>]
    private var _terminals: [FakeTerminal] = []
    private var _sizes: [String] = []
    var terminals: [FakeTerminal] { lock.withLock { _terminals } }
    var sizes: [String] { lock.withLock { _sizes } }
    let output: Data

    init(_ results: [Result<AttachEnd, Error>], output: Data = Data("hi".utf8)) {
        self.results = results
        self.output = output
    }

    func attach(cols: Int, rows: Int,
                onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
                onOutput: @escaping @Sendable (Data) -> Void) async throws -> AttachEnd {
        let next: Result<AttachEnd, Error> = lock.withLock {
            _sizes.append("\(cols)x\(rows)")
            return results.isEmpty ? .success(.exited(0)) : results.removeFirst()
        }
        let terminal = FakeTerminal()
        lock.withLock { _terminals.append(terminal) }
        onOpen(terminal)
        onOutput(output)
        return try next.get()
    }
}

/// Opens a terminal and stays attached until cancelled (the pane closing).
private final class HoldingAttacher: RemoteAttacher, @unchecked Sendable {
    private let lock = NSLock()
    private var _terminal: FakeTerminal?
    var terminal: FakeTerminal? { lock.withLock { _terminal } }

    func attach(cols: Int, rows: Int,
                onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
                onOutput: @escaping @Sendable (Data) -> Void) async throws -> AttachEnd {
        let terminal = FakeTerminal()
        lock.withLock { _terminal = terminal }
        onOpen(terminal)
        try await Task.sleep(for: .seconds(60))
        return .exited(0)
    }
}

private let fakeSurface = OpaquePointer(bitPattern: 0x1)!

struct RemoteSurfaceIOTests {
    @Test func attachesAtTheSizeTheCoreReportedAndFeedsOutput() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.resize(cols: 100, rows: 30, widthPx: 1000, heightPx: 600)
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes == ["100x30"])
        #expect(log.fed == Data("hi".utf8))
        #expect(log.events == ["exited 0"])
    }

    @Test func aLostConnectionShowsReconnectingAndAttachesAgain() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.lost), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.resize(cols: 80, rows: 24, widthPx: 0, heightPx: 0)
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes == ["80x24", "80x24"])
        #expect(log.events == ["disconnected", "exited 0"])
    }

    @Test func aFailedConnectRetriesUntilItAttaches() async {
        struct Down: Error {}
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.failure(Down()), .failure(Down()), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes.count == 3)
        #expect(log.events.last == "exited 0")
    }

    @Test func aHostKeyChangeStopsWithAMessageInsteadOfRetrying() async {
        let log = SurfaceLog()
        let changed = RemoteError.hostKeyChanged(host: "localhost", pinned: "A", offered: "B")
        let attacher = ScriptedAttacher([.failure(changed), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(attacher.sizes.count == 1)
        #expect(String(decoding: log.fed, as: UTF8.self).contains("host key"))
        #expect(log.events == ["exited 1"])
    }

    @Test func typingGoesToTheOpenTerminalAndResizesFollow() async throws {
        let log = SurfaceLog()
        let attacher = HoldingAttacher()
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.attach(to: fakeSurface)
        var terminal: FakeTerminal?
        for _ in 0..<50 where terminal == nil {
            try await Task.sleep(for: .milliseconds(20))
            terminal = attacher.terminal
        }
        let open = try #require(terminal)
        Data("ls\r".utf8).withUnsafeBytes { io.write($0) }
        io.resize(cols: 90, rows: 20, widthPx: 0, heightPx: 0)
        io.detach()
        await io.finished()
        #expect(open.written == Data("ls\r".utf8))
        #expect(open.sizes == ["90x20"])
        #expect(open.closed)
        #expect(log.events.isEmpty, "closing the pane is not an exit or a disconnect")
    }

    @Test func afterDetachNothingReachesTheSurface() async {
        let log = SurfaceLog()
        let attacher = ScriptedAttacher([.success(.lost), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: log.calls, delays: { _ in })
        io.detach()
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(log.fed.isEmpty)
        #expect(log.events.isEmpty)
    }
}
#endif
```

If the test target cannot `import LosttyRemote`, also add `4C5A00022F7A000000C0FFEE /* LosttyRemote */` to the GhosttyTests target's `packageProductDependencies` (a second `XCSwiftPackageProductDependency` with a new ID is needed if Xcode rejects sharing one; use `4C5A00042F7A000000C0FFEE`).

- [ ] **Step 3: Run them to verify they fail**

Run: `macos/skins-test.sh RemoteSurfaceIOTests`
Expected: FAIL to compile — `RemoteSurfaceIO`, `RemoteAttacher` not found.

- [ ] **Step 4: Add `RemoteIO` and the C plumbing to `SurfaceView.swift`**

Inside `extension Ghostty` in `macos/Sources/Ghostty/Surface View/SurfaceView.swift`, just before `struct SurfaceConfiguration {`:

```swift
    /// Lostty Mobile: a surface whose program runs elsewhere (the core's
    /// remote backend, termio/Remote.zig). The core calls `write` on its IO
    /// thread and `resize` during surface creation and on its IO thread;
    /// both copy what they need and return at once.
    protocol RemoteIO: AnyObject {
        func write(_ bytes: UnsafeRawBufferPointer)
        func resize(cols: UInt16, rows: UInt16, widthPx: UInt32, heightPx: UInt32)
        /// The surface exists: start delivering bytes to it.
        func attach(to surface: ghostty_surface_t)
        /// The view is going away: stop calling into the surface.
        func detach()
    }
```

In `struct SurfaceConfiguration`, after `var context: …`:

```swift
        /// Lostty Mobile: set for a remote surface (see `RemoteIO`).
        var remoteIO: RemoteIO?
```

In `withCValue`, after `config.context = context`:

```swift
            // Lostty Mobile: a remote surface's bytes come from `remoteIO`.
            if let remoteIO {
                config.io_mode = GHOSTTY_SURFACE_IO_REMOTE
                config.io_userdata = Unmanaged.passUnretained(remoteIO as AnyObject).toOpaque()
                config.io_write = { userdata, bytes, len in
                    guard let userdata, let bytes,
                          let io = Unmanaged<AnyObject>.fromOpaque(userdata).takeUnretainedValue() as? RemoteIO
                    else { return }
                    io.write(UnsafeRawBufferPointer(start: bytes, count: len))
                }
                config.io_resize = { userdata, cols, rows, width, height in
                    guard let userdata,
                          let io = Unmanaged<AnyObject>.fromOpaque(userdata).takeUnretainedValue() as? RemoteIO
                    else { return }
                    io.resize(cols: cols, rows: rows, widthPx: width, heightPx: height)
                }
            }
```

- [ ] **Step 5: Keep the remote IO alive until the surface is freed**

In `macos/Sources/Ghostty/Ghostty.Surface.swift`, add a property to the class and extend the deinit's task:

```swift
        /// Lostty Mobile: an object the C surface's callbacks point at
        /// (a remote surface's IO). The surface is freed later on the main
        /// actor, and its IO thread may call back until then.
        var keepAlive: AnyObject?
```

and in `deinit`:

```swift
            let surface = self.surface
            let keepAlive = self.keepAlive
            Task.detached { @MainActor in
                ghostty_surface_free(surface)
                withExtendedLifetime(keepAlive) {}
            }
```

- [ ] **Step 6: Remote panes in `SurfaceView_AppKit.swift`**

1. Add a stored property next to `let inTmuxSession: Bool`:
```swift
        /// Lostty Mobile: the remote IO of a remote pane (see Ghostty.RemoteIO).
        private let remoteIO: Ghostty.RemoteIO?
```
2. In `init`, replace the `tmuxLaunch` computation so remote panes never get the launcher:
```swift
            self.remoteIO = baseConfig?.remoteIO
            let tmuxLaunch = baseConfig?.remoteIO != nil ? nil : SessionLaunch.command(
                existing: baseConfig?.command,
                binary: Bundle.main.executableURL?.path,
                disabled: UserDefaults.ghostty.bool(forKey: TmuxConstants.disabledDefaultsKey))
            self.inTmuxSession = SessionLaunch.isLauncher(tmuxLaunch ?? baseConfig?.command)
```
3. After `self.surfaceModel = Ghostty.Surface(cSurface: surface)`:
```swift
            // Lostty Mobile: a remote pane starts its session now that the
            // surface exists, and its IO lives until the surface is freed.
            if let remoteIO {
                surfaceModel?.keepAlive = remoteIO
                remoteIO.attach(to: surface)
            }
```
4. In `deinit`, before `// Lostty Mobile: closing a pane ends its tmux session`:
```swift
            // Lostty Mobile: a remote pane closes its channel; the session
            // keeps running on the Mac.
            remoteIO?.detach()
```
5. In `needsConfirmQuit`, first line after `guard let surface = self.surface else { return false }`:
```swift
            // Lostty Mobile: closing a remote pane only closes the viewer.
            if remoteIO != nil { return false }
```

- [ ] **Step 7: Write `RemoteSurfaceIO.swift`**

`macos/Sources/Features/Remote/RemoteSurfaceIO.swift`:

```swift
#if os(macOS)
import Foundation
import GhosttyKit
import LosttyRemote

/// Attaches to one remote session; implemented over SSH by
/// `SSHAttacher` and by fakes in tests.
protocol RemoteAttacher: Sendable {
    func attach(
        cols: Int,
        rows: Int,
        onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws -> AttachEnd
}

/// Joins a remote surface to a remote tmux session: the core's writes and
/// resizes go to the session, received bytes go to the core, and a dropped
/// connection shows "reconnecting…" and attaches again with backoff. The
/// session ending closes the pane. Closing the pane closes only the channel.
final class RemoteSurfaceIO: Ghostty.RemoteIO, @unchecked Sendable {
    /// The surface calls this makes; tests replace them.
    struct SurfaceCalls: Sendable {
        var feed: @Sendable (ghostty_surface_t, Data) -> Void
        var disconnected: @Sendable (ghostty_surface_t) -> Void
        var exited: @Sendable (ghostty_surface_t, UInt32) -> Void

        static let live = SurfaceCalls(
            feed: { surface, data in
                data.withUnsafeBytes { raw in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                    ghostty_surface_io_feed(surface, base, raw.count)
                }
            },
            disconnected: { ghostty_surface_io_disconnected($0) },
            exited: { surface, code in
                DispatchQueue.main.async { ghostty_surface_io_exited(surface, code) }
            })
    }

    private let attacher: RemoteAttacher
    private let calls: SurfaceCalls
    private let delays: @Sendable (TimeInterval) async throws -> Void

    private let lock = NSLock()
    private var surface: ghostty_surface_t?
    private var terminal: RemoteTerminal?
    private var size = (cols: 80, rows: 24)
    private var detached = false
    private var task: Task<Void, Never>?

    init(
        attacher: RemoteAttacher,
        surfaceCalls: SurfaceCalls = .live,
        delays: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.attacher = attacher
        self.calls = surfaceCalls
        self.delays = delays
    }

    // MARK: Ghostty.RemoteIO

    func write(_ bytes: UnsafeRawBufferPointer) {
        let data = Data(bytes)
        // Typing while not attached (connecting, reconnecting) is dropped.
        lock.withLock { terminal }?.write(data)
    }

    func resize(cols: UInt16, rows: UInt16, widthPx: UInt32, heightPx: UInt32) {
        let open: RemoteTerminal? = lock.withLock {
            size = (Int(cols), Int(rows))
            return terminal
        }
        open?.resize(cols: Int(cols), rows: Int(rows))
    }

    func attach(to surface: ghostty_surface_t) {
        lock.withLock {
            guard !detached else { return }
            self.surface = surface
            task = Task { [self] in await run() }
        }
    }

    func detach() {
        let open: RemoteTerminal? = lock.withLock {
            detached = true
            surface = nil
            task?.cancel()
            defer { terminal = nil }
            return terminal
        }
        open?.close()
    }

    /// Waits for the session loop to end (tests).
    func finished() async {
        await lock.withLock { task }?.value
    }

    // MARK: Session loop

    private func run() async {
        var policy = ReconnectPolicy()
        while !Task.isCancelled {
            let (cols, rows) = lock.withLock { size }
            let end: AttachEnd
            do {
                end = try await attacher.attach(
                    cols: cols,
                    rows: rows,
                    onOpen: { [self] terminal in opened(terminal) },
                    onOutput: { [self] data in received(data) })
            } catch let error as RemoteError {
                // Host key changed, key refused, no Secure Enclave: say why
                // and stop; retrying cannot help.
                received(Data("\r\n\u{1b}[31m\(error.message)\u{1b}[0m\r\n".utf8))
                withSurface { calls.exited($0, 1) }
                return
            } catch {
                // Could not connect (or the pane closed mid-attach): try
                // again unless the pane is gone.
                closed()
                if Task.isCancelled { return }
                guard (try? await delays(policy.nextDelay())) != nil else { return }
                continue
            }
            if Task.isCancelled { return }
            closed()
            switch end {
            case .exited(let code):
                withSurface { calls.exited($0, UInt32(bitPattern: code)) }
                return
            case .lost:
                withSurface { calls.disconnected($0) }
                guard (try? await delays(policy.nextDelay())) != nil else { return }
            }
            policy.reset()
        }
    }

    private func opened(_ terminal: RemoteTerminal) {
        let keep: Bool = lock.withLock {
            guard !detached else { return false }
            self.terminal = terminal
            return true
        }
        if !keep { terminal.close() }
    }

    private func closed() {
        lock.withLock { terminal = nil }
    }

    /// Received bytes go to the surface while it exists. The lock is held
    /// across the call so `detach` (before the surface is freed) waits for
    /// a feed in flight.
    private func received(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard let surface else { return }
        calls.feed(surface, data)
    }

    private func withSurface(_ body: (ghostty_surface_t) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let surface else { return }
        body(surface)
    }
}

/// Attaches over SSH: a fresh connection per attempt, so a dropped network
/// reconnects from scratch.
@available(macOS 15, *)
struct SSHAttacher: RemoteAttacher {
    let host: RemoteHost
    let key: RemoteKey
    let knownHosts: KnownHosts
    let sessionID: String

    func attach(
        cols: Int,
        rows: Int,
        onOpen: @escaping @Sendable (RemoteTerminal) -> Void,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws -> AttachEnd {
        let connection = try await RemoteConnection.connect(to: host, key: key, knownHosts: knownHosts)
        let end = await connection.attach(
            sessionID: sessionID, cols: cols, rows: rows, onOpen: onOpen, onOutput: onOutput)
        await connection.close()
        return end
    }
}
#endif
```

Every `RemoteError` is a hard stop (host key changed, key refused, no Secure Enclave); any other error is a failed connect and is retried.

`SurfaceCalls.live.exited` hops to the main thread (the core handles exits there). That is safe without re-checking the surface: `withSurface` only calls it while the surface is attached, and the view frees the surface in a main-actor task enqueued after its `deinit` detaches, so the exit block always runs first.

Note the reset placement: `policy.reset()` runs only after an attach that returned (`.lost`), i.e. after a connection that worked, so repeated connect failures keep backing off.

- [ ] **Step 8: Run the tests to verify they pass**

Run:
```bash
zig build -Demit-macos-app=false
macos/skins-test.sh RemoteSurfaceIOTests
for s in TmuxSessionTests TmuxOwnershipTests TmuxPaneTests TmuxClientTests SessionLaunchTests SessionsPromptTests; do macos/skins-test.sh $s >/dev/null || echo "FAIL $s"; done
```
Expected: `** TEST SUCCEEDED **` and no `FAIL` lines.

- [ ] **Step 9: Commit**

```bash
git add macos/Ghostty.xcodeproj/project.pbxproj "macos/Sources/Ghostty/Surface View/SurfaceView.swift" \
  macos/Sources/Ghostty/Ghostty.Surface.swift "macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift" \
  macos/Sources/Features/Remote/RemoteSurfaceIO.swift macos/Tests/Remote/RemoteSurfaceIOTests.swift
git commit -m "lostty: remote surfaces in the Mac app: bridge to LosttyRemote with reconnect; app needs macOS 14

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Debug menu — open a session over SSH to localhost

**Files:**
- Create: `macos/Sources/Features/Remote/RemoteDebugUI.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (the `#if DEBUG` block that adds "Preview Claude Trace")

**Interfaces:**
- Consumes: `RemoteKey.secureEnclave(storedAt:)`, `RemoteConnection`, `KnownHosts`, `RemoteHost.localhost(terminfoDir:)`, `RemoteError.message` (Task 4); `RemoteSurfaceIO`, `SSHAttacher` (Task 5); `TerminalController.newWindow(_:withBaseConfig:)`.
- Produces: `enum RemoteDebugUI { @MainActor static func installMenuItems(after anchor: NSMenuItem, target: AnyObject) }` (DEBUG only).

- [ ] **Step 1: Write `RemoteDebugUI.swift`**

```swift
#if os(macOS) && DEBUG
import AppKit
import LosttyRemote

/// Lostty Mobile, debug builds only: opens one of this Mac's tmux sessions
/// over SSH to localhost through the remote backend, proving the core and
/// LosttyRemote before the iPhone app exists. Needs Remote Login on and the
/// key from "Copy Remote Key" in ~/.ssh/authorized_keys.
@MainActor
enum RemoteDebugUI {
    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty", isDirectory: true)
    }
    static var keyURL: URL { supportDir.appendingPathComponent("remote-key") }
    static var knownHostsURL: URL { supportDir.appendingPathComponent("known_hosts") }
    static var host: RemoteHost {
        RemoteHost.localhost(terminfoDir: Bundle.main.resourceURL!.appendingPathComponent("terminfo").path)
    }

    static func installMenuItems(after anchor: NSMenuItem) {
        guard let menu = anchor.menu else { return }
        let open = NSMenuItem(title: "Open Remote Session…", action: #selector(Actions.open(_:)), keyEquivalent: "")
        let copy = NSMenuItem(title: "Copy Remote Key", action: #selector(Actions.copyKey(_:)), keyEquivalent: "")
        for item in [open, copy] {
            item.target = Actions.shared
        }
        let index = menu.index(of: anchor) + 1
        menu.insertItem(copy, at: index)
        menu.insertItem(open, at: index)
    }

    final class Actions: NSObject {
        static let shared = Actions()

        @objc func copyKey(_ sender: Any?) {
            do {
                let key = try RemoteKey.secureEnclave(storedAt: RemoteDebugUI.keyURL)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key.publicKeyLine + "\n", forType: .string)
            } catch {
                RemoteDebugUI.show(error)
            }
        }

        @objc func open(_ sender: Any?) {
            guard #available(macOS 15, *) else {
                RemoteDebugUI.show(message: "Remote sessions need macOS 15 or later.")
                return
            }
            Task { @MainActor in await RemoteDebugUI.open() }
        }
    }

    @available(macOS 15, *)
    static func open() async {
        guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }
        do {
            let key = try RemoteKey.secureEnclave(storedAt: keyURL)
            let knownHosts = KnownHosts(fileURL: knownHostsURL)
            let connection = try await RemoteConnection.connect(to: host, key: key, knownHosts: knownHosts)
            let sessions = try await connection.sessions()
            await connection.close()
            guard let session = pick(sessions) else { return }

            var config = Ghostty.SurfaceConfiguration()
            config.remoteIO = RemoteSurfaceIO(attacher: SSHAttacher(
                host: host, key: key, knownHosts: knownHosts, sessionID: session.id))
            _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
        } catch {
            show(error)
        }
    }

    /// Asks which session to open; nil when there are none or on Cancel.
    static func pick(_ sessions: [RemoteSession]) -> RemoteSession? {
        guard !sessions.isEmpty else {
            show(message: "No Lostty tmux sessions are running on this Mac.")
            return nil
        }
        let alert = NSAlert()
        alert.messageText = "Open Remote Session"
        alert.informativeText = "Opens the session over SSH to localhost, as the phone will."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        popup.addItems(withTitles: sessions.map { "\($0.name) (\($0.id))" })
        alert.accessoryView = popup
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return sessions[popup.indexOfSelectedItem]
    }

    static func show(_ error: Error) {
        show(message: (error as? RemoteError)?.message ?? error.localizedDescription)
    }

    static func show(message: String) {
        let alert = NSAlert()
        alert.messageText = "Lostty Remote"
        alert.informativeText = message
        alert.runModal()
    }
}
#endif
```

- [ ] **Step 2: Install the items from `AppDelegate`**

In `macos/Sources/App/macOS/AppDelegate.swift`, inside the existing `#if DEBUG` block that inserts "Preview Claude Trace", after `menu.insertItem(item, at: menu.index(of: anchor) + 2)`:

```swift
            // Lostty Mobile: open a session over SSH to localhost.
            RemoteDebugUI.installMenuItems(after: item)
```

- [ ] **Step 3: Build and run the existing suites**

Run:
```bash
xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build 2>&1 | grep -E '\*\* BUILD|error:'
macos/skins-test.sh RemoteSurfaceIOTests | tail -1
sh macos/lostty-tmux-smoke.sh | tail -1
```
Expected: `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, `PASS`.

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/Remote/RemoteDebugUI.swift macos/Sources/App/macOS/AppDelegate.swift
git commit -m "lostty: debug menu opens a tmux session over SSH to localhost through the remote backend

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Desk check and spec notes

**Files:**
- Modify: `docs/superpowers/specs/2026-10-09-lostty-mobile-design.md` (§3 and §4: "As built (phase 2)")

- [ ] **Step 1: Automated checks**

Run:
```bash
zig build test -Dtest-filter="lostty" && echo ZIG-OK
(cd macos/LosttyRemote && swift test 2>&1 | tail -2)
for s in RemoteSurfaceIOTests TmuxSessionTests TmuxOwnershipTests TmuxPaneTests TmuxClientTests SessionLaunchTests SessionsPromptTests; do macos/skins-test.sh $s >/dev/null || echo "FAIL $s"; done
sh macos/lostty-tmux-smoke.sh | tail -1
```
Expected: `ZIG-OK`, package tests pass, no `FAIL`, `PASS`.

- [ ] **Step 2: STOP — desk check with your human partner**

They do the setup (security settings are theirs to change), then run the Debug app (`open macos/build/Debug/Ghostty.app`, which runs beside the installed Lostty):

Setup (once):
1. System Settings → General → Sharing → **Remote Login** on (only for their user).
2. In the Debug app's menu (next to "Preview Claude Trace"): **Copy Remote Key** — Touch ID may prompt. Append the clipboard to `~/.ssh/authorized_keys` (`pbpaste >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys`).

Checks:
1. Cmd+N in the Debug app; `cd ~/projectrepos/lostty`. Then **Open Remote Session…**: Touch ID prompt, then a list including `lostty ($N)`. Pick it: a second window opens showing the same shell.
2. Type `echo remote` in the remote window: it runs and shows in both windows.
3. The remote window's skin follows `cd` into a skinned project (OSC 7 through tmux and SSH).
4. Run `claude`, send `say hi`: the trace and "Ready for response" show in the remote window.
5. Resize the remote window: the shell redraws at the new size (`tput cols` matches).
6. Unicode: `echo héllo ✓` shows correctly in the remote window.
7. Close the remote window (Cmd+W): it closes without asking; the Mac window and its session are untouched (`tmux -L lostty ls` still lists it).
8. Reopen it, then drop the connection: in another terminal run `pkill -f "sshd-session: $USER@"` (or `pkill -f "sshd: $USER@"` on older macOS). The remote window shows a dim "reconnecting…", then (after Touch ID) reattaches and redraws.
9. In the remote window type `exit`: the session ends, the remote window closes, and the Mac window closes too.
10. Host key pin: edit `~/Library/Application Support/Lostty/known_hosts`, change one character of the key, then **Open Remote Session…**: a "host key … changed" message, no connection. Restore the line afterwards.

- [ ] **Step 3: Fix what fails**

Each failure gets a fix through a subagent with review, then the check is repeated.

- [ ] **Step 4: Record how phase 2 was built**

Add an "As built (phase 2)" list to the end of spec §4 (after the debug-window paragraph): the remote backend's C API as shipped (including `ghostty_surface_io_exited`, which the spec did not name), the PTY attach (shell + `exec … tmux -u … attach-session -t '$N'`), PATH prefix, host-key file and key-handle locations, reconnect backoff (0.5 s → 15 s), macOS 14 floor and macOS 15 for the PTY API, the desk outcomes, and anything deferred. Commit:

```bash
git add docs/superpowers/specs/2026-10-09-lostty-mobile-design.md
git commit -m "docs: Lostty Mobile spec records how phase 2 was built

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
