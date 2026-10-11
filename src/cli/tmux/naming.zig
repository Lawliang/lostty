//! Session names on Lostty's tmux: each session is named after the project
//! its shell is in, so the phone can list sessions by project. See
//! docs/superpowers/specs/2026-10-09-lostty-mobile-design.md (§2, Naming).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// The session name for a project directory: its last path component, with
/// '.', ':', whitespace and control characters turned into '_' (tmux
/// rewrites '.' and ':' itself, and the others read badly in a list). The
/// home directory is "home" and "/" is "root".
pub fn projectName(alloc: Allocator, path: []const u8, home: ?[]const u8) ![]u8 {
    const trimmed = std.mem.trimEnd(u8, path, "/");
    if (trimmed.len == 0) return alloc.dupe(u8, "root");
    if (home) |h| {
        if (std.mem.eql(u8, trimmed, std.mem.trimEnd(u8, h, "/"))) return alloc.dupe(u8, "home");
    }
    const out = try alloc.dupe(u8, std.fs.path.basename(trimmed));
    for (out) |*c| {
        if (c.* == '.' or c.* == ':' or c.* <= ' ' or c.* == 0x7f) c.* = '_';
    }
    return out;
}

/// True when `name` is `base` or `base-<digits>`: the session already
/// carries this project's name, so there is nothing to rename.
pub fn alreadyNamed(name: []const u8, base: []const u8) bool {
    if (std.mem.eql(u8, name, base)) return true;
    if (name.len < base.len + 2 or !std.mem.startsWith(u8, name, base)) return false;
    if (name[base.len] != '-') return false;
    for (name[base.len + 1 ..]) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

/// `base`, else `base-2`, `base-3`, …: the first name no session in
/// `taken` uses.
pub fn uniqueName(alloc: Allocator, base: []const u8, taken: []const []const u8) ![]u8 {
    if (!contains(taken, base)) return alloc.dupe(u8, base);
    var n: usize = 2;
    while (true) : (n += 1) {
        const candidate = try std.fmt.allocPrint(alloc, "{s}-{d}", .{ base, n });
        if (!contains(taken, candidate)) return candidate;
        alloc.free(candidate);
    }
}

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, s)) return true;
    }
    return false;
}

/// The path after `+tmux-rename` (a `--` before it is skipped).
pub fn pathFromArgs(argv: []const []const u8) ?[]const u8 {
    for (argv, 0..) |arg, i| {
        if (!std.mem.eql(u8, arg, "+tmux-rename")) continue;
        var j = i + 1;
        if (j < argv.len and std.mem.eql(u8, argv[j], "--")) j += 1;
        return if (j < argv.len) argv[j] else null;
    }
    return null;
}

test "lostty tmux naming: projectName uses the last path component" {
    const alloc = std.testing.allocator;
    const cases = [_]struct { path: []const u8, want: []const u8 }{
        .{ .path = "/Users/me/code/idfk", .want = "idfk" },
        .{ .path = "/Users/me/code/idfk/", .want = "idfk" },
        .{ .path = "/Users/me/code/my.app", .want = "my_app" },
        .{ .path = "/Users/me/code/a:b", .want = "a_b" },
        .{ .path = "/Users/me/code/my proj", .want = "my_proj" },
        .{ .path = "/Users/me/code/tab\there", .want = "tab_here" },
        .{ .path = "/Users/me/code/código", .want = "código" },
        .{ .path = "/Users/me", .want = "home" },
        .{ .path = "/Users/me/", .want = "home" },
        .{ .path = "/", .want = "root" },
        .{ .path = "", .want = "root" },
    };
    for (cases) |c| {
        const got = try projectName(alloc, c.path, "/Users/me");
        defer alloc.free(got);
        try std.testing.expectEqualStrings(c.want, got);
    }
}

test "lostty tmux naming: projectName without a home directory" {
    const alloc = std.testing.allocator;
    const got = try projectName(alloc, "/Users/me", null);
    defer alloc.free(got);
    try std.testing.expectEqualStrings("me", got);
}

test "lostty tmux naming: alreadyNamed accepts base and base-N only" {
    const t = std.testing;
    try t.expect(alreadyNamed("idfk", "idfk"));
    try t.expect(alreadyNamed("idfk-2", "idfk"));
    try t.expect(alreadyNamed("idfk-12", "idfk"));
    try t.expect(!alreadyNamed("idfk-", "idfk"));
    try t.expect(!alreadyNamed("idfk-x", "idfk"));
    try t.expect(!alreadyNamed("idfkx", "idfk"));
    try t.expect(!alreadyNamed("notes", "idfk"));
    // The temporary name is never mistaken for a project named "lostty".
    try t.expect(!alreadyNamed("lostty-abcdef01-4242", "lostty"));
}

test "lostty tmux naming: uniqueName picks the first free suffix" {
    const alloc = std.testing.allocator;
    const cases = [_]struct { taken: []const []const u8, want: []const u8 }{
        .{ .taken = &.{}, .want = "idfk" },
        .{ .taken = &.{"notes"}, .want = "idfk" },
        .{ .taken = &.{"idfk"}, .want = "idfk-2" },
        .{ .taken = &.{ "idfk", "idfk-2" }, .want = "idfk-3" },
        .{ .taken = &.{"idfk-2"}, .want = "idfk" },
    };
    for (cases) |c| {
        const got = try uniqueName(alloc, "idfk", c.taken);
        defer alloc.free(got);
        try std.testing.expectEqualStrings(c.want, got);
    }
}

test "lostty tmux naming: pathFromArgs" {
    const t = std.testing;
    try t.expectEqualStrings("/a b", pathFromArgs(&.{ "/x/ghostty", "+tmux-rename", "/a b" }).?);
    try t.expectEqualStrings("/a", pathFromArgs(&.{ "/x/ghostty", "+tmux-rename", "--", "/a" }).?);
    try t.expect(pathFromArgs(&.{ "/x/ghostty", "+tmux-rename" }) == null);
    try t.expect(pathFromArgs(&.{ "/x/ghostty", "+tmux-rename", "--" }) == null);
    try t.expect(pathFromArgs(&.{ "/x/ghostty", "/a" }) == null);
}
