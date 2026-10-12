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
  internet) moves the Mac to the customer's iPhone hotspot without anyone
  touching the Mac. The "connected with no internet" half depends on the
  spike in §10.

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
| Root access | One-time sudoers rule for four exact `pmset` commands | Cut-offs and lid changes happen with nobody to type a password |
| Restoring | Record previous `disablesleep` and `lowpowermode`, restore them | Respects a hand-set `disablesleep 1` |
| Quitting Lostty | Turns it off after a confirmation | Lostty owns the setting; its sessions end anyway |
| Crash | Next launch restores from the saved record | `disablesleep` would otherwise outlive Lostty |
| Available when | A phone is paired and the permission is installed | Otherwise it keeps the Mac awake for nothing |
| Icon | Template axolotl; filled while on; dot when a Claude is waiting | Readable at a glance, follows menu bar appearance |
| Icon visibility | Always shown; checkbox in Phone Access to hide | It is a general Lostty menu |
| Settings storage | `UserDefaults`, like Phone Access and Claude usage | Lostty features don't add Ghostty config keys |
| Phone push | `PhoneNotifier` hook, no-op until "Lostty phone push" lands | Push needs APNs work of its own |
| Wi-Fi gone | macOS auto-joins the iPhone hotspot; Lostty checks the setting | macOS already does it |
| Wi-Fi with no internet | Lostty switches to the hotspot after ~60 s, if the spike confirms CoreWLAN can | macOS stays on a broken network |
| Which hotspot | Chosen once from known networks in Phone Access | Names change; guessing breaks |
| Switching back | Left to macOS | Flapping would drop the phone's session |

## Architecture

```
PowerMonitor ──events──▶ StayAwakeModel ──actions──▶ StayAwakeStore ──▶ PowerControl (sudo -n pmset)
 lid, battery,             (pure rules)                 │  restore record      PhoneNotifier (no-op)
 thermal, timer                                         │  (UserDefaults)      UNUserNotificationCenter
                                                        ▼
LosttyStatusItem ◀── StayAwakeStore, PhoneAccessStore, ClaudeRuntime, AttachedPhones
```

`HotspotFallback` (§10) runs beside `StayAwakeStore` while it is on. New code
lives in `macos/Sources/Features/StayAwake/` and
`macos/Sources/Features/MenuBar/`, tests in `macos/Tests/StayAwake/` and
`macos/Tests/MenuBar/`.

### 1. PowerControl

A protocol with a real implementation and a test fake.

- `read() -> PowerSettings` parses `pmset -g` for `disablesleep` (shown as
  `SleepDisabled`) and `lowpowermode`.
- `set(disableSleep: Bool)` and `set(lowPowerMode: Bool)` run
  `/usr/bin/sudo -n /usr/bin/pmset -a disablesleep|lowpowermode 0|1`.
  `-n` never prompts: a missing rule fails at once with
  `PowerControlError.permissionMissing`; any other non-zero exit is
  `PowerControlError.failed(stderr)`.

### 2. PowerMonitor

Publishes `PowerState { lidClosed, onBattery, batteryPercent, thermal }`.

- Lid: `AppleClamshellState` on `IOPMrootDomain`, updated by an
  `IOServiceAddInterestNotification` for `kIOPMMessageClamshellStateChange`.
- Battery: `IOPSCopyPowerSourcesInfo`, updated by
  `IOPSNotificationCreateRunLoopSource`.
- Thermal: `ProcessInfo.thermalState` and
  `thermalStateDidChangeNotification`.

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
  <user> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a lowpowermode 0, /usr/bin/pmset -a lowpowermode 1
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

### 10. Wi-Fi fallback

Two halves, the second gated on a spike.

**Wi-Fi gone.** macOS can join the iPhone's hotspot by itself when no known
Wi-Fi is available (Wi-Fi settings, joining hotspots automatically). Phone
Access gets a checklist row "Joins your iPhone's hotspot automatically" that
reads the setting and, when it is off, opens Wi-Fi settings. How to read the
setting is a spike question; if it can't be read, the row is informational
with an Open Settings button and no ✓.

**Wi-Fi with no internet.** `HotspotFallback`, active only while Stay Awake is
on:

- Watches `NWPathMonitor` and probes reachability (an HTTPS HEAD to a fixed
  captive-portal check URL) every 15 s while on Wi-Fi.
- After 60 s on Wi-Fi with every probe failing, and the current network is
  not the chosen hotspot, it associates with the chosen hotspot through
  CoreWLAN (`CWInterface.associate(to:password:)`), password from the
  system keychain entry for that network.
- Does not switch again for 10 minutes after a switch, and never switches
  back; macOS rejoins known Wi-Fi on its own.
- Records the switch for the status line ("Moved to iPhone hotspot · 9:41
  PM"), sends `notifyMac` and `notifyPhone`.
- The rules (timing, cooldown, "already on hotspot") live in a pure
  `HotspotFallbackModel` like `StayAwakeModel`; CoreWLAN and the probe sit
  behind protocols.

Phone Access gets a "Your iPhone's hotspot" picker listing known Wi-Fi
networks (CoreWLAN known profiles), saved in `UserDefaults`. Without a choice,
`HotspotFallback` stays idle and the menu says so.

**Spike (first task of the plan, throwaway).** On the MacBook, with Stay Awake
set by hand (`sudo pmset -a disablesleep 1`) and the lid closed:

1. Turn the router's Wi-Fi off: does macOS join the iPhone hotspot, and how
   long does it take? Can Lostty read the "join hotspots" setting?
2. Keep Wi-Fi up with no internet (unplug the router's uplink): from a small
   script, can CoreWLAN see the hotspot (Personal Hotspot with "Allow Others
   to Join" off, so only Instant Hotspot advertises it), read its password,
   and associate, without any prompt? What permission does reading network
   names need (Location Services)?

If 2 fails, the "no internet" half and the hotspot picker are cut from this
spec and the plan; the checklist row stays. The results are written into
this section before implementation continues.

## Error handling

| Case | Behavior |
|---|---|
| `sudo -n` fails when turning on | Stays off; menu shows "Needs the stay-awake permission — Set Up…" |
| Restore fails (quit, cut-off, turn off) | Record kept, retried at next launch; Mac notification with `sudo pmset -a disablesleep 0` |
| Lostty force-quit and never reopened | Mac stays awake; the docs give the one-line undo |
| Battery info unavailable (desktop Mac) | No battery cut-off; status line omits battery |
| `list-clients` fails or tmux not running | Phones section shows paired phones without "attached" |
| Hotspot not visible or association fails | Stays on the current network; status line "Couldn't reach iPhone hotspot"; retries after the cooldown |
| Location or keychain access denied | `HotspotFallback` stays idle; Phone Access row shows what to allow |

## Testing

- `StayAwakeModel` unit tests for every rule: restore of a hand-set
  `disablesleep 1`, Low Power Mode only while the lid is closed, battery floor
  only on battery, heat, timer, no re-arming, crash record at launch,
  permission missing, restore failure keeping the record, notifications
  emitted before restore actions.
- `PowerControl` parsing of `pmset -g` output samples.
- The sudoers line and admin script text.
- `AttachedPhones` parsing and ancestry with fake process tables.
- `HotspotFallbackModel` unit tests: switches only after 60 s of failed
  probes on Wi-Fi, not when already on the hotspot, not without a chosen
  hotspot, not when Stay Awake is off, honours the 10-minute cooldown, never
  switches back.
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
- Switching back from the hotspot to Wi-Fi (left to macOS), and turning on
  the iPhone's Personal Hotspot remotely.
- Always-on hosts such as a Mac mini (nothing to build).

## Risks

- `kIOPMMessageClamshellStateChange` delivery while `disablesleep` is set
  needs checking on hardware first; polling `AppleClamshellState` every few
  seconds while on is the fallback.
- A closed MacBook can still get hot under heavy builds; the critical thermal
  cut-off is the backstop, not a guarantee.
- CoreWLAN may not see or join an Instant Hotspot network that isn't
  broadcasting, or may need prompts nobody can answer with the lid closed;
  the spike decides whether the "no internet" half ships.
- Each switch to the hotspot uses cellular data, and the phone's battery
  drains faster while it is the Mac's uplink.
- macOS may change `pmset` keys or output; `PowerControl` parsing tests pin
  today's format and a failed read keeps Stay Awake off.
