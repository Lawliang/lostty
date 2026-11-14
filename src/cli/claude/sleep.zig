//! Pure logic for the Claude sessions Lostty put to sleep: the app quits
//! an idle card's Claude and lists it in `handoff/sleeping.json` until it
//! wakes. A SendMessage to one would fail, as its session is gone, so the
//! hook denies it and the app wakes the agent and passes the message on.

const std = @import("std");
const Allocator = std.mem.Allocator;
const zone = @import("zone.zig");

pub const path = "Library/Application Support/Lostty/handoff/sleeping.json";

/// A sleeping Claude, as the app lists it (`SleepingAgent`).
pub const Sleeper = struct {
    /// The pane it sleeps in, a `LOSTTY_SURFACE` id.
    pane: []const u8,
    sessionId: []const u8,
    /// The name its peers message it by.
    name: []const u8,
    /// The tmux session showing its pane.
    tmux: []const u8,
    folder: []const u8,
};

/// The app's list; none when `json` isn't one.
pub fn parse(alloc: Allocator, json: []const u8) []const Sleeper {
    return std.json.parseFromSliceLeaky([]const Sleeper, alloc, json, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch &.{};
}

/// `agents` and the sleepers, as zone.decide sees them: a sleeper sits in
/// its tmux session and started in its folder.
pub fn withSleepers(alloc: Allocator, agents: []const zone.Agent, sleepers: []const Sleeper) Allocator.Error![]const zone.Agent {
    var all: std.ArrayList(zone.Agent) = .empty;
    try all.appendSlice(alloc, agents);
    for (sleepers) |s| try all.append(alloc, .{ .name = s.name, .tmux = s.tmux, .sessionId = s.sessionId, .cwd = s.folder });
    return all.items;
}

/// The sleeper a message to `to` is for; none while a running session has
/// that name.
pub fn find(to: []const u8, sleepers: []const Sleeper, agents: []const zone.Agent) ?Sleeper {
    for (agents) |agent| if (std.mem.eql(u8, agent.name, to)) return null;
    for (sleepers) |s| if (std.mem.eql(u8, s.name, to)) return s;
    return null;
}

/// The text of a PreToolUse hook's SendMessage (`tool_input.message`, else
/// `content`); null when it isn't text.
pub fn message(root: std.json.Value) ?[]const u8 {
    if (root != .object) return null;
    const tool_input = root.object.get("tool_input") orelse return null;
    if (tool_input != .object) return null;
    for ([_][]const u8{ "message", "content" }) |key| {
        const value = tool_input.object.get(key) orelse continue;
        if (value == .string and std.mem.trim(u8, value.string, " \t\r\n").len > 0) return value.string;
    }
    return null;
}

/// The name of the session `session_id` is, among `agents`.
pub fn sender(agents: []const zone.Agent, session_id: ?[]const u8) ?[]const u8 {
    const id = session_id orelse return null;
    for (agents) |agent| if (agent.sessionId) |s| if (std.mem.eql(u8, s, id)) return agent.name;
    return null;
}

/// What Claude reads when its message to sleeping `to` is held: `passed`
/// when Lostty has the text to pass on, else too long to carry.
pub fn reason(alloc: Allocator, to: []const u8, passed: bool) Allocator.Error![]const u8 {
    return if (passed)
        std.fmt.allocPrint(alloc, "Lostty: {s} is asleep. Lostty is waking it and will pass your message on; " ++
            "don't resend.", .{to})
    else
        std.fmt.allocPrint(alloc, "Lostty: {s} is asleep. Lostty is waking it, but your message is too long " ++
            "to pass on: send it again in a minute, once it's up.", .{to});
}

const testing = std.testing;

const parseInput = @import("protocol.zig").parseInput;

test "claude sleep: the app's list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const list = parse(a,
        \\[{"pane":"0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6","sessionId":"s1","name":"wt-17-4c","tmux":"lostty-3","folder":"\/Users\/me\/My Repo"}]
    );
    try testing.expectEqual(@as(usize, 1), list.len);
    try testing.expectEqualStrings("wt-17-4c", list[0].name);
    try testing.expectEqualStrings("/Users/me/My Repo", list[0].folder);
    try testing.expectEqual(@as(usize, 0), parse(a, "[]").len);
    try testing.expectEqual(@as(usize, 0), parse(a, "not json").len);
    try testing.expectEqual(@as(usize, 0), parse(a,
        \\[{"pane":"x"}]
    ).len);
}

test "claude sleep: a sleeper is in its zone, and out of others" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const members = [_][]const u8{ "tb-1", "tb-2" };
    const awake = [_]zone.Agent{.{ .name = "inside", .tmux = "tb-1:@1.%1" }};
    const sleepers = [_]Sleeper{
        .{ .pane = "P1", .sessionId = "s1", .name = "dozing", .tmux = "tb-2", .folder = "/t" },
        .{ .pane = "P2", .sessionId = "s2", .name = "far", .tmux = "web", .folder = "/web" },
    };
    const all = try withSleepers(a, &awake, &sleepers);
    try testing.expectEqual(zone.Decision.allow, zone.decide("dozing", &members, all, &.{}));
    try testing.expectEqual(zone.Decision.deny, zone.decide("far", &members, all, &.{}));
    try testing.expectEqual(zone.Decision.allow, zone.decide("inside", &members, all, &.{}));
}

test "claude sleep: a message for a sleeper, unless a running session has its name" {
    const sleepers = [_]Sleeper{.{ .pane = "P1", .sessionId = "s1", .name = "dozing", .tmux = "tb-2", .folder = "/t" }};
    try testing.expectEqualStrings("P1", find("dozing", &sleepers, &.{}).?.pane);
    try testing.expect(find("other", &sleepers, &.{}) == null);
    const awake = [_]zone.Agent{.{ .name = "dozing", .tmux = "tb-2:@1.%1" }};
    try testing.expect(find("dozing", &sleepers, &awake) == null);
}

test "claude sleep: the message's text and its sender" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("hello", message(parseInput(a,
        \\{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"SendMessage","tool_input":{"to":"x","message":"hello","content":"other"}}
    )).?);
    try testing.expectEqualStrings("hi", message(parseInput(a,
        \\{"tool_input":{"recipient":"x","content":"hi"}}
    )).?);
    try testing.expect(message(parseInput(a,
        \\{"tool_input":{"to":"x","message":{"type":"shutdown_request"}}}
    )) == null);
    try testing.expect(message(parseInput(a,
        \\{"tool_input":{"to":"x","message":"  "}}
    )) == null);
    try testing.expect(message(parseInput(a, "not json")) == null);
    const agents = [_]zone.Agent{ .{ .name = "me", .sessionId = "s" }, .{ .name = "you", .sessionId = "t" } };
    try testing.expectEqualStrings("me", sender(&agents, "s").?);
    try testing.expect(sender(&agents, "u") == null);
    try testing.expect(sender(&agents, null) == null);
}

test "claude sleep: the deny says Lostty passes it on, or why it can't" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings(
        "Lostty: wt-17-4c is asleep. Lostty is waking it and will pass your message on; don't resend.",
        try reason(arena.allocator(), "wt-17-4c", true),
    );
    try testing.expect(std.mem.indexOf(u8, try reason(arena.allocator(), "wt-17-4c", false), "send it again") != null);
}
