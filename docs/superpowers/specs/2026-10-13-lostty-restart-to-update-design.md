# Lostty Restart to Update — design

Status: draft for review (2026-10-13)

## Goal

Putting a new Lostty in `/Applications` (`macos/install-skins.sh`, an agent's
Debug build, or later Sparkle) never costs you your terminals. Lostty notices
it was replaced and offers **Restart to Update** in its menu bar. Restarting
brings back every window, tab and split, each still attached to the same tmux
session, with Claude still running in it and its state shown correctly. A
normal Quit still ends sessions, as quitting a terminal ends its shells.

### Success criteria

- With 6 terminals open (Claudes working in some), run `install-skins.sh`,
  then choose Restart to Update: within a few seconds the same windows, tabs
  and splits are back, each pane in the same tmux session with its
  scrollback; no prompt; no Claude was interrupted.
- A row that was "Working" or "Waiting" before the restart shows the same
  after it, without waiting for Claude's next hook.
- Stay Awake for Phone, if on, stays on through the restart.
- A build that crashes at launch: the sessions are still running; one
  command (or the menu item, if the new build runs at all) puts the previous
  build back and reopens them.
- A real crash still gets today's "Reopen N terminal sessions?" prompt.
- The installed app and an agent's Debug build each restart only into the
  sessions they own.

## Facts this design rests on

- Quitting ends this Lostty's sessions: `applicationWillTerminate` calls
  `TmuxClient().endSessions(ownedBy: pid)` (`AppDelegate.swift`). Sparkle's
  relaunch quits the same way, so it would end them too. Sparkle has no feed
  today (`UpdateDelegate.feedURLString` is nil), so it can't update yet.
- Windows, tabs and splits are saved by Ghostty's state restoration
  (`TerminalRestorable.swift`, each pane's `uuid`). Whether macOS restores
  them follows `NSQuitAlwaysKeepsWindows`, which `window-save-state`
  controls; at its default it follows the system's "Close windows when
  quitting an application", which on this Mac doesn't keep them.
- A restored pane starts `+tmux-launch`, whose `claimOrphan`
  (`src/cli/tmux_launch.zig`) reattaches to the session whose
  `@lostty_surface` is the pane's UUID and whose `@lostty_owner` is dead.
  That is how a crash already brings panes back.
- `offerOrphansAtLaunch` skips orphans a restored window already shows, so
  a restart that restores everything shows no prompt.
- Claude's hooks report state by an escape sequence to attached clients
  (`+claude-state`); nothing queues it, so hooks fired while Lostty is down
  are lost. The last state is still in tmux (`@lostty_claude`,
  `@lostty_action`, written by `ClaudeTmuxSync`).
- `+claude-hooks status` reports `partial` when the installed hook commands
  don't match the running binary's; `+claude-hooks install` replaces only
  Lostty's own entries.

## Decisions

| | Decision |
|---|---|
| Trigger | Lostty notices its bundle was replaced and shows **Restart to Update** in the menu bar (and the Lostty app menu). You click it when it suits you. Nothing restarts on its own. |
| Claudes | Never wait for them. After the restart, each session's last Claude state is read back from tmux, so rows stay right. |
| Bad build | `install-skins.sh` keeps the previous app as `/Applications/Lostty (previous).app`. **Go Back to Previous Build** (menu bar) swaps it back and restarts; `macos/install-skins.sh --previous` does the same from any shell when the new build won't run. No automatic rollback. |
| What comes back | Exactly what you had: every window, tab and split, reattached, no prompt. A real crash still prompts. |
| Builds | The installed app and Debug builds alike; each only restarts into the sessions it owns. |
| Window restore | A restart always restores windows, whatever the macOS setting; a normal Quit keeps following `window-save-state`. |
| Sparkle | Its install-and-relaunch goes through the same restart. |
| Claude hooks | After a restart, if the hooks were installed and are now `partial`, Lostty reinstalls them quietly. It never installs them where there were none. |

## Design

### Restart (`macos/Sources/Features/Restart/`)

`LosttyRestart.restart(reason:)`:

1. Writes `~/Library/Application Support/Lostty/restart.json`: this pid, the
   session ids it owns, each one's `@lostty_claude`/`@lostty_action`, Stay
   Awake's state, the hooks' status, and the time.
2. Sets `NSQuitAlwaysKeepsWindows = true` in Lostty's defaults, so macOS
   restores the windows at the next launch.
3. Starts a detached helper (`/bin/sh -c 'while kill -0 <pid>; do sleep 0.2;
   done; open -n "<bundle path>"'`, its own session via `setsid`, so it
   outlives Lostty) that reopens the app once this one has exited.
4. Terminates with `isRestarting = true`. `applicationShouldTerminate` then
   asks nothing (no Stay Awake or "Quit Lostty?" alert), and
   `applicationWillTerminate` skips `endSessions` and Stay Awake's quit. Each
   window's state is saved first (as `updaterWillRelaunchApplication` does).

At launch, if `restart.json` exists, names a dead pid, and is under 2
minutes old:

- `NSQuitAlwaysKeepsWindows` goes back to what `window-save-state` says.
- Before `ClaudeTmuxSync` or `TmuxOptionSync` can clear "sessions whose
  Lostty is gone", the saved Claude states seed `ClaudeRuntime` for those
  panes (by `@lostty_surface`, the same UUIDs the restored panes have).
- Stay Awake resumes from the saved state.
- If the hooks were installed and are now `partial`, run
  `+claude-hooks install`.
- The file is deleted.

An older file or another pid's file is ignored and deleted; the orphan
prompt works as today.

### Noticing a new build (`BundleWatch`)

At launch Lostty notes its executable's inode and modification time. A
check on each menu open and every 30 seconds compares them again; once they
differ, the menu bar icon gets a small up-arrow badge and both menus show
**Restart to Update**, which says "keeps your terminals". Sparkle's
"install and relaunch" calls `LosttyRestart.restart(reason: .sparkle)`
instead of quitting normally: steps 1, 2 and 4, but not the helper (3),
because Sparkle relaunches the app itself once it has installed the new one;
a helper of ours could open the old build first.

### Previous build

`install-skins.sh` moves the current `/Applications/Lostty.app` to
`/Applications/Lostty (previous).app` (replacing an older one) before
copying the new one in. `install-skins.sh --previous` swaps the two back and,
if a Lostty is running, asks it to restart (`osascript … restart to update`),
else opens it. The menu bar shows **Go Back to Previous Build** while a
previous build exists and this one is the newer.

### AppleScript

A `restart to update` command in `Ghostty.sdef` (Lostty's suite) calls
`LosttyRestart.restart(reason: .script)`, for the install script's
`--previous` and for agents.

### Agents

`macos/AGENTS.md` gets: "After Mac changes: `macos/install-skins.sh`, then
Restart to Update in the Lostty menu bar. Never Quit Lostty to update: Quit
ends every session."

## Errors

- The helper can't start: Restart says so and nothing quits.
- The new build doesn't reopen within 30 seconds: nothing automatic; the
  sessions keep running, orphaned, and the next launch (either build)
  reattaches them via restoration or the prompt.
- A restored pane whose session ended meanwhile starts a fresh session in
  its folder, as restoration does today.

## Testing

- Unit: `restart.json` round trip and its 2-minute / dead-pid checks;
  `applicationWillTerminate`'s choice (restart vs quit) as a pure function;
  seeding Claude state from saved options before the clear runs; the
  bundle-change check.
- By hand on this Mac: 6 terminals (tabs and a split, one Claude working,
  one waiting), `install-skins.sh`, Restart to Update: same layout,
  same sessions, rows right, Stay Awake still on. Then `--previous`.
- A real `kill -9`: the "Reopen N sessions?" prompt as today.

## Out of scope

- Turning Sparkle's feed on.
- Automatic rollback.
- Restarting on its own when idle.
