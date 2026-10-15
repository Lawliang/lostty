const std = @import("std");
const Allocator = std.mem.Allocator;

// Paths for the guard: resolving what a command names, and the folders
// that are guardrails or that don't count as "outside the project".

pub fn resolve(alloc: Allocator, cwd: []const u8, p: []const u8) Allocator.Error![]const u8 {
    return std.fs.path.resolve(alloc, &.{ cwd, p });
}

/// True when `path` is `root` or lies under it. ASCII case-insensitive, since
/// macOS volumes usually are. Inputs must be resolved absolute paths (see `resolve`).
pub fn inside(path: []const u8, root: []const u8) bool {
    if (!std.ascii.startsWithIgnoreCase(path, root)) return false;
    if (path.len == root.len) return true;
    return root.len > 0 and (root[root.len - 1] == '/' or path[root.len] == '/');
}

fn under(path: []const u8, home: []const u8, rel: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const full = std.fmt.bufPrint(&buf, "{s}/{s}", .{ home, rel }) catch return false;
    return inside(path, full);
}

/// Guardrail locations, relative to home (or absolute, for the app bundle).
const home_guardrails = [_][]const u8{
    ".claude/settings.json",
    ".claude/settings.local.json",
    ".codex/hooks.json",
    ".codex/config.toml",
    ".config/lostty",
    ".ssh",
};
const app_guardrail = "/Applications/Lostty.app";

/// Files and folders whose change would loosen the guard or reach secrets.
/// A guardrail's ancestor counts too, since deleting it deletes the guardrail.
/// Inputs must be resolved absolute paths (see `resolve`).
pub fn isGuardrail(path: []const u8, home: []const u8) bool {
    // Project-level Claude and Codex settings, in any repo.
    const suffixes = [_][]const u8{
        "/.claude/settings.json", "/.claude/settings.local.json",
        "/.codex/hooks.json",     "/.codex/config.toml",
    };
    for (suffixes) |n| if (std.ascii.endsWithIgnoreCase(path, n)) return true;
    // Under a guardrail, or an ancestor of one (`rm -rf ~/.claude`).
    for (home_guardrails) |rel| {
        if (under(path, home, rel)) return true;
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const loc = std.fmt.bufPrint(&buf, "{s}/{s}", .{ home, rel }) catch continue;
        if (inside(loc, path)) return true;
    }
    if (inside(path, app_guardrail)) return true;
    return inside(app_guardrail, path);
}

/// Writes here don't count as leaving the project: the temp folders and
/// Claude's own memory and transcripts. Inputs must be resolved absolute
/// paths (see `resolve`).
pub fn isWriteExempt(path: []const u8, home: []const u8, tmpdir: ?[]const u8) bool {
    const roots = [_][]const u8{ "/tmp", "/private/tmp", "/var/folders", "/private/var/folders" };
    for (roots) |r| if (inside(path, r)) return true;
    if (tmpdir) |t| if (inside(path, std.mem.trimRight(u8, t, "/"))) return true;
    return under(path, home, ".claude/projects");
}

pub fn findRepo(alloc: Allocator, cwd: []const u8) ?[]const u8 {
    var dir: []const u8 = cwd;
    while (true) {
        const dot_git = std.fs.path.join(alloc, &.{ dir, ".git" }) catch return null;
        if (std.fs.cwd().access(dot_git, .{})) |_| return dir else |_| {}
        dir = std.fs.path.dirname(dir) orelse return null;
    }
}

test "guard paths: resolve folds dots and joins relative paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("/r/x", try resolve(a, "/r/sub", "../x"));
    try std.testing.expectEqualStrings("/Users/me/x", try resolve(a, "/r", "/tmp/../Users/me/x"));
    try std.testing.expectEqualStrings("/r/sub", try resolve(a, "/r/sub", "."));
    try std.testing.expectEqualStrings("/r", try resolve(a, "/r/sub/", ".."));
}

test "guard paths: inside" {
    try std.testing.expect(inside("/r/a", "/r"));
    try std.testing.expect(inside("/r", "/r"));
    try std.testing.expect(!inside("/rx/a", "/r"));
    try std.testing.expect(!inside("/", "/r"));
    try std.testing.expect(inside("/R/A", "/r"));
}

test "guard paths: guardrails" {
    const h = "/Users/me";
    try std.testing.expect(isGuardrail("/Users/me/.claude/settings.json", h));
    try std.testing.expect(isGuardrail("/Users/me/proj/.claude/settings.local.json", h));
    try std.testing.expect(isGuardrail("/Users/me/.codex/hooks.json", h));
    try std.testing.expect(isGuardrail("/Users/me/proj/.codex/config.toml", h));
    try std.testing.expect(isGuardrail("/Users/me/.config/lostty/guard.json", h));
    try std.testing.expect(isGuardrail("/Users/me/.config/lostty", h));
    try std.testing.expect(isGuardrail("/Users/me/.ssh/id_ed25519", h));
    try std.testing.expect(isGuardrail("/Applications/Lostty.app/Contents/MacOS/lostty", h));
    try std.testing.expect(!isGuardrail("/Users/me/proj/settings.json", h));
    try std.testing.expect(!isGuardrail("/Users/me/.claude/projects/x/memory/a.md", h));
}

test "guard paths: guardrails ignore case" {
    const h = "/Users/me";
    try std.testing.expect(isGuardrail("/Users/me/.SSH/id", h));
    try std.testing.expect(isGuardrail("/Users/me/.Claude/Settings.json", h));
    try std.testing.expect(isGuardrail("/Users/me/proj/.CLAUDE/settings.local.json", h));
    try std.testing.expect(isGuardrail("/applications/LOSTTY.app/x", h));
    try std.testing.expect(isWriteExempt("/TMP/x", h, null));
}

test "guard paths: a guardrail's ancestors are guardrails too" {
    const h = "/Users/me";
    try std.testing.expect(isGuardrail("/Users/me/.claude", h));
    try std.testing.expect(isGuardrail("/Users/me/.codex", h));
    try std.testing.expect(isGuardrail("/Users/me", h));
    try std.testing.expect(isGuardrail("/", h));
    try std.testing.expect(isGuardrail("/Applications", h));
    try std.testing.expect(isGuardrail("/Users/me/.config", h));
    try std.testing.expect(!isGuardrail("/Users/me/.claude/projects", h));
    try std.testing.expect(!isGuardrail("/Users/me/.claude/projects/x", h));
}

test "guard paths: write-exempt folders" {
    const h = "/Users/me";
    try std.testing.expect(isWriteExempt("/tmp/x", h, null));
    try std.testing.expect(isWriteExempt("/private/var/folders/ab/T/x", h, null));
    try std.testing.expect(isWriteExempt("/Users/me/.claude/projects/p/memory/a.md", h, null));
    try std.testing.expect(isWriteExempt("/scratch/x", h, "/scratch/"));
    try std.testing.expect(!isWriteExempt("/Users/me/notes.md", h, null));
    try std.testing.expect(!isWriteExempt("/Users/me/.claude/settings.json", h, null));
}

test "guard paths: findRepo walks up to .git without git" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("repo/.git");
    try tmp.dir.makePath("repo/a/b");
    try tmp.dir.makePath("wt/x");
    try tmp.dir.writeFile(.{ .sub_path = "wt/.git", .data = "gitdir: /elsewhere\n" });
    const base = try tmp.dir.realpathAlloc(a, ".");
    const repo = try std.fs.path.join(a, &.{ base, "repo" });
    try std.testing.expectEqualStrings(repo, findRepo(a, try std.fs.path.join(a, &.{ repo, "a", "b" })).?);
    const wt = try std.fs.path.join(a, &.{ base, "wt" });
    try std.testing.expectEqualStrings(wt, findRepo(a, try std.fs.path.join(a, &.{ wt, "x" })).?);
    // The temp folder has no .git of its own, so any repo found is a strict
    // ancestor. (It can't be asserted null: Zig's tmpDir lives under
    // <cwd>/.zig-cache, and tests run from inside a repo worktree.)
    if (findRepo(a, base)) |r| try std.testing.expect(r.len < base.len);
}
