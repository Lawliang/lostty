# Developing Lostty

How to build, test and debug Lostty. To send a change, also read
[CONTRIBUTING.md](CONTRIBUTING.md).

## Prerequisites

- macOS with **Xcode 26** (macOS 26 SDK and iOS SDK). You can run Xcode 26
  on macOS 15.
- The Metal Toolchain: `xcodebuild -downloadComponent MetalToolchain`
- **Zig 0.15.2** and **Nushell**: `brew install zig@0.15 nushell`. Homebrew
  doesn't link `zig@0.15`, so put it on your `PATH`:
  `export PATH="$(brew --prefix zig@0.15)/bin:$PATH"`
- tmux, for the phone features: `brew install tmux`

If the build picks up the wrong Xcode:

```sh
sudo xcode-select --switch /Applications/Xcode.app
```

## Build

Lostty has two halves: the terminal engine (Zig, in `src/`), built into
`macos/GhosttyKit.xcframework`, and the apps (Swift, in `macos/`).

1. Build the engine. Do this first, and again whenever code outside
   `macos/` changes:

   ```sh
   zig build -Demit-macos-app=false
   ```

2. Build the Mac app with `macos/build.nu`, not `zig build`:

   ```sh
   macos/build.nu                              # Debug build of the Lostty scheme
   macos/build.nu --configuration Release
   macos/build.nu --action clean
   ```

   Flags: `--scheme` (`Lostty`, `Lostty-iOS`, `DockTilePlugin`),
   `--configuration` (`Debug`, `Release`, `ReleaseLocal`) and `--action`
   (any `xcodebuild` action). The app lands in
   `macos/build/<configuration>/Lostty.app`.

3. Build the iPhone app in Xcode: open `macos/Lostty.xcodeproj`, pick the
   `Lostty-iOS` scheme and a simulator or your phone, and run.

To build a release copy and install it as `/Applications/Lostty.app`:

```sh
macos/install-skins.sh
```

## Test

| What                    | Command                               |
| ----------------------- | ------------------------------------- |
| Zig (engine and CLI)    | `zig build test -Dtest-filter=<name>` |
| Mac app (`LosttyTests`) | `macos/build.nu --action test`        |
| One Mac test suite      | `macos/skins-test.sh <SuiteName>`     |
| Phone's shared package  | `cd macos/LosttyRemote && swift test` |

The full Zig suite is slow, so prefer `-Dtest-filter`. Add
`-Demit-macos-app=false` to skip building the app bundle.
`macos/skins-test.sh` writes its full log to `macos/build/last-test.log`.

## Format

- Zig: `zig fmt .`
- Swift: `swiftlint lint --strict --fix` (if you have
  [SwiftLint](https://github.com/realm/SwiftLint) installed)
- Everything else: `prettier -w .`

## Repo layout

| Path                  | What's there                                                         |
| --------------------- | -------------------------------------------------------------------- |
| `src/`                | Ghostty's terminal engine, plus Lostty's CLI additions in `src/cli/` |
| `macos/`              | The Lostty Mac and iPhone apps (`macos/Lostty.xcodeproj`)            |
| `macos/LosttyRemote/` | Swift package the phone uses for SSH and tmux                        |
| `docs/`               | Lostty docs; `docs/skins/` has the example skins config              |

Lostty still merges from upstream Ghostty, so code for other platforms
(`src/apprt/gtk`, `flatpak/`, `snap/`, `nix/` and so on) stays even though
Lostty is Mac-only. Leave it in place. See [UPGRADING.md](UPGRADING.md) for
merging a new Ghostty release.

## Logging

Debug builds log to `stderr`. On macOS, logs also go to the unified log.
To watch them live:

```sh
log stream --level debug --process lostty
```

The `GHOSTTY_LOG` environment variable picks where logs go: `stderr`,
`macos` (the unified log), or both separated by a comma. Prefix one with
`no-` to turn it off, or use `true` / `false` for all or none. For example,
`GHOSTTY_LOG=stderr,no-macos`.

## Debugging tips

- Run the Debug app straight from the terminal to see `stderr`:
  `macos/build/Debug/Lostty.app/Contents/MacOS/lostty`
- Don't launch a dev build from inside another Lostty or Ghostty pane with
  `open`: it inherits that app's `GHOSTTY_RESOURCES_DIR`, and the `skins`
  shell function breaks in every new pane.
- For memory leaks (Zig can't see leaks in the engine's C libraries), run
  the Debug app under Instruments' Leaks template.
