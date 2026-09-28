const std = @import("std");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const protocol = @import("skins/protocol.zig");

const vaxis = @import("vaxis");

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

const usage =
    \\usage: skins                     interactive picker (live preview)
    \\       skins set <name>          use a skin from skins.toml
    \\       skins color <#rrggbb>     override the background color
    \\       skins texture <name|none> override the texture
    \\       skins opacity <0-1>       override the texture opacity
    \\       skins reset               back to the project's skin
    \\       skins list                list skins and textures
    \\       skins current             show this pane's skin
    \\
;

/// The `skins` command previews and sets the skin of the current Ghostty
/// Skins pane. Run `skins` with no arguments for an interactive picker with
/// live preview, or one of: `skins set <name>`, `skins color <#rrggbb>`,
/// `skins texture <name|none>`, `skins opacity <0-1>`, `skins reset`,
/// `skins list`, `skins current`.
pub fn run(gpa: Allocator) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    // Arguments after "+skins" (Ghostty's action detection already consumed it).
    const argv = try std.process.argsAlloc(alloc);
    var start: usize = argv.len;
    for (argv, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "+skins")) {
            start = i + 1;
            break;
        }
    }
    var arg_list: std.ArrayList([]const u8) = .empty;
    for (argv[start..]) |arg| try arg_list.append(alloc, arg);
    const args = arg_list.items;

    const command = protocol.parseArgs(args) catch |err| {
        try stderr.print("skins: {s}\n{s}", .{ @errorName(err), usage });
        return 2;
    };
    if (command == .help) {
        try stdout.writeAll(usage);
        return 0;
    }

    const surface_id = std.posix.getenv(protocol.surface_env) orelse {
        try stderr.writeAll("skins: run this inside a Ghostty Skins terminal\n");
        return 1;
    };
    const tmux = std.posix.getenv("TMUX") != null;

    switch (command) {
        .help => unreachable,
        .send => |req| {
            try sendToTty(alloc, req, tmux);
            return 0;
        },
        .list => {
            const catalog = try loadCatalog(alloc, stderr) orelse return 1;
            for (catalog.skins) |skin| try stdout.print("{s}\t{s}\t{s}\n", .{ skin.name, skin.background, skin.texture });
            try stdout.writeAll("textures:");
            for (catalog.textures) |t| try stdout.print(" {s}", .{t});
            try stdout.writeAll(" none\n");
            return 0;
        },
        .current => {
            const catalog = try loadCatalog(alloc, stderr) orelse return 1;
            if (catalog.panes.map.get(surface_id)) |pane| {
                try stdout.print("{s} ({s}) {s}\n", .{ pane.skin, pane.source, pane.background });
            } else {
                try stdout.writeAll("default\n");
            }
            return 0;
        },
        .picker => {
            const catalog = try loadCatalog(alloc, stderr) orelse return 1;
            if (!std.posix.isatty(std.fs.File.stdout().handle)) {
                for (catalog.skins) |skin| try stdout.print("{s}\n", .{skin.name});
                return 0;
            }
            try pick(alloc, catalog, tmux);
            return 0;
        },
    }
}

fn sendToTty(alloc: Allocator, req: protocol.Request, tmux: bool) !void {
    const seq = try protocol.encodeSequence(alloc, req, tmux);
    const tty = try std.fs.openFileAbsolute("/dev/tty", .{ .mode = .write_only });
    defer tty.close();
    try tty.writeAll(seq);
}

fn loadCatalog(alloc: Allocator, stderr: *std.Io.Writer) !?protocol.Catalog {
    const home = std.posix.getenv("HOME") orelse return null;
    const path = try std.fs.path.join(alloc, &.{ home, ".config/ghostty-skins/state/catalog.json" });
    const bytes = std.fs.cwd().readFileAlloc(alloc, path, 1 << 20) catch {
        try stderr.print("skins: cannot read {s} (is Ghostty Skins running?)\n", .{path});
        return null;
    };
    const parsed = protocol.parseCatalog(alloc, bytes) catch {
        try stderr.print("skins: {s} is not valid\n", .{path});
        return null;
    };
    return parsed.value;
}

// MARK: Picker

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const Entry = struct {
    label: []const u8,
    swatch: ?[3]u8,
    preview: protocol.Request,
    commit: protocol.Request,
};

fn pick(alloc: Allocator, catalog: protocol.Catalog, tmux: bool) !void {
    var entries: std.ArrayList(Entry) = .empty;
    for (catalog.skins) |skin| {
        try entries.append(alloc, .{
            .label = skin.name,
            .swatch = parseHex(skin.background),
            .preview = .{ .op = .preview, .skin = skin.name },
            .commit = .{ .op = .set, .skin = skin.name },
        });
    }
    for (catalog.textures) |t| {
        try entries.append(alloc, .{
            .label = try std.fmt.allocPrint(alloc, "texture: {s}", .{t}),
            .swatch = null,
            .preview = .{ .op = .preview, .texture = t },
            .commit = .{ .op = .set, .texture = t },
        });
    }
    try entries.append(alloc, .{
        .label = "reset to project",
        .swatch = null,
        .preview = .{ .op = .cancel },
        .commit = .{ .op = .reset },
    });

    var buf: [4096]u8 = undefined;
    var picker = try Picker.init(alloc, entries.items, tmux, &buf);
    defer picker.deinit();
    try picker.run();
}

fn parseHex(s: []const u8) ?[3]u8 {
    if (!protocol.isHexColor(s)) return null;
    const v = std.fmt.parseInt(u24, s[1..], 16) catch return null;
    return .{ @intCast(v >> 16), @intCast((v >> 8) & 0xff), @intCast(v & 0xff) };
}

const Picker = struct {
    alloc: Allocator,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    entries: []const Entry,
    current: usize,
    committed: bool,
    quit: bool,
    tmux: bool,

    fn init(alloc: Allocator, entries: []const Entry, tmux: bool, buf: []u8) !Picker {
        return .{
            .alloc = alloc,
            .tty = try .init(buf),
            .vx = try vaxis.init(alloc, .{}),
            .entries = entries,
            .current = 0,
            .committed = false,
            .quit = false,
            .tmux = tmux,
        };
    }

    fn deinit(self: *Picker) void {
        self.vx.deinit(self.alloc, self.tty.writer());
        self.tty.deinit();
    }

    fn run(self: *Picker) !void {
        var loop: vaxis.Loop(Event) = .{ .tty = &self.tty, .vaxis = &self.vx };
        try loop.init();
        try loop.start();

        const writer = self.tty.writer();
        try self.vx.enterAltScreen(writer);
        try self.vx.queryTerminal(writer, 1 * std.time.ns_per_s);
        try self.send(self.entries[0].preview);

        while (!self.quit) {
            loop.pollEvent();
            while (loop.tryEvent()) |event| try self.update(event);
            self.draw();
            try self.vx.render(writer);
            try writer.flush();
        }
        if (!self.committed) try self.send(.{ .op = .cancel });
    }

    fn update(self: *Picker, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }) or key.matchesAny(&.{ 'q', vaxis.Key.escape }, .{})) {
                    self.quit = true;
                    return;
                }
                if (key.matchesAny(&.{ vaxis.Key.enter, vaxis.Key.kp_enter }, .{})) {
                    try self.send(self.entries[self.current].commit);
                    self.committed = true;
                    self.quit = true;
                    return;
                }
                if (key.matchesAny(&.{ 'j', vaxis.Key.down, vaxis.Key.kp_down }, .{})) try self.move(1);
                if (key.matchesAny(&.{ 'k', vaxis.Key.up, vaxis.Key.kp_up }, .{})) try self.move(-1);
            },
            .winsize => |ws| try self.vx.resize(self.alloc, self.tty.writer(), ws),
        }
    }

    fn move(self: *Picker, delta: isize) !void {
        const last: isize = @intCast(self.entries.len - 1);
        const next = std.math.clamp(@as(isize, @intCast(self.current)) + delta, 0, last);
        if (next == @as(isize, @intCast(self.current))) return;
        self.current = @intCast(next);
        try self.send(self.entries[self.current].preview);
    }

    fn send(self: *Picker, req: protocol.Request) !void {
        const seq = try protocol.encodeSequence(self.alloc, req, self.tmux);
        defer self.alloc.free(seq);
        const writer = self.tty.writer();
        try writer.writeAll(seq);
        try writer.flush();
    }

    fn draw(self: *Picker) void {
        const win = self.vx.window();
        win.clear();
        _ = win.printSegment(.{
            .text = "skins — ↑/↓ preview · enter apply · esc cancel",
            .style = .{ .bold = true },
        }, .{ .row_offset = 0 });
        for (self.entries, 0..) |entry, i| {
            const row: u16 = @intCast(i + 2);
            if (row >= win.height) break;
            const selected = i == self.current;
            if (selected) _ = win.printSegment(.{ .text = "❯", .style = .{ .bold = true } }, .{ .row_offset = row });
            if (entry.swatch) |rgb| {
                _ = win.printSegment(.{ .text = "██", .style = .{ .fg = .{ .rgb = rgb } } }, .{ .row_offset = row, .col_offset = 2 });
            }
            _ = win.printSegment(.{
                .text = entry.label,
                .style = .{ .bold = selected, .reverse = selected },
            }, .{ .row_offset = row, .col_offset = 5 });
        }
    }
};

test {
    _ = @import("skins/protocol.zig");
}
