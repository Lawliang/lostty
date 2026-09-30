# Upgrading Lostty (Ghostty Skins) to a new Ghostty release

Lostty is `skins` = upstream tag + our commits. To move to a new tag:

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

- `macos/Ghostty.xcodeproj/project.pbxproj` — app target `PRODUCT_BUNDLE_IDENTIFIER` and `INFOPLIST_KEY_CFBundleDisplayName` (3 build configurations).
- `images/Ghostty.icon/` (Screen.png, Ghostty.png, Inner Bevel 6px.png, and icon.json's frame gradient + GhosttyBlur fill) and `macos/Assets.xcassets/AppIconImage.imageset/*.png` — Lostty's neon-pink icon. On conflict keep ours. If upstream redraws the icon, rerun `python3 docs/skins/recolor-icon.py screen|bevel|ghost <upstream layer> <dst>`, reapply the icon.json colors, build, and re-export the fallback PNGs from the built app's icon.
- `macos/Sources/Features/Custom App Icon/DockTilePlugin.swift` — release builds on macOS 26 use the bundled `AppIconImage` (hologram-pink Blueprint) and stamp it on the bundle instead of the composed glass icon. `macos/Assets.xcassets/AppIconImage.imageset/*.png` hold that artwork (`python3 docs/skins/recolor-icon.py blueprint <Blueprint 1024px> <dst>`).
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
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` — `GHOSTTY_SKINS_SURFACE` env var on surface creation.
- `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift` — `skinChipModel`, `skinAccessory`, chip mount in `awakeFromNib`.
- `macos/Sources/Features/Terminal/BaseTerminalController.swift` — `focusedSurface.didSet` updates the chip.
- `src/cli/ghostty.zig` — `skins` import, `Action.skins`, `runMain` and `options` entries, trailing `test { _ = skins; }` block.
- `src/shell-integration/zsh/ghostty-integration` — `skins()` above `_entrypoint`.
- `src/shell-integration/bash/ghostty.bash` — `skins()` at end.
- `macos/Sources/Features/Update/UpdateDelegate.swift` — `feedURLString(for:)` unconditionally returns `nil` (this fork has no appcast and must never resolve to upstream Ghostty's feed).
- `macos/Sources/App/macOS/AppDelegate.swift` — `validateMenuItem(_:)` disables the `checkForUpdates(_:)` (Check for Updates…) menu item, since there is no feed to check.
