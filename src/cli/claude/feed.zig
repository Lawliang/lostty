//! Lostty: a Claude Code subagent's transcript as `+agent-watch` shows it,
//! one step to a line. The transcript is Claude Code's own JSONL (one
//! event a line, appended as the subagent works); its format isn't a
//! documented API, so lines this doesn't know show nothing rather than
//! fail.
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const protocol = @import("protocol.zig");

const bold = "\x1b[1m";
const dim = "\x1b[2m";
const cyan = "\x1b[36m";
const green = "\x1b[32m";
const red = "\x1b[31m";
const reset = "\x1b[0m";

/// How many lines of the subagent's brief show; the rest is cut.
pub const prompt_lines = 6;

/// The feed's first line, from the `agent-<id>.meta.json` beside the
/// transcript: "Explore · Find facts for step 2 · sonnet", or "Subagent"
/// without one. Also sets the pane's title to the description.
pub fn header(alloc: Allocator, out: *std.ArrayList(u8), meta: ?[]const u8) Allocator.Error!void {
    const parsed = if (meta) |m| std.json.parseFromSlice(std.json.Value, alloc, m, .{}) catch null else null;
    defer if (parsed) |p| p.deinit();
    const root: std.json.Value = if (parsed) |p| p.value else .null;
    const kind = text(root, "agentType") orelse "Subagent";
    const description = text(root, "description");
    if (description) |d| try out.print(alloc, "\x1b]2;{s}\x07", .{try protocol.clean(alloc, d)});
    try out.print(alloc, bold ++ "{s}" ++ reset, .{try printable(alloc, kind)});
    if (description) |d| try out.print(alloc, " · {s}", .{try printable(alloc, d)});
    if (text(root, "model")) |model| try out.print(alloc, dim ++ " · {s}" ++ reset, .{try printable(alloc, model)});
    try out.appendSlice(alloc, "\n\n");
}

/// One transcript line as the feed shows it, appended to `out`: the
/// brief (dimmed, cut to `prompt_lines`), a message from the parent, what
/// each tool call does, a failed call's first line, the subagent's own
/// words, and "Done" when it ends its turn. Thinking and Claude Code's
/// bookkeeping show nothing.
pub fn render(alloc: Allocator, out: *std.ArrayList(u8), line: []const u8) Allocator.Error!void {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, line, .{}) catch return;
    defer parsed.deinit();
    const root = parsed.value;
    const kind = text(root, "type") orelse return;
    const message = field(root, "message") orelse return;
    const content = field(message, "content") orelse return;
    if (std.mem.eql(u8, kind, "user")) {
        // The first line is the brief; a later one is the parent's follow-up.
        const first = (field(root, "parentUuid") orelse std.json.Value.null) == .null;
        if (content == .string) return words(alloc, out, content.string, first);
        if (content != .array) return;
        for (content.array.items) |block| {
            const block_type = text(block, "type") orelse continue;
            if (std.mem.eql(u8, block_type, "text")) {
                if (text(block, "text")) |t| try words(alloc, out, t, first);
            } else if (std.mem.eql(u8, block_type, "tool_result")) {
                const failed = field(block, "is_error") orelse continue;
                if (failed != .bool or !failed.bool) continue;
                const result = resultText(field(block, "content") orelse continue) orelse "failed";
                try out.print(alloc, red ++ "  ✗ {s}" ++ reset ++ "\n", .{try protocol.clean(alloc, firstLine(result))});
            }
        }
    } else if (std.mem.eql(u8, kind, "assistant")) {
        if (content != .array) return;
        for (content.array.items) |block| {
            const block_type = text(block, "type") orelse continue;
            if (std.mem.eql(u8, block_type, "tool_use")) {
                const name = text(block, "name") orelse continue;
                // Its report, handed back through a tool (Claude Code 2.1.271+).
                if (std.mem.eql(u8, name, "SubagentHandback")) {
                    if (text(field(block, "input") orelse continue, "message")) |report|
                        try out.print(alloc, "\n{s}\n\n", .{try printable(alloc, report)});
                    continue;
                }
                const action = protocol.toolAction(alloc, name, field(block, "input") orelse .null) orelse name;
                try out.print(alloc, cyan ++ "▸" ++ reset ++ " {s}\n", .{action});
            } else if (std.mem.eql(u8, block_type, "text")) {
                const t = text(block, "text") orelse continue;
                try out.print(alloc, "\n{s}\n\n", .{try printable(alloc, t)});
            }
        }
        const stop = text(message, "stop_reason") orelse return;
        if (std.mem.eql(u8, stop, "end_turn")) try out.appendSlice(alloc, green ++ "✓ Done" ++ reset ++ "\n");
    }
}

/// Shows each line of `file` as it's written, from the start, to `out`,
/// until the process is stopped. Each line gets its own arena; `pending`
/// holds a line not yet whole.
pub fn follow(gpa: Allocator, file: std.fs.File, out: std.fs.File) !void {
    var waiter = Waiter.init(file);
    defer waiter.deinit();
    var line_arena = std.heap.ArenaAllocator.init(gpa);
    defer line_arena.deinit();
    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(gpa);
    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = file.read(&buf) catch 0;
        if (n == 0) {
            waiter.wait();
            continue;
        }
        try pending.appendSlice(gpa, buf[0..n]);
        var start: usize = 0;
        while (std.mem.indexOfScalarPos(u8, pending.items, start, '\n')) |end| : (start = end + 1) {
            _ = line_arena.reset(.retain_capacity);
            var shown: std.ArrayList(u8) = .empty;
            try render(line_arena.allocator(), &shown, pending.items[start..end]);
            if (shown.items.len > 0) try out.writeAll(shown.items);
        }
        pending.replaceRangeAssumeCapacity(0, start, &.{});
    }
}

/// Waits for the transcript to grow: on macOS with kqueue, so a quiet
/// subagent costs no CPU; elsewhere, or if kqueue fails, by checking
/// twice a second.
const Waiter = struct {
    kq: ?i32,

    const darwin = builtin.os.tag.isDarwin();

    fn init(file: std.fs.File) Waiter {
        if (comptime !darwin) return .{ .kq = null };
        const kq = std.posix.kqueue() catch return .{ .kq = null };
        const change = std.posix.Kevent{
            .ident = @intCast(file.handle),
            .filter = std.c.EVFILT.VNODE,
            .flags = std.c.EV.ADD | std.c.EV.CLEAR,
            .fflags = std.c.NOTE.WRITE | std.c.NOTE.EXTEND,
            .data = 0,
            .udata = 0,
        };
        _ = std.posix.kevent(kq, &.{change}, &.{}, null) catch {
            std.posix.close(kq);
            return .{ .kq = null };
        };
        return .{ .kq = kq };
    }

    fn deinit(self: Waiter) void {
        if (self.kq) |kq| std.posix.close(kq);
    }

    fn wait(self: Waiter) void {
        if (comptime darwin) if (self.kq) |kq| {
            // The timeout is only a backstop for a missed wake.
            var events: [1]std.posix.Kevent = undefined;
            const timeout = std.posix.timespec{ .sec = 5, .nsec = 0 };
            _ = std.posix.kevent(kq, &.{}, &events, &timeout) catch {};
            return;
        };
        std.Thread.sleep(500 * std.time.ns_per_ms);
    }
};

/// The brief, dimmed and cut to `prompt_lines`, or a message from the
/// parent.
fn words(alloc: Allocator, out: *std.ArrayList(u8), t: []const u8, brief: bool) Allocator.Error!void {
    const trimmed = std.mem.trim(u8, t, " \t\r\n");
    if (trimmed.len == 0) return;
    if (!brief) return out.print(alloc, "\n" ++ bold ++ "↳ From Claude:" ++ reset ++ " {s}\n\n", .{try printable(alloc, trimmed)});
    var lines = std.mem.splitScalar(u8, trimmed, '\n');
    var shown: usize = 0;
    try out.appendSlice(alloc, dim);
    while (lines.next()) |l| : (shown += 1) {
        if (shown == prompt_lines) {
            try out.appendSlice(alloc, "…\n");
            break;
        }
        try out.print(alloc, "{s}\n", .{try printable(alloc, l)});
    }
    try out.appendSlice(alloc, reset ++ "\n");
}

/// `t` trimmed, with control characters but newlines and tabs dropped: the
/// transcript holds whatever the subagent read, and an escape sequence in
/// it must not reach the terminal.
fn printable(alloc: Allocator, t: []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (std.mem.trim(u8, t, " \t\r\n")) |c| {
        if ((c < ' ' and c != '\n' and c != '\t') or c == 0x7f) continue;
        try out.append(alloc, c);
    }
    return out.toOwnedSlice(alloc);
}

/// A tool result's text: a string, or its first text block.
fn resultText(content: std.json.Value) ?[]const u8 {
    if (content == .string) return content.string;
    if (content != .array) return null;
    for (content.array.items) |block| if (text(block, "text")) |t| return t;
    return null;
}

fn firstLine(t: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, t, " \t\r\n");
    return trimmed[0 .. std.mem.indexOfScalar(u8, trimmed, '\n') orelse trimmed.len];
}

fn field(object: std.json.Value, key: []const u8) ?std.json.Value {
    if (object != .object) return null;
    return object.object.get(key);
}

fn text(object: std.json.Value, key: []const u8) ?[]const u8 {
    const value = field(object, key) orelse return null;
    return if (value == .string) value.string else null;
}

fn rendered(alloc: Allocator, line: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try render(alloc, &out, line);
    return out.toOwnedSlice(alloc);
}

test "agent feed: the brief shows dimmed, cut after a few lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try std.testing.expectEqualStrings(dim ++ "Map how updates work.\nBe brief.\n" ++ reset ++ "\n", try rendered(alloc,
        \\{"parentUuid":null,"type":"user","message":{"role":"user","content":"Map how updates work.\nBe brief.\n"}}
    ));
    try std.testing.expectEqualStrings(dim ++ "1\n2\n3\n4\n5\n6\n…\n" ++ reset ++ "\n", try rendered(alloc,
        \\{"parentUuid":null,"type":"user","message":{"content":"1\n2\n3\n4\n5\n6\n7\n8"}}
    ));
}

test "agent feed: a later message is the parent's" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try std.testing.expectEqualStrings("\n" ++ bold ++ "↳ From Claude:" ++ reset ++ " Also check the phone.\n\n", try rendered(alloc,
        \\{"parentUuid":"u1","type":"user","message":{"content":[{"type":"text","text":"Also check the phone."}]}}
    ));
}

test "agent feed: tool calls are worded as the trace words them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try std.testing.expectEqualStrings(cyan ++ "▸" ++ reset ++ " Reading CanvasDrop.swift\n" ++ cyan ++ "▸" ++ reset ++ " Run the drop tests\n", try rendered(alloc,
        \\{"parentUuid":"u1","type":"assistant","message":{"content":[
        \\{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a/CanvasDrop.swift"}},
        \\{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"secret=1 make","description":"Run the drop tests"}}],"stop_reason":"tool_use"}}
    ));
}

test "agent feed: only failed results show, by their first line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try std.testing.expectEqualStrings("", try rendered(alloc,
        \\{"parentUuid":"u1","type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok","is_error":false}]}}
    ));
    try std.testing.expectEqualStrings(red ++ "  ✗ Exit code 1" ++ reset ++ "\n", try rendered(alloc,
        \\{"parentUuid":"u1","type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"Exit code 1\nmore"}],"is_error":true}]}}
    ));
}

test "agent feed: its own words, then Done when it ends its turn" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try std.testing.expectEqualStrings("\nFound all seven.\n\n" ++ green ++ "✓ Done" ++ reset ++ "\n", try rendered(alloc,
        \\{"parentUuid":"u1","type":"assistant","message":{"content":[{"type":"text","text":"Found all seven.\n"}],"stop_reason":"end_turn"}}
    ));
}

test "agent feed: thinking, bookkeeping and junk show nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    for ([_][]const u8{
        \\{"parentUuid":"u1","type":"assistant","message":{"content":[{"type":"thinking","thinking":"","signature":"x"}]}}
        ,
        \\{"type":"attachment","attachment":{"type":"skill_listing"}}
        ,
        \\{"type":"api-request-blob","message":{"content":[{"type":"text","text":"raw"}]}}
        ,
        "not json",
        "[]",
    }) |line| try std.testing.expectEqualStrings("", try rendered(alloc, line));
}

test "agent feed: the header names the agent, its task and model" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var out: std.ArrayList(u8) = .empty;
    try header(alloc, &out,
        \\{"agentType":"Explore","description":"Find facts for step 2","model":"sonnet"}
    );
    try std.testing.expectEqualStrings("\x1b]2;Find facts for step 2\x07" ++ bold ++ "Explore" ++ reset ++
        " · Find facts for step 2" ++ dim ++ " · sonnet" ++ reset ++ "\n\n", out.items);
    out.clearRetainingCapacity();
    try header(alloc, &out, null);
    try std.testing.expectEqualStrings(bold ++ "Subagent" ++ reset ++ "\n\n", out.items);
}

test "agent feed: a report handed back through a tool shows as its words" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try std.testing.expectEqualStrings("\nAll three found.\n\n", try rendered(alloc,
        \\{"parentUuid":"u1","type":"assistant","message":{"content":[{"type":"tool_use","name":"SubagentHandback","input":{"message":"All three found."}}]}}
    ));
}

test "agent feed: escape sequences in what it read don't reach the terminal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try std.testing.expectEqualStrings("\nok ]2;evilbye\n\tdone\n\n", try rendered(alloc,
        \\{"parentUuid":"u1","type":"assistant","message":{"content":[{"type":"text","text":"ok \u001b]2;evil\u0007bye\n\tdone"}]}}
    ));
}
