const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const session = @import("tmux/session.zig");
const naming = @import("tmux/naming.zig");
const launch = @import("tmux_launch.zig");

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

/// The `tmux-rename` command is run by Lostty's zsh snippet when the shell
/// enters another project: it renames the pane's tmux session after the
/// project (`idfk`, then `idfk-2` for a second pane there), which is how the
/// phone lists sessions. Outside Lostty's tmux it does nothing; it never
/// prints and always exits 0.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const argv = std.process.argsAlloc(alloc) catch return 0;
    const path = naming.pathFromArgs(argv) orelse return 0;
    if (std.posix.getenv("TMUX") == null) return 0;
    const pane = std.posix.getenv("TMUX_PANE") orelse return 0;
    const tmux = session.findTmux(alloc, std.posix.getenv("PATH"), launch.isExecutable) orelse return 0;
    const base = naming.projectName(alloc, path, std.posix.getenv("HOME")) catch return 0;

    // Another pane can take the same name between listing and renaming
    // (two windows opened in one project); then try the next name.
    for (0..5) |_| {
        const current = launch.runTmux(alloc, &.{ tmux, "-L", session.socket, "display-message", "-p", "-t", pane, "#{session_id}\t#{session_name}" }) orelse return 0;
        var fields = std.mem.splitScalar(u8, std.mem.trimEnd(u8, current, "\r\n"), '\t');
        const id = fields.next() orelse return 0;
        const name = fields.next() orelse return 0;
        if (naming.alreadyNamed(name, base)) return 0;

        const listed = launch.runTmux(alloc, &.{ tmux, "-L", session.socket, "list-sessions", "-F", "#{session_name}" }) orelse return 0;
        var taken: std.ArrayList([]const u8) = .empty;
        var lines = std.mem.tokenizeAny(u8, listed, "\r\n");
        while (lines.next()) |line| taken.append(alloc, line) catch return 0;

        const want = naming.uniqueName(alloc, base, taken.items) catch return 0;
        if (launch.runTmux(alloc, &.{ tmux, "-L", session.socket, "rename-session", "-t", id, want }) != null) return 0;
    }
    return 0;
}

test {
    _ = @import("tmux/naming.zig");
}
