//! Pure logic for a pane's zone file, `<PANE>.zone.json` beside the
//! context handoff's queue: the Mac app rewrites it whenever the pane's
//! zone changes and deletes it when the pane leaves every zone. See
//! docs/superpowers/specs/2026-10-24-lostty-zones-design.md (§5, §7).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// The SessionStart sources that start Claude without the zone's brief in
/// its context. `resume` and `fork` carry the conversation that had it.
pub fn briefsAt(source: []const u8) bool {
    for ([_][]const u8{ "startup", "clear", "compact" }) |s| {
        if (std.mem.eql(u8, source, s)) return true;
    }
    return false;
}

/// What the app writes in a pane's zone file.
pub const File = struct {
    /// The brief a new Claude session in the zone starts with.
    start: ?[]const u8 = null,
    /// The zone's title: "Textberry › Onboarding" for a domain.
    zone: ?[]const u8 = null,
    /// The tmux sessions (on the `lostty` socket) of every pane in the
    /// project zone, its domains included. Null in a file from an app
    /// that didn't write them: then nothing is kept inside.
    members: ?[]const []const u8 = null,
};

/// The zone file `json`; null when it isn't one. An empty `start` is none.
pub fn parse(alloc: Allocator, json: []const u8) ?File {
    var file = std.json.parseFromSliceLeaky(File, alloc, json, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch return null;
    if (file.start) |s| if (s.len == 0) {
        file.start = null;
    };
    return file;
}

/// The project a zone title names: "Textberry" of "Textberry › Onboarding".
pub fn project(title: []const u8) []const u8 {
    const end = std.mem.indexOf(u8, title, " › ") orelse title.len;
    return title[0..end];
}

/// A Claude Code session, as its `~/.claude/sessions/<pid>.json` names it.
pub const Agent = struct {
    /// What ListAgents shows, and what SendMessage's `to` names.
    name: []const u8,
    /// Where it runs in tmux, `session:@window.%pane`; null outside tmux.
    tmux: ?[]const u8 = null,
    sessionId: ?[]const u8 = null,
};

/// A session file's agent; null without a name.
pub fn parseAgent(alloc: Allocator, json: []const u8) ?Agent {
    const agent = std.json.parseFromSliceLeaky(Agent, alloc, json, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch return null;
    return if (agent.name.len == 0) null else agent;
}

/// The agent a PreToolUse hook's SendMessage is for (`tool_input.to`, else
/// `recipient`), its ` [ref]` left off; null for any other tool call.
pub fn sendTarget(alloc: Allocator, input: []const u8) ?[]const u8 {
    const Input = struct {
        hook_event_name: []const u8 = "",
        tool_name: []const u8 = "",
        tool_input: struct { to: ?[]const u8 = null, recipient: ?[]const u8 = null } = .{},
    };
    const parsed = std.json.parseFromSliceLeaky(Input, alloc, input, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch return null;
    if (!std.mem.eql(u8, parsed.hook_event_name, "PreToolUse")) return null;
    if (!std.mem.eql(u8, parsed.tool_name, "SendMessage")) return null;
    const to = target(parsed.tool_input.to orelse parsed.tool_input.recipient orelse return null);
    return if (to.len == 0) null else to;
}

/// "name [3fa9c1]" → "name": SendMessage's docs allow a ref after the name.
pub fn target(to: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, to, " ");
    if (!std.mem.endsWith(u8, trimmed, "]")) return trimmed;
    const open = std.mem.lastIndexOf(u8, trimmed, " [") orelse return trimmed;
    return std.mem.trimRight(u8, trimmed[0..open], " ");
}

/// Whether `location` (`session:@window.%pane`) is in a member session.
fn isMember(members: []const []const u8, location: ?[]const u8) bool {
    const loc = location orelse return false;
    const session = loc[0 .. std.mem.indexOfScalar(u8, loc, ':') orelse loc.len];
    for (members) |m| if (std.mem.eql(u8, m, session)) return true;
    return false;
}

pub const Decision = enum { allow, deny };

/// Whether a message to `to` stays inside the zone. `main` and names no
/// session file has (subagents, teammates, agent ids) stay inside Claude.
/// A named session is inside when it runs in a member tmux session; one
/// outside tmux is outside.
pub fn decide(to: []const u8, members: []const []const u8, agents: []const Agent) Decision {
    if (std.mem.eql(u8, to, "main")) return .allow;
    var named = false;
    for (agents) |agent| {
        if (!std.mem.eql(u8, agent.name, to)) continue;
        if (isMember(members, agent.tmux)) return .allow;
        named = true;
    }
    return if (named) .deny else .allow;
}

/// Whether the owner's Allow Once (`<PANE>.zone.allow`'s text) names `to`.
pub fn allows(allowance: []const u8, to: []const u8) bool {
    return std.mem.eql(u8, std.mem.trim(u8, allowance, " \t\r\n"), to);
}

/// What Claude reads when a message to `to` is kept inside zone `title`.
pub fn denyReason(alloc: Allocator, to: []const u8, title: ?[]const u8) Allocator.Error![]const u8 {
    const name = if (title) |t| project(t) else "this zone";
    return std.fmt.allocPrint(alloc, "Lostty zone: {s} is outside zone {s}, so this message was kept inside. " ++
        "The owner can press Allow Once on the canvas, and you'll be told when you may retry.", .{ to, name });
}

/// The names of the zone's other agents, sorted, each once: sessions in a
/// member tmux session that aren't `session_id` or in tmux pane `pane`
/// (`%12`, as TMUX_PANE has it).
pub fn others(
    alloc: Allocator,
    members: []const []const u8,
    agents: []const Agent,
    session_id: ?[]const u8,
    pane: ?[]const u8,
) Allocator.Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (agents) |agent| {
        if (!isMember(members, agent.tmux)) continue;
        if (session_id) |id| if (agent.sessionId) |s| if (std.mem.eql(u8, s, id)) continue;
        if (pane) |p| if (std.mem.endsWith(u8, agent.tmux.?, p)) continue;
        for (names.items) |n| {
            if (std.mem.eql(u8, n, agent.name)) break;
        } else try names.append(alloc, agent.name);
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return names.items;
}

/// The brief's line naming the zone's other agents; null when none.
pub fn othersLine(alloc: Allocator, names: []const []const u8) Allocator.Error!?[]const u8 {
    if (names.len == 0) return null;
    const list = try std.mem.join(alloc, ", ", names);
    return try std.fmt.allocPrint(alloc, "Other agents in this zone: {s}.", .{list});
}

/// A hook input's `session_id`.
pub fn sessionId(alloc: Allocator, input: []const u8) ?[]const u8 {
    const Input = struct { session_id: ?[]const u8 = null };
    const parsed = std.json.parseFromSliceLeaky(Input, alloc, input, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch return null;
    return parsed.session_id;
}

const testing = std.testing;

test "claude zone: the file's brief, title and members" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const file = parse(a,
        \\{"start":"Lostty zone: Textberry (~/t).\nTextberry: an app","zone":"Textberry › Onboarding","folder":null,"members":["tb-1","tb-2"]}
    ).?;
    try testing.expectEqualStrings("Lostty zone: Textberry (~/t).\nTextberry: an app", file.start.?);
    try testing.expectEqualStrings("Textberry › Onboarding", file.zone.?);
    try testing.expectEqual(@as(usize, 2), file.members.?.len);
    try testing.expectEqualStrings("tb-2", file.members.?[1]);
    try testing.expect(parse(a,
        \\{"zone":"Textberry"}
    ).?.members == null);
    try testing.expect(parse(a,
        \\{"start":""}
    ).?.start == null);
    try testing.expect(parse(a,
        \\{"start":7}
    ) == null);
    try testing.expect(parse(a, "not json") == null);
}

test "claude zone: which sources get the brief" {
    try testing.expect(briefsAt("startup"));
    try testing.expect(briefsAt("clear"));
    try testing.expect(briefsAt("compact"));
    try testing.expect(!briefsAt("resume"));
    try testing.expect(!briefsAt("fork"));
}

test "claude zone: a domain's project" {
    try testing.expectEqualStrings("Textberry", project("Textberry › Onboarding"));
    try testing.expectEqualStrings("Textberry", project("Textberry"));
}

test "claude zone: SendMessage's target without its ref" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("lostty-a9", sendTarget(a,
        \\{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"SendMessage","tool_input":{"to":"lostty-a9 [3fa9c1]","summary":"x","message":"y","type":"message","recipient":"lostty-a9 [3fa9c1]","recipient_kind":"name","content":"y"},"tool_use_id":"t"}
    ).?);
    try testing.expectEqualStrings("main", sendTarget(a,
        \\{"hook_event_name":"PreToolUse","tool_name":"SendMessage","tool_input":{"recipient":"main"}}
    ).?);
    try testing.expect(sendTarget(a,
        \\{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"to":"x"}}
    ) == null);
    try testing.expect(sendTarget(a,
        \\{"hook_event_name":"PostToolUse","tool_name":"SendMessage","tool_input":{"to":"x"}}
    ) == null);
    try testing.expect(sendTarget(a, "not json") == null);
    try testing.expectEqualStrings("name", target("name [3fa9c1]"));
    try testing.expectEqualStrings("name", target("name"));
    try testing.expectEqualStrings("a [b] c", target("a [b] c"));
    try testing.expectEqualStrings("[x]", target("[x]"));
}

test "claude zone: a session file's agent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const agent = parseAgent(a,
        \\{"pid":98705,"sessionId":"abc","cwd":"/r","name":"zones-33","tmux":"zones-2:@12.%12","status":"busy"}
    ).?;
    try testing.expectEqualStrings("zones-33", agent.name);
    try testing.expectEqualStrings("zones-2:@12.%12", agent.tmux.?);
    try testing.expectEqualStrings("abc", agent.sessionId.?);
    try testing.expect(parseAgent(a,
        \\{"name":"solo"}
    ).?.tmux == null);
    try testing.expect(parseAgent(a,
        \\{"peerToken":"t","procStart":"x"}
    ) == null);
    try testing.expect(parseAgent(a,
        \\{"name":""}
    ) == null);
}

test "claude zone: a message stops at the zone's edge" {
    const members = [_][]const u8{ "tb-1", "tb-2" };
    const agents = [_]Agent{
        .{ .name = "inside", .tmux = "tb-2:@4.%4" },
        .{ .name = "outside", .tmux = "lostty:@2.%2" },
        .{ .name = "untmuxed" },
        .{ .name = "prefix", .tmux = "tb-10:@1.%1" },
    };
    try testing.expectEqual(Decision.allow, decide("inside", &members, &agents));
    try testing.expectEqual(Decision.deny, decide("outside", &members, &agents));
    try testing.expectEqual(Decision.deny, decide("untmuxed", &members, &agents));
    try testing.expectEqual(Decision.deny, decide("prefix", &members, &agents));
    try testing.expectEqual(Decision.allow, decide("main", &members, &agents));
    try testing.expectEqual(Decision.allow, decide("a-subagent", &members, &agents));
    try testing.expectEqual(Decision.deny, decide("inside", &.{}, &agents));
}

test "claude zone: Allow Once names one target" {
    try testing.expect(allows("lostty-a9\n", "lostty-a9"));
    try testing.expect(!allows("lostty-a9", "lostty"));
    try testing.expect(!allows("", "lostty"));
}

test "claude zone: the deny names the target and the project" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqualStrings(
        "Lostty zone: lostty-a9 is outside zone Textberry, so this message was kept inside. " ++
            "The owner can press Allow Once on the canvas, and you'll be told when you may retry.",
        try denyReason(arena.allocator(), "lostty-a9", "Textberry › Onboarding"),
    );
}

test "claude zone: the brief names the zone's other agents" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const members = [_][]const u8{ "tb-1", "tb-2", "tb-3" };
    const agents = [_]Agent{
        .{ .name = "tb-b", .tmux = "tb-2:@4.%4", .sessionId = "s2" },
        .{ .name = "me", .tmux = "tb-1:@3.%3", .sessionId = "s1" },
        .{ .name = "me-before-clear", .tmux = "tb-1:@3.%3", .sessionId = "s0" },
        .{ .name = "tb-a", .tmux = "tb-3:@5.%5", .sessionId = "s3" },
        .{ .name = "tb-a", .tmux = "tb-3:@5.%5", .sessionId = "s4" },
        .{ .name = "outside", .tmux = "lostty:@2.%2", .sessionId = "s5" },
    };
    const names = try others(a, &members, &agents, "s1", "%3");
    try testing.expectEqualStrings("Other agents in this zone: tb-a, tb-b.", (try othersLine(a, names)).?);
    try testing.expectEqual(@as(usize, 3), (try others(a, &members, &agents, "s1", null)).len);
    try testing.expect(try othersLine(a, try others(a, &.{"tb-1"}, &agents, "s1", "%3")) == null);
}

test "claude zone: a hook's session id" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("s1", sessionId(a,
        \\{"session_id":"s1","hook_event_name":"SessionStart","source":"startup"}
    ).?);
    try testing.expect(sessionId(a, "{}") == null);
}
