//! `lostty-hook`: the two actions Claude Code runs on every tool call and
//! reply (`+claude-state`, `+claude-usage`), without the app. `lostty`
//! runs the same code, but loading the whole app for it costs most of a
//! hook's time. Anything else exits `not_mine`, and the hook command
//! (cli/claude/hooks.zig) then runs `lostty`.

const std = @import("std");
const claude_state = @import("cli/claude_state.zig");
const claude_usage = @import("cli/claude_usage.zig");

/// `lostty` running an action logs nothing to stderr.
pub const std_options: std.Options = .{ .logFn = noLog };

fn noLog(
    comptime _: std.log.Level,
    comptime _: @TypeOf(.enum_literal),
    comptime _: []const u8,
    _: anytype,
) void {}

/// EX_USAGE: not a command line this program runs.
pub const not_mine = 64;

const Hook = enum { @"claude-state", @"claude-usage" };

pub fn main() u8 {
    // `lostty` ignores SIGPIPE (global.zig), so a closed stdout is a
    // failed write there, not a death.
    std.posix.sigaction(std.posix.SIG.PIPE, &.{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    }, null);

    const alloc = std.heap.c_allocator;
    const argv = std.process.argsAlloc(alloc) catch return not_mine;
    const hook = detect(argv[1..]) orelse return not_mine;
    return switch (hook) {
        .@"claude-state" => claude_state.run(alloc),
        .@"claude-usage" => claude_usage.run(alloc),
    } catch 1;
}

/// The one action in `args` when it is ours. `lostty` treats a second
/// action as an error and gives `-e`, `--version`, `--help` and `-h` their
/// own meaning (cli/ghostty.zig): those are left to it.
fn detect(args: []const []const u8) ?Hook {
    var found: ?Hook = null;
    for (args) |arg| {
        for ([_][]const u8{ "-e", "--version", "--help", "-h" }) |special| {
            if (std.mem.eql(u8, arg, special)) return null;
        }
        if (arg.len == 0 or arg[0] != '+') continue;
        if (found != null) return null;
        found = std.meta.stringToEnum(Hook, arg[1..]) orelse return null;
    }
    return found;
}
