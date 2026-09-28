# Ghostty Skins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every Ghostty pane an automatic, project-specific background color and texture that follows `cd`, with temporary overrides from a title-bar chip and a `skins` CLI.

**Architecture:** A personal fork of Ghostty v1.3.1. New Swift code in `macos/Sources/Features/Skins/` resolves each pane's working directory to a skin and applies it with the existing per-surface API `ghostty_surface_update_config`. The Zig core gains OSC 1337 `SetUserVar` support (delivered to Swift as a new apprt action) and a `ghostty +skins` CLI action, so a `skins` command can talk to its own pane by printing an escape sequence.

**Tech Stack:** Zig 0.15.2 (core + CLI, vaxis TUI), Swift 5 mode / SwiftUI / AppKit / CoreGraphics (macOS app), Swift Testing (`import Testing`), Xcode 26.3.

**Spec:** `docs/superpowers/specs/2026-09-28-ghostty-skins-design.md` (rev. 2). Read it before starting any task.

## Global Constraints

- Base is tag `v1.3.1`; work on branch `skins`. Remotes: `origin` = `Lawliang/ghostty-skins` (push here), `upstream` = `ghostty-org/ghostty` (never push).
- Zig is `$(brew --prefix zig@0.15)/bin/zig` (0.15.2). Prefix Zig commands with `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" &&`.
- Rebuild the core library after any change outside `macos/`: `zig build -Demit-macos-app=false -Doptimize=ReleaseFast -Dxcframework-target=native`.
- Build the app with `macos/build.nu --scheme Ghostty --configuration Debug --action build`; run Swift tests with `macos/skins-test.sh [SuiteName]` (created in Task 1).
- Every new Swift file is wrapped in `#if os(macOS)` … `#endif` and explicitly imports each module it uses (`Foundation`, `AppKit`, `SwiftUI`, `Combine`, `GhosttyKit`) — the project enables `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`.
- Swift tests live in `macos/Tests/Skins/` and use `import Testing` + `@testable import Ghostty`.
- Config file: `~/.config/ghostty-skins/skins.toml`. Catalog: `~/.config/ghostty-skins/state/catalog.json`. Caches: `~/Library/Caches/ghostty-skins/{textures,overlays}/`.
- User var name `GHOSTTY_SKIN`; pane env var `GHOSTTY_SKINS_SURFACE`; payload cap 4096 decoded bytes; names match `[A-Za-z0-9_-]{1,64}`.
- Terminal-originated requests never carry file paths (spec §6.3).
- Texture tiles are 220×220 device pixels; defaults: `texture_opacity = 0.16`, `auto = true`, preview timeout 60 s.
- App name "Ghostty Skins", bundle ID `com.lawliang.ghostty-skins` (Debug: `com.lawliang.ghostty-skins.debug`).
- Edits to upstream files are minimal hooks; every one is recorded in `UPGRADING.md`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Git author email is already the GitHub no-reply address; do not change git config. Never commit anything from `spike-shots/` or `~/.config`.
- Screenshots need macOS Screen Recording permission for the terminal running the agent: ask the user before each E2E screenshot session and remind them to revoke it afterwards.

## Review Focus

1. **Home directory is itself a git repo (dotfiles).** Expected: `~` and unrelated folders under it are not auto-skinned as one giant "project". Pinned by `ProjectResolverTests.homeGitRootIsIgnored` (Task 6).
2. **Editor saves an invalid `skins.toml` mid-edit, or saves via rename.** Expected: panes keep the last good skins, the chip shows the error, and the next valid save recovers. Pinned by `SkinConfigStoreTests` (Task 10) and the directory watcher.
3. **Hostile output (`cat` of a crafted file) sends a skin request with a path, an unknown name, or a huge payload.** Expected: ignored, nothing read from disk. Pinned by `SkinRequestTests` (Task 7), `SkinManagerTests.rejectsUnknownNames` (Task 9) and Zig `decodeUserVar` size tests (Task 3).
4. **Picker killed mid-preview (terminal closed, `kill`).** Expected: the preview disappears within ~60 s. Pinned by `SkinManagerTests.previewExpires` (Task 9).
5. **Symlinked or oddly spelled paths (`/tmp` → `/private/tmp`, `..`, trailing `/`, `arca` vs `arca-labs`).** Expected: matched by real path and whole path components. Pinned by `ProjectResolverTests` (Task 6).

---

## File Structure

New Swift (`macos/Sources/Features/Skins/`):

| File | Responsibility |
|---|---|
| `SkinsTOML.swift` | TOML-subset tokenizer → `[TOMLSection]` |
| `SkinModel.swift` | `RGB`, `BuiltinTexture`, `SkinTexture`, `Skin`, `SkinMatch`, `SkinNames`, `SkinConfig.parse` validation |
| `ProjectResolver.swift` | pwd → `SkinSource` (config match / git root / none) |
| `AutoSkin.swift` | repo name → deterministic `Skin` |
| `SkinRequest.swift` | constants + decoding/validating the `GHOSTTY_SKIN` JSON payload |
| `TextureStore.swift` | render + cache tile PNGs (built-ins and logo tiles) |
| `SkinManager.swift` | per-pane layers, apply decisions, catalog.json |
| `SkinConfigStore.swift` | load/watch `skins.toml`, keep last good config |
| `SkinsRuntime.swift` | `SkinOverlay`, `GhosttySkinApplier`, `SkinsRuntime` singleton wiring |
| `SkinChipView.swift` | `SkinChipModel`, title-bar chip, `Color(rgb:)` |
| `SkinPopoverView.swift` | override popover |

New Zig: `src/cli/skins.zig` (CLI + TUI), `src/cli/skins/protocol.zig` (pure encode/parse logic).

Upstream files touched (hooks only): `macos/Ghostty.xcodeproj/project.pbxproj`, `src/terminal/osc.zig`, `src/terminal/osc/parsers/iterm2.zig`, `src/terminal/stream.zig`, `src/terminal/stream_readonly.zig`, `src/termio/stream_handler.zig`, `src/apprt/surface.zig`, `src/Surface.zig`, `src/apprt/action.zig`, `include/ghostty.h`, `src/apprt/gtk/class/application.zig`, `src/cli/ghostty.zig`, `src/shell-integration/zsh/ghostty-integration`, `src/shell-integration/bash/ghostty.bash`, `macos/Sources/Ghostty/Ghostty.App.swift`, `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`, `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift`, `macos/Sources/Features/Terminal/BaseTerminalController.swift`.

New repo files: `UPGRADING.md`, `SKINS.md`, `docs/skins/skins.example.toml`, `macos/skins-test.sh`, `macos/install-skins.sh`.

---

### Task 1: Fork identity, test runner, upgrade notes

**Files:**
- Modify: `macos/Ghostty.xcodeproj/project.pbxproj` (app target build settings only)
- Create: `macos/skins-test.sh`, `UPGRADING.md`

**Interfaces:**
- Produces: `macos/skins-test.sh [Suite]` used by every Swift task; app bundle ID `com.lawliang.ghostty-skins(.debug)`.

- [ ] **Step 1: Rename the app target (bundle ID + display name) in the three app build configurations**

Only build-settings blocks containing `EXECUTABLE_NAME = ghostty;` are the macOS app target. Run:

```bash
cd /Users/lawliang/projectrepos/ghostty-skins && python3 - <<'EOF'
import pathlib
p = pathlib.Path("macos/Ghostty.xcodeproj/project.pbxproj")
s = p.read_text()
parts = s.split("buildSettings = {")
changed = 0
for i in range(1, len(parts)):
    end = parts[i].index("};")
    body = parts[i][:end]
    if "EXECUTABLE_NAME = ghostty;" not in body:
        continue
    new = (body
        .replace("PRODUCT_BUNDLE_IDENTIFIER = com.mitchellh.ghostty.debug;", "PRODUCT_BUNDLE_IDENTIFIER = com.lawliang.ghostty-skins.debug;")
        .replace("PRODUCT_BUNDLE_IDENTIFIER = com.mitchellh.ghostty;", "PRODUCT_BUNDLE_IDENTIFIER = com.lawliang.ghostty-skins;")
        .replace('INFOPLIST_KEY_CFBundleDisplayName = "Ghostty[DEBUG]";', 'INFOPLIST_KEY_CFBundleDisplayName = "Ghostty Skins[DEBUG]";')
        .replace("INFOPLIST_KEY_CFBundleDisplayName = Ghostty;", 'INFOPLIST_KEY_CFBundleDisplayName = "Ghostty Skins";'))
    changed += new != body
    parts[i] = new + parts[i][end:]
p.write_text("buildSettings = {".join(parts))
print("blocks changed:", changed)
EOF
grep -c "com.lawliang.ghostty-skins" macos/Ghostty.xcodeproj/project.pbxproj
grep -c 'CFBundleDisplayName = "Ghostty Skins' macos/Ghostty.xcodeproj/project.pbxproj
```

Expected: `blocks changed: 3`, then `3`, then `3`.

Sparkle needs no change: `macos/Ghostty-Info.plist` already has `SUEnableAutomaticChecks = false`, which `AppDelegate.swift:764-769` honors.

- [ ] **Step 2: Create the Swift test runner**

`macos/skins-test.sh`:

```sh
#!/bin/sh
# Runs the macOS unit tests with a clean environment (mirrors build.nu).
# Usage: macos/skins-test.sh [SuiteName]   e.g. macos/skins-test.sh SkinsTOMLTests
set -eu
cd "$(dirname "$0")"
mkdir -p build
ONLY=""
if [ $# -gt 0 ]; then ONLY="-only-testing:GhosttyTests/$1"; fi
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project Ghostty.xcodeproj -scheme Ghostty -configuration Debug \
  SYMROOT="$PWD/build" -skip-testing GhosttyUITests $ONLY test > build/last-test.log 2>&1 || true
grep -E "error:|✘|Test run with|\*\* TEST (SUCCEEDED|FAILED)" build/last-test.log || true
grep -q "\*\* TEST SUCCEEDED" build/last-test.log
```

Run: `chmod +x macos/skins-test.sh`

- [ ] **Step 3: Write `UPGRADING.md`**

```markdown
# Upgrading Ghostty Skins to a new Ghostty release

Ghostty Skins is `skins` = upstream tag + our commits. To move to a new tag:

    git fetch upstream tag v1.3.2 --no-tags
    git merge v1.3.2
    # resolve conflicts in the hook list below, then:
    export PATH="$(brew --prefix zig@0.15)/bin:$PATH"   # use the Zig version the new tag requires
    zig build test -Demit-macos-app=false -Dtest-filter=SetUserVar
    zig build -Demit-macos-app=false -Doptimize=ReleaseFast -Dxcframework-target=native
    macos/skins-test.sh
    macos/install-skins.sh

## Upstream files we hook (keep these hunks when resolving conflicts)

- `macos/Ghostty.xcodeproj/project.pbxproj` — app target `PRODUCT_BUNDLE_IDENTIFIER` and `INFOPLIST_KEY_CFBundleDisplayName` (3 build configurations).
```

- [ ] **Step 4: Verify the renamed app builds**

Run: `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" && zig build -Demit-macos-app=false -Doptimize=ReleaseFast -Dxcframework-target=native && macos/build.nu --scheme Ghostty --configuration Debug --action build 2>&1 | tail -3 && /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" macos/build/Debug/Ghostty.app/Contents/Info.plist`
Expected: `** BUILD SUCCEEDED **` and `com.lawliang.ghostty-skins.debug`.

- [ ] **Step 5: Verify the test runner works on an existing suite**

Run: `macos/skins-test.sh ShellTests`
Expected: exit 0, output contains `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add macos/Ghostty.xcodeproj/project.pbxproj macos/skins-test.sh UPGRADING.md
git commit -m "skins: rename app to Ghostty Skins, add test runner and upgrade notes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Parse OSC 1337 SetUserVar

**Files:**
- Modify: `src/terminal/osc.zig` (Command union ~line 25, `Key` list ~line 170, reset switch ~line 420)
- Modify: `src/terminal/osc/parsers/iterm2.zig` (`.SetUserVar` branch, tests at end)

**Interfaces:**
- Produces: `osc.Command.set_user_var: struct { name: []const u8, value: [:0]const u8 }` — `value` is still base64 text.

- [ ] **Step 1: Write the failing tests** (append to `src/terminal/osc/parsers/iterm2.zig`)

```zig
test "OSC: 1337: SetUserVar with name and value" {
    const testing = std.testing;

    var p: Parser = .init(testing.allocator);
    defer p.deinit();

    const input = "1337;SetUserVar=GHOSTTY_SKIN=eyJ2IjoxfQ==";
    for (input) |ch| p.next(ch);

    const cmd = p.end('\x1b').?.*;
    try testing.expect(cmd == .set_user_var);
    try testing.expectEqualStrings("GHOSTTY_SKIN", cmd.set_user_var.name);
    try testing.expectEqualStrings("eyJ2IjoxfQ==", cmd.set_user_var.value);
}

test "OSC: 1337: SetUserVar with empty value is allowed" {
    const testing = std.testing;

    var p: Parser = .init(testing.allocator);
    defer p.deinit();

    const input = "1337;SetUserVar=FOO=";
    for (input) |ch| p.next(ch);

    const cmd = p.end('\x1b').?.*;
    try testing.expect(cmd == .set_user_var);
    try testing.expectEqualStrings("FOO", cmd.set_user_var.name);
    try testing.expectEqualStrings("", cmd.set_user_var.value);
}

test "OSC: 1337: SetUserVar invalid forms" {
    const testing = std.testing;

    for ([_][]const u8{
        "1337;SetUserVar",
        "1337;SetUserVar=",
        "1337;SetUserVar=NOEQUALS",
        "1337;SetUserVar==abc",
    }) |input| {
        var p: Parser = .init(testing.allocator);
        defer p.deinit();
        for (input) |ch| p.next(ch);
        try testing.expect(p.end('\x1b') == null);
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" && zig build test -Demit-macos-app=false -Dtest-filter="SetUserVar" 2>&1 | tail -15`
Expected: compile error — `no field named 'set_user_var'`.

- [ ] **Step 3: Add the command to `src/terminal/osc.zig`**

In `pub const Command = union(Key) {`, directly after the `mouse_shape` field, add:

```zig
    /// OSC 1337 SetUserVar (iTerm2). `value` is the raw base64 text; decoding
    /// happens in the surface so the parser stays allocation-free.
    set_user_var: struct {
        name: []const u8,
        value: [:0]const u8,
    },
```

In `pub const Key = LibEnum(` append `"set_user_var",` as the **last** entry of the list (after `"context_signal",`; order matters for the C ABI).

In the reset switch that lists `.context_signal,` followed by `=> {},` (around line 427), add `.set_user_var,` to that list.

- [ ] **Step 4: Implement the parser branch in `src/terminal/osc/parsers/iterm2.zig`**

Remove `.SetUserVar,` from the "unimplemented OSC 1337" list, and add this branch before `.AddAnnotation,`:

```zig
        .SetUserVar => {
            // Format: SetUserVar=<name>=<base64 value>
            const value = value_ orelse {
                parser.command = .invalid;
                return null;
            };
            const eq = std.mem.indexOfScalar(u8, value, '=') orelse {
                parser.command = .invalid;
                return null;
            };
            if (eq == 0) {
                parser.command = .invalid;
                return null;
            }
            parser.command = .{
                .set_user_var = .{
                    .name = value[0..eq],
                    .value = value[eq + 1 .. value.len :0],
                },
            };
            return &parser.command;
        },
```

- [ ] **Step 5: Handle the new command in the stream dispatcher so the tree compiles**

In `src/terminal/stream.zig`, in `oscDispatch`'s list of ignored commands (the arm containing `.context_signal,` and `log.debug("unimplemented OSC callback: ...`), add `.set_user_var,`. (Task 3 replaces this with real handling.)

- [ ] **Step 6: Run the tests to verify they pass**

Run: `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" && zig build test -Demit-macos-app=false -Dtest-filter="OSC: 1337" 2>&1 | tail -5`
Expected: all `OSC: 1337` tests pass (no failures reported). If the compiler reports another exhaustive `switch` missing `set_user_var`, add `.set_user_var` to that switch's no-op arm and re-run.

- [ ] **Step 7: Record hooks and commit**

Append to the hook list in `UPGRADING.md`:

```markdown
- `src/terminal/osc.zig` — `set_user_var` Command field, `Key` list entry (last), reset-switch entry.
- `src/terminal/osc/parsers/iterm2.zig` — `.SetUserVar` branch (removed from unimplemented list) + tests.
```

```bash
git add src/terminal/osc.zig src/terminal/osc/parsers/iterm2.zig src/terminal/stream.zig UPGRADING.md
git commit -m "core: parse OSC 1337 SetUserVar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Deliver user vars to the app (`GHOSTTY_ACTION_SET_USER_VAR`)

**Files:**
- Modify: `src/terminal/stream.zig`, `src/terminal/stream_readonly.zig`, `src/termio/stream_handler.zig`, `src/apprt/surface.zig`, `src/Surface.zig`, `src/apprt/action.zig`, `include/ghostty.h`, `src/apprt/gtk/class/application.zig`

**Interfaces:**
- Consumes: `osc.Command.set_user_var` (Task 2).
- Produces: C API `GHOSTTY_ACTION_SET_USER_VAR` with `ghostty_action_set_user_var_s { const char* name; const char* value; }` — `value` is **decoded** (≤ 4096 bytes), both NUL-terminated. Target is always a surface.

- [ ] **Step 1: Write the failing test** (append to `src/Surface.zig`)

```zig
test "decodeUserVar" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const d = (try decodeUserVar(alloc, "GHOSTTY_SKIN=eyJ2IjoxfQ==")).?;
    defer alloc.free(d.buf);
    try testing.expectEqualStrings("GHOSTTY_SKIN", d.name);
    try testing.expectEqualStrings("{\"v\":1}", d.value);

    try testing.expect((try decodeUserVar(alloc, "noequals")) == null);
    try testing.expect((try decodeUserVar(alloc, "=eyJ2IjoxfQ==")) == null);
    try testing.expect((try decodeUserVar(alloc, "X=not base64!")) == null);

    // Over the cap: 4097 decoded bytes.
    const big = try alloc.alloc(u8, 4097);
    defer alloc.free(big);
    @memset(big, 'a');
    const enc = std.base64.standard.Encoder;
    const b64 = try alloc.alloc(u8, enc.calcSize(big.len));
    defer alloc.free(b64);
    _ = enc.encode(b64, big);
    const raw = try std.fmt.allocPrint(alloc, "X={s}", .{b64});
    defer alloc.free(raw);
    try testing.expect((try decodeUserVar(alloc, raw)) == null);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" && zig build test -Demit-macos-app=false -Dtest-filter="decodeUserVar" 2>&1 | tail -5`
Expected: compile error — `use of undeclared identifier 'decodeUserVar'`.

- [ ] **Step 3: Add the stream action (`src/terminal/stream.zig`)**

In the `Action` union, after `report_pwd: ReportPwd,` add `set_user_var: SetUserVar,`. In that union's `Key` name list, append `"set_user_var",` as the **last** entry (after `"semantic_prompt",`). Next to `pub const ShowDesktopNotification = struct {`, add:

```zig
    pub const SetUserVar = struct {
        name: []const u8,
        value: []const u8,

        pub const C = extern struct {
            name: lib.String,
            value: lib.String,
        };

        pub fn cval(self: SetUserVar) SetUserVar.C {
            return .{
                .name = .init(self.name),
                .value = .init(self.value),
            };
        }
    };
```

In `oscDispatch`, remove `.set_user_var,` from the ignored list (added in Task 2) and add this arm after the `.report_pwd` arm:

```zig
                .set_user_var => |v| {
                    try self.handler.vt(.set_user_var, .{
                        .name = v.name,
                        .value = v.value,
                    });
                },
```

In `src/terminal/stream_readonly.zig`, add `.set_user_var,` to the no-op list that contains `.report_pwd,` and `.show_desktop_notification,`.

- [ ] **Step 4: Forward from the stream handler (`src/termio/stream_handler.zig`)**

In the `vt` switch, after `.report_pwd => try self.reportPwd(value.url),` add:

```zig
            .set_user_var => self.setUserVar(value.name, value.value),
```

Add this method next to `reportPwd`:

```zig
    /// Forward OSC 1337 SetUserVar to the surface as "name=base64value".
    fn setUserVar(self: *StreamHandler, name: []const u8, value: []const u8) void {
        const joined = std.fmt.allocPrint(self.alloc, "{s}={s}", .{ name, value }) catch |err| {
            log.warn("error formatting user var err={}", .{err});
            return;
        };
        defer self.alloc.free(joined);
        const req = apprt.surface.Message.WriteReq.init(self.alloc, joined) catch |err| {
            log.warn("error notifying surface of user var err={}", .{err});
            return;
        };
        self.surfaceMessageWriter(.{ .user_var = req });
    }
```

- [ ] **Step 5: Add the surface message (`src/apprt/surface.zig`)**

After `pwd_change: WriteReq,` add:

```zig
    /// The terminal set a user variable (OSC 1337 SetUserVar) as "name=base64".
    user_var: WriteReq,
```

- [ ] **Step 6: Add the apprt action (`src/apprt/action.zig`)**

At the end of the `Action` union (after `copy_title_to_clipboard,`), add:

```zig
    /// A program set a user variable with OSC 1337 SetUserVar. The value
    /// is base64-decoded and at most 4096 bytes.
    set_user_var: SetUserVar,
```

Append `set_user_var,` as the last entry of `pub const Key = enum(c_int) {` (after `copy_title_to_clipboard,`). After `pub const Pwd = struct {…};` add:

```zig
pub const SetUserVar = struct {
    name: [:0]const u8,
    value: [:0]const u8,

    // Sync with: ghostty_action_set_user_var_s
    pub const C = extern struct {
        name: [*:0]const u8,
        value: [*:0]const u8,
    };

    pub fn cval(self: SetUserVar) C {
        return .{
            .name = self.name.ptr,
            .value = self.value.ptr,
        };
    }

    pub fn format(
        value: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: *std.Io.Writer,
    ) !void {
        try writer.print("{s}{{ {s} }}", .{ @typeName(@This()), value.name });
    }
};
```

- [ ] **Step 7: Mirror it in `include/ghostty.h`**

After `} ghostty_action_pwd_s;` add:

```c
// apprt.action.SetUserVar
typedef struct {
  const char* name;
  const char* value;
} ghostty_action_set_user_var_s;
```

Append `GHOSTTY_ACTION_SET_USER_VAR,` after `GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD,` in `ghostty_action_tag_e`, and add `ghostty_action_set_user_var_s set_user_var;` as the last member of the `ghostty_action_u` union.

- [ ] **Step 8: Decode and dispatch in `src/Surface.zig`**

In `handleMessage`'s switch, after the `.pwd_change => |w| { … },` arm, add:

```zig
        .user_var => |w| {
            defer w.deinit();
            self.userVar(w.slice()) catch |err| {
                log.warn("error handling user var err={}", .{err});
            };
        },
```

Add near the end of the file (before the tests), using the file's existing `Allocator` alias:

```zig
/// Largest decoded SetUserVar value we forward to the apprt.
pub const max_user_var_len = 4096;

const DecodedUserVar = struct {
    /// Backing allocation: name, NUL, value, NUL. Free with the same allocator.
    buf: []u8,
    name: [:0]const u8,
    value: [:0]const u8,
};

/// Split "name=base64" and decode the value. Returns null for malformed
/// input or a value larger than max_user_var_len.
fn decodeUserVar(alloc: Allocator, raw: []const u8) !?DecodedUserVar {
    const eq = std.mem.indexOfScalar(u8, raw, '=') orelse return null;
    const name = raw[0..eq];
    if (name.len == 0) return null;
    const encoded = raw[eq + 1 ..];

    const decoder = std.base64.standard.Decoder;
    const size = decoder.calcSizeForSlice(encoded) catch return null;
    if (size > max_user_var_len) return null;

    const buf = try alloc.alloc(u8, name.len + 1 + size + 1);
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    decoder.decode(buf[name.len + 1 .. name.len + 1 + size], encoded) catch {
        alloc.free(buf);
        return null;
    };
    buf[buf.len - 1] = 0;
    return .{
        .buf = buf,
        .name = buf[0..name.len :0],
        .value = buf[name.len + 1 .. buf.len - 1 :0],
    };
}

fn userVar(self: *Surface, raw: []const u8) !void {
    const decoded = (try decodeUserVar(self.alloc, raw)) orelse {
        log.debug("ignoring malformed or oversized user var", .{});
        return;
    };
    defer self.alloc.free(decoded.buf);
    _ = try self.rt_app.performAction(
        .{ .surface = self },
        .set_user_var,
        .{ .name = decoded.name, .value = decoded.value },
    );
}
```

- [ ] **Step 9: Keep the GTK apprt compiling**

In `src/apprt/gtk/class/application.zig`, add `.set_user_var,` to the list ending in `.undo, .redo, => { log.warn("unimplemented action={}", …` (around line 779).

- [ ] **Step 10: Run tests**

Run: `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" && zig build test -Demit-macos-app=false -Dtest-filter="decodeUserVar" 2>&1 | tail -5 && zig build test -Demit-macos-app=false -Dtest-filter="ghostty.h Action.Key" 2>&1 | tail -5 && zig build test -Demit-macos-app=false -Dtest-filter="OSC" 2>&1 | tail -5`
Expected: all pass. If the compiler reports another exhaustive switch missing `set_user_var` (stream handler test doubles, inspector), add it to that switch's no-op arm and re-run.

- [ ] **Step 11: Rebuild the core library and the app**

Run: `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" && zig build -Demit-macos-app=false -Doptimize=ReleaseFast -Dxcframework-target=native && macos/build.nu --scheme Ghostty --configuration Debug --action build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **` (Swift ignores the new action via its `default:` case for now).

- [ ] **Step 12: Record hooks and commit**

Append to `UPGRADING.md`:

```markdown
- `src/terminal/stream.zig` — `set_user_var` Action + Key entry (last) + `SetUserVar` struct + `oscDispatch` arm.
- `src/terminal/stream_readonly.zig` — `.set_user_var` no-op.
- `src/termio/stream_handler.zig` — `.set_user_var` vt arm + `setUserVar`.
- `src/apprt/surface.zig` — `user_var: WriteReq` message.
- `src/Surface.zig` — `.user_var` handler, `decodeUserVar`, `userVar`, test.
- `src/apprt/action.zig` + `include/ghostty.h` — `set_user_var` action (last in enum/union), `ghostty_action_set_user_var_s`.
- `src/apprt/gtk/class/application.zig` — `.set_user_var` unimplemented.
```

```bash
git add src include UPGRADING.md
git commit -m "core: deliver OSC 1337 user vars to the apprt as set_user_var

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: TOML-subset parser

**Files:**
- Create: `macos/Sources/Features/Skins/SkinsTOML.swift`
- Test: `macos/Tests/Skins/SkinsTOMLTests.swift`

**Interfaces:**
- Produces: `enum TOMLValue: Equatable { case string(String), number(Double), bool(Bool) }`; `struct TOMLSection: Equatable { var path: [String]; var isArrayElement: Bool; var values: [String: TOMLValue]; var line: Int }`; `struct TOMLError: Error, Equatable, CustomStringConvertible { let line: Int; let message: String }`; `enum SkinsTOML { static func parse(_ text: String) throws -> [TOMLSection]; static func isBareKey(_ key: String) -> Bool }`. `parse` always returns the implicit root section (path `[]`, line 0) first.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Ghostty

struct SkinsTOMLTests {
    @Test func parsesTablesArraysAndScalars() throws {
        let sections = try SkinsTOML.parse("""
        # top comment
        [defaults]
        texture_opacity = 0.2   # trailing comment
        auto = false

        [skins.arca]
        background = "#12222b"
        logo = "~/a b/logo.svg"

        [[match]]
        path = "~/projectrepos/arca"
        skin = "arca"

        [[match]]
        path = "~/x#y"
        skin = "arca"
        """)
        #expect(sections.count == 5)
        #expect(sections[0] == TOMLSection(path: [], isArrayElement: false, values: [:], line: 0))
        #expect(sections[1] == TOMLSection(
            path: ["defaults"], isArrayElement: false,
            values: ["texture_opacity": .number(0.2), "auto": .bool(false)], line: 2))
        #expect(sections[2].path == ["skins", "arca"])
        #expect(sections[2].values["logo"] == .string("~/a b/logo.svg"))
        #expect(sections[3].isArrayElement)
        #expect(sections[4].values["path"] == .string("~/x#y"))
    }

    @Test func stringEscapes() throws {
        let sections = try SkinsTOML.parse(#"k = "a\"b\\c""#)
        #expect(sections[0].values["k"] == .string(#"a"b\c"#))
    }

    @Test(arguments: [
        "k = [1, 2]", "k = {a = 1}", "k = \"open", "k = 1979-05-27", "k = inf",
        "= 1", "bad key = 1", "[a", "[[a]", "k = \"x\" y", #"k = "\q""#,
    ])
    func rejectsUnsupported(_ input: String) {
        #expect(throws: TOMLError.self) { try SkinsTOML.parse(input) }
    }

    @Test func rejectsDuplicates() {
        #expect(throws: TOMLError.self) { try SkinsTOML.parse("[a]\nk = 1\nk = 2") }
        #expect(throws: TOMLError.self) { try SkinsTOML.parse("[a]\n[a]") }
    }

    @Test func errorsCarryLineNumbers() {
        #expect(throws: TOMLError(line: 3, message: "expected key = value")) {
            try SkinsTOML.parse("[a]\n\nnonsense")
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `macos/skins-test.sh SkinsTOMLTests`
Expected: FAIL — `cannot find 'SkinsTOML' in scope`.

- [ ] **Step 3: Implement `SkinsTOML.swift`**

```swift
#if os(macOS)
import Foundation

/// A scalar value in skins.toml.
enum TOMLValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
}

/// One `[table]` or `[[array-of-tables]]` block, or the implicit root block.
struct TOMLSection: Equatable {
    var path: [String]
    var isArrayElement: Bool
    var values: [String: TOMLValue]
    var line: Int
}

struct TOMLError: Error, Equatable, CustomStringConvertible {
    let line: Int
    let message: String
    var description: String { "skins.toml line \(line): \(message)" }
}

/// Parses the subset of TOML that skins.toml uses: `#` comments, `[a.b]` tables,
/// `[[a]]` arrays of tables, and `key = "string" | number | true | false`.
/// Inline tables, arrays, multi-line strings and dates are rejected.
enum SkinsTOML {
    static func parse(_ text: String) throws -> [TOMLSection] {
        var sections = [TOMLSection(path: [], isArrayElement: false, values: [:], line: 0)]
        var seenTables = Set<[String]>()
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let number = index + 1
            let line = stripComment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[[") {
                guard line.hasSuffix("]]"), line.count > 4 else {
                    throw TOMLError(line: number, message: "malformed [[table]] header")
                }
                let path = try keyPath(String(line.dropFirst(2).dropLast(2)), line: number)
                sections.append(TOMLSection(path: path, isArrayElement: true, values: [:], line: number))
            } else if line.hasPrefix("[") {
                guard line.hasSuffix("]"), line.count > 2 else {
                    throw TOMLError(line: number, message: "malformed [table] header")
                }
                let path = try keyPath(String(line.dropFirst().dropLast()), line: number)
                guard seenTables.insert(path).inserted else {
                    throw TOMLError(line: number, message: "duplicate table [\(path.joined(separator: "."))]")
                }
                sections.append(TOMLSection(path: path, isArrayElement: false, values: [:], line: number))
            } else {
                guard let eq = line.firstIndex(of: "=") else {
                    throw TOMLError(line: number, message: "expected key = value")
                }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                guard isBareKey(key) else {
                    throw TOMLError(line: number, message: "invalid key '\(key)'")
                }
                let valueText = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                let value = try parseValue(valueText, line: number)
                guard sections[sections.count - 1].values[key] == nil else {
                    throw TOMLError(line: number, message: "duplicate key '\(key)'")
                }
                sections[sections.count - 1].values[key] = value
            }
        }
        return sections
    }

    static func isBareKey(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "_" || $0 == "-"
        }
    }

    private static func keyPath(_ text: String, line: Int) throws -> [String] {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.allSatisfy(isBareKey) else {
            throw TOMLError(line: line, message: "invalid table name '\(text)'")
        }
        return parts
    }

    /// Removes a `# comment` that is not inside a string.
    private static func stripComment(_ line: String) -> String {
        var inString = false
        var escaped = false
        for (offset, ch) in line.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else if ch == "\"" {
                inString = true
            } else if ch == "#" {
                return String(line.prefix(offset))
            }
        }
        return line
    }

    private static func parseValue(_ text: String, line: Int) throws -> TOMLValue {
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        if text.hasPrefix("\"") { return .string(try parseString(text, line: line)) }
        if !text.hasPrefix("+"), text.rangeOfCharacter(from: .letters) == nil, let number = Double(text) {
            return .number(number)
        }
        throw TOMLError(line: line, message: "unsupported value '\(text)'")
    }

    private static func parseString(_ text: String, line: Int) throws -> String {
        var result = ""
        var iterator = text.dropFirst().makeIterator()
        while let ch = iterator.next() {
            switch ch {
            case "\"":
                guard iterator.next() == nil else {
                    throw TOMLError(line: line, message: "unexpected text after string")
                }
                return result
            case "\\":
                switch iterator.next() {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: throw TOMLError(line: line, message: "unsupported escape in string")
                }
            default:
                result.append(ch)
            }
        }
        throw TOMLError(line: line, message: "unterminated string")
    }
}
#endif
```

- [ ] **Step 4: Run to verify pass**

Run: `macos/skins-test.sh SkinsTOMLTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Skins/SkinsTOML.swift macos/Tests/Skins/SkinsTOMLTests.swift
git commit -m "skins: add TOML-subset parser for skins.toml

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Skin model and config validation

**Files:**
- Create: `macos/Sources/Features/Skins/SkinModel.swift`
- Test: `macos/Tests/Skins/SkinModelTests.swift`

**Interfaces:**
- Consumes: `SkinsTOML.parse`, `TOMLSection`, `TOMLValue`, `TOMLError` (Task 4).
- Produces:
  - `struct RGB: Hashable { var r, g, b: UInt8; init(r:g:b:); init?(hex: String); var hex: String; static func hsl(_ h: Double, _ s: Double, _ l: Double) -> RGB; func mixed(with: RGB, amount: Double) -> RGB; static let white }`
  - `enum BuiltinTexture: String, CaseIterable { case dots, grid, diagonal, cross, waves, noise }`
  - `enum SkinTexture: Hashable { case none, builtin(BuiltinTexture), logo(path: String) }`
  - `struct Skin: Hashable { var name: String; var background: RGB; var foreground: RGB?; var accent: RGB; var texture: SkinTexture; var textureOpacity: Double; static func defaultAccent(for: RGB) -> RGB; static let fallback: Skin }`
  - `struct SkinMatch: Hashable { var path: String; var skin: String }`
  - `enum SkinNames { static func isValid(_ s: String) -> Bool }` — `[A-Za-z0-9_-]{1,64}`
  - `struct SkinConfigError: Error, Equatable, CustomStringConvertible { let message: String }`
  - `struct SkinConfig: Equatable { var textureOpacity = 0.16; var auto = true; var skins: [String: Skin]; var matches: [SkinMatch]; static let empty; static func parse(_ text: String, home: String, fileExists: (String) -> Bool = …) throws -> SkinConfig; static func expand(_ path: String, home: String) -> String }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Ghostty

struct SkinModelTests {
    let home = "/Users/test"
    let arcaToml = """
    [defaults]
    texture_opacity = 0.2

    [skins.arca]
    background = "#12222B"
    foreground = "#eaf3ff"
    accent = "#46a2ff"
    logo = "~/projectrepos/arca-labs/website/assets/favicon.svg"

    [skins.prod]
    background = "#3a0f14"
    texture = "diagonal"

    [[match]]
    path = "~/projectrepos/arca"
    skin = "arca"
    """

    @Test func parsesFullConfig() throws {
        let config = try SkinConfig.parse(arcaToml, home: home, fileExists: { _ in true })
        #expect(config.textureOpacity == 0.2)
        #expect(config.auto == true)
        #expect(config.skins["arca"] == Skin(
            name: "arca",
            background: RGB(hex: "#12222b")!,
            foreground: RGB(hex: "#eaf3ff")!,
            accent: RGB(hex: "#46a2ff")!,
            texture: .logo(path: "/Users/test/projectrepos/arca-labs/website/assets/favicon.svg"),
            textureOpacity: 0.2))
        #expect(config.skins["prod"]?.texture == .builtin(.diagonal))
        #expect(config.skins["prod"]?.accent == Skin.defaultAccent(for: RGB(hex: "#3a0f14")!))
        #expect(config.matches == [SkinMatch(path: "/Users/test/projectrepos/arca", skin: "arca")])
    }

    @Test func defaultsApplyRegardlessOfOrder() throws {
        let config = try SkinConfig.parse("""
        [skins.a]
        background = "#000000"
        [defaults]
        texture_opacity = 0.3
        auto = false
        """, home: home)
        #expect(config.skins["a"]?.textureOpacity == 0.3)
        #expect(config.auto == false)
    }

    @Test func emptyTextIsEmptyConfig() throws {
        #expect(try SkinConfig.parse("", home: home) == .empty)
    }

    @Test(arguments: [
        "[skins.a]\nlogo = \"/x.svg\"\nbackground = \"#000000\"",                  // logo without accent
        "[skins.a]\nbackground = \"#000000\"\ntexture = \"grid\"\nlogo = \"/x\"\naccent = \"#ffffff\"", // both
        "[skins.a]\nbackground = \"#000000\"\ntexture = \"plaid\"",                 // unknown texture
        "[skins.a]\nbackground = \"#000000\"\ncolour = \"#000000\"",                // unknown key
        "[skins.a]\nbackground = \"red\"",                                          // bad color
        "[skins.a]\nforeground = \"#ffffff\"",                                      // missing background
        "[[match]]\npath = \"~/x\"\nskin = \"nope\"",                               // unknown skin
        "[[match]]\npath = \"~/x\"",                                                 // missing skin
        "[colors]\na = 1",                                                           // unknown table
        "k = 1",                                                                     // root key
        "[defaults]\ntexture_opacity = 2",                                           // out of range
        "[defaults]\nauto = \"yes\"",                                                // wrong type
    ])
    func rejectsInvalid(_ text: String) {
        #expect(throws: SkinConfigError.self) {
            try SkinConfig.parse(text, home: "/Users/test", fileExists: { _ in true })
        }
    }

    @Test func missingLogoFileIsAnError() {
        #expect(throws: SkinConfigError.self) {
            try SkinConfig.parse(
                "[skins.a]\nbackground = \"#000000\"\naccent = \"#ffffff\"\nlogo = \"~/gone.svg\"",
                home: "/Users/test", fileExists: { _ in false })
        }
    }

    @Test func tomlErrorsBecomeConfigErrors() {
        #expect(throws: SkinConfigError(message: "skins.toml line 1: expected key = value")) {
            try SkinConfig.parse("nonsense", home: "/Users/test")
        }
    }

    @Test func rgb() {
        #expect(RGB(hex: "#12222B")?.hex == "#12222b")
        #expect(RGB(hex: "12222b") == nil)
        #expect(RGB(hex: "#+abcde") == nil)
        #expect(RGB(hex: "#12222") == nil)
        #expect(RGB.hsl(0, 1, 0.5) == RGB(r: 255, g: 0, b: 0))
        #expect(RGB.hsl(120, 1, 0.25) == RGB(r: 0, g: 128, b: 0))
        #expect(RGB(r: 0, g: 0, b: 0).mixed(with: .white, amount: 0.5) == RGB(r: 128, g: 128, b: 128))
    }

    @Test func names() {
        #expect(SkinNames.isValid("arca-labs_2"))
        #expect(!SkinNames.isValid(""))
        #expect(!SkinNames.isValid("../etc"))
        #expect(!SkinNames.isValid("a/b"))
        #expect(!SkinNames.isValid(String(repeating: "a", count: 65)))
    }

    @Test func expand() {
        #expect(SkinConfig.expand("~", home: "/h") == "/h")
        #expect(SkinConfig.expand("~/a", home: "/h") == "/h/a")
        #expect(SkinConfig.expand("/abs", home: "/h") == "/abs")
        #expect(SkinConfig.expand("~other/a", home: "/h") == "~other/a")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `macos/skins-test.sh SkinModelTests`
Expected: FAIL — `cannot find 'SkinConfig' in scope`.

- [ ] **Step 3: Implement `SkinModel.swift`**

```swift
#if os(macOS)
import Foundation

struct RGB: Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    static let white = RGB(r: 255, g: 255, b: 255)

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parses `#rrggbb` (case-insensitive).
    init?(hex: String) {
        let digits = hex.dropFirst()
        guard hex.count == 7, hex.hasPrefix("#"), digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16) else { return nil }
        r = UInt8((value >> 16) & 0xff)
        g = UInt8((value >> 8) & 0xff)
        b = UInt8(value & 0xff)
    }

    var hex: String { String(format: "#%02x%02x%02x", r, g, b) }

    /// HSL with h in degrees and s, l in 0...1.
    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> RGB {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let rgb: (Double, Double, Double) = switch hp {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        func byte(_ v: Double) -> UInt8 { UInt8((min(max(v + m, 0), 1) * 255).rounded()) }
        return RGB(r: byte(rgb.0), g: byte(rgb.1), b: byte(rgb.2))
    }

    func mixed(with other: RGB, amount t: Double) -> RGB {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded())
        }
        return RGB(r: mix(r, other.r), g: mix(g, other.g), b: mix(b, other.b))
    }
}

enum BuiltinTexture: String, CaseIterable {
    case dots, grid, diagonal, cross, waves, noise
}

enum SkinTexture: Hashable {
    case none
    case builtin(BuiltinTexture)
    case logo(path: String)
}

struct Skin: Hashable {
    var name: String
    var background: RGB
    var foreground: RGB?
    var accent: RGB
    var texture: SkinTexture
    var textureOpacity: Double

    /// Accent used when a skin does not set one.
    static func defaultAccent(for background: RGB) -> RGB {
        background.mixed(with: .white, amount: 0.45)
    }

    /// Base for color/texture overrides on a pane that has no skin.
    static let fallback = Skin(
        name: "custom",
        background: RGB(r: 0x1c, g: 0x1c, b: 0x1c),
        foreground: nil,
        accent: defaultAccent(for: RGB(r: 0x1c, g: 0x1c, b: 0x1c)),
        texture: .none,
        textureOpacity: 0.16)
}

struct SkinMatch: Hashable {
    var path: String
    var skin: String
}

enum SkinNames {
    /// Skin and texture names: 1–64 of [A-Za-z0-9_-]. Nothing path-like passes.
    static func isValid(_ s: String) -> Bool {
        (1...64).contains(s.count) && SkinsTOML.isBareKey(s)
    }
}

struct SkinConfigError: Error, Equatable, CustomStringConvertible {
    let message: String
    var description: String { message }
}

struct SkinConfig: Equatable {
    var textureOpacity: Double = 0.16
    var auto: Bool = true
    var skins: [String: Skin] = [:]
    var matches: [SkinMatch] = []

    static let empty = SkinConfig()

    /// Parses and validates skins.toml. `home` replaces a leading `~`.
    static func parse(
        _ text: String,
        home: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> SkinConfig {
        let sections: [TOMLSection]
        do {
            sections = try SkinsTOML.parse(text)
        } catch let error as TOMLError {
            throw SkinConfigError(message: error.description)
        }

        var config = SkinConfig()
        var skinSections: [(name: String, section: TOMLSection)] = []
        for section in sections {
            switch (section.path, section.isArrayElement) {
            case ([], false):
                guard section.values.isEmpty else { throw error(section, "keys must be inside a table") }
            case (["defaults"], false):
                try checkKeys(section, allowed: ["texture_opacity", "auto"])
                if let value = section.values["texture_opacity"] {
                    config.textureOpacity = try opacity(value, section)
                }
                if let value = section.values["auto"] {
                    guard case .bool(let flag) = value else { throw error(section, "auto must be true or false") }
                    config.auto = flag
                }
            case (let path, false) where path.count == 2 && path[0] == "skins":
                skinSections.append((path[1], section))
            case (["match"], true):
                try checkKeys(section, allowed: ["path", "skin"])
                guard case .string(let path)? = section.values["path"],
                      case .string(let skin)? = section.values["skin"] else {
                    throw error(section, "[[match]] needs path and skin")
                }
                config.matches.append(SkinMatch(path: expand(path, home: home), skin: skin))
            default:
                throw error(section, "unknown table [\(section.path.joined(separator: "."))]")
            }
        }

        for (name, section) in skinSections {
            config.skins[name] = try skin(
                name: name, section: section, defaultOpacity: config.textureOpacity,
                home: home, fileExists: fileExists)
        }
        for match in config.matches where config.skins[match.skin] == nil {
            throw SkinConfigError(message: "[[match]] \(match.path) references unknown skin '\(match.skin)'")
        }
        return config
    }

    static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst() }
        return path
    }

    private static func skin(
        name: String, section: TOMLSection, defaultOpacity: Double,
        home: String, fileExists: (String) -> Bool
    ) throws -> Skin {
        try checkKeys(section, allowed: ["background", "foreground", "accent", "logo", "texture", "texture_opacity"])
        guard SkinNames.isValid(name) else {
            throw error(section, "skin name '\(name)' may only use letters, digits, - and _")
        }
        guard let background = try color(section, "background") else {
            throw error(section, "background is required")
        }
        let foreground = try color(section, "foreground")
        let accent = try color(section, "accent")

        var texture = SkinTexture.none
        switch (section.values["logo"], section.values["texture"]) {
        case (.some, .some):
            throw error(section, "use either logo or texture, not both")
        case (.string(let logo)?, nil):
            guard accent != nil else { throw error(section, "logo requires accent") }
            let path = expand(logo, home: home)
            guard fileExists(path) else { throw error(section, "logo file not found: \(path)") }
            texture = .logo(path: path)
        case (nil, .string(let textureName)?):
            if textureName != "none" {
                guard let builtin = BuiltinTexture(rawValue: textureName) else {
                    let names = BuiltinTexture.allCases.map(\.rawValue).joined(separator: ", ")
                    throw error(section, "unknown texture '\(textureName)' (use \(names) or none)")
                }
                texture = .builtin(builtin)
            }
        case (nil, nil):
            break
        default:
            throw error(section, "logo and texture must be strings")
        }

        let textureOpacity = try section.values["texture_opacity"].map { try opacity($0, section) } ?? defaultOpacity
        return Skin(
            name: name, background: background, foreground: foreground,
            accent: accent ?? Skin.defaultAccent(for: background),
            texture: texture, textureOpacity: textureOpacity)
    }

    private static func error(_ section: TOMLSection, _ message: String) -> SkinConfigError {
        SkinConfigError(message: "skins.toml line \(section.line): \(message)")
    }

    private static func checkKeys(_ section: TOMLSection, allowed: Set<String>) throws {
        if let unknown = section.values.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw error(section, "unknown key '\(unknown)'")
        }
    }

    private static func color(_ section: TOMLSection, _ key: String) throws -> RGB? {
        guard let value = section.values[key] else { return nil }
        guard case .string(let text) = value, let rgb = RGB(hex: text) else {
            throw error(section, "\(key) must be a #rrggbb color")
        }
        return rgb
    }

    private static func opacity(_ value: TOMLValue, _ section: TOMLSection) throws -> Double {
        guard case .number(let number) = value, (0...1).contains(number) else {
            throw error(section, "texture_opacity must be a number from 0 to 1")
        }
        return number
    }
}
#endif
```

- [ ] **Step 4: Run to verify pass**

Run: `macos/skins-test.sh SkinModelTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Skins/SkinModel.swift macos/Tests/Skins/SkinModelTests.swift
git commit -m "skins: add skin model and skins.toml validation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Project resolution and automatic skins

**Files:**
- Create: `macos/Sources/Features/Skins/ProjectResolver.swift`, `macos/Sources/Features/Skins/AutoSkin.swift`
- Test: `macos/Tests/Skins/ProjectResolverTests.swift`, `macos/Tests/Skins/AutoSkinTests.swift`

**Interfaces:**
- Consumes: `SkinMatch`, `Skin`, `RGB`, `BuiltinTexture` (Task 5).
- Produces:
  - `enum SkinSource: Hashable { case configured(String), auto(repoName: String), none }`
  - `struct ProjectResolver { var matches: [SkinMatch]; var auto: Bool; var home: String = NSHomeDirectory(); func resolve(pwd: String) -> SkinSource; static func canonical(_ path: String) -> String; static func gitRoot(of dir: String) -> String? }`
  - `enum AutoSkin { static func fnv1a(_ s: String) -> UInt64; static func skin(forRepo name: String, textureOpacity: Double) -> Skin }`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Skins/ProjectResolverTests.swift`:

```swift
import Foundation
import Testing
@testable import Ghostty

struct ProjectResolverTests {
    /// Builds a throwaway tree and returns its canonical root.
    private func makeTree(rootIsGitRepo: Bool = false) throws -> String {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("skins-resolver-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        let root = ProjectResolver.canonical(base)
        for dir in ["projectrepos/arca/app", "projectrepos/arca-labs/site", "projectrepos/Milo/src", "plain/dir"] {
            try FileManager.default.createDirectory(atPath: "\(root)/\(dir)", withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(atPath: "\(root)/projectrepos/arca/.git", withIntermediateDirectories: true)
        // A `.git` *file* (worktrees, submodules) also marks a repo root.
        FileManager.default.createFile(atPath: "\(root)/projectrepos/Milo/.git", contents: Data())
        try FileManager.default.createSymbolicLink(
            atPath: "\(root)/link-to-arca", withDestinationPath: "\(root)/projectrepos/arca")
        if rootIsGitRepo {
            try FileManager.default.createDirectory(atPath: "\(root)/.git", withIntermediateDirectories: true)
        }
        return root
    }

    @Test func configuredMatchWinsAndRespectsComponentBoundaries() throws {
        let root = try makeTree()
        let resolver = ProjectResolver(matches: [
            SkinMatch(path: "\(root)/projectrepos/arca", skin: "arca"),
            SkinMatch(path: "\(root)/projectrepos/arca-labs", skin: "labs"),
        ], auto: true, home: "/nonexistent-home")
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca") == .configured("arca"))
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca/app") == .configured("arca"))
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca-labs/site") == .configured("labs"))
    }

    @Test func longestMatchWins() throws {
        let root = try makeTree()
        let resolver = ProjectResolver(matches: [
            SkinMatch(path: "\(root)/projectrepos", skin: "generic"),
            SkinMatch(path: "\(root)/projectrepos/arca", skin: "arca"),
        ], auto: true, home: "/nonexistent-home")
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca/app") == .configured("arca"))
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/Milo") == .configured("generic"))
    }

    @Test func symlinksDotsAndTrailingSlashes() throws {
        let root = try makeTree()
        let resolver = ProjectResolver(matches: [
            SkinMatch(path: "\(root)/projectrepos/arca", skin: "arca"),
        ], auto: false, home: "/nonexistent-home")
        #expect(resolver.resolve(pwd: "\(root)/link-to-arca/app") == .configured("arca"))
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca/app/../app/") == .configured("arca"))
    }

    @Test func autoSkinsUseTheGitRootName() throws {
        let root = try makeTree()
        let resolver = ProjectResolver(matches: [], auto: true, home: "/nonexistent-home")
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/Milo/src") == .auto(repoName: "Milo"))
        #expect(resolver.resolve(pwd: "\(root)/plain/dir") == .none)
        let noAuto = ProjectResolver(matches: [], auto: false, home: "/nonexistent-home")
        #expect(noAuto.resolve(pwd: "\(root)/projectrepos/Milo/src") == .none)
    }

    @Test func homeGitRootIsIgnored() throws {
        let root = try makeTree(rootIsGitRepo: true)
        let resolver = ProjectResolver(matches: [], auto: true, home: root)
        #expect(resolver.resolve(pwd: "\(root)/plain/dir") == .none)
        #expect(resolver.resolve(pwd: root) == .none)
        #expect(resolver.resolve(pwd: "\(root)/projectrepos/arca/app") == .auto(repoName: "arca"))
    }
}
```

`macos/Tests/Skins/AutoSkinTests.swift`:

```swift
import Testing
@testable import Ghostty

struct AutoSkinTests {
    @Test func deterministicAndCaseInsensitive() {
        let a = AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16)
        #expect(a == AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16))
        #expect(a.background == AutoSkin.skin(forRepo: "milo", textureOpacity: 0.16).background)
        #expect(a.name == "Milo")
        #expect(a.textureOpacity == 0.16)
        if case .builtin = a.texture {} else { Issue.record("auto skins use a built-in texture") }
    }

    @Test func differentReposDiffer() {
        let names = ["Milo", "Tabletake", "fewdy", "songslice", "Grain-app"]
        let backgrounds = Set(names.map { AutoSkin.skin(forRepo: $0, textureOpacity: 0.16).background })
        #expect(backgrounds.count == names.count)
    }

    @Test func backgroundsAreDark() {
        for name in ["Milo", "Tabletake", "fewdy", "songslice", "x"] {
            let bg = AutoSkin.skin(forRepo: name, textureOpacity: 0.16).background
            let luminance = (0.2126 * Double(bg.r) + 0.7152 * Double(bg.g) + 0.0722 * Double(bg.b)) / 255
            #expect(luminance < 0.2, "\(name) background \(bg.hex) is too light")
        }
    }

    @Test func fnvIsStable() {
        #expect(AutoSkin.fnv1a("") == 0xcbf29ce484222325)
        #expect(AutoSkin.fnv1a("a") == 0xaf63dc4c8601ec8c)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `macos/skins-test.sh ProjectResolverTests; macos/skins-test.sh AutoSkinTests`
Expected: both FAIL — `cannot find 'ProjectResolver' / 'AutoSkin' in scope`.

- [ ] **Step 3: Implement `ProjectResolver.swift`**

```swift
#if os(macOS)
import Foundation

enum SkinSource: Hashable {
    case configured(String)
    case auto(repoName: String)
    case none
}

/// Maps a working directory to where its skin comes from.
struct ProjectResolver {
    var matches: [SkinMatch]
    var auto: Bool
    var home: String = NSHomeDirectory()

    func resolve(pwd: String) -> SkinSource {
        let dir = Self.canonical(pwd)
        var best: (skin: String, length: Int)?
        for match in matches {
            let path = Self.canonical(match.path)
            guard dir == path || dir.hasPrefix(path + "/") else { continue }
            if path.count > (best?.length ?? -1) { best = (match.skin, path.count) }
        }
        if let best { return .configured(best.skin) }

        // A home directory under git (dotfiles) is not a project.
        guard auto, let root = Self.gitRoot(of: dir), root != Self.canonical(home) else { return .none }
        return .auto(repoName: (root as NSString).lastPathComponent)
    }

    /// Absolute path with symlinks, `.`, `..` and trailing slashes resolved.
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Nearest ancestor (including `dir`) containing a `.git` file or directory.
    static func gitRoot(of dir: String) -> String? {
        var current = dir
        while true {
            if FileManager.default.fileExists(atPath: current + "/.git") { return current }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { return nil }
            current = parent
        }
    }
}
#endif
```

- [ ] **Step 4: Implement `AutoSkin.swift`**

```swift
#if os(macOS)
import Foundation

/// Deterministic skins for git repos that skins.toml does not mention.
enum AutoSkin {
    /// 64-bit FNV-1a. Stable across launches, unlike `hashValue`.
    static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    static func skin(forRepo name: String, textureOpacity: Double) -> Skin {
        let hash = fnv1a(name.lowercased())
        let hue = Double(hash % 360)
        let textures = BuiltinTexture.allCases
        return Skin(
            name: name,
            background: .hsl(hue, 0.35, 0.13),
            foreground: nil,
            accent: .hsl(hue, 0.55, 0.62),
            texture: .builtin(textures[Int((hash >> 16) % UInt64(textures.count))]),
            textureOpacity: textureOpacity)
    }
}
#endif
```

- [ ] **Step 5: Run to verify pass**

Run: `macos/skins-test.sh ProjectResolverTests && macos/skins-test.sh AutoSkinTests`
Expected: both `** TEST SUCCEEDED **`. If `differentReposDiffer` fails because two sample names collide on hue, that is a real (if unlucky) collision: change the hue source to `Double((hash >> 8) % 360)` and re-run; do not change the test names.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Skins/ProjectResolver.swift macos/Sources/Features/Skins/AutoSkin.swift macos/Tests/Skins/ProjectResolverTests.swift macos/Tests/Skins/AutoSkinTests.swift
git commit -m "skins: resolve pwd to configured, automatic, or no skin

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Skin request protocol (decode + validate)

**Files:**
- Create: `macos/Sources/Features/Skins/SkinRequest.swift`
- Test: `macos/Tests/Skins/SkinRequestTests.swift`

**Interfaces:**
- Consumes: `RGB`, `SkinNames` (Task 5).
- Produces:
  - `enum SkinsConstants { static let surfaceEnvKey = "GHOSTTY_SKINS_SURFACE"; static let userVarName = "GHOSTTY_SKIN"; static let maxPayloadBytes = 4096 }`
  - `enum SkinOp: String { case preview, set, cancel, reset }`
  - `struct SkinRequest: Equatable { var op: SkinOp; var skin: String?; var background: RGB?; var texture: String?; var opacity: Double?; static func decode(_ json: String) -> SkinRequest? }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import Ghostty

struct SkinRequestTests {
    @Test func decodesValidRequests() {
        #expect(SkinRequest.decode(#"{"v":1,"op":"preview","skin":"arca"}"#)
            == SkinRequest(op: .preview, skin: "arca"))
        #expect(SkinRequest.decode(#"{"v":1,"op":"set","background":"#3A0F14","texture":"grid","opacity":0.25}"#)
            == SkinRequest(op: .set, background: RGB(hex: "#3a0f14"), texture: "grid", opacity: 0.25))
        #expect(SkinRequest.decode(#"{"v":1,"op":"reset"}"#) == SkinRequest(op: .reset))
        #expect(SkinRequest.decode(#"{"v":1,"op":"cancel","future":"field"}"#) == SkinRequest(op: .cancel))
    }

    @Test(arguments: [
        #"{"v":2,"op":"set"}"#,
        #"{"op":"set"}"#,
        #"{"v":1,"op":"delete"}"#,
        #"{"v":1,"op":"set","texture":"../../etc/passwd"}"#,
        #"{"v":1,"op":"set","texture":"/tmp/x.png"}"#,
        #"{"v":1,"op":"set","skin":"a/b"}"#,
        #"{"v":1,"op":"set","background":"red"}"#,
        #"{"v":1,"op":"set","opacity":1.5}"#,
        #"{"v":1,"op":"set","opacity":-0.1}"#,
        "not json",
        "",
    ])
    func rejects(_ json: String) {
        #expect(SkinRequest.decode(json) == nil)
    }

    @Test func rejectsOversizedPayloads() {
        let padding = String(repeating: " ", count: SkinsConstants.maxPayloadBytes)
        #expect(SkinRequest.decode(#"{"v":1,"op":"reset"}"# + padding) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `macos/skins-test.sh SkinRequestTests`
Expected: FAIL — `cannot find 'SkinRequest' in scope`.

- [ ] **Step 3: Implement `SkinRequest.swift`**

```swift
#if os(macOS)
import Foundation

enum SkinsConstants {
    /// Environment variable holding the pane's UUID (set on every new surface).
    static let surfaceEnvKey = "GHOSTTY_SKINS_SURFACE"
    /// OSC 1337 SetUserVar name carrying skin requests.
    static let userVarName = "GHOSTTY_SKIN"
    static let maxPayloadBytes = 4096
}

enum SkinOp: String {
    case preview, set, cancel, reset
}

/// A request from a program in the pane (normally the `skins` CLI). It can
/// only name skins/textures and give colors and opacity, never file paths.
struct SkinRequest: Equatable {
    var op: SkinOp
    var skin: String?
    var background: RGB?
    var texture: String?
    var opacity: Double?

    /// Returns nil for anything malformed, oversized, or path-like.
    /// Unknown JSON fields are ignored for forward compatibility.
    static func decode(_ json: String) -> SkinRequest? {
        guard json.utf8.count <= SkinsConstants.maxPayloadBytes,
              let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(Raw.self, from: data),
              raw.v == 1,
              let op = SkinOp(rawValue: raw.op) else { return nil }

        var request = SkinRequest(op: op)
        if let skin = raw.skin {
            guard SkinNames.isValid(skin) else { return nil }
            request.skin = skin
        }
        if let background = raw.background {
            guard let rgb = RGB(hex: background) else { return nil }
            request.background = rgb
        }
        if let texture = raw.texture {
            guard SkinNames.isValid(texture) else { return nil }
            request.texture = texture
        }
        if let opacity = raw.opacity {
            guard (0...1).contains(opacity) else { return nil }
            request.opacity = opacity
        }
        return request
    }

    private struct Raw: Decodable {
        let v: Int
        let op: String
        let skin: String?
        let background: String?
        let texture: String?
        let opacity: Double?
    }
}
#endif
```

- [ ] **Step 4: Run to verify pass**

Run: `macos/skins-test.sh SkinRequestTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Skins/SkinRequest.swift macos/Tests/Skins/SkinRequestTests.swift
git commit -m "skins: decode and validate GHOSTTY_SKIN requests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Texture tiles

**Files:**
- Create: `macos/Sources/Features/Skins/TextureStore.swift`
- Test: `macos/Tests/Skins/TextureStoreTests.swift`

**Interfaces:**
- Consumes: `Skin`, `SkinTexture`, `BuiltinTexture`, `RGB` (Task 5), `AutoSkin.fnv1a` (Task 6).
- Produces: `final class TextureStore { static let tileSize = 220; init(cacheDir: URL); func tileURL(for skin: Skin) throws -> URL?; static func renderBuiltin(_: BuiltinTexture, accent: RGB) throws -> CGImage; static func renderLogoTile(path: String, accent: RGB) throws -> CGImage; static func logoMask(_ image: CGImage) -> [UInt8]; static func makeContext(width: Int, height: Int) throws -> CGContext }`; `enum TextureError: Error, Equatable { case render(String), unreadableLogo(String) }`. `tileURL` returns nil for `.none`, caches by content key, and throws when a logo can't be read.

- [ ] **Step 1: Write the failing tests**

```swift
import AppKit
import Foundation
import ImageIO
import Testing
@testable import Ghostty

struct TextureStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("skins-tex-\(UUID().uuidString)")
    }

    private func skin(_ texture: SkinTexture, accent: String = "#46a2ff") -> Skin {
        Skin(name: "t", background: RGB(hex: "#12222b")!, foreground: nil,
             accent: RGB(hex: accent)!, texture: texture, textureOpacity: 0.16)
    }

    private func loadImage(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func paintedPixels(_ image: CGImage) -> Int {
        TextureStore.logoMask(image).filter { $0 > 0 }.count
    }

    @Test func noneHasNoTile() throws {
        #expect(try TextureStore(cacheDir: tempDir()).tileURL(for: skin(.none)) == nil)
    }

    @Test(arguments: BuiltinTexture.allCases)
    func builtinTilesRender(_ texture: BuiltinTexture) throws {
        let url = try #require(try TextureStore(cacheDir: tempDir()).tileURL(for: skin(.builtin(texture))))
        let image = try loadImage(url)
        #expect(image.width == TextureStore.tileSize)
        #expect(image.height == TextureStore.tileSize)
        #expect(paintedPixels(image) > 100)
    }

    @Test func tilesAreCachedPerAccent() throws {
        let store = TextureStore(cacheDir: tempDir())
        let first = try store.tileURL(for: skin(.builtin(.grid)))
        let modified = try FileManager.default.attributesOfItem(atPath: first!.path)[.modificationDate] as? Date
        let again = try store.tileURL(for: skin(.builtin(.grid)))
        #expect(first == again)
        #expect(try FileManager.default.attributesOfItem(atPath: again!.path)[.modificationDate] as? Date == modified)
        #expect(try store.tileURL(for: skin(.builtin(.grid), accent: "#ff0000")) != first)
    }

    @Test func maskIgnoresAnOpaqueBackground() throws {
        let ctx = try TextureStore.makeContext(width: 64, height: 64)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 24, y: 24, width: 16, height: 16))
        let mask = TextureStore.logoMask(try #require(ctx.makeImage()))
        #expect(mask[0] == 0)
        #expect(mask[32 * 64 + 32] == 255)
    }

    @Test func maskUsesAlphaForTransparentLogos() throws {
        let ctx = try TextureStore.makeContext(width: 64, height: 64)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 24, y: 24, width: 16, height: 16))
        let mask = TextureStore.logoMask(try #require(ctx.makeImage()))
        #expect(mask[0] == 0)
        #expect(mask[32 * 64 + 32] == 255)
    }

    @Test func svgLogoTileRenders() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let svg = dir.appendingPathComponent("logo.svg")
        try #"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" fill="#ffffff"/><circle cx="16" cy="16" r="8" fill="none" stroke="#12222b" stroke-width="3"/></svg>"#
            .write(to: svg, atomically: true, encoding: .utf8)
        let url = try #require(try TextureStore(cacheDir: dir.appendingPathComponent("cache"))
            .tileURL(for: skin(.logo(path: svg.path))))
        let image = try loadImage(url)
        let painted = paintedPixels(image)
        #expect(painted > 50)
        // The white square background must not be tinted (it would paint ~2*57*57 pixels).
        #expect(painted < 2 * 57 * 57 / 2)
    }

    @Test func unreadableLogoThrows() {
        #expect(throws: TextureError.self) {
            try TextureStore(cacheDir: tempDir()).tileURL(for: skin(.logo(path: "/nonexistent/logo.svg")))
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `macos/skins-test.sh TextureStoreTests`
Expected: FAIL — `cannot find 'TextureStore' in scope`.

- [ ] **Step 3: Implement `TextureStore.swift`**

```swift
#if os(macOS)
import AppKit
import Foundation
import ImageIO

enum TextureError: Error, Equatable {
    case render(String)
    case unreadableLogo(String)
}

/// Renders and caches 220×220 device-pixel tiles. Ghostty draws
/// `background-image-fit = none` at one image pixel per device pixel.
final class TextureStore {
    static let tileSize = 220
    static let logoSize = 57
    /// Staggered logo placement within a tile (matches the spike's look).
    static let logoOrigins = [CGPoint(x: 30, y: 30), CGPoint(x: 140, y: 135)]

    let cacheDir: URL

    init(cacheDir: URL) {
        self.cacheDir = cacheDir
    }

    func tileURL(for skin: Skin) throws -> URL? {
        let key: String
        let render: () throws -> CGImage
        switch skin.texture {
        case .none:
            return nil
        case .builtin(let texture):
            key = "b-\(texture.rawValue)-\(skin.accent.hex.dropFirst())"
            render = { try Self.renderBuiltin(texture, accent: skin.accent) }
        case .logo(let path):
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
                throw TextureError.unreadableLogo(path)
            }
            let mtime = Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
            key = "l-\(String(AutoSkin.fnv1a(path), radix: 16))-\(mtime)-\(skin.accent.hex.dropFirst())"
            render = { try Self.renderLogoTile(path: path, accent: skin.accent) }
        }

        let url = cacheDir.appendingPathComponent("v1-\(key).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let image = try render()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Self.writePNG(image, to: url)
        return url
    }

    static func makeContext(width: Int, height: Int) throws -> CGContext {
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw TextureError.render("could not create bitmap context")
        }
        return ctx
    }

    static func cgColor(_ color: RGB, alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                blue: CGFloat(color.b) / 255, alpha: alpha)
    }

    static func renderBuiltin(_ texture: BuiltinTexture, accent: RGB) throws -> CGImage {
        let size = CGFloat(tileSize)
        let ctx = try makeContext(width: tileSize, height: tileSize)
        // 8 cells per tile keeps every pattern seamless.
        let step = size / 8
        ctx.setStrokeColor(cgColor(accent))
        ctx.setFillColor(cgColor(accent))
        ctx.setLineWidth(1.5)
        func center(_ i: Int, _ j: Int) -> CGPoint {
            CGPoint(x: (CGFloat(i) + 0.5) * step, y: (CGFloat(j) + 0.5) * step)
        }

        switch texture {
        case .dots:
            for i in 0..<8 {
                for j in 0..<8 {
                    let c = center(i, j)
                    ctx.fillEllipse(in: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5))
                }
            }
        case .grid:
            for i in 0..<8 {
                let p = CGFloat(i) * step + 0.75
                ctx.move(to: CGPoint(x: p, y: 0))
                ctx.addLine(to: CGPoint(x: p, y: size))
                ctx.move(to: CGPoint(x: 0, y: p))
                ctx.addLine(to: CGPoint(x: size, y: p))
            }
            ctx.strokePath()
        case .diagonal:
            for k in -8...8 {
                let offset = CGFloat(k) * step
                ctx.move(to: CGPoint(x: offset, y: 0))
                ctx.addLine(to: CGPoint(x: offset + size, y: size))
            }
            ctx.strokePath()
        case .cross:
            for i in 0..<8 {
                for j in 0..<8 {
                    let c = center(i, j)
                    ctx.move(to: CGPoint(x: c.x - 4, y: c.y))
                    ctx.addLine(to: CGPoint(x: c.x + 4, y: c.y))
                    ctx.move(to: CGPoint(x: c.x, y: c.y - 4))
                    ctx.addLine(to: CGPoint(x: c.x, y: c.y + 4))
                }
            }
            ctx.strokePath()
        case .waves:
            for j in 0..<8 {
                let y0 = (CGFloat(j) + 0.5) * step
                ctx.move(to: CGPoint(x: 0, y: y0))
                for x in stride(from: CGFloat(0), through: size, by: 2) {
                    ctx.addLine(to: CGPoint(x: x, y: y0 + 4 * sin(x / size * 8 * .pi)))
                }
            }
            ctx.strokePath()
        case .noise:
            var seed: UInt64 = 42
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
            }
            for _ in 0..<700 {
                ctx.setFillColor(cgColor(accent, alpha: 0.3 + 0.7 * next()))
                ctx.fill(CGRect(x: next() * size, y: next() * size, width: 1.5, height: 1.5))
            }
        }

        guard let image = ctx.makeImage() else { throw TextureError.render("makeImage failed") }
        return image
    }

    static func renderLogoTile(path: String, accent: RGB) throws -> CGImage {
        guard let logo = NSImage(contentsOfFile: path), logo.size.width > 0, logo.size.height > 0 else {
            throw TextureError.unreadableLogo(path)
        }
        let n = logoSize
        let logoCtx = try makeContext(width: n, height: n)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: logoCtx, flipped: false)
        logo.draw(in: NSRect(x: 0, y: 0, width: n, height: n))
        NSGraphicsContext.restoreGraphicsState()
        guard let logoImage = logoCtx.makeImage() else { throw TextureError.render("logo render failed") }

        let tinted = try tintedImage(mask: logoMask(logoImage), width: n, height: n, color: accent)
        let tile = try makeContext(width: tileSize, height: tileSize)
        for origin in logoOrigins {
            tile.draw(tinted, in: CGRect(origin: origin, size: CGSize(width: n, height: n)))
        }
        guard let image = tile.makeImage() else { throw TextureError.render("tile render failed") }
        return image
    }

    /// Row-major alpha mask (0–255) of the logo's shape. If the image has an
    /// opaque background (top-left pixel alpha ≥ 230), the shape is the pixels
    /// whose color differs from that corner; otherwise it is the alpha channel.
    static func logoMask(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let corner = Array(pixels[0..<4])
        let opaqueBackground = corner[3] >= 230
        var mask = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let alpha = pixels[i * 4 + 3]
            guard opaqueBackground else {
                mask[i] = alpha
                continue
            }
            let difference = (0..<3).map { abs(Int(pixels[i * 4 + $0]) - Int(corner[$0])) }.max() ?? 0
            let strength = min(1, Double(difference) / 255 / 0.35)
            mask[i] = UInt8((strength * Double(alpha)).rounded())
        }
        return mask
    }

    private static func tintedImage(mask: [UInt8], width: Int, height: Int, color: RGB) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let alpha = UInt16(mask[i])
            pixels[i * 4] = UInt8(UInt16(color.r) * alpha / 255)
            pixels[i * 4 + 1] = UInt8(UInt16(color.g) * alpha / 255)
            pixels[i * 4 + 2] = UInt8(UInt16(color.b) * alpha / 255)
            pixels[i * 4 + 3] = mask[i]
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw TextureError.render("tint failed")
        }
        return image
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw TextureError.render("could not create \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TextureError.render("could not write \(url.path)")
        }
    }
}
#endif
```

- [ ] **Step 4: Run to verify pass**

Run: `macos/skins-test.sh TextureStoreTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Check the real Arca logo renders**

Add this temporary test to `TextureStoreTests`, run it, look at the PNG, then delete the test before committing:

```swift
@Test func arcaLogoPreview() throws {
    let url = try TextureStore(cacheDir: URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/ghostty-skins/check"))
        .tileURL(for: Skin(name: "arca", background: RGB(hex: "#12222b")!, foreground: nil,
                           accent: RGB(hex: "#46a2ff")!,
                           texture: .logo(path: NSHomeDirectory() + "/projectrepos/arca-labs/website/assets/favicon.svg"),
                           textureOpacity: 0.16))
    print("ARCA TILE:", url!.path)
}
```

Run: `macos/skins-test.sh TextureStoreTests && grep -o "ARCA TILE: .*" macos/build/last-test.log`, then open that PNG with the Read tool. Expected: two blue Arca marks on transparency, no filled squares. Remove the temporary test (and delete `~/Library/Caches/ghostty-skins/check`).

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Skins/TextureStore.swift macos/Tests/Skins/TextureStoreTests.swift
git commit -m "skins: render and cache built-in and logo texture tiles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: SkinManager (layers, apply decisions, catalog)

**Files:**
- Create: `macos/Sources/Features/Skins/SkinManager.swift`
- Test: `macos/Tests/Skins/SkinManagerTests.swift`

**Interfaces:**
- Consumes: `SkinConfig`, `Skin`, `SkinSource`, `ProjectResolver`, `AutoSkin`, `SkinRequest`, `SkinsConstants`, `TextureStore`, `BuiltinTexture`.
- Produces:
  - `struct AppliedSkin: Hashable { var skin: Skin; var tile: URL? }`
  - `@MainActor final class SkinManager: ObservableObject` with `typealias Applier = @MainActor (UUID, AppliedSkin?) -> Bool` (false = surface gone), `static let previewTimeout: TimeInterval = 60`, `@Published private(set) var config: SkinConfig`, `@Published private(set) var configError: String?`, `@Published private(set) var panes: [UUID: Pane]` (`Pane.override`, `Pane.preview`), and methods `init(config:textures:catalogURL:home:now:apply:)`, `updateConfig(_:error:)`, `pwdChanged(_:pwd:)`, `handleUserVar(_:name:value:)`, `handle(_:for:)`, `setPreview(_:_:)`, `setOverride(_:_:)`, `reset(_:)`, `expirePreviews()`, `reapplyAll()`, `effectiveSkin(_:) -> Skin?`, `sourceLabel(_:) -> String`, `tileURL(for:) -> URL?`, `writeCatalog()`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SkinManagerTests {
    final class Harness {
        var calls: [(UUID, AppliedSkin?)] = []
        var alive = true
        var clock = Date(timeIntervalSince1970: 1_000_000)
    }

    let root: String
    let arca: Skin
    let prod: Skin
    let config: SkinConfig

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("skins-mgr-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: "\(base)/arca/app", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(base)/Milo/.git", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(base)/plain", withIntermediateDirectories: true)
        root = ProjectResolver.canonical(base)
        arca = Skin(name: "arca", background: RGB(hex: "#12222b")!, foreground: nil,
                    accent: RGB(hex: "#46a2ff")!, texture: .builtin(.dots), textureOpacity: 0.16)
        prod = Skin(name: "prod", background: RGB(hex: "#3a0f14")!, foreground: nil,
                    accent: Skin.defaultAccent(for: RGB(hex: "#3a0f14")!), texture: .builtin(.diagonal), textureOpacity: 0.16)
        var config = SkinConfig()
        config.skins = ["arca": arca, "prod": prod]
        config.matches = [SkinMatch(path: "\(root)/arca", skin: "arca")]
        self.config = config
    }

    func makeManager(_ harness: Harness, catalog: URL? = nil) -> SkinManager {
        SkinManager(
            config: config,
            textures: TextureStore(cacheDir: URL(fileURLWithPath: root).appendingPathComponent("cache")),
            catalogURL: catalog,
            home: "/nonexistent-home",
            now: { harness.clock },
            apply: { id, applied in
                harness.calls.append((id, applied))
                return harness.alive
            })
    }

    @Test func appliesConfiguredSkinOnceAndRevertsOnLeave() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca/app")
        #expect(h.calls.count == 1)
        #expect(h.calls.last?.1?.skin == arca)
        #expect(h.calls.last?.1?.tile != nil)
        m.pwdChanged(id, pwd: "\(root)/arca")
        #expect(h.calls.count == 1)
        m.pwdChanged(id, pwd: "\(root)/plain")
        #expect(h.calls.count == 2)
        #expect(h.calls.last?.1 == nil)
    }

    @Test func unskinnedPaneIsNeverTouched() {
        let h = Harness(); let m = makeManager(h)
        m.pwdChanged(UUID(), pwd: "\(root)/plain")
        #expect(h.calls.isEmpty)
    }

    @Test func autoSkinForUnlistedRepo() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        #expect(h.calls.last?.1?.skin == AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16))
        #expect(m.sourceLabel(id) == "Auto: Milo")
    }

    @Test func overridePersistsAcrossCdUntilReset() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        m.handleUserVar(id, name: SkinsConstants.userVarName, value: #"{"v":1,"op":"set","skin":"prod"}"#)
        #expect(m.effectiveSkin(id) == prod)
        m.pwdChanged(id, pwd: "\(root)/plain")
        #expect(m.effectiveSkin(id) == prod)
        #expect(m.sourceLabel(id) == "Override")
        m.handleUserVar(id, name: SkinsConstants.userVarName, value: #"{"v":1,"op":"reset"}"#)
        #expect(m.effectiveSkin(id) == nil)
        #expect(h.calls.last?.1 == nil)
    }

    @Test func previewAndCancel() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        m.handle(SkinRequest(op: .preview, skin: "prod"), for: id)
        #expect(m.effectiveSkin(id) == prod)
        // A second preview replaces the first rather than stacking on it.
        m.handle(SkinRequest(op: .preview, texture: "grid"), for: id)
        #expect(m.effectiveSkin(id)?.background == arca.background)
        #expect(m.effectiveSkin(id)?.texture == .builtin(.grid))
        m.handle(SkinRequest(op: .cancel), for: id)
        #expect(m.effectiveSkin(id) == arca)
    }

    @Test func previewExpires() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        m.handle(SkinRequest(op: .preview, skin: "prod"), for: id)
        h.clock += 59
        m.expirePreviews()
        #expect(m.effectiveSkin(id) == prod)
        h.clock += 2
        m.expirePreviews()
        #expect(m.effectiveSkin(id) == arca)
        #expect(h.calls.last?.1?.skin == arca)
    }

    @Test func rejectsUnknownNames() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        let before = h.calls.count
        m.handle(SkinRequest(op: .set, skin: "missing"), for: id)
        m.handle(SkinRequest(op: .set, texture: "missing"), for: id)
        m.handleUserVar(id, name: "OTHER_VAR", value: #"{"v":1,"op":"set","skin":"prod"}"#)
        m.handleUserVar(id, name: SkinsConstants.userVarName, value: "garbage")
        #expect(h.calls.count == before)
        #expect(m.effectiveSkin(id) == arca)
    }

    @Test func colorOverrideRecomputesBuiltinAccent() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        let red = RGB(hex: "#400000")!
        m.handle(SkinRequest(op: .set, background: red), for: id)
        #expect(m.effectiveSkin(id)?.background == red)
        #expect(m.effectiveSkin(id)?.accent == Skin.defaultAccent(for: red))
        #expect(m.effectiveSkin(id)?.name == "custom")
    }

    @Test func goneSurfacesAreDropped() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        h.alive = false
        m.pwdChanged(id, pwd: "\(root)/arca")
        #expect(m.panes[id] == nil)
    }

    @Test func configChangesReResolvePanes() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        var next = config
        next.matches = []
        next.auto = false
        m.updateConfig(next, error: nil)
        #expect(m.effectiveSkin(id) == nil)
        #expect(h.calls.last?.1 == nil)
        m.updateConfig(next, error: "skins.toml line 3: boom")
        #expect(m.configError == "skins.toml line 3: boom")
    }

    @Test func reapplyAllForcesSkinnedPanesOnly() {
        let h = Harness(); let m = makeManager(h)
        let skinned = UUID(), plain = UUID()
        m.pwdChanged(skinned, pwd: "\(root)/arca")
        m.pwdChanged(plain, pwd: "\(root)/plain")
        h.calls.removeAll()
        m.reapplyAll()
        #expect(h.calls.map(\.0) == [skinned])
    }

    @Test func writesCatalog() throws {
        let h = Harness()
        let url = URL(fileURLWithPath: root).appendingPathComponent("state/catalog.json")
        let m = makeManager(h, catalog: url); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        m.handle(SkinRequest(op: .set, skin: "prod"), for: id)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let skins = object?["skins"] as? [[String: String]]
        #expect(skins?.map { $0["name"] } == ["arca", "prod"])
        #expect((object?["textures"] as? [String]) == BuiltinTexture.allCases.map(\.rawValue))
        let pane = (object?["panes"] as? [String: [String: String]])?[id.uuidString]
        #expect(pane == ["skin": "prod", "source": "override", "background": "#3a0f14"])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `macos/skins-test.sh SkinManagerTests`
Expected: FAIL — `cannot find 'SkinManager' in scope`.

- [ ] **Step 3: Implement `SkinManager.swift`**

```swift
#if os(macOS)
import Combine
import Foundation

struct AppliedSkin: Hashable {
    var skin: Skin
    var tile: URL?
}

/// Owns every pane's skin state; the only component that changes how panes look.
/// Layers, first non-nil wins: preview (transient) → override (sticky) → auto.
@MainActor
final class SkinManager: ObservableObject {
    struct Pane: Equatable {
        var pwd: String?
        var source: SkinSource = .none
        var override: Skin?
        var preview: Skin?
        var previewUpdatedAt: Date?
        /// nil = never applied; `.some(nil)` = the user's normal look is applied.
        var lastApplied: AppliedSkin??
    }

    /// Applies a look to a surface. Returns false when the surface no longer exists.
    typealias Applier = @MainActor (UUID, AppliedSkin?) -> Bool

    static let previewTimeout: TimeInterval = 60

    @Published private(set) var config: SkinConfig
    @Published private(set) var configError: String?
    @Published private(set) var panes: [UUID: Pane] = [:]

    private let textures: TextureStore
    private let catalogURL: URL?
    private let home: String
    private let now: () -> Date
    private let apply: Applier
    private var resolver: ProjectResolver

    init(
        config: SkinConfig,
        textures: TextureStore,
        catalogURL: URL?,
        home: String = NSHomeDirectory(),
        now: @escaping () -> Date = Date.init,
        apply: @escaping Applier
    ) {
        self.config = config
        self.textures = textures
        self.catalogURL = catalogURL
        self.home = home
        self.now = now
        self.apply = apply
        self.resolver = ProjectResolver(matches: config.matches, auto: config.auto, home: home)
    }

    // MARK: Inputs

    func updateConfig(_ config: SkinConfig, error: String?) {
        configError = error
        if config != self.config {
            self.config = config
            resolver = ProjectResolver(matches: config.matches, auto: config.auto, home: home)
            for (id, pane) in panes {
                if let pwd = pane.pwd { panes[id]?.source = resolver.resolve(pwd: pwd) }
                applyIfNeeded(id)
            }
        }
        writeCatalog()
    }

    func pwdChanged(_ id: UUID, pwd: String) {
        var pane = panes[id] ?? Pane()
        pane.pwd = pwd
        pane.source = resolver.resolve(pwd: pwd)
        panes[id] = pane
        applyIfNeeded(id)
        writeCatalog()
    }

    func handleUserVar(_ id: UUID, name: String, value: String) {
        guard name == SkinsConstants.userVarName, let request = SkinRequest.decode(value) else { return }
        handle(request, for: id)
    }

    func handle(_ request: SkinRequest, for id: UUID) {
        var pane = panes[id] ?? Pane()
        switch request.op {
        case .cancel:
            pane.preview = nil
            pane.previewUpdatedAt = nil
        case .reset:
            pane.preview = nil
            pane.previewUpdatedAt = nil
            pane.override = nil
        case .preview:
            guard let skin = skin(from: request, base: pane.override ?? autoSkin(for: pane.source)) else { return }
            pane.preview = skin
            pane.previewUpdatedAt = now()
        case .set:
            guard let skin = skin(from: request, base: pane.override ?? autoSkin(for: pane.source)) else { return }
            pane.override = skin
            pane.preview = nil
            pane.previewUpdatedAt = nil
        }
        panes[id] = pane
        applyIfNeeded(id)
        writeCatalog()
    }

    /// UI entry points (the popover builds `Skin` values directly).
    func setPreview(_ id: UUID, _ skin: Skin?) {
        var pane = panes[id] ?? Pane()
        pane.preview = skin
        pane.previewUpdatedAt = skin == nil ? nil : now()
        panes[id] = pane
        applyIfNeeded(id)
    }

    func setOverride(_ id: UUID, _ skin: Skin?) {
        var pane = panes[id] ?? Pane()
        pane.override = skin
        pane.preview = nil
        pane.previewUpdatedAt = nil
        panes[id] = pane
        applyIfNeeded(id)
        writeCatalog()
    }

    func reset(_ id: UUID) {
        handle(SkinRequest(op: .reset), for: id)
    }

    func expirePreviews() {
        let cutoff = now().addingTimeInterval(-Self.previewTimeout)
        for (id, pane) in panes where pane.preview != nil && (pane.previewUpdatedAt ?? .distantPast) < cutoff {
            panes[id]?.preview = nil
            panes[id]?.previewUpdatedAt = nil
            applyIfNeeded(id)
        }
    }

    /// Re-applies every skinned pane, e.g. after Ghostty reloaded its config
    /// and replaced each surface's config with the global one.
    func reapplyAll() {
        for id in panes.keys.sorted(by: { $0.uuidString < $1.uuidString }) where effectiveSkin(id) != nil {
            applyIfNeeded(id, force: true)
        }
    }

    // MARK: Queries

    func effectiveSkin(_ id: UUID) -> Skin? {
        guard let pane = panes[id] else { return nil }
        return pane.preview ?? pane.override ?? autoSkin(for: pane.source)
    }

    func sourceLabel(_ id: UUID) -> String {
        guard let pane = panes[id] else { return "Default" }
        if pane.preview != nil { return "Preview" }
        if pane.override != nil { return "Override" }
        switch pane.source {
        case .configured(let name): return "Config: \(name)"
        case .auto(let repo): return "Auto: \(repo)"
        case .none: return "Default"
        }
    }

    func tileURL(for skin: Skin) -> URL? {
        do {
            return try textures.tileURL(for: skin)
        } catch {
            Ghostty.logger.warning("skins: texture for \(skin.name) failed: \(String(describing: error))")
            return nil
        }
    }

    // MARK: Internals

    private func autoSkin(for source: SkinSource) -> Skin? {
        switch source {
        case .configured(let name): return config.skins[name]
        case .auto(let repo): return AutoSkin.skin(forRepo: repo, textureOpacity: config.textureOpacity)
        case .none: return nil
        }
    }

    /// Builds the skin a request asks for, or nil if it names something unknown.
    private func skin(from request: SkinRequest, base: Skin?) -> Skin? {
        var skin: Skin
        if let name = request.skin {
            guard let named = config.skins[name] else { return nil }
            skin = named
        } else {
            skin = base ?? Skin.fallback
            if base == nil { skin.textureOpacity = config.textureOpacity }
            skin.name = "custom"
        }
        if let background = request.background {
            skin.background = background
            if case .builtin = skin.texture { skin.accent = Skin.defaultAccent(for: background) }
        }
        if let texture = request.texture {
            if texture == "none" {
                skin.texture = .none
            } else if let builtin = BuiltinTexture(rawValue: texture) {
                skin.texture = .builtin(builtin)
                skin.accent = Skin.defaultAccent(for: skin.background)
            } else if let named = config.skins[texture], named.texture != .none {
                skin.texture = named.texture
                skin.accent = named.accent
            } else {
                return nil
            }
        }
        if let opacity = request.opacity { skin.textureOpacity = opacity }
        return skin
    }

    private func applyIfNeeded(_ id: UUID, force: Bool = false) {
        guard var pane = panes[id] else { return }
        let target = effectiveSkin(id).map { AppliedSkin(skin: $0, tile: tileURL(for: $0)) }
        if !force, let last = pane.lastApplied, last == target { return }
        if pane.lastApplied == nil, target == nil {
            // Never skinned and nothing to show: leave the surface alone.
            pane.lastApplied = .some(nil)
            panes[id] = pane
            return
        }
        if apply(id, target) {
            pane.lastApplied = .some(target)
            panes[id] = pane
        } else {
            panes[id] = nil
        }
    }

    private func sourceKind(_ id: UUID) -> String {
        guard let pane = panes[id] else { return "none" }
        if pane.preview != nil { return "preview" }
        if pane.override != nil { return "override" }
        switch pane.source {
        case .configured: return "config"
        case .auto: return "auto"
        case .none: return "none"
        }
    }

    private struct Catalog: Encodable {
        struct SkinEntry: Encodable {
            let name: String
            let background: String
            let texture: String
        }
        struct PaneEntry: Encodable {
            let skin: String
            let source: String
            let background: String
        }
        let version: Int
        let skins: [SkinEntry]
        let textures: [String]
        let panes: [String: PaneEntry]
    }

    /// Writes catalog.json for the `skins` CLI (skins, textures, each pane's skin).
    func writeCatalog() {
        guard let catalogURL else { return }
        let skins = config.skins.values.sorted { $0.name < $1.name }.map {
            Catalog.SkinEntry(name: $0.name, background: $0.background.hex, texture: Self.textureName($0.texture))
        }
        var paneEntries: [String: Catalog.PaneEntry] = [:]
        for id in panes.keys {
            guard let skin = effectiveSkin(id) else { continue }
            paneEntries[id.uuidString] = .init(skin: skin.name, source: sourceKind(id), background: skin.background.hex)
        }
        let catalog = Catalog(
            version: 1, skins: skins,
            textures: BuiltinTexture.allCases.map(\.rawValue), panes: paneEntries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(catalog).write(to: catalogURL, options: .atomic)
        } catch {
            Ghostty.logger.warning("skins: failed to write catalog: \(String(describing: error))")
        }
    }

    private static func textureName(_ texture: SkinTexture) -> String {
        switch texture {
        case .none: return "none"
        case .builtin(let builtin): return builtin.rawValue
        case .logo: return "logo"
        }
    }
}
#endif
```

- [ ] **Step 4: Run to verify pass**

Run: `macos/skins-test.sh SkinManagerTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Skins/SkinManager.swift macos/Tests/Skins/SkinManagerTests.swift
git commit -m "skins: add SkinManager with preview/override/auto layers and catalog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Config store, overlay, and wiring into Ghostty

**Files:**
- Create: `macos/Sources/Features/Skins/SkinConfigStore.swift`, `macos/Sources/Features/Skins/SkinsRuntime.swift`
- Modify: `macos/Sources/Ghostty/Ghostty.App.swift` (action switch ~line 548, `pwdChanged` ~line 1715, `configChange` app branch ~line 2170)
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (~line 393)
- Test: `macos/Tests/Skins/SkinConfigStoreTests.swift`, `macos/Tests/Skins/SkinOverlayTests.swift`

**Interfaces:**
- Consumes: everything above; C API `GHOSTTY_ACTION_SET_USER_VAR` (Task 3); `GhosttyAppDelegate.findSurface(forUUID:)`.
- Produces:
  - `final class SkinConfigStore { init(fileURL: URL, home: String = NSHomeDirectory()); private(set) var config: SkinConfig; private(set) var error: String?; var onChange: (() -> Void)?; func reload(); func startWatching() }`
  - `enum SkinOverlay { static func configText(for: AppliedSkin) -> String }`
  - `@MainActor final class SkinsRuntime { static let shared; let manager: SkinManager; func pwdChanged(_ view: Ghostty.SurfaceView, pwd: String); func userVarChanged(_ view: Ghostty.SurfaceView, name: String, value: String); func ghosttyConfigReloaded() }`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Skins/SkinConfigStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Ghostty

struct SkinConfigStoreTests {
    private func makeStore() throws -> (SkinConfigStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skins-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("skins.toml")
        return (SkinConfigStore(fileURL: file, home: "/h"), file)
    }

    @Test func missingFileIsEmptyConfig() throws {
        let (store, _) = try makeStore()
        store.reload()
        #expect(store.config == .empty)
        #expect(store.error == nil)
    }

    @Test func keepsLastGoodConfigOnError() throws {
        let (store, file) = try makeStore()
        var changes = 0
        store.onChange = { changes += 1 }

        try "[skins.a]\nbackground = \"#000000\"\n".write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.config.skins["a"] != nil)
        #expect(store.error == nil)

        try "[skins.a]\nbackground = \"#0000".write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.config.skins["a"] != nil)
        #expect(store.error?.contains("line 2") == true)

        try "[skins.b]\nbackground = \"#ffffff\"\n".write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.config.skins["b"] != nil)
        #expect(store.error == nil)
        #expect(changes == 3)
    }
}
```

`macos/Tests/Skins/SkinOverlayTests.swift`:

```swift
import Foundation
import Testing
@testable import Ghostty

struct SkinOverlayTests {
    @Test func colorOnly() {
        let skin = Skin(name: "p", background: RGB(hex: "#3a0f14")!, foreground: RGB(hex: "#eeeeee")!,
                        accent: RGB(hex: "#ffffff")!, texture: .none, textureOpacity: 0.16)
        #expect(SkinOverlay.configText(for: AppliedSkin(skin: skin, tile: nil))
            == "background = #3a0f14\nforeground = #eeeeee\n")
    }

    @Test func withTile() {
        let skin = Skin(name: "a", background: RGB(hex: "#12222b")!, foreground: nil,
                        accent: RGB(hex: "#46a2ff")!, texture: .builtin(.dots), textureOpacity: 0.2)
        let text = SkinOverlay.configText(for: AppliedSkin(skin: skin, tile: URL(fileURLWithPath: "/c/My Tiles/t.png")))
        #expect(text == """
        background = #12222b
        background-image = "/c/My Tiles/t.png"
        background-image-opacity = 0.200
        background-image-fit = none
        background-image-position = top-left
        background-image-repeat = true

        """)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `macos/skins-test.sh SkinConfigStoreTests; macos/skins-test.sh SkinOverlayTests`
Expected: both FAIL — types not found.

- [ ] **Step 3: Implement `SkinConfigStore.swift`**

```swift
#if os(macOS)
import Foundation

/// Loads skins.toml, keeps the last good config on errors, and watches for saves.
final class SkinConfigStore {
    let fileURL: URL
    private let home: String
    private(set) var config: SkinConfig = .empty
    private(set) var error: String?
    var onChange: (() -> Void)?
    private var watcher: DispatchSourceFileSystemObject?

    init(fileURL: URL, home: String = NSHomeDirectory()) {
        self.fileURL = fileURL
        self.home = home
    }

    deinit {
        watcher?.cancel()
    }

    func reload() {
        defer { onChange?() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            config = .empty
            error = nil
            return
        }
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            config = try SkinConfig.parse(text, home: home)
            error = nil
        } catch {
            // Keep the last good config; surface the problem to the UI.
            self.error = String(describing: error)
        }
    }

    /// Watches the directory (not the file) so rename-on-save editors are seen.
    func startWatching() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
#endif
```

- [ ] **Step 4: Implement `SkinsRuntime.swift`**

```swift
#if os(macOS)
import AppKit
import Foundation
import GhosttyKit

/// The Ghostty config lines a skin adds on top of the user's config.
enum SkinOverlay {
    static func configText(for applied: AppliedSkin) -> String {
        var lines = ["background = \(applied.skin.background.hex)"]
        if let foreground = applied.skin.foreground {
            lines.append("foreground = \(foreground.hex)")
        }
        if let tile = applied.tile {
            lines.append("background-image = \"\(tile.path)\"")
            lines.append(String(format: "background-image-opacity = %.3f", applied.skin.textureOpacity))
            lines.append("background-image-fit = none")
            lines.append("background-image-position = top-left")
            lines.append("background-image-repeat = true")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Applies a skin to one surface: user config + overlay → ghostty_surface_update_config.
@MainActor
final class GhosttySkinApplier {
    private let overlayDir: URL

    init(overlayDir: URL) {
        self.overlayDir = overlayDir
    }

    func apply(_ id: UUID, _ applied: AppliedSkin?) -> Bool {
        guard let delegate = NSApp.delegate as? GhosttyAppDelegate,
              let view = delegate.findSurface(forUUID: id),
              let surface = view.surface else { return false }
        guard let cfg = ghostty_config_new() else { return true }
        defer { ghostty_config_free(cfg) }

        ghostty_config_load_default_files(cfg)
        if !isRunningInXcode() { ghostty_config_load_cli_args(cfg) }
        if let applied {
            let url = overlayDir.appendingPathComponent("\(id.uuidString).ghostty")
            do {
                try FileManager.default.createDirectory(at: overlayDir, withIntermediateDirectories: true)
                try SkinOverlay.configText(for: applied).write(to: url, atomically: true, encoding: .utf8)
                ghostty_config_load_file(cfg, url.path)
            } catch {
                Ghostty.logger.warning("skins: failed to write overlay: \(String(describing: error))")
            }
        }
        ghostty_config_load_recursive_files(cfg)
        ghostty_config_finalize(cfg)
        ghostty_surface_update_config(surface, cfg)
        return true
    }
}

/// App-wide skins wiring: config store, manager, applier, preview expiry.
@MainActor
final class SkinsRuntime {
    static let shared = SkinsRuntime()

    static var configDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/ghostty-skins")
    }

    static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ghostty-skins")
    }

    let manager: SkinManager
    private let store: SkinConfigStore
    private var expiryTimer: Timer?

    private init() {
        let applier = GhosttySkinApplier(overlayDir: Self.cacheDir.appendingPathComponent("overlays"))
        let store = SkinConfigStore(fileURL: Self.configDir.appendingPathComponent("skins.toml"))
        store.reload()
        self.store = store
        self.manager = SkinManager(
            config: store.config,
            textures: TextureStore(cacheDir: Self.cacheDir.appendingPathComponent("textures")),
            catalogURL: Self.configDir.appendingPathComponent("state/catalog.json"),
            apply: { id, applied in applier.apply(id, applied) })
        manager.updateConfig(store.config, error: store.error)
        store.onChange = { [weak self] in
            guard let self else { return }
            self.manager.updateConfig(self.store.config, error: self.store.error)
        }
        store.startWatching()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.manager.expirePreviews() }
        }
    }

    func pwdChanged(_ view: Ghostty.SurfaceView, pwd: String) {
        manager.pwdChanged(view.id, pwd: pwd)
    }

    func userVarChanged(_ view: Ghostty.SurfaceView, name: String, value: String) {
        manager.handleUserVar(view.id, name: name, value: value)
    }

    func ghosttyConfigReloaded() {
        manager.reapplyAll()
    }
}
#endif
```

- [ ] **Step 5: Run the unit tests**

Run: `macos/skins-test.sh SkinConfigStoreTests && macos/skins-test.sh SkinOverlayTests`
Expected: both `** TEST SUCCEEDED **`.

- [ ] **Step 6: Hook `Ghostty.App.swift`**

(a) In `pwdChanged`, directly after `surfaceView.pwd = pwd`:

```swift
                // Ghostty Skins: re-skin the pane for its new directory.
                MainActor.assumeIsolated { SkinsRuntime.shared.pwdChanged(surfaceView, pwd: pwd) }
```

(b) In the action switch, after the `case GHOSTTY_ACTION_PWD:` case:

```swift
            case GHOSTTY_ACTION_SET_USER_VAR:
                userVarChanged(app, target: target, v: action.action.set_user_var)
```

and add next to `pwdChanged`:

```swift
        private static func userVarChanged(
            _ app: ghostty_app_t,
            target: ghostty_target_s,
            v: ghostty_action_set_user_var_s) {
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                  let surface = target.target.surface,
                  let surfaceView = self.surfaceView(from: surface),
                  let namePtr = v.name, let valuePtr = v.value,
                  let name = String(cString: namePtr, encoding: .utf8),
                  let value = String(cString: valuePtr, encoding: .utf8) else { return }
            // Ghostty Skins: requests from the `skins` CLI arrive as a user var.
            MainActor.assumeIsolated {
                SkinsRuntime.shared.userVarChanged(surfaceView, name: name, value: value)
            }
        }
```

(c) In `configChange`, in the `case GHOSTTY_TARGET_APP:` branch, directly before its `return`:

```swift
                    // Ghostty Skins: an app-wide reload replaced every surface's
                    // config; put skins back once this callback has returned.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { SkinsRuntime.shared.ghosttyConfigReloaded() }
                    }
```

- [ ] **Step 7: Give every pane its UUID in the environment (`SurfaceView_AppKit.swift`)**

Replace `let surface_cfg = baseConfig ?? SurfaceConfiguration()` (~line 393) with:

```swift
            var surface_cfg = baseConfig ?? SurfaceConfiguration()
            // Ghostty Skins: lets the `skins` CLI find this pane in catalog.json.
            surface_cfg.environmentVariables[SkinsConstants.surfaceEnvKey] = id.uuidString
```

- [ ] **Step 8: Build and run all skins tests**

Run: `macos/build.nu --scheme Ghostty --configuration Debug --action build 2>&1 | grep -E "error:|BUILD" ; macos/skins-test.sh`
Expected: `** BUILD SUCCEEDED **`, then the full suite `** TEST SUCCEEDED **`.

- [ ] **Step 9: End-to-end check (automatic switching)**

Create the real config (the user approved Arca as the branded skin):

```bash
mkdir -p ~/.config/ghostty-skins
cat > ~/.config/ghostty-skins/skins.toml <<'EOF'
[skins.arca]
background = "#12222b"
foreground = "#eaf3ff"
accent = "#46a2ff"
logo = "~/projectrepos/arca-labs/website/assets/favicon.svg"

[[match]]
path = "~/projectrepos/arca"
skin = "arca"

[[match]]
path = "~/projectrepos/arca-labs"
skin = "arca"

[skins.prod]
background = "#3a0f14"
texture = "diagonal"
EOF
```

Launch and drive the Debug build (same technique as the spike: `input text` then `send key "enter"`):

```bash
APP="$PWD/macos/build/Debug/Ghostty.app"
open "$APP"; sleep 5
osascript -e "tell application \"$APP\"" \
  -e 'set c to new surface configuration' \
  -e 'set initial working directory of c to "/Users/lawliang/projectrepos/arca"' \
  -e 'set w to new window with configuration c' -e 'end tell'
sleep 3
osascript -e "tell application \"$APP\"" -e 'input text "cd ~/projectrepos/Milo" to terminal 1' -e 'send key "enter" to terminal 1' -e 'end tell'
cat ~/.config/ghostty-skins/state/catalog.json
```

Expected: `catalog.json` lists skin `arca` and has a pane entry whose skin is `Milo` with source `auto` (the pane moved from arca to Milo). With the user's permission, screenshot the window (`screencapture -x -o -l <windowid>`) to confirm: Arca navy + logo tile before the `cd`, a dark auto color + pattern after. Then run in that terminal `cd ~` and confirm the default look returns. Quit the Debug app afterwards.

Also confirm the quoted `background-image` path is accepted: `grep -i "background-image" ~/Library/Logs/ghostty*.log 2>/dev/null` shows no config error, and the texture is visible in the screenshot. If Ghostty rejects the quotes, remove them in `SkinOverlay` and in `SkinOverlayTests.withTile`, then re-run tests.

- [ ] **Step 10: Record hooks and commit**

Append to `UPGRADING.md`:

```markdown
- `macos/Sources/Ghostty/Ghostty.App.swift` — `pwdChanged` calls `SkinsRuntime.shared.pwdChanged`; `GHOSTTY_ACTION_SET_USER_VAR` case + `userVarChanged`; app-target `configChange` schedules `ghosttyConfigReloaded()`.
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` — `GHOSTTY_SKINS_SURFACE` env var on surface creation.
```

```bash
git add macos/Sources macos/Tests UPGRADING.md
git commit -m "skins: wire skins into Ghostty (pwd, user vars, config reload)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Title-bar chip and popover

**Files:**
- Create: `macos/Sources/Features/Skins/SkinChipView.swift`, `macos/Sources/Features/Skins/SkinPopoverView.swift`
- Modify: `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift` (properties near line 22; `awakeFromNib` titled block ~line 145)
- Modify: `macos/Sources/Features/Terminal/BaseTerminalController.swift` (`focusedSurface` `didSet`, line 40)

**Interfaces:**
- Consumes: `SkinManager` (`effectiveSkin`, `panes`, `configError`, `config`, `sourceLabel`, `setPreview`, `setOverride`, `reset`, `tileURL`), `SkinsRuntime.shared`.
- Produces: `@MainActor final class SkinChipModel: ObservableObject { @Published var focusedSurfaceID: UUID? }`; `TerminalWindow.skinChipModel`.

- [ ] **Step 1: Implement `SkinChipView.swift`**

```swift
#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Which surface the window's chip describes.
@MainActor
final class SkinChipModel: ObservableObject {
    @Published var focusedSurfaceID: UUID?
}

extension Color {
    init(rgb: RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

/// Title-bar pill showing the focused pane's skin; click to override it.
struct SkinChipView: View {
    @ObservedObject var model: SkinChipModel
    @ObservedObject var manager: SkinManager
    @State private var showingPopover = false

    var body: some View {
        let id = model.focusedSurfaceID
        let skin = id.flatMap { manager.effectiveSkin($0) }
        Button {
            showingPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(skin.map { Color(rgb: $0.background) } ?? Color.secondary.opacity(0.3))
                    .overlay(Circle().strokeBorder(skin.map { Color(rgb: $0.accent) } ?? Color.secondary, lineWidth: 1.5))
                    .frame(width: 11, height: 11)
                Text(skin?.name ?? "default")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let id, manager.panes[id]?.override != nil {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                }
                if manager.configError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(id == nil)
        .help("Pane skin")
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            if let id {
                SkinPopoverView(surfaceID: id, manager: manager)
            }
        }
        .padding(.leading, 6)
    }
}
#endif
```

- [ ] **Step 2: Implement `SkinPopoverView.swift`**

```swift
#if os(macOS)
import AppKit
import SwiftUI

/// Edits a draft skin that previews live; Apply makes it the pane's override.
struct SkinPopoverView: View {
    let surfaceID: UUID
    @ObservedObject var manager: SkinManager
    @State private var draft: Skin?
    @State private var committed = false

    private static let presets: [RGB] = [
        "#12222b", "#10262b", "#1f2a1c", "#2a2416", "#2b1a10", "#3a0f14", "#2b1f33", "#1c1c1c",
    ].compactMap(RGB.init(hex:))

    private var base: Skin {
        manager.effectiveSkin(surfaceID) ?? Skin.fallback
    }

    private var current: Skin {
        draft ?? base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(manager.sourceLabel(surfaceID)).font(.headline)
            if let error = manager.configError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !manager.config.skins.isEmpty {
                section("Skins") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(manager.config.skins.values.sorted { $0.name < $1.name }, id: \.name) { skin in
                            Button {
                                preview(skin)
                            } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(Color(rgb: skin.background)).frame(width: 10, height: 10)
                                    Text(skin.name).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }

            section("Color") {
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.self) { color in
                        Button {
                            edit { $0.background = color }
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(rgb: color))
                                .frame(width: 20, height: 20)
                                .overlay(RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(current.background == color ? Color.accentColor : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    ColorPicker("", selection: colorBinding, supportsOpacity: false).labelsHidden()
                }
            }

            section("Texture") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                    ForEach(textureOptions, id: \.label) { option in
                        Button {
                            edit { skin in
                                skin.texture = option.texture
                                skin.accent = option.accent ?? Skin.defaultAccent(for: skin.background)
                            }
                        } label: {
                            thumbnail(option)
                        }
                        .buttonStyle(.plain)
                        .help(option.label)
                    }
                }
            }

            section("Texture opacity") {
                Slider(value: opacityBinding, in: 0...0.5)
            }

            HStack {
                Button("Reset to project") {
                    committed = true
                    draft = nil
                    manager.reset(surfaceID)
                }
                Spacer()
                Button("Apply") {
                    committed = true
                    if let draft { manager.setOverride(surfaceID, draft) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft == nil)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onDisappear {
            if !committed { manager.setPreview(surfaceID, nil) }
        }
    }

    // MARK: Draft editing

    private func preview(_ skin: Skin) {
        committed = false
        draft = skin
        manager.setPreview(surfaceID, skin)
    }

    private func edit(_ change: (inout Skin) -> Void) {
        var skin = current
        skin.name = "custom"
        change(&skin)
        preview(skin)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(rgb: current.background) },
            set: { newValue in
                guard let c = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                let rgb = RGB(
                    r: UInt8((c.redComponent * 255).rounded()),
                    g: UInt8((c.greenComponent * 255).rounded()),
                    b: UInt8((c.blueComponent * 255).rounded()))
                edit { skin in
                    skin.background = rgb
                    if case .builtin = skin.texture { skin.accent = Skin.defaultAccent(for: rgb) }
                }
            })
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { current.textureOpacity }, set: { value in edit { $0.textureOpacity = value } })
    }

    // MARK: Textures

    private struct TextureOption {
        let label: String
        let texture: SkinTexture
        let accent: RGB?
    }

    private var textureOptions: [TextureOption] {
        var options = [TextureOption(label: "None", texture: .none, accent: nil)]
        options += BuiltinTexture.allCases.map { TextureOption(label: $0.rawValue, texture: .builtin($0), accent: nil) }
        for skin in manager.config.skins.values.sorted(by: { $0.name < $1.name }) {
            if case .logo = skin.texture {
                options.append(TextureOption(label: "\(skin.name) logo", texture: skin.texture, accent: skin.accent))
            }
        }
        return options
    }

    private func sampleSkin(for option: TextureOption) -> Skin {
        var skin = current
        skin.texture = option.texture
        skin.accent = option.accent ?? Skin.defaultAccent(for: current.background)
        return skin
    }

    @ViewBuilder
    private func thumbnail(_ option: TextureOption) -> some View {
        let selected = current.texture == option.texture
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color(rgb: current.background))
            if option.texture != .none {
                if let url = manager.tileURL(for: sampleSkin(for: option)), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFill().opacity(0.8)
                }
            } else {
                Image(systemName: "nosign").foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
#endif
```

- [ ] **Step 3: Mount the chip (`TerminalWindow.swift`)**

Next to `private let updateAccessory = NSTitlebarAccessoryViewController()` add:

```swift
    /// Ghostty Skins: model and accessory for the pane skin chip.
    let skinChipModel = SkinChipModel()
    private let skinAccessory = NSTitlebarAccessoryViewController()
```

In `awakeFromNib`, inside `if styleMask.contains(.titled) {`, after the update-accessory block, add:

```swift
            // Ghostty Skins: pane skin chip at the leading edge of the titlebar.
            skinAccessory.layoutAttribute = .left
            skinAccessory.view = NonDraggableHostingView(rootView: SkinChipView(
                model: skinChipModel,
                manager: SkinsRuntime.shared.manager))
            addTitlebarAccessoryViewController(skinAccessory)
```

- [ ] **Step 4: Tell the chip which pane is focused (`BaseTerminalController.swift`)**

Change:

```swift
    var focusedSurface: Ghostty.SurfaceView? {
        didSet { syncFocusToSurfaceTree() }
    }
```

to:

```swift
    var focusedSurface: Ghostty.SurfaceView? {
        didSet {
            syncFocusToSurfaceTree()
            // Ghostty Skins: keep the title-bar chip on the focused pane.
            (window as? TerminalWindow)?.skinChipModel.focusedSurfaceID = focusedSurface?.id
        }
    }
```

- [ ] **Step 5: Build and run the full test suite**

Run: `macos/build.nu --scheme Ghostty --configuration Debug --action build 2>&1 | grep -E "error:|BUILD" ; macos/skins-test.sh`
Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`.

- [ ] **Step 6: End-to-end check (chip + popover)**

Launch the Debug build, open a window in `~/projectrepos/arca`, and split it (`osascript … split terminal 1 direction right`). With the user's permission, screenshot and confirm:
- the chip reads `arca` with a navy swatch; focusing the other (home) pane switches it to `default`;
- clicking the chip opens the popover; picking a preset color previews it live, closing the popover without Apply reverts, Apply keeps it and shows the override dot; "Reset to project" removes it;
- repeat once with `macos-titlebar-style = tabs` in `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` temporarily (restore the file afterwards) to confirm the chip also appears with the tabs title bar. If it does not, record that in the final report rather than patching tab-style subclasses.

- [ ] **Step 7: Record hooks and commit**

Append to `UPGRADING.md`:

```markdown
- `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift` — `skinChipModel`, `skinAccessory`, chip mount in `awakeFromNib`.
- `macos/Sources/Features/Terminal/BaseTerminalController.swift` — `focusedSurface.didSet` updates the chip.
```

```bash
git add macos/Sources UPGRADING.md
git commit -m "skins: add title-bar skin chip and override popover

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: `ghostty +skins` CLI, picker, and `skins` shell function

**Files:**
- Create: `src/cli/skins/protocol.zig`, `src/cli/skins.zig`
- Modify: `src/cli/ghostty.zig` (imports, `Action` enum, `runMain`, `options`)
- Modify: `src/shell-integration/zsh/ghostty-integration` (before the final `_entrypoint` line), `src/shell-integration/bash/ghostty.bash` (end of file)

**Interfaces:**
- Consumes: wire protocol (spec §6.3), `catalog.json` written by `SkinManager.writeCatalog` (Task 9), `GHOSTTY_SKINS_SURFACE` (Task 10).
- Produces: `protocol.Request`, `protocol.Op`, `protocol.Command`, `protocol.parseArgs`, `protocol.encodeJson`, `protocol.encodeSequence`, `protocol.parseCatalog`, `protocol.Catalog`; CLI `ghostty +skins [set <name>|color <#hex>|texture <name|none>|opacity <0-1>|reset|list|current|help]`; shell function `skins`.

- [ ] **Step 1: Write the failing tests** (`src/cli/skins/protocol.zig`, tests first — the file starts with just these tests and the imports)

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

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
```

- [ ] **Step 2: Register the file with the test build and verify failure**

Create `src/cli/skins.zig` with only:

```zig
test {
    _ = @import("skins/protocol.zig");
}
```

and add `const skins = @import("skins.zig");` to `src/cli/ghostty.zig` imports plus, at the end of that file, `test { _ = skins; }` if the file has no existing test block referencing imports (check with `grep -n "^test" src/cli/ghostty.zig`; if a `test {` block with `_ = …` lines exists, add `_ = skins;` to it instead).

Run: `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" && zig build test -Demit-macos-app=false -Dtest-filter="skins:" 2>&1 | tail -5`
Expected: compile error — `use of undeclared identifier 'encodeJson'`.

- [ ] **Step 3: Implement `src/cli/skins/protocol.zig`** (add above the tests)

```zig
//! Pure logic for the `skins` CLI: argument parsing, the GHOSTTY_SKIN wire
//! format, and reading catalog.json. See docs/superpowers/specs (§6).

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
```

- [ ] **Step 4: Run to verify pass**

Run: `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" && zig build test -Demit-macos-app=false -Dtest-filter="skins:" 2>&1 | tail -5`
Expected: all `skins:` tests pass. (If `Writer.Allocating.toOwnedSlice` or `print` signatures differ in this Zig version, mirror `ThemeListElement.toUri` in `src/cli/list_themes.zig`, which uses the same API.)

- [ ] **Step 5: Implement the CLI and picker (`src/cli/skins.zig`)**

Replace the file with:

```zig
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
```

- [ ] **Step 6: Register the action (`src/cli/ghostty.zig`)**

- In `pub const Action = enum {`, after `@"new-window",` add:

```zig
    // Ghostty Skins: preview and set this pane's skin.
    skins,
```

- In `runMain`, add `.skins => try skins.run(alloc),`.
- In `pub fn options`, add `.skins => skins.Options,`.

- [ ] **Step 7: Add the shell functions**

In `src/shell-integration/zsh/ghostty-integration`, directly above the final `_entrypoint` line:

```zsh
# Ghostty Skins: `skins` runs the running app's skin picker / CLI.
skins() { "${GHOSTTY_BIN_DIR:+$GHOSTTY_BIN_DIR/}ghostty" +skins "$@"; }
```

At the end of `src/shell-integration/bash/ghostty.bash`:

```bash
# Ghostty Skins: `skins` runs the running app's skin picker / CLI.
skins() { "${GHOSTTY_BIN_DIR:+$GHOSTTY_BIN_DIR/}ghostty" +skins "$@"; }
```

- [ ] **Step 8: Build and run tests**

Run: `export PATH="$(brew --prefix zig@0.15)/bin:$PATH" && zig build test -Demit-macos-app=false -Dtest-filter="skins:" 2>&1 | tail -3 && zig build -Demit-macos-app=false -Doptimize=ReleaseFast -Dxcframework-target=native && macos/build.nu --scheme Ghostty --configuration Debug --action build 2>&1 | grep -E "error:|BUILD"`
Expected: tests pass, `** BUILD SUCCEEDED **`. If vaxis API names differ (`printSegment` options, `Style` fields, `resize` signature), copy the exact call shapes from `src/cli/list_themes.zig` (lines 229–690).

- [ ] **Step 9: End-to-end check**

Launch the Debug build and open a window in `~/projectrepos/arca`. Drive it with AppleScript (`input text` + `send key "enter"`):
1. `skins current` → prints `arca (config) #12222b`.
2. `skins list` → lists `arca` and the texture names.
3. `skins set prod` → `skins current` prints `… (override) …`; with permission, screenshot shows the new look.
4. `skins reset` → back to Arca.
5. `skins` (picker) → send `down` key twice via `send key "down"`, confirm the pane previews; send `escape`; confirm Arca returns and `skins current` shows `(config)`.
6. Outside Ghostty Skins (e.g. `env -u GHOSTTY_SKINS_SURFACE ghostty +skins current` from the Debug app's binary path) → exits 1 with the "run this inside" message.

- [ ] **Step 10: Record hooks and commit**

Append to `UPGRADING.md`:

```markdown
- `src/cli/ghostty.zig` — `skins` import, `Action.skins`, `runMain` and `options` entries.
- `src/shell-integration/zsh/ghostty-integration` — `skins()` above `_entrypoint`.
- `src/shell-integration/bash/ghostty.bash` — `skins()` at end.
```

```bash
git add src/cli src/shell-integration UPGRADING.md
git commit -m "skins: add ghostty +skins CLI with live-preview picker and skins shell function

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Docs, example config, installer, final verification

**Files:**
- Create: `SKINS.md`, `docs/skins/skins.example.toml`, `macos/install-skins.sh`

**Interfaces:**
- Consumes: everything.
- Produces: user documentation and `/Applications/Ghostty Skins.app`.

- [ ] **Step 1: Example config** — `docs/skins/skins.example.toml`

```toml
# Copy to ~/.config/ghostty-skins/skins.toml. Saved changes apply immediately.

[defaults]
texture_opacity = 0.16   # 0–1; how visible textures are
auto = true              # automatic skin for any git repo not listed below

[skins.arca]
background = "#12222b"
foreground = "#eaf3ff"
accent     = "#46a2ff"   # logo color
logo       = "~/projectrepos/arca-labs/website/assets/favicon.svg"

[skins.prod]             # not tied to a folder; use with `skins set prod`
background = "#3a0f14"
texture    = "diagonal"  # dots, grid, diagonal, cross, waves, noise, none

[[match]]
path = "~/projectrepos/arca"
skin = "arca"

[[match]]
path = "~/projectrepos/arca-labs"
skin = "arca"
```

- [ ] **Step 2: User guide** — `SKINS.md`

```markdown
# Ghostty Skins

A fork of [Ghostty](https://github.com/ghostty-org/ghostty) that gives every
pane a background color and texture based on the project it is in.

- `cd` into a project and the pane re-skins; leave and it reverts.
- Split panes are skinned independently.
- Git repos you have not configured get a stable automatic skin.
- Override any pane from the title-bar chip or the `skins` command.

## Install

    macos/install-skins.sh      # builds and installs /Applications/Ghostty Skins.app

Requires Xcode (with the Metal Toolchain component:
`xcodebuild -downloadComponent MetalToolchain`), `brew install zig@0.15 nushell`.
It reads your normal Ghostty config.

## Configure

Copy `docs/skins/skins.example.toml` to `~/.config/ghostty-skins/skins.toml`.
Errors never break the terminal: the last good config stays active and the
title-bar chip shows a warning.

## Override

- Click the chip at the left of the title bar: pick a skin, color, texture or
  opacity (previews live), then **Apply**. **Reset to project** undoes it.
- Or in any pane: `skins` (interactive picker), `skins set <name>`,
  `skins color '#3a0f14'`, `skins texture grid`, `skins opacity 0.3`,
  `skins reset`, `skins list`, `skins current`.

Overrides last until reset or until the pane closes. zsh and bash get the
`skins` function from Ghostty's shell integration; other shells can run
`ghostty +skins`. In tmux, enable `set -g allow-passthrough on`.

## Updating from upstream Ghostty

See `UPGRADING.md`.
```

- [ ] **Step 3: Installer** — `macos/install-skins.sh`

```sh
#!/bin/sh
# Builds Ghostty Skins (ReleaseLocal) and installs /Applications/Ghostty Skins.app.
set -eu
cd "$(dirname "$0")/.."
export PATH="$(brew --prefix zig@0.15)/bin:$PATH"
zig build -Demit-macos-app=false -Doptimize=ReleaseFast -Dxcframework-target=native
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal \
  SYMROOT="$PWD/macos/build" build | tail -3
APP="macos/build/ReleaseLocal/Ghostty.app"
codesign --force --deep --sign - "$APP"
rm -rf "/Applications/Ghostty Skins.app"
cp -R "$APP" "/Applications/Ghostty Skins.app"
echo "Installed /Applications/Ghostty Skins.app"
```

Run: `chmod +x macos/install-skins.sh`

- [ ] **Step 4: Full verification**

Run:

```bash
export PATH="$(brew --prefix zig@0.15)/bin:$PATH"
zig build test -Demit-macos-app=false -Dtest-filter="SetUserVar" 2>&1 | tail -2
zig build test -Demit-macos-app=false -Dtest-filter="decodeUserVar" 2>&1 | tail -2
zig build test -Demit-macos-app=false -Dtest-filter="skins:" 2>&1 | tail -2
zig build test -Demit-macos-app=false -Dtest-filter="ghostty.h" 2>&1 | tail -2
macos/skins-test.sh
macos/install-skins.sh
```

Expected: every Zig filter passes, the Swift suite reports `** TEST SUCCEEDED **`, and the installer prints `Installed /Applications/Ghostty Skins.app`. Open the installed app, repeat the Task 10/11/12 E2E checks once against it (with the user's permission for screenshots), and confirm the regular `/Applications/Ghostty.app` still launches unchanged.

- [ ] **Step 5: Clean up spike leftovers (local only)**

Delete the spike's files that the real feature replaced: `rm -f ~/.config/ghostty-skins/arca.ghostty && rm -rf ~/.config/ghostty-skins/textures`. Leave `spike-shots/` (git-ignored) for the user to delete.

- [ ] **Step 6: Commit and push**

Before pushing, re-run the confidential-content check on the branch diff:

```bash
git diff v1.3.1..HEAD --stat
git diff v1.3.1..HEAD | grep -inE "token|secret|password|api[_-]?key|gho_|ghp_|sk-|BEGIN .*PRIVATE|@gmail" || echo "clean"
```

Expected: `clean` (the word "token" may legitimately appear only if you added it; inspect any hit).

```bash
git add SKINS.md docs/skins/skins.example.toml macos/install-skins.sh
git commit -m "skins: add user guide, example config, and installer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin skins
```
