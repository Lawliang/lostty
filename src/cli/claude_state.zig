const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("claude/protocol.zig");
const sleep = @import("claude/sleep.zig");
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
/// SendMessage to an agent outside the pane's zone, or to one asleep,
/// which Lostty wakes to pass the message on. `subagent`
/// (SubagentStart) names the subagent and its transcript, and a SubagentStop
/// says `subagent_done` for it before anything else; `done` after a Bash
/// call that started a background shell says `shell`, and a prompt that is
/// Claude Code's notice of finished tasks says `shell_done` for each, for
/// the pane's strip of them. It never fails,
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
    const tmux = std.posix.getenv("TMUX") != null;
    // A subagent or background task finishing is said first, then whatever
    // its stop or prompt means.
    var stopped: ?[]u8 = null;
    switch (state) {
        // A prompt: give Claude what's queued for it, then say busy. A
        // zone's note comes with the zone's other agents as they are now,
        // and a conversation not yet told how to claim a feature is told.
        .busy => {
            const input = hookInput(alloc);
            const note = take(alloc, pane, .zone_say);
            const others = if (note != null) othersLine(alloc, pane, input) else null;
            speakTexts(alloc, "UserPromptSubmit", &.{ take(alloc, pane, .say), note, others, claimOnce(alloc, pane, input) });
            if (protocol.finishedTasks(alloc, input)) |ids| for (ids) |id| {
                const seq = protocol.encodeSequence(alloc, .shell_done, .{ .shell = .{ .id = id } }, tmux) catch continue;
                stopped = if (stopped) |first| std.mem.concat(alloc, u8, &.{ first, seq }) catch first else seq;
            };
        },
        // After a tool call: speak the handoff's directive (Claude's own
        // calls, not a subagent's), and name a background shell it started.
        .done => {
            const input = hookInput(alloc);
            if (speak.isSubagent(input)) return 0;
            speakTexts(alloc, "PostToolUse", &.{ take(alloc, pane, .say), zoneAgents(alloc, pane, input) });
            const shell = protocol.backgroundShell(alloc, input) orelse return 0;
            return say(alloc, protocol.encodeSequence(alloc, .shell, .{ .shell = shell }, tmux) catch null);
        },
        // A session starting without the zone's brief gets it. After
        // /clear the fresh window also gets the handoff, and says so, or
        // says it was cleared with none (the Mac disarms the pane). Any
        // other start says `start`: a sleeping pane's resume woke it.
        .start => {
            const input = hookInput(alloc);
            const source = speak.sessionSource(input) orelse return 0;
            const cleared = std.mem.eql(u8, source, "clear");
            if (zone.briefsAt(source)) {
                const handoff = if (cleared) take(alloc, pane, .start) else null;
                speakTexts(alloc, "SessionStart", &.{ handoff, zoneBrief(alloc, pane, input) });
                if (cleared) state = if (handoff != null) .fresh else .cleared;
            }
        },
        // A subagent starting, for the pane's list (Claude's own internal
        // agents aren't listed).
        .subagent => detail.agent = protocol.subagent(alloc, hookInput(alloc)) orelse return 0,
        .idle, .resumed => {
            const input = hookInput(alloc);
            if (state == .resumed) if (protocol.subagent(alloc, input)) |agent| {
                stopped = protocol.encodeSequence(alloc, .subagent_done, .{ .agent = agent }, tmux) catch null;
            };
            state = protocol.refine(state, input) orelse return say(alloc, stopped);
            detail.permission = state == .idle and protocol.isPermissionPrompt(input);
            if (state == .idle) detail.transcript = protocol.transcriptPath(input);
        },
        .tool => {
            const input = hookInput(alloc);
            detail.action = protocol.action(alloc, input) orelse return 0;
            holdMessage(alloc, pane, input, &detail);
        },
        else => {},
    }

    const seq = protocol.encodeSequence(alloc, state, detail, tmux) catch return say(alloc, stopped);
    const both = if (stopped) |first| std.mem.concat(alloc, u8, &.{ first, seq }) catch seq else seq;
    return say(alloc, both);
}

/// Writes `seq` to the pane's terminal; always 0, as a hook never fails.
fn say(alloc: Allocator, seq: ?[]const u8) u8 {
    const bytes = seq orelse return 0;
    const tty = openTerminal(alloc) orelse return 0;
    defer tty.close();
    writeWhole(tty, bytes) catch {};
    return 0;
}

/// Writes `bytes` to a pane's terminal in one piece. Hooks run side by
/// side (five subagents starting, their tool calls), and a write the
/// terminal can't take at once goes in chunks that another write would
/// split, losing both messages; holding the terminal's lock keeps each
/// whole. The lock goes with the file's close.
pub fn writeWhole(tty: std.fs.File, bytes: []const u8) !void {
    std.posix.flock(tty.handle, std.posix.LOCK.EX) catch {};
    try tty.writeAll(bytes);
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
fn zoneBrief(alloc: Allocator, pane: []const u8, input: std.json.Value) ?[]const u8 {
    if (paneFile(alloc, pane, .zone_say)) |path| std.fs.deleteFileAbsolute(path) catch {};
    const file = zoneFile(alloc, pane) orelse return null;
    const start = file.start orelse return null;
    // The brief holds how to claim a feature.
    if (file.claim != null) if (zone.sessionId(input)) |session| markTold(alloc, pane, session);
    const line = othersLine(alloc, pane, input) orelse return start;
    return std.fmt.allocPrint(alloc, "{s}\n{s}", .{ start, line }) catch start;
}

/// How to claim a feature, once a conversation: with its first prompt
/// when its start didn't say it, as a conversation that began before the
/// zone told it. Null when the zone has no claim or this one was told.
fn claimOnce(alloc: Allocator, pane: []const u8, input: std.json.Value) ?[]const u8 {
    const file = zoneFile(alloc, pane) orelse return null;
    const claim = file.claim orelse return null;
    const session = zone.sessionId(input) orelse return null;
    const path = paneFile(alloc, pane, .zone_told) orelse return null;
    if (std.fs.cwd().readFileAlloc(alloc, path, 256)) |told| {
        if (std.mem.eql(u8, told, session)) return null;
    } else |_| {}
    markTold(alloc, pane, session);
    return claim;
}

fn markTold(alloc: Allocator, pane: []const u8, session: []const u8) void {
    const path = paneFile(alloc, pane, .zone_told) orelse return;
    const file = std.fs.createFileAbsolute(path, .{}) catch return;
    defer file.close();
    file.writeAll(session) catch {};
}

/// After ListAgents, which lists every session on the Mac: which of them
/// are in the pane's zone. Null for other tools or outside a zone.
fn zoneAgents(alloc: Allocator, pane: []const u8, input: std.json.Value) ?[]const u8 {
    if (!zone.isListAgents(input)) return null;
    const file = zoneFile(alloc, pane) orelse return null;
    const title = file.zone orelse return null;
    const members = file.members orelse return null;
    const list = zone.others(alloc, members, file.features, agents(alloc), zone.sessionId(input), std.posix.getenv("TMUX_PANE")) catch return null;
    return zone.listAgentsNote(alloc, title, list) catch null;
}

/// The line naming the pane's zone's other agents and their features;
/// null with none.
fn othersLine(alloc: Allocator, pane: []const u8, input: std.json.Value) ?[]const u8 {
    const file = zoneFile(alloc, pane) orelse return null;
    const members = file.members orelse return null;
    const list = zone.others(alloc, members, file.features, agents(alloc), zone.sessionId(input), std.posix.getenv("TMUX_PANE")) catch return null;
    return zone.othersLine(alloc, list) catch null;
}

/// Denies a SendMessage that can't go as it is. One to an agent outside
/// the pane's zone names the target in `detail.denied`, for the app's
/// notice; the owner's Allow Once for that target lets one through. One
/// to a sleeping agent names it in `detail.wake`, with the message when it
/// fits, for the app to wake it and pass the message on.
fn holdMessage(alloc: Allocator, pane: []const u8, input: std.json.Value, detail: *protocol.Detail) void {
    const to = zone.sendTarget(input) orelse return;
    const running = agents(alloc);
    const sleepers = sleeping(alloc);
    if (zoneFile(alloc, pane)) |file| if (file.members) |members| {
        const all = sleep.withSleepers(alloc, running, sleepers) catch running;
        if (zone.decide(to, members, all, worktrees(alloc)) == .deny and !allowedOnce(alloc, pane, to)) {
            deny(alloc, zone.denyReason(alloc, to, file.zone) catch return);
            if (to.len <= protocol.denied_max) detail.denied = to;
            return;
        }
    };
    const asleep = sleep.find(to, sleepers, running) orelse return;
    detail.wake = .{
        .pane = asleep.pane,
        .from = sleep.sender(running, zone.sessionId(input)),
        .message = sleep.message(input),
    };
    if (!protocol.fits(alloc, .tool, detail.*)) detail.wake.?.message = null;
    if (!protocol.fits(alloc, .tool, detail.*)) {
        detail.wake = null;
        return;
    }
    deny(alloc, sleep.reason(alloc, to, detail.wake.?.message != null) catch return);
}

/// Prints Claude Code's deny of the tool call, with `reason`.
fn deny(alloc: Allocator, reason: []const u8) void {
    const out = wire.claudeJson(alloc, "deny", reason) catch return;
    std.fs.File.stdout().writeAll(out) catch {};
}

/// The agents Lostty put to sleep; none outside Lostty or with no list.
fn sleeping(alloc: Allocator) []const sleep.Sleeper {
    const home = std.posix.getenv("HOME") orelse return &.{};
    const path = std.fs.path.join(alloc, &.{ home, sleep.path }) catch return &.{};
    const json = std.fs.cwd().readFileAlloc(alloc, path, speak.text_max) catch return &.{};
    return sleep.parse(alloc, json);
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

/// The hook input Claude Code writes to stdin, read and parsed once. With
/// stdin a terminal (someone ran the command by hand), unreadable or not
/// JSON it is `.null`: a payload with nothing in it.
fn hookInput(alloc: Allocator) std.json.Value {
    const stdin = std.fs.File.stdin();
    if (std.posix.isatty(stdin.handle)) return .null;
    var buf: [4096]u8 = undefined;
    var reader = stdin.reader(&buf);
    const text = reader.interface.allocRemaining(alloc, .limited(4 << 20)) catch return .null;
    return protocol.parseInput(alloc, text);
}

/// `/dev/tty` when we have a controlling terminal; otherwise (Claude Code
/// runs hooks without one) the terminal of the nearest ancestor that has
/// one, which is `claude` in the pane, or the tmux pane it runs in.
pub fn openTerminal(alloc: Allocator) ?std.fs.File {
    if (std.fs.openFileAbsolute("/dev/tty", .{ .mode = .write_only })) |f| return f else |_| {}
    const Lookup = if (builtin.os.tag.isDarwin()) Kernel else Ps;
    const name = protocol.findTty(Lookup{ .alloc = alloc }, std.c.getppid(), 8) orelse return null;
    const path = std.fmt.allocPrint(alloc, "/dev/{s}", .{name}) catch return null;
    return std.fs.openFileAbsolute(path, .{ .mode = .write_only }) catch null;
}

/// What `ps -o ppid=,tty=` prints for a pid, read from the kernel the way
/// `ps` reads it, without starting `ps`: a hook runs on every tool call.
/// libproc's `proc_pidinfo` is no substitute: it refuses root's processes.
const Kernel = struct {
    alloc: Allocator,

    /// `struct kinfo_proc` (sys/sysctl.h) on 64-bit macOS: its size, and
    /// where `kp_eproc.e_ppid` and `kp_eproc.e_tdev` sit in it.
    const size = 648;
    const ppid_at = 560;
    const tdev_at = 572;
    /// `e_tdev` of a process with no terminal (NODEV).
    const no_device: i32 = -1;

    extern "c" fn devname_r(dev: i32, mode: std.c.mode_t, buf: [*]u8, len: c_int) ?[*:0]const u8;

    pub fn lookup(self: Kernel, pid: i32) ?protocol.ProcInfo {
        var info: [size]u8 align(8) = undefined;
        var len: usize = size;
        // CTL_KERN, KERN_PROC, KERN_PROC_PID. A pid that isn't running
        // succeeds with nothing written.
        const mib = [_]c_int{ 1, 14, 1, pid };
        if (std.c.sysctl(&mib, mib.len, &info, &len, null, 0) != 0 or len != size) return null;
        const ppid = std.mem.readInt(i32, info[ppid_at..][0..4], builtin.cpu.arch.endian());
        const tdev = std.mem.readInt(i32, info[tdev_at..][0..4], builtin.cpu.arch.endian());
        var buf: [64]u8 = undefined;
        const name = if (tdev == no_device) null else devname_r(tdev, std.c.S.IFCHR, &buf, buf.len);
        const tty = if (name) |n| self.alloc.dupe(u8, std.mem.span(n)) catch return null else null;
        return .{ .ppid = ppid, .tty = if (tty) |t| if (protocol.isTtyName(t)) t else null else null };
    }
};

/// The same from `ps` itself, where the kernel isn't macOS's.
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

test "claude state: the kernel names the parent and terminal ps names" {
    if (comptime !builtin.os.tag.isDarwin()) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const kernel: Kernel = .{ .alloc = a };
    const ps: Ps = .{ .alloc = a };

    // This process and each ancestor up to launchd, which root owns.
    var pid: i32 = std.c.getpid();
    var seen: usize = 0;
    while (pid >= 1) : (seen += 1) {
        const want = ps.lookup(pid).?;
        const got = kernel.lookup(pid).?;
        try std.testing.expectEqual(want.ppid, got.ppid);
        try std.testing.expectEqualDeep(want.tty, got.tty);
        pid = got.ppid;
    }
    try std.testing.expect(seen >= 2);

    // The walk a hook makes picks the same terminal either way.
    try std.testing.expectEqualDeep(
        protocol.findTty(ps, std.c.getpid(), 64),
        protocol.findTty(kernel, std.c.getpid(), 64),
    );
    try std.testing.expect(kernel.lookup(std.math.maxInt(i32)) == null);
}

test {
    _ = @import("claude/protocol.zig");
    _ = @import("claude/sleep.zig");
    _ = @import("claude/speak.zig");
    _ = @import("claude/zone.zig");
}
