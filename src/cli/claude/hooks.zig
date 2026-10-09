//! Pure logic for `+claude-hooks`: reading and editing the `hooks` table of
//! Claude Code's settings.json. Values come from std.json parsed with
//! `.parse_numbers = false`; the object map keeps insertion order and
//! numbers are re-emitted as written, so a user's file keeps its layout.
//! See docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md (§5).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = std.json.Value;

pub const Event = struct { name: []const u8, state: []const u8 };

/// The coding agents whose hook files Lostty edits.
pub const Agent = enum { claude, codex };

/// Claude Code hook events and the `+claude-state` each one sends.
const claude_events = [_]Event{
    .{ .name = "UserPromptSubmit", .state = "busy" },
    .{ .name = "Stop", .state = "idle" },
    .{ .name = "Notification", .state = "idle" },
    .{ .name = "SessionEnd", .state = "exit" },
};

/// Codex hook events (same hooks.json names). Codex has no session-end
/// event (Lostty sees the process exit anyway), and PermissionRequest is
/// left out: a hook there could count as an approval decision.
const codex_events = [_]Event{
    .{ .name = "UserPromptSubmit", .state = "busy" },
    .{ .name = "Stop", .state = "idle" },
};

pub fn eventsFor(agent: Agent) []const Event {
    return switch (agent) {
        .claude => &claude_events,
        .codex => &codex_events,
    };
}

pub const timeout_seconds = 5;

pub const Status = enum {
    installed,
    partial,
    not_installed,
    unreadable,

    pub fn label(self: Status) []const u8 {
        return switch (self) {
            .installed => "installed",
            .partial => "partial",
            .not_installed => "not-installed",
            .unreadable => "unreadable",
        };
    }
};

pub const EditError = error{Malformed} || Allocator.Error;

/// The hook command for `state`. It is a no-op outside Lostty (no
/// LOSTTY_SURFACE) and when the binary is gone, and always exits 0.
pub fn command(alloc: Allocator, state: []const u8) Allocator.Error![]u8 {
    return std.fmt.allocPrint(
        alloc,
        "[ -n \"$LOSTTY_SURFACE\" ] && [ -x \"$LOSTTY_BIN\" ] && \"$LOSTTY_BIN\" +claude-state {s}; exit 0",
        .{state},
    );
}

/// Lostty's entries, in any version, mention both of these.
pub fn isLosttyCommand(cmd: []const u8) bool {
    return std.mem.indexOf(u8, cmd, "+claude-state") != null and
        std.mem.indexOf(u8, cmd, "LOSTTY_SURFACE") != null;
}

/// Claude Code's status line runs this to feed the window's usage bar.
pub const status_line_command =
    "[ -n \"$LOSTTY_SURFACE\" ] && [ -x \"$LOSTTY_BIN\" ] && \"$LOSTTY_BIN\" +claude-usage; exit 0";

const StatusLine = enum { missing, foreign, outdated, current };

/// Whose `statusLine` this is. Someone else's is left alone.
fn statusLineState(root: Value) StatusLine {
    const sl = root.object.get("statusLine") orelse return .missing;
    const cmd = hookCommand(sl) orelse return .foreign;
    if (std.mem.indexOf(u8, cmd, "+claude-usage") == null or
        std.mem.indexOf(u8, cmd, "LOSTTY_SURFACE") == null) return .foreign;
    return if (std.mem.eql(u8, cmd, status_line_command)) .current else .outdated;
}

fn statusLineValue(alloc: Allocator) Allocator.Error!Value {
    var sl = std.json.ObjectMap.init(alloc);
    try sl.put("type", .{ .string = "command" });
    try sl.put("command", .{ .string = status_line_command });
    return .{ .object = sl };
}

fn hookCommand(hook: Value) ?[]const u8 {
    if (hook != .object) return null;
    const c = hook.object.get("command") orelse return null;
    return if (c == .string) c.string else null;
}

fn isTimeout(v: Value) bool {
    return switch (v) {
        .integer => |i| i == timeout_seconds,
        .number_string => |s| std.mem.eql(u8, s, "5"),
        else => false,
    };
}

/// Checks `hooks.<event>` has Claude Code's documented shape: an array of
/// objects, each with a `hooks` array.
fn checkEvent(event_value: Value) EditError!void {
    if (event_value != .array) return error.Malformed;
    for (event_value.array.items) |group_value| {
        if (group_value != .object) return error.Malformed;
        const list = group_value.object.get("hooks") orelse return error.Malformed;
        if (list != .array) return error.Malformed;
    }
}

fn expectedFor(alloc: Allocator, agent: Agent, event_name: []const u8) Allocator.Error!?[]const u8 {
    for (eventsFor(agent)) |e| {
        if (std.mem.eql(u8, e.name, event_name)) return try command(alloc, e.state);
    }
    return null;
}

pub fn status(alloc: Allocator, agent: Agent, root: Value) Allocator.Error!Status {
    if (root != .object) return .unreadable;
    var current: usize = 0;
    var ours: usize = 0;
    var n = eventsFor(agent).len;
    if (root.object.get("hooks")) |hooks| {
        if (hooks != .object) return .unreadable;
        var it = hooks.object.iterator();
        while (it.next()) |entry| {
            checkEvent(entry.value_ptr.*) catch return .unreadable;
            const expected = try expectedFor(alloc, agent, entry.key_ptr.*);
            for (entry.value_ptr.array.items) |group_value| {
                for (group_value.object.get("hooks").?.array.items) |hook| {
                    const cmd = hookCommand(hook) orelse continue;
                    if (!isLosttyCommand(cmd)) continue;
                    ours += 1;
                    const exp = expected orelse continue;
                    if (std.mem.eql(u8, cmd, exp) and isTimeout(hook.object.get("timeout") orelse .null)) current += 1;
                }
            }
        }
    }
    // Claude's status line feeds the usage bar, unless the user has their own.
    if (agent == .claude) switch (statusLineState(root)) {
        .foreign => {},
        .missing => n += 1,
        .outdated => {
            n += 1;
            ours += 1;
        },
        .current => {
            n += 1;
            ours += 1;
            current += 1;
        },
    };
    if (ours == 0) return .not_installed;
    if (current == n and ours == n) return .installed;
    return .partial;
}

/// Removes Lostty's commands under every event. Drops matcher groups and
/// event arrays that this emptied (never ones that were already empty).
/// Validates everything before changing anything.
fn strip(hooks: *std.json.ObjectMap) EditError!bool {
    for (hooks.values()) |v| try checkEvent(v);
    var changed = false;
    var i: usize = 0;
    while (i < hooks.count()) {
        const event_value = &hooks.values()[i];
        var event_changed = false;
        var g: usize = 0;
        while (g < event_value.array.items.len) {
            const list = &event_value.array.items[g].object.getPtr("hooks").?.array;
            var removed = false;
            var h: usize = 0;
            while (h < list.items.len) {
                const cmd = hookCommand(list.items[h]);
                if (cmd != null and isLosttyCommand(cmd.?)) {
                    _ = list.orderedRemove(h);
                    removed = true;
                } else {
                    h += 1;
                }
            }
            if (removed) event_changed = true;
            if (removed and list.items.len == 0) {
                _ = event_value.array.orderedRemove(g);
            } else {
                g += 1;
            }
        }
        if (event_changed) changed = true;
        if (event_changed and event_value.array.items.len == 0) {
            _ = hooks.orderedRemove(hooks.keys()[i]);
        } else {
            i += 1;
        }
    }
    return changed;
}

fn group(alloc: Allocator, state: []const u8) Allocator.Error!Value {
    var hook = std.json.ObjectMap.init(alloc);
    try hook.put("type", .{ .string = "command" });
    try hook.put("command", .{ .string = try command(alloc, state) });
    try hook.put("timeout", .{ .integer = timeout_seconds });
    var list = std.json.Array.init(alloc);
    try list.append(.{ .object = hook });
    var g = std.json.ObjectMap.init(alloc);
    try g.put("hooks", .{ .array = list });
    return .{ .object = g };
}

/// Adds Lostty's hooks, replacing older Lostty entries. Returns false when
/// already installed in the current form (nothing to write).
pub fn install(alloc: Allocator, agent: Agent, root: *Value) EditError!bool {
    if (root.* != .object) return error.Malformed;
    if (try status(alloc, agent, root.*) == .installed) return false;
    const gop = try root.object.getOrPut("hooks");
    if (!gop.found_existing) gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(alloc) };
    if (gop.value_ptr.* != .object) return error.Malformed;
    const hooks = &gop.value_ptr.object;
    _ = try strip(hooks);
    for (eventsFor(agent)) |e| {
        const ev = try hooks.getOrPut(e.name);
        if (!ev.found_existing) ev.value_ptr.* = .{ .array = std.json.Array.init(alloc) };
        try ev.value_ptr.array.append(try group(alloc, e.state));
    }
    if (agent == .claude and statusLineState(root.*) != .foreign) {
        try root.object.put("statusLine", try statusLineValue(alloc));
    }
    return true;
}

/// Removes Lostty's hooks, and `hooks` itself if that empties it, and
/// Lostty's status line.
pub fn remove(root: *Value) EditError!bool {
    if (root.* != .object) return error.Malformed;
    var changed = false;
    if (root.object.getPtr("hooks")) |hooks| {
        if (hooks.* != .object) return error.Malformed;
        changed = try strip(&hooks.object);
        if (changed and hooks.object.count() == 0) _ = root.object.orderedRemove("hooks");
    }
    switch (statusLineState(root.*)) {
        .outdated, .current => {
            _ = root.object.orderedRemove("statusLine");
            changed = true;
        },
        .missing, .foreign => {},
    }
    return changed;
}

/// The `hooks` object install adds, for the app's "Show changes".
pub fn preview(alloc: Allocator, agent: Agent) Allocator.Error!Value {
    var hooks = std.json.ObjectMap.init(alloc);
    for (eventsFor(agent)) |e| {
        var list = std.json.Array.init(alloc);
        try list.append(try group(alloc, e.state));
        try hooks.put(e.name, .{ .array = list });
    }
    var root = std.json.ObjectMap.init(alloc);
    try root.put("hooks", .{ .object = hooks });
    if (agent == .claude) try root.put("statusLine", try statusLineValue(alloc));
    return .{ .object = root };
}

pub fn stringify(alloc: Allocator, root: Value) Allocator.Error![]u8 {
    const body = try std.json.Stringify.valueAlloc(alloc, root, .{ .whitespace = .indent_2 });
    return std.mem.concat(alloc, u8, &.{ body, "\n" });
}

fn parseFixture(alloc: Allocator, text: []const u8) !Value {
    return std.json.parseFromSliceLeaky(Value, alloc, text, .{ .parse_numbers = false });
}

test "claude hooks: status of empty and missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(Status.not_installed, try status(a, .claude, try parseFixture(a, "{}")));
    try std.testing.expectEqual(Status.not_installed, try status(a, .claude, try parseFixture(a, "{\"hooks\":{}}")));
    try std.testing.expectEqual(Status.unreadable, try status(a, .claude, try parseFixture(a, "[]")));
}

test "claude hooks: install into empty object, then idempotent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a, "{}");
    try std.testing.expect(try install(a, .claude, &root));
    try std.testing.expectEqual(Status.installed, try status(a, .claude, root));
    const once = try stringify(a, root);
    try std.testing.expect(!(try install(a, .claude, &root)));
    try std.testing.expectEqualStrings(once, try stringify(a, root));
    // Survives a write/read round trip.
    try std.testing.expectEqual(Status.installed, try status(a, .claude, try parseFixture(a, once)));
    try std.testing.expect(std.mem.indexOf(u8, once, "+claude-state busy") != null);
    try std.testing.expect(std.mem.indexOf(u8, once, "\"timeout\": 5") != null);
}

test "claude hooks: install keeps user keys, order, numbers and hooks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a,
        \\{"model":"opus","cleanupPeriodDays":30.0,"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]},"zeta":true}
    );
    try std.testing.expect(try install(a, .claude, &root));
    const out = try stringify(a, root);
    // Key order of the top level is unchanged.
    const m = std.mem.indexOf(u8, out, "\"model\"").?;
    const c = std.mem.indexOf(u8, out, "\"cleanupPeriodDays\"").?;
    const h = std.mem.indexOf(u8, out, "\"hooks\"").?;
    const z = std.mem.indexOf(u8, out, "\"zeta\"").?;
    try std.testing.expect(m < c and c < h and h < z);
    // Numbers are written back exactly as they were.
    try std.testing.expect(std.mem.indexOf(u8, out, "30.0") != null);
    // The user's Stop hook is still there, before Lostty's.
    const user = std.mem.indexOf(u8, out, "say done").?;
    const ours = std.mem.indexOf(u8, out, "+claude-state idle").?;
    try std.testing.expect(user < ours);
}

test "claude hooks: outdated entries become partial and are replaced" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a,
        \\{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"[ -n \"$LOSTTY_SURFACE\" ] && old +claude-state idle"}]}]}}
    );
    try std.testing.expectEqual(Status.partial, try status(a, .claude, root));
    try std.testing.expect(try install(a, .claude, &root));
    try std.testing.expectEqual(Status.installed, try status(a, .claude, root));
    const out = try stringify(a, root);
    try std.testing.expect(std.mem.indexOf(u8, out, "old +claude-state") == null);
}

test "claude hooks: remove takes out only Lostty entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a,
        \\{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}
    );
    _ = try install(a, .claude, &root);
    try std.testing.expect(try remove(&root));
    try std.testing.expectEqual(Status.not_installed, try status(a, .claude, root));
    const out = try stringify(a, root);
    try std.testing.expect(std.mem.indexOf(u8, out, "say done") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "UserPromptSubmit") == null);
    try std.testing.expect(!(try remove(&root)));
}

test "claude hooks: remove drops an emptied hooks table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a, "{\"model\":\"opus\"}");
    _ = try install(a, .claude, &root);
    _ = try remove(&root);
    try std.testing.expectEqualStrings("{\n  \"model\": \"opus\"\n}\n", try stringify(a, root));
}

test "claude hooks: remove keeps a user's hook in a shared group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ours = try std.json.Stringify.valueAlloc(a, Value{ .string = try command(a, "idle") }, .{});
    const text = try std.fmt.allocPrint(a,
        \\{{"hooks":{{"Stop":[{{"matcher":"","hooks":[{{"type":"command","command":"say done"}},{{"type":"command","command":{s}}}]}}]}}}}
    , .{ours});
    var root = try parseFixture(a, text);
    try std.testing.expect(try remove(&root));
    const out = try stringify(a, root);
    try std.testing.expect(std.mem.indexOf(u8, out, "say done") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"matcher\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "+claude-state") == null);
}

test "claude hooks: malformed layouts are refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bad = [_][]const u8{
        "{\"hooks\":[]}",
        "{\"hooks\":null}",
        "{\"hooks\":{\"Stop\":{}}}",
        "{\"hooks\":{\"Stop\":[1]}}",
        "{\"hooks\":{\"Stop\":[{\"hooks\":\"x\"}]}}",
    };
    for (bad) |text| {
        var root = try parseFixture(a, text);
        try std.testing.expectEqual(Status.unreadable, try status(a, .claude, root));
        try std.testing.expectError(error.Malformed, install(a, .claude, &root));
        try std.testing.expectError(error.Malformed, remove(&root));
    }
    var arr = try parseFixture(a, "[]");
    try std.testing.expectError(error.Malformed, install(a, .claude, &arr));
}

test "claude hooks: command and detection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cmd = try command(a, "busy");
    try std.testing.expectEqualStrings(
        "[ -n \"$LOSTTY_SURFACE\" ] && [ -x \"$LOSTTY_BIN\" ] && \"$LOSTTY_BIN\" +claude-state busy; exit 0",
        cmd,
    );
    try std.testing.expect(isLosttyCommand(cmd));
    try std.testing.expect(!isLosttyCommand("say done"));
    try std.testing.expect(!isLosttyCommand("echo +claude-state"));
    try std.testing.expectEqualStrings("not-installed", Status.not_installed.label());
}

test "claude hooks: preview lists the four events" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try stringify(a, try preview(a, .claude));
    for (eventsFor(.claude)) |e| try std.testing.expect(std.mem.indexOf(u8, out, e.name) != null);
}

test "claude hooks: the status line is added, updated and removed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a, "{}");
    _ = try install(a, .claude, &root);
    // Hooks from before the usage bar: partial until the status line is added.
    _ = root.object.orderedRemove("statusLine");
    try std.testing.expectEqual(Status.partial, try status(a, .claude, root));
    try std.testing.expect(try install(a, .claude, &root));
    try std.testing.expectEqual(Status.installed, try status(a, .claude, root));
    try std.testing.expect(std.mem.indexOf(u8, try stringify(a, root), "+claude-usage") != null);
    // An older Lostty status line is replaced.
    try root.object.put("statusLine", try parseFixture(a,
        \\{"type":"command","command":"[ -n \"$LOSTTY_SURFACE\" ] && old +claude-usage"}
    ));
    try std.testing.expectEqual(Status.partial, try status(a, .claude, root));
    try std.testing.expect(try install(a, .claude, &root));
    try std.testing.expectEqual(Status.installed, try status(a, .claude, root));
    try std.testing.expect(try remove(&root));
    try std.testing.expectEqualStrings("{}\n", try stringify(a, root));
}

test "claude hooks: a user's own status line is kept" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a,
        \\{"statusLine":{"type":"command","command":"~/bin/my-status"}}
    );
    try std.testing.expectEqual(Status.not_installed, try status(a, .claude, root));
    try std.testing.expect(try install(a, .claude, &root));
    try std.testing.expectEqual(Status.installed, try status(a, .claude, root));
    try std.testing.expect(try remove(&root));
    const out = try stringify(a, root);
    try std.testing.expect(std.mem.indexOf(u8, out, "my-status") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "+claude-usage") == null);
}

test "codex hooks: install adds only the busy and idle events" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var root = try parseFixture(a, "{}");
    try std.testing.expect(try install(a, .codex, &root));
    try std.testing.expectEqual(Status.installed, try status(a, .codex, root));
    const out = try stringify(a, root);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"UserPromptSubmit\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"Stop\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Notification") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "SessionEnd") == null);
    // PermissionRequest stays out: a hook there might count as an approval.
    try std.testing.expect(std.mem.indexOf(u8, out, "PermissionRequest") == null);
    // Second install is a no-op; remove takes everything back out.
    try std.testing.expect(!(try install(a, .codex, &root)));
    try std.testing.expect(try remove(&root));
    try std.testing.expectEqual(Status.not_installed, try status(a, .codex, root));
}

test "codex hooks: preview lists the two events" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try stringify(a, try preview(a, .codex));
    try std.testing.expect(std.mem.indexOf(u8, out, "UserPromptSubmit") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Notification") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "statusLine") == null);
}
