const std = @import("std");
const Allocator = std.mem.Allocator;
const git = @import("peers.zig").git;

/// The config key Lostty sets on a branch it named for a new worktree
/// (`wt-3`): the commit the branch started from.
pub fn baseKey(alloc: Allocator, branch: []const u8) ![]const u8 {
    return std.fmt.allocPrint(alloc, "branch.{s}.lostty-base", .{branch});
}

/// `+ticket working "<feature>"` names the branch checked out at `dir`
/// after the feature, when Lostty named that branch and nothing has merged
/// it yet: the new name, or null when it stays. A name taken by another
/// branch gets `-2`, `-3`, and so on.
pub fn rename(alloc: Allocator, dir: []const u8, feature: []const u8) ?[]const u8 {
    const branch = git(alloc, dir, &.{ "symbolic-ref", "--quiet", "--short", "HEAD" }) orelse return null;
    const key = baseKey(alloc, branch) catch return null;
    const base = git(alloc, dir, &.{ "config", "--get", key }) orelse return null;
    if (merged(alloc, dir, branch, base)) return null;
    const name = slug(alloc, feature) orelse return null;
    var n: usize = 1;
    while (n < 100) : (n += 1) {
        const candidate = if (n == 1) name else std.fmt.allocPrint(alloc, "{s}-{d}", .{ name, n }) catch return null;
        if (std.mem.eql(u8, candidate, branch)) return null;
        const ref = std.fmt.allocPrint(alloc, "refs/heads/{s}", .{candidate}) catch return null;
        if (git(alloc, dir, &.{ "show-ref", "--verify", "--quiet", ref }) != null) continue;
        // git moves the branch's config, the base with it.
        _ = git(alloc, dir, &.{ "branch", "-m", branch, candidate }) orelse return null;
        return candidate;
    }
    return null;
}

/// Whether another local branch has a commit made on `branch` since `base`
/// (merges into it count, the commits they brought don't).
fn merged(alloc: Allocator, dir: []const u8, branch: []const u8, base: []const u8) bool {
    const not_base = std.fmt.allocPrint(alloc, "^{s}", .{base}) catch return true;
    const others = std.fmt.allocPrint(alloc, "--exclude={s}", .{branch}) catch return true;
    const own = git(alloc, dir, &.{ "rev-list", "--first-parent", branch, not_base }) orelse return true;
    const only_here = git(alloc, dir, &.{ "rev-list", branch, not_base, "--not", others, "--branches" }) orelse return true;
    var lines = std.mem.tokenizeScalar(u8, own, '\n');
    while (lines.next()) |commit| {
        if (std.mem.indexOf(u8, only_here, commit) == null) return true;
    }
    return false;
}

/// `feature` as a branch name: lowercase letters and digits, dashes
/// between words, at most 40 bytes. Null when no letter or digit is left.
pub fn slug(alloc: Allocator, feature: []const u8) ?[]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (feature) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            out.append(alloc, std.ascii.toLower(c)) catch return null;
        } else if (out.items.len > 0 and out.items[out.items.len - 1] != '-') {
            out.append(alloc, '-') catch return null;
        }
    }
    const name = std.mem.trimRight(u8, out.items[0..@min(out.items.len, 40)], "-");
    return if (name.len == 0) null else name;
}

const testing = std.testing;

test "ticket branch: a feature's slug" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try testing.expectEqualStrings("tickets-panel", slug(alloc, "Tickets panel").?);
    try testing.expectEqualStrings("canvas-the-button-opens-one", slug(alloc, "  canvas: the + button opens one!").?);
    try testing.expectEqualStrings("caf-menu", slug(alloc, "Café menu").?);
    try testing.expectEqual(@as(usize, 40), slug(alloc, "a" ** 50).?.len);
    try testing.expectEqualStrings("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", slug(alloc, "a" ** 39 ++ " b").?);
    try testing.expect(slug(alloc, "→ ·") == null);
}

fn run(alloc: Allocator, dir: []const u8, args: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(alloc, &.{ "/usr/bin/git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@t" });
    try argv.appendSlice(alloc, args);
    const result = try std.process.Child.run(.{ .allocator = alloc, .argv = argv.items });
    try testing.expect(result.term == .Exited and result.term.Exited == 0);
}

test "ticket branch: renamed until it's merged, never one Lostty didn't name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(alloc, ".");
    const repo = try std.fs.path.join(alloc, &.{ root, "repo" });
    const wt = try std.fs.path.join(alloc, &.{ root, "wt" });
    try run(alloc, root, &.{ "init", "-q", "-b", "main", "repo" });
    try run(alloc, repo, &.{ "commit", "-q", "--allow-empty", "-m", "start" });
    try run(alloc, repo, &.{ "branch", "taken" });

    // Not Lostty's: never renamed.
    try testing.expect(rename(alloc, repo, "Login") == null);

    try run(alloc, repo, &.{ "worktree", "add", "-q", "-b", "wt-1", wt });
    const base = git(alloc, wt, &.{ "rev-parse", "HEAD" }).?;
    try run(alloc, repo, &.{ "config", "branch.wt-1.lostty-base", base });
    try testing.expectEqualStrings("login", rename(alloc, wt, "Login").?);
    // The same feature again: it stays.
    try testing.expect(rename(alloc, wt, "login") == null);
    // Another branch has the name: the next free one.
    try testing.expectEqualStrings("taken-2", rename(alloc, wt, "Taken").?);
    try testing.expect(rename(alloc, wt, "Taken") == null);

    // main merged into it: still its own.
    try run(alloc, repo, &.{ "commit", "-q", "--allow-empty", "-m", "on main" });
    try run(alloc, wt, &.{ "commit", "-q", "--allow-empty", "-m", "work" });
    try run(alloc, wt, &.{ "merge", "-q", "--no-edit", "main" });
    try testing.expectEqualStrings("tickets", rename(alloc, wt, "Tickets").?);

    // Merged into main: its name stays.
    try run(alloc, repo, &.{ "merge", "-q", "--no-edit", "tickets" });
    try testing.expect(rename(alloc, wt, "Something else") == null);
    try testing.expectEqualStrings("tickets", git(alloc, wt, &.{ "branch", "--show-current" }).?);
}
