const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("claude/protocol.zig");
const claude_state = @import("claude_state.zig");

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

/// The `sharpen-log` command is run by Lostty's prompt sharpener mod
/// (mods/lostty-sharpener) once per prompt. It reads one JSON entry on
/// stdin (what was typed, what was sent, the verdict and why), adds an id
/// and the time, and appends it as one line to
/// `~/Library/Application Support/Lostty/sharpener/log.jsonl`. A
/// `rewritten` entry also tells the pane, so it can show yours next to the
/// rewrite; any other prompt clears that. It prints the entry's id and never fails the prompt: on any
/// problem it exits 0 having done nothing.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const stdin = std.fs.File.stdin();
    if (std.posix.isatty(stdin.handle)) return 0;
    var buf: [4096]u8 = undefined;
    var reader = stdin.reader(&buf);
    const input = reader.interface.allocRemaining(alloc, .limited(4 << 20)) catch return 0;
    const home = std.posix.getenv("HOME") orelse return 0;

    var id_bytes: [6]u8 = undefined;
    std.crypto.random.bytes(&id_bytes);
    const id = std.fmt.bytesToHex(id_bytes, .lower);
    const line = entryLine(alloc, input, &id, std.time.milliTimestamp()) catch return 0;
    append(logDir(alloc, home) catch return 0, line) catch return 0;
    std.fs.File.stdout().writeAll(&id) catch {};

    if (std.posix.getenv(protocol.surface_env) == null) return 0;
    const shown: ?[]const u8 = switch (paneSignal(alloc, input)) {
        .none => return 0,
        .show => &id,
        .clear => null,
    };
    const seq = signal(alloc, shown, std.posix.getenv("TMUX") != null) catch return 0;
    const tty = claude_state.openTerminal(alloc) orelse return 0;
    defer tty.close();
    claude_state.writeWhole(tty, seq) catch {};
    return 0;
}

pub const log_name = "log.jsonl";

/// Where the sharpener keeps its log and its off switch (`off`).
pub fn logDir(alloc: Allocator, home: []const u8) ![]u8 {
    return std.fs.path.join(alloc, &.{ home, "Library", "Application Support", "Lostty", "sharpener" });
}

/// `input`, a JSON object with a string `verdict`, with `id` and `time`
/// (ms since the epoch) added, as one line ending in a newline.
pub fn entryLine(alloc: Allocator, input: []const u8, id: []const u8, time_ms: i64) ![]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return error.BadEntry;
    defer parsed.deinit();
    var value = parsed.value;
    if (value != .object) return error.BadEntry;
    const verdict = value.object.get("verdict") orelse return error.BadEntry;
    if (verdict != .string) return error.BadEntry;
    try value.object.put("id", .{ .string = id });
    try value.object.put("time", .{ .integer = time_ms });
    const json = try std.json.Stringify.valueAlloc(alloc, value, .{});
    defer alloc.free(json);
    return std.mem.concat(alloc, u8, &.{ json, "\n" });
}

/// Appends `line` to `dir`/log.jsonl in one write, so lines from panes
/// sending at once never interleave.
pub fn append(dir: []const u8, line: []const u8) !void {
    try std.fs.cwd().makePath(dir);
    var d = try std.fs.cwd().openDir(dir, .{});
    defer d.close();
    const f = try d.createFile(log_name, .{ .truncate = false });
    defer f.close();
    std.posix.flock(f.handle, std.posix.LOCK.EX) catch {};
    try f.seekFromEnd(0);
    try f.writeAll(line);
}

pub const PaneSignal = enum { none, show, clear };

/// What an entry tells its pane's strip: a rewrite shows; any other prompt
/// the owner sent clears the last one; a notification or a peer's message
/// (rule `origin`) leaves it.
pub fn paneSignal(alloc: Allocator, input: []const u8) PaneSignal {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return .none;
    defer parsed.deinit();
    if (parsed.value != .object) return .none;
    const o = parsed.value.object;
    const verdict = o.get("verdict") orelse return .none;
    if (verdict != .string) return .none;
    if (std.mem.eql(u8, verdict.string, "rewritten")) return .show;
    if (o.get("rule")) |rule| {
        if (rule == .string and std.mem.eql(u8, rule.string, "origin")) return .none;
    }
    return .clear;
}

/// The pane's `sharpened` message: with an id, the rewrite to show (the app
/// reads it from the log, as a prompt can outgrow what the message holds);
/// with none, clear the strip.
pub fn signal(alloc: Allocator, id: ?[]const u8, tmux: bool) ![]u8 {
    const json = if (id) |v|
        try std.json.Stringify.valueAlloc(alloc, .{ .v = 1, .state = "sharpened", .id = v }, .{})
    else
        try std.json.Stringify.valueAlloc(alloc, .{ .v = 1, .state = "sharpened" }, .{});
    defer alloc.free(json);
    return protocol.encodeUserVar(alloc, protocol.user_var_name, json, tmux);
}

test "sharpen log: a line is the entry with its id and time, on one line" {
    const a = std.testing.allocator;
    const line = try entryLine(a, "{\"verdict\":\"clean\",\"original\":\"say \\\"hi\\\"\\nthen é\"}", "a1b2", 1700);
    defer a.free(line);
    try std.testing.expect(std.mem.endsWith(u8, line, "\n"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, line, "\n"));
    const parsed = try std.json.parseFromSlice(std.json.Value, a, line, .{});
    defer parsed.deinit();
    const o = parsed.value.object;
    try std.testing.expectEqualStrings("a1b2", o.get("id").?.string);
    try std.testing.expectEqual(@as(i64, 1700), o.get("time").?.integer);
    try std.testing.expectEqualStrings("say \"hi\"\nthen é", o.get("original").?.string);
}

test "sharpen log: an entry that isn't an object with a verdict is refused" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.BadEntry, entryLine(a, "[1,2]", "x", 1));
    try std.testing.expectError(error.BadEntry, entryLine(a, "{\"original\":\"x\"}", "x", 1));
    try std.testing.expectError(error.BadEntry, entryLine(a, "not json", "x", 1));
}

test "sharpen log: the log lives in Lostty's Application Support" {
    const a = std.testing.allocator;
    const p = try logDir(a, "/Users/me");
    defer a.free(p);
    try std.testing.expectEqualStrings("/Users/me/Library/Application Support/Lostty/sharpener", p);
}

test "sharpen log: appends whole lines, creating the folder" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const a = std.testing.allocator;
    const root = try tmp.dir.realpathAlloc(a, ".");
    defer a.free(root);
    const dir = try std.fs.path.join(a, &.{ root, "deep", "sharpener" });
    defer a.free(dir);
    try append(dir, "{\"id\":\"1\"}\n");
    try append(dir, "{\"id\":\"2\"}\n");
    const text = try tmp.dir.readFileAlloc(a, "deep/sharpener/log.jsonl", 1 << 16);
    defer a.free(text);
    try std.testing.expectEqualStrings("{\"id\":\"1\"}\n{\"id\":\"2\"}\n", text);
}

test "sharpen log: a rewrite signals the pane with only the entry's id" {
    const a = std.testing.allocator;
    const seq = try signal(a, "a1b2", false);
    defer a.free(seq);
    try std.testing.expectEqualStrings("{\"v\":1,\"state\":\"sharpened\",\"id\":\"a1b2\"}", try decodeSeq(&seq_buf, seq));
}

test "sharpen log: a prompt that wasn't rewritten clears the pane's strip" {
    const a = std.testing.allocator;
    const seq = try signal(a, null, false);
    defer a.free(seq);
    try std.testing.expectEqualStrings("{\"v\":1,\"state\":\"sharpened\"}", try decodeSeq(&seq_buf, seq));
}

test "sharpen log: what each entry tells the pane" {
    const a = std.testing.allocator;
    try std.testing.expectEqual(PaneSignal.show, paneSignal(a, "{\"verdict\":\"rewritten\"}"));
    try std.testing.expectEqual(PaneSignal.clear, paneSignal(a, "{\"verdict\":\"clean\"}"));
    try std.testing.expectEqual(PaneSignal.clear, paneSignal(a, "{\"verdict\":\"skipped\",\"rule\":\"short\"}"));
    // A notification or a peer's message is not the owner's prompt.
    try std.testing.expectEqual(PaneSignal.none, paneSignal(a, "{\"verdict\":\"skipped\",\"rule\":\"origin\"}"));
    try std.testing.expectEqual(PaneSignal.none, paneSignal(a, "nope"));
}

var seq_buf: [256]u8 = undefined;

fn decodeSeq(buf: []u8, seq: []const u8) ![]const u8 {
    const prefix = "\x1b]1337;SetUserVar=LOSTTY_CLAUDE=";
    try std.testing.expect(std.mem.startsWith(u8, seq, prefix));
    const b64 = seq[prefix.len .. seq.len - 1];
    const n = try std.base64.standard.Decoder.calcSizeForSlice(b64);
    try std.base64.standard.Decoder.decode(buf[0..n], b64);
    return buf[0..n];
}
