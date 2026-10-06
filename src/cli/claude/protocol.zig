//! Pure logic for `+claude-state`: the LOSTTY_CLAUDE wire format. See
//! docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md (§2.1).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const user_var_name = "LOSTTY_CLAUDE";
pub const surface_env = "LOSTTY_SURFACE";

pub const State = enum { busy, idle, exit };

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

pub const ProcInfo = struct {
    ppid: i32,
    /// Terminal name as `ps` prints it ("ttys001", "pts/3"), or null.
    tty: ?[]const u8,
};

/// Parses `ps -o ppid=,tty= -p <pid>` output.
pub fn parsePs(out: []const u8) ?ProcInfo {
    var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
    const ppid = std.fmt.parseInt(i32, it.next() orelse return null, 10) catch return null;
    const tty = it.next() orelse return .{ .ppid = ppid, .tty = null };
    return .{ .ppid = ppid, .tty = if (isTtyName(tty)) tty else null };
}

/// "ttys001" or "pts/3": letters/digits with at most one "/" and no dots.
fn isTtyName(s: []const u8) bool {
    if (s.len == 0 or std.mem.indexOfScalar(u8, s, '?') != null) return false;
    var slashes: usize = 0;
    for (s) |c| {
        if (c == '/') {
            slashes += 1;
        } else if (!std.ascii.isAlphanumeric(c)) return false;
    }
    return slashes <= 1;
}

/// Claude Code runs hooks without a controlling terminal, so `/dev/tty`
/// fails there. Walk up from `start` (at most `max_hops` processes) to the
/// first one attached to a terminal: that is `claude` in the pane.
/// `ctx.lookup(pid) ?ProcInfo` supplies process info.
pub fn findTty(ctx: anytype, start: i32, max_hops: usize) ?[]const u8 {
    var pid = start;
    var hops: usize = 0;
    while (hops < max_hops and pid > 1) : (hops += 1) {
        const info = ctx.lookup(pid) orelse return null;
        if (info.tty) |tty| return tty;
        pid = info.ppid;
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

test "claude protocol: parsePs" {
    const t = std.testing;
    const a = parsePs("  38137 ttys001\n").?;
    try t.expectEqual(@as(i32, 38137), a.ppid);
    try t.expectEqualStrings("ttys001", a.tty.?);
    const b = parsePs("1 ??\n").?;
    try t.expect(b.tty == null);
    const c = parsePs("812 pts/3\n").?;
    try t.expectEqualStrings("pts/3", c.tty.?);
    try t.expect(parsePs("812 ?\n").?.tty == null);
    try t.expect(parsePs("") == null);
    try t.expect(parsePs("abc ttys001") == null);
    // Nothing path-like beyond one "pts/N" level.
    try t.expect(parsePs("5 ../../etc/passwd").?.tty == null);
}

test "claude protocol: findTty walks up to the first process with a terminal" {
    const Table = struct {
        pub fn lookup(_: @This(), pid: i32) ?ProcInfo {
            return switch (pid) {
                300 => .{ .ppid = 200, .tty = null }, // +claude-state's sh
                200 => .{ .ppid = 100, .tty = null }, // hook runner
                100 => .{ .ppid = 1, .tty = "ttys001" }, // claude
                else => null,
            };
        }
    };
    const t = std.testing;
    try t.expectEqualStrings("ttys001", findTty(Table{}, 300, 8).?);
    try t.expect(findTty(Table{}, 300, 2) == null);
    try t.expect(findTty(Table{}, 999, 8) == null);
}

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
