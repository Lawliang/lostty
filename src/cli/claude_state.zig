const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("claude/protocol.zig");
const speak = @import("claude/speak.zig");
const zone = @import("claude/zone.zig");

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
/// or background shells still working) or mean nothing should be sent
/// (protocol.refine), and marks Claude asking permission. An `idle` also names the conversation
/// file, for the Mac's turn observer. `tool` (PreToolUse) sends what the tool
/// call is about to do, for Lostty Mobile's session list. It never fails,
/// and prints only what the Mac app keeps for the pane (speak.Kind): the
/// queued texts on `busy` and `done`, and on `start` the zone's brief,
/// after the handoff when it follows /clear. Outside Lostty, without a
/// terminal, or with a bad argument it does nothing and exits 0, so a hook
/// can never break Claude.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const argv = std.process.argsAlloc(alloc) catch return 0;
    var args: std.ArrayList([]const u8) = .empty;
    for (argv) |arg| args.append(alloc, arg) catch return 0;
    var state = protocol.stateFromArgs(args.items) orelse return 0;
    const pane = std.posix.getenv(protocol.surface_env) orelse return 0;
    var detail: protocol.Detail = .{};
    switch (state) {
        // A prompt: give Claude what's queued for it, then say busy.
        .busy => speakQueued(alloc, pane, "UserPromptSubmit"),
        // After a tool call: only speak (Claude's own calls, not a subagent's).
        .done => {
            if (hookInput(alloc)) |input| if (speak.isSubagent(alloc, input)) return 0;
            speakQueued(alloc, pane, "PostToolUse");
            return 0;
        },
        // A session starting without the zone's brief gets it. After
        // /clear the fresh window also gets the handoff, and says so, or
        // says it was cleared with none (the Mac disarms the pane).
        .start => {
            const input = hookInput(alloc) orelse return 0;
            const source = speak.sessionSource(alloc, input) orelse return 0;
            if (!zone.briefsAt(source)) return 0;
            const cleared = std.mem.eql(u8, source, "clear");
            const handoff = if (cleared) take(alloc, pane, .start) else null;
            speakTexts(alloc, "SessionStart", &.{ handoff, zoneBrief(alloc, pane) });
            if (!cleared) return 0;
            state = if (handoff != null) .fresh else .cleared;
        },
        .idle, .resumed => if (hookInput(alloc)) |input| {
            state = protocol.refine(alloc, state, input) orelse return 0;
            detail.permission = state == .idle and protocol.isPermissionPrompt(alloc, input);
            if (state == .idle) detail.transcript = protocol.transcriptPath(alloc, input);
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

/// Prints the handoff's directive and any zone move's note, taken from
/// the queue, as one additionalContext for `event`.
fn speakQueued(alloc: Allocator, pane: []const u8, event: []const u8) void {
    speakTexts(alloc, event, &.{ take(alloc, pane, .say), take(alloc, pane, .zone_say) });
}

/// Prints `texts` as Claude Code's additionalContext for `event`, or
/// nothing when there are none.
fn speakTexts(alloc: Allocator, event: []const u8, texts: []const ?[]const u8) void {
    const text = (speak.join(alloc, texts) catch return) orelse return;
    const out = speak.output(alloc, event, text) catch return;
    std.fs.File.stdout().writeAll(out) catch {};
}

/// The pane's file of `kind`, or null when the pane id isn't one Lostty
/// sets.
fn paneFile(alloc: Allocator, pane: []const u8, kind: speak.Kind) ?[]const u8 {
    if (!speak.isPaneId(pane)) return null;
    const home = std.posix.getenv("HOME") orelse return null;
    return speak.queuedPath(alloc, home, pane, kind) catch null;
}

fn take(alloc: Allocator, pane: []const u8, kind: speak.Kind) ?[]const u8 {
    return speak.take(alloc, paneFile(alloc, pane, kind) orelse return null);
}

/// The brief of the pane's zone, left in place for the next session. A
/// move's note still queued is dropped: the brief is the zone as it is now.
fn zoneBrief(alloc: Allocator, pane: []const u8) ?[]const u8 {
    if (paneFile(alloc, pane, .zone_say)) |path| std.fs.deleteFileAbsolute(path) catch {};
    const path = paneFile(alloc, pane, .zone) orelse return null;
    const json = std.fs.cwd().readFileAlloc(alloc, path, speak.text_max) catch return null;
    return zone.start(alloc, json);
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
    _ = @import("claude/speak.zig");
    _ = @import("claude/zone.zig");
}
