# Upgrading Lostty to a new Ghostty release

Lostty is `skins` = upstream tag + our commits. Lostty's history starts at
its own root commit, a copy of Ghostty 1.3.1, so git can't see that it
shares history with upstream. Before merging, tell your clone once that the
root sits on top of Ghostty's 1.3.1 commit (this stays local and is never
pushed):

    git fetch upstream tag v1.3.1 --no-tags
    git replace --graft "$(git rev-list --max-parents=0 HEAD)" v1.3.1

To move to a new tag:

    git fetch upstream tag v1.3.2 --no-tags
    git merge v1.3.2
    # resolve conflicts in the hook list below, then:
    export PATH="$(brew --prefix zig@0.15)/bin:$PATH"   # use the Zig version the new tag requires
    zig build test -Demit-macos-app=false -Dtest-filter=UserVar
    zig build test -Demit-macos-app=false -Dtest-filter="skins:"
    zig build -Demit-macos-app=false -Doptimize=ReleaseFast -Dxcframework-target=native
    macos/skins-test.sh
    macos/install-skins.sh

## Upstream files we hook (keep these hunks when resolving conflicts)

- `macos/Lostty.xcodeproj/project.pbxproj` (upstream's `macos/Ghostty.xcodeproj`, renamed) — the `Lostty`, `Lostty-iOS` and `LosttyTests` targets and schemes, the `lostty` executable name, app target `PRODUCT_BUNDLE_IDENTIFIER` and `INFOPLIST_KEY_CFBundleDisplayName` (3 build configurations). Git follows the rename; take upstream's new files and settings, keep our names.
- Icons: Lostty's own axolotl icons are `macos/Assets.xcassets/LosttyMacIcon.appiconset`, `LosttyIconImage.imageset` and `LosttyPhoneIcon.appiconset`. Upstream's icon art (`AppIconImage.imageset`, `Alternate Icons/`, `Custom Icon/`) and its custom-icon code were removed, and `images/Ghostty.icon` was deleted. If upstream changes those, keep them removed.
- Removed Ghostty project tooling: `nix/`, `flake.nix`, `flake.lock`, `default.nix`, `shell.nix`, `.envrc`, `build.zig.zon.nix`, `Doxyfile`, `DoxygenLayout.xml`, `src/build/docker/`, `example/`, `typos.toml`, `.mailmap`, `.github/`. If upstream changes these, keep them deleted (`git rm` them).
- `macos/Sources/Features/Custom App Icon/DockTilePlugin.swift`: ours only clears a custom icon an older build stamped on the app. The app ignores the `macos-icon` options. On conflict keep ours.
- `src/terminal/osc.zig` — `set_user_var` Command field, `Key` list entry (last), reset-switch entry.
- `src/terminal/osc/parsers/iterm2.zig` — `.SetUserVar` branch (removed from unimplemented list) + tests.
- `src/terminal/stream.zig` — `set_user_var` Action + Key entry (last) + `SetUserVar` struct + `oscDispatch` arm.
- `src/terminal/stream_readonly.zig` — `.set_user_var` no-op.
- `src/termio/stream_handler.zig` — `.set_user_var` vt arm + `setUserVar`.
- `src/apprt/surface.zig` — `user_var: WriteReq` message.
- `src/Surface.zig` — `.user_var` handler, `decodeUserVar`, `userVar`, test.
- `src/apprt/action.zig` + `include/ghostty.h` — `set_user_var` action (last in enum/union), `ghostty_action_set_user_var_s`.
- `src/apprt/gtk/class/application.zig` — `.set_user_var` unimplemented.
- `macos/Sources/Ghostty/Ghostty.App.swift` — `pwdChanged` calls `SkinsRuntime.shared.pwdChanged`; `GHOSTTY_ACTION_SET_USER_VAR` case + `userVarChanged`; app-target `configChange` schedules `ghosttyConfigReloaded()`; surface-target `configReload` schedules `SkinsRuntime.shared.surfaceConfigReloaded(surfaceView)` after `ghostty.reloadConfig(surface:soft:)` (covers the soft reload macOS sends on a light/dark appearance change).
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` — `LOSTTY_SKINS_SURFACE` env var on surface creation.
- `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift` — `skinChipModel`, `skinAccessory`, chip mount in `awakeFromNib`.
- `macos/Sources/Features/Terminal/BaseTerminalController.swift` — `focusedSurface.didSet` updates the chip.
- `src/cli/ghostty.zig` — `skins` import, `Action.skins`, `runMain` and `options` entries, trailing `test { _ = skins; }` block.
- `src/shell-integration/zsh/ghostty-integration` — `skins()` above `_entrypoint`.
- `src/shell-integration/bash/ghostty.bash` — `skins()` at end.
- `macos/Sources/Features/Update/UpdateDelegate.swift` — `feedURLString(for:)` unconditionally returns `nil` (this fork has no appcast and must never resolve to upstream Ghostty's feed).
- `macos/Sources/App/macOS/AppDelegate.swift` — `validateMenuItem(_:)` disables the `checkForUpdates(_:)` (Check for Updates…) menu item, since there is no feed to check.
