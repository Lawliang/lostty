//! Pure logic for Lostty's private tmux (`tmux -L lostty`): where tmux is,
//! what to call a pane's session, and the tmux command lines `+tmux-launch`
//! runs. Builders allocate freely; pass an arena. See
//! docs/superpowers/specs/2026-10-09-lostty-mobile-design.md (§2).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const socket = "lostty";
pub const opt_surface = "@lostty_surface";
pub const opt_owner = "@lostty_owner";
pub const opt_shell = "@lostty_shell";

/// Homebrew's usual places come first: Lostty started from the Dock has a
/// bare PATH (/usr/bin:/bin:/usr/sbin:/sbin) without them.
pub const tmux_candidates = [_][]const u8{ "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux" };

/// What the launcher reads from its environment.
pub const Env = struct {
    surface: ?[]const u8 = null, // LOSTTY_SURFACE
    bin: ?[]const u8 = null, // LOSTTY_BIN
    skins_surface: ?[]const u8 = null, // GHOSTTY_SKINS_SURFACE
    app_pid: ?[]const u8 = null, // LOSTTY_APP_PID
    shell: ?[]const u8 = null, // SHELL
    resources_dir: ?[]const u8 = null, // GHOSTTY_RESOURCES_DIR
    shell_features: ?[]const u8 = null, // GHOSTTY_SHELL_FEATURES
    zdotdir: ?[]const u8 = null, // ZDOTDIR
    path: ?[]const u8 = null, // PATH

    pub fn fromProcess() Env {
        const get = std.posix.getenv;
        return .{
            .surface = get("LOSTTY_SURFACE"),
            .bin = get("LOSTTY_BIN"),
            .skins_surface = get("GHOSTTY_SKINS_SURFACE"),
            .app_pid = get("LOSTTY_APP_PID"),
            .shell = get("SHELL"),
            .resources_dir = get("GHOSTTY_RESOURCES_DIR"),
            .shell_features = get("GHOSTTY_SHELL_FEATURES"),
            .zdotdir = get("ZDOTDIR"),
            .path = get("PATH"),
        };
    }

    pub fn shellPath(self: Env) []const u8 {
        return self.shell orelse "/bin/zsh";
    }
};

pub const Size = struct { cols: u16, rows: u16 };

pub const NewSession = struct {
    tmux: []const u8,
    env: Env,
    surface: []const u8,
    resources_dir: []const u8,
    cwd: []const u8,
    /// The launcher's pid, which keeps temporary names unique.
    pid: i32,
    size: ?Size = null,
};

pub const Notice = enum { no_tmux, tmux_failed, session_gone };

/// The first executable tmux: Homebrew's places, then each PATH entry.
/// `isExecutable` is injected so tests don't depend on this machine.
pub fn findTmux(
    alloc: Allocator,
    path_env: ?[]const u8,
    isExecutable: *const fn ([]const u8) bool,
) ?[]const u8 {
    for (tmux_candidates) |c| {
        if (isExecutable(c)) return c;
    }
    var it = std.mem.tokenizeScalar(u8, path_env orelse return null, ':');
    while (it.next()) |dir| {
        const candidate = std.fs.path.join(alloc, &.{ dir, "tmux" }) catch return null;
        if (isExecutable(candidate)) return candidate;
    }
    return null;
}

/// A session's name until its shell renames it to its project:
/// "lostty-", the first 8 characters of the pane's UUID (lowercased), and
/// the launcher's pid. A restored window reuses its pane UUID while the old
/// session may still exist, so the UUID alone is not unique.
pub fn tempName(alloc: Allocator, surface: []const u8, pid: i32) ![]u8 {
    const n = @min(surface.len, 8);
    var prefix: [8]u8 = undefined;
    for (surface[0..n], prefix[0..n]) |c, *o| {
        o.* = if (std.ascii.isAlphanumeric(c)) std.ascii.toLower(c) else 'x';
    }
    return std.fmt.allocPrint(alloc, "lostty-{s}-{d}", .{ prefix[0..n], pid });
}

fn integrationPath(alloc: Allocator, resources_dir: []const u8, name: []const u8) ![]u8 {
    return std.fs.path.join(alloc, &.{ resources_dir, "shell-integration", "lostty-tmux", name });
}

pub fn isZsh(shell: []const u8) bool {
    return std.mem.eql(u8, std.fs.path.basename(shell), "zsh");
}

fn appendEnv(alloc: Allocator, argv: *std.ArrayList([]const u8), name: []const u8, value: []const u8) !void {
    try argv.appendSlice(alloc, &.{ "-e", try std.fmt.allocPrint(alloc, "{s}={s}", .{ name, value }) });
}

/// The tmux command that creates the pane's session, detached, and prints
/// its id ("$3"). The session's shell gets the pane's env vars (the server's
/// own environment belongs to whichever pane started it) and, for zsh,
/// Lostty's ZDOTDIR, which loads the passthrough snippet.
pub fn newSessionArgv(alloc: Allocator, s: NewSession) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(alloc, &.{
        s.tmux,          "-L",                                                     socket,
        "-f",            try integrationPath(alloc, s.resources_dir, "tmux.conf"), "new-session",
        "-d",            "-P",                                                     "-F",
        "#{session_id}", "-s",                                                     try tempName(alloc, s.surface, s.pid),
        "-c",            s.cwd,
    });
    if (s.size) |size| {
        try argv.appendSlice(alloc, &.{
            "-x", try std.fmt.allocPrint(alloc, "{d}", .{size.cols}),
            "-y", try std.fmt.allocPrint(alloc, "{d}", .{size.rows}),
        });
    }
    try appendEnv(alloc, &argv, "LOSTTY_TMUX", "1");
    try appendEnv(alloc, &argv, "LOSTTY_SURFACE", s.surface);
    try appendEnv(alloc, &argv, "GHOSTTY_RESOURCES_DIR", s.resources_dir);
    if (s.env.bin) |v| try appendEnv(alloc, &argv, "LOSTTY_BIN", v);
    if (s.env.skins_surface) |v| try appendEnv(alloc, &argv, "GHOSTTY_SKINS_SURFACE", v);
    if (s.env.app_pid) |v| try appendEnv(alloc, &argv, "LOSTTY_APP_PID", v);
    if (s.env.shell_features) |v| try appendEnv(alloc, &argv, "GHOSTTY_SHELL_FEATURES", v);
    const shell = s.env.shellPath();
    if (isZsh(shell)) {
        try appendEnv(alloc, &argv, "ZDOTDIR", try integrationPath(alloc, s.resources_dir, "zsh"));
        if (s.env.zdotdir) |v| try appendEnv(alloc, &argv, "LOSTTY_ZDOTDIR", v);
    }
    try argv.appendSlice(alloc, &.{ shell, "-l" });
    return argv.toOwnedSlice(alloc);
}

/// The tmux command that tags session `id` with its pane, its Lostty
/// (`owner`, a pid) and its shell's name. Null fields are left as they are.
pub fn tagArgv(
    alloc: Allocator,
    tmux: []const u8,
    id: []const u8,
    surface: []const u8,
    owner: ?[]const u8,
    shell_name: ?[]const u8,
) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(alloc, &.{ tmux, "-L", socket, "set-option", "-t", id, opt_surface, surface });
    if (owner) |v| try argv.appendSlice(alloc, &.{ ";", "set-option", "-t", id, opt_owner, v });
    if (shell_name) |v| try argv.appendSlice(alloc, &.{ ";", "set-option", "-t", id, opt_shell, v });
    return argv.toOwnedSlice(alloc);
}

pub fn attachArgv(alloc: Allocator, tmux: []const u8, id: []const u8) ![]const []const u8 {
    return alloc.dupe([]const u8, &.{ tmux, "-L", socket, "attach-session", "-t", id });
}

/// The session id after `--attach=`, if any.
pub fn attachIdFromArgs(argv: []const []const u8) ?[]const u8 {
    const prefix = "--attach=";
    for (argv) |arg| {
        if (std.mem.startsWith(u8, arg, prefix)) return arg[prefix.len..];
    }
    return null;
}

/// Lists every session as "id<TAB>surface<TAB>owner", for `orphanFor`.
pub fn listArgv(alloc: Allocator, tmux: []const u8) ![]const []const u8 {
    const format = "#{session_id}\t#{" ++ opt_surface ++ "}\t#{" ++ opt_owner ++ "}";
    return alloc.dupe([]const u8, &.{ tmux, "-L", socket, "list-sessions", "-F", format });
}

/// The session a crashed Lostty left showing pane `surface`, from
/// `listArgv` output: macOS restores the window with the same pane id, so
/// it picks its shell back up instead of starting a new one beside it.
pub fn orphanFor(list: []const u8, surface: []const u8, isAlive: *const fn (i32) bool) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, list, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, '\t');
        const id = fields.next() orelse continue;
        const s = fields.next() orelse continue;
        const owner = std.fmt.parseInt(i32, fields.next() orelse continue, 10) catch continue;
        if (isSessionId(id) and std.mem.eql(u8, s, surface) and !isAlive(owner)) return id;
    }
    return null;
}

/// True when the pane's command is Lostty's tmux launcher (see
/// SessionLaunch.swift), i.e. the pane's shell rather than a script.
pub fn isLauncherCommand(cmd: []const u8) bool {
    return std.mem.indexOf(u8, cmd, "' +tmux-launch") != null;
}

/// tmux session ids look like "$12".
pub fn isSessionId(s: []const u8) bool {
    if (s.len < 2 or s[0] != '$') return false;
    for (s[1..]) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

/// One dim line printed above the plain shell the launcher falls back to.
pub fn noticeLine(n: Notice) []const u8 {
    return switch (n) {
        .no_tmux => "\x1b[2mLostty: tmux not found (brew install tmux). This window runs a plain shell and can't be opened from the phone.\x1b[0m\r\n",
        .tmux_failed => "\x1b[2mLostty: tmux couldn't start a session. This window runs a plain shell and can't be opened from the phone.\x1b[0m\r\n",
        .session_gone => "\x1b[2mLostty: that session has ended. This window runs a plain shell.\x1b[0m\r\n",
    };
}

/// OSC 7 for `path`, written straight to the window (not through tmux) when
/// a window adopts an existing session, so auto-skin needn't wait for the
/// next prompt. kitty-shell-cwd takes the raw path, no percent-escaping.
pub fn pwdSequence(alloc: Allocator, host: []const u8, path: []const u8) ![]u8 {
    return std.fmt.allocPrint(alloc, "\x1b]7;kitty-shell-cwd://{s}{s}\x07", .{ host, path });
}

// ---- tests ----

const Fake = struct {
    fn onlyUsrLocal(p: []const u8) bool {
        return std.mem.eql(u8, p, "/usr/local/bin/tmux");
    }
    fn homebrewAndUsrBin(p: []const u8) bool {
        return std.mem.eql(u8, p, "/opt/homebrew/bin/tmux") or std.mem.eql(u8, p, "/usr/bin/tmux");
    }
    fn onlyCustom(p: []const u8) bool {
        return std.mem.eql(u8, p, "/custom/bin/tmux");
    }
    fn none(_: []const u8) bool {
        return false;
    }
};

/// True when `a` is immediately followed by `b` somewhere in `argv`.
fn hasPair(argv: []const []const u8, a: []const u8, b: []const u8) bool {
    if (argv.len < 2) return false;
    for (argv[0 .. argv.len - 1], argv[1..]) |x, y| {
        if (std.mem.eql(u8, x, a) and std.mem.eql(u8, y, b)) return true;
    }
    return false;
}

fn hasArg(argv: []const []const u8, a: []const u8) bool {
    for (argv) |x| if (std.mem.eql(u8, x, a)) return true;
    return false;
}

const test_surface = "ABCDEF01-0000-4000-8000-000000000001";

test "lostty tmux session: findTmux prefers Homebrew over a bare PATH" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = std.testing;
    try t.expectEqualStrings("/opt/homebrew/bin/tmux", findTmux(a, "/usr/bin:/bin", Fake.homebrewAndUsrBin).?);
    try t.expectEqualStrings("/usr/local/bin/tmux", findTmux(a, "/usr/bin:/bin", Fake.onlyUsrLocal).?);
    try t.expectEqualStrings("/custom/bin/tmux", findTmux(a, "/usr/bin:/custom/bin", Fake.onlyCustom).?);
    try t.expect(findTmux(a, "/usr/bin:/bin", Fake.none) == null);
    try t.expect(findTmux(a, null, Fake.none) == null);
}

test "lostty tmux session: tempName is unique per launcher" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = std.testing;
    try t.expectEqualStrings("lostty-abcdef01-4242", try tempName(a, test_surface, 4242));
    // A restored window reuses its pane UUID; a different launcher pid keeps the name free.
    try t.expect(!std.mem.eql(u8, try tempName(a, test_surface, 1), try tempName(a, test_surface, 2)));
    try t.expectEqualStrings("lostty-axb-7", try tempName(a, "a.b", 7));
}

test "lostty tmux session: newSessionArgv for zsh" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = std.testing;
    const argv = try newSessionArgv(a, .{
        .tmux = "/opt/homebrew/bin/tmux",
        .env = .{
            .bin = "/Apps/Lostty.app/Contents/MacOS/ghostty",
            .skins_surface = test_surface,
            .app_pid = "4242",
            .shell = "/bin/zsh",
            .shell_features = "cursor,title",
            .zdotdir = "/Users/me/.zsh",
        },
        .surface = test_surface,
        .resources_dir = "/R",
        .cwd = "/Users/me/code/idfk",
        .pid = 77,
        .size = .{ .cols = 120, .rows = 40 },
    });
    try t.expectEqualStrings("/opt/homebrew/bin/tmux", argv[0]);
    try t.expect(hasPair(argv, "-L", "lostty"));
    try t.expect(hasPair(argv, "-f", "/R/shell-integration/lostty-tmux/tmux.conf"));
    try t.expect(hasArg(argv, "new-session"));
    try t.expect(hasArg(argv, "-d"));
    try t.expect(hasPair(argv, "-F", "#{session_id}"));
    try t.expect(hasPair(argv, "-s", "lostty-abcdef01-77"));
    try t.expect(hasPair(argv, "-c", "/Users/me/code/idfk"));
    try t.expect(hasPair(argv, "-x", "120"));
    try t.expect(hasPair(argv, "-y", "40"));
    try t.expect(hasPair(argv, "-e", "LOSTTY_TMUX=1"));
    try t.expect(hasPair(argv, "-e", "LOSTTY_SURFACE=" ++ test_surface));
    try t.expect(hasPair(argv, "-e", "GHOSTTY_SKINS_SURFACE=" ++ test_surface));
    try t.expect(hasPair(argv, "-e", "LOSTTY_BIN=/Apps/Lostty.app/Contents/MacOS/ghostty"));
    try t.expect(hasPair(argv, "-e", "LOSTTY_APP_PID=4242"));
    try t.expect(hasPair(argv, "-e", "GHOSTTY_RESOURCES_DIR=/R"));
    try t.expect(hasPair(argv, "-e", "GHOSTTY_SHELL_FEATURES=cursor,title"));
    try t.expect(hasPair(argv, "-e", "ZDOTDIR=/R/shell-integration/lostty-tmux/zsh"));
    try t.expect(hasPair(argv, "-e", "LOSTTY_ZDOTDIR=/Users/me/.zsh"));
    try t.expectEqualStrings("/bin/zsh", argv[argv.len - 2]);
    try t.expectEqualStrings("-l", argv[argv.len - 1]);
}

test "lostty tmux session: newSessionArgv keeps a cwd with spaces as one argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const argv = try newSessionArgv(arena.allocator(), .{
        .tmux = "tmux",
        .env = .{ .shell = "/bin/zsh" },
        .surface = test_surface,
        .resources_dir = "/My Apps/R",
        .cwd = "/Users/me/My Projects/x",
        .pid = 1,
    });
    try std.testing.expect(hasPair(argv, "-c", "/Users/me/My Projects/x"));
    try std.testing.expect(hasPair(argv, "-f", "/My Apps/R/shell-integration/lostty-tmux/tmux.conf"));
    // No size known: tmux picks one and the attach resizes.
    try std.testing.expect(!hasArg(argv, "-x"));
}

test "lostty tmux session: newSessionArgv leaves other shells and ZDOTDIR alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = std.testing;
    const bash = try newSessionArgv(a, .{ .tmux = "tmux", .env = .{ .shell = "/bin/bash" }, .surface = test_surface, .resources_dir = "/R", .cwd = "/", .pid = 1 });
    for (bash) |arg| try t.expect(!std.mem.startsWith(u8, arg, "ZDOTDIR="));
    try t.expectEqualStrings("/bin/bash", bash[bash.len - 2]);
    // zsh without a ZDOTDIR of its own: nothing to restore later.
    const zsh = try newSessionArgv(a, .{ .tmux = "tmux", .env = .{}, .surface = test_surface, .resources_dir = "/R", .cwd = "/", .pid = 1 });
    for (zsh) |arg| try t.expect(!std.mem.startsWith(u8, arg, "LOSTTY_ZDOTDIR="));
    try t.expect(hasPair(zsh, "-e", "ZDOTDIR=/R/shell-integration/lostty-tmux/zsh"));
    try t.expectEqualStrings("/bin/zsh", zsh[zsh.len - 2]);
}

test "lostty tmux session: tagArgv" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = std.testing;
    const full = try tagArgv(a, "tmux", "$3", test_surface, "4242", "zsh");
    const want_full = [_][]const u8{
        "tmux", "-L",         "lostty",        "set-option", "-t",            "$3",   "@lostty_surface", test_surface,
        ";",    "set-option", "-t",            "$3",         "@lostty_owner", "4242", ";",               "set-option",
        "-t",   "$3",         "@lostty_shell", "zsh",
    };
    try t.expectEqual(want_full.len, full.len);
    for (want_full, full) |w, g| try t.expectEqualStrings(w, g);
    // Adopting a session: no owner known, shell kept as it was.
    const bare = try tagArgv(a, "tmux", "$3", test_surface, null, null);
    try t.expectEqual(@as(usize, 8), bare.len);
}

test "lostty tmux session: attach arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const t = std.testing;
    const argv = try attachArgv(arena.allocator(), "tmux", "$3");
    const want = [_][]const u8{ "tmux", "-L", "lostty", "attach-session", "-t", "$3" };
    try t.expectEqual(want.len, argv.len);
    for (want, argv) |w, g| try t.expectEqualStrings(w, g);
    try t.expectEqualStrings("$3", attachIdFromArgs(&.{ "/x/ghostty", "+tmux-launch", "--attach=$3" }).?);
    try t.expect(attachIdFromArgs(&.{ "/x/ghostty", "+tmux-launch" }) == null);
    try t.expect(isSessionId("$3"));
    try t.expect(isSessionId("$120"));
    try t.expect(!isSessionId("$"));
    try t.expect(!isSessionId("3"));
    try t.expect(!isSessionId("$3;kill-server"));
    try t.expect(isZsh("/bin/zsh"));
    try t.expect(isZsh("/opt/homebrew/bin/zsh"));
    try t.expect(!isZsh("/bin/bash"));
}

test "lostty tmux session: notices and OSC 7" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const t = std.testing;
    try t.expectEqualStrings(
        "\x1b[2mLostty: tmux not found (brew install tmux). This window runs a plain shell and can't be opened from the phone.\x1b[0m\r\n",
        noticeLine(.no_tmux),
    );
    try t.expect(std.mem.indexOf(u8, noticeLine(.tmux_failed), "tmux couldn't start a session") != null);
    try t.expect(std.mem.indexOf(u8, noticeLine(.session_gone), "that session has ended") != null);
    try t.expectEqualStrings(
        "\x1b]7;kitty-shell-cwd://mac/Users/me/My Projects/x\x07",
        try pwdSequence(arena.allocator(), "mac", "/Users/me/My Projects/x"),
    );
}

test "lostty tmux session: isLauncherCommand" {
    const t = std.testing;
    try t.expect(isLauncherCommand("'/Applications/Lostty.app/Contents/MacOS/ghostty' +tmux-launch"));
    try t.expect(isLauncherCommand("'/x/ghostty' +tmux-launch '--attach=$3'"));
    try t.expect(!isLauncherCommand("vim foo"));
    try t.expect(!isLauncherCommand(""));
    try t.expect(!isLauncherCommand("echo +tmux-launch"));
}

test "lostty tmux session: orphanFor finds the crashed Lostty's session for this pane" {
    const t = std.testing;
    const isAlive = struct {
        fn f(pid: i32) bool {
            return pid == 100;
        }
    }.f;
    const list =
        "$1\t" ++ test_surface ++ "\t100\n" ++ // this pane, a live Lostty (a Debug build beside it)
        "$2\tOTHER\t300\n" ++ // another pane's orphan
        "$3\t" ++ test_surface ++ "\t300\n" ++ // this pane, crashed Lostty
        "$4\t\t\n"; // phone session, no owner
    try t.expectEqualStrings("$3", orphanFor(list, test_surface, &isAlive).?);
    try t.expect(orphanFor("$1\t" ++ test_surface ++ "\t100\n", test_surface, &isAlive) == null);
    try t.expect(orphanFor("", test_surface, &isAlive) == null);
    try t.expect(orphanFor("garbage\n$5\t" ++ test_surface ++ "\tnope\n", test_surface, &isAlive) == null);
}
