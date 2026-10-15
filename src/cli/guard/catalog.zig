//! The guard's catalog: which commands are critical. Spec §7.2. A command
//! is critical when it deletes what git can't get back, throws work away,
//! leaves the Mac, merges into a protected branch, touches the guardrails,
//! writes outside the project, or can't be read. Everything else returns
//! null and goes through without asking.

const std = @import("std");
const Allocator = std.mem.Allocator;
const shell = @import("shell.zig");
const config = @import("config.zig");
const paths = @import("paths.zig");
const git = @import("git.zig");

pub const Group = enum { deleting, discarding, leaving, merging, guardrails, outside, unreadable };

pub fn label(g: Group) []const u8 {
    return switch (g) {
        .deleting => "Deleting",
        .discarding => "Throwing work away",
        .leaving => "Leaving the Mac",
        .merging => "Merging into a protected branch",
        .guardrails => "Changing the guardrails",
        .outside => "Writing outside the project",
        .unreadable => "A command Lostty can't read",
    };
}

pub const Finding = struct { group: Group, why: []const u8, lost: ?[]const u8 = null };

pub const Ctx = struct {
    alloc: Allocator,
    cwd: ?[]const u8,
    home: []const u8,
    tmpdir: ?[]const u8,
    config: config.Config,
};

const Error = Allocator.Error;

fn base(s: []const u8) []const u8 {
    return std.fs.path.basename(s);
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn has(argv: []const shell.Word, flag: []const u8) bool {
    for (argv) |w| if (!w.dynamic and eq(w.text, flag)) return true;
    return false;
}

/// A short flag set like `-fdx` contains `c`.
fn hasShort(argv: []const shell.Word, c: u8) bool {
    for (argv) |w| {
        if (w.dynamic or w.text.len < 2 or w.text[0] != '-' or w.text[1] == '-') continue;
        if (std.mem.indexOfScalar(u8, w.text[1..], c) != null) return true;
    }
    return false;
}

fn operands(alloc: Allocator, argv: []const shell.Word) Error![]const shell.Word {
    var out: std.ArrayList(shell.Word) = .empty;
    var dashdash = false;
    for (argv) |w| {
        if (!dashdash and !w.dynamic and eq(w.text, "--")) {
            dashdash = true;
            continue;
        }
        if (!dashdash and !w.dynamic and w.text.len > 0 and w.text[0] == '-') continue;
        try out.append(alloc, w);
    }
    return out.toOwnedSlice(alloc);
}

fn finding(g: Group, why: []const u8) ?Finding {
    return .{ .group = g, .why = why };
}

pub fn classify(ctx: Ctx, probe: anytype, cmd: shell.Command) Error!?Finding {
    // Writes first: a redirect to a guardrail or outside is critical
    // whatever the command.
    for (cmd.writes) |w| if (try write(ctx, probe, w)) |f| return f;
    return command(ctx, probe, cmd.argv);
}

fn command(ctx: Ctx, probe: anytype, argv_in: []const shell.Word) Error!?Finding {
    var argv = argv_in;
    if (argv.len == 0) return null;
    // Unwrap commands that run another one.
    while (argv.len > 0 and !argv[0].dynamic) {
        const name = base(argv[0].text);
        if (eq(name, "sudo") or eq(name, "command") or eq(name, "nohup") or eq(name, "exec") or eq(name, "time")) {
            argv = argv[1..];
        } else if (eq(name, "env")) {
            argv = argv[1..];
            while (argv.len > 0 and !argv[0].dynamic and (std.mem.indexOfScalar(u8, argv[0].text, '=') != null or (argv[0].text.len > 0 and argv[0].text[0] == '-'))) argv = argv[1..];
        } else if (eq(name, "nice") or eq(name, "timeout")) {
            argv = argv[1..];
            while (argv.len > 0 and !argv[0].dynamic and argv[0].text.len > 0 and (argv[0].text[0] == '-' or std.ascii.isDigit(argv[0].text[0]))) argv = argv[1..];
        } else break;
    }
    if (argv.len == 0) return null;
    // Before the name check: `"$LOSTTY_BIN" +claude-hooks remove` has a
    // variable for a name but is plainly Lostty's hooks command.
    if (has(argv, "+claude-hooks") and (has(argv, "remove") or has(argv, "install"))) return finding(.guardrails, "changes Lostty's agent hooks, which run the guard");
    if (argv[0].dynamic) return finding(.unreadable, "runs a command named by a variable or another command's output");
    const name = base(argv[0].text);
    const args = argv[1..];

    // Scripts you listed as critical. findRepo reads the filesystem only:
    // no git process for an everyday command.
    const eff = try ctx.config.forRepo(ctx.alloc, if (ctx.cwd) |c| paths.findRepo(ctx.alloc, c) else null);
    for (eff.commands) |c| if (eq(name, base(c)) or eq(argv[0].text, c)) {
        return .{ .group = .leaving, .why = try std.fmt.allocPrint(ctx.alloc, "{s} is on your list of critical commands", .{name}) };
    };

    if (eq(name, "sh") or eq(name, "bash") or eq(name, "zsh") or eq(name, "dash")) {
        for (args, 0..) |w, i| if (!w.dynamic and eq(w.text, "-c")) {
            if (i + 1 >= args.len or args[i + 1].dynamic) return finding(.unreadable, "runs a shell string Lostty can't read");
            return inner(ctx, probe, args[i + 1].text);
        };
        return null;
    }
    if (eq(name, "eval")) {
        var parts: std.ArrayList([]const u8) = .empty;
        for (args) |w| {
            if (w.dynamic) return finding(.unreadable, "eval runs text Lostty can't read");
            try parts.append(ctx.alloc, w.text);
        }
        return inner(ctx, probe, try std.mem.join(ctx.alloc, " ", parts.items));
    }
    if (eq(name, "xargs")) {
        var i: usize = 0;
        while (i < args.len and !args[i].dynamic and args[i].text.len > 0 and args[i].text[0] == '-') : (i += 1) {
            const f = args[i].text;
            if (f.len == 2 and std.mem.indexOfScalar(u8, "nIPLsdE", f[1]) != null) i += 1; // takes a value
        }
        if (i >= args.len) return null;
        const inner_name = base(args[i].text);
        if (isRemover(inner_name)) return finding(.deleting, "xargs deletes paths it reads from its input, which Lostty can't see");
        return command(ctx, probe, args[i..]);
    }

    if (isRemover(name)) return deletion(ctx, probe, try operands(ctx.alloc, args));
    if (eq(name, "shred") or eq(name, "srm")) return finding(.deleting, "shred destroys files for good");
    if (eq(name, "find")) {
        if (has(args, "-delete")) return finding(.deleting, "find -delete removes whatever matches, which Lostty can't see");
        for (args, 0..) |w, i| if (!w.dynamic and (eq(w.text, "-exec") or eq(w.text, "-execdir") or eq(w.text, "-ok")) and i + 1 < args.len and isRemover(base(args[i + 1].text))) {
            return finding(.deleting, "find runs rm on whatever matches, which Lostty can't see");
        };
        return null;
    }
    if (eq(name, "security")) return finding(.guardrails, "security reads or changes your Keychain");
    if (eq(name, "git")) return gitCommand(ctx, probe, args);
    if (eq(name, "gh")) return ghCommand(args);
    if ((eq(name, "npm") or eq(name, "pnpm") or eq(name, "yarn") or eq(name, "cargo")) and has(args, "publish")) return finding(.leaving, "publishes a package");
    if (eq(name, "gem") and has(args, "push")) return finding(.leaving, "publishes a gem");
    if (eq(name, "twine") and has(args, "upload")) return finding(.leaving, "publishes a Python package");
    if (eq(name, "pod") and has(args, "trunk")) return finding(.leaving, "publishes a pod");
    if (eq(name, "scp") or eq(name, "rsync")) {
        for (try operands(ctx.alloc, args)) |w| if (w.dynamic or isRemote(w.text)) return finding(.leaving, "copies files to another machine");
    }
    if (eq(name, "docker") or eq(name, "podman")) {
        if (has(args, "rm") or has(args, "rmi") or has(args, "prune") or (has(args, "down") and hasShort(args, 'v'))) return finding(.deleting, "removes containers, images or volumes");
    }
    if (eq(name, "kubectl") and has(args, "delete")) return finding(.deleting, "deletes cluster resources");
    if (eq(name, "psql") or eq(name, "mysql") or eq(name, "sqlite3") or eq(name, "duckdb")) {
        for (args) |w| if (w.dynamic or sqlDestroys(ctx.alloc, w.text)) return finding(.deleting, "runs SQL that drops, truncates or deletes data");
    }
    if (eq(name, "cp") or eq(name, "mv") or eq(name, "install") or eq(name, "ln")) {
        const ops = try operands(ctx.alloc, args);
        if (ops.len >= 2) return write(ctx, probe, ops[ops.len - 1]);
        return null;
    }
    if (eq(name, "tee") or eq(name, "truncate") or eq(name, "chmod") or eq(name, "chown")) {
        for (try operands(ctx.alloc, args)) |w| if (try write(ctx, probe, w)) |f| return f;
        return null;
    }
    if ((eq(name, "sed") or eq(name, "perl")) and (has(args, "-i") or hasShort(args, 'i'))) {
        const ops = try operands(ctx.alloc, args);
        // sed's first operand is the script (unless -e gave it).
        const files = if (has(args, "-e") or ops.len == 0) ops else ops[1..];
        for (files) |w| if (try write(ctx, probe, w)) |f| return f;
        return null;
    }
    if (eq(name, "dd")) {
        for (args) |w| if (!w.dynamic and std.mem.startsWith(u8, w.text, "of=")) {
            return write(ctx, probe, .{ .text = w.text[3..], .dynamic = false });
        };
    }
    return null;
}

fn isRemover(name: []const u8) bool {
    return eq(name, "rm") or eq(name, "rmdir") or eq(name, "unlink") or eq(name, "trash");
}

fn isRemote(s: []const u8) bool {
    if (s.len == 0 or s[0] == '/' or s[0] == '.') return false;
    const colon = std.mem.indexOfScalar(u8, s, ':') orelse return false;
    return std.mem.indexOfScalar(u8, s[0..colon], '/') == null;
}

fn sqlDestroys(alloc: Allocator, s: []const u8) bool {
    const up = std.ascii.allocUpperString(alloc, s) catch return true;
    return std.mem.indexOf(u8, up, "DROP ") != null or std.mem.indexOf(u8, up, "TRUNCATE") != null or
        std.mem.indexOf(u8, up, "DELETE FROM") != null;
}

fn inner(ctx: Ctx, probe: anytype, src: []const u8) Error!?Finding {
    const cmds = shell.parse(ctx.alloc, src, ctx.home) catch |e| switch (e) {
        error.Unparseable => return finding(.unreadable, "runs a shell string Lostty can't read"),
        error.OutOfMemory => return error.OutOfMemory,
    };
    for (cmds) |c| if (try classify(ctx, probe, c)) |f| return f;
    return null;
}

/// The rm family, and apply_patch's deletes: critical unless every target
/// is inside the repo and git can restore it (or it's a `deletable` folder).
pub fn deletion(ctx: Ctx, probe: anytype, words: []const shell.Word) Error!?Finding {
    if (words.len == 0) return null;
    const cwd = ctx.cwd orelse return finding(.deleting, "deletes from a folder Lostty can't work out");
    for (words) |w| if (w.dynamic) return finding(.deleting, "deletes paths held in a variable or another command's output");
    const root = probe.repoRoot(cwd) orelse return finding(.deleting, "deletes outside any git repo, so git can't restore it");
    const eff = try ctx.config.forRepo(ctx.alloc, root);
    var rels: std.ArrayList([]const u8) = .empty;
    for (words) |w| {
        const abs = try paths.resolve(ctx.alloc, cwd, w.text);
        if (paths.isGuardrail(abs, ctx.home)) return finding(.guardrails, "deletes a file the guard depends on");
        if (!paths.inside(abs, root)) return .{ .group = .deleting, .why = try std.fmt.allocPrint(ctx.alloc, "deletes {s}, outside the repo, so git can't restore it", .{abs}) };
        const rel = if (abs.len == root.len) "." else abs[root.len + 1 ..];
        if (isDeletable(rel, eff.deletable)) continue;
        try rels.append(ctx.alloc, rel);
    }
    if (rels.items.len == 0) return null;
    const changes = probe.changes(root, rels.items) orelse return finding(.deleting, "git couldn't check what this would delete");
    if (changes.total() == 0) return null;
    return .{ .group = .deleting, .why = "deletes files git can't restore", .lost = try changes.describe(ctx.alloc) };
}

fn isDeletable(rel: []const u8, names: []const []const u8) bool {
    var it = std.mem.splitScalar(u8, rel, '/');
    while (it.next()) |part| for (names) |n| if (eq(part, n)) return true;
    return false;
}

/// A file tool's write, or a shell write: critical for guardrails and for
/// places outside the project (the repo, or the folder when there's none).
pub fn write(ctx: Ctx, probe: anytype, w: shell.Word) Error!?Finding {
    if (w.dynamic) return finding(.outside, "writes to a path held in a variable");
    if (std.mem.startsWith(u8, w.text, "/dev/") and !eq(w.text, "/dev/null") and !std.mem.startsWith(u8, w.text, "/dev/std") and !std.mem.startsWith(u8, w.text, "/dev/fd/")) {
        return finding(.outside, "writes to a device");
    }
    if (std.mem.startsWith(u8, w.text, "/dev/")) return null;
    const cwd = ctx.cwd orelse return finding(.outside, "writes from a folder Lostty can't work out");
    const abs = try paths.resolve(ctx.alloc, cwd, w.text);
    if (paths.isGuardrail(abs, ctx.home)) return finding(.guardrails, "changes a file the guard depends on");
    if (paths.isWriteExempt(abs, ctx.home, ctx.tmpdir)) return null;
    const project = probe.repoRoot(cwd) orelse cwd;
    if (paths.inside(abs, project)) return null;
    return .{ .group = .outside, .why = try std.fmt.allocPrint(ctx.alloc, "writes {s}, outside the project", .{abs}) };
}

fn gitCommand(ctx_in: Ctx, probe: anytype, args_in: []const shell.Word) Error!?Finding {
    var ctx = ctx_in;
    var args = args_in;
    // Global options before the subcommand.
    while (args.len > 0 and !args[0].dynamic and args[0].text.len > 0 and args[0].text[0] == '-') {
        if ((eq(args[0].text, "-C") or eq(args[0].text, "-c")) and args.len > 1) {
            if (eq(args[0].text, "-C")) {
                if (args[1].dynamic) return finding(.unreadable, "runs git in a folder held in a variable");
                if (ctx.cwd) |c| ctx.cwd = try paths.resolve(ctx.alloc, c, args[1].text);
            }
            args = args[2..];
        } else args = args[1..];
    }
    if (args.len == 0 or args[0].dynamic) return null;
    const sub = args[0].text;
    const rest = args[1..];
    const root: ?[]const u8 = if (ctx.cwd) |c| probe.repoRoot(c) else null;

    if (eq(sub, "push")) return push(ctx, probe, root, rest);
    if (eq(sub, "clean")) {
        if ((has(rest, "--force") or hasShort(rest, 'f')) and !has(rest, "--dry-run") and !hasShort(rest, 'n'))
            return finding(.deleting, "git clean deletes untracked files git can't restore");
        return null;
    }
    if (eq(sub, "reset") and has(rest, "--hard")) return finding(.discarding, "git reset --hard throws away uncommitted changes");
    if (eq(sub, "rebase")) {
        if (has(rest, "--continue") or has(rest, "--abort") or has(rest, "--quit")) return null;
        return finding(.discarding, "git rebase rewrites history");
    }
    if (eq(sub, "filter-branch") or eq(sub, "filter-repo")) return finding(.discarding, "rewrites the whole history");
    if (eq(sub, "reflog") and (has(rest, "expire") or has(rest, "delete"))) return finding(.discarding, "removes git's record of old commits, its safety net");
    if (eq(sub, "gc")) for (rest) |w| if (!w.dynamic and std.mem.startsWith(u8, w.text, "--prune=")) return finding(.discarding, "prunes unreachable commits for good");
    if (eq(sub, "switch") and (has(rest, "-f") or has(rest, "--force") or has(rest, "--discard-changes"))) return finding(.discarding, "switches branch and throws away changes");
    if (eq(sub, "checkout")) {
        if (has(rest, "-f") or has(rest, "--force")) return finding(.discarding, "checks out over uncommitted changes");
        var after: []const shell.Word = &.{};
        for (rest, 0..) |w, i| if (!w.dynamic and eq(w.text, "--")) {
            after = rest[i + 1 ..];
        };
        if (after.len == 0 and has(rest, ".")) after = &.{.{ .text = ".", .dynamic = false }};
        if (after.len > 0) return discards(ctx, probe, root, after);
        return null;
    }
    if (eq(sub, "restore")) {
        if (has(rest, "--staged") and !has(rest, "--worktree") and !hasShort(rest, 'W')) return null;
        return discards(ctx, probe, root, try operands(ctx.alloc, rest));
    }
    if (eq(sub, "commit") and has(rest, "--amend")) {
        const r = root orelse return null;
        if (probe.headPushed(r)) return finding(.discarding, "amends a commit that's already pushed");
        return null;
    }
    if (eq(sub, "stash") and (has(rest, "drop") or has(rest, "clear"))) return finding(.deleting, "drops stashed work");
    if (eq(sub, "tag") and (has(rest, "-d") or has(rest, "--delete"))) return finding(.deleting, "deletes a tag");
    if (eq(sub, "update-ref") and has(rest, "-d")) return finding(.deleting, "deletes a ref");
    if (eq(sub, "branch") and (has(rest, "-d") or has(rest, "-D") or has(rest, "--delete"))) {
        const r = root orelse return finding(.deleting, "deletes a branch outside any repo Lostty can check");
        for (try operands(ctx.alloc, rest)) |w| {
            if (w.dynamic) return finding(.deleting, "deletes a branch named by a variable");
            if (probe.onlyHere(r, w.text)) return .{ .group = .deleting, .why = try std.fmt.allocPrint(ctx.alloc, "deletes branch {s}, whose commits are on no other branch", .{w.text}) };
        }
        return null;
    }
    if (eq(sub, "worktree") and rest.len > 0 and !rest[0].dynamic and eq(rest[0].text, "remove")) {
        if (has(rest, "--force") or hasShort(rest[1..], 'f')) return finding(.deleting, "removes a worktree with --force, uncommitted work included");
        const ops = try operands(ctx.alloc, rest[1..]);
        if (ops.len == 0) return null;
        if (ops[0].dynamic or ctx.cwd == null) return finding(.deleting, "removes a worktree Lostty can't check");
        const wt = try paths.resolve(ctx.alloc, ctx.cwd.?, ops[0].text);
        const c = probe.changes(wt, &.{"."}) orelse return finding(.deleting, "git couldn't check the worktree");
        if (c.ignored > 0) return .{ .group = .deleting, .why = "removes a worktree and its ignored files", .lost = try c.describe(ctx.alloc) };
        return null;
    }
    if (eq(sub, "merge")) {
        if (has(rest, "--abort") or has(rest, "--continue")) return null;
        const r = root orelse return null;
        const current = probe.branch(r) orelse return null;
        const eff = try ctx.config.forRepo(ctx.alloc, r);
        for (eff.protected_branches) |b| if (eq(b, current)) {
            return .{ .group = .merging, .why = try std.fmt.allocPrint(ctx.alloc, "merges into {s}, a protected branch", .{current}) };
        };
        return null;
    }
    return null;
}

fn discards(ctx: Ctx, probe: anytype, root: ?[]const u8, targets: []const shell.Word) Error!?Finding {
    const r = root orelse return finding(.discarding, "discards changes outside any repo Lostty can check");
    const cwd = ctx.cwd orelse return finding(.discarding, "discards changes from a folder Lostty can't work out");
    var rels: std.ArrayList([]const u8) = .empty;
    for (targets) |w| {
        if (w.dynamic) return finding(.discarding, "discards changes in paths held in a variable");
        const abs = try paths.resolve(ctx.alloc, cwd, w.text);
        try rels.append(ctx.alloc, if (abs.len <= r.len) "." else abs[r.len + 1 ..]);
    }
    const c = probe.changes(r, rels.items) orelse return finding(.discarding, "git couldn't check what this would discard");
    if (c.changed == 0) return null;
    return .{ .group = .discarding, .why = "throws away uncommitted changes", .lost = try (git.Changes{ .changed = c.changed }).describe(ctx.alloc) };
}

fn push(ctx: Ctx, probe: anytype, root: ?[]const u8, rest: []const shell.Word) Error!?Finding {
    const eff = try ctx.config.forRepo(ctx.alloc, root);
    const forced = has(rest, "--force") or has(rest, "--force-with-lease") or hasShort(rest, 'f') or has(rest, "--mirror");
    if (eff.push == .all) return finding(.leaving, if (forced) "git push --force overwrites the remote" else "git push sends commits off this Mac");
    // push = protected: only force, tags, deletes, and protected branches.
    if (forced) return finding(.leaving, "git push --force overwrites the remote");
    if (has(rest, "--tags") or has(rest, "--delete") or hasShort(rest, 'd')) return finding(.leaving, "pushes tags or deletes on the remote");
    const ops = try operands(ctx.alloc, rest);
    if (ops.len >= 2) {
        for (ops[1..]) |w| {
            if (w.dynamic) return finding(.leaving, "pushes a branch named by a variable");
            const dst = if (std.mem.indexOfScalar(u8, w.text, ':')) |i| w.text[i + 1 ..] else w.text;
            const name = if (std.mem.startsWith(u8, dst, "refs/heads/")) dst["refs/heads/".len..] else dst;
            for (eff.protected_branches) |b| if (eq(b, name)) return .{ .group = .leaving, .why = try std.fmt.allocPrint(ctx.alloc, "pushes to {s}, a protected branch", .{name}) };
        }
        return null;
    }
    const r = root orelse return finding(.leaving, "git push from outside a repo Lostty can check");
    const current = probe.branch(r) orelse return finding(.leaving, "git push from a detached HEAD");
    for (eff.protected_branches) |b| if (eq(b, current)) return .{ .group = .leaving, .why = try std.fmt.allocPrint(ctx.alloc, "pushes {s}, a protected branch", .{current}) };
    return null;
}

fn ghCommand(args: []const shell.Word) ?Finding {
    if (args.len < 2 or args[0].dynamic or args[1].dynamic) return null;
    const a = args[0].text;
    const b = args[1].text;
    if (eq(a, "pr") and (eq(b, "create") or eq(b, "merge"))) return finding(.leaving, "acts on GitHub: a pull request");
    if (eq(a, "issue") and eq(b, "create")) return finding(.leaving, "creates a GitHub issue");
    if (eq(a, "release") and (eq(b, "create") or eq(b, "delete") or eq(b, "upload"))) return finding(.leaving, "changes a GitHub release");
    if (eq(a, "repo") and (eq(b, "create") or eq(b, "delete") or eq(b, "archive") or eq(b, "rename"))) return finding(.leaving, "changes a GitHub repository");
    if (eq(a, "api")) {
        for (args, 0..) |w, i| if (!w.dynamic and (eq(w.text, "-X") or eq(w.text, "--method")) and i + 1 < args.len) {
            if (!eq(args[i + 1].text, "GET")) return finding(.leaving, "changes something on GitHub through its API");
        };
    }
    return null;
}

const Fake = struct {
    root: ?[]const u8 = "/r",
    current: ?[]const u8 = "feature",
    /// Paths (as given, relative to the root) that are untracked.
    dirty: []const []const u8 = &.{},
    /// Paths with uncommitted changes to tracked files.
    changed: []const []const u8 = &.{},
    only_here: bool = false,
    pushed: bool = false,
    git_fails: bool = false,

    pub fn repoRoot(self: Fake, cwd: []const u8) ?[]const u8 {
        const r = self.root orelse return null;
        return if (paths.inside(cwd, r)) r else null;
    }
    pub fn branch(self: Fake, _: []const u8) ?[]const u8 {
        return self.current;
    }
    pub fn changes(self: Fake, _: []const u8, ps: []const []const u8) ?git.Changes {
        if (self.git_fails) return null;
        var c: git.Changes = .{};
        for (ps) |p| {
            for (self.dirty) |d| if (std.mem.eql(u8, p, d)) {
                c.untracked += 1;
            };
            for (self.changed) |d| if (std.mem.eql(u8, p, d)) {
                c.changed += 1;
            };
        }
        return c;
    }
    pub fn onlyHere(self: Fake, _: []const u8, _: []const u8) bool {
        return self.only_here;
    }
    pub fn headPushed(self: Fake, _: []const u8) bool {
        return self.pushed;
    }
};

fn check(a: Allocator, probe: Fake, cwd: ?[]const u8, src: []const u8) !?Finding {
    const ctx: Ctx = .{ .alloc = a, .cwd = cwd, .home = "/Users/me", .tmpdir = null, .config = config.Config.parse(a, "") };
    const cmds = try shell.parse(a, src, "/Users/me");
    for (cmds) |c| if (try classify(ctx, probe, c)) |f| return f;
    return null;
}

fn group(a: Allocator, probe: Fake, src: []const u8) !?Group {
    const f = try check(a, probe, "/r", src) orelse return null;
    return f.group;
}

test "guard catalog: harmless everyday commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const harmless = [_][]const u8{
        "ls -la",                 "git status",  "git diff HEAD~1", "zig build test",     "git commit -m 'wip'",
        "git checkout main",      "git stash",   "git stash pop",   "git worktree prune", "git reset HEAD~1",
        "git restore --staged x", "npm install", "cat a > out.txt", "git log | head",     "echo 'rm -rf /'",
        "git branch -m old new",
    };
    for (harmless) |src| {
        if (try group(a, .{}, src)) |g| {
            std.debug.print("unexpected {s} for: {s}\n", .{ @tagName(g), src });
            return error.TestUnexpectedResult;
        }
    }
}

test "guard catalog: deletes are critical only when git can't restore them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "rm src/committed.zig"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{ .dirty = &.{"notes.md"} }, "rm notes.md"));
    const f = (try check(a, .{ .dirty = &.{"notes.md"} }, "/r", "rm -f notes.md")).?;
    try std.testing.expectEqualStrings("1 untracked files", f.lost.?);
    // `deletable` folders go without asking even when ignored.
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .dirty = &.{"node_modules"} }, "rm -rf node_modules"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .dirty = &.{"macos/zig-out"} }, "rm -rf macos/zig-out"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{ .dirty = &.{"build"} }, "rm -rf build"));
    // Unknown targets, failed git, and other delete tools.
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "rm -rf $DIR"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{ .git_fails = true }, "rm x"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "find . -name '*.o' -delete"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "git ls-files -o | xargs rm"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{ .dirty = &.{"a"} }, "unlink a"));
}

test "guard catalog: paths that leave the repo" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "rm ../x"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "rm ~/notes.md"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "rm /tmp/../Users/me/x"));
    try std.testing.expectEqual(@as(?Group, .deleting), (try check(a, .{ .root = null }, "/Users/me", "rm x")).?.group);
    try std.testing.expectEqual(@as(?Group, .deleting), (try check(a, .{}, null, "rm x")).?.group);
    // Writes outside the project (temp folders are fine).
    try std.testing.expectEqual(@as(?Group, .outside), try group(a, .{}, "echo hi > ~/notes.md"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "echo hi > /tmp/x"));
    try std.testing.expectEqual(@as(?Group, .outside), try group(a, .{}, "cp a ../elsewhere/"));
    try std.testing.expectEqual(@as(?Group, .outside), try group(a, .{}, "sed -i '' s/a/b/ ../x.txt"));
}

test "guard catalog: guardrails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, .guardrails), try group(a, .{}, "echo '{}' > ~/.claude/settings.json"));
    try std.testing.expectEqual(@as(?Group, .guardrails), try group(a, .{}, "rm ~/.codex/hooks.json"));
    try std.testing.expectEqual(@as(?Group, .guardrails), try group(a, .{}, "security find-generic-password -s x"));
    try std.testing.expectEqual(@as(?Group, .guardrails), try group(a, .{}, "\"$LOSTTY_BIN\" +claude-hooks remove"));
    try std.testing.expectEqual(@as(?Group, .guardrails), try group(a, .{}, "lostty +claude-hooks remove --agent=codex"));
}

test "guard catalog: git that throws work away" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git reset --hard origin/main"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git rebase -i HEAD~3"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "git rebase --continue"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{ .changed = &.{"x.zig"} }, "git checkout -- x.zig"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "git checkout -- clean.zig"));
    // Untracked files aren't touched by checkout/restore.
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .dirty = &.{"x.zig"} }, "git checkout -- x.zig"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{ .changed = &.{"."} }, "git restore ."));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git switch -f other"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{ .pushed = true }, "git commit --amend --no-edit"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .pushed = false }, "git commit --amend --no-edit"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git filter-branch --tree-filter x"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git reflog expire --expire=now --all"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "git clean -fdx"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "git clean -n"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "git stash drop"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "git tag -d v1"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{ .only_here = true }, "git branch -D solo"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .only_here = false }, "git branch -d merged"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "git worktree remove --force .claude/worktrees/x"));
    try std.testing.expectEqual(@as(?Group, .discarding), try group(a, .{}, "git -C ../other reset --hard"));
}

test "guard catalog: leaving the Mac and merging" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "git push"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "git push origin feature"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "gh pr create --fill"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "gh issue create -t x"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{}, "gh pr view 12"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "gh api -X DELETE repos/o/r"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "npm publish"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "macos/ship-phone.sh"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "scp out.tar host:/tmp/"));
    try std.testing.expectEqual(@as(?Group, .merging), try group(a, .{ .current = "main" }, "git merge feature"));
    try std.testing.expectEqual(@as(?Group, null), try group(a, .{ .current = "feature" }, "git merge main"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "gh pr merge 12"));
}

test "guard catalog: push relaxed to protected for a repo" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ctx: Ctx = .{ .alloc = a, .cwd = "/r", .home = "/Users/me", .tmpdir = null, .config = config.Config.parse(a,
        \\{"repos":{"/r":{"push":"protected"}}}
    ) };
    const p = Fake{ .current = "feature" };
    const run = struct {
        fn f(c: Ctx, probe: Fake, src: []const u8) !?Finding {
            const cmds = try shell.parse(c.alloc, src, "/Users/me");
            return classify(c, probe, cmds[0]);
        }
    }.f;
    try std.testing.expect((try run(ctx, p, "git push")) == null);
    try std.testing.expect((try run(ctx, p, "git push -u origin feature")) == null);
    try std.testing.expect((try run(ctx, p, "git push origin main")) != null);
    try std.testing.expect((try run(ctx, p, "git push --force")) != null);
    try std.testing.expect((try run(ctx, p, "git push --tags")) != null);
    try std.testing.expect((try run(ctx, .{ .current = "main" }, "git push")) != null);
}

test "guard catalog: wrappers, shells and unreadable commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "sudo env FOO=1 nohup git push"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "timeout 30 git push"));
    try std.testing.expectEqual(@as(?Group, .leaving), try group(a, .{}, "bash -c 'git status && git push'"));
    try std.testing.expectEqual(@as(?Group, .unreadable), try group(a, .{}, "eval \"$CMD\""));
    try std.testing.expectEqual(@as(?Group, .unreadable), try group(a, .{}, "$TOOL --go"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "docker volume rm data"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "psql -c 'drop table users'"));
    try std.testing.expectEqual(@as(?Group, .deleting), try group(a, .{}, "kubectl delete pod x"));
}
