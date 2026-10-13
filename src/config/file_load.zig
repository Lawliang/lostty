const std = @import("std");
const builtin = @import("builtin");
const assert = @import("../quirks.zig").inlineAssert;
const Allocator = std.mem.Allocator;
const internal_os = @import("../os/main.zig");

const log = std.log.scoped(.config);

// Lostty: the user's config lives in Lostty's own place:
//
//   1. `$XDG_CONFIG_HOME/lostty/config` (default `~/.config/lostty/config`)
//   2. macOS only: `~/Library/Application Support/com.lawliang.lostty/config`
//
// If any of those exists, only Lostty's files load. Otherwise Ghostty's
// locations load exactly as upstream does (`$XDG_CONFIG_HOME/ghostty/config`
// and `config.ghostty`, and on macOS the same two names under
// `~/Library/Application Support/com.mitchellh.ghostty/`), so an existing
// Ghostty config keeps working until the user makes a Lostty one. A new
// config (template or "open config") is created at (1).

/// Ghostty's bundle ID. On macOS `build_config.bundle_id` is Lostty's, but
/// Ghostty's Application Support folder is still read as the fallback.
pub const ghostty_bundle_id = "com.mitchellh.ghostty";

/// Lostty's XDG config file. Returned value must be freed by the caller.
pub fn losttyXdgPath(alloc: Allocator) ![]const u8 {
    return try internal_os.xdg.config(alloc, .{ .subdir = "lostty/config" });
}

/// Lostty's macOS Application Support config file (in the folder named
/// after `build_config.bundle_id`). Returned value must be freed by the
/// caller.
pub fn losttyAppSupportPath(alloc: Allocator) ![]const u8 {
    return try internal_os.macos.appSupportDir(alloc, "config");
}

/// Lostty's config files for this OS in load order (later wins): XDG, then
/// on macOS Application Support, as upstream orders Ghostty's. Allocated
/// with `alloc`; meant for an arena.
pub fn losttyPaths(alloc: Allocator) ![]const []const u8 {
    var paths: std.ArrayList([]const u8) = try .initCapacity(alloc, 2);
    paths.appendAssumeCapacity(try losttyXdgPath(alloc));
    if (comptime builtin.os.tag == .macos) {
        paths.appendAssumeCapacity(try losttyAppSupportPath(alloc));
    }
    return paths.items;
}

/// True if a file (empty or not) exists at any of `paths`. An empty Lostty
/// config still counts: it means "start fresh, ignore Ghostty's".
pub fn anyExists(paths: []const []const u8) bool {
    for (paths) |path| {
        const stat = std.fs.cwd().statFile(path) catch continue;
        if (stat.kind == .file) return true;
    }
    return false;
}

/// Ghostty's macOS Application Support folder with `sub_path` joined.
fn ghosttyAppSupportDir(alloc: Allocator, sub_path: []const u8) ![]const u8 {
    // `appSupportDir` gives ".../Application Support/<bundle_id>/x"; swap
    // the bundle folder for Ghostty's.
    const ours = try internal_os.macos.appSupportDir(alloc, "x");
    defer alloc.free(ours);
    const base = std.fs.path.dirname(std.fs.path.dirname(ours).?).?;
    return try std.fs.path.join(alloc, &.{ base, ghostty_bundle_id, sub_path });
}

/// Default path for the XDG home configuration file. Returned value
/// must be freed by the caller.
pub fn defaultXdgPath(alloc: Allocator) ![]const u8 {
    return try internal_os.xdg.config(
        alloc,
        .{ .subdir = "ghostty/config.ghostty" },
    );
}

/// Ghostty <1.3.0 default path for the XDG home configuration file.
/// Returned value must be freed by the caller.
pub fn legacyDefaultXdgPath(alloc: Allocator) ![]const u8 {
    return try internal_os.xdg.config(
        alloc,
        .{ .subdir = "ghostty/config" },
    );
}

/// Preferred default path for the XDG home configuration file.
/// Returned value must be freed by the caller.
pub fn preferredXdgPath(alloc: Allocator) ![]const u8 {
    // If the XDG path exists, use that.
    const xdg_path = try defaultXdgPath(alloc);
    if (open(xdg_path)) |f| {
        f.close();
        return xdg_path;
    } else |_| {}

    // Try the legacy path
    errdefer alloc.free(xdg_path);
    const legacy_xdg_path = try legacyDefaultXdgPath(alloc);
    if (open(legacy_xdg_path)) |f| {
        f.close();
        alloc.free(xdg_path);
        return legacy_xdg_path;
    } else |_| {}

    // Legacy path and XDG path both don't exist. Return the
    // new one.
    alloc.free(legacy_xdg_path);
    return xdg_path;
}

/// Default path for the macOS Application Support configuration file.
/// Returned value must be freed by the caller.
pub fn defaultAppSupportPath(alloc: Allocator) ![]const u8 {
    return try ghosttyAppSupportDir(alloc, "config.ghostty"); // Lostty: Ghostty's folder
}

/// Ghostty <1.3.0 default path for the macOS Application Support
/// configuration file. Returned value must be freed by the caller.
pub fn legacyDefaultAppSupportPath(alloc: Allocator) ![]const u8 {
    return try ghosttyAppSupportDir(alloc, "config"); // Lostty: Ghostty's folder
}

/// Preferred default path for the macOS Application Support configuration file.
/// Returned value must be freed by the caller.
pub fn preferredAppSupportPath(alloc: Allocator) ![]const u8 {
    // If the app support path exists, use that.
    const app_support_path = try defaultAppSupportPath(alloc);
    if (open(app_support_path)) |f| {
        f.close();
        return app_support_path;
    } else |_| {}

    // Try the legacy path
    errdefer alloc.free(app_support_path);
    const legacy_app_support_path = try legacyDefaultAppSupportPath(alloc);
    if (open(legacy_app_support_path)) |f| {
        f.close();
        alloc.free(app_support_path);
        return legacy_app_support_path;
    } else |_| {}

    // Legacy path and app support path both don't exist. Return the
    // new one.
    alloc.free(legacy_app_support_path);
    return app_support_path;
}

/// Returns the path to the preferred default configuration file.
/// This is the file where users should place their configuration.
///
/// This doesn't create or populate the file with any default
/// contents; downstream callers must handle this.
///
/// Lostty: a Lostty file if one exists (Application Support first on macOS,
/// as upstream prefers it), else the Ghostty file in use, else Lostty's XDG
/// path.
///
/// The returned value must be freed by the caller.
pub fn preferredDefaultFilePath(alloc: Allocator) ![]const u8 {
    if (comptime builtin.os.tag == .macos) {
        const app_support_path = try losttyAppSupportPath(alloc);
        if (anyExists(&.{app_support_path})) return app_support_path;
        alloc.free(app_support_path);
    }
    const lostty_xdg_path = try losttyXdgPath(alloc);
    if (anyExists(&.{lostty_xdg_path})) return lostty_xdg_path;
    errdefer alloc.free(lostty_xdg_path);

    const ghostty_path = try ghosttyPreferredDefaultFilePath(alloc);
    if (anyExists(&.{ghostty_path})) {
        alloc.free(lostty_xdg_path);
        return ghostty_path;
    }
    alloc.free(ghostty_path);
    return lostty_xdg_path;
}

/// Upstream's `preferredDefaultFilePath`, over Ghostty's locations only.
fn ghosttyPreferredDefaultFilePath(alloc: Allocator) ![]const u8 {
    switch (builtin.os.tag) {
        .macos => {
            // macOS prefers the Application Support directory
            // if it exists.
            const app_support_path = try preferredAppSupportPath(alloc);
            const app_support_file = open(app_support_path) catch {
                // Try the XDG path if it exists
                const xdg_path = try preferredXdgPath(alloc);
                const xdg_file = open(xdg_path) catch {
                    // If neither file exists, use app support
                    alloc.free(xdg_path);
                    return app_support_path;
                };
                xdg_file.close();
                alloc.free(app_support_path);
                return xdg_path;
            };
            app_support_file.close();
            return app_support_path;
        },

        // All other platforms use XDG only
        else => return try preferredXdgPath(alloc),
    }
}

const OpenFileError = error{
    FileNotFound,
    FileIsEmpty,
    FileOpenFailed,
    NotAFile,
};

/// Opens the file at the given path and returns the file handle
/// if it exists and is non-empty. This also constrains the possible
/// errors to a smaller set that we can explicitly handle.
pub fn open(path: []const u8) OpenFileError!std.fs.File {
    assert(std.fs.path.isAbsolute(path));

    var file = std.fs.openFileAbsolute(
        path,
        .{},
    ) catch |err| switch (err) {
        error.FileNotFound => return OpenFileError.FileNotFound,
        else => {
            log.warn("unexpected file open error path={s} err={}", .{
                path,
                err,
            });
            return OpenFileError.FileOpenFailed;
        },
    };
    errdefer file.close();

    const stat = file.stat() catch |err| {
        log.warn("error getting file stat path={s} err={}", .{
            path,
            err,
        });
        return OpenFileError.FileOpenFailed;
    };
    switch (stat.kind) {
        .file => {},
        else => return OpenFileError.NotAFile,
    }

    if (stat.size == 0) return OpenFileError.FileIsEmpty;

    return file;
}

test "lostty: anyExists counts empty files but not missing ones or folders" {
    const testing = std.testing;
    var td = testing.tmpDir(.{});
    defer td.cleanup();
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const root = try td.dir.realpath(".", &buf);
    const alloc = testing.allocator;

    const missing = try std.fs.path.join(alloc, &.{ root, "missing" });
    defer alloc.free(missing);
    const folder = try std.fs.path.join(alloc, &.{ root, "folder" });
    defer alloc.free(folder);
    const empty = try std.fs.path.join(alloc, &.{ root, "empty" });
    defer alloc.free(empty);

    try td.dir.makeDir("folder");
    try testing.expect(!anyExists(&.{ missing, folder }));
    try td.dir.writeFile(.{ .sub_path = "empty", .data = "" });
    try testing.expect(anyExists(&.{ missing, folder, empty }));
}

test "lostty: config file locations" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const xdg = try losttyXdgPath(alloc);
    defer alloc.free(xdg);
    try testing.expect(std.mem.endsWith(u8, xdg, "/lostty/config"));

    if (comptime builtin.os.tag != .macos) return;

    // Lostty's own folder in Application Support; Ghostty's is the fallback.
    const ours = try losttyAppSupportPath(alloc);
    defer alloc.free(ours);
    try testing.expect(std.mem.endsWith(u8, ours, "/Application Support/com.lawliang.lostty/config"));

    const theirs = try defaultAppSupportPath(alloc);
    defer alloc.free(theirs);
    try testing.expect(std.mem.endsWith(u8, theirs, "/Application Support/com.mitchellh.ghostty/config.ghostty"));

    const legacy = try legacyDefaultAppSupportPath(alloc);
    defer alloc.free(legacy);
    try testing.expect(std.mem.endsWith(u8, legacy, "/Application Support/com.mitchellh.ghostty/config"));
}
