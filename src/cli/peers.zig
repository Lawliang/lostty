const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const session = @import("tmux/session.zig");
const launch = @import("tmux_launch.zig");
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

/// The `peers` command lists who else works on this repo, for an agent to
/// check with before it installs a build or merges: each worktree with a
/// Lostty terminal in it (its branch, uncommitted files, the commits this
/// worktree doesn't have, the files both change, and its tmux session as
/// Claude Code's ListAgents shows it, to message), any other worktree whose
/// uncommitted work touches the same files, and where the installed Lostty
/// was built (`macos/install.sh` records it). In a canvas zone it lists
/// only the zone's terminals. It only reads.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    const cwd = try std.process.getCwdAlloc(alloc);
    const root = git(alloc, cwd, &.{ "rev-parse", "--show-toplevel" }) orelse {
        var stderr_buf: [256]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
        try stderr_writer.interface.writeAll("peers: not in a git repository\n");
        try stderr_writer.interface.flush();
        return 1;
    };
    const worktrees = try parseWorktrees(alloc, git(alloc, root, &.{ "worktree", "list", "--porcelain" }) orelse "");
    const sessions = try inZone(alloc, try listSessions(alloc), zoneMembers(alloc));
    const here = owner(worktrees, root) orelse return 1;
    const me = std.posix.getenv("TMUX_PANE");
    const my_uncommitted = try uncommitted(alloc, root);

    try out.print("You: {s} ({s}), {d} files uncommitted\n", .{
        std.fs.path.basename(root), try describeHead(alloc, worktrees[here]), my_uncommitted.len,
    });

    var shown: usize = 0;
    for (worktrees, 0..) |wt, i| {
        var terminals: std.ArrayList(Session) = .empty;
        for (sessions) |s| {
            if (me != null and std.mem.endsWith(u8, s.location, me.?)) continue;
            if (owner(worktrees, s.path) == i) try terminals.append(alloc, s);
        }
        const theirs_uncommitted = if (i == here) &.{} else try uncommitted(alloc, wt.path);
        // What a merge or a build of both would bring together: each
        // side's changes the other doesn't have, committed or not.
        if (terminals.items.len == 0) {
            // No one's there: only its uncommitted work can be lost.
            if (theirs_uncommitted.len == 0) continue;
            const mine = try join(alloc, try onlyIn(alloc, root, "HEAD", wt.head), my_uncommitted);
            const same = try overlap(alloc, mine, theirs_uncommitted);
            if (same.len == 0) continue;
            try out.print("\n{s} ({s}), no terminal, {d} files uncommitted\n", .{
                std.fs.path.basename(wt.path), try describeHead(alloc, wt), theirs_uncommitted.len,
            });
            try printFiles(out, "uncommitted there, changed by you", same);
            shown += 1;
            continue;
        }
        shown += 1;
        if (i == here) {
            try out.print("\nAlso in this worktree:\n", .{});
            for (terminals.items) |t| try printTerminal(out, t);
            continue;
        }
        const ahead = git(alloc, root, &.{ "rev-list", "--count", try std.fmt.allocPrint(alloc, "HEAD..{s}", .{wt.head}) }) orelse "?";
        try out.print("\n{s} ({s}), {d} files uncommitted, {s} commits you don't have\n", .{
            std.fs.path.basename(wt.path), try describeHead(alloc, wt), theirs_uncommitted.len, ahead,
        });
        for (terminals.items) |t| try printTerminal(out, t);
        const mine = try join(alloc, try onlyIn(alloc, root, "HEAD", wt.head), my_uncommitted);
        const theirs = try join(alloc, try onlyIn(alloc, root, wt.head, "HEAD"), theirs_uncommitted);
        try printFiles(out, "same files as yours", try overlap(alloc, mine, theirs));
    }
    if (shown == 0) try out.print("\nNo other terminals in this repo.\n", .{});

    try printInstalled(alloc, out, root);
    return 0;
}

/// One worktree from `git worktree list --porcelain`.
pub const Worktree = struct {
    path: []const u8,
    head: []const u8,
    /// Null when detached.
    branch: ?[]const u8 = null,
};

/// The worktrees still on disk: one block per worktree, blank-line
/// separated; prunable ones (their folder is gone) are left out.
pub fn parseWorktrees(alloc: Allocator, porcelain: []const u8) ![]Worktree {
    var list: std.ArrayList(Worktree) = .empty;
    var blocks = std.mem.splitSequence(u8, porcelain, "\n\n");
    while (blocks.next()) |block| {
        var wt: Worktree = .{ .path = "", .head = "" };
        var prunable = false;
        var lines = std.mem.tokenizeScalar(u8, block, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "worktree ")) wt.path = line["worktree ".len..];
            if (std.mem.startsWith(u8, line, "HEAD ")) wt.head = line["HEAD ".len..];
            if (std.mem.startsWith(u8, line, "branch refs/heads/")) wt.branch = line["branch refs/heads/".len..];
            if (std.mem.startsWith(u8, line, "prunable")) prunable = true;
        }
        if (wt.path.len > 0 and !prunable) try list.append(alloc, wt);
    }
    return list.items;
}

/// A session on Lostty's tmux: its name, where it is as ListAgents shows
/// it (`name:@window.%pane`), what its Claude is doing (`@lostty_claude`:
/// working, waiting, or empty) and its active pane's folder.
pub const Session = struct {
    location: []const u8,
    claude: []const u8,
    path: []const u8,
};

pub const session_format = "#{session_name}:#{window_id}.#{pane_id}\t#{@lostty_claude}\t#{pane_current_path}";

pub fn parseSessions(alloc: Allocator, listed: []const u8) ![]Session {
    var list: std.ArrayList(Session) = .empty;
    var lines = std.mem.tokenizeAny(u8, listed, "\r\n");
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '\t');
        const location = fields.next() orelse continue;
        const claude = fields.next() orelse continue;
        const path = fields.next() orelse continue;
        try list.append(alloc, .{ .location = location, .claude = claude, .path = path });
    }
    return list.items;
}

fn listSessions(alloc: Allocator) ![]Session {
    const tmux = session.findTmux(alloc, std.posix.getenv("PATH"), launch.isExecutable) orelse return &.{};
    const listed = launch.runTmux(alloc, &.{ tmux, "-L", session.socket, "list-sessions", "-F", session_format }) orelse return &.{};
    return parseSessions(alloc, listed);
}

/// The sessions in `members`, the tmux sessions of the zone this pane is
/// in; all of them when it's in none (null).
pub fn inZone(alloc: Allocator, sessions: []const Session, members: ?[]const []const u8) ![]const Session {
    const names = members orelse return sessions;
    var kept: std.ArrayList(Session) = .empty;
    for (sessions) |s| {
        const name = s.location[0 .. std.mem.indexOfScalar(u8, s.location, ':') orelse s.location.len];
        for (names) |m| if (std.mem.eql(u8, m, name)) {
            try kept.append(alloc, s);
            break;
        };
    }
    return kept.items;
}

/// The members in this pane's zone file (LOSTTY_SURFACE); null without one.
fn zoneMembers(alloc: Allocator) ?[]const []const u8 {
    const pane = std.posix.getenv(protocol.surface_env) orelse return null;
    if (!speak.isPaneId(pane)) return null;
    const home = std.posix.getenv("HOME") orelse return null;
    const path = speak.queuedPath(alloc, home, pane, .zone) catch return null;
    const json = std.fs.cwd().readFileAlloc(alloc, path, speak.text_max) catch return null;
    return (zone.parse(alloc, json) orelse return null).members;
}

/// The worktree `path` is in: the deepest one holding it, since worktrees
/// can sit inside the main checkout.
pub fn owner(worktrees: []const Worktree, path: []const u8) ?usize {
    var best: ?usize = null;
    for (worktrees, 0..) |wt, i| {
        const inside = std.mem.eql(u8, path, wt.path) or
            (std.mem.startsWith(u8, path, wt.path) and path.len > wt.path.len and path[wt.path.len] == '/');
        if (inside and (best == null or wt.path.len > worktrees[best.?].path.len)) best = i;
    }
    return best;
}

/// The files in both lists, in `a`'s order.
pub fn overlap(alloc: Allocator, a: []const []const u8, b: []const []const u8) ![]const []const u8 {
    var set: std.StringHashMapUnmanaged(void) = .empty;
    for (b) |file| try set.put(alloc, file, {});
    var both: std.ArrayList([]const u8) = .empty;
    for (a) |file| if (set.contains(file)) try both.append(alloc, file);
    return both.items;
}

fn join(alloc: Allocator, a: []const []const u8, b: []const []const u8) ![]const []const u8 {
    var set: std.StringHashMapUnmanaged(void) = .empty;
    var all: std.ArrayList([]const u8) = .empty;
    for ([_][]const []const u8{ a, b }) |files| for (files) |file| {
        if (set.contains(file)) continue;
        try set.put(alloc, file, {});
        try all.append(alloc, file);
    };
    return all.items;
}

/// Changed, staged or new files in the worktree at `path`.
fn uncommitted(alloc: Allocator, path: []const u8) ![]const []const u8 {
    const tracked = try fileList(alloc, git(alloc, path, &.{ "diff", "--name-only", "HEAD" }) orelse "");
    const untracked = try fileList(alloc, git(alloc, path, &.{ "ls-files", "--others", "--exclude-standard" }) orelse "");
    return join(alloc, tracked, untracked);
}

/// The files changed by commits `head` has and `other` doesn't. Not a diff
/// from their merge base: once two branches have each merged the other
/// (or main), they have several, and a diff from any one counts what both
/// already share.
fn onlyIn(alloc: Allocator, root: []const u8, head: []const u8, other: []const u8) ![]const []const u8 {
    const range = try std.fmt.allocPrint(alloc, "{s}..{s}", .{ other, head });
    const listed = git(alloc, root, &.{ "log", "--format=", "--name-only", range }) orelse "";
    return join(alloc, try fileList(alloc, listed), &.{});
}

fn fileList(alloc: Allocator, text: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, "\r\n");
    while (it.next()) |line| try list.append(alloc, line);
    return list.items;
}

fn describeHead(alloc: Allocator, wt: Worktree) ![]const u8 {
    if (wt.branch) |branch| return std.fmt.allocPrint(alloc, "branch {s}", .{branch});
    return std.fmt.allocPrint(alloc, "detached at {s}", .{wt.head[0..@min(9, wt.head.len)]});
}

fn printTerminal(out: *std.Io.Writer, t: Session) !void {
    const doing = if (t.claude.len > 0) t.claude else "not working";
    try out.print("  terminal: tmux {s} (Claude {s})\n", .{ t.location, doing });
}

/// Up to eight files by name, then how many more.
fn printFiles(out: *std.Io.Writer, label: []const u8, files: []const []const u8) !void {
    if (files.len == 0) return out.print("  {s}: none\n", .{label});
    try out.print("  {s}:", .{label});
    for (files[0..@min(8, files.len)]) |file| try out.print(" {s}", .{std.fs.path.basename(file)});
    if (files.len > 8) try out.print(" and {d} more", .{files.len - 8});
    try out.print("\n", .{});
}

/// `macos/install.sh`'s record of the installed build: `key=value` lines.
pub const Installed = struct {
    worktree: []const u8 = "",
    branch: []const u8 = "",
    commit: []const u8 = "",
    uncommitted: []const u8 = "0",
    channel: []const u8 = "",
    at: []const u8 = "",
};

pub fn parseInstalled(text: []const u8) Installed {
    var record: Installed = .{};
    var it = std.mem.tokenizeAny(u8, text, "\r\n");
    while (it.next()) |line| {
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = line[0..eq];
        const value = line[eq + 1 ..];
        inline for (std.meta.fields(Installed)) |field| {
            if (std.mem.eql(u8, key, field.name)) @field(record, field.name) = value;
        }
    }
    return record;
}

/// Where install.sh keeps its record: Lostty's config folder.
pub fn installedPath(alloc: Allocator) ![]const u8 {
    if (std.posix.getenv("XDG_CONFIG_HOME")) |config| {
        if (config.len > 0) return std.fs.path.join(alloc, &.{ config, "lostty", "installed-build" });
    }
    const home = std.posix.getenv("HOME") orelse return error.NoHome;
    return std.fs.path.join(alloc, &.{ home, ".config", "lostty", "installed-build" });
}

fn printInstalled(alloc: Allocator, out: *std.Io.Writer, root: []const u8) !void {
    const path = installedPath(alloc) catch return;
    const text = std.fs.cwd().readFileAlloc(alloc, path, 1 << 16) catch {
        return out.print("\nInstalled: not recorded (built before install.sh recorded its builds)\n", .{});
    };
    const record = parseInstalled(text);
    const uncommitted_note = if (std.mem.eql(u8, record.uncommitted, "0"))
        ""
    else
        try std.fmt.allocPrint(alloc, ", with {s} files uncommitted", .{record.uncommitted});
    const name = if (std.mem.eql(u8, record.channel, "beta")) "Lostty Beta" else "Lostty";
    const branch = if (record.branch.len > 0) record.branch else "detached";
    try out.print("\nInstalled: {s}, built in {s} ({s} at {s}{s}) on {s}\n", .{
        name,             std.fs.path.basename(record.worktree), branch, record.commit[0..@min(9, record.commit.len)],
        uncommitted_note, record.at,
    });
    if (std.mem.eql(u8, record.worktree, root)) return;
    const has_commit = record.commit.len > 0 and
        git(alloc, root, &.{ "merge-base", "--is-ancestor", record.commit, "HEAD" }) != null;
    if (!has_commit or !std.mem.eql(u8, record.uncommitted, "0")) {
        try out.print("  An install from here would drop work it has that this worktree doesn't.\n", .{});
    }
}

/// `git -C dir args…`'s output, trimmed, when it succeeds.
fn git(alloc: Allocator, dir: []const u8, args: []const []const u8) ?[]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    argv.appendSlice(alloc, &.{ "/usr/bin/git", "-C", dir }) catch return null;
    argv.appendSlice(alloc, args) catch return null;
    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = argv.items,
        .max_output_bytes = 16 << 20,
    }) catch return null;
    switch (result.term) {
        .Exited => |code| if (code != 0) return null,
        else => return null,
    }
    return std.mem.trim(u8, result.stdout, " \r\n");
}

const testing = std.testing;

test "worktrees: branches, detached, and prunable left out" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const listed =
        \\worktree /repo
        \\HEAD aaa
        \\branch refs/heads/main
        \\
        \\worktree /repo/.claude/worktrees/a
        \\HEAD bbb
        \\detached
        \\
        \\worktree /tmp/gone
        \\HEAD ccc
        \\branch refs/heads/old
        \\prunable gitdir file points to non-existent location
        \\
    ;
    const wts = try parseWorktrees(arena.allocator(), listed);
    try testing.expectEqual(@as(usize, 2), wts.len);
    try testing.expectEqualStrings("main", wts[0].branch.?);
    try testing.expectEqualStrings("bbb", wts[1].head);
    try testing.expect(wts[1].branch == null);
}

test "a folder belongs to the deepest worktree holding it" {
    const wts = [_]Worktree{
        .{ .path = "/repo", .head = "" },
        .{ .path = "/repo/.claude/worktrees/a", .head = "" },
        .{ .path = "/repo/.claude/worktrees/ab", .head = "" },
    };
    try testing.expectEqual(@as(?usize, 0), owner(&wts, "/repo/src"));
    try testing.expectEqual(@as(?usize, 1), owner(&wts, "/repo/.claude/worktrees/a"));
    try testing.expectEqual(@as(?usize, 2), owner(&wts, "/repo/.claude/worktrees/ab/macos"));
    try testing.expectEqual(@as(?usize, null), owner(&wts, "/repository"));
}

test "sessions: location, Claude and folder" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const listed = "more:@6.%6\tworking\t/repo/a\nlostty:@2.%2\t\t/repo\n";
    const sessions = try parseSessions(arena.allocator(), listed);
    try testing.expectEqual(@as(usize, 2), sessions.len);
    try testing.expectEqualStrings("more:@6.%6", sessions[0].location);
    try testing.expectEqualStrings("working", sessions[0].claude);
    try testing.expectEqualStrings("", sessions[1].claude);
    try testing.expectEqualStrings("/repo", sessions[1].path);
}

test "sessions: a zone keeps only its members" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const listed = try parseSessions(a, "tb-1:@6.%6\tworking\t/t\nlostty:@2.%2\t\t/repo\ntb-10:@3.%3\t\t/t\n");
    const kept = try inZone(a, listed, &.{ "tb-1", "tb-2" });
    try testing.expectEqual(@as(usize, 1), kept.len);
    try testing.expectEqualStrings("tb-1:@6.%6", kept[0].location);
    try testing.expectEqual(@as(usize, 3), (try inZone(a, listed, null)).len);
    try testing.expectEqual(@as(usize, 0), (try inZone(a, listed, &.{})).len);
}

test "files both sides change" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const both = try overlap(arena.allocator(), &.{ "a.swift", "b.swift", "c.swift" }, &.{ "c.swift", "a.swift" });
    try testing.expectEqual(@as(usize, 2), both.len);
    try testing.expectEqualStrings("a.swift", both[0]);
    try testing.expectEqualStrings("c.swift", both[1]);
}

test "install.sh's record" {
    const record = parseInstalled(
        \\worktree=/repo/.claude/worktrees/test-both
        \\branch=
        \\commit=301602ab7
        \\uncommitted=9
        \\channel=beta
        \\at=2026-10-23 21:51
    );
    try testing.expectEqualStrings("/repo/.claude/worktrees/test-both", record.worktree);
    try testing.expectEqualStrings("", record.branch);
    try testing.expectEqualStrings("9", record.uncommitted);
    try testing.expectEqualStrings("2026-10-23 21:51", record.at);
}
