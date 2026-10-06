const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const hooks = @import("claude/hooks.zig");

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

pub const Op = enum { install, remove, status, preview };

pub const Outcome = union(enum) {
    status: hooks.Status,
    changed: bool,
    failed: []const u8,
    preview: []const u8,
};

const usage =
    \\usage: +claude-hooks install   add Lostty's hooks to ~/.claude/settings.json
    \\       +claude-hooks remove    take them out again
    \\       +claude-hooks status    installed | partial | not-installed | unreadable
    \\       +claude-hooks preview   print the JSON that install adds
    \\
;

/// The `claude-hooks` command installs, removes or reports Lostty's Claude
/// Code hooks in `~/.claude/settings.json`: `+claude-hooks install`,
/// `+claude-hooks remove`, `+claude-hooks status` or `+claude-hooks preview`.
/// It backs the file up to `settings.json.lostty-backup` before changing it,
/// never touches a file it cannot parse, and only edits Lostty's own entries.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    const argv = try std.process.argsAlloc(alloc);
    var op: ?Op = null;
    for (argv, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "+claude-hooks") and i + 1 < argv.len) {
            op = std.meta.stringToEnum(Op, argv[i + 1]);
            break;
        }
    }
    const chosen = op orelse {
        try stderr.writeAll(usage);
        return 2;
    };

    const home = std.posix.getenv("HOME") orelse {
        try stderr.writeAll("claude-hooks: HOME is not set\n");
        return 1;
    };
    const path = try std.fs.path.join(alloc, &.{ home, ".claude", "settings.json" });

    switch (try applyAt(alloc, path, chosen)) {
        .status => |s| try stdout.print("{s}\n", .{s.label()}),
        .preview => |json| try stdout.writeAll(json),
        .changed => |changed| try stdout.writeAll(switch (chosen) {
            .install => if (changed) "installed\n" else "already installed\n",
            else => if (changed) "removed\n" else "nothing to remove\n",
        }),
        .failed => |msg| {
            try stderr.print("claude-hooks: {s}\n", .{msg});
            return 1;
        },
    }
    return 0;
}

/// Runs `op` on the settings file at `path` (absolute).
pub fn applyAt(alloc: Allocator, path: []const u8, op: Op) !Outcome {
    if (op == .preview) return .{ .preview = try hooks.stringify(alloc, try hooks.preview(alloc)) };

    // Follow a symlinked settings.json (dotfile managers) so the rename
    // replaces the real file and the link stays a link.
    const real = std.fs.realpathAlloc(alloc, path) catch |err| switch (err) {
        error.FileNotFound => try alloc.dupe(u8, path),
        else => return .{ .failed = "cannot resolve the settings file path" },
    };
    const bytes: ?[]u8 = std.fs.cwd().readFileAlloc(alloc, real, 16 << 20) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return .{ .failed = "cannot read the settings file" },
    };

    var root: std.json.Value = if (bytes) |b|
        std.json.parseFromSliceLeaky(std.json.Value, alloc, b, .{ .parse_numbers = false }) catch {
            if (op == .status) return .{ .status = .unreadable };
            return .{ .failed = "settings file is not valid JSON; left untouched" };
        }
    else
        .{ .object = std.json.ObjectMap.init(alloc) };

    if (op == .status) {
        return .{ .status = if (bytes == null) .not_installed else try hooks.status(alloc, root) };
    }

    const changed = (switch (op) {
        .install => hooks.install(alloc, &root),
        .remove => hooks.remove(&root),
        .status, .preview => unreachable,
    }) catch |err| switch (err) {
        error.Malformed => return .{ .failed = "settings file has an unexpected hooks layout; left untouched" },
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (!changed) return .{ .changed = false };

    if (std.fs.path.dirname(real)) |dir| try std.fs.cwd().makePath(dir);
    if (bytes) |b| {
        const backup = try std.fmt.allocPrint(alloc, "{s}.lostty-backup", .{real});
        try std.fs.cwd().writeFile(.{ .sub_path = backup, .data = b });
    }
    const tmp = try std.fmt.allocPrint(alloc, "{s}.lostty-tmp", .{real});
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = try hooks.stringify(alloc, root) });
    std.fs.renameAbsolute(tmp, real) catch |err| {
        std.fs.cwd().deleteFile(tmp) catch {};
        return err;
    };
    return .{ .changed = true };
}

fn tmpPath(alloc: Allocator, dir: std.testing.TmpDir, name: []const u8) ![]u8 {
    const base = try dir.dir.realpathAlloc(alloc, ".");
    return std.fs.path.join(alloc, &.{ base, name });
}

fn readAll(alloc: Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(alloc, path, 1 << 20);
}

test "claude hooks file: install creates a missing file and its directory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmpPath(a, tmp, ".claude/settings.json");
    try std.testing.expectEqual(Outcome{ .status = .not_installed }, try applyAt(a, path, .status));
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, path, .install));
    try std.testing.expectEqual(Outcome{ .status = .installed }, try applyAt(a, path, .status));
    // No backup when there was no file.
    try std.testing.expectError(error.FileNotFound, readAll(a, try tmpPath(a, tmp, ".claude/settings.json.lostty-backup")));
}

test "claude hooks file: install backs up, second install is a no-op" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "settings.json", .data = "{\"model\":\"opus\"}\n" });
    const path = try tmpPath(a, tmp, "settings.json");
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, path, .install));
    try std.testing.expectEqualStrings("{\"model\":\"opus\"}\n", try readAll(a, try tmpPath(a, tmp, "settings.json.lostty-backup")));
    const after = try readAll(a, path);
    try std.testing.expectEqual(Outcome{ .changed = false }, try applyAt(a, path, .install));
    try std.testing.expectEqualStrings(after, try readAll(a, path));
    // No temp file is left behind.
    try std.testing.expectError(error.FileNotFound, readAll(a, try tmpPath(a, tmp, "settings.json.lostty-tmp")));
}

test "claude hooks file: invalid JSON is left untouched" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "settings.json", .data = "{ \"model\": // comment\n}" });
    const path = try tmpPath(a, tmp, "settings.json");
    try std.testing.expectEqual(Outcome{ .status = .unreadable }, try applyAt(a, path, .status));
    const result = try applyAt(a, path, .install);
    try std.testing.expect(result == .failed);
    try std.testing.expectEqualStrings("{ \"model\": // comment\n}", try readAll(a, path));
}

test "claude hooks file: remove on a missing file changes nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmpPath(a, tmp, "settings.json");
    try std.testing.expectEqual(Outcome{ .changed = false }, try applyAt(a, path, .remove));
    try std.testing.expectError(error.FileNotFound, readAll(a, path));
}

test "claude hooks: install follows a symlink" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("dotfiles");
    try tmp.dir.writeFile(.{ .sub_path = "dotfiles/settings.json", .data = "{}" });
    try tmp.dir.symLink("dotfiles/settings.json", "settings.json", .{});
    const link = try tmpPath(a, tmp, "settings.json");
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, link, .install));
    // The link is still a link, and the target got the hooks.
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    _ = try tmp.dir.readLink("settings.json", &buf);
    const target = try readAll(a, try tmpPath(a, tmp, "dotfiles/settings.json"));
    try std.testing.expect(std.mem.indexOf(u8, target, "+claude-state busy") != null);
}

test "claude hooks file: preview needs no file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const result = try applyAt(a, "/nonexistent/settings.json", .preview);
    try std.testing.expect(std.mem.indexOf(u8, result.preview, "SessionEnd") != null);
}

test {
    _ = @import("claude/hooks.zig");
}
