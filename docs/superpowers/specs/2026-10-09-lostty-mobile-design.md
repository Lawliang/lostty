# Lostty Mobile — design

Status: draft for review (2026-10-09)

## Goal

Prompt Claude Code from an iPhone while away from the desk, in a Lostty that
looks and behaves like desk Lostty: same renderer, same skins, same Claude
trace and Ready for response. Any session open on the Mac can be picked up on
the phone, and handed back.

### Success criteria

- Every Mac Lostty window is reachable from the phone, with no change to how
  the desk feels (Cmd+N, closing windows, scrolling, skins, Claude features).
- On the phone: open the app, pick a session by project name, type to Claude,
  see the same skin and trace as the desk.
- Losing signal, switching Wi-Fi/cellular or backgrounding the app never kills
  a session; reopening the app reattaches where it left off.
- A push notification arrives when Claude finishes or asks for permission
  while the phone app is closed.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Phone renderer | Real Lostty core (libghostty) | "As close as possible" to desk Lostty |
| Unix user | The user's own account | Behavior identical to the laptop; phone is trusted |
| Which windows are reachable | All of them | No mode to remember |
| Session keeper | tmux on a private socket (`tmux -L lostty`) | Mature, multi-client, `+claude-state` already supports it |
| Host machine | The MacBook, carried closed in a bag | No new hardware; a Mac mini later needs no redesign |
| Network | Tailscale + SSH | Works on any network pair, including the phone's hotspot |
| Distribution | Personal install via Xcode/TestFlight | No App Store release |

## Architecture

```
iPhone Lostty ──SSH over Tailscale──▶ MacBook sshd ──▶ tmux -L lostty ◀── Mac Lostty windows
 (libghostty, remote IO)                                  │ session per window
                                                          └─ zsh → claude (hooks → +claude-state, ntfy)
```

Four parts:

1. **Mac host** — setup only (Tailscale, Remote Login, tmux, sleep, hotspot).
2. **Mac Lostty** — every window runs inside its own session on a private tmux;
   shell signals are passed through tmux.
3. **Lostty core** — a `remote` termio backend so a surface can be driven by
   bytes from the app instead of a local process.
4. **iPhone app** — GhosttyKit for iOS plus a shared Swift package
   (`LosttyRemote`) for SSH, session listing and reconnect.

## 1. Mac host

- Tailscale on Mac and iPhone, starting at login; two-factor on the Tailscale
  account.
- Remote Login on; password authentication off (drop-in under
  `/etc/ssh/sshd_config.d/`), key-only.
- `brew install tmux` (not installed today).
- Bag mode: closed-lid awake via `pmset disablesleep` or Amphetamine with a
  battery floor; Mac Wi-Fi set to auto-join the iPhone's hotspot.
- Accepted costs: heat with no airflow during heavy builds, battery drain on
  both devices, cellular data.

## 2. Mac Lostty + tmux

Lostty depends on three shell signals: `GHOSTTY_ACTION_PWD` (OSC 7, drives
auto-skin), `GHOSTTY_ACTION_COMMAND_FINISHED` (OSC 133, ends the trace) and
`GHOSTTY_ACTION_SET_USER_VAR` (OSC 1337, carries `LOSTTY_CLAUDE`,
`LOSTTY_USAGE` and skin requests). tmux consumes OSC 7 and OSC 133 rather than
forwarding them; `+claude-state` already wraps its sequence for tmux
(`src/cli/claude_state.zig`). Ghostty's automatic shell integration is not
reliably injected into shells started by tmux.

Design:

- **Private tmux.** All Lostty sessions live on `tmux -L lostty` with a config
  Lostty ships and owns (not `~/.tmux.conf`): no status bar, `mouse on` with
  normal-feeling scroll and select, prefix not bound to Ctrl-B, `window-size
  latest`, `allow-passthrough on`, `set-clipboard on`.
- **Launch.** Each new surface's `command` (existing `ghostty_surface_config_s.command`)
  becomes a small launcher that creates a new session, sets `LOSTTY_SURFACE`
  and `LOSTTY_BIN` in the session environment, and starts the login shell.
- **Naming.** Sessions start with a temporary name and are renamed to the
  project (git root basename, `-2`, `-3` for duplicates) on directory change.
- **Shell snippet.** A zsh snippet, active only inside Lostty's tmux, emits on
  `chpwd`/`precmd`/`preexec`: OSC 7, OSC 133 prompt/command marks, and a
  `LOSTTY_PROJECT` user var (git root path), each wrapped in tmux DCS
  passthrough. Passthrough reaches every attached client, so the phone gets
  the same signals.
- **Lifecycle.** Closing a window kills its session; quitting Lostty kills all
  of them (desk behavior unchanged). After a crash, surviving sessions are
  offered for reopening on next launch. Phone-created sessions do not open
  Mac windows; a command palette entry "Open session…" attaches one.
- **Fallback.** If tmux is missing or the launcher fails, the window opens a
  plain local shell and shows a small notice.

## 3. Lostty core: `remote` termio backend

Today `src/termio/backend.zig` has one kind, `exec`, which spawns a local
process with a pty. iOS cannot spawn processes.

- New `Kind.remote` and `src/termio/Remote.zig`. It spawns nothing, skips
  termios polling, shell-integration injection and child-pid cwd lookup.
- Surface config gains an IO mode (`local` default, `remote`) and two
  callbacks: `write(userdata, bytes, len)` for keyboard/paste/terminal replies,
  and `resize(userdata, cols, rows, width_px, height_px)`.
- New C API: `ghostty_surface_io_feed(surface, bytes, len)` pushes received
  bytes through the same stream path `exec` uses (thread-safe);
  `ghostty_surface_io_disconnected(surface)` shows a quiet "reconnecting…"
  state instead of "process exited".
- Kept self-contained (new file plus small switch arms and header additions)
  to keep upstream Ghostty merges easy.

## 4. `LosttyRemote` Swift package

Shared by a Mac debug window and the iPhone app.

- SSH via a pure-Swift client (Citadel on SwiftNIO SSH).
- Auth: ECDSA P-256 key in the Secure Enclave behind Face ID (the Secure
  Enclave does not support ed25519). Host key pinned on first connect, which
  should happen on a trusted network; a mismatch is a hard stop.
- Session list: `tmux -L lostty list-sessions -F …` over an exec channel.
- Attach: pty channel running `tmux -L lostty attach -t <name>` with
  `TERM=xterm-ghostty` and `TERMINFO` pointing at the Lostty.app terminfo.
- Reconnect on app foreground and network change; tmux keeps the session
  while disconnected.

A debug-only Mac menu item opens a remote surface through this package against
`localhost`, proving the core backend and the SSH layer before iOS work.

## 5. iPhone app

- Built from the existing `Ghostty-iOS` target (`macos/Sources/App/iOS/`),
  currently a 50-line placeholder.
- Session list as the home screen, styled freely (tabs, cards, swipe); under
  the hood it is the tmux session list.
- Key row above the keyboard: Esc, Ctrl (sticky), Tab, arrows, and keys
  Claude Code uses often.
- Close-session action (kills the tmux session).

### Skins on the phone

The skin model, presets and TOML parsing port mostly as-is (the files are
macOS-guarded but largely platform-neutral). `ProjectResolver` matches config
paths as strings, which works anywhere, but finds git roots on the local
filesystem, which the phone cannot see. The phone instead takes the git root
from the `LOSTTY_PROJECT` user var, and fetches `~/.config/ghostty-skins/skins.toml`
and textures over SSH on connect.

### Claude features on the phone

Trace and Ready for response port with `ClaudeRuntime`; their signals already
arrive through passthrough. The usage bar ports if `LOSTTY_USAGE` carries
everything it needs (to verify).

## 6. Notifications

A Claude Code `Stop` and `Notification` hook on the Mac posts to ntfy when the
Mac screen is locked (the on-the-go case). The topic name is unguessable and
the message is minimal ("idfk: Claude is waiting"), since public ntfy topics
are readable by anyone who knows the name. The ntfy iOS app delivers the push.
Moving to APNs from the Lostty app is a later option.

## Build order

0. Mac host setup; Blink Shell on the phone as a stand-in.
1. Mac Lostty tmux sessions and signal passthrough.
2. Core `remote` backend and `LosttyRemote`, proven in the Mac debug window.
3. iPhone app: terminal, SSH, session list, key row, reconnect.
4. Skins, Claude features and notifications on the phone.

Each phase gets its own implementation plan.

## Testing

- Zig: feed bytes → expected screen; typed input → write callback; resize →
  resize callback; disconnect state.
- Snippet: escape-sequence wrapping and session naming unit-tested.
- Manual per phase: desk windows behave as today (auto-skin, trace, Ready,
  usage bar, scroll, select, close); Mac debug window runs Claude over SSH;
  phone survives Wi-Fi ↔ cellular and backgrounding.

## Out of scope

MindControl and other Mac-only extras, App Store release, a Mac mini or cloud
host (a later move that needs no redesign), Linux/GTK.

## Risks

- tmux scrollback and selection may never feel exactly like native Lostty;
  `shpool` is the fallback keeper if it is too intrusive.
- A closed MacBook in a bag can get hot under heavy builds.
- `xterm-ghostty` terminfo must be visible to the shell started by tmux on SSH
  attach.
- libghostty's iOS build is a lightly used path upstream; expect build and
  rendering fixes.
