//! Pure logic for `+claude-state`: the LOSTTY_CLAUDE wire format. See
//! docs/superpowers/specs/2026-10-05-lostty-claude-trace-design.md (§2.1).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const user_var_name = "LOSTTY_CLAUDE";
pub const surface_env = "LOSTTY_SURFACE";

/// `agents`: Claude finished its turn but its subagents or background
/// shells are still working, so it carries on by itself when they finish.
/// `resumed`: the last of them finished, so Claude itself works again. `tool`: Claude (or one of
/// its subagents) is about to run a tool; it carries the action, not a
/// change of state. `done` (PostToolUse) and `start` (SessionStart) only
/// speak the context handoff's queued text; after a /clear, `start` sends
/// `fresh` (the fresh window took the handoff) or `cleared` (none waited).
pub const State = enum { busy, idle, exit, agents, resumed, tool, done, start, fresh, cleared };

/// What a message says beyond its state.
pub const Detail = struct {
    /// `tool`: what the tool call does, as `action` words it.
    action: ?[]const u8 = null,
    /// `idle`: Claude asks permission to run the last action.
    permission: bool = false,
    /// `idle`: the conversation file the Stop or Notification hook named,
    /// for the Mac's turn observer.
    transcript: ?[]const u8 = null,
};

/// The longest action sent, in characters.
pub const action_max = 80;

/// The longest conversation file path sent, in bytes; a longer one is
/// dropped rather than cut.
pub const transcript_max = 1024;

pub fn parseState(s: []const u8) ?State {
    return std.meta.stringToEnum(State, s);
}

/// Background task types that keep working for Claude after its turn, as
/// Claude Code names them in the Stop and SubagentStop hook input's
/// `background_tasks` (which lists only running and pending tasks).
/// Shells count even though a dev server can run for hours; monitors are
/// left out, as they only watch.
const working_task_types = [_][]const u8{ "subagent", "workflow", "teammate", "shell" };

/// Refines the hook's `state` with the hook input Claude Code passes on
/// stdin. Returns null when the hook should send nothing.
/// - Stop (`idle`): `agents` while working tasks are still running.
/// - SubagentStop (`resumed`): nothing while other working tasks still run.
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
        return if (runningTasks(root, null)) .agents else .idle;
    }
    if (std.mem.eql(u8, event, "SubagentStop") and state == .resumed) {
        return if (runningTasks(root, stringField(root, "agent_id"))) null else .resumed;
    }
    return state;
}

/// Whether a Notification hook's input is Claude asking permission (for
/// the tool call the last PreToolUse described).
pub fn isPermissionPrompt(alloc: Allocator, input: []const u8) bool {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return false;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return false;
    const event = stringField(root, "hook_event_name") orelse return false;
    const kind = stringField(root, "notification_type") orelse return false;
    return std.mem.eql(u8, event, "Notification") and std.mem.eql(u8, kind, "permission_prompt");
}

/// The conversation file a Stop or Notification hook's input names
/// (`transcript_path`, which Claude Code and Codex both send). Null for
/// other events, a missing or blank path, or one longer than
/// `transcript_max` bytes. The Mac decides whether to read it.
pub fn transcriptPath(alloc: Allocator, input: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return null;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return null;
    const event = stringField(root, "hook_event_name") orelse return null;
    if (!std.mem.eql(u8, event, "Stop") and !std.mem.eql(u8, event, "Notification")) return null;
    const path = textField(root, "transcript_path") orelse return null;
    if (path.len > transcript_max) return null;
    return alloc.dupe(u8, path) catch null;
}

/// What a PreToolUse hook's tool call does, as a person reads it at a
/// glance: "Editing Foo.swift", "Searching for \"bar\"", or the
/// description Claude gave a shell command (never the command itself when
/// it gave one: commands can carry secrets). One line, at most
/// `action_max` characters. Null when the input isn't a PreToolUse
/// payload, or for a to-do list with nothing in progress.
pub fn action(alloc: Allocator, input: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{}) catch return null;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return null;
    const event = stringField(root, "hook_event_name") orelse return null;
    if (!std.mem.eql(u8, event, "PreToolUse")) return null;
    const tool = stringField(root, "tool_name") orelse return null;
    const raw = (describe(alloc, tool, root.object.get("tool_input") orelse .null) catch return null) orelse return null;
    const line = clean(alloc, raw) catch return null;
    return if (line.len == 0) null else line;
}

fn describe(alloc: Allocator, tool: []const u8, input: std.json.Value) Allocator.Error!?[]const u8 {
    const is = struct {
        fn any(name: []const u8, names: []const []const u8) bool {
            for (names) |n| if (std.mem.eql(u8, name, n)) return true;
            return false;
        }
    }.any;
    if (is(tool, &.{ "Edit", "MultiEdit", "Write", "NotebookEdit" })) {
        if (textField(input, "file_path") orelse textField(input, "notebook_path")) |path|
            return try std.fmt.allocPrint(alloc, "Editing {s}", .{std.fs.path.basenamePosix(path)});
    } else if (is(tool, &.{"Read"})) {
        if (textField(input, "file_path")) |path|
            return try std.fmt.allocPrint(alloc, "Reading {s}", .{std.fs.path.basenamePosix(path)});
    } else if (is(tool, &.{ "Grep", "Glob" })) {
        if (textField(input, "pattern")) |pattern| return try std.fmt.allocPrint(alloc, "Searching for \"{s}\"", .{pattern});
    } else if (is(tool, &.{"WebSearch"})) {
        if (textField(input, "query")) |query| return try std.fmt.allocPrint(alloc, "Searching for \"{s}\"", .{query});
    } else if (is(tool, &.{"WebFetch"})) {
        if (textField(input, "url")) |url| return try std.fmt.allocPrint(alloc, "Reading {s}", .{host(url)});
    } else if (is(tool, &.{"Bash"})) {
        if (textField(input, "description")) |description| return description;
        if (textField(input, "command")) |command| {
            const trimmed = std.mem.trim(u8, command, " \t\r\n");
            return trimmed[0 .. std.mem.indexOfScalar(u8, trimmed, '\n') orelse trimmed.len];
        }
    } else if (is(tool, &.{ "Task", "Agent" })) {
        if (textField(input, "description")) |description| return try std.fmt.allocPrint(alloc, "Agent: {s}", .{description});
    } else if (is(tool, &.{"TodoWrite"})) {
        // The item now in progress, as Claude words it while working on it.
        const todos = if (input == .object) input.object.get("todos") orelse return null else return null;
        if (todos != .array) return null;
        for (todos.array.items) |todo| {
            const status = if (todo == .object) stringField(todo, "status") orelse continue else continue;
            if (!std.mem.eql(u8, status, "in_progress")) continue;
            return textField(todo, "activeForm") orelse textField(todo, "content");
        }
        return null;
    }
    // An MCP tool ("mcp__server__tool") by its own name.
    if (std.mem.startsWith(u8, tool, "mcp__")) if (std.mem.lastIndexOf(u8, tool, "__")) |i| {
        if (i + 2 < tool.len) return tool[i + 2 ..];
    };
    return tool;
}

/// A string field with something in it besides blanks.
fn textField(object: std.json.Value, key: []const u8) ?[]const u8 {
    if (object != .object) return null;
    const s = stringField(object, key) orelse return null;
    return if (std.mem.trim(u8, s, " \t\r\n").len == 0) null else s;
}

/// "https://docs.example.com:8080/a?b" → "docs.example.com".
fn host(url: []const u8) []const u8 {
    const rest = if (std.mem.indexOf(u8, url, "://")) |i| url[i + 3 ..] else url;
    const end = std.mem.indexOfAny(u8, rest, "/:?#") orelse rest.len;
    return if (end == 0) url else rest[0..end];
}

/// One line: control characters and runs of blanks become one space, then
/// at most `action_max` characters, the last an ellipsis when cut.
fn clean(alloc: Allocator, raw: []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var blank = false;
    for (raw) |c| {
        if (c <= ' ' or c == 0x7f) {
            blank = out.items.len > 0;
            continue;
        }
        if (blank) try out.append(alloc, ' ');
        blank = false;
        try out.append(alloc, c);
    }
    // Characters start at every byte but UTF-8 continuation bytes.
    var chars: usize = 0;
    for (out.items) |c| chars += @intFromBool(c & 0xC0 != 0x80);
    if (chars > action_max) {
        var seen: usize = 0;
        const cut = for (out.items, 0..) |c, i| {
            if (c & 0xC0 == 0x80) continue;
            if (seen == action_max - 1) break i;
            seen += 1;
        } else out.items.len;
        out.shrinkRetainingCapacity(cut);
        while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') out.items.len -= 1;
        try out.appendSlice(alloc, "\u{2026}");
    }
    return out.toOwnedSlice(alloc);
}

fn stringField(object: std.json.Value, key: []const u8) ?[]const u8 {
    const value = object.object.get(key) orelse return null;
    return if (value == .string) value.string else null;
}

/// Whether `background_tasks` lists a working task other than `except` (the
/// subagent that is stopping; its task id is its agent id).
fn runningTasks(root: std.json.Value, except: ?[]const u8) bool {
    const tasks = root.object.get("background_tasks") orelse return false;
    if (tasks != .array) return false;
    for (tasks.array.items) |task| {
        if (task != .object) continue;
        const kind = stringField(task, "type") orelse continue;
        const is_working = for (working_task_types) |t| {
            if (std.mem.eql(u8, kind, t)) break true;
        } else false;
        if (!is_working) continue;
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

/// OSC 1337 SetUserVar carrying `{"v":1,"state":"<state>"}`, plus
/// `"action"`, `"permission":true` and `"transcript"` when `detail` has
/// them. With `tmux`, wrapped in tmux's DCS passthrough (requires
/// `allow-passthrough on`).
pub fn encodeSequence(alloc: Allocator, state: State, detail: Detail, tmux: bool) ![]u8 {
    const json = try std.json.Stringify.valueAlloc(alloc, .{
        .v = 1,
        .state = @tagName(state),
        .action = detail.action,
        .permission = if (detail.permission) true else null,
        .transcript = detail.transcript,
    }, .{ .emit_null_optional_fields = false });
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
    try t.expectEqual(State.tool, parseState("tool").?);
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
    const seq = try encodeSequence(alloc, .idle, .{}, false);
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
    const seq = try encodeSequence(alloc, .busy, .{}, true);
    defer alloc.free(seq);
    try std.testing.expect(std.mem.startsWith(u8, seq, "\x1bPtmux;\x1b\x1b]1337;SetUserVar=LOSTTY_CLAUDE="));
    try std.testing.expect(std.mem.endsWith(u8, seq, "\x07\x1b\\"));
}

test "claude protocol: Stop with subagents or shells still running reports agents" {
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
    // A background shell counts too; a monitor alone doesn't.
    const shell =
        \\{"hook_event_name":"Stop","background_tasks":[{"id":"b1","type":"shell","status":"running"}]}
    ;
    try t.expectEqual(State.agents, refine(alloc, .idle, shell).?);
    const monitor =
        \\{"hook_event_name":"Stop","background_tasks":[{"id":"m1","type":"monitor","status":"running"}]}
    ;
    try t.expectEqual(State.idle, refine(alloc, .idle, monitor).?);
    try t.expectEqual(State.idle, refine(alloc, .idle, "{\"hook_event_name\":\"Stop\",\"background_tasks\":[]}").?);
    try t.expectEqual(State.idle, refine(alloc, .idle, "{\"hook_event_name\":\"Stop\"}").?);
}

test "claude protocol: SubagentStop resumes only when nothing else still works" {
    const t = std.testing;
    const alloc = t.allocator;
    const last =
        \\{"hook_event_name":"SubagentStop","agent_id":"a7","background_tasks":[
        \\{"id":"a7","type":"subagent","status":"running"},{"id":"m1","type":"monitor","status":"running"}]}
    ;
    try t.expectEqual(State.resumed, refine(alloc, .resumed, last).?);
    const shell =
        \\{"hook_event_name":"SubagentStop","agent_id":"a7","background_tasks":[
        \\{"id":"a7","type":"subagent","status":"running"},{"id":"b1","type":"shell","status":"running"}]}
    ;
    try t.expect(refine(alloc, .resumed, shell) == null);
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

fn decodeSequence(alloc: Allocator, seq: []const u8) ![]u8 {
    const prefix = "\x1b]1337;SetUserVar=LOSTTY_CLAUDE=";
    const b64 = seq[prefix.len .. seq.len - 1];
    const out = try alloc.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(b64));
    try std.base64.standard.Decoder.decode(out, b64);
    return out;
}

test "claude protocol: encodeSequence carries the action and a permission wait" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tool = try encodeSequence(alloc, .tool, .{ .action = "Searching for \"a\\b\"" }, false);
    try t.expectEqualStrings(
        \\{"v":1,"state":"tool","action":"Searching for \"a\\b\""}
    , try decodeSequence(alloc, tool));
    const asks = try encodeSequence(alloc, .idle, .{ .permission = true }, false);
    try t.expectEqualStrings("{\"v\":1,\"state\":\"idle\",\"permission\":true}", try decodeSequence(alloc, asks));
}

test "claude protocol: isPermissionPrompt" {
    const t = std.testing;
    const alloc = t.allocator;
    try t.expect(isPermissionPrompt(alloc, "{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\"}"));
    try t.expect(!isPermissionPrompt(alloc, "{\"hook_event_name\":\"Notification\",\"notification_type\":\"idle_prompt\"}"));
    try t.expect(!isPermissionPrompt(alloc, "{\"hook_event_name\":\"Notification\"}"));
    try t.expect(!isPermissionPrompt(alloc, "{\"hook_event_name\":\"Stop\"}"));
    try t.expect(!isPermissionPrompt(alloc, "not json"));
}

test "claude protocol: action words each tool call" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const cases = [_][2][]const u8{
        .{ "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/a/b/Foo.swift\"}}", "Editing Foo.swift" },
        .{ "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/a/new.md\"}}", "Editing new.md" },
        .{ "{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":\"/n.ipynb\"}}", "Editing n.ipynb" },
        .{ "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/a/TmuxRemote.swift\"}}", "Reading TmuxRemote.swift" },
        .{ "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"listFormat\"}}", "Searching for \"listFormat\"" },
        .{ "{\"tool_name\":\"Glob\",\"tool_input\":{\"pattern\":\"**/*.zig\"}}", "Searching for \"**/*.zig\"" },
        .{ "{\"tool_name\":\"WebSearch\",\"tool_input\":{\"query\":\"tmux hooks\"}}", "Searching for \"tmux hooks\"" },
        .{ "{\"tool_name\":\"WebFetch\",\"tool_input\":{\"url\":\"https://docs.example.com:8/a?b\"}}", "Reading docs.example.com" },
        .{ "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"TOKEN=x make\",\"description\":\"Build the app\"}}", "Build the app" },
        .{ "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"  zig build test\\n  echo done\"}}", "zig build test" },
        .{ "{\"tool_name\":\"Agent\",\"tool_input\":{\"description\":\"Find sources\"}}", "Agent: Find sources" },
        .{ "{\"tool_name\":\"Task\",\"tool_input\":{\"description\":\"Find sources\"}}", "Agent: Find sources" },
        .{ "{\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":[{\"status\":\"completed\",\"activeForm\":\"Old\"},{\"status\":\"in_progress\",\"activeForm\":\"Fixing the header\"}]}}", "Fixing the header" },
        .{ "{\"tool_name\":\"mcp__XcodeBuildMCP__build_sim\",\"tool_input\":{}}", "build_sim" },
        .{ "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"x\"}}", "Skill" },
        // A field missing or blank: the tool's name.
        .{ "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"  \"}}", "Read" },
        .{ "{\"tool_name\":\"Bash\"}", "Bash" },
        // One line, blanks collapsed.
        .{ "{\"tool_name\":\"Bash\",\"tool_input\":{\"description\":\"Run\\tthe\\n\\ntests  \"}}", "Run the tests" },
    };
    for (cases) |c| {
        const input = try std.fmt.allocPrint(alloc, "{{\"hook_event_name\":\"PreToolUse\",{s}", .{c[0][1..]});
        try t.expectEqualStrings(c[1], action(alloc, input) orelse "(null)");
    }
}

test "claude protocol: action caps the line and ignores other input" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const long = "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"description\":\"" ++
        "\u{e9}" ** 100 ++ "\"}}";
    const line = action(alloc, long).?;
    try t.expectEqual(@as(usize, action_max), try std.unicode.utf8CountCodepoints(line));
    try t.expect(std.mem.endsWith(u8, line, "\u{2026}"));
    // A cut that lands after a blank doesn't leave it before the ellipsis.
    const spaced = "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"description\":\"" ++
        "a" ** 78 ++ " " ++ "b" ** 10 ++ "\"}}";
    try t.expectEqualStrings("a" ** 78 ++ "\u{2026}", action(alloc, spaced).?);
    const todo = "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":[{\"status\":\"pending\",\"activeForm\":\"Later\"}]}}";
    try t.expect(action(alloc, todo) == null);
    try t.expect(action(alloc, "{\"hook_event_name\":\"Stop\",\"tool_name\":\"Bash\"}") == null);
    try t.expect(action(alloc, "not json") == null);
    try t.expect(action(alloc, "") == null);
}
test "claude protocol: transcriptPath reads Stop and Notification input" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    try t.expectEqualStrings("/Users/a/.claude/projects/p/s.jsonl", transcriptPath(
        alloc,
        "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"/Users/a/.claude/projects/p/s.jsonl\"}",
    ).?);
    try t.expectEqualStrings("/Users/a/.codex/sessions/r.jsonl", transcriptPath(
        alloc,
        "{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"transcript_path\":\"/Users/a/.codex/sessions/r.jsonl\"}",
    ).?);
    try t.expect(transcriptPath(alloc, "{\"hook_event_name\":\"Stop\"}") == null);
    try t.expect(transcriptPath(alloc, "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"  \"}") == null);
    try t.expect(transcriptPath(alloc, "{\"hook_event_name\":\"Stop\",\"transcript_path\":42}") == null);
    try t.expect(transcriptPath(alloc, "{\"hook_event_name\":\"PreToolUse\",\"transcript_path\":\"/x.jsonl\"}") == null);
    try t.expect(transcriptPath(alloc, "not json") == null);
    try t.expect(transcriptPath(alloc, "") == null);
}

test "claude protocol: transcriptPath drops an over-long path" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const at_max = "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"/" ++ "a" ** (transcript_max - 1) ++ "\"}";
    try t.expectEqual(@as(usize, transcript_max), transcriptPath(alloc, at_max).?.len);
    const over = "{\"hook_event_name\":\"Stop\",\"transcript_path\":\"/" ++ "a" ** transcript_max ++ "\"}";
    try t.expect(transcriptPath(alloc, over) == null);
}

test "claude protocol: encodeSequence carries the transcript" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const done = try encodeSequence(alloc, .idle, .{ .transcript = "/Users/a/.claude/projects/p/s.jsonl" }, false);
    try t.expectEqualStrings(
        "{\"v\":1,\"state\":\"idle\",\"transcript\":\"/Users/a/.claude/projects/p/s.jsonl\"}",
        try decodeSequence(alloc, done),
    );
    const asks = try encodeSequence(alloc, .idle, .{ .permission = true, .transcript = "/t.jsonl" }, false);
    try t.expectEqualStrings(
        "{\"v\":1,\"state\":\"idle\",\"permission\":true,\"transcript\":\"/t.jsonl\"}",
        try decodeSequence(alloc, asks),
    );
}
