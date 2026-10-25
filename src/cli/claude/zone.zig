//! Pure logic for a pane's zone file, `<PANE>.zone.json` beside the
//! context handoff's queue: the Mac app rewrites it whenever the pane's
//! zone changes and deletes it when the pane leaves every zone. See
//! docs/superpowers/specs/2026-10-24-lostty-zones-design.md (§5, §7).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// The SessionStart sources that start Claude without the zone's brief in
/// its context. `resume` and `fork` carry the conversation that had it.
pub fn briefsAt(source: []const u8) bool {
    for ([_][]const u8{ "startup", "clear", "compact" }) |s| {
        if (std.mem.eql(u8, source, s)) return true;
    }
    return false;
}

/// The brief a new Claude session in the zone starts with: the zone
/// file's `"start"`. Null when the file isn't JSON or has none.
pub fn start(alloc: Allocator, json: []const u8) ?[]const u8 {
    const File = struct { start: ?[]const u8 = null };
    const parsed = std.json.parseFromSliceLeaky(File, alloc, json, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch return null;
    const text = parsed.start orelse return null;
    return if (text.len == 0) null else text;
}

test "claude zone: the brief is the file's start" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("Lostty zone: Textberry (~/t).\nTextberry: an app", start(a,
        \\{"start":"Lostty zone: Textberry (~/t).\nTextberry: an app","zone":"Textberry","folder":null,"members":[]}
    ).?);
    try std.testing.expect(start(a,
        \\{"zone":"Textberry"}
    ) == null);
    try std.testing.expect(start(a,
        \\{"start":""}
    ) == null);
    try std.testing.expect(start(a,
        \\{"start":7}
    ) == null);
    try std.testing.expect(start(a, "not json") == null);
}

test "claude zone: which sources get the brief" {
    try std.testing.expect(briefsAt("startup"));
    try std.testing.expect(briefsAt("clear"));
    try std.testing.expect(briefsAt("compact"));
    try std.testing.expect(!briefsAt("resume"));
    try std.testing.expect(!briefsAt("fork"));
}
