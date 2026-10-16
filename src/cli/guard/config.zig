const std = @import("std");
const Allocator = std.mem.Allocator;

// The guard's settings: `~/.config/lostty/guard.json` over built-in
// defaults. The file sits under ~/.config/lostty, which the guard itself
// protects, so an agent can't loosen it. A missing or broken file means
// the defaults: the guard never turns itself off over a typo.
//
//   { "push": "all" | "protected",
//     "protectedBranches": ["release"],
//     "commands": ["deploy.sh"],
//     "deletable": ["vendor"],
//     "repos": { "/abs/path": { same keys } } }
//
// Lists add to the defaults (and a repo's to the global ones); `push`
// overrides.

pub const Push = enum { all, protected };

pub const default_protected = [_][]const u8{ "main", "master" };
pub const default_commands = [_][]const u8{"ship-phone.sh"};
pub const default_deletable = [_][]const u8{ "node_modules", ".zig-cache", "zig-cache", "zig-out", ".build", "DerivedData", "__pycache__" };

pub const Effective = struct {
    push: Push,
    protected_branches: []const []const u8,
    commands: []const []const u8,
    deletable: []const []const u8,
};

pub const Config = struct {
    /// The parsed file, or null for defaults only.
    root: ?std.json.Value,

    pub fn load(alloc: Allocator, home: []const u8) Config {
        const path = std.fs.path.join(alloc, &.{ home, ".config", "lostty", "guard.json" }) catch return .{ .root = null };
        const text = std.fs.cwd().readFileAlloc(alloc, path, 1 << 20) catch return .{ .root = null };
        return parse(alloc, text);
    }

    pub fn parse(alloc: Allocator, text: []const u8) Config {
        const v = std.json.parseFromSliceLeaky(std.json.Value, alloc, text, .{}) catch return .{ .root = null };
        return .{ .root = if (v == .object) v else null };
    }

    pub fn forRepo(self: Config, alloc: Allocator, repo: ?[]const u8) Allocator.Error!Effective {
        var push: Push = .all;
        var protected: std.ArrayList([]const u8) = .empty;
        var commands: std.ArrayList([]const u8) = .empty;
        var deletable: std.ArrayList([]const u8) = .empty;
        try protected.appendSlice(alloc, &default_protected);
        try commands.appendSlice(alloc, &default_commands);
        try deletable.appendSlice(alloc, &default_deletable);
        const layers = [_]?std.json.Value{ self.root, try self.repoLayer(alloc, repo) };
        for (layers) |layer| {
            const obj = layer orelse continue;
            if (obj != .object) continue;
            if (obj.object.get("push")) |p| if (p == .string) {
                if (std.mem.eql(u8, p.string, "protected")) push = .protected;
                if (std.mem.eql(u8, p.string, "all")) push = .all;
            };
            try addStrings(alloc, &protected, obj.object.get("protectedBranches"));
            try addStrings(alloc, &commands, obj.object.get("commands"));
            try addStrings(alloc, &deletable, obj.object.get("deletable"));
        }
        return .{
            .push = push,
            .protected_branches = try protected.toOwnedSlice(alloc),
            .commands = try commands.toOwnedSlice(alloc),
            .deletable = try deletable.toOwnedSlice(alloc),
        };
    }

    /// The `repos` entry for `repo`. Keys and the repo are compared after
    /// dropping trailing slashes and resolving symlinks where they exist
    /// (`/tmp/x` is `/private/tmp/x`), so a repo's settings aren't lost to
    /// how its path was written.
    fn repoLayer(self: Config, alloc: Allocator, repo: ?[]const u8) Allocator.Error!?std.json.Value {
        const root = self.root orelse return null;
        const r = repo orelse return null;
        const repos = root.object.get("repos") orelse return null;
        if (repos != .object) return null;
        if (repos.object.get(r)) |exact| return exact;
        const want = try normalize(alloc, r);
        var it = repos.object.iterator();
        while (it.next()) |e| {
            if (std.mem.eql(u8, try normalize(alloc, e.key_ptr.*), want)) return e.value_ptr.*;
        }
        return null;
    }
};

/// `path` without trailing slashes, symlinks resolved when it exists.
pub fn normalize(alloc: Allocator, path: []const u8) Allocator.Error![]const u8 {
    var p = path;
    while (p.len > 1 and p[p.len - 1] == '/') p = p[0 .. p.len - 1];
    if (p.len == 0 or p[0] != '/') return p;
    return std.fs.cwd().realpathAlloc(alloc, p) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => p,
    };
}

fn addStrings(alloc: Allocator, list: *std.ArrayList([]const u8), v: ?std.json.Value) Allocator.Error!void {
    const arr = v orelse return;
    if (arr != .array) return;
    for (arr.array.items) |item| if (item == .string) try list.append(alloc, item.string);
}

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, s)) return true;
    return false;
}

test "guard config: defaults" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = try Config.parse(a, "").forRepo(a, "/r");
    try std.testing.expectEqual(Push.all, e.push);
    try std.testing.expect(contains(e.protected_branches, "main"));
    try std.testing.expect(contains(e.protected_branches, "master"));
    try std.testing.expect(contains(e.commands, "ship-phone.sh"));
    try std.testing.expect(contains(e.deletable, "node_modules"));
    try std.testing.expect(!contains(e.deletable, "build"));
}

test "guard config: a repo adds to the global lists and can relax push" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cfg = Config.parse(a,
        \\{"protectedBranches":["release"],"commands":["deploy.sh"],
        \\ "repos":{"/r":{"push":"protected","protectedBranches":["skins"],"deletable":["build"]}}}
    );
    const r = try cfg.forRepo(a, "/r");
    try std.testing.expectEqual(Push.protected, r.push);
    try std.testing.expect(contains(r.protected_branches, "main"));
    try std.testing.expect(contains(r.protected_branches, "release"));
    try std.testing.expect(contains(r.protected_branches, "skins"));
    try std.testing.expect(contains(r.commands, "deploy.sh"));
    try std.testing.expect(contains(r.deletable, "build"));
    const other = try cfg.forRepo(a, "/other");
    try std.testing.expectEqual(Push.all, other.push);
    try std.testing.expect(!contains(other.deletable, "build"));
}

test "guard config: a broken file falls back to defaults" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = try Config.parse(a, "{ not json").forRepo(a, null);
    try std.testing.expectEqual(Push.all, e.push);
    try std.testing.expect(contains(e.protected_branches, "main"));
}

test "guard config: repo keys match however the path is written" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Trailing slashes, on either side.
    const slash = Config.parse(a,
        \\{"repos":{"/r/":{"push":"protected","commands":["deploy.sh"]}}}
    );
    try std.testing.expectEqual(Push.protected, (try slash.forRepo(a, "/r")).push);
    try std.testing.expect(contains((try slash.forRepo(a, "/r//")).commands, "deploy.sh"));
    // A symlinked key finds the real repo, and the other way round.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("real");
    try tmp.dir.symLink("real", "link", .{ .is_directory = true });
    const base = try tmp.dir.realpathAlloc(a, ".");
    const real = try std.fs.path.join(a, &.{ base, "real" });
    const link = try std.fs.path.join(a, &.{ base, "link" });
    const by_link = Config.parse(a, try std.fmt.allocPrint(a, "{{\"repos\":{{\"{s}/\":{{\"push\":\"protected\"}}}}}}", .{link}));
    try std.testing.expectEqual(Push.protected, (try by_link.forRepo(a, real)).push);
    const by_real = Config.parse(a, try std.fmt.allocPrint(a, "{{\"repos\":{{\"{s}\":{{\"push\":\"protected\"}}}}}}", .{real}));
    try std.testing.expectEqual(Push.protected, (try by_real.forRepo(a, link)).push);
    try std.testing.expectEqual(Push.all, (try by_real.forRepo(a, base)).push);
}
