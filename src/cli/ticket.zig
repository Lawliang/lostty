const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("claude/protocol.zig");
const claude_state = @import("claude_state.zig");

pub const user_var_name = "LOSTTY_TICKET";

/// The longest report the app takes: a longer user var is dropped whole.
const value_max = @import("../Surface.zig").max_user_var_len;

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

/// Each verb, with how many arguments follow it. The app checks who may
/// use it; this checks only the shape.
const verbs = [_]struct { name: []const u8, args: usize }{
    .{ .name = "review", .args = 2 },
    .{ .name = "blocked", .args = 2 },
};

const usage =
    \\usage: lostty +ticket review <key> "<one line on what changed>"
    \\       lostty +ticket blocked <key> "<why>"
    \\
;

/// The `ticket` command is run by a feature's agent in a Lostty pane to
/// report on the ticket Lostty typed into it (zone board spec §6):
/// `+ticket review TB-7 "what changed"` or `+ticket blocked TB-7 "why"`.
/// It writes its arguments to the pane's terminal as the LOSTTY_TICKET
/// user var, as +claude-state does, so the app knows which pane sent it,
/// and prints "sent". The app applies it only if that pane may: the report
/// is one-way, so it can't say. A bad call prints usage and exits 1.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    var stdout_buf: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};
    var stderr_buf: [512]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const err = &stderr_writer.interface;
    defer err.flush() catch {};

    const argv = try std.process.argsAlloc(alloc);
    const args = parse(argsAfter(argv)) orelse {
        try err.writeAll(usage);
        return 1;
    };
    if (std.posix.getenv(protocol.surface_env) == null) {
        try err.writeAll("ticket: run this in a Lostty terminal\n");
        return 1;
    }
    const seq = try protocol.encodeUserVar(alloc, user_var_name, try json(alloc, args), std.posix.getenv("TMUX") != null);
    const tty = claude_state.openTerminal(alloc) orelse {
        try err.writeAll("ticket: can't reach this pane's terminal\n");
        return 1;
    };
    defer tty.close();
    try tty.writeAll(seq);
    try out.writeAll("sent\n");
    return 0;
}

/// The arguments after `+ticket` in `argv`.
fn argsAfter(argv: []const []const u8) []const []const u8 {
    for (argv, 0..) |arg, i| if (std.mem.eql(u8, arg, "+ticket")) return argv[i + 1 ..];
    return &.{};
}

/// `args` when they're a verb with its arguments, none of them empty.
pub fn parse(args: []const []const u8) ?[]const []const u8 {
    if (args.len == 0) return null;
    for (verbs) |verb| {
        if (!std.mem.eql(u8, args[0], verb.name)) continue;
        if (args.len != verb.args + 1) return null;
        for (args) |arg| if (std.mem.trim(u8, arg, " \t\r\n").len == 0) return null;
        return args;
    }
    return null;
}

/// The user var's value: the arguments as a JSON array of strings
/// (TicketReport in the app reads it), the longest cut at a UTF-8
/// boundary until it fits in `value_max` bytes.
pub fn json(alloc: Allocator, args: []const []const u8) ![]u8 {
    const cut = try alloc.dupe([]const u8, args);
    defer alloc.free(cut);
    while (true) {
        const out = try std.json.Stringify.valueAlloc(alloc, cut, .{});
        if (out.len <= value_max) return out;
        alloc.free(out);
        var longest: usize = 0;
        for (cut, 0..) |arg, i| {
            if (arg.len > cut[longest].len) longest = i;
        }
        // The longest prefix that fits, searched by its JSON length, since
        // escaping makes that longer than its bytes; none when even an
        // empty one doesn't, so the next longest is cut too.
        const arg = cut[longest];
        var fits: usize = 0;
        var too_long = arg.len;
        while (too_long - fits > 1) {
            const mid = fits + (too_long - fits) / 2;
            cut[longest] = arg[0..utf8Prefix(arg, mid)];
            if (try jsonLen(alloc, cut) <= value_max) fits = mid else too_long = mid;
        }
        cut[longest] = arg[0..utf8Prefix(arg, fits)];
    }
}

fn jsonLen(alloc: Allocator, args: []const []const u8) !usize {
    const out = try std.json.Stringify.valueAlloc(alloc, args, .{});
    defer alloc.free(out);
    return out.len;
}

/// The length of the longest prefix of `s` at most `max` bytes that ends
/// on a UTF-8 character boundary.
fn utf8Prefix(s: []const u8, max: usize) usize {
    if (s.len <= max) return s.len;
    var end = max;
    while (end > 0 and s[end] & 0xC0 == 0x80) end -= 1;
    return end;
}

test "ticket: parse takes each verb with its arguments only" {
    const t = std.testing;
    try t.expect(parse(&.{ "review", "TB-7", "Added the button" }) != null);
    try t.expect(parse(&.{ "blocked", "TB-7", "Needs GOOGLE_CLIENT_ID" }) != null);
    try t.expect(parse(&.{ "review", "TB-7" }) == null);
    try t.expect(parse(&.{ "review", "TB-7", "one", "two" }) == null);
    try t.expect(parse(&.{ "review", " ", "Added the button" }) == null);
    try t.expect(parse(&.{ "done", "TB-7", "Added the button" }) == null);
    try t.expect(parse(&.{}) == null);
}

test "ticket: argsAfter skips the program and the action" {
    const t = std.testing;
    const args = argsAfter(&.{ "lostty", "+ticket", "review", "TB-7", "Done" });
    try t.expectEqual(@as(usize, 3), args.len);
    try t.expectEqualStrings("review", args[0]);
    try t.expectEqual(@as(usize, 0), argsAfter(&.{"lostty"}).len);
}

test "ticket: json is the arguments as the app reads them" {
    const t = std.testing;
    const out = try json(t.allocator, &.{ "review", "TB-7", "Added the \"Continue\" button\nand the callback" });
    defer t.allocator.free(out);
    try t.expectEqualStrings(
        \\["review","TB-7","Added the \"Continue\" button\nand the callback"]
    , out);
}

test "ticket: a long report is cut to fit at a UTF-8 boundary" {
    const t = std.testing;
    try t.expectEqual(@as(usize, 3), utf8Prefix("abc", 10));
    // "é" is two bytes: cutting through it keeps neither.
    try t.expectEqual(@as(usize, 1), utf8Prefix("aé", 2));
    try t.expectEqual(@as(usize, 3), utf8Prefix("aéb", 3));
    // Each newline is two bytes in JSON, so the raw length alone isn't enough.
    const long = "·\n" ** value_max;
    const out = try json(t.allocator, &.{ "review", "TB-7", long });
    defer t.allocator.free(out);
    try t.expect(out.len <= value_max and out.len > value_max - 8);
    try t.expect(std.mem.startsWith(u8, out, "[\"review\",\"TB-7\",\"·\\n"));
    try t.expect(std.unicode.utf8ValidateSlice(out));
}

test "ticket: the report reaches the app as LOSTTY_TICKET" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const seq = try protocol.encodeUserVar(alloc, user_var_name, try json(alloc, &.{ "blocked", "TB-8", "why" }), false);
    try t.expectEqualStrings("\x1b]1337;SetUserVar=LOSTTY_TICKET=WyJibG9ja2VkIiwiVEItOCIsIndoeSJd\x07", seq);
}
