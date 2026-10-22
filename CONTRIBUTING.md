# Contributing to Lostty

Thanks for helping out. Bug reports, ideas and changes are all welcome.

## Report a bug or suggest an idea

Open an issue at <https://github.com/Lawliang/lostty/issues>. For a bug,
say what you did, what you expected and what happened, plus your macOS
version (and iOS version for the phone app). Logs help; see
[Logging](#logging) below.

Lostty runs on [Ghostty](https://github.com/ghostty-org/ghostty)'s terminal
engine. If a bug also happens in plain Ghostty (rendering, fonts, escape
sequences, input), it belongs upstream at
<https://github.com/ghostty-org/ghostty>.

## Send a change

1. Fork the repo and make a branch.
2. Keep the change focused: one fix or feature per pull request.
3. Run the tests that cover what you touched (see [Test](#test)).
4. Open a pull request saying what changed and why. Screenshots help for UI.

If you're planning something big, open an issue first so we can agree on
the shape before you spend the time.

## Develop Lostty

How to build, test and debug Lostty.

### Build from source

To build Lostty from this repo instead of downloading it:

```sh
git clone https://github.com/Lawliang/lostty.git
cd lostty
macos/setup.sh
```

`setup.sh` installs the prerequisites below, then builds Lostty into `/Applications`. A copy built this way never checks for updates. To update it, `git pull`, run `macos/install.sh --stable` (plain `macos/install.sh` builds Lostty Beta; see [Stable and beta](#stable-and-beta)), then choose **Restart to Update** in Lostty's menu bar. Don't Quit Lostty to update: quitting ends every terminal session.

### Prerequisites

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

### Build

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
macos/install.sh --stable   # Lostty, as people download it
macos/install.sh            # Lostty Beta (see Stable and beta)
```

### Test

| What                    | Command                               |
| ----------------------- | ------------------------------------- |
| Zig (engine and CLI)    | `zig build test -Dtest-filter=<name>` |
| Mac app (`LosttyTests`) | `macos/build.nu --action test`        |
| One Mac test suite      | `macos/skins-test.sh <SuiteName>`     |
| Phone's shared package  | `cd macos/LosttyRemote && swift test` |

The full Zig suite is slow, so prefer `-Dtest-filter`. Add
`-Demit-macos-app=false` to skip building the app bundle.
`macos/skins-test.sh` writes its full log to `macos/build/last-test.log`.

### Format

- Zig: `zig fmt .`
- Swift: `swiftlint lint --strict --fix` (if you have
  [SwiftLint](https://github.com/realm/SwiftLint) installed)
- Everything else: `prettier -w .`

### Repo layout

| Path                  | What's there                                                         |
| --------------------- | -------------------------------------------------------------------- |
| `src/`                | Ghostty's terminal engine, plus Lostty's CLI additions in `src/cli/` |
| `macos/`              | The Lostty Mac and iPhone apps (`macos/Lostty.xcodeproj`)            |
| `macos/LosttyRemote/` | Swift package the phone uses for SSH and tmux                        |
| `docs/`               | Lostty docs; `docs/skins/` has the example skins config              |

Lostty still merges from upstream Ghostty, so code for other platforms
(`src/apprt/gtk`, `flatpak/`, `snap/` and so on) stays even though Lostty is
Mac-only. Leave it in place. Ghostty's project tooling that the build never
uses (Nix, Doxygen, examples) was removed. See [UPGRADING.md](UPGRADING.md)
for merging a new Ghostty release.

### Logging

Debug builds log to `stderr`. On macOS, logs also go to the unified log.
To watch them live:

```sh
log stream --level debug --process lostty
```

The `GHOSTTY_LOG` environment variable picks where logs go: `stderr`,
`macos` (the unified log), or both separated by a comma. Prefix one with
`no-` to turn it off, or use `true` / `false` for all or none. For example,
`GHOSTTY_LOG=stderr,no-macos`.

### Debugging tips

- Run the Debug app straight from the terminal to see `stderr`:
  `macos/build/Debug/Lostty.app/Contents/MacOS/lostty`
- Don't launch a dev build from inside another Lostty or Ghostty pane with
  `open`: it inherits that app's `GHOSTTY_RESOURCES_DIR`, and the `skins`
  shell function breaks in every new pane.
- For memory leaks (Zig can't see leaks in the engine's C libraries), run
  the Debug app under Instruments' Leaks template.

### Stable and beta

Lostty comes in two builds of the same `main`:

- **Lostty**, stable: the finished build people download.
- **Lostty Beta**: the same, plus features that aren't finished yet. Today that's the context handoff, Branches and the canvas.

Both are `/Applications/Lostty.app` with the same settings, terminals and phone pairing, so a Mac has one or the other. The beta says "Lostty Beta" and has a BETA band on its icon. Each follows its own update feed; to switch, download the other one.

- `macos/install.sh` builds the beta; `macos/install.sh --stable` builds stable. `macos/setup.sh` installs stable.
- Debug builds from Xcode are the beta.
- To keep a feature in the beta, check `LosttyChannel.current` (add a named check like `handsOff`) and make sure stable does none of its work.
- `macos/make-beta-icon.swift` remakes the beta icon after the icon changes.

### Release

Releases are made on the owner's Mac with `macos/release.sh`. It builds Lostty, signs it as Developer ID, has Apple notarize `Lostty.dmg`, and publishes it with Sparkle's `appcast.xml` as a GitHub release. Installed copies find it through that feed.

One-time setup, for team K85Z63QH48:

1. **Developer ID Application certificate:** Xcode → Settings → Accounts → Manage Certificates → **+** → Developer ID Application. Only the Account Holder can make it.
2. **Notarization login:** make an app-specific password at [account.apple.com](https://account.apple.com), then run `xcrun notarytool store-credentials lostty-notary --apple-id <your Apple ID> --team-id K85Z63QH48`.
3. **Update-signing key:** `macos/release.sh --make-key` puts the key in your login keychain and its public half in `macos/Lostty-Info.plist`. Commit that and push it to main.

Then, from a clean checkout of GitHub's `main`:

```sh
macos/release.sh --dry-run   # everything but publishing
macos/release.sh             # 0.2, 0.3, …; --version 1.0 to jump
```

It opens the release notes in `$EDITOR` first; an empty file stops it.

Each stable release also publishes its matching beta (`vX.Y-beta.1`, as a pre-release, plus the fixed `beta` release that holds the beta's feed). To publish a beta by itself, run `macos/release.sh --beta`: the next beta of the latest stable, with notes since the last release of either kind.
