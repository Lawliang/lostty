const std = @import("std");
const builtin = @import("builtin");
const assert = @import("../quirks.zig").inlineAssert;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const file_load = @import("file_load.zig");

/// The path to the configuration that should be opened for editing.
///
/// On Linux, this will use the file at the XDG config path. This is the
/// only valid path for Linux so we don't need to check for other paths.
///
/// On macOS, both XDG and AppSupport paths are valid. Because Ghostty
/// prioritizes AppSupport over XDG, we will use AppSupport if it exists,
/// followed by XDG if it exists, and finally AppSupport if neither exist.
/// For the existence check, we also prefer non-empty files over empty
/// files.
///
/// Lostty: Lostty's files are checked first, the same way, then Ghostty's
/// (the fallback that loads when no Lostty file exists). If none exists,
/// the file is created at Lostty's XDG path.
///
/// The returned value is allocated using the provided allocator.
pub fn openPath(alloc_gpa: Allocator) ![:0]const u8 {
    // Use an arena to make memory management easier in here.
    var arena = ArenaAllocator.init(alloc_gpa);
    defer arena.deinit();
    const alloc_arena = arena.allocator();

    // Get the path we should open
    const config_path = try configPath(alloc_arena);

    // Create config directory recursively.
    if (std.fs.path.dirname(config_path)) |config_dir| {
        try std.fs.cwd().makePath(config_dir);
    }

    // Try to create file and go on if it already exists
    _ = std.fs.createFileAbsolute(
        config_path,
        .{ .exclusive = true },
    ) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        }
    };

    return try alloc_gpa.dupeZ(u8, config_path);
}

/// Returns the config path to use for open for the current OS.
///
/// The allocator must be an arena allocator. No memory is freed by this
/// function and the resulting path is not all the memory that is allocated.
fn configPath(alloc_arena: Allocator) ![]const u8 {
    // Lostty: open the file that is loaded; create Lostty's if none exists.
    return try choosePath(
        try losttyPathCandidates(alloc_arena),
        try configPathCandidates(alloc_arena),
        try file_load.losttyXdgPath(alloc_arena),
    );
}

/// Lostty: a Lostty file if any exists, else a Ghostty file if any exists,
/// else `new_path`.
fn choosePath(
    lostty: []const []const u8,
    ghostty: []const []const u8,
    new_path: []const u8,
) ![]const u8 {
    return try pickPath(lostty) orelse try pickPath(ghostty) orelse new_path;
}

/// Lostty's config files in the order they are preferred for opening:
/// on macOS Application Support first, mirroring Ghostty's candidates.
fn losttyPathCandidates(alloc_arena: Allocator) ![]const []const u8 {
    var paths: std.ArrayList([]const u8) = try .initCapacity(alloc_arena, 2);
    if (comptime builtin.os.tag == .macos) {
        paths.appendAssumeCapacity(try file_load.losttyAppSupportPath(alloc_arena));
    }
    paths.appendAssumeCapacity(try file_load.losttyXdgPath(alloc_arena));
    return paths.items;
}

/// The first of `paths` that exists and is non-empty, else the first that
/// exists, else null.
fn pickPath(paths: []const []const u8) !?[]const u8 {
    assert(paths.len > 0);

    // Find the first path that exists and is non-empty. If no paths are
    // non-empty but at least one exists, we will return the first path that
    // exists.
    var exists: ?[]const u8 = null;
    for (paths) |path| {
        const f = std.fs.openFileAbsolute(path, .{}) catch |err| {
            switch (err) {
                // File doesn't exist, continue.
                error.BadPathName, error.FileNotFound => continue,

                // Some other error, assume it exists and return it.
                else => return err,
            }
        };
        defer f.close();

        // We expect stat to succeed because we just opened the file.
        const stat = try f.stat();

        // If the file is non-empty, return it.
        if (stat.size > 0) return path;

        // If the file is empty, remember it exists.
        if (exists == null) exists = path;
    }

    // No paths are non-empty, return the first path that exists.
    if (exists) |v| return v;

    // Lostty: none exists; the caller decides.
    return null;
}

/// Returns a const list of possible paths the main config file could be
/// in for the current OS.
fn configPathCandidates(alloc_arena: Allocator) ![]const []const u8 {
    var paths: std.ArrayList([]const u8) = try .initCapacity(alloc_arena, 4);
    errdefer paths.deinit(alloc_arena);

    if (comptime builtin.os.tag == .macos) {
        paths.appendAssumeCapacity(try file_load.defaultAppSupportPath(alloc_arena));
        paths.appendAssumeCapacity(try file_load.legacyDefaultAppSupportPath(alloc_arena));
    }

    paths.appendAssumeCapacity(try file_load.defaultXdgPath(alloc_arena));
    paths.appendAssumeCapacity(try file_load.legacyDefaultXdgPath(alloc_arena));

    return paths.items;
}

test "lostty: open path prefers Lostty's files, then Ghostty's, then creates Lostty's" {
    const testing = std.testing;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const root = try td.dir.realpath(".", &buf);

    var arena = ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const lostty_app = try std.fs.path.join(alloc, &.{ root, "lostty-app-support-config" });
    const lostty_xdg = try std.fs.path.join(alloc, &.{ root, "lostty-xdg-config" });
    const ghostty_app = try std.fs.path.join(alloc, &.{ root, "ghostty-app-support-config.ghostty" });
    const ghostty_xdg = try std.fs.path.join(alloc, &.{ root, "ghostty-xdg-config.ghostty" });
    const lostty: []const []const u8 = &.{ lostty_app, lostty_xdg };
    const ghostty: []const []const u8 = &.{ ghostty_app, ghostty_xdg };

    // Nothing exists: Lostty's new file.
    try testing.expectEqualStrings(lostty_xdg, try choosePath(lostty, ghostty, lostty_xdg));

    // Only a Ghostty config: open it rather than shadowing it.
    try td.dir.writeFile(.{ .sub_path = "ghostty-xdg-config.ghostty", .data = "a = b\n" });
    try testing.expectEqualStrings(ghostty_xdg, try choosePath(lostty, ghostty, lostty_xdg));

    // A Lostty config, even an empty one, wins over Ghostty's.
    try td.dir.writeFile(.{ .sub_path = "lostty-xdg-config", .data = "" });
    try testing.expectEqualStrings(lostty_xdg, try choosePath(lostty, ghostty, lostty_xdg));

    // Among Lostty's files, a non-empty one is preferred, then the order given.
    try td.dir.writeFile(.{ .sub_path = "lostty-app-support-config", .data = "" });
    try testing.expectEqualStrings(lostty_app, try choosePath(lostty, ghostty, lostty_xdg));
    try td.dir.writeFile(.{ .sub_path = "lostty-xdg-config", .data = "a = b\n" });
    try testing.expectEqualStrings(lostty_xdg, try choosePath(lostty, ghostty, lostty_xdg));
}
