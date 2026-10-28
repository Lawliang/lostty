const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("claude/protocol.zig");
const claude_state = @import("claude_state.zig");

pub const user_var_name = "LOSTTY_CLOSE_CHECK";

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

/// The `close-check` command answers Lostty's close check: the
/// lostty-close-check skill runs `+close-check done` when the agent's work
/// in this pane is finished, so Lostty closes the terminal, or
/// `+close-check pending` to keep it open. Lostty ignores it unless it
/// asked. Outside a Lostty terminal it says so and exits 1; a bad argument
/// exits 2.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const stderr = std.fs.File.stderr();
    const argv = try std.process.argsAlloc(alloc);
    const answer = parse(argv) orelse {
        try stderr.writeAll("Usage: lostty +close-check done|pending\n");
        return 2;
    };

    const tty = if (std.posix.getenv(protocol.surface_env) != null)
        claude_state.openTerminal(alloc)
    else
        null;
    const file = tty orelse {
        try stderr.writeAll("Not in a Lostty terminal\n");
        return 1;
    };
    defer file.close();
    const tmux = std.posix.getenv("TMUX") != null;
    try file.writeAll(try protocol.encodeUserVar(alloc, user_var_name, answer, tmux));
    return 0;
}

/// The one `done` or `pending` among the arguments after `+close-check`.
fn parse(argv: []const []const u8) ?[]const u8 {
    var answer: ?[]const u8 = null;
    for (argv[1..]) |arg| {
        if (std.mem.eql(u8, arg, "+close-check")) continue;
        if (answer != null) return null;
        if (!std.mem.eql(u8, arg, "done") and !std.mem.eql(u8, arg, "pending")) return null;
        answer = arg;
    }
    return answer;
}

test "close-check: parse" {
    const t = std.testing;
    try t.expectEqualStrings("done", parse(&.{ "lostty", "+close-check", "done" }).?);
    try t.expectEqualStrings("pending", parse(&.{ "lostty", "+close-check", "pending" }).?);
    try t.expect(parse(&.{ "lostty", "+close-check" }) == null);
    try t.expect(parse(&.{ "lostty", "+close-check", "maybe" }) == null);
    try t.expect(parse(&.{ "lostty", "+close-check", "done", "pending" }) == null);
}
