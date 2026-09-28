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

## Known limitations

- The title-bar chip is not shown when `macos-titlebar-style = hidden`.
- Quick Terminal panes are not skinned.
- fish, nushell, and other non-zsh/bash shells do not get the `skins`
  shell function; run `ghostty +skins` directly instead.
- tmux passes the skin escape sequence through only when
  `set -g allow-passthrough on` is set.

## Updating from upstream Ghostty

See `UPGRADING.md`.
