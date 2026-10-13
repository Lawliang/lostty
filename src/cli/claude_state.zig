const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("claude/protocol.zig");

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

/// The `claude-state` command is run by Lostty's Claude Code hooks to tell
/// the pane it runs in whether Claude is working: `+claude-state busy`,
/// `idle`, `exit`, `agents` or `resumed`. For `idle` and `resumed` it reads
/// the hook input on stdin, which can turn a Stop into `agents` (subagents
/// still working) or mean nothing should be sent (protocol.refine), and
/// marks Claude asking permission. `tool` (PreToolUse) sends what the tool
/// call is about to do, for Lostty Mobile's session list. It
/// never fails and never prints: outside Lostty, without a terminal, or
/// with a bad argument it does nothing and exits 0, so a hook can never
/// break Claude.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const argv = std.process.argsAlloc(alloc) catch return 0;
    var args: std.ArrayList([]const u8) = .empty;
    for (argv) |arg| args.append(alloc, arg) catch return 0;
    var state = protocol.stateFromArgs(args.items) orelse return 0;
    if (std.posix.getenv(protocol.surface_env) == null) return 0;
    var detail: protocol.Detail = .{};
    switch (state) {
        .idle, .resumed => if (hookInput(alloc)) |input| {
            state = protocol.refine(alloc, state, input) orelse return 0;
            detail.permission = state == .idle and protocol.isPermissionPrompt(alloc, input);
        },
        .tool => detail.action = protocol.action(alloc, hookInput(alloc) orelse return 0) orelse return 0,
        else => {},
    }

    const tmux = std.posix.getenv("TMUX") != null;
    const seq = protocol.encodeSequence(alloc, state, detail, tmux) catch return 0;
    const tty = openTerminal(alloc) orelse return 0;
    defer tty.close();
    tty.writeAll(seq) catch {};
    return 0;
}

/// The hook input Claude Code writes to stdin, or null when stdin is a
/// terminal (someone ran the command by hand) or can't be read.
fn hookInput(alloc: Allocator) ?[]const u8 {
    const stdin = std.fs.File.stdin();
    if (std.posix.isatty(stdin.handle)) return null;
    var buf: [4096]u8 = undefined;
    var reader = stdin.reader(&buf);
    return reader.interface.allocRemaining(alloc, .limited(4 << 20)) catch null;
}

/// `/dev/tty` when we have a controlling terminal; otherwise (Claude Code
/// runs hooks without one) the terminal of the nearest ancestor that has
/// one, which is `claude` in the pane, or the tmux pane it runs in.
pub fn openTerminal(alloc: Allocator) ?std.fs.File {
    if (std.fs.openFileAbsolute("/dev/tty", .{ .mode = .write_only })) |f| return f else |_| {}
    const name = protocol.findTty(Ps{ .alloc = alloc }, std.c.getppid(), 8) orelse return null;
    const path = std.fmt.allocPrint(alloc, "/dev/{s}", .{name}) catch return null;
    return std.fs.openFileAbsolute(path, .{ .mode = .write_only }) catch null;
}

const Ps = struct {
    alloc: Allocator,

    pub fn lookup(self: Ps, pid: i32) ?protocol.ProcInfo {
        var buf: [16]u8 = undefined;
        const pid_str = std.fmt.bufPrint(&buf, "{d}", .{pid}) catch return null;
        const result = std.process.Child.run(.{
            .allocator = self.alloc,
            .argv = &.{ "/bin/ps", "-o", "ppid=,tty=", "-p", pid_str },
        }) catch return null;
        return protocol.parsePs(result.stdout);
    }
};

test {
    _ = @import("claude/protocol.zig");
}
