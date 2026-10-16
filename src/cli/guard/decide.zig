//! The guard's decision for one PreToolUse hook input: harmless, or
//! critical with everything the approval request shows. Tool names and
//! input fields are the same for Claude Code and Codex (`Bash` with
//! `command`); Codex adds `apply_patch`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const shell = @import("shell.zig");
const catalog = @import("catalog.zig");
const config = @import("config.zig");
const paths = @import("paths.zig");
const git = @import("git.zig");

pub const Critical = struct {
    group: catalog.Group,
    why: []const u8,
    lost: ?[]const u8 = null,
    tool: []const u8,
    input: []const u8,
    cwd: []const u8,
    repo: ?[]const u8 = null,
    branch: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    session: ?[]const u8 = null,
    /// The whole tool input, as an approval keys it (see `toolInput`).
    tool_input: ?[]const u8 = null,
    /// Its size, when `tool_input` is only its hash.
    tool_input_bytes: ?usize = null,
};

pub const Verdict = union(enum) { harmless, critical: Critical };

pub const Env = struct { home: []const u8, tmpdir: ?[]const u8, config: config.Config };

fn str(obj: std.json.Value, key: []const u8) ?[]const u8 {
    if (obj != .object) return null;
    const v = obj.object.get(key) orelse return null;
    return if (v == .string) v.string else null;
}

pub fn decide(alloc: Allocator, e: Env, probe: anytype, input_json: []const u8) Allocator.Error!Verdict {
    const root = std.json.parseFromSliceLeaky(std.json.Value, alloc, input_json, .{}) catch
        return unreadable(alloc, "?", input_json, "/");
    const tool = str(root, "tool_name") orelse return unreadable(alloc, "?", input_json, "/");
    const cwd = str(root, "cwd") orelse e.home;
    const ti = if (root == .object) root.object.get("tool_input") orelse std.json.Value{ .null = {} } else std.json.Value{ .null = {} };
    const ctx: catalog.Ctx = .{ .alloc = alloc, .cwd = cwd, .home = e.home, .tmpdir = e.tmpdir, .config = e.config };

    var input: []const u8 = "";
    var found: ?catalog.Finding = null;
    const is_mcp = std.mem.startsWith(u8, tool, "mcp__");
    const is_bash = std.mem.eql(u8, tool, "Bash");
    const is_patch_tool = std.mem.eql(u8, tool, "apply_patch") or std.mem.eql(u8, tool, "applypatch");
    if (isFileTool(tool)) {
        input = str(ti, "file_path") orelse str(ti, "notebook_path") orelse return unreadable(alloc, tool, input_json, cwd);
        found = try catalog.write(ctx, probe, .{ .text = input, .dynamic = false });
    } else if (is_mcp and mcpLooksCritical(alloc, tool)) {
        input = tool;
        found = .{ .group = .leaving, .why = "an MCP tool named like it deletes, publishes or merges" };
    } else if (if (is_bash) null else patchText(ti, is_patch_tool)) |patch| {
        // Before the `command` branch: Codex sends its patch as `command`.
        input = patch;
        found = try catalog.patch(ctx, probe, patch);
    } else if (is_patch_tool) {
        input = "";
        found = .{ .group = .unreadable, .why = "a patch Lostty can't read" };
    } else if (is_bash or (!is_mcp and ti == .object and ti.object.get("command") != null)) {
        // A `command` that isn't a string (an argv array, say) can't be read.
        input = str(ti, "command") orelse return unreadable(alloc, tool, input_json, cwd);
        found = try bashFinding(ctx, probe, input);
    } else if (is_mcp) {
        input = tool;
    }
    const f = found orelse return .harmless;
    // Bash's `description` is the agent's own words about the command, not
    // part of what runs: a retry that rewords it is still the same call.
    const whole = try toolInput(alloc, if (is_bash) try without(ti, "description") else ti);
    const repo = probe.repoRoot(cwd);
    return .{ .critical = .{
        .group = f.group,
        .why = f.why,
        .lost = f.lost,
        .tool = tool,
        .input = input,
        .cwd = cwd,
        .repo = repo,
        .branch = if (repo) |r| probe.branch(r) else null,
        .reason = str(ti, "description"),
        .session = str(root, "session_id"),
        .tool_input = whole.text,
        .tool_input_bytes = whole.bytes,
    } };
}

/// What an approval keys beyond `input`: the whole tool input, so an
/// approval for one Write or MCP call never covers different content.
/// Above this size it is its SHA-256 instead.
pub const tool_input_cap = 200 * 1024;

pub const ToolInput = struct { text: []const u8, bytes: ?usize = null };

/// `tool_input` re-serialized canonically (object keys sorted), or
/// `sha256:<hex>` and its size when larger than the cap.
pub fn toolInput(alloc: Allocator, v: std.json.Value) Allocator.Error!ToolInput {
    const text = try std.json.Stringify.valueAlloc(alloc, try canonical(alloc, v), .{});
    return capped(alloc, text);
}

/// `v` without the top-level field `key`.
fn without(v: std.json.Value, key: []const u8) Allocator.Error!std.json.Value {
    if (v != .object or v.object.get(key) == null) return v;
    var out = try v.object.clone();
    _ = out.orderedRemove(key);
    return .{ .object = out };
}

fn capped(alloc: Allocator, text: []const u8) Allocator.Error!ToolInput {
    if (text.len <= tool_input_cap) return .{ .text = text };
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(text, &digest, .{});
    return .{ .text = try std.fmt.allocPrint(alloc, "sha256:{s}", .{std.fmt.bytesToHex(digest, .lower)}), .bytes = text.len };
}

fn canonical(alloc: Allocator, v: std.json.Value) Allocator.Error!std.json.Value {
    switch (v) {
        .object => |o| {
            const keys = try alloc.dupe([]const u8, o.keys());
            std.mem.sort([]const u8, keys, {}, struct {
                fn lt(_: void, x: []const u8, y: []const u8) bool {
                    return std.mem.order(u8, x, y) == .lt;
                }
            }.lt);
            var out = std.json.ObjectMap.init(alloc);
            for (keys) |k| try out.put(k, try canonical(alloc, o.get(k).?));
            return .{ .object = out };
        },
        .array => |arr| {
            var out = std.json.Array.init(alloc);
            for (arr.items) |item| try out.append(try canonical(alloc, item));
            return .{ .array = out };
        },
        else => return v,
    }
}

/// At most `max` bytes of `s`, cut on a UTF-8 character boundary.
pub fn truncateUtf8(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    var n = max;
    while (n > 0 and (s[n] & 0xC0) == 0x80) n -= 1;
    return s[0..n];
}

fn unreadable(alloc: Allocator, tool: []const u8, input: []const u8, cwd: []const u8) Allocator.Error!Verdict {
    // The raw input is what an approval keys, so it covers all of it.
    const whole = try capped(alloc, input);
    return .{ .critical = .{
        .group = .unreadable,
        .why = "Lostty couldn't read this tool call",
        .tool = tool,
        .input = truncateUtf8(input, 4096),
        .cwd = cwd,
        .tool_input = whole.text,
        .tool_input_bytes = whole.bytes,
    } };
}

fn isFileTool(tool: []const u8) bool {
    const names = [_][]const u8{ "Write", "Edit", "MultiEdit", "NotebookEdit" };
    for (names) |n| if (std.mem.eql(u8, tool, n)) return true;
    return false;
}

fn bashFinding(ctx_in: catalog.Ctx, probe: anytype, src: []const u8) Allocator.Error!?catalog.Finding {
    const cmds = shell.parse(ctx_in.alloc, src, ctx_in.home) catch |e| switch (e) {
        error.Unparseable => return .{ .group = .unreadable, .why = "a shell command Lostty can't read" },
        error.OutOfMemory => return error.OutOfMemory,
    };
    var ctx = ctx_in;
    // cwd before each open subshell level, to restore when it closes.
    var saved: [64]?[]const u8 = undefined;
    var depth: u8 = 0;
    for (cmds) |c| {
        while (depth < c.depth and depth < saved.len) : (depth += 1) saved[depth] = ctx.cwd;
        while (depth > c.depth) {
            depth -= 1;
            ctx.cwd = saved[depth];
        }
        if (cdTarget(c.argv)) |t| {
            switch (t) {
                .home => ctx.cwd = ctx.home,
                .unknown => ctx.cwd = null,
                .dir => |d| if (ctx.cwd) |cur| {
                    ctx.cwd = try paths.resolve(ctx.alloc, cur, d);
                },
            }
            continue;
        }
        if (try catalog.classify(ctx, probe, c)) |f| return f;
    }
    return null;
}

const CdTarget = union(enum) { home, unknown, dir: []const u8 };

/// Where a `cd`/`pushd` (maybe wrapped in `builtin`/`command`) goes, or
/// null when argv isn't one.
fn cdTarget(argv: []const shell.Word) ?CdTarget {
    var i: usize = 0;
    while (i < argv.len) {
        const w = argv[i];
        if (w.dynamic) return null;
        if (std.mem.eql(u8, w.text, "builtin") or std.mem.eql(u8, w.text, "command")) {
            i += 1;
            while (i < argv.len and !argv[i].dynamic and argv[i].text.len > 1 and argv[i].text[0] == '-') : (i += 1) {}
            continue;
        }
        break;
    }
    if (i >= argv.len or argv[i].dynamic) return null;
    const name = argv[i].text;
    if (!std.mem.eql(u8, name, "cd") and !std.mem.eql(u8, name, "pushd")) return null;
    i += 1;
    while (i < argv.len and !argv[i].dynamic and argv[i].text.len > 1 and argv[i].text[0] == '-') {
        const is_dd = std.mem.eql(u8, argv[i].text, "--");
        i += 1;
        if (is_dd) break;
    }
    if (i >= argv.len) return .home;
    if (argv[i].dynamic or std.mem.eql(u8, argv[i].text, "-")) return .unknown;
    return .{ .dir = argv[i].text };
}

/// A Codex patch: a tool_input string (or any string field, `command`
/// included) that starts with "*** Begin Patch". For apply_patch itself,
/// any field holding a patch line counts (Codex tolerates a wrapper).
fn patchText(ti: std.json.Value, patch_tool: bool) ?[]const u8 {
    const ok = struct {
        fn f(s: []const u8, lenient: bool) bool {
            if (std.mem.startsWith(u8, std.mem.trimLeft(u8, s, " \t\r\n"), "*** Begin Patch")) return true;
            return lenient and catalog.isPatch(s);
        }
    }.f;
    if (ti == .string and ok(ti.string, patch_tool)) return ti.string;
    if (ti != .object) return null;
    var it = ti.object.iterator();
    while (it.next()) |e| if (e.value_ptr.* == .string and ok(e.value_ptr.string, patch_tool)) return e.value_ptr.string;
    return null;
}

fn mcpLooksCritical(alloc: Allocator, tool: []const u8) bool {
    const last = tool[(std.mem.lastIndexOf(u8, tool, "__") orelse 0)..];
    const lower = std.ascii.allocLowerString(alloc, last) catch return true;
    const words = [_][]const u8{ "delete", "remove", "drop", "destroy", "publish", "deploy", "push", "merge" };
    for (words) |w| if (std.mem.indexOf(u8, lower, w) != null) return true;
    return false;
}

const Fake = struct {
    root: ?[]const u8 = "/r",
    dirty: []const []const u8 = &.{},

    pub fn repoRoot(self: Fake, cwd: []const u8) ?[]const u8 {
        const r = self.root orelse return null;
        return if (paths.inside(cwd, r)) r else null;
    }
    pub fn branch(_: Fake, _: []const u8) ?[]const u8 {
        return "feature";
    }
    pub fn changes(self: Fake, _: []const u8, ps: []const []const u8) ?git.Changes {
        var c: git.Changes = .{};
        for (ps) |p| for (self.dirty) |d| {
            if (std.mem.eql(u8, p, d)) c.untracked += 1;
        };
        return c;
    }
    pub fn onlyHere(_: Fake, _: []const u8, _: []const u8) bool {
        return false;
    }
    pub fn headPushed(_: Fake, _: []const u8) bool {
        return false;
    }
};

fn env(a: Allocator) Env {
    return .{ .home = "/Users/me", .tmpdir = null, .config = config.Config.parse(a, "") };
}

fn bash(a: Allocator, cmd: []const u8, cwd: []const u8) ![]const u8 {
    var obj = std.json.ObjectMap.init(a);
    var ti = std.json.ObjectMap.init(a);
    try ti.put("command", .{ .string = cmd });
    try ti.put("description", .{ .string = "Clean up" });
    try obj.put("tool_name", .{ .string = "Bash" });
    try obj.put("tool_input", .{ .object = ti });
    try obj.put("cwd", .{ .string = cwd });
    try obj.put("session_id", .{ .string = "s1" });
    return std.json.Stringify.valueAlloc(a, std.json.Value{ .object = obj }, .{});
}

test "guard decide: harmless and critical Bash" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect(try decide(a, env(a), Fake{}, try bash(a, "ls", "/r")) == .harmless);
    const v = try decide(a, env(a), Fake{}, try bash(a, "git push", "/r"));
    try std.testing.expectEqual(catalog.Group.leaving, v.critical.group);
    try std.testing.expectEqualStrings("git push", v.critical.input);
    try std.testing.expectEqualStrings("Bash", v.critical.tool);
    try std.testing.expectEqualStrings("/r", v.critical.cwd);
    try std.testing.expectEqualStrings("/r", v.critical.repo.?);
    try std.testing.expectEqualStrings("feature", v.critical.branch.?);
    try std.testing.expectEqualStrings("Clean up", v.critical.reason.?);
    try std.testing.expectEqualStrings("s1", v.critical.session.?);
}

test "guard decide: a commit message about rm is harmless" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cmd =
        \\git add -A && git commit -m "$(cat <<'EOF'
        \\Stop the guard from flagging rm -rf build; it's in a message
        \\
        \\Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
        \\EOF
        \\)"
    ;
    try std.testing.expect(try decide(a, env(a), Fake{}, try bash(a, cmd, "/r")) == .harmless);
}

test "guard decide: cd moves where later commands run" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = env(a);
    // In /r, `rm x` is restorable; after `cd /elsewhere` it's outside the repo.
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "rm x", "/r")) == .harmless);
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd /elsewhere && rm x", "/r")) == .critical);
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd ../other && rm -rf src", "/r")) == .critical);
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd $X && rm y", "/r")) == .critical);
    // A subshell's cd doesn't leak out.
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "(cd /elsewhere && ls); rm x", "/r")) == .harmless);
    // cd inside the repo stays fine.
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd sub && rm x", "/r")) == .harmless);
}

test "guard decide: file tools" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inside =
        \\{"tool_name":"Write","tool_input":{"file_path":"/r/a.zig","content":"x"},"cwd":"/r"}
    ;
    const outside =
        \\{"tool_name":"Edit","tool_input":{"file_path":"/Users/me/notes.md","old_string":"a","new_string":"b"},"cwd":"/r"}
    ;
    const settings =
        \\{"tool_name":"Write","tool_input":{"file_path":"/Users/me/.claude/settings.json","content":"{}"},"cwd":"/r"}
    ;
    const memory =
        \\{"tool_name":"Write","tool_input":{"file_path":"/Users/me/.claude/projects/p/memory/x.md","content":"x"},"cwd":"/r"}
    ;
    try std.testing.expect(try decide(a, env(a), Fake{}, inside) == .harmless);
    try std.testing.expectEqual(catalog.Group.outside, (try decide(a, env(a), Fake{}, outside)).critical.group);
    try std.testing.expectEqual(catalog.Group.guardrails, (try decide(a, env(a), Fake{}, settings)).critical.group);
    try std.testing.expect(try decide(a, env(a), Fake{}, memory) == .harmless);
    try std.testing.expectEqualStrings("/Users/me/notes.md", (try decide(a, env(a), Fake{}, outside)).critical.input);
}

test "guard decide: apply_patch as Codex sends it, in `command`" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ok =
        \\{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: src/a.zig\n@@\n-x\n+y\n*** End Patch\n"},"cwd":"/r"}
    ;
    const del =
        \\{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Delete File: notes.md\n*** End Patch\n"},"cwd":"/r"}
    ;
    const away =
        \\{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: /Users/me/x.txt\n+hi\n*** End Patch\n"},"cwd":"/r"}
    ;
    const guardrail =
        \\{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: /Users/me/.codex/hooks.json\n@@\n-a\n+b\n*** End Patch\n"},"cwd":"/r"}
    ;
    const wrapped =
        \\{"tool_name":"apply_patch","tool_input":{"command":"<<'EOF'\n*** Begin Patch\n*** Add File: ../x.txt\n+hi\n*** End Patch\nEOF\n"},"cwd":"/r"}
    ;
    const junk =
        \\{"tool_name":"apply_patch","tool_input":{"command":"rm -rf x"},"cwd":"/r"}
    ;
    const empty =
        \\{"tool_name":"applypatch","tool_input":{},"cwd":"/r"}
    ;
    try std.testing.expect(try decide(a, env(a), Fake{}, ok) == .harmless);
    try std.testing.expectEqual(catalog.Group.deleting, (try decide(a, env(a), Fake{ .dirty = &.{"notes.md"} }, del)).critical.group);
    try std.testing.expect(try decide(a, env(a), Fake{}, del) == .harmless);
    try std.testing.expectEqual(catalog.Group.outside, (try decide(a, env(a), Fake{}, away)).critical.group);
    try std.testing.expectEqual(catalog.Group.guardrails, (try decide(a, env(a), Fake{}, guardrail)).critical.group);
    try std.testing.expectEqual(catalog.Group.outside, (try decide(a, env(a), Fake{}, wrapped)).critical.group);
    try std.testing.expectEqual(catalog.Group.unreadable, (try decide(a, env(a), Fake{}, junk)).critical.group);
    try std.testing.expectEqual(catalog.Group.unreadable, (try decide(a, env(a), Fake{}, empty)).critical.group);
    // A Bash command written as a patch is still read as Bash.
    try std.testing.expectEqual(catalog.Group.leaving, (try decide(a, env(a), Fake{}, try bash(a, "*** Begin Patch\ngit push", "/r"))).critical.group);
}

test "guard decide: apply_patch through Bash" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cmd = "apply_patch <<'EOF'\n*** Begin Patch\n*** Add File: /Users/me/x.txt\n+hi\n*** End Patch\nEOF\n";
    try std.testing.expectEqual(catalog.Group.outside, (try decide(a, env(a), Fake{}, try bash(a, cmd, "/r"))).critical.group);
    try std.testing.expect(try decide(a, env(a), Fake{}, try bash(a, "cd src && apply_patch <<'EOF'\n*** Begin Patch\n*** Add File: x.txt\n+hi\n*** End Patch\nEOF", "/r")) == .harmless);
}

test "guard decide: a command that isn't a string can't be read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const arr =
        \\{"tool_name":"shell","tool_input":{"command":["bash","-lc","rm -rf ~"]},"cwd":"/r"}
    ;
    const num =
        \\{"tool_name":"Bash","tool_input":{"command":42},"cwd":"/r"}
    ;
    try std.testing.expectEqual(catalog.Group.unreadable, (try decide(a, env(a), Fake{}, arr)).critical.group);
    try std.testing.expectEqual(catalog.Group.unreadable, (try decide(a, env(a), Fake{}, num)).critical.group);
}

test "guard decide: apply_patch in the older `input` shape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ok =
        \\{"tool_name":"apply_patch","tool_input":{"input":"*** Begin Patch\n*** Update File: src/a.zig\n@@\n-x\n+y\n*** End Patch"},"cwd":"/r"}
    ;
    const del =
        \\{"tool_name":"apply_patch","tool_input":{"input":"*** Begin Patch\n*** Delete File: notes.md\n*** End Patch"},"cwd":"/r"}
    ;
    const away =
        \\{"tool_name":"apply_patch","tool_input":{"input":"*** Begin Patch\n*** Add File: ../x.txt\n+hi\n*** End Patch"},"cwd":"/r"}
    ;
    try std.testing.expect(try decide(a, env(a), Fake{}, ok) == .harmless);
    try std.testing.expectEqual(catalog.Group.deleting, (try decide(a, env(a), Fake{ .dirty = &.{"notes.md"} }, del)).critical.group);
    try std.testing.expect(try decide(a, env(a), Fake{}, del) == .harmless);
    try std.testing.expectEqual(catalog.Group.outside, (try decide(a, env(a), Fake{}, away)).critical.group);
}

test "guard decide: mcp tools, other tools, and junk" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mcp =
        \\{"tool_name":"mcp__github__delete_branch","tool_input":{},"cwd":"/r"}
    ;
    const read =
        \\{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"},"cwd":"/r"}
    ;
    try std.testing.expectEqual(catalog.Group.leaving, (try decide(a, env(a), Fake{}, mcp)).critical.group);
    try std.testing.expect(try decide(a, env(a), Fake{}, read) == .harmless);
    try std.testing.expectEqual(catalog.Group.unreadable, (try decide(a, env(a), Fake{}, "not json")).critical.group);
    try std.testing.expectEqual(catalog.Group.unreadable, (try decide(a, env(a), Fake{}, try bash(a, "echo \"oops", "/r"))).critical.group);
}

const NoGit = struct {
    pub fn repoRoot(_: NoGit, _: []const u8) ?[]const u8 {
        @panic("harmless call started git: repoRoot");
    }
    pub fn branch(_: NoGit, _: []const u8) ?[]const u8 {
        @panic("harmless call started git: branch");
    }
    pub fn changes(_: NoGit, _: []const u8, _: []const []const u8) ?git.Changes {
        @panic("harmless call started git: changes");
    }
    pub fn onlyHere(_: NoGit, _: []const u8, _: []const u8) bool {
        @panic("harmless call started git: onlyHere");
    }
    pub fn headPushed(_: NoGit, _: []const u8) bool {
        @panic("harmless call started git: headPushed");
    }
};

test "guard decide: harmless calls never touch git" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = env(a);
    const inputs = [_][]const u8{
        try bash(a, "ls", "/r"),
        try bash(a, "git status", "/r"),
        \\{"tool_name":"Write","tool_input":{"file_path":"/r/a.zig","content":"x"},"cwd":"/r"}
        ,
        \\{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"},"cwd":"/r"}
        ,
    };
    for (inputs) |i| try std.testing.expect(try decide(a, e, NoGit{}, i) == .harmless);
}

test "guard decide: cd flags and wrapped cd" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = env(a);
    const crit = [_][]const u8{
        "cd -P /elsewhere && rm x",
        "cd -- /elsewhere && rm x",
        "builtin cd /elsewhere && rm x",
        "command cd /elsewhere && rm x",
        "command -p cd /elsewhere && rm x",
    };
    for (crit) |c| try std.testing.expect(try decide(a, e, Fake{}, try bash(a, c, "/r")) == .critical);
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd -L sub && rm x", "/r")) == .harmless);
}

test "guard decide: other shell tools and mcp before patch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const push =
        \\{"tool_name":"shell","tool_input":{"command":"git push"},"cwd":"/r"}
    ;
    const ls =
        \\{"tool_name":"shell","tool_input":{"command":"ls"},"cwd":"/r"}
    ;
    const mcp =
        \\{"tool_name":"mcp__x__delete_branch","tool_input":{"p":"*** Begin Patch\n*** Update File: a\n*** End Patch"},"cwd":"/r"}
    ;
    try std.testing.expectEqual(catalog.Group.leaving, (try decide(a, env(a), Fake{}, push)).critical.group);
    try std.testing.expect(try decide(a, env(a), Fake{}, ls) == .harmless);
    try std.testing.expectEqual(catalog.Group.leaving, (try decide(a, env(a), Fake{}, mcp)).critical.group);
}

test "guard decide: file tools win over a command field; more cd forms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = env(a);
    const w =
        \\{"tool_name":"Write","tool_input":{"file_path":"/Users/me/.ssh/x","command":"ls"},"cwd":"/r"}
    ;
    try std.testing.expectEqual(catalog.Group.guardrails, (try decide(a, e, Fake{}, w)).critical.group);
    // No target after flags goes home, which is outside the repo.
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd -P && rm x", "/r")) == .critical);
    // `--` ends the flags: the next word is the directory, even if it starts with `-`.
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd -- -weird-dir && rm x", "/r")) == .harmless);
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd -- /elsewhere/-d && rm x", "/r")) == .critical);
    // A lone `-` is unknown.
    try std.testing.expect(try decide(a, e, Fake{}, try bash(a, "cd - && rm x", "/r")) == .critical);
}

test "guard decide: the whole tool input goes with the request" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const w1 =
        \\{"tool_name":"Write","tool_input":{"file_path":"/Users/me/notes.md","content":"one"},"cwd":"/r"}
    ;
    const w2 =
        \\{"tool_name":"Write","tool_input":{"content":"two","file_path":"/Users/me/notes.md"},"cwd":"/r"}
    ;
    const c1 = (try decide(a, env(a), Fake{}, w1)).critical;
    const c2 = (try decide(a, env(a), Fake{}, w2)).critical;
    try std.testing.expectEqualStrings(c1.input, c2.input);
    // Keys sorted, whatever order the agent sent them in.
    try std.testing.expectEqualStrings("{\"content\":\"one\",\"file_path\":\"/Users/me/notes.md\"}", c1.tool_input.?);
    try std.testing.expectEqualStrings("{\"content\":\"two\",\"file_path\":\"/Users/me/notes.md\"}", c2.tool_input.?);
    try std.testing.expect(c1.tool_input_bytes == null);
    const m =
        \\{"tool_name":"mcp__gh__delete_branch","tool_input":{"repo":"o/r","branch":"x"},"cwd":"/r"}
    ;
    try std.testing.expectEqualStrings("{\"branch\":\"x\",\"repo\":\"o/r\"}", (try decide(a, env(a), Fake{}, m)).critical.tool_input.?);
    // Bash keeps the command as input and sends the tool input too.
    const b = (try decide(a, env(a), Fake{}, try bash(a, "git push", "/r"))).critical;
    try std.testing.expectEqualStrings("git push", b.input);
    try std.testing.expect(std.mem.indexOf(u8, b.tool_input.?, "\"command\":\"git push\"") != null);
    // A reworded description is the same call; a different timeout isn't.
    try std.testing.expect(std.mem.indexOf(u8, b.tool_input.?, "Clean up") == null);
    const t1 =
        \\{"tool_name":"Bash","tool_input":{"command":"git push","description":"Push","timeout":1000},"cwd":"/r"}
    ;
    const t2 =
        \\{"tool_name":"Bash","tool_input":{"command":"git push","description":"Push it now","timeout":1000},"cwd":"/r"}
    ;
    const t3 =
        \\{"tool_name":"Bash","tool_input":{"command":"git push","description":"Push","timeout":2000},"cwd":"/r"}
    ;
    const k1 = (try decide(a, env(a), Fake{}, t1)).critical.tool_input.?;
    try std.testing.expectEqualStrings(k1, (try decide(a, env(a), Fake{}, t2)).critical.tool_input.?);
    try std.testing.expect(!std.mem.eql(u8, k1, (try decide(a, env(a), Fake{}, t3)).critical.tool_input.?));
}

test "guard decide: a huge tool input is sent as its hash" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const big = try a.alloc(u8, tool_input_cap + 10);
    @memset(big, 'x');
    const json = try std.fmt.allocPrint(a, "{{\"tool_name\":\"Write\",\"tool_input\":{{\"file_path\":\"/Users/me/x\",\"content\":\"{s}\"}},\"cwd\":\"/r\"}}", .{big});
    const c = (try decide(a, env(a), Fake{}, json)).critical;
    try std.testing.expect(std.mem.startsWith(u8, c.tool_input.?, "sha256:"));
    try std.testing.expectEqual(@as(usize, "sha256:".len + 64), c.tool_input.?.len);
    try std.testing.expect(c.tool_input_bytes.? > tool_input_cap);
}

test "guard decide: unreadable input is cut on a character boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 4095 ASCII bytes, then a 3-byte character across the 4096 cap.
    const junk = try std.mem.concat(a, u8, &.{ "x" ** 4095, "\u{2603}", "tail" });
    const c = (try decide(a, env(a), Fake{}, junk)).critical;
    try std.testing.expectEqual(catalog.Group.unreadable, c.group);
    try std.testing.expectEqual(@as(usize, 4095), c.input.len);
    try std.testing.expect(std.unicode.utf8ValidateSlice(c.input));
    try std.testing.expectEqualStrings(junk, c.tool_input.?);
}
