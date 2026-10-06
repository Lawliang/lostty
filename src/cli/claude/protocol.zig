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
