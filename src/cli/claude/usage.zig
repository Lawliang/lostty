//! Pure logic for `+claude-usage`: turning the JSON Claude Code feeds its
//! status line command into the LOSTTY_USAGE user var, e.g.
//! `{"v":1,"ctx":{"used":84000,"size":200000},"five":{"pct":42,"reset":1760000000},
//! "week":{"pct":17,"reset":1760400000},"model":"Opus"}`.
//! Each key except `v` is left out when Claude Code did not send it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = std.json.Value;

pub const user_var_name = "LOSTTY_USAGE";

/// The LOSTTY_USAGE value for status line `input`, or null when the input
/// is not a JSON object.
pub fn report(alloc: Allocator, input: []const u8) !?[]u8 {
    const root = std.json.parseFromSliceLeaky(Value, alloc, input, .{}) catch return null;
    if (root != .object) return null;

    var out = std.json.ObjectMap.init(alloc);
    try out.put("v", .{ .integer = 1 });

    if (field(root, "context_window")) |cw| {
        if (number(field(cw, "context_window_size"))) |size| if (size > 0) {
            // Tokens in the window: the last request's input, as /context counts it.
            const used: ?f64 = if (field(cw, "current_usage")) |cu|
                (number(field(cu, "input_tokens")) orelse 0) +
                    (number(field(cu, "cache_creation_input_tokens")) orelse 0) +
                    (number(field(cu, "cache_read_input_tokens")) orelse 0)
            else if (number(field(cw, "used_percentage"))) |pct|
                pct * size / 100
            else
                null;
            if (used) |u| {
                var ctx = std.json.ObjectMap.init(alloc);
                try ctx.put("used", .{ .integer = @intFromFloat(@round(u)) });
                try ctx.put("size", .{ .integer = @intFromFloat(@round(size)) });
                try out.put("ctx", .{ .object = ctx });
            }
        };
    }

    if (field(root, "rate_limits")) |limits| {
        if (try limit(alloc, field(limits, "five_hour"))) |v| try out.put("five", v);
        if (try limit(alloc, field(limits, "seven_day"))) |v| try out.put("week", v);
    }

    if (field(root, "model")) |model| {
        if (field(model, "display_name")) |name| if (name == .string) {
            try out.put("model", name);
        };
    }

    return try std.json.Stringify.valueAlloc(alloc, Value{ .object = out }, .{});
}

/// `{"pct":…,"reset":…}` from a rate_limits window; null without a percentage.
fn limit(alloc: Allocator, window: ?Value) !?Value {
    const w = window orelse return null;
    const pct = number(field(w, "used_percentage")) orelse return null;
    var obj = std.json.ObjectMap.init(alloc);
    try obj.put("pct", .{ .float = pct });
    if (number(field(w, "resets_at"))) |reset| try obj.put("reset", .{ .integer = @intFromFloat(reset) });
    return .{ .object = obj };
}

fn field(v: Value, name: []const u8) ?Value {
    if (v != .object) return null;
    const f = v.object.get(name) orelse return null;
    return if (f == .null) null else f;
}

fn number(v: ?Value) ?f64 {
    return switch (v orelse return null) {
        .integer => |i| @floatFromInt(i),
        .float => |f| if (std.math.isFinite(f)) f else null,
        else => null,
    };
}

test "claude usage: full status line input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = (try report(arena.allocator(),
        \\{"session_id":"abc","model":{"id":"claude-opus","display_name":"Opus"},
        \\ "context_window":{"total_input_tokens":90000,"context_window_size":200000,
        \\   "used_percentage":42,"current_usage":{"input_tokens":10,"output_tokens":500,
        \\   "cache_creation_input_tokens":1990,"cache_read_input_tokens":82000}},
        \\ "rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1760000000},
        \\   "seven_day":{"used_percentage":17,"resets_at":1760400000}}}
    )).?;
    try std.testing.expectEqualStrings(
        \\{"v":1,"ctx":{"used":84000,"size":200000},"five":{"pct":42.5,"reset":1760000000},"week":{"pct":17,"reset":1760400000},"model":"Opus"}
    , out);
}

test "claude usage: missing and null pieces are left out" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Early in a session: no usage yet, no rate limits (API key users).
    try std.testing.expectEqualStrings("{\"v\":1}", (try report(a,
        \\{"context_window":{"context_window_size":200000,"used_percentage":null,"current_usage":null}}
    )).?);
    // Only a percentage: derive the token count.
    try std.testing.expectEqualStrings(
        \\{"v":1,"ctx":{"used":50000,"size":200000},"five":{"pct":3}}
    , (try report(a,
        \\{"context_window":{"context_window_size":200000,"used_percentage":25},
        \\ "rate_limits":{"five_hour":{"used_percentage":3},"seven_day":{"resets_at":5}}}
    )).?);
}

test "claude usage: not an object" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect((try report(arena.allocator(), "")) == null);
    try std.testing.expect((try report(arena.allocator(), "[1,2]")) == null);
    try std.testing.expect((try report(arena.allocator(), "{nope")) == null);
}
