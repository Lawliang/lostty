# Lostty menu bar and Stay Awake for Phone — design

Status: draft for review (2026-10-12)

Builds on docs/superpowers/specs/2026-10-09-lostty-mobile-design.md (phone
attaches to the Mac's `tmux -L lostty` sessions over SSH through Tailscale)
and docs/superpowers/specs/2026-10-11-lostty-mobile-onboarding-design.md
(Phone Access window, pairing), which listed "keeping the Mac awake with the
lid closed" as out of scope. This spec brings it in.

## Goal

The iPhone can reach the Mac's terminals while the MacBook is closed in a bag
or left idle on a desk. A Lostty icon in the menu bar turns this on and off,
and also carries general Lostty shortcuts.

### Success criteria

- With Stay Awake on, closing the lid on battery does not sleep the Mac: the
  phone, on LTE, attaches to a session and Claude keeps working in it.
- While the lid is closed, Low Power Mode is on; opening the lid restores the
  customer's previous Low Power Mode setting.
- Turning Stay Awake off, quitting Lostty, a safety cut-off, the timer ending,
  or relaunching after a crash all leave `disablesleep` and `lowpowermode` as
  they were before Stay Awake turned on.
- Nothing asks for a password after the one-time permission install.
- The menu shows whether a phone is attached right now and which Claude
  sessions are waiting.
- While Stay Awake is on, losing working Wi-Fi (gone, or connected with no
  internet) moves the Mac to the customer's iPhone hotspot within 2 minutes,
  lid closed, without anyone touching the Mac; the phone is told and its
  terminal keeps working. Back in range of known Wi-Fi, the Mac returns to
  it within about 5 minutes (§10).

## Facts this design rests on

- With the lid closed, the built-in display and keyboard backlight turn off by
  themselves even when the Mac stays awake.
- A power assertion (`IOPMAssertionCreateWithName`, `caffeinate`) prevents
  idle sleep but not lid-close sleep on battery without an external display.
  Only `pmset -a disablesleep 1` does, and it needs root. It also prevents
  idle sleep.
- `pmset -a lowpowermode 0|1` sets Low Power Mode and needs root.
- `disablesleep` persists across reboots until something resets it.
- Phone Access runs admin steps through `NSAppleScript` `do shell script …
  with administrator privileges` (`PhoneAccessAdmin.swift:37`); there is no
  privileged helper. The app is not sandboxed.
- Quitting Lostty ends the tmux sessions it owns
  (`AppDelegate.swift:483`, `TmuxClient.endSessions`); the tmux server and
  phone-started sessions survive.
- Claude state is tracked per Mac pane in `ClaudeRuntime.shared` (`phases`,
  `awaiting`); there is none for sessions with no Mac pane.
- There is no existing menu bar item, no power code, and no detection of an
  attached phone.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Name in the UI | "Stay Awake for Phone" | Says what it does and who it is for |
| Turning it on | Manual, with a duration: until I turn it off (default), 1 h, 4 h, 8 h | Timer covers "forgot it was on" |
| What it blocks | Lid-close and idle sleep | The promise is "the Mac stays reachable" |
| Low Power Mode | On only while the lid is closed, previous setting restored on open | Nobody is looking; runs cooler in a bag |
| Safety cut-offs | Battery floor (default 15%, on battery only) and critical thermal state | A bag can drain or cook the Mac |
| After a cut-off | Stays off until turned on again | No surprise re-arming |
| Root access | One-time sudoers rule for seven exact `pmset` commands | Cut-offs and lid changes happen with nobody to type a password |
| Restoring | Record previous `disablesleep` and `lowpowermode`, restore them | Respects a hand-set `disablesleep 1` |
| Quitting Lostty | Turns it off after a confirmation | Lostty owns the setting; its sessions end anyway |
| Crash | Next launch restores from the saved record | `disablesleep` would otherwise outlive Lostty |
| Available when | A phone is paired and the permission is installed | Otherwise it keeps the Mac awake for nothing |
| Icon | Template axolotl; filled while on; dot when a Claude is waiting | Readable at a glance, follows menu bar appearance |
| Icon visibility | Always shown; checkbox in Phone Access to hide | It is a general Lostty menu |
| Settings storage | `UserDefaults`, like Phone Access and Claude usage | Lostty features don't add Ghostty config keys |
| Phone push | `PhoneNotifier` hook, no-op until "Lostty phone push" lands | Push needs APNs work of its own |
| Wi-Fi gone or no internet | Lostty joins the hotspot itself (CoreWLAN) after 20 s / 60 s | macOS refuses to join with the lid closed (§10) |
| Which hotspot | Chosen once in Phone Access, password stored by Lostty | Names change; macOS's saved password can't be used |
| Switching back | Lostty leaves the hotspot after 2 strong scans of known Wi-Fi | Saves the phone's data and battery |

## Architecture

```
PowerMonitor ──events──▶ StayAwakeModel ──actions──▶ StayAwakeStore ──▶ PowerControl (sudo -n pmset)
 lid, battery,             (pure rules)                 │  restore record      PhoneNotifier (no-op)
 thermal, timer                                         │  (UserDefaults)      UNUserNotificationCenter
                                                        ▼
LosttyStatusItem ◀── StayAwakeStore, PhoneAccessStore, ClaudeRuntime, AttachedPhones
```

`Hotswitch` (§10) runs beside `StayAwakeStore` while it is on. New code
lives in `macos/Sources/Features/StayAwake/` and
`macos/Sources/Features/MenuBar/`, tests in `macos/Tests/StayAwake/` and
`macos/Tests/MenuBar/`.

### 1. PowerControl

A protocol with a real implementation and a test fake.

- `read() -> PowerSettings` parses `pmset -g` for `disablesleep` (shown as
  `SleepDisabled`) and `pmset -g custom` for `lowpowermode` per power source
  (battery and AC), so "Low Power Mode: Only on Battery" is restored as it was.
- `run(_ command)` runs `/usr/bin/sudo -n /usr/bin/pmset` with one of seven
  argument lists: `-a disablesleep 0|1`, `-a lowpowermode 1` (lid closed),
  `-b lowpowermode 0|1` and `-c lowpowermode 0|1` (restore).
  `-n` never prompts: a missing rule fails at once with
  `PowerControlError.permissionMissing`; any other non-zero exit is
  `PowerControlError.failed(stderr)`.

### 2. PowerMonitor

Reads `PowerState { lidClosed, onBattery, batteryPercent, thermal }`; the
store polls it every 5 s while Stay Awake is on (and when the menu opens).
Polling is simpler than three notification sources and nothing needs the
state while Stay Awake is off.

- Lid: `AppleClamshellState` on `IOPMrootDomain`.
- Battery: `IOPSCopyPowerSourcesInfo`.
- Thermal: `ProcessInfo.thermalState`.

### 3. StayAwakeModel

A value type with no system calls. `handle(_ event) -> [Action]`.

Events: `turnOn(duration)`, `turnOff`, `power(PowerState)`, `tick(now)`,
`quit`, `launch(record)`, `controlFailed(error)`.

Actions: `saveRecord(PowerSettings)`, `clearRecord`, `setDisableSleep(Bool)`,
`setLowPowerMode(Bool)`, `notifyMac(String)`, `notifyPhone(String)`.

State: `off(lastReason: Reason?)` or `on(until: Date?, record, lowPowerApplied)`.

Rules:

- `turnOn` from `off`: save the current settings as the record, then
  `setDisableSleep(true)`. If the lid is already closed, apply Low Power Mode.
- Lid closes while on: `setLowPowerMode(true)` unless the record already had
  it on. Lid opens: `setLowPowerMode(record.lowPowerMode)`.
- Turning off for any reason: `setLowPowerMode(record.lowPowerMode)` if it
  was applied, `setDisableSleep(record.disableSleep)`, `clearRecord`.
- Cut-offs, each turning off with a `Reason`:
  - battery: `onBattery && batteryPercent <= floor`;
  - heat: `thermal == .critical`;
  - timer: `tick` at or after `until`.

  Each sends `notifyMac` and `notifyPhone` ("Mac is going to sleep — battery
  at 15%") before the restore actions.
- `launch(record)` with an active record: restore it and `clearRecord`; no
  notification unless restoring fails.
- `controlFailed(.permissionMissing)` while turning on: stay `off` with reason
  `.permissionMissing` and `clearRecord` (nothing was changed).
- `controlFailed` while restoring: keep the record (retried at next launch)
  and `notifyMac` with the manual undo command.

### 4. StayAwakeStore

`@MainActor ObservableObject` that owns the model, feeds it `PowerMonitor`
updates and a one-minute timer while on, and performs actions.

- The restore record (`disableSleep`, `lowPowerMode`, `active`) is saved to
  `UserDefaults` before any `pmset` change.
- Publishes `isOn`, `until`, `lastReason`, `available` (phone paired and
  permission installed), and the latest `PowerState` for the status line.
- Battery floor (10/15/20/30%) and the last chosen duration are
  `UserDefaults` values.

### 5. AttachedPhones

Answers "which sessions have a phone attached right now", refreshed when the
menu opens.

- Runs `tmux -L lostty list-clients -F '#{client_pid}\t#{session_name}'`.
- Keeps clients whose parent chain (walked with `sysctl` `KERN_PROC_PID`)
  reaches a process named `sshd` before `launchd`.
- Parsing and the ancestry walk take injected inputs so they can be tested.
  Any failure yields an empty list.

### 6. PhoneNotifier

Protocol with `notify(_ text: String)`. The only implementation for now does
nothing. "Lostty phone push" replaces it with APNs.

### 7. LosttyStatusItem

An `NSStatusItem` with an `NSMenu` rebuilt in `menuNeedsUpdate`.

```
◉ Stay Awake for Phone                ▸  Until I turn it off / 1 hour / 4 hours / 8 hours
   2h 40m left · 64% on battery · normal
   (or: Turned off at 15% battery · 9:41 PM)
   (or: Needs the stay-awake permission — Set Up…)
───────────────
Phones
   iPhone — attached to api-server
───────────────
Claude
   ● idfk — waiting for you
   ○ api-server — working
───────────────
New Window
Phone Access…
Pair a Phone…
Battery Floor                         ▸  10% / 15% / 20% / 30%
```

- The toggle is disabled, with "Set Up Phone Access…" beneath it, until a
  phone is paired and the permission is installed.
- Claude rows come from `ClaudeRuntime.shared`; clicking one focuses that
  window and pane the same way clicking a Lostty notification does.
- Icon: a template image of the axolotl, an outline when off and filled when
  on, with a dot when `ClaudeRuntime.shared.awaiting` is not empty.

### 8. Phone Access changes

- New checklist row "Stay-awake permission" with an Install button. The admin
  script writes the rule to a temporary file, checks it with
  `visudo -cf <tmp>`, then installs it as `/etc/sudoers.d/lostty`, owned by
  root, mode 0440:

  ```
  <user> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a lowpowermode 1, /usr/bin/pmset -b lowpowermode 0, /usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset -c lowpowermode 0, /usr/bin/pmset -c lowpowermode 1
  ```

  `<user>` is `NSUserName()`. The row is ✓ when `sudo -n -l /usr/bin/pmset -a
  disablesleep 0` succeeds.
- When the checklist's first admin step runs, a missing rule is installed in
  the same password prompt.
- Turn Off Phone Access turns Stay Awake off first, then removes
  `/etc/sudoers.d/lostty` in its existing admin prompt.
- Checkbox "Show Lostty in the menu bar", on by default.

### 9. AppDelegate

- Installs `LosttyStatusItem` at launch when the checkbox is on.
- Runs `launch(record)` before anything else touches power.
- In `applicationShouldTerminate`, while Stay Awake is on, asks: "Stay Awake
  for Phone is on. Quitting lets the Mac sleep and ends this Mac's sessions."
  On quit, restores settings before sessions end.

### 10. Hotswitch (Wi-Fi to iPhone hotspot)

Rewritten 2026-10-13 after the spike below. "Hotswitch" in code; in the UI,
"Switch to iPhone hotspot when Wi-Fi drops".

**Why Lostty does it.** macOS won't do it with the lid closed. On
2026-10-13 Wi-Fi dropped at 6:42 PM with Stay Awake on and "Ask to join
hotspots" set to Ask to Join: for 72 minutes macOS only offered join
prompts, refused them with "Screen is locked or Device sleeping" once the
lid closed, and joined at 7:54 PM when the lid opened.

**Spike results (2026-10-13, throwaway app joining through CoreWLAN).**

- The iPhone's hotspot is invisible to `scanForNetworks` unless Personal
  Hotspot → "Allow Others to Join" is on (5 scans, lid open, phone beside
  the Mac: 0 found). With it on: found at −33 dBm.
- `associate(to:password: nil)` (macOS's saved password) fails with
  `tmpErr` (-3900) in under a second. With the password passed in, it joins
  in 0.8–1.1 s and the internet works through the hotspot 4 s later.
- Lid closed, display off, `disablesleep 1`: the join worked the same. The
  screen was not locked (this Mac locks 8 h after the display sleeps), so
  joining while locked is untested.
- A failed `associate` leaves the Mac on no network.
- `disassociate()` from the hotspot: macOS rejoined the known Wi-Fi within
  30 s by itself, internet working.
- Scanning and network names need Location, and a re-signed ad-hoc build
  loses it (the spike's rebuild went back to "not asked yet").

**When it switches.** Only while Stay Awake is on.

- Wi-Fi gone (no network, and no probe getting through, so Ethernet
  counts) for 20 s, or on Wi-Fi with every probe failing for 60 s. The probe is a GET to `http://captive.apple.com/hotspot-detect.html`
  every 15 s that must return 200 with "Success".
- Not when already on the hotspot, not within 10 minutes of the last switch
  to it.
- Scan for the hotspot, then associate with the stored password. Success:
  phone note "Moved to your iPhone hotspot", menu status line. Failure
  (not found, refused, or no internet within 60 s): phone note "Couldn't
  move to your iPhone hotspot" once per outage, retry every 2 minutes, and
  the Lostty log gets the CoreWLAN error and whether the screen was locked.
- If the hotspot itself drops, do nothing: macOS takes whatever it finds.

**Back to Wi-Fi.** While on the hotspot, scan every 2 minutes. After 2
scans in a row that find a known network (CoreWLAN profiles, not the
hotspot) at −70 dBm or better, `disassociate()` and let macOS rejoin it.
If there's no internet within 60 s, go back to the hotspot and ignore that
network for 15 minutes. Quiet in-app note "Back on <network>". Turning
Stay Awake off while on the hotspot also disassociates.

**Setup (Phone Access).** One row "Switch to iPhone hotspot when Wi-Fi
drops" with:

- a hotspot picker of known networks, preselecting the one named like a
  paired phone (here "Law");
- a password field, stored as a generic password in the login keychain
  (service "Lostty hotspot", account = network name);
- a Location row that asks once and shows ✓ or "Allow in System Settings";
- the hint "On the iPhone: Personal Hotspot → Allow Others to Join".

The switch stays off until all three are set, then turns on by itself once.
Settings live in `UserDefaults` like the rest.

**Stable signing.** Location and the keychain item both follow the app's
code signature; `install-skins.sh` signs ad-hoc, which changes on every
install, so each update would drop Location and make the keychain ask
again with nobody there. `install-skins.sh` signs with the "Apple
Development" identity when the keychain has one (ad-hoc otherwise).

**Phone heartbeat.** Tailscale keeps the Mac's address across networks, but
a dead link can take minutes to notice. The phone runs `true` over its SSH
connection every 20 s; 3 misses in a row close the connection, which
reconnects with the usual backoff.

**Code.**

- `HotswitchModel` (pure, in `LosttyRemote` so `swift test` covers it):
  events `tick(now, Link)`, `stayAwake(Bool)`, `joined(Result)`,
  `scanned([Sighting])`; actions `join`, `leave`, `scan`, `notifyPhone`,
  `note`, `log`. `Link` is `.none`, `.wifi(name, internet: Bool?)`.
- `Hotswitch` (`Features/StayAwake/`): a 5 s timer while Stay Awake is on,
  the probe, CoreWLAN, the keychain, and the model's actions.
- `HotswitchSettings` + the Phone Access row; the menu's status line reads
  `Hotswitch.status`.
- Phone: a heartbeat task beside each attach and the list watch.

## Error handling

| Case | Behavior |
|---|---|
| `sudo -n` fails when turning on | Stays off; menu shows "Needs the stay-awake permission — Set Up…" |
| Restore fails (quit, cut-off, turn off) | Record kept, retried at next launch; Mac notification with `sudo pmset -a disablesleep 0` |
| Lostty force-quit and never reopened | Mac stays awake; the docs give the one-line undo |
| Battery info unavailable (desktop Mac) | No battery cut-off; status line omits battery |
| `list-clients` fails or tmux not running | Phones section shows paired phones without "attached" |
| Hotspot not visible or association fails | Phone note once per outage; status line "Couldn't reach iPhone hotspot"; retries every 2 minutes |
| Location or keychain access denied | `Hotswitch` stays idle; Phone Access row shows what to allow |

## Testing

- `StayAwakeModel` unit tests for every rule: restore of a hand-set
  `disablesleep 1`, Low Power Mode only while the lid is closed, battery floor
  only on battery, heat, timer, no re-arming, crash record at launch,
  permission missing, restore failure keeping the record, notifications
  emitted before restore actions.
- `PowerControl` parsing of `pmset -g` output samples.
- The sudoers line and admin script text.
- `AttachedPhones` parsing and ancestry with fake process tables.
- `HotswitchModel` unit tests: 20 s with no network, 60 s of failed
  probes, not when already on the hotspot, not when Stay Awake is off, the
  10-minute cooldown, one failure note per outage with 2-minute retries,
  leaving after 2 strong scans, going back and ignoring a network with no
  internet for 15 minutes, leaving when Stay Awake turns off.
- Manual checklist on a MacBook:
  - turn on, close the lid on battery, attach from the phone over LTE, run a
    command, open the lid; `pmset -g` shows the previous Low Power Mode;
  - set the floor above the current battery, unplug, see the cut-off and the
    restored settings;
  - `kill -9` Lostty while on, relaunch, `pmset -g` shows `SleepDisabled 0`;
  - set `disablesleep 1` by hand, turn on then off, it is still 1;
  - Turn Off Phone Access removes `/etc/sudoers.d/lostty`;
  - lid closed, router Wi-Fi off: the Mac lands on the hotspot and the phone
    reattaches;
  - lid closed, router uplink unplugged: within ~75 s the Mac moves to the
    hotspot and the phone reattaches.

## Docs

- `docs/lostty-mobile-host-setup.md` step 7: point to Stay Awake for Phone;
  keep the manual `pmset` lines as the undo.
- `docs/lostty-mobile-phone-access.md`: replace "only while the Mac is awake
  and Lostty is open" with how to use Stay Awake, and add the force-quit undo
  to troubleshooting and the clean-up list. Mention the hotspot setting and
  picker.

## Out of scope

- Push to the phone (next spec, "Lostty phone push": APNs straight from the
  Mac to the Lostty iPhone app, device token handed over on connect; fires on
  battery, heat and timer cut-offs).
- Tailscale status, skins, and Claude state for sessions started from the
  phone.
- A privileged helper (`SMAppService`).
- Turning on the iPhone's Personal Hotspot remotely; a data or battery
  guard while on the hotspot.
- Always-on hosts such as a Mac mini (nothing to build).

## Risks

- `AppleClamshellState` must stay readable (and the Mac awake) with the lid
  closed while `disablesleep` is set; the spike checks this first.
- A closed MacBook can still get hot under heavy builds; the critical thermal
  cut-off is the backstop, not a guarantee.
- Joining while the screen is locked is untested (§10); a refusal shows up
  as "Couldn't move" notes and a logged CoreWLAN error.
- "Allow Others to Join" must stay on, so anyone with the password can join
  the hotspot.
- Each switch to the hotspot uses cellular data, and the phone's battery
  drains faster while it is the Mac's uplink.
- macOS may change `pmset` keys or output; `PowerControl` parsing tests pin
  today's format and a failed read keeps Stay Awake off.
