//! Pure logic for the `skins` CLI: argument parsing, the GHOSTTY_SKIN wire
//! format, and reading catalog.json. See docs/superpowers/specs (§6).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const user_var_name = "GHOSTTY_SKIN";
pub const surface_env = "GHOSTTY_SKINS_SURFACE";

pub const Op = enum { preview, set, cancel, reset };

pub const Request = struct {
    op: Op,
    skin: ?[]const u8 = null,
    background: ?[]const u8 = null,
    texture: ?[]const u8 = null,
    opacity: ?f64 = null,
};

pub const Command = union(enum) {
    picker,
    list,
    current,
    help,
    send: Request,
};

pub const ParseError = error{ UnknownCommand, MissingArgument, InvalidArgument, TooManyArguments };

/// Names are 1–64 chars of [A-Za-z0-9_-] (mirrors the app's validation).
pub fn isName(s: []const u8) bool {
    if (s.len == 0 or s.len > 64) return false;
    for (s) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '-')) return false;
    }
    return true;
}

pub fn isHexColor(s: []const u8) bool {
    if (s.len != 7 or s[0] != '#') return false;
    for (s[1..]) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

pub fn parseArgs(args: []const []const u8) ParseError!Command {
    if (args.len == 0) return .picker;
    const cmd = args[0];
    const rest = args[1..];
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) return .help;
    if (std.mem.eql(u8, cmd, "list")) return noArgs(rest, .list);
    if (std.mem.eql(u8, cmd, "current")) return noArgs(rest, .current);
    if (std.mem.eql(u8, cmd, "reset")) return noArgs(rest, .{ .send = .{ .op = .reset } });
    if (std.mem.eql(u8, cmd, "set")) {
        const v = try one(rest);
        if (!isName(v)) return error.InvalidArgument;
        return .{ .send = .{ .op = .set, .skin = v } };
    }
    if (std.mem.eql(u8, cmd, "color")) {
        const v = try one(rest);
        if (!isHexColor(v)) return error.InvalidArgument;
        return .{ .send = .{ .op = .set, .background = v } };
    }
    if (std.mem.eql(u8, cmd, "texture")) {
        const v = try one(rest);
        if (!isName(v)) return error.InvalidArgument;
        return .{ .send = .{ .op = .set, .texture = v } };
    }
    if (std.mem.eql(u8, cmd, "opacity")) {
        const v = try one(rest);
        const o = std.fmt.parseFloat(f64, v) catch return error.InvalidArgument;
        if (!(o >= 0 and o <= 1)) return error.InvalidArgument;
        return .{ .send = .{ .op = .set, .opacity = o } };
    }
    return error.UnknownCommand;
}

fn one(rest: []const []const u8) ParseError![]const u8 {
    if (rest.len == 0) return error.MissingArgument;
    if (rest.len > 1) return error.TooManyArguments;
    return rest[0];
}

fn noArgs(rest: []const []const u8, cmd: Command) ParseError!Command {
    if (rest.len > 0) return error.TooManyArguments;
    return cmd;
}

/// JSON body for the app. Fields are validated, so nothing needs escaping.
pub fn encodeJson(alloc: Allocator, req: Request) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;
    try w.print("{{\"v\":1,\"op\":\"{s}\"", .{@tagName(req.op)});
    if (req.skin) |s| {
        if (!isName(s)) return error.InvalidRequest;
        try w.print(",\"skin\":\"{s}\"", .{s});
    }
    if (req.background) |b| {
        if (!isHexColor(b)) return error.InvalidRequest;
        try w.print(",\"background\":\"{s}\"", .{b});
    }
    if (req.texture) |t| {
        if (!isName(t)) return error.InvalidRequest;
        try w.print(",\"texture\":\"{s}\"", .{t});
    }
    if (req.opacity) |o| {
        if (!(o >= 0 and o <= 1)) return error.InvalidRequest;
        try w.print(",\"opacity\":{d}", .{o});
    }
    try w.writeByte('}');
    return out.toOwnedSlice();
}

/// OSC 1337 SetUserVar carrying `req`. With `tmux`, wrapped in tmux's DCS
/// passthrough (requires `set -g allow-passthrough on`).
pub fn encodeSequence(alloc: Allocator, req: Request, tmux: bool) ![]u8 {
    const json = try encodeJson(alloc, req);
    defer alloc.free(json);
    const encoder = std.base64.standard.Encoder;
    const b64 = try alloc.alloc(u8, encoder.calcSize(json.len));
    defer alloc.free(b64);
    _ = encoder.encode(b64, json);
    if (tmux) {
        return std.fmt.allocPrint(alloc, "\x1bPtmux;\x1b\x1b]1337;SetUserVar={s}={s}\x07\x1b\\", .{ user_var_name, b64 });
    }
    return std.fmt.allocPrint(alloc, "\x1b]1337;SetUserVar={s}={s}\x07", .{ user_var_name, b64 });
}

pub const Catalog = struct {
    version: u32,
    skins: []const SkinEntry,
    textures: []const []const u8,
    panes: std.json.ArrayHashMap(PaneEntry),

    pub const SkinEntry = struct {
        name: []const u8,
        background: []const u8,
        texture: []const u8,
        rarity: []const u8 = "project",
    };

    pub const PaneEntry = struct {
        skin: []const u8,
        source: []const u8,
        background: []const u8,
    };
};

pub fn parseCatalog(alloc: Allocator, bytes: []const u8) !std.json.Parsed(Catalog) {
    return std.json.parseFromSlice(Catalog, alloc, bytes, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

/// Message buffer for `validateAgainstCatalog`. The CLI is single-threaded
/// and prints the message immediately, so a threadlocal scratch buffer lets
/// the validator stay a plain, allocator-free function.
threadlocal var validate_error_buf: [160]u8 = undefined;

/// Checks a `set`/`preview` request's `skin`/`texture` names against a
/// loaded catalog. Returns an error message (already prefixed `skins: `,
/// ready to print to stderr) or null if the request is fine. `background`
/// and `opacity` are validated by `parseArgs` already and are not rechecked
/// here.
pub fn validateAgainstCatalog(catalog: Catalog, req: Request) ?[]const u8 {
    if (req.skin) |name| {
        var found = false;
        for (catalog.skins) |skin| {
            if (std.mem.eql(u8, skin.name, name)) {
                found = true;
                break;
            }
        }
        if (!found) return formatValidateError("unknown skin", name);
    }
    if (req.texture) |name| {
        if (!std.mem.eql(u8, name, "none") and !catalogHasTexture(catalog, name)) {
            return formatValidateError("unknown texture", name);
        }
    }
    return null;
}

/// True if `name` is one of the catalog's built-in textures, or the name of
/// a catalog skin whose own texture is a logo.
fn catalogHasTexture(catalog: Catalog, name: []const u8) bool {
    for (catalog.textures) |t| {
        if (std.mem.eql(u8, t, name)) return true;
    }
    for (catalog.skins) |skin| {
        if (std.mem.eql(u8, skin.texture, "logo") and std.mem.eql(u8, skin.name, name)) return true;
    }
    return false;
}

fn formatValidateError(kind: []const u8, name: []const u8) []const u8 {
    return std.fmt.bufPrint(&validate_error_buf, "skins: {s} '{s}' (try: skins list)", .{ kind, name }) catch
        "skins: invalid value (try: skins list)";
}

test "skins: encodeJson" {
    const alloc = std.testing.allocator;
    const a = try encodeJson(alloc, .{ .op = .set, .skin = "arca" });
    defer alloc.free(a);
    try std.testing.expectEqualStrings("{\"v\":1,\"op\":\"set\",\"skin\":\"arca\"}", a);

    const b = try encodeJson(alloc, .{ .op = .preview, .background = "#3a0f14", .texture = "grid", .opacity = 0.25 });
    defer alloc.free(b);
    try std.testing.expectEqualStrings(
        "{\"v\":1,\"op\":\"preview\",\"background\":\"#3a0f14\",\"texture\":\"grid\",\"opacity\":0.25}",
        b,
    );

    try std.testing.expectError(error.InvalidRequest, encodeJson(alloc, .{ .op = .set, .skin = "../x" }));
    try std.testing.expectError(error.InvalidRequest, encodeJson(alloc, .{ .op = .set, .background = "red" }));
    try std.testing.expectError(error.InvalidRequest, encodeJson(alloc, .{ .op = .set, .opacity = 2 }));
}

test "skins: encodeSequence round-trips through base64" {
    const alloc = std.testing.allocator;
    const seq = try encodeSequence(alloc, .{ .op = .reset }, false);
    defer alloc.free(seq);
    const prefix = "\x1b]1337;SetUserVar=GHOSTTY_SKIN=";
    try std.testing.expect(std.mem.startsWith(u8, seq, prefix));
    try std.testing.expect(std.mem.endsWith(u8, seq, "\x07"));
    const b64 = seq[prefix.len .. seq.len - 1];
    var out: [64]u8 = undefined;
    const n = try std.base64.standard.Decoder.calcSizeForSlice(b64);
    try std.base64.standard.Decoder.decode(out[0..n], b64);
    try std.testing.expectEqualStrings("{\"v\":1,\"op\":\"reset\"}", out[0..n]);
}

test "skins: encodeSequence wraps for tmux" {
    const alloc = std.testing.allocator;
    const seq = try encodeSequence(alloc, .{ .op = .cancel }, true);
    defer alloc.free(seq);
    try std.testing.expect(std.mem.startsWith(u8, seq, "\x1bPtmux;\x1b\x1b]1337;SetUserVar=GHOSTTY_SKIN="));
    try std.testing.expect(std.mem.endsWith(u8, seq, "\x07\x1b\\"));
}

test "skins: parseArgs" {
    const t = std.testing;
    try t.expectEqual(Command.picker, try parseArgs(&.{}));
    try t.expectEqual(Command.list, try parseArgs(&.{"list"}));
    try t.expectEqual(Command.current, try parseArgs(&.{"current"}));
    try t.expectEqual(Command.help, try parseArgs(&.{"help"}));

    const set = try parseArgs(&.{ "set", "arca" });
    try t.expectEqual(Op.set, set.send.op);
    try t.expectEqualStrings("arca", set.send.skin.?);

    const color = try parseArgs(&.{ "color", "#3a0f14" });
    try t.expectEqualStrings("#3a0f14", color.send.background.?);

    const texture = try parseArgs(&.{ "texture", "none" });
    try t.expectEqualStrings("none", texture.send.texture.?);

    const opacity = try parseArgs(&.{ "opacity", "0.3" });
    try t.expectEqual(@as(f64, 0.3), opacity.send.opacity.?);

    try t.expectEqual(Op.reset, (try parseArgs(&.{"reset"})).send.op);

    try t.expectError(error.UnknownCommand, parseArgs(&.{"paint"}));
    try t.expectError(error.MissingArgument, parseArgs(&.{"set"}));
    try t.expectError(error.TooManyArguments, parseArgs(&.{ "set", "a", "b" }));
    try t.expectError(error.InvalidArgument, parseArgs(&.{ "color", "red" }));
    try t.expectError(error.InvalidArgument, parseArgs(&.{ "opacity", "1.5" }));
    try t.expectError(error.InvalidArgument, parseArgs(&.{ "set", "a/b" }));
}

test "skins: parseCatalog" {
    const alloc = std.testing.allocator;
    const json =
        \\{"version":1,"skins":[{"name":"arca","background":"#12222b","texture":"logo"}],
        \\ "textures":["dots","grid"],
        \\ "panes":{"ABC":{"skin":"arca","source":"config","background":"#12222b"}},
        \\ "future":true}
    ;
    const parsed = try parseCatalog(alloc, json);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.value.skins.len);
    try std.testing.expectEqualStrings("arca", parsed.value.skins[0].name);
    try std.testing.expectEqualStrings("grid", parsed.value.textures[1]);
    try std.testing.expectEqualStrings("config", parsed.value.panes.map.get("ABC").?.source);
}

fn testCatalog() Catalog {
    return .{
        .version = 1,
        .skins = &.{
            .{ .name = "arca", .background = "#12222b", .texture = "logo" },
            .{ .name = "prod", .background = "#3a0f14", .texture = "diagonal" },
        },
        .textures = &.{ "dots", "grid", "diagonal" },
        .panes = .{},
    };
}

test "skins: validateAgainstCatalog accepts a known skin and texture" {
    const catalog = testCatalog();
    try std.testing.expectEqual(@as(?[]const u8, null), validateAgainstCatalog(catalog, .{ .op = .set, .skin = "arca" }));
    try std.testing.expectEqual(@as(?[]const u8, null), validateAgainstCatalog(catalog, .{ .op = .set, .texture = "grid" }));
    try std.testing.expectEqual(@as(?[]const u8, null), validateAgainstCatalog(catalog, .{ .op = .set, .texture = "none" }));
    // A skin whose own texture is "logo" can be named as a texture source.
    try std.testing.expectEqual(@as(?[]const u8, null), validateAgainstCatalog(catalog, .{ .op = .set, .texture = "arca" }));
    // Requests that only carry color/opacity/reset are not checked here.
    try std.testing.expectEqual(@as(?[]const u8, null), validateAgainstCatalog(catalog, .{ .op = .reset }));
    try std.testing.expectEqual(@as(?[]const u8, null), validateAgainstCatalog(catalog, .{ .op = .set, .background = "#123456" }));
}

test "skins: validateAgainstCatalog rejects an unknown skin" {
    const catalog = testCatalog();
    const msg = validateAgainstCatalog(catalog, .{ .op = .set, .skin = "nosuchskin" });
    try std.testing.expectEqualStrings("skins: unknown skin 'nosuchskin' (try: skins list)", msg.?);
}

test "skins: validateAgainstCatalog rejects an unknown texture" {
    const catalog = testCatalog();
    const msg = validateAgainstCatalog(catalog, .{ .op = .set, .texture = "nosuchtexture" });
    try std.testing.expectEqualStrings("skins: unknown texture 'nosuchtexture' (try: skins list)", msg.?);
    // "prod" is a real skin, but its texture isn't "logo", so it isn't a
    // valid texture name either.
    const msg2 = validateAgainstCatalog(catalog, .{ .op = .set, .texture = "prod" });
    try std.testing.expectEqualStrings("skins: unknown texture 'prod' (try: skins list)", msg2.?);
}

// Real shape written by `SkinManager.writeCatalog()` (`JSONEncoder` with
// `.prettyPrinted, .sortedKeys`), including a pane entry, so a change to the
// Swift encoder's output that this parser can't read is caught here rather
// than only at runtime against `~/.config/ghostty-skins/state/catalog.json`.
test "skins: parseCatalog reads the Swift writer's fixture" {
    const alloc = std.testing.allocator;
    const bytes = @embedFile("testdata/catalog.json");
    const parsed = try parseCatalog(alloc, bytes);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.version);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.skins.len);
    try std.testing.expectEqualStrings("arca", parsed.value.skins[0].name);
    try std.testing.expectEqualStrings("logo", parsed.value.skins[0].texture);
    try std.testing.expectEqualStrings("prod", parsed.value.skins[1].name);
    try std.testing.expectEqual(@as(usize, 6), parsed.value.textures.len);
    const pane = parsed.value.panes.map.get("3A281C4C-6DE1-4B96-9B35-0F7F5EE2AB3E").?;
    try std.testing.expectEqualStrings("arca", pane.skin);
    try std.testing.expectEqualStrings("config", pane.source);
    try std.testing.expectEqualStrings("#12222b", pane.background);
    try std.testing.expect(validateAgainstCatalog(parsed.value, .{ .op = .set, .skin = "arca" }) == null);
    try std.testing.expect(validateAgainstCatalog(parsed.value, .{ .op = .set, .skin = "nosuchskin" }) != null);
}

test "skins: catalog without rarity still parses" {
    const alloc = std.testing.allocator;
    const json =
        \\{"version":1,"skins":[{"name":"a","background":"#000000","texture":"none"}],"textures":[],
        \\ "panes":{"A":{"skin":"a","source":"override","background":"#000000"}}}
    ;
    const parsed = try parseCatalog(alloc, json);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("project", parsed.value.skins[0].rarity);
    try std.testing.expectEqualStrings("override", parsed.value.panes.map.get("A").?.source);
}
