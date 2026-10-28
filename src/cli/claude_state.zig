const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("claude/protocol.zig");
const speak = @import("claude/speak.zig");
const zone = @import("claude/zone.zig");
const peers = @import("peers.zig");
const wire = @import("guard/wire.zig");

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
/// call is about to do, for Lostty Mobile's session list, and denies a
/// SendMessage to an agent outside the pane's zone. It never fails,
/// and prints only what the Mac app keeps for the pane (speak.Kind): the
/// queued texts on `busy`, the handoff's directive on `done` (a zone
/// move's note waits for the next prompt) and, after ListAgents, which
/// agents are in the pane's zone, and on `start` the zone's brief,
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
        // A prompt: give Claude what's queued for it, then say busy. A
        // zone's note comes with the zone's other agents as they are now.
        .busy => {
            const note = take(alloc, pane, .zone_say);
            const others = if (note != null) othersLine(alloc, pane, hookInput(alloc) orelse "{}") else null;
            speakTexts(alloc, "UserPromptSubmit", &.{ take(alloc, pane, .say), note, others });
        },
        // After a tool call: only speak the handoff's directive (Claude's
        // own calls, not a subagent's).
        .done => {
            const input = hookInput(alloc);
            if (input) |i| if (speak.isSubagent(alloc, i)) return 0;
            speakTexts(alloc, "PostToolUse", &.{ take(alloc, pane, .say), if (input) |i| zoneAgents(alloc, pane, i) else null });
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
            speakTexts(alloc, "SessionStart", &.{ handoff, zoneBrief(alloc, pane, input) });
            if (!cleared) return 0;
            state = if (handoff != null) .fresh else .cleared;
        },
        .idle, .resumed => if (hookInput(alloc)) |input| {
            state = protocol.refine(alloc, state, input) orelse return 0;
            detail.permission = state == .idle and protocol.isPermissionPrompt(alloc, input);
            if (state == .idle) detail.transcript = protocol.transcriptPath(alloc, input);
        },
        .tool => {
            const input = hookInput(alloc) orelse return 0;
            detail.denied = keepInside(alloc, pane, input);
            detail.action = protocol.action(alloc, input) orelse return 0;
        },
        else => {},
    }

    const tmux = std.posix.getenv("TMUX") != null;
    const seq = protocol.encodeSequence(alloc, state, detail, tmux) catch return 0;
    const tty = openTerminal(alloc) orelse return 0;
    defer tty.close();
    tty.writeAll(seq) catch {};
    return 0;
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

/// The brief of the pane's zone, left in place for the next session, and
/// the zone's other agents. A move's note still queued is dropped: the
/// brief is the zone as it is now.
fn zoneBrief(alloc: Allocator, pane: []const u8, input: []const u8) ?[]const u8 {
    if (paneFile(alloc, pane, .zone_say)) |path| std.fs.deleteFileAbsolute(path) catch {};
    const file = zoneFile(alloc, pane) orelse return null;
    const start = file.start orelse return null;
    const line = othersLine(alloc, pane, input) orelse return start;
    return std.fmt.allocPrint(alloc, "{s}\n{s}", .{ start, line }) catch start;
}

/// After ListAgents, which lists every session on the Mac: which of them
/// are in the pane's zone. Null for other tools or outside a zone.
fn zoneAgents(alloc: Allocator, pane: []const u8, input: []const u8) ?[]const u8 {
    if (!zone.isListAgents(alloc, input)) return null;
    const file = zoneFile(alloc, pane) orelse return null;
    const title = file.zone orelse return null;
    const members = file.members orelse return null;
    const list = zone.others(alloc, members, file.features, agents(alloc), zone.sessionId(alloc, input), std.posix.getenv("TMUX_PANE")) catch return null;
    return zone.listAgentsNote(alloc, title, list) catch null;
}

/// The line naming the pane's zone's other agents and their features;
/// null with none.
fn othersLine(alloc: Allocator, pane: []const u8, input: []const u8) ?[]const u8 {
    const file = zoneFile(alloc, pane) orelse return null;
    const members = file.members orelse return null;
    const list = zone.others(alloc, members, file.features, agents(alloc), zone.sessionId(alloc, input), std.posix.getenv("TMUX_PANE")) catch return null;
    return zone.othersLine(alloc, list) catch null;
}

/// A SendMessage to an agent outside the pane's zone: prints Claude
/// Code's deny and returns the target, for the app's notice. The owner's
/// Allow Once for that target lets one through.
fn keepInside(alloc: Allocator, pane: []const u8, input: []const u8) ?[]const u8 {
    const to = zone.sendTarget(alloc, input) orelse return null;
    const file = zoneFile(alloc, pane) orelse return null;
    const members = file.members orelse return null;
    if (zone.decide(to, members, agents(alloc), worktrees(alloc)) == .allow) return null;
    if (allowedOnce(alloc, pane, to)) return null;
    const reason = zone.denyReason(alloc, to, file.zone) catch return null;
    const out = wire.claudeJson(alloc, "deny", reason) catch return null;
    std.fs.File.stdout().writeAll(out) catch {};
    return if (to.len <= protocol.denied_max) to else null;
}

/// Takes the pane's Allow Once when it names `to`.
fn allowedOnce(alloc: Allocator, pane: []const u8, to: []const u8) bool {
    const path = paneFile(alloc, pane, .zone_allow) orelse return false;
    const text = std.fs.cwd().readFileAlloc(alloc, path, speak.text_max) catch return false;
    if (!zone.allows(text, to)) return false;
    const taken = speak.take(alloc, path) orelse return false;
    return zone.allows(taken, to);
}

pub fn zoneFile(alloc: Allocator, pane: []const u8) ?zone.File {
    const path = paneFile(alloc, pane, .zone) orelse return null;
    const json = std.fs.cwd().readFileAlloc(alloc, path, speak.text_max) catch return null;
    return zone.parse(alloc, json);
}

/// The worktrees of the repo Claude runs in; none outside a repo.
fn worktrees(alloc: Allocator) []const peers.Worktree {
    const cwd = std.process.getCwdAlloc(alloc) catch return &.{};
    const listed = peers.git(alloc, cwd, &.{ "worktree", "list", "--porcelain" }) orelse return &.{};
    return peers.parseWorktrees(alloc, listed) catch &.{};
}

/// Claude Code's running sessions, from its session files.
fn agents(alloc: Allocator) []const zone.Agent {
    const dir_path = sessionsDir(alloc) orelse return &.{};
    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return &.{};
    defer dir.close();
    var list: std.ArrayList(zone.Agent) = .empty;
    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json")) continue;
        const json = dir.readFileAlloc(alloc, entry.name, 1 << 16) catch continue;
        const agent = zone.parseAgent(alloc, json) orelse continue;
        list.append(alloc, agent) catch break;
    }
    return list.items;
}

fn sessionsDir(alloc: Allocator) ?[]const u8 {
    if (std.posix.getenv("CLAUDE_CONFIG_DIR")) |config| if (config.len > 0)
        return std.fs.path.join(alloc, &.{ config, "sessions" }) catch null;
    const home = std.posix.getenv("HOME") orelse return null;
    return std.fs.path.join(alloc, &.{ home, ".claude", "sessions" }) catch null;
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
