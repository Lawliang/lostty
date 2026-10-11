//! Tests for lostty-tmux.zsh (src/shell-integration/lostty-tmux/zsh/). They
//! run the snippet in a real zsh, which macOS always has; elsewhere they
//! skip.

const std = @import("std");
const snippet = @embedFile("../../shell-integration/lostty-tmux/zsh/lostty-tmux.zsh");

/// An OSC body as the snippet sends it: in tmux's DCS passthrough, with the
/// OSC's ESC doubled.
fn wrapped(comptime body: []const u8) []const u8 {
    return "\x1bPtmux;\x1b\x1b]" ++ body ++ "\x07\x1b\\";
}

/// Runs `script` in zsh right after the snippet and returns stdout.
fn runZsh(alloc: std.mem.Allocator, script: []const u8, cwd: ?[]const u8, in_lostty_tmux: bool, git_ceiling: ?[]const u8) ![]u8 {
    std.fs.accessAbsolute("/bin/zsh", .{}) catch return error.SkipZigTest;
    var env = std.process.EnvMap.init(alloc);
    defer env.deinit();
    try env.put("PATH", "/usr/bin:/bin");
    try env.put("HOME", "/nonexistent");
    // Test temp dirs live inside this repo's .zig-cache; keep git from
    // finding the repo above them.
    if (git_ceiling) |c| try env.put("GIT_CEILING_DIRECTORIES", c);
    if (in_lostty_tmux) {
        try env.put("LOSTTY_TMUX", "1");
        try env.put("TMUX", "/private/tmp/tmux-test/lostty,1,0");
    }
    const full = try std.mem.concat(alloc, u8, &.{ snippet, "\n", script });
    defer alloc.free(full);
    const result = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "/bin/zsh", "-f", "-c", full },
        .env_map = &env,
        .cwd = cwd,
    });
    alloc.free(result.stderr);
    return result.stdout;
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

fn base64Alloc(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    const enc = std.base64.standard.Encoder;
    const out = try alloc.alloc(u8, enc.calcSize(s.len));
    _ = enc.encode(out, s);
    return out;
}

test "lostty tmux snippet: wraps an OSC in tmux passthrough with ESC doubled" {
    const alloc = std.testing.allocator;
    const out = try runZsh(alloc, "_lostty_osc '133;C'", null, true, null);
    defer alloc.free(out);
    try std.testing.expectEqualStrings(wrapped("133;C"), out);
}

test "lostty tmux snippet: does nothing outside Lostty's tmux" {
    const alloc = std.testing.allocator;
    const out = try runZsh(alloc, "print -n after", null, false, null);
    defer alloc.free(out);
    try std.testing.expectEqualStrings("", out);
}

test "lostty tmux snippet: reports the exit status only after a command ran" {
    const alloc = std.testing.allocator;
    const out = try runZsh(alloc, "_lostty_precmd; print -n '|'; _lostty_preexec; (exit 3); _lostty_precmd", null, true, null);
    defer alloc.free(out);
    const bar = std.mem.indexOfScalar(u8, out, '|').?;
    try std.testing.expect(!contains(out[0..bar], "133;D"));
    try std.testing.expect(contains(out[bar..], wrapped("133;C")));
    try std.testing.expect(contains(out[bar..], wrapped("133;D;3")));
    // Never prompt marks: Ghostty does a fresh-line on them, which would
    // move its cursor behind tmux's back.
    try std.testing.expect(!contains(out, "133;A"));
    try std.testing.expect(!contains(out, "133;B"));
    try std.testing.expect(!contains(out, "133;P"));
}

test "lostty tmux snippet: reports cwd and project for a path with spaces" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makeDir("my proj");
    const dir = try tmp.dir.realpathAlloc(alloc, "my proj");
    defer alloc.free(dir);

    const out = try runZsh(alloc, "_lostty_precmd", dir, true, std.fs.path.dirname(std.fs.path.dirname(dir).?));
    defer alloc.free(out);
    try std.testing.expect(contains(out, "]7;kitty-shell-cwd://"));
    try std.testing.expect(contains(out, "/my proj\x07"));
    // Not a git repo: the project is the directory itself.
    const b64 = try base64Alloc(alloc, dir);
    defer alloc.free(b64);
    const want = try std.fmt.allocPrint(alloc, "]1337;SetUserVar=LOSTTY_PROJECT={s}\x07", .{b64});
    defer alloc.free(want);
    try std.testing.expect(contains(out, want));
}

test "lostty tmux snippet: the project is the git root" {
    const alloc = std.testing.allocator;
    std.fs.accessAbsolute("/usr/bin/git", .{}) catch return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("repo/sub");
    const root = try tmp.dir.realpathAlloc(alloc, "repo");
    defer alloc.free(root);
    const sub = try tmp.dir.realpathAlloc(alloc, "repo/sub");
    defer alloc.free(sub);
    const init = try std.process.Child.run(.{ .allocator = alloc, .argv = &.{ "/usr/bin/git", "init", "-q" }, .cwd = root });
    alloc.free(init.stdout);
    alloc.free(init.stderr);

    const out = try runZsh(alloc, "_lostty_precmd", sub, true, null);
    defer alloc.free(out);
    const b64 = try base64Alloc(alloc, root);
    defer alloc.free(b64);
    const want = try std.fmt.allocPrint(alloc, "LOSTTY_PROJECT={s}\x07", .{b64});
    defer alloc.free(want);
    try std.testing.expect(contains(out, want));
}
