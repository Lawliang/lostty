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

/// The config for a surface whose options ask for remote IO, or null for a
/// local process (mode 0, an unknown mode, or a missing callback). Surface
/// options use 1 for remote (GHOSTTY_SURFACE_IO_REMOTE).
pub fn fromOptions(io_mode: c_int, userdata: ?*anyopaque, write_fn: ?WriteFn, resize_fn: ?ResizeFn) ?Config {
    if (io_mode != 1) return null;
    return .{
        .userdata = userdata,
        .write = write_fn orelse return null,
        .resize = resize_fn orelse return null,
    };
}

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
        // Qualified: a bare `resize` is ambiguous with Remote.resize here.
        return .{ .userdata = self, .write = TestSink.write, .resize = TestSink.resize };
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

test "lostty remote: surface options ask for the remote backend only when complete" {
    const t = std.testing;
    var sink: TestSink = .{};
    // Default: a local process.
    try t.expect(fromOptions(0, null, TestSink.write, TestSink.resize) == null);
    // Remote mode with both callbacks.
    const cfg = fromOptions(1, &sink, TestSink.write, TestSink.resize).?;
    try t.expect(cfg.userdata == @as(?*anyopaque, &sink));
    // Remote mode missing a callback falls back to local.
    try t.expect(fromOptions(1, null, TestSink.write, null) == null);
    // An unknown mode is local.
    try t.expect(fromOptions(7, null, TestSink.write, TestSink.resize) == null);
}
