const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("claude/protocol.zig");
const claude_state = @import("claude_state.zig");
const ticket = @import("ticket.zig");

pub const user_var_name = "LOSTTY_AGENT";

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

const usage =
    \\usage: lostty +agent open <agent> [--feature=<feature>] [--branch=<branch>] ["<first message>"]
    \\       lostty +agent report "<what to tell the agent that opened you>"
    \\
;

/// The `agent` command is run in a Lostty pane on the canvas. A project's
/// coordinator opens another agent from the + menu's list, `+agent open
/// Worker --feature=Login --branch=tb-7-google`, as a card in that
/// feature's zone, on a new worktree when a branch is given, or beside
/// its own card without a feature. An agent it opened tells it something
/// with `+agent report "<text>"`. These write the request to the pane's
/// terminal as the LOSTTY_AGENT user var, as +ticket does, so the app
/// knows which pane sent it, and print "sent". A bad call prints usage
/// and exits 1.
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
    const request = parse(argsAfter(argv)) orelse {
        try err.writeAll(usage);
        return 1;
    };
    if (std.posix.getenv(protocol.surface_env) == null) {
        try err.writeAll("agent: run this in a Lostty terminal\n");
        return 1;
    }
    const seq = try protocol.encodeUserVar(alloc, user_var_name, try ticket.json(alloc, request.slice()), std.posix.getenv("TMUX") != null);
    const tty = claude_state.openTerminal(alloc) orelse {
        try err.writeAll("agent: can't reach this pane's terminal\n");
        return 1;
    };
    defer tty.close();
    try claude_state.writeWhole(tty, seq);
    try out.writeAll("sent\n");
    return 0;
}

/// The arguments after `+agent` in `argv`.
fn argsAfter(argv: []const []const u8) []const []const u8 {
    for (argv, 0..) |arg, i| if (std.mem.eql(u8, arg, "+agent")) return argv[i + 1 ..];
    return &.{};
}

/// What the app reads: `["open", agent, message, feature, branch]`, an
/// empty string for each left out, or `["report", text]`.
pub const Request = struct {
    words: [5][]const u8 = .{ "", "", "", "", "" },
    len: usize = 0,

    pub fn slice(self: *const Request) []const []const u8 {
        return self.words[0..self.len];
    }
};

/// The request in `args`; null for anything but `open` with an agent's
/// name and at most one message, or `report` with one line.
pub fn parse(args: []const []const u8) ?Request {
    if (args.len == 0) return null;
    var request: Request = .{};
    if (std.mem.eql(u8, args[0], "report")) {
        if (args.len != 2 or blank(args[1])) return null;
        request.words[0] = "report";
        request.words[1] = args[1];
        request.len = 2;
        return request;
    }
    if (!std.mem.eql(u8, args[0], "open")) return null;
    request.words[0] = "open";
    request.len = 5;
    var message: ?[]const u8 = null;
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--feature=")) {
            request.words[3] = arg["--feature=".len..];
        } else if (std.mem.startsWith(u8, arg, "--branch=")) {
            request.words[4] = arg["--branch=".len..];
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return null;
        } else if (request.words[1].len == 0) {
            if (blank(arg)) return null;
            request.words[1] = arg;
        } else {
            if (message != null) return null;
            message = arg;
        }
    }
    if (request.words[1].len == 0) return null;
    request.words[2] = message orelse "";
    return request;
}

fn blank(s: []const u8) bool {
    return std.mem.trim(u8, s, " \t\r\n").len == 0;
}

test "agent: parse takes open with flags in any order, and report" {
    const t = std.testing;
    const open = parse(&.{ "open", "Worker", "--feature=Login", "--branch=tb-7", "Start on TB-7" }).?;
    try t.expectEqual(@as(usize, 5), open.len);
    try t.expectEqualStrings("Worker", open.words[1]);
    try t.expectEqualStrings("Start on TB-7", open.words[2]);
    try t.expectEqualStrings("Login", open.words[3]);
    try t.expectEqualStrings("tb-7", open.words[4]);

    const plain = parse(&.{ "open", "--feature=Login", "Verifier" }).?;
    try t.expectEqualStrings("Verifier", plain.words[1]);
    try t.expectEqualStrings("", plain.words[2]);
    try t.expectEqualStrings("Login", plain.words[3]);
    try t.expectEqualStrings("", plain.words[4]);

    const report = parse(&.{ "report", "TB-7 passes" }).?;
    try t.expectEqual(@as(usize, 2), report.len);
    try t.expectEqualStrings("TB-7 passes", report.words[1]);

    try t.expect(parse(&.{}) == null);
    try t.expect(parse(&.{"open"}) == null);
    try t.expect(parse(&.{ "open", " " }) == null);
    try t.expect(parse(&.{ "open", "Worker", "one", "two" }) == null);
    try t.expect(parse(&.{ "open", "Worker", "--model=opus" }) == null);
    try t.expect(parse(&.{"report"}) == null);
    try t.expect(parse(&.{ "report", "" }) == null);
    try t.expect(parse(&.{ "report", "a", "b" }) == null);
    try t.expect(parse(&.{ "close", "Worker" }) == null);
}

test "agent: argsAfter skips the program and the action" {
    const t = std.testing;
    const args = argsAfter(&.{ "lostty", "+agent", "report", "Done" });
    try t.expectEqual(@as(usize, 2), args.len);
    try t.expectEqualStrings("report", args[0]);
}
