//! Pure logic for the context handoff's hook output: what `+claude-state`
//! prints for Claude Code to add to its context. See
//! docs/superpowers/specs/2026-10-16-observer-handoff-design.md (§4, §6).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A file the Mac app keeps for a pane. Hooks take the queued texts once:
/// `say` (the handoff's directive) and `zone_say` (a zone move's note) on
/// UserPromptSubmit and PostToolUse, `start` (the handoff for the fresh
/// window) on SessionStart after /clear. `zone` (zone.zig) is read, never
/// taken: the app keeps it current. `zone_allow`, the owner's Allow Once,
/// names the one agent a SendMessage may reach outside the zone, and is
/// taken by that message.
pub const Kind = enum {
    say,
    start,
    zone_say,
    zone,
    zone_allow,

    fn suffix(kind: Kind) []const u8 {
        return switch (kind) {
            .say => "say",
            .start => "start",
            .zone_say => "zone.say",
            .zone => "zone.json",
            .zone_allow => "zone.allow",
        };
    }
};

/// Under $HOME: where the Mac app queues each pane's text.
pub const panes_dir = "Library/Application Support/Lostty/handoff/panes";

/// The most a queued text may hold; Claude caps it at 10,000 characters.
pub const text_max = 64 << 10;

/// A pane id as Lostty sets LOSTTY_SURFACE (`UUID.uuidString`): uppercase
/// hex in 8-4-4-4-12. Anything else is refused, so the variable can't
/// name another file.
pub fn isPaneId(s: []const u8) bool {
    if (s.len != 36) return false;
    for (s, 0..) |c, i| {
        if (i == 8 or i == 13 or i == 18 or i == 23) {
            if (c != '-') return false;
            continue;
        }
        if (!((c >= '0' and c <= '9') or (c >= 'A' and c <= 'F'))) return false;
    }
    return true;
}

pub fn queuedPath(alloc: Allocator, home: []const u8, pane: []const u8, kind: Kind) Allocator.Error![]u8 {
    return std.fmt.allocPrint(alloc, "{s}/{s}/{s}.{s}", .{ home, panes_dir, pane, kind.suffix() });
}

/// The non-empty `texts` as one, in order, a blank line between; null
/// when there are none.
pub fn join(alloc: Allocator, texts: []const ?[]const u8) Allocator.Error!?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (texts) |text| {
        const t = text orelse continue;
        if (t.len == 0) continue;
        if (out.items.len > 0) try out.appendSlice(alloc, "\n\n");
        try out.appendSlice(alloc, t);
    }
    return if (out.items.len == 0) null else try out.toOwnedSlice(alloc);
}

/// Claude Code's hook output that adds `text` to the model's context.
pub fn output(alloc: Allocator, event: []const u8, text: []const u8) Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(alloc, .{
        .hookSpecificOutput = .{ .hookEventName = event, .additionalContext = text },
    }, .{});
}

/// Whether a tool hook's input comes from one of Claude's subagents (it
/// names a non-empty `agent_id`): the directive is for Claude itself.
pub fn isSubagent(alloc: Allocator, input: []const u8) bool {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const id = parsed.value.object.get("agent_id") orelse return false;
    return id == .string and id.string.len > 0;
}

/// A SessionStart hook's `source` ("startup", "resume", "clear",
/// "compact" or "fork"); null for other events.
pub fn sessionSource(alloc: Allocator, input: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return null;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return null;
    const event = root.object.get("hook_event_name") orelse return null;
    if (event != .string or !std.mem.eql(u8, event.string, "SessionStart")) return null;
    const source = root.object.get("source") orelse return null;
    if (source != .string) return null;
    return alloc.dupe(u8, source.string) catch null;
}

/// Takes the file at `path` (renaming it first, so of two hooks running at
/// once only one gets it), returns its text and deletes it. Null when
/// there is none.
pub fn take(alloc: Allocator, path: []const u8) ?[]u8 {
    const taken = std.fmt.allocPrint(alloc, "{s}.taken", .{path}) catch return null;
    std.fs.renameAbsolute(path, taken) catch return null;
    defer std.fs.deleteFileAbsolute(taken) catch {};
    return std.fs.cwd().readFileAlloc(alloc, taken, text_max) catch null;
}

test "claude speak: pane ids" {
    const t = std.testing;
    try t.expect(isPaneId("0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6"));
    try t.expect(!isPaneId("0f8c2a5e-1b2c-4d3e-8f90-a1b2c3d4e5f6"));
    try t.expect(!isPaneId("../../../../etc/passwd-0000-0000-000000"));
    try t.expect(!isPaneId("0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F"));
    try t.expect(!isPaneId(""));
}

test "claude speak: queued path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings(
        "/Users/me/Library/Application Support/Lostty/handoff/panes/0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6.say",
        try queuedPath(a, "/Users/me", "0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6", .say),
    );
    try std.testing.expectEqualStrings(
        "/Users/me/Library/Application Support/Lostty/handoff/panes/0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6.zone.say",
        try queuedPath(a, "/Users/me", "0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6", .zone_say),
    );
    try std.testing.expectEqualStrings(
        "/Users/me/Library/Application Support/Lostty/handoff/panes/0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6.zone.json",
        try queuedPath(a, "/Users/me", "0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6", .zone),
    );
}

test "claude speak: texts join with a blank line, skipping missing ones" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("handoff\n\nbrief", (try join(a, &.{ "handoff", "brief" })).?);
    try std.testing.expectEqualStrings("brief", (try join(a, &.{ null, "brief" })).?);
    try std.testing.expectEqualStrings("say", (try join(a, &.{ "say", "" })).?);
    try std.testing.expect((try join(a, &.{ null, null })) == null);
}

test "claude speak: output is Claude's additionalContext JSON" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try output(a, "PostToolUse", "Hand off \"soon\"\nplease");
    try std.testing.expectEqualStrings(
        \\{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Hand off \"soon\"\nplease"}}
    , out);
}

test "claude speak: a subagent's tool call is not spoken to" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect(isSubagent(a,
        \\{"hook_event_name":"PostToolUse","agent_id":"a7","tool_name":"Read"}
    ));
    try std.testing.expect(!isSubagent(a,
        \\{"hook_event_name":"PostToolUse","tool_name":"Read"}
    ));
    try std.testing.expect(!isSubagent(a,
        \\{"hook_event_name":"PostToolUse","agent_id":"","tool_name":"Read"}
    ));
    try std.testing.expect(!isSubagent(a, "not json"));
}

test "claude speak: session source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("clear", sessionSource(a,
        \\{"hook_event_name":"SessionStart","source":"clear"}
    ).?);
    try std.testing.expect(sessionSource(a,
        \\{"hook_event_name":"Stop","source":"clear"}
    ) == null);
    try std.testing.expect(sessionSource(a, "{}") == null);
}

test "claude speak: take is once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "P.say", .data = "the directive" });
    const dir = try tmp.dir.realpathAlloc(a, ".");
    const path = try std.fmt.allocPrint(a, "{s}/P.say", .{dir});
    try std.testing.expectEqualStrings("the directive", take(a, path).?);
    try std.testing.expect(take(a, path) == null);
    // Nothing left behind.
    try std.testing.expectError(error.FileNotFound, tmp.dir.access("P.say.taken", .{}));
}
