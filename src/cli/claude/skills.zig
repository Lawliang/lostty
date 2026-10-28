const std = @import("std");
const Allocator = std.mem.Allocator;
const Dir = std.fs.Dir;
const Status = @import("hooks.zig").Status;

/// Lostty's skills (the repo's skills/ folder, bundled in the app's
/// resources as lostty-skills) in an agent's skills folder
/// (~/.claude/skills, ~/.codex/skills). Only folders named lostty-* are
/// touched, and only those Lostty installed (they hold `mark`) are removed.
pub const resources_subdir = "lostty-skills";
const prefix = "lostty-";
const mark = ".lostty";
const file_max = 1 << 20;

/// installed when every skill matches and none Lostty retired is left,
/// not_installed when Lostty installed none, else partial.
pub fn status(alloc: Allocator, src: Dir, dest: Dir) !Status {
    if (!try anyOurs(dest)) return .not_installed;
    var it = src.iterate();
    while (try it.next()) |entry| {
        if (!isSkill(entry)) continue;
        if (!try same(alloc, src, dest, entry.name)) return .partial;
    }
    if (try retired(src, dest) != null) return .partial;
    return .installed;
}

/// Copies each skill that differs, and removes the ones Lostty installed
/// that it no longer ships. True when anything changed.
pub fn install(alloc: Allocator, src: Dir, dest: Dir) !bool {
    var changed = false;
    var it = src.iterate();
    while (try it.next()) |entry| {
        if (!isSkill(entry)) continue;
        if (try same(alloc, src, dest, entry.name) and isOurs(dest, entry.name)) continue;
        try dest.deleteTree(entry.name);
        try copyTree(alloc, src, dest, entry.name);
        var skill = try dest.openDir(entry.name, .{});
        defer skill.close();
        try skill.writeFile(.{ .sub_path = mark, .data = "Installed by Lostty. Lostty replaces or removes this folder.\n" });
        changed = true;
    }
    while (try retired(src, dest)) |name| {
        try dest.deleteTree(name.slice());
        changed = true;
    }
    return changed;
}

/// Removes every skill Lostty installed. True when anything changed.
pub fn remove(dest: Dir) !bool {
    var changed = false;
    while (try firstOurs(dest, null)) |name| {
        try dest.deleteTree(name.slice());
        changed = true;
    }
    return changed;
}

const Name = struct {
    buf: [std.fs.max_name_bytes]u8 = undefined,
    len: usize = 0,

    fn slice(self: *const Name) []const u8 {
        return self.buf[0..self.len];
    }
};

fn isSkill(entry: Dir.Entry) bool {
    return entry.kind == .directory and std.mem.startsWith(u8, entry.name, prefix);
}

fn isOurs(dest: Dir, name: []const u8) bool {
    var skill = dest.openDir(name, .{}) catch return false;
    defer skill.close();
    skill.access(mark, .{}) catch return false;
    return true;
}

fn anyOurs(dest: Dir) !bool {
    return try firstOurs(dest, null) != null;
}

/// A skill Lostty installed that `src` no longer has.
fn retired(src: Dir, dest: Dir) !?Name {
    return firstOurs(dest, src);
}

/// The first lostty-* folder in `dest` holding the mark and, with `src`,
/// missing from it.
fn firstOurs(dest: Dir, src: ?Dir) !?Name {
    var it = dest.iterate();
    while (try it.next()) |entry| {
        if (!isSkill(entry) or !isOurs(dest, entry.name)) continue;
        if (src) |s| if (s.access(entry.name, .{})) |_| continue else |_| {};
        var name: Name = .{ .len = entry.name.len };
        @memcpy(name.buf[0..entry.name.len], entry.name);
        return name;
    }
    return null;
}

/// The skill `name` has the same files in `src` and `dest`, the mark aside.
fn same(alloc: Allocator, src: Dir, dest: Dir, name: []const u8) !bool {
    var from = try src.openDir(name, .{ .iterate = true });
    defer from.close();
    var to = dest.openDir(name, .{ .iterate = true }) catch return false;
    defer to.close();

    var files: usize = 0;
    var walker = try from.walk(alloc);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        files += 1;
        const a = try from.readFileAlloc(alloc, entry.path, file_max);
        defer alloc.free(a);
        const b = to.readFileAlloc(alloc, entry.path, file_max) catch return false;
        defer alloc.free(b);
        if (!std.mem.eql(u8, a, b)) return false;
        const mode_a = (try from.statFile(entry.path)).mode;
        const mode_b = (try to.statFile(entry.path)).mode;
        if (mode_a & 0o111 != mode_b & 0o111) return false;
    }

    var installed: usize = 0;
    var walker_to = try to.walk(alloc);
    defer walker_to.deinit();
    while (try walker_to.next()) |entry| {
        if (entry.kind == .file and !std.mem.eql(u8, entry.path, mark)) installed += 1;
    }
    return files == installed;
}

fn copyTree(alloc: Allocator, src: Dir, dest: Dir, name: []const u8) !void {
    var from = try src.openDir(name, .{ .iterate = true });
    defer from.close();
    var to = try dest.makeOpenPath(name, .{});
    defer to.close();
    var walker = try from.walk(alloc);
    defer walker.deinit();
    while (try walker.next()) |entry| switch (entry.kind) {
        .directory => try to.makePath(entry.path),
        .file => try from.copyFile(entry.path, to, entry.path, .{}),
        else => {},
    };
}

const testing = std.testing;

fn fixture(tmp: *testing.TmpDir) !struct { src: Dir, dest: Dir } {
    try tmp.dir.makePath("src/lostty-a/scripts");
    try tmp.dir.writeFile(.{ .sub_path = "src/lostty-a/SKILL.md", .data = "a" });
    try tmp.dir.writeFile(.{ .sub_path = "src/lostty-a/scripts/run.sh", .data = "echo" });
    try tmp.dir.writeFile(.{ .sub_path = "src/README.md", .data = "readme" });
    try tmp.dir.makePath("dest/mine");
    try tmp.dir.makePath("dest/lostty-made-by-hand");
    return .{
        .src = try tmp.dir.openDir("src", .{ .iterate = true }),
        .dest = try tmp.dir.openDir("dest", .{ .iterate = true }),
    };
}

test "claude skills: install, then installed; a change makes it partial" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var dirs = try fixture(&tmp);
    defer dirs.src.close();
    defer dirs.dest.close();

    try testing.expectEqual(Status.not_installed, try status(testing.allocator, dirs.src, dirs.dest));
    try testing.expect(try install(testing.allocator, dirs.src, dirs.dest));
    try testing.expectEqual(Status.installed, try status(testing.allocator, dirs.src, dirs.dest));
    try testing.expect(!try install(testing.allocator, dirs.src, dirs.dest));
    try dirs.dest.access("lostty-a/scripts/run.sh", .{});
    try testing.expectError(error.FileNotFound, dirs.dest.access("README.md", .{}));

    try tmp.dir.writeFile(.{ .sub_path = "src/lostty-a/SKILL.md", .data = "a, edited" });
    try testing.expectEqual(Status.partial, try status(testing.allocator, dirs.src, dirs.dest));
    try testing.expect(try install(testing.allocator, dirs.src, dirs.dest));
    try testing.expectEqual(Status.installed, try status(testing.allocator, dirs.src, dirs.dest));
}

test "claude skills: a retired skill goes only if Lostty installed it" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var dirs = try fixture(&tmp);
    defer dirs.src.close();
    defer dirs.dest.close();

    try tmp.dir.makePath("src/lostty-old");
    try tmp.dir.writeFile(.{ .sub_path = "src/lostty-old/SKILL.md", .data = "old" });
    _ = try install(testing.allocator, dirs.src, dirs.dest);
    try tmp.dir.deleteTree("src/lostty-old");

    try testing.expectEqual(Status.partial, try status(testing.allocator, dirs.src, dirs.dest));
    try testing.expect(try install(testing.allocator, dirs.src, dirs.dest));
    try testing.expectError(error.FileNotFound, dirs.dest.access("lostty-old", .{}));
    try dirs.dest.access("lostty-made-by-hand", .{});
    try dirs.dest.access("mine", .{});
}

test "claude skills: remove takes out only Lostty's" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var dirs = try fixture(&tmp);
    defer dirs.src.close();
    defer dirs.dest.close();

    _ = try install(testing.allocator, dirs.src, dirs.dest);
    try testing.expect(try remove(dirs.dest));
    try testing.expect(!try remove(dirs.dest));
    try testing.expectError(error.FileNotFound, dirs.dest.access("lostty-a", .{}));
    try dirs.dest.access("lostty-made-by-hand", .{});
    try dirs.dest.access("mine", .{});
    try testing.expectEqual(Status.not_installed, try status(testing.allocator, dirs.src, dirs.dest));
}
