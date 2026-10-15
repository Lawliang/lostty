//! The guard's two conversations: with the app over a Unix socket (one
//! JSON line each way; the app can only answer "allow" for an approval you
//! already gave, or "deny, request #N"), and with the agent through the
//! hook's output.

const std = @import("std");
const Allocator = std.mem.Allocator;
const decide = @import("decide.zig");
const catalog = @import("catalog.zig");

pub const Agent = enum { claude, codex };
pub const Reply = union(enum) { allow, deny: u32 };

pub fn socketPath(alloc: Allocator, home: []const u8) Allocator.Error![]const u8 {
    return std.fs.path.join(alloc, &.{ home, ".config", "lostty", "coord", "guard.sock" });
}

pub fn encodeRequest(alloc: Allocator, pane: []const u8, agent: Agent, c: decide.Critical) Allocator.Error![]const u8 {
    var o = std.json.ObjectMap.init(alloc);
    try o.put("v", .{ .integer = 1 });
    try o.put("pane", .{ .string = pane });
    try o.put("agent", .{ .string = @tagName(agent) });
    try o.put("tool", .{ .string = c.tool });
    try o.put("input", .{ .string = c.input });
    try o.put("cwd", .{ .string = c.cwd });
    try o.put("group", .{ .string = @tagName(c.group) });
    try o.put("why", .{ .string = c.why });
    const optional = [_]struct { []const u8, ?[]const u8 }{
        .{ "session", c.session }, .{ "repo", c.repo },     .{ "branch", c.branch },
        .{ "lost", c.lost },       .{ "reason", c.reason },
    };
    for (optional) |kv| if (kv[1]) |v| try o.put(kv[0], .{ .string = v });
    return std.json.Stringify.valueAlloc(alloc, std.json.Value{ .object = o }, .{});
}

pub fn parseReply(alloc: Allocator, line: []const u8) ?Reply {
    const v = std.json.parseFromSliceLeaky(std.json.Value, alloc, line, .{}) catch return null;
    if (v != .object) return null;
    const d = v.object.get("decision") orelse return null;
    if (d != .string) return null;
    if (std.mem.eql(u8, d.string, "allow")) return .allow;
    if (!std.mem.eql(u8, d.string, "deny")) return null;
    const id = v.object.get("request") orelse return null;
    if (id != .integer or id.integer <= 0) return null;
    return .{ .deny = @intCast(id.integer) };
}

pub const Output = struct { stdout: []const u8 = "", stderr: []const u8 = "", exit: u8 = 0 };

fn claudeJson(alloc: Allocator, decision: []const u8, reason: []const u8) Allocator.Error![]const u8 {
    var h = std.json.ObjectMap.init(alloc);
    try h.put("hookEventName", .{ .string = "PreToolUse" });
    try h.put("permissionDecision", .{ .string = decision });
    try h.put("permissionDecisionReason", .{ .string = reason });
    var o = std.json.ObjectMap.init(alloc);
    try o.put("hookSpecificOutput", .{ .object = h });
    return std.json.Stringify.valueAlloc(alloc, std.json.Value{ .object = o }, .{});
}

pub fn outputDeny(alloc: Allocator, agent: Agent, id: u32, c: decide.Critical) Allocator.Error!Output {
    const text = try std.fmt.allocPrint(alloc, "Blocked by Lostty: {s} ({s}). This needs your user's approval in Lostty: request #{d}. " ++
        "Don't try another way to do it. Carry on with other parts of the task; your user will tell you when they decide.", .{ c.why, catalog.label(c.group), id });
    return switch (agent) {
        .claude => .{ .stdout = try claudeJson(alloc, "deny", text) },
        .codex => .{ .stderr = text, .exit = 2 },
    };
}

pub fn outputUnreachable(alloc: Allocator, agent: Agent, c: decide.Critical) Allocator.Error!Output {
    return switch (agent) {
        .claude => .{ .stdout = try claudeJson(alloc, "ask", try std.fmt.allocPrint(alloc, "Lostty's guard can't reach the app, so it's asking you directly: {s} ({s}).", .{ c.why, catalog.label(c.group) })) },
        .codex => .{ .stderr = try std.fmt.allocPrint(alloc, "Blocked by Lostty: {s} ({s}). Lostty isn't running, so this can't be approved right now. Don't try another way to do it.", .{ c.why, catalog.label(c.group) }), .exit = 2 },
    };
}

fn setTimeouts(handle: std.posix.socket_t, ms: u32) ?void {
    const tv: std.posix.timeval = .{ .sec = @intCast(ms / 1000), .usec = @intCast((ms % 1000) * 1000) };
    std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&tv)) catch return null;
    std.posix.setsockopt(handle, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&tv)) catch return null;
}

/// Sends one request line and reads one reply line. Null when the app
/// can't be reached, times out, or answers nonsense: the caller fails
/// closed.
pub fn ask(alloc: Allocator, path: []const u8, request: []const u8, timeout_ms: u32) ?Reply {
    const stream = std.net.connectUnixSocket(path) catch return null;
    defer stream.close();
    var timer = std.time.Timer.start() catch return null;
    setTimeouts(stream.handle, timeout_ms) orelse return null;
    // One write, so a peer that reads once sees the whole line.
    const line_out = std.fmt.allocPrint(alloc, "{s}\n", .{request}) catch return null;
    stream.writeAll(line_out) catch return null;
    var buf: [4096]u8 = undefined;
    var len: usize = 0;
    // The socket timeout is per read, so each read gets only what is left.
    while (len < buf.len) {
        const used_ms = timer.read() / std.time.ns_per_ms;
        if (used_ms >= timeout_ms) return null;
        setTimeouts(stream.handle, @intCast(@max(1, timeout_ms - used_ms))) orelse return null;
        const n = stream.read(buf[len..]) catch return null;
        if (n == 0) break;
        len += n;
        if (std.mem.indexOfScalar(u8, buf[0..len], '\n') != null) break;
    }
    const line = std.mem.trimRight(u8, buf[0..len], "\n");
    return parseReply(alloc, line);
}

const sample: decide.Critical = .{
    .group = .deleting,
    .why = "deletes files git can't restore",
    .lost = "2 untracked files",
    .tool = "Bash",
    .input = "rm -rf \"tmp dir\"",
    .cwd = "/r",
    .repo = "/r",
    .branch = "feature",
    .reason = null,
    .session = "s1",
};

test "guard wire: request is one JSON line with optional fields omitted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const line = try encodeRequest(a, "PANE-1", .codex, sample);
    try std.testing.expect(std.mem.indexOfScalar(u8, line, '\n') == null);
    const v = try std.json.parseFromSliceLeaky(std.json.Value, a, line, .{});
    try std.testing.expectEqual(@as(i64, 1), v.object.get("v").?.integer);
    try std.testing.expectEqualStrings("PANE-1", v.object.get("pane").?.string);
    try std.testing.expectEqualStrings("codex", v.object.get("agent").?.string);
    try std.testing.expectEqualStrings("deleting", v.object.get("group").?.string);
    try std.testing.expectEqualStrings("rm -rf \"tmp dir\"", v.object.get("input").?.string);
    try std.testing.expect(v.object.get("reason") == null);
}

test "guard wire: parseReply" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect(parseReply(a, "{\"v\":1,\"decision\":\"allow\"}").? == .allow);
    try std.testing.expectEqual(@as(u32, 42), parseReply(a, "{\"v\":1,\"decision\":\"deny\",\"request\":42}").?.deny);
    try std.testing.expect(parseReply(a, "{\"v\":1,\"decision\":\"grant\"}") == null);
    try std.testing.expect(parseReply(a, "garbage") == null);
    try std.testing.expect(parseReply(a, "{\"v\":1,\"decision\":\"deny\"}") == null);
}

test "guard wire: outputs per agent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cd = try outputDeny(a, .claude, 42, sample);
    try std.testing.expectEqual(@as(u8, 0), cd.exit);
    const j = try std.json.parseFromSliceLeaky(std.json.Value, a, cd.stdout, .{});
    const h = j.object.get("hookSpecificOutput").?.object;
    try std.testing.expectEqualStrings("deny", h.get("permissionDecision").?.string);
    try std.testing.expect(std.mem.indexOf(u8, h.get("permissionDecisionReason").?.string, "request #42") != null);

    const xd = try outputDeny(a, .codex, 42, sample);
    try std.testing.expectEqual(@as(u8, 2), xd.exit);
    try std.testing.expect(std.mem.indexOf(u8, xd.stderr, "request #42") != null);

    const cu = try outputUnreachable(a, .claude, sample);
    const ju = try std.json.parseFromSliceLeaky(std.json.Value, a, cu.stdout, .{});
    try std.testing.expectEqualStrings("ask", ju.object.get("hookSpecificOutput").?.object.get("permissionDecision").?.string);
    const xu = try outputUnreachable(a, .codex, sample);
    try std.testing.expectEqual(@as(u8, 2), xu.exit);
    try std.testing.expect(std.mem.indexOf(u8, xu.stderr, "isn't running") != null);
}

test "guard wire: ask talks to a socket, and an absent one is unreachable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(a, ".");
    const path = try std.fs.path.join(a, &.{ dir, "g.sock" });
    try std.testing.expect(ask(a, path, "{}", 500) == null);

    const addr = try std.net.Address.initUnix(path);
    var server = try addr.listen(.{});
    defer server.deinit();
    const T = struct {
        fn serve(s: *std.net.Server) void {
            const conn = s.accept() catch return;
            defer conn.stream.close();
            var buf: [256]u8 = undefined;
            _ = conn.stream.read(&buf) catch return;
            _ = conn.stream.writeAll("{\"v\":1,\"decision\":\"deny\",\"request\":7}\n") catch {};
        }
    };
    const th = try std.Thread.spawn(.{}, T.serve, .{&server});
    const r = ask(a, path, "{\"v\":1}", 2000);
    th.join();
    try std.testing.expectEqual(@as(u32, 7), r.?.deny);
}

test "guard wire: a peer that trickles one byte then stalls hits the deadline" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(a, ".");
    const path = try std.fs.path.join(a, &.{ dir, "g.sock" });
    const addr = try std.net.Address.initUnix(path);
    var server = try addr.listen(.{});
    defer server.deinit();
    const T = struct {
        fn serve(s: *std.net.Server) void {
            const conn = s.accept() catch return;
            defer conn.stream.close();
            var buf: [256]u8 = undefined;
            _ = conn.stream.read(&buf) catch return;
            _ = conn.stream.writeAll("{") catch return;
            std.Thread.sleep(1200 * std.time.ns_per_ms);
        }
    };
    const th = try std.Thread.spawn(.{}, T.serve, .{&server});
    var timer = try std.time.Timer.start();
    const r = ask(a, path, "{\"v\":1}", 300);
    const took = timer.read() / std.time.ns_per_ms;
    th.join();
    try std.testing.expect(r == null);
    try std.testing.expect(took < 1000);
}
