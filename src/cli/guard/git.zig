//! What the guard asks git: where the repo is, what a path would lose, and
//! whether a branch or commit exists elsewhere. Only called for commands
//! that delete, discard or merge, never for harmless ones.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Changes = struct {
    untracked: usize = 0,
    ignored: usize = 0,
    changed: usize = 0,

    pub fn total(self: Changes) usize {
        return self.untracked + self.ignored + self.changed;
    }

    pub fn describe(self: Changes, alloc: Allocator) Allocator.Error![]const u8 {
        var parts: std.ArrayList([]const u8) = .empty;
        if (self.untracked > 0) try parts.append(alloc, try std.fmt.allocPrint(alloc, "{d} untracked", .{self.untracked}));
        if (self.ignored > 0) try parts.append(alloc, try std.fmt.allocPrint(alloc, "{d} ignored", .{self.ignored}));
        if (self.changed > 0) try parts.append(alloc, try std.fmt.allocPrint(alloc, "{d} changed", .{self.changed}));
        const joined = try std.mem.join(alloc, ", ", parts.items);
        return std.fmt.allocPrint(alloc, "{s} files", .{joined});
    }
};

/// Counts `git status --porcelain=v1 -z` entries. A rename's second path
/// (the old name) follows its entry and isn't counted again.
pub fn parseStatus(out: []const u8) Changes {
    var c: Changes = .{};
    var it = std.mem.splitScalar(u8, out, 0);
    while (it.next()) |entry| {
        if (entry.len < 3) continue;
        const xy = entry[0..2];
        if (std.mem.eql(u8, xy, "??")) {
            c.untracked += 1;
        } else if (std.mem.eql(u8, xy, "!!")) {
            c.ignored += 1;
        } else {
            c.changed += 1;
            if (xy[0] == 'R' or xy[0] == 'C') _ = it.next();
        }
    }
    return c;
}

pub const Live = struct {
    alloc: Allocator,

    /// Runs `git -C cwd args`; stdout on exit 0, null otherwise.
    fn git(self: Live, cwd: []const u8, args: []const []const u8) ?[]const u8 {
        var argv: std.ArrayList([]const u8) = .empty;
        argv.appendSlice(self.alloc, &.{ "git", "-C", cwd }) catch return null;
        argv.appendSlice(self.alloc, args) catch return null;
        const r = std.process.Child.run(.{ .allocator = self.alloc, .argv = argv.items, .max_output_bytes = 4 << 20 }) catch return null;
        self.alloc.free(r.stderr);
        if (r.term != .Exited or r.term.Exited != 0) {
            self.alloc.free(r.stdout);
            return null;
        }
        return r.stdout;
    }

    pub fn repoRoot(self: Live, cwd: []const u8) ?[]const u8 {
        const out = self.git(cwd, &.{ "rev-parse", "--show-toplevel" }) orelse return null;
        return std.mem.trimRight(u8, out, "\n");
    }

    pub fn branch(self: Live, root: []const u8) ?[]const u8 {
        const out = self.git(root, &.{ "symbolic-ref", "--short", "-q", "HEAD" }) orelse return null;
        return std.mem.trimRight(u8, out, "\n");
    }

    pub fn changes(self: Live, root: []const u8, paths: []const []const u8) ?Changes {
        var args: std.ArrayList([]const u8) = .empty;
        args.appendSlice(self.alloc, &.{ "status", "--porcelain=v1", "-z", "--ignored=matching", "--untracked-files=all", "--" }) catch return null;
        args.appendSlice(self.alloc, paths) catch return null;
        const out = self.git(root, args.items) orelse return null;
        return parseStatus(out);
    }

    pub fn onlyHere(self: Live, root: []const u8, name: []const u8) bool {
        const ref = std.fmt.allocPrint(self.alloc, "refs/heads/{s}", .{name}) catch return true;
        const out = self.git(root, &.{ "for-each-ref", "--contains", ref, "--format=%(refname)", "refs/heads", "refs/remotes" }) orelse return true;
        var it = std.mem.tokenizeScalar(u8, out, '\n');
        while (it.next()) |r| if (!std.mem.eql(u8, r, ref)) return false;
        return true;
    }

    pub fn headPushed(self: Live, root: []const u8) bool {
        const out = self.git(root, &.{ "branch", "-r", "--contains", "HEAD" }) orelse return false;
        return std.mem.trim(u8, out, " \n").len > 0;
    }
};

test "guard git: parseStatus counts each kind" {
    const out = "?? a.txt\x00?? b/c.txt\x00!! zig-out/\x00 M src/x.zig\x00M  y\x00R  new\x00old\x00";
    const c = parseStatus(out);
    try std.testing.expectEqual(@as(usize, 2), c.untracked);
    try std.testing.expectEqual(@as(usize, 1), c.ignored);
    try std.testing.expectEqual(@as(usize, 3), c.changed);
}

test "guard git: describe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const d = try (Changes{ .untracked = 3, .changed = 1 }).describe(arena.allocator());
    try std.testing.expectEqualStrings("3 untracked, 1 changed files", d);
}

fn sh(alloc: Allocator, cwd: []const u8, argv: []const []const u8) !void {
    const r = try std.process.Child.run(.{ .allocator = alloc, .argv = argv, .cwd = cwd });
    if (r.term != .Exited or r.term.Exited != 0) return error.CommandFailed;
}

test "guard git: live probe in a temp repo" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(a, ".");
    try sh(a, root, &.{ "git", "init", "-q", "-b", "main" });
    try sh(a, root, &.{ "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init" });
    try tmp.dir.writeFile(.{ .sub_path = ".gitignore", .data = "out/\n" });
    try tmp.dir.writeFile(.{ .sub_path = "kept.txt", .data = "x" });
    try sh(a, root, &.{ "git", "add", ".gitignore", "kept.txt" });
    try sh(a, root, &.{ "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "files" });
    try tmp.dir.makePath("out");
    try tmp.dir.writeFile(.{ .sub_path = "out/build.o", .data = "x" });
    try tmp.dir.writeFile(.{ .sub_path = "new.txt", .data = "x" });

    const live: Live = .{ .alloc = a };
    try tmp.dir.makePath("sub");
    const sub = try std.fs.path.join(a, &.{ root, "sub" });
    try std.testing.expectEqualStrings(root, live.repoRoot(sub).?);
    try std.testing.expectEqualStrings("main", live.branch(root).?);
    try std.testing.expectEqual(@as(usize, 0), live.changes(root, &.{"kept.txt"}).?.total());
    try std.testing.expectEqual(@as(usize, 1), live.changes(root, &.{"new.txt"}).?.untracked);
    try std.testing.expectEqual(@as(usize, 1), live.changes(root, &.{"out"}).?.ignored);
    try std.testing.expectEqual(@as(usize, 0), live.changes(root, &.{"missing.txt"}).?.total());
    try std.testing.expect(!live.headPushed(root));

    try sh(a, root, &.{ "git", "branch", "side" });
    try std.testing.expect(!live.onlyHere(root, "side")); // main has the same tip
    try sh(a, root, &.{ "git", "checkout", "-q", "-b", "solo" });
    try sh(a, root, &.{ "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "only" });
    try sh(a, root, &.{ "git", "checkout", "-q", "main" });
    try std.testing.expect(live.onlyHere(root, "solo"));
    try std.testing.expect(live.repoRoot("/") == null);
}
