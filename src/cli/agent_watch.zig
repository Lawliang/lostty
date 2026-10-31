const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const feed = @import("claude/feed.zig");

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

/// The `agent-watch` command follows a Claude Code subagent as it works:
/// `lostty +agent-watch <transcript>`, the subagent's
/// `…/subagents/agent-<id>.jsonl`. It prints one line a step (what each
/// tool call does, a failed call, the subagent's own words, "Done" when
/// it finishes) and keeps following until you close the pane, as the
/// parent can send the subagent more work. It only reads: the subagent
/// runs inside its parent's Claude, and this costs next to nothing while
/// it waits for the file to grow.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const argv = try std.process.argsAlloc(alloc);
    const stderr = std.fs.File.stderr();
    const path = pathFromArgs(argv) orelse {
        try stderr.writeAll("Usage: lostty +agent-watch <subagent transcript .jsonl>\n");
        return 1;
    };
    const stdout = std.fs.File.stdout();

    var out: std.ArrayList(u8) = .empty;
    const meta = if (metaPath(alloc, path)) |meta_path|
        std.fs.cwd().readFileAlloc(alloc, meta_path, 64 * 1024) catch null
    else |_|
        null;
    try feed.header(alloc, &out, meta);
    try stdout.writeAll(out.items);

    // The subagent may not have written its first line yet.
    const file = while (true) {
        break std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.Thread.sleep(250 * std.time.ns_per_ms);
                continue;
            },
            else => {
                try stderr.writeAll("lostty +agent-watch: can't read that transcript\n");
                return 1;
            },
        };
    };
    defer file.close();
    try feed.follow(gpa, file, stdout);
    return 0;
}

/// The transcript in `lostty +agent-watch <path>`.
fn pathFromArgs(argv: []const []const u8) ?[]const u8 {
    for (argv, 0..) |arg, i| {
        if (!std.mem.eql(u8, arg, "+agent-watch")) continue;
        var j = i + 1;
        if (j < argv.len and std.mem.eql(u8, argv[j], "--")) j += 1;
        return if (j < argv.len) argv[j] else null;
    }
    return null;
}

/// `agent-<id>.jsonl` → `agent-<id>.meta.json`, beside it.
fn metaPath(alloc: Allocator, path: []const u8) ![]const u8 {
    const stem = if (std.mem.endsWith(u8, path, ".jsonl")) path[0 .. path.len - ".jsonl".len] else return error.NotATranscript;
    return std.fmt.allocPrint(alloc, "{s}.meta.json", .{stem});
}

test "agent-watch: the transcript comes after the command" {
    try std.testing.expectEqualStrings("/t/agent-a1.jsonl", pathFromArgs(&.{ "lostty", "+agent-watch", "/t/agent-a1.jsonl" }).?);
    try std.testing.expectEqualStrings("-odd.jsonl", pathFromArgs(&.{ "lostty", "+agent-watch", "--", "-odd.jsonl" }).?);
    try std.testing.expect(pathFromArgs(&.{ "lostty", "+agent-watch" }) == null);
}

test "agent-watch: the meta file sits beside the transcript" {
    const alloc = std.testing.allocator;
    const meta = try metaPath(alloc, "/s/subagents/agent-a1.jsonl");
    defer alloc.free(meta);
    try std.testing.expectEqualStrings("/s/subagents/agent-a1.meta.json", meta);
    try std.testing.expectError(error.NotATranscript, metaPath(alloc, "/s/notes.txt"));
}

test {
    _ = @import("claude/feed.zig");
}
