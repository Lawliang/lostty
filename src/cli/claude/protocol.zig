//! Pure logic for `+claude-state`: the LOSTTY_CLAUDE wire format. See
//! docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md (§2.1).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const user_var_name = "LOSTTY_CLAUDE";
pub const surface_env = "LOSTTY_SURFACE";

/// `agents`: Claude finished its turn but its subagents are still working,
/// so it carries on by itself when they finish. `resumed`: the last of
/// them finished, so Claude itself works again.
pub const State = enum { busy, idle, exit, agents, resumed };

pub fn parseState(s: []const u8) ?State {
    return std.meta.stringToEnum(State, s);
}

/// Background task types that are agents working for Claude, as Claude
/// Code names them in the Stop and SubagentStop hook input's
/// `background_tasks` (which lists only running and pending tasks).
/// Shells and monitors are left out: a dev server can run for hours.
const agent_task_types = [_][]const u8{ "subagent", "workflow", "teammate" };

/// Refines the hook's `state` with the hook input Claude Code passes on
/// stdin. Returns null when the hook should send nothing.
/// - Stop (`idle`): `agents` while agent tasks are still running.
/// - SubagentStop (`resumed`): nothing while other agent tasks still run.
/// - Notification: nothing for `idle_prompt` and `auth_success`, which
///   don't mean Claude is waiting on the person to continue.
/// Input that isn't a hook payload leaves `state` as it is.
pub fn refine(alloc: Allocator, state: State, input: []const u8) ?State {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return state;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return state;
    const event = stringField(root, "hook_event_name") orelse return state;
    if (std.mem.eql(u8, event, "Notification")) {
        const kind = stringField(root, "notification_type") orelse return state;
        if (std.mem.eql(u8, kind, "idle_prompt") or std.mem.eql(u8, kind, "auth_success")) return null;
        return state;
    }
    if (std.mem.eql(u8, event, "Stop") and state == .idle) {
        return if (runningAgents(root, null)) .agents else .idle;
    }
    if (std.mem.eql(u8, event, "SubagentStop") and state == .resumed) {
        return if (runningAgents(root, stringField(root, "agent_id"))) null else .resumed;
    }
    return state;
}

fn stringField(object: std.json.Value, key: []const u8) ?[]const u8 {
    const value = object.object.get(key) orelse return null;
    return if (value == .string) value.string else null;
}

/// Whether `background_tasks` lists an agent task other than `except` (the
/// subagent that is stopping; its task id is its agent id).
fn runningAgents(root: std.json.Value, except: ?[]const u8) bool {
    const tasks = root.object.get("background_tasks") orelse return false;
    if (tasks != .array) return false;
    for (tasks.array.items) |task| {
        if (task != .object) continue;
        const kind = stringField(task, "type") orelse continue;
        const is_agent = for (agent_task_types) |t| {
            if (std.mem.eql(u8, kind, t)) break true;
        } else false;
        if (!is_agent) continue;
        if (except) |id| if (stringField(task, "id")) |task_id| if (std.mem.eql(u8, task_id, id)) continue;
        return true;
    }
    return false;
}

/// The state named right after `+claude-state` in argv, if valid.
pub fn stateFromArgs(argv: []const []const u8) ?State {
    for (argv, 0..) |arg, i| {
        if (!std.mem.eql(u8, arg, "+claude-state")) continue;
        if (i + 1 >= argv.len) return null;
        return parseState(argv[i + 1]);
    }
    return null;
}

pub const ProcInfo = struct {
    ppid: i32,
    /// Terminal name as `ps` prints it ("ttys001", "pts/3"), or null.
    tty: ?[]const u8,
};

/// Parses `ps -o ppid=,tty= -p <pid>` output.
pub fn parsePs(out: []const u8) ?ProcInfo {
    var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
    const ppid = std.fmt.parseInt(i32, it.next() orelse return null, 10) catch return null;
    const tty = it.next() orelse return .{ .ppid = ppid, .tty = null };
    return .{ .ppid = ppid, .tty = if (isTtyName(tty)) tty else null };
}

/// "ttys001" or "pts/3": letters/digits with at most one "/" and no dots.
fn isTtyName(s: []const u8) bool {
    if (s.len == 0 or std.mem.indexOfScalar(u8, s, '?') != null) return false;
    var slashes: usize = 0;
    for (s) |c| {
        if (c == '/') {
            slashes += 1;
        } else if (!std.ascii.isAlphanumeric(c)) return false;
    }
    return slashes <= 1;
}

/// Claude Code runs hooks without a controlling terminal, so `/dev/tty`
/// fails there. Walk up from `start` (at most `max_hops` processes) to the
/// first one attached to a terminal: that is `claude` in the pane.
/// `ctx.lookup(pid) ?ProcInfo` supplies process info.
pub fn findTty(ctx: anytype, start: i32, max_hops: usize) ?[]const u8 {
    var pid = start;
    var hops: usize = 0;
    while (hops < max_hops and pid > 1) : (hops += 1) {
        const info = ctx.lookup(pid) orelse return null;
        if (info.tty) |tty| return tty;
        pid = info.ppid;
    }
    return null;
}

/// OSC 1337 SetUserVar carrying `{"v":1,"state":"<state>"}`. With `tmux`,
/// wrapped in tmux's DCS passthrough (requires `allow-passthrough on`).
pub fn encodeSequence(alloc: Allocator, state: State, tmux: bool) ![]u8 {
    const json = try std.fmt.allocPrint(alloc, "{{\"v\":1,\"state\":\"{s}\"}}", .{@tagName(state)});
    defer alloc.free(json);
    return encodeUserVar(alloc, user_var_name, json, tmux);
}

/// OSC 1337 SetUserVar setting `name` to `json` (base64-encoded on the
/// wire). With `tmux`, wrapped in tmux's DCS passthrough.
pub fn encodeUserVar(alloc: Allocator, name: []const u8, json: []const u8, tmux: bool) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const b64 = try alloc.alloc(u8, encoder.calcSize(json.len));
    defer alloc.free(b64);
    _ = encoder.encode(b64, json);
    if (tmux) {
        return std.fmt.allocPrint(alloc, "\x1bPtmux;\x1b\x1b]1337;SetUserVar={s}={s}\x07\x1b\\", .{ name, b64 });
    }
    return std.fmt.allocPrint(alloc, "\x1b]1337;SetUserVar={s}={s}\x07", .{ name, b64 });
}

test "claude protocol: parsePs" {
    const t = std.testing;
    const a = parsePs("  38137 ttys001\n").?;
    try t.expectEqual(@as(i32, 38137), a.ppid);
    try t.expectEqualStrings("ttys001", a.tty.?);
    const b = parsePs("1 ??\n").?;
    try t.expect(b.tty == null);
    const c = parsePs("812 pts/3\n").?;
    try t.expectEqualStrings("pts/3", c.tty.?);
    try t.expect(parsePs("812 ?\n").?.tty == null);
    try t.expect(parsePs("") == null);
    try t.expect(parsePs("abc ttys001") == null);
    // Nothing path-like beyond one "pts/N" level.
    try t.expect(parsePs("5 ../../etc/passwd").?.tty == null);
}

test "claude protocol: findTty walks up to the first process with a terminal" {
    const Table = struct {
        pub fn lookup(_: @This(), pid: i32) ?ProcInfo {
            return switch (pid) {
                300 => .{ .ppid = 200, .tty = null }, // +claude-state's sh
                200 => .{ .ppid = 100, .tty = null }, // hook runner
                100 => .{ .ppid = 1, .tty = "ttys001" }, // claude
                else => null,
            };
        }
    };
    const t = std.testing;
    try t.expectEqualStrings("ttys001", findTty(Table{}, 300, 8).?);
    try t.expect(findTty(Table{}, 300, 2) == null);
    try t.expect(findTty(Table{}, 999, 8) == null);
}

test "claude protocol: parseState" {
    const t = std.testing;
    try t.expectEqual(State.busy, parseState("busy").?);
    try t.expectEqual(State.idle, parseState("idle").?);
    try t.expectEqual(State.exit, parseState("exit").?);
    try t.expectEqual(State.agents, parseState("agents").?);
    try t.expectEqual(State.resumed, parseState("resumed").?);
    try t.expect(parseState("BUSY") == null);
    try t.expect(parseState("") == null);
}

test "claude protocol: stateFromArgs" {
    const t = std.testing;
    try t.expectEqual(State.busy, stateFromArgs(&.{ "/x/ghostty", "+claude-state", "busy" }).?);
    try t.expect(stateFromArgs(&.{ "/x/ghostty", "+claude-state" }) == null);
    try t.expect(stateFromArgs(&.{ "/x/ghostty", "+claude-state", "nope" }) == null);
    try t.expect(stateFromArgs(&.{ "/x/ghostty", "busy" }) == null);
}

test "claude protocol: encodeSequence round-trips through base64" {
    const alloc = std.testing.allocator;
    const seq = try encodeSequence(alloc, .idle, false);
    defer alloc.free(seq);
    const prefix = "\x1b]1337;SetUserVar=LOSTTY_CLAUDE=";
    try std.testing.expect(std.mem.startsWith(u8, seq, prefix));
    try std.testing.expect(std.mem.endsWith(u8, seq, "\x07"));
    const b64 = seq[prefix.len .. seq.len - 1];
    var out: [64]u8 = undefined;
    const n = try std.base64.standard.Decoder.calcSizeForSlice(b64);
    try std.base64.standard.Decoder.decode(out[0..n], b64);
    try std.testing.expectEqualStrings("{\"v\":1,\"state\":\"idle\"}", out[0..n]);
}

test "claude protocol: encodeSequence wraps for tmux" {
    const alloc = std.testing.allocator;
    const seq = try encodeSequence(alloc, .busy, true);
    defer alloc.free(seq);
    try std.testing.expect(std.mem.startsWith(u8, seq, "\x1bPtmux;\x1b\x1b]1337;SetUserVar=LOSTTY_CLAUDE="));
    try std.testing.expect(std.mem.endsWith(u8, seq, "\x07\x1b\\"));
}

test "claude protocol: Stop with subagents still running reports agents" {
    const t = std.testing;
    const alloc = t.allocator;
    const running =
        \\{"hook_event_name":"Stop","stop_hook_active":false,"background_tasks":[
        \\{"id":"b1","type":"shell","status":"running","description":"dev server"},
        \\{"id":"a7","type":"subagent","status":"running","description":"Explore","agent_type":"Explore"}]}
    ;
    try t.expectEqual(State.agents, refine(alloc, .idle, running).?);
    const workflow =
        \\{"hook_event_name":"Stop","background_tasks":[{"id":"w1","type":"workflow","status":"pending"}]}
    ;
    try t.expectEqual(State.agents, refine(alloc, .idle, workflow).?);
    // Shells and monitors alone don't count.
    const shells =
        \\{"hook_event_name":"Stop","background_tasks":[{"id":"b1","type":"shell","status":"running"},
        \\{"id":"m1","type":"monitor","status":"running"}]}
    ;
    try t.expectEqual(State.idle, refine(alloc, .idle, shells).?);
    try t.expectEqual(State.idle, refine(alloc, .idle, "{\"hook_event_name\":\"Stop\",\"background_tasks\":[]}").?);
    try t.expectEqual(State.idle, refine(alloc, .idle, "{\"hook_event_name\":\"Stop\"}").?);
}

test "claude protocol: SubagentStop resumes only when it was the last agent" {
    const t = std.testing;
    const alloc = t.allocator;
    const last =
        \\{"hook_event_name":"SubagentStop","agent_id":"a7","background_tasks":[
        \\{"id":"a7","type":"subagent","status":"running"},{"id":"b1","type":"shell","status":"running"}]}
    ;
    try t.expectEqual(State.resumed, refine(alloc, .resumed, last).?);
    const others =
        \\{"hook_event_name":"SubagentStop","agent_id":"a7","background_tasks":[
        \\{"id":"a7","type":"subagent","status":"running"},{"id":"a8","type":"subagent","status":"running"}]}
    ;
    try t.expect(refine(alloc, .resumed, others) == null);
}

test "claude protocol: idle and auth notifications send nothing" {
    const t = std.testing;
    const alloc = t.allocator;
    try t.expect(refine(alloc, .idle, "{\"hook_event_name\":\"Notification\",\"notification_type\":\"idle_prompt\"}") == null);
    try t.expect(refine(alloc, .idle, "{\"hook_event_name\":\"Notification\",\"notification_type\":\"auth_success\"}") == null);
    try t.expectEqual(State.idle, refine(alloc, .idle, "{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\"}").?);
    try t.expectEqual(State.idle, refine(alloc, .idle, "{\"hook_event_name\":\"Notification\"}").?);
}

test "claude protocol: input that isn't a hook payload keeps the state" {
    const t = std.testing;
    const alloc = t.allocator;
    try t.expectEqual(State.idle, refine(alloc, .idle, "").?);
    try t.expectEqual(State.idle, refine(alloc, .idle, "not json").?);
    try t.expectEqual(State.resumed, refine(alloc, .resumed, "[1,2]").?);
    try t.expectEqual(State.busy, refine(alloc, .busy, "{\"hook_event_name\":\"UserPromptSubmit\"}").?);
    // Only a Stop hook's idle is refined to agents.
    const stop = "{\"hook_event_name\":\"Stop\",\"background_tasks\":[{\"id\":\"a\",\"type\":\"subagent\"}]}";
    try t.expectEqual(State.exit, refine(alloc, .exit, stop).?);
}
