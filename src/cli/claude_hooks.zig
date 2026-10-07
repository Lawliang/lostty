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
    \\                               (and ~/.codex/hooks.json when Codex is installed)
    \\       +claude-hooks remove    take them out again
    \\       +claude-hooks status    installed | partial | not-installed | unreadable
    \\       +claude-hooks preview   print the JSON that install adds
    \\
    \\Add --agent=claude or --agent=codex to act on just one of them.
    \\
;

/// The `claude-hooks` command installs, removes or reports Lostty's hooks
/// for Claude Code (`~/.claude/settings.json`) and, when `~/.codex` exists,
/// for Codex (`~/.codex/hooks.json`): `+claude-hooks install`,
/// `+claude-hooks remove`, `+claude-hooks status` or `+claude-hooks preview`.
/// It backs each file up (`<file>.lostty-backup`) before changing it, never
/// touches a file it cannot parse, and only edits Lostty's own entries.
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
    var arg_list: std.ArrayList([]const u8) = .empty;
    for (argv) |arg| try arg_list.append(alloc, arg);
    const args = parseArgs(arg_list.items) orelse {
        try stderr.writeAll(usage);
        return 2;
    };
    const chosen = args.op;

    const home = std.posix.getenv("HOME") orelse {
        try stderr.writeAll("claude-hooks: HOME is not set\n");
        return 1;
    };
    // Claude always; Codex only when it is installed (~/.codex exists).
    var targets: std.ArrayList(Target) = .empty;
    // With --agent, only that agent; otherwise Claude, plus Codex when
    // it is installed.
    if (args.agent == null or args.agent == .claude) {
        try targets.append(alloc, .{ .agent = .claude, .path = try std.fs.path.join(alloc, &.{ home, ".claude", "settings.json" }) });
    }
    const codex_dir = try std.fs.path.join(alloc, &.{ home, ".codex" });
    if (args.agent == .codex or (args.agent == null and if (std.fs.cwd().access(codex_dir, .{})) |_| true else |_| false)) {
        try targets.append(alloc, .{ .agent = .codex, .path = try std.fs.path.join(alloc, &.{ codex_dir, "hooks.json" }) });
    }

    // One combined answer, so callers (the app's prompt) see a single state.
    if (chosen == .status) {
        var combined: ?hooks.Status = null;
        for (targets.items) |t| {
            const s = switch (try applyAt(alloc, t.path, .status, t.agent)) {
                .status => |s| s,
                else => unreachable,
            };
            combined = if (combined) |c| combine(c, s) else s;
        }
        try stdout.print("{s}\n", .{combined.?.label()});
        return 0;
    }
    if (chosen == .preview) {
        try stdout.writeAll((try applyAt(alloc, targets.items[0].path, .preview, targets.items[0].agent)).preview);
        return 0;
    }

    for (targets.items) |t| {
        const name = @tagName(t.agent);
        switch (try applyAt(alloc, t.path, chosen, t.agent)) {
            .changed => |changed| try stdout.print("{s}: {s}\n", .{ name, switch (chosen) {
                .install => if (changed) "installed" else "already installed",
                else => if (changed) "removed" else "nothing to remove",
            } }),
            .failed => |msg| {
                try stderr.print("claude-hooks: {s}: {s}\n", .{ name, msg });
                return 1;
            },
            .status, .preview => unreachable,
        }
    }
    return 0;
}

const Target = struct { agent: hooks.Agent, path: []const u8 };

pub const Args = struct { op: Op, agent: ?hooks.Agent };

/// `+claude-hooks <op> [--agent=claude|codex]`; null on anything else.
pub fn parseArgs(argv: []const []const u8) ?Args {
    for (argv, 0..) |arg, i| {
        if (!std.mem.eql(u8, arg, "+claude-hooks")) continue;
        if (i + 1 >= argv.len) return null;
        const op = std.meta.stringToEnum(Op, argv[i + 1]) orelse return null;
        var agent: ?hooks.Agent = null;
        for (argv[i + 2 ..]) |extra| {
            const prefix = "--agent=";
            if (!std.mem.startsWith(u8, extra, prefix)) return null;
            agent = std.meta.stringToEnum(hooks.Agent, extra[prefix.len..]) orelse return null;
        }
        return .{ .op = op, .agent = agent };
    }
    return null;
}

/// Two agents' states as one: any unreadable wins, then all-installed or
/// all-missing, else partial.
pub fn combine(a: hooks.Status, b: hooks.Status) hooks.Status {
    if (a == .unreadable or b == .unreadable) return .unreadable;
    if (a == b) return a;
    return .partial;
}

/// Runs `op` on `agent`'s hook file at `path` (absolute).
pub fn applyAt(alloc: Allocator, path: []const u8, op: Op, agent: hooks.Agent) !Outcome {
    if (op == .preview) return .{ .preview = try hooks.stringify(alloc, try hooks.preview(alloc, agent)) };

    // Follow a symlinked settings.json (dotfile managers) so the rename
    // replaces the real file and the link stays a link.
    const real = std.fs.realpathAlloc(alloc, path) catch |err| switch (err) {
        error.FileNotFound => missing: {
            // A symlink to a file that does not exist yet (dotfiles not
            // applied): refuse rather than replace the link with a file.
            var buf: [std.fs.max_path_bytes]u8 = undefined;
            if (std.fs.cwd().readLink(path, &buf)) |_| {
                if (op == .status) return .{ .status = .not_installed };
                return .{ .failed = "settings file is a symlink to a missing file; left untouched" };
            } else |_| {}
            break :missing try alloc.dupe(u8, path);
        },
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
        return .{ .status = if (bytes == null) .not_installed else try hooks.status(alloc, agent, root) };
    }

    const changed = (switch (op) {
        .install => hooks.install(alloc, agent, &root),
        .remove => hooks.remove(&root),
        .status, .preview => unreachable,
    }) catch |err| switch (err) {
        error.Malformed => return .{ .failed = "settings file has an unexpected hooks layout; left untouched" },
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (!changed) return .{ .changed = false };

    // Keep the original's permissions: settings.json may hold tokens.
    const mode: std.fs.File.Mode = if (bytes != null)
        (if (std.fs.cwd().statFile(real)) |st| st.mode & 0o777 else |_| 0o600)
    else
        0o644;
    writeOut(alloc, real, bytes, try hooks.stringify(alloc, root), mode) catch |err| {
        return .{ .failed = try std.fmt.allocPrint(alloc, "cannot write {s} ({s}); left untouched", .{ real, @errorName(err) }) };
    };
    return .{ .changed = true };
}

/// Backs up `original` (if any), then replaces `real` with `data` through a
/// temp file and a rename, all with `mode`. On error the original is intact.
fn writeOut(alloc: Allocator, real: []const u8, original: ?[]const u8, data: []const u8, mode: std.fs.File.Mode) !void {
    if (std.fs.path.dirname(real)) |dir| try std.fs.cwd().makePath(dir);
    if (original) |b| try writeWithMode(try std.fmt.allocPrint(alloc, "{s}.lostty-backup", .{real}), b, mode);
    const tmp = try std.fmt.allocPrint(alloc, "{s}.lostty-tmp", .{real});
    errdefer std.fs.cwd().deleteFile(tmp) catch {};
    try writeWithMode(tmp, data, mode);
    try std.fs.renameAbsolute(tmp, real);
}

fn writeWithMode(path: []const u8, data: []const u8, mode: std.fs.File.Mode) !void {
    const file = try std.fs.cwd().createFile(path, .{ .mode = mode });
    defer file.close();
    // createFile's mode is filtered by the umask (and ignored for an
    // existing file), so set it explicitly.
    try file.chmod(mode);
    try file.writeAll(data);
    try file.sync();
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
    try std.testing.expectEqual(Outcome{ .status = .not_installed }, try applyAt(a, path, .status, .claude));
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, path, .install, .claude));
    try std.testing.expectEqual(Outcome{ .status = .installed }, try applyAt(a, path, .status, .claude));
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
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, path, .install, .claude));
    try std.testing.expectEqualStrings("{\"model\":\"opus\"}\n", try readAll(a, try tmpPath(a, tmp, "settings.json.lostty-backup")));
    const after = try readAll(a, path);
    try std.testing.expectEqual(Outcome{ .changed = false }, try applyAt(a, path, .install, .claude));
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
    try std.testing.expectEqual(Outcome{ .status = .unreadable }, try applyAt(a, path, .status, .claude));
    const result = try applyAt(a, path, .install, .claude);
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
    try std.testing.expectEqual(Outcome{ .changed = false }, try applyAt(a, path, .remove, .claude));
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
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, link, .install, .claude));
    // The link is still a link, and the target got the hooks.
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    _ = try tmp.dir.readLink("settings.json", &buf);
    const target = try readAll(a, try tmpPath(a, tmp, "dotfiles/settings.json"));
    try std.testing.expect(std.mem.indexOf(u8, target, "+claude-state busy") != null);
}

test "claude hooks file: install keeps the file's permissions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    // settings.json may hold tokens in its env block; a 0600 file stays 0600.
    const f = try tmp.dir.createFile("settings.json", .{ .mode = 0o600 });
    try f.writeAll("{}");
    f.close();
    const path = try tmpPath(a, tmp, "settings.json");
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, path, .install, .claude));
    try std.testing.expectEqual(@as(std.fs.File.Mode, 0o600), (try tmp.dir.statFile("settings.json")).mode & 0o777);
    try std.testing.expectEqual(@as(std.fs.File.Mode, 0o600), (try tmp.dir.statFile("settings.json.lostty-backup")).mode & 0o777);
}

test "claude hooks file: write errors become a message and leave the file alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "settings.json", .data = "{}" });
    const path = try tmpPath(a, tmp, "settings.json");
    // A read-only directory (e.g. a Nix store target) cannot take the backup.
    try std.posix.fchmod(tmp.dir.fd, 0o555);
    defer std.posix.fchmod(tmp.dir.fd, 0o755) catch {};
    const result = try applyAt(a, path, .install, .claude);
    try std.testing.expect(result == .failed);
    try std.testing.expect(std.mem.indexOf(u8, result.failed, "AccessDenied") != null);
    try std.testing.expectEqualStrings("{}", try readAll(a, path));
}

test "claude hooks file: a dangling symlink is refused, not replaced" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink("dotfiles/settings.json", "settings.json", .{});
    const link = try tmpPath(a, tmp, "settings.json");
    const result = try applyAt(a, link, .install, .claude);
    try std.testing.expect(result == .failed);
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    try std.testing.expectEqualStrings("dotfiles/settings.json", try tmp.dir.readLink("settings.json", &buf));
}

test "claude hooks file: preview needs no file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const result = try applyAt(a, "/nonexistent/settings.json", .preview, .claude);
    try std.testing.expect(std.mem.indexOf(u8, result.preview, "SessionEnd") != null);
}

test "claude hooks file: parseArgs reads the op and an optional agent" {
    const t = std.testing;
    try t.expectEqual(Args{ .op = .install, .agent = null }, parseArgs(&.{ "/x/ghostty", "+claude-hooks", "install" }).?);
    try t.expectEqual(Args{ .op = .status, .agent = .codex }, parseArgs(&.{ "/x/ghostty", "+claude-hooks", "status", "--agent=codex" }).?);
    try t.expectEqual(Args{ .op = .install, .agent = .claude }, parseArgs(&.{ "/x/ghostty", "+claude-hooks", "install", "--agent=claude" }).?);
    try t.expect(parseArgs(&.{ "/x/ghostty", "+claude-hooks", "install", "--agent=gemini" }) == null);
    try t.expect(parseArgs(&.{ "/x/ghostty", "+claude-hooks", "bogus" }) == null);
    try t.expect(parseArgs(&.{ "/x/ghostty", "+claude-hooks" }) == null);
}

test "claude hooks file: combine two agents' states" {
    const t = std.testing;
    try t.expectEqual(hooks.Status.installed, combine(.installed, .installed));
    try t.expectEqual(hooks.Status.not_installed, combine(.not_installed, .not_installed));
    try t.expectEqual(hooks.Status.partial, combine(.installed, .not_installed));
    try t.expectEqual(hooks.Status.partial, combine(.partial, .installed));
    try t.expectEqual(hooks.Status.unreadable, combine(.installed, .unreadable));
}

test "claude hooks file: codex install writes hooks.json with its events" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmpPath(a, tmp, ".codex/hooks.json");
    try std.testing.expectEqual(Outcome{ .changed = true }, try applyAt(a, path, .install, .codex));
    try std.testing.expectEqual(Outcome{ .status = .installed }, try applyAt(a, path, .status, .codex));
    const text = try readAll(a, path);
    try std.testing.expect(std.mem.indexOf(u8, text, "+claude-state busy") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "SessionEnd") == null);
}

test {
    _ = @import("claude/hooks.zig");
}
