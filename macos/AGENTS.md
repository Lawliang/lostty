# Lostty Mac and iPhone apps

- Use `swiftlint` for formatting and linting Swift code.
- If code outside of `macos/` directory is modified, use
  `zig build -Demit-macos-app=false` before building the Mac app to update
  the underlying terminal engine library (GhosttyKit).
- Use `macos/build.nu` to build the Mac app, do not use `zig build`
  (except to build the underlying library as mentioned above).
  - Build: `macos/build.nu [--scheme Lostty] [--configuration Debug] [--action build]`
  - Schemes: `Lostty` (Mac), `Lostty-iOS` (iPhone), `DockTilePlugin`
  - Output: `macos/build/<configuration>/Lostty.app` (e.g. `macos/build/Debug/Lostty.app`)
- Install a new build for the user with `macos/install.sh`, then
  switch to it with Lostty's menu bar → **Restart to Update** (or
  `osascript -e 'tell application id "com.lawliang.lostty" to «event GhstRsUp»'`,
  the raw `restart to update` event). Never Quit Lostty to update:
  Quit ends every terminal session it owns. Back out with
  `macos/install.sh --previous`.
- Run unit tests (`LosttyTests`) directly with `macos/build.nu --action test`,
  or one suite with `macos/skins-test.sh <SuiteName>`.
- Test the phone's shared package with `cd macos/LosttyRemote && swift test`.

## AppleScript

- The AppleScript scripting definition is in `macos/Ghostty.sdef`.
- Guard AppleScript entry points and object accessors with the
  `macos-applescript` configuration (use `NSApp.isAppleScriptEnabled`
  and `NSApp.validateScript(command:)` where applicable).
- In `macos/Ghostty.sdef`, keep top-level definitions in this order:
  1. Classes
  2. Records
  3. Enums
  4. Commands
- Test AppleScript support:
  (1) Build with `macos/build.nu`
  (2) Launch and activate the app via osascript using the absolute path
      to the built app bundle:
      `osascript -e 'tell application "<absolute path to build/Debug/Lostty.app>" to activate'`
  (3) Wait a few seconds for the app to fully launch and open a terminal.
  (4) Run test scripts with `osascript`, always targeting the app by
      its absolute path (not by name) to avoid calling the wrong
      application.
  (5) When done, quit via:
      `osascript -e 'tell application "<absolute path to build/Debug/Lostty.app>" to quit'`
