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
- `src/terminal/osc.zig` — `set_user_var` Command field, `Key` list entry (last), reset-switch entry.
- `src/terminal/osc/parsers/iterm2.zig` — `.SetUserVar` branch (removed from unimplemented list) + tests.
- `src/terminal/stream.zig` — `set_user_var` Action + Key entry (last) + `SetUserVar` struct + `oscDispatch` arm.
- `src/terminal/stream_readonly.zig` — `.set_user_var` no-op.
- `src/termio/stream_handler.zig` — `.set_user_var` vt arm + `setUserVar`.
- `src/apprt/surface.zig` — `user_var: WriteReq` message.
- `src/Surface.zig` — `.user_var` handler, `decodeUserVar`, `userVar`, test.
- `src/apprt/action.zig` + `include/ghostty.h` — `set_user_var` action (last in enum/union), `ghostty_action_set_user_var_s`.
- `src/apprt/gtk/class/application.zig` — `.set_user_var` unimplemented.
