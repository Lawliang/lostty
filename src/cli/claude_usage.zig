const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("claude/protocol.zig");
const usage = @import("claude/usage.zig");
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

/// The `claude-usage` command is Lostty's Claude Code status line: Claude
/// Code runs it after each reply with session JSON on stdin, and it tells
/// the pane how full the context window is and how much of the plan's
/// limits is used, for the window's usage bar. It prints nothing (so the
/// status line stays empty), never fails, and outside Lostty does nothing.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const input = stdin_reader.interface.allocRemaining(alloc, .limited(1 << 20)) catch return 0;
    if (std.posix.getenv(protocol.surface_env) == null) return 0;

    const json = (usage.report(alloc, input) catch return 0) orelse return 0;
    const tmux = std.posix.getenv("TMUX") != null;
    const seq = protocol.encodeUserVar(alloc, usage.user_var_name, json, tmux) catch return 0;
    const tty = claude_state.openTerminal(alloc) orelse return 0;
    defer tty.close();
    tty.writeAll(seq) catch {};
    return 0;
}

test {
    _ = @import("claude/usage.zig");
}
