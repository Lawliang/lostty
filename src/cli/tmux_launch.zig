const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const session = @import("tmux/session.zig");

pub const Options = struct {
    pub fn deinit(self: Options) void {
        _ = self;
    }

    /// Enables "-h" and "--help" to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

/// The `tmux-launch` command is what each new Lostty pane runs: it starts
/// the pane's shell in its own session on Lostty's private tmux (`tmux -L
/// lostty`) and attaches to it, so the shell outlives the window and can be
/// picked up from the phone. `--attach=<session id>` adopts an existing
/// session instead. If tmux is missing or fails, it prints one line saying
/// so and runs a plain login shell.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();
    const env = session.Env.fromProcess();
    // The pane is not inside tmux, whatever Lostty itself was started from.
    var clean_env = std.process.getEnvMap(alloc) catch return fallback(alloc, env, .tmux_failed);
    clean_env.remove("TMUX");
    clean_env.remove("TMUX_PANE");

    const argv = std.process.argsAlloc(alloc) catch return fallback(alloc, env, .tmux_failed);
    const attach_id = session.attachIdFromArgs(argv);
    const failed: session.Notice = if (attach_id != null) .session_gone else .tmux_failed;
    const tmux = session.findTmux(alloc, env.path, isExecutable) orelse return fallback(alloc, env, .no_tmux);
    const surface = env.surface orelse return fallback(alloc, env, .tmux_failed);
    const resources = env.resources_dir orelse return fallback(alloc, env, .tmux_failed);

    const id: []const u8 = if (attach_id) |want| want else create: {
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = std.posix.getcwd(&cwd_buf) catch return fallback(alloc, env, .tmux_failed);
        const create = session.newSessionArgv(alloc, .{
            .tmux = tmux,
            .env = env,
            .surface = surface,
            .resources_dir = resources,
            .cwd = cwd,
            .pid = std.c.getpid(),
            .size = terminalSize(),
        }) catch return fallback(alloc, env, .tmux_failed);
        const out = runTmuxEnv(alloc, create, &clean_env) orelse return fallback(alloc, env, .tmux_failed);
        break :create std.mem.trim(u8, out, " \r\n");
    };
    if (!session.isSessionId(id)) return fallback(alloc, env, failed);

    // A new session records its shell, for "is this pane busy?" when its
    // window closes; an adopted one keeps what it has.
    const shell_name: ?[]const u8 = if (attach_id == null) std.fs.path.basename(env.shellPath()) else null;
    const tag = session.tagArgv(alloc, tmux, id, surface, env.app_pid, shell_name) catch return fallback(alloc, env, failed);
    if (runTmuxEnv(alloc, tag, &clean_env) == null) return fallback(alloc, env, failed);
    if (attach_id != null) reportPwd(alloc, tmux, id, &clean_env);

    const attach = session.attachArgv(alloc, tmux, id) catch return fallback(alloc, env, failed);
    const err = std.process.execve(alloc, attach, &clean_env);
    std.log.warn("lostty: could not attach to tmux: {}", .{err});
    return fallback(alloc, env, .tmux_failed);
}

pub fn isExecutable(path: []const u8) bool {
    std.posix.access(path, std.posix.X_OK) catch return false;
    return true;
}

/// Runs a tmux command; its stdout when it exits 0, else null.
pub fn runTmux(alloc: Allocator, argv: []const []const u8) ?[]u8 {
    return runTmuxEnv(alloc, argv, null);
}

/// `runTmux` with an explicit environment for the child (null inherits).
fn runTmuxEnv(alloc: Allocator, argv: []const []const u8, env_map: ?*const std.process.EnvMap) ?[]u8 {
    const result = std.process.Child.run(.{ .allocator = alloc, .argv = argv, .env_map = env_map }) catch return null;
    return switch (result.term) {
        .Exited => |code| if (code == 0) result.stdout else null,
        else => null,
    };
}

/// The pane's size, so the shell starts at the right width rather than
/// tmux's 80x24 until the attach resizes it.
fn terminalSize() ?session.Size {
    const TIOCGWINSZ = if (builtin.os.tag == .macos) 1074295912 else std.posix.T.IOCGWINSZ;
    var ws: std.posix.winsize = undefined;
    if (std.c.ioctl(std.posix.STDIN_FILENO, TIOCGWINSZ, @intFromPtr(&ws)) < 0) return null;
    if (ws.col == 0 or ws.row == 0) return null;
    return .{ .cols = ws.col, .rows = ws.row };
}

/// Tells the window an adopted session's directory right away.
fn reportPwd(alloc: Allocator, tmux: []const u8, id: []const u8, env_map: *const std.process.EnvMap) void {
    const out = runTmuxEnv(alloc, &.{ tmux, "-L", session.socket, "display-message", "-p", "-t", id, "#{pane_current_path}" }, env_map) orelse return;
    const path = std.mem.trim(u8, out, "\r\n");
    if (path.len == 0) return;
    var host_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const host = std.posix.gethostname(&host_buf) catch return;
    const seq = session.pwdSequence(alloc, host, path) catch return;
    std.fs.File.stdout().writeAll(seq) catch {};
}

/// Prints why, then becomes the user's login shell, with Ghostty's own zsh
/// integration as a plain Lostty pane would have.
fn fallback(alloc: Allocator, env: session.Env, notice: session.Notice) u8 {
    std.fs.File.stdout().writeAll(session.noticeLine(notice)) catch {};
    const shell = env.shellPath();
    var env_map = std.process.getEnvMap(alloc) catch return 1;
    env_map.remove("TMUX");
    env_map.remove("TMUX_PANE");
    if (env.resources_dir) |res| {
        if (session.isZsh(shell)) {
            if (env.zdotdir) |z| env_map.put("GHOSTTY_ZSH_ZDOTDIR", z) catch {};
            const dir = std.fs.path.join(alloc, &.{ res, "shell-integration", "zsh" }) catch return 1;
            env_map.put("ZDOTDIR", dir) catch {};
        }
    }
    const err = std.process.execve(alloc, &.{ shell, "-l" }, &env_map);
    std.log.err("lostty: could not start {s}: {}", .{ shell, err });
    return 1;
}

test {
    _ = @import("tmux/session.zig");
}
