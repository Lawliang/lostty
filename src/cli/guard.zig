const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const decide = @import("guard/decide.zig");
const wire = @import("guard/wire.zig");
const config = @import("guard/config.zig");
const git = @import("guard/git.zig");
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

/// The `guard` command is run by Lostty's PreToolUse hooks for Claude Code
/// (`+guard --agent=claude`) and Codex (`+guard --agent=codex`). It reads
/// the hook input on stdin and lets a harmless tool call through silently.
/// A critical one (deleting what git can't restore, throwing work away,
/// leaving the Mac, merging into a protected branch, changing the
/// guardrails, writing outside the project) goes through only if you
/// approved exactly that call in Lostty; otherwise it's blocked and Lostty
/// shows you the request. If Lostty can't be reached, Claude asks you
/// itself and Codex stays blocked. Outside Lostty it does nothing.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const pane = std.posix.getenv("LOSTTY_SURFACE") orelse return 0;
    const argv = std.process.argsAlloc(alloc) catch return failClosed(alloc, .codex);
    const agent = agentFromArgs(argv);
    return runFor(alloc, pane, agent) catch failClosed(alloc, agent);
}

/// Only an exact `--agent=claude` gets Claude's JSON answer. Anything else
/// (a missing or mistyped flag) gets the stderr and exit 2 form, which
/// blocks in both agents: a wrong guess must never let a call through.
fn agentFromArgs(argv: []const []const u8) wire.Agent {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--agent=claude")) return .claude;
    }
    return .codex;
}

test "guard args: only an exact --agent=claude is Claude" {
    try std.testing.expectEqual(wire.Agent.claude, agentFromArgs(&.{ "lostty", "+guard", "--agent=claude" }));
    try std.testing.expectEqual(wire.Agent.codex, agentFromArgs(&.{ "lostty", "+guard", "--agent=codex" }));
    try std.testing.expectEqual(wire.Agent.codex, agentFromArgs(&.{ "lostty", "+guard", "--agent", "codex" }));
    try std.testing.expectEqual(wire.Agent.codex, agentFromArgs(&.{ "lostty", "+guard", "--agent", "claude" }));
    try std.testing.expectEqual(wire.Agent.codex, agentFromArgs(&.{ "lostty", "+guard", "--agent=Codex" }));
    try std.testing.expectEqual(wire.Agent.codex, agentFromArgs(&.{ "lostty", "+guard", "--agent=" }));
    try std.testing.expectEqual(wire.Agent.codex, agentFromArgs(&.{ "lostty", "+guard" }));
}

fn runFor(alloc: Allocator, pane: []const u8, agent: wire.Agent) !u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    const cfg = config.Config.load(alloc, home);
    // Coordination off (no `"enabled": true` in guard.json): Lostty doesn't
    // install this hook, and one left from before lets every call through.
    if (!cfg.enabled()) return 0;
    // As claude_state.hookInput reads it.
    var buf: [4096]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&buf);
    const input = try reader.interface.allocRemaining(alloc, .limited(8 << 20));
    const env: decide.Env = .{ .home = home, .tmpdir = std.posix.getenv("TMPDIR"), .config = cfg, .zone_folder = zoneFolder(alloc, home, pane) };
    const verdict = try decide.decide(alloc, env, git.Live{ .alloc = alloc }, input);
    const c = switch (verdict) {
        .harmless => return 0,
        .critical => |c| c,
    };
    const request = try wire.encodeRequest(alloc, pane, agent, c);
    const out = if (wire.ask(alloc, try wire.socketPath(alloc, std.posix.getenv(wire.socket_env), home), request, 3000)) |reply| switch (reply) {
        .allow => return 0,
        .deny => |id| try wire.outputDeny(alloc, agent, id, c),
    } else try wire.outputUnreachable(alloc, agent, c);
    return emit(out);
}

/// The folder in the pane's zone file, resolved; null without a zone
/// file, a folder, or a directory there.
fn zoneFolder(alloc: Allocator, home: []const u8, pane: []const u8) ?[]const u8 {
    if (!speak.isPaneId(pane)) return null;
    const path = speak.queuedPath(alloc, home, pane, .zone) catch return null;
    const json = std.fs.cwd().readFileAlloc(alloc, path, speak.text_max) catch return null;
    const folder = (zone.parse(alloc, json) orelse return null).folder orelse return null;
    if (!std.fs.path.isAbsolute(folder)) return null;
    var dir = std.fs.openDirAbsolute(folder, .{}) catch return null;
    defer dir.close();
    return dir.realpathAlloc(alloc, ".") catch null;
}

test "guard zone: the folder in the pane's zone file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(speak.panes_dir);
    try tmp.dir.makePath("t/onboarding");
    try tmp.dir.writeFile(.{ .sub_path = "t/notes.md", .data = "" });
    const home = try tmp.dir.realpathAlloc(a, ".");
    const pane = "0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6";
    const zone_path = try speak.queuedPath(a, home, pane, .zone);
    const domain = try std.fs.path.join(a, &.{ home, "t/onboarding" });

    try std.testing.expect(zoneFolder(a, home, pane) == null);
    for ([_][]const u8{
        "{\"zone\":\"Textberry\",\"folder\":null}",
        "{\"folder\":\"t/onboarding\"}",
        try std.fmt.allocPrint(a, "{{\"folder\":\"{s}/t/notes.md\"}}", .{home}),
        try std.fmt.allocPrint(a, "{{\"folder\":\"{s}/t/gone\"}}", .{home}),
    }) |json| {
        try std.fs.cwd().writeFile(.{ .sub_path = zone_path, .data = json });
        try std.testing.expect(zoneFolder(a, home, pane) == null);
    }
    try std.fs.cwd().writeFile(.{ .sub_path = zone_path, .data = try std.fmt.allocPrint(a, "{{\"folder\":\"{s}/\"}}", .{domain}) });
    try std.testing.expectEqualStrings(domain, zoneFolder(a, home, pane).?);
    try std.testing.expect(zoneFolder(a, home, "../x") == null);
}

fn emit(out: wire.Output) u8 {
    if (out.stdout.len > 0) std.fs.File.stdout().writeAll(out.stdout) catch {};
    if (out.stderr.len > 0) std.fs.File.stderr().writeAll(out.stderr) catch {};
    return out.exit;
}

/// Something failed before a decision: never let the call through silently.
fn failClosed(alloc: Allocator, agent: wire.Agent) u8 {
    const c: decide.Critical = .{ .group = .unreadable, .why = "Lostty's guard hit an error checking this call", .tool = "?", .input = "", .cwd = "/" };
    const out = wire.outputUnreachable(alloc, agent, c) catch return 2;
    return emit(out);
}
