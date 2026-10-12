# Lostty Menu Bar and Stay Awake for Phone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Lostty menu bar icon whose main item, Stay Awake for Phone, keeps a MacBook awake with the lid closed (Low Power Mode on while closed, safety cut-offs, settings restored afterwards) so the iPhone keeps reaching its terminals, plus a Wi-Fi to iPhone hotspot fallback if a hardware spike shows it can work.

**Architecture:** Pure, unit-tested rules (`StayAwakeModel`, `HotspotFallbackModel`, parsers, text builders) sit behind thin system adapters: `pmset` through `sudo -n` with a one-time sudoers rule, IOKit reads polled every 5 s while on, `tmux list-clients` plus a process-ancestry walk, CoreWLAN. `StayAwakeStore` runs the model and performs its actions; `LosttyStatusItem` draws the menu from the stores. Phone Access gains a permission row, a menu bar checkbox and (if the spike passes) a hotspot picker.

**Tech Stack:** Swift 5 mode, AppKit + SwiftUI (macOS 14), IOKit (`IOPMrootDomain`, `IOPowerSources`), `sysctl`, CoreWLAN, Network (`NWPathMonitor`), UserNotifications, Combine, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-12-lostty-menu-bar-stay-awake-design.md`

## Global Constraints

- New Mac-only files under `macos/Sources` and `macos/Tests` are wrapped in `#if os(macOS)` … `#endif` (the iOS target compiles every file under `macos/Sources`). The project uses synchronized folders: new files need no `project.pbxproj` edits.
- Root access only through `/usr/bin/sudo -n /usr/bin/pmset …` with the rule in `/etc/sudoers.d/lostty`, installed by the existing `PhoneAccessAdmin.run` prompt. No privileged helper, no other root commands at runtime.
- The sudoers rule allows exactly these seven commands (refines the spec's four: restoring Low Power Mode per power source keeps "Only on Battery" intact):
  `/usr/bin/pmset -a disablesleep 0`, `/usr/bin/pmset -a disablesleep 1`, `/usr/bin/pmset -a lowpowermode 1`, `/usr/bin/pmset -b lowpowermode 0`, `/usr/bin/pmset -b lowpowermode 1`, `/usr/bin/pmset -c lowpowermode 0`, `/usr/bin/pmset -c lowpowermode 1`.
- The previous `disablesleep` and per-source `lowpowermode` are saved (`UserDefaults.ghostty`, key `LosttyStayAwakeRecord`) before any `pmset` change, and restored on turn off, cut-off, timer end, quit, and at the next launch after a crash.
- Durations: until I turn it off (default), 1 h, 4 h, 8 h. Battery floor choices 10/15/20/30 %, default 15 %, applies on battery only. Heat cut-off at `ProcessInfo.ThermalState.critical`. No re-arming after a cut-off.
- Stay Awake can be turned on only when at least one phone is paired and the permission is installed.
- Settings live in `UserDefaults.ghostty`: `LosttyStayAwakeRecord`, `LosttyStayAwakeFloor`, `LosttyStayAwakeDuration`, `LosttyMenuBarIcon` (default true), `LosttyHotspotSSID`.
- Phone push is a no-op `PhoneNotifier`; "Lostty phone push" is a later spec.
- Copy (exact):
  - Menu toggle: `Stay Awake for Phone`
  - Cut-off notification bodies: `Mac is going to sleep — battery at <n>%.` / `Mac is going to sleep — it's too hot.` / `Mac is going to sleep — Stay Awake time is up.`
  - Restore failure: `Lostty couldn't let your Mac sleep again. Run: sudo pmset -a disablesleep 0`
  - Quit alert: title `Stay Awake for Phone is on.` body `Quitting lets the Mac sleep and ends this Mac's sessions.` buttons `Quit` / `Cancel`
  - Phone Access awake note: `Your phone can reach this Mac only while it's awake. Stay Awake for Phone in the menu bar keeps it awake with the lid closed.`
- Implementer tasks never run the admin prompt, never run real `sudo`/`pmset` changes, never touch `/etc`, Wi-Fi association or tmux sessions. Those are the human's desk checks (Tasks 1 and 11). Tests use fakes and a throwaway `UserDefaults(suiteName:)`.
- Tests: `macos/skins-test.sh <SuiteName>` (build `zig build -Demit-macos-app=false` first only if `macos/GhosttyKit.xcframework` is missing). The Mac Debug app must build (`macos/build.nu --configuration Debug --action build`) and the iOS target must still build: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SYMROOT="$PWD/macos/build" CODE_SIGNING_ALLOWED=NO build`.
- Commits: stage files by path (never `default.profraw`, never other people's work in progress); end each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never create a PR or issue. swiftlint is not installed.

## Review Focus

1. **"Low Power Mode: Only on Battery"** (a common System Settings choice: battery 1, AC 0) must come back exactly so after Stay Awake, never flattened to one value. Pinned by `PowerParseTests.readsLowPowerPerSource` (Task 2) and `StayAwakeModelTests.restoresLowPowerPerSource` (Task 3).
2. **A user name that could inject into sudoers** (spaces, commas, `ALL`, newlines, a leading `-`) must produce no rule at all. Pinned by `StayAwakeSudoersTests.refusesUnsafeUserNames` (Task 2).
3. **Turning on while already below the floor or overheating** must not flip `disablesleep` on and straight off again; it stays off with the reason shown. Pinned by `StayAwakeModelTests.refusesToTurnOnBelowTheFloorOrHot` (Task 3).
4. **A restore that fails** (rule deleted by hand while on) must keep the record so the next launch retries, and must tell the person the manual undo. Pinned by `StayAwakeModelTests.failedRestoreKeepsTheRecordAndSaysHowToUndo` (Task 3) and `StayAwakeStoreTests.stopsAtTheFirstFailureSoTheRecordSurvives` (Task 5).
5. **An SSH session that isn't the phone's** (the person's own `ssh mac` from a laptop attaching tmux) counts as "attached" too; the menu must say "A phone or SSH client", never name a specific phone it can't tell apart. Pinned by `AttachedPhonesTests.anySSHClientCountsAndMacClientsDont` (Task 6) and `StayAwakeMenuTextTests.attachedLineNamesNoPhone` (Task 7).

---

## File Structure

| File | Responsibility |
|---|---|
| `macos/Sources/Features/StayAwake/PowerControl.swift` (new) | `PowerSettings`, `PowerCommand`, `PowerParse`, `PowerControl` protocol, `SystemPowerControl`. |
| `macos/Sources/Features/StayAwake/StayAwakeSudoers.swift` (new) | The sudoers rule text and its install/remove admin scripts. |
| `macos/Sources/Features/StayAwake/StayAwakeModel.swift` (new) | Pure rules: events in, actions out. `PowerState`, `StayAwakeRecord`, `StayAwakeReason`, `StayAwakeDuration`. |
| `macos/Sources/Features/StayAwake/PowerReader.swift` (new) | Reads lid, battery and thermal state (IOKit, ProcessInfo); pure battery parser. |
| `macos/Sources/Features/StayAwake/StayAwakeStore.swift` (new) | Runs the model, polls power, performs actions, persists the record, notifies. `PhoneNotifier`. |
| `macos/Sources/Features/StayAwake/AttachedPhones.swift` (new) | Sessions with an SSH-attached tmux client. |
| `macos/Sources/Features/MenuBar/StayAwakeMenuText.swift` (new) | Pure strings for the menu: status line, phones, Claude rows. |
| `macos/Sources/Features/MenuBar/LosttyStatusItem.swift` (new) | The `NSStatusItem`, its icon and menu. |
| `macos/Sources/Features/StayAwake/HotspotFallback.swift` (new, gated) | `HotspotFallbackModel` (pure) and the runtime watcher. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessChecks.swift` | + `stayAwakePermission` in status and probe. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessModel.swift` | + `.stayAwake` row and `.installStayAwake` fix. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessStore.swift` | Install fix, admin setup includes the rule, Turn Off removes it. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift` | Fix label, awake note, menu bar checkbox, (gated) hotspot picker. |
| `macos/Sources/App/macOS/AppDelegate.swift` | Launch cleanup and status item, quit confirmation, restore on quit. |
| `macos/Tests/StayAwake/*.swift` (new) | Tests for the StayAwake files. |
| `macos/Tests/MenuBar/StayAwakeMenuTextTests.swift` (new) | Menu text tests. |
| `macos/Tests/PhoneAccess/PhoneAccessModelTests.swift`, `PhoneAccessAdminTests.swift` | Updated for the new row and scripts. |
| `docs/lostty-mobile-host-setup.md`, `docs/lostty-mobile-phone-access.md` | Docs. |

---

### Task 1: Hardware spike (throwaway, needs the human)

Answers the questions the rest of the plan depends on. Nothing from this task is kept except the findings written into the spec. The human runs the physical steps; the agent prepares scripts in the scratchpad and records results.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-12-lostty-menu-bar-stay-awake-design.md` (§10, add "Spike results")
- Throwaway: `$SCRATCH/spike/wifi.swift` (scratchpad, never committed)

- [ ] **Step 1: Check sudoers includes `/etc/sudoers.d`**

Human runs: `sudo grep -n includedir /etc/sudoers`
Expected: a line `#includedir /private/etc/sudoers.d`. If missing, stop: the plan's permission model needs revisiting.

- [ ] **Step 2: Check the lid is readable while sleep is disabled**

Human runs `sudo pmset -a disablesleep 1`, then in a terminal:

```bash
while true; do ioreg -r -k AppleClamshellState -d 1 | grep '"AppleClamshellState"'; sleep 2; done
```

Close the lid for ~10 s (on battery, no external display), reopen, read the log, then `sudo pmset -a disablesleep 0`.
Expected: `Yes` lines while closed. If the Mac slept instead, stop: `disablesleep` doesn't hold on this macOS.

- [ ] **Step 3: Find where "join hotspots automatically" is stored**

```bash
defaults read > "$SCRATCH/spike/before.txt"; sudo defaults read /Library/Preferences/com.apple.wifi.known-networks > "$SCRATCH/spike/before-sys.txt" 2>&1
```

Human flips the iPhone-hotspot auto-join setting in System Settings → Wi-Fi, then:

```bash
defaults read > "$SCRATCH/spike/after.txt"; sudo defaults read /Library/Preferences/com.apple.wifi.known-networks > "$SCRATCH/spike/after-sys.txt" 2>&1
diff "$SCRATCH/spike/before.txt" "$SCRATCH/spike/after.txt"; diff "$SCRATCH/spike/before-sys.txt" "$SCRATCH/spike/after-sys.txt"
```

Record the domain and key if a diff shows it (readable without root?), or "not readable".

- [ ] **Step 4: Wi-Fi gone → does macOS join the hotspot with the lid closed?**

With `disablesleep 1` and Personal Hotspot available on the iPhone: turn the router's Wi-Fi off, close the lid for 2 minutes, open, run `networksetup -getairportnetwork en0`.
Record: joined the hotspot? how long (check `log show --last 5m --predicate 'subsystem == "com.apple.wifi"' | grep -i assoc`)?

- [ ] **Step 5: CoreWLAN can see and join the hotspot without prompts**

Write `$SCRATCH/spike/wifi.swift`:

```swift
import CoreWLAN
import Foundation

let hotspot = CommandLine.arguments[1]
let iface = CWWiFiClient.shared().interface()!
print("current:", iface.ssid() ?? "nil (Location not allowed?)")
let networks = try iface.scanForNetworks(withName: nil)
for n in networks { print("seen:", n.ssid ?? "<hidden>", n.rssiValue) }
guard let target = networks.first(where: { $0.ssid == hotspot }) else {
    print("hotspot not visible"); exit(2)
}
var password: NSString?
let status = CWKeychainFindWiFiPassword(.system, Data(hotspot.utf8), &password)
print("keychain status:", status, password == nil ? "no password" : "password found")
try iface.associate(to: target, password: password as String?)
print("associated; now:", iface.ssid() ?? "nil")
```

Human, with Wi-Fi up but the router's internet unplugged and "Allow Others to Join" OFF on the iPhone (Instant Hotspot only): `swift "$SCRATCH/spike/wifi.swift" "<hotspot name>"` from Lostty. Then repeat with "Allow Others to Join" ON.
Record for each: prompts shown (Location, keychain), hotspot visible, associated.

- [ ] **Step 6: Record results and decide**

Add to spec §10 a "Spike results (2026-10-…)" list: includedir, lid reading, the setting's location (or "not readable"), Step 4 outcome, Step 5 outcomes. Decision rule from the spec: if Step 5 can't associate without a prompt in at least the "Allow Others to Join ON" case, write "No-internet half cut" and skip Tasks 9 and 10's runtime and picker parts (Task 10 keeps only the checklist row).

```bash
git add docs/superpowers/specs/2026-10-12-lostty-menu-bar-stay-awake-design.md
git commit -m "lostty: Stay Awake spike results

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: PowerControl and the sudoers rule

**Files:**
- Create: `macos/Sources/Features/StayAwake/PowerControl.swift`
- Create: `macos/Sources/Features/StayAwake/StayAwakeSudoers.swift`
- Test: `macos/Tests/StayAwake/PowerControlTests.swift`

**Interfaces:**
- Consumes: `Command.run(_:_:environment:timeout:) -> Command.Result?` (`PhoneAccessChecks.swift`).
- Produces:
  - `struct PowerSettings: Codable, Equatable { var disableSleep: Bool; var lowPowerOnBattery: Bool?; var lowPowerOnAC: Bool }`
  - `enum PowerSource: String, Codable { case battery = "-b", ac = "-c" }`
  - `enum PowerCommand: Equatable, CaseIterable-like list { case disableSleep(Bool), lowPowerEverywhere, lowPower(PowerSource, Bool) }` with `var pmsetArguments: [String]` and `static let all: [PowerCommand]`
  - `enum PowerParse { static func sleepDisabled(pmsetG: String) -> Bool; static func lowPower(pmsetCustom: String) -> (battery: Bool?, ac: Bool?) }`
  - `enum PowerControlError: Error, Equatable { case permissionMissing, failed(String), unreadable }`
  - `protocol PowerControl { func read() throws -> PowerSettings; func run(_ command: PowerCommand) throws; func hasPermission() -> Bool }`
  - `struct SystemPowerControl: PowerControl`
  - `enum StayAwakeSudoers { static let path: String; static func rule(user: String) -> String?; static func installScript(user: String) -> String?; static let removeScript: String }`

- [ ] **Step 1: Write the failing tests**

```swift
#if os(macOS)
import Testing
@testable import Ghostty

struct PowerParseTests {
    let custom = """
    Battery Power:
     Sleep On Power Button 1
     lowpowermode         1
     displaysleep         57
    AC Power:
     Sleep On Power Button 1
     lowpowermode         0
     displaysleep         10
    """

    @Test func readsLowPowerPerSource() {
        let lp = PowerParse.lowPower(pmsetCustom: custom)
        #expect(lp.battery == true)
        #expect(lp.ac == false)
    }

    @Test func desktopHasNoBatterySection() {
        let lp = PowerParse.lowPower(pmsetCustom: "AC Power:\n lowpowermode         1\n")
        #expect(lp.battery == nil)
        #expect(lp.ac == true)
    }

    @Test func sleepDisabledOnlyWhenListedAsOne() {
        #expect(PowerParse.sleepDisabled(pmsetG: "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n sleep 1\n"))
        #expect(!PowerParse.sleepDisabled(pmsetG: "System-wide power settings:\n SleepDisabled\t\t0\n"))
        #expect(!PowerParse.sleepDisabled(pmsetG: "System-wide power settings:\nCurrently in use:\n standby 1\n"))
    }

    @Test func commandsMapToPmsetArguments() {
        #expect(PowerCommand.disableSleep(true).pmsetArguments == ["-a", "disablesleep", "1"])
        #expect(PowerCommand.lowPowerEverywhere.pmsetArguments == ["-a", "lowpowermode", "1"])
        #expect(PowerCommand.lowPower(.battery, false).pmsetArguments == ["-b", "lowpowermode", "0"])
        #expect(PowerCommand.lowPower(.ac, true).pmsetArguments == ["-c", "lowpowermode", "1"])
        #expect(PowerCommand.all.count == 7)
    }
}

struct StayAwakeSudoersTests {
    @Test func ruleAllowsExactlyTheSevenCommands() throws {
        let rule = try #require(StayAwakeSudoers.rule(user: "lawliang"))
        #expect(rule == "lawliang ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a lowpowermode 1, /usr/bin/pmset -b lowpowermode 0, /usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset -c lowpowermode 0, /usr/bin/pmset -c lowpowermode 1")
    }

    @Test func refusesUnsafeUserNames() {
        for bad in ["", "a b", "a,b", "ALL", "-x", "a\nb", "a:b", "a=b", "%admin"] {
            #expect(StayAwakeSudoers.rule(user: bad) == nil, "\(bad)")
            #expect(StayAwakeSudoers.installScript(user: bad) == nil, "\(bad)")
        }
        #expect(StayAwakeSudoers.rule(user: "first.last-2_x") != nil)
    }

    @Test func installChecksWithVisudoBeforeInstalling() throws {
        let script = try #require(StayAwakeSudoers.installScript(user: "lawliang"))
        let visudo = try #require(script.range(of: "/usr/sbin/visudo -cf"))
        let install = try #require(script.range(of: "/usr/bin/install -m 0440 -o root -g wheel"))
        #expect(visudo.lowerBound < install.lowerBound)
        #expect(script.contains("/etc/sudoers.d/lostty"))
        #expect(script.contains(StayAwakeSudoers.rule(user: "lawliang")!))
        #expect(StayAwakeSudoers.removeScript == "rm -f /etc/sudoers.d/lostty")
    }
}
#endif
```

- [ ] **Step 2: Run to verify they fail**

Run: `macos/skins-test.sh PowerParseTests` and `macos/skins-test.sh StayAwakeSudoersTests`
Expected: build FAILS, "cannot find 'PowerParse' in scope".

- [ ] **Step 3: Implement `PowerControl.swift`**

```swift
#if os(macOS)
import Foundation

/// The power settings Stay Awake changes, as they were before it did.
struct PowerSettings: Codable, Equatable {
    var disableSleep: Bool
    /// nil on Macs without a battery.
    var lowPowerOnBattery: Bool?
    var lowPowerOnAC: Bool
}

enum PowerSource: String, Codable {
    case battery = "-b"
    case ac = "-c"
}

/// The only `pmset` changes Lostty makes; each is one line of the sudoers
/// rule (`StayAwakeSudoers`).
enum PowerCommand: Equatable {
    case disableSleep(Bool)
    case lowPowerEverywhere
    case lowPower(PowerSource, Bool)

    static let all: [PowerCommand] = [
        .disableSleep(false), .disableSleep(true), .lowPowerEverywhere,
        .lowPower(.battery, false), .lowPower(.battery, true),
        .lowPower(.ac, false), .lowPower(.ac, true),
    ]

    var pmsetArguments: [String] {
        switch self {
        case .disableSleep(let on): ["-a", "disablesleep", on ? "1" : "0"]
        case .lowPowerEverywhere: ["-a", "lowpowermode", "1"]
        case .lowPower(let source, let on): [source.rawValue, "lowpowermode", on ? "1" : "0"]
        }
    }
}

enum PowerParse {
    /// `pmset -g` lists `SleepDisabled 1` under the system-wide settings only
    /// while it is set.
    static func sleepDisabled(pmsetG: String) -> Bool {
        pmsetG.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count == 2 && fields[0] == "SleepDisabled" && fields[1] == "1"
        }
    }

    /// `pmset -g custom`: `lowpowermode` under "Battery Power:" and "AC Power:".
    static func lowPower(pmsetCustom: String) -> (battery: Bool?, ac: Bool?) {
        var section: PowerSource?
        var battery: Bool?
        var ac: Bool?
        for line in pmsetCustom.split(separator: "\n") {
            if line.hasPrefix("Battery Power:") { section = .battery; continue }
            if line.hasPrefix("AC Power:") { section = .ac; continue }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[0] == "lowpowermode" else { continue }
            let on = fields[1] == "1"
            switch section {
            case .battery: battery = on
            case .ac: ac = on
            case nil: break
            }
        }
        return (battery, ac)
    }
}

enum PowerControlError: Error, Equatable {
    /// `sudo -n` wants a password: the sudoers rule is missing.
    case permissionMissing
    case failed(String)
    case unreadable
}

protocol PowerControl {
    func read() throws -> PowerSettings
    func run(_ command: PowerCommand) throws
    func hasPermission() -> Bool
}

/// `pmset` through `sudo -n`, which never prompts: without the rule it fails
/// at once instead of waiting for a password nobody can type.
struct SystemPowerControl: PowerControl {
    func read() throws -> PowerSettings {
        guard let g = Command.run("/usr/bin/pmset", ["-g"]), g.status == 0,
              let custom = Command.run("/usr/bin/pmset", ["-g", "custom"]), custom.status == 0
        else { throw PowerControlError.unreadable }
        let lowPower = PowerParse.lowPower(pmsetCustom: custom.output)
        guard let ac = lowPower.ac else { throw PowerControlError.unreadable }
        return PowerSettings(
            disableSleep: PowerParse.sleepDisabled(pmsetG: g.output),
            lowPowerOnBattery: lowPower.battery, lowPowerOnAC: ac)
    }

    func run(_ command: PowerCommand) throws {
        guard let result = Command.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + command.pmsetArguments) else {
            throw PowerControlError.failed("pmset didn't finish.")
        }
        guard result.status != 0 else { return }
        if result.output.contains("password is required") || result.output.contains("terminal is required") {
            throw PowerControlError.permissionMissing
        }
        throw PowerControlError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The rule file is there and sudo lets this user run pmset without a
    /// password. Both: `sudo -n -l` alone also passes on a fresh sudo timestamp.
    func hasPermission() -> Bool {
        FileManager.default.fileExists(atPath: StayAwakeSudoers.path)
            && Command.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"])?.status == 0
    }
}
#endif
```

- [ ] **Step 4: Implement `StayAwakeSudoers.swift`**

```swift
#if os(macOS)
import Foundation

/// The one-time permission: a sudoers rule letting this user run exactly the
/// `PowerCommand`s as root without a password.
enum StayAwakeSudoers {
    static let path = "/etc/sudoers.d/lostty"

    /// nil for a name that isn't a plain account name: anything else could
    /// change what the rule means.
    static func rule(user: String) -> String? {
        guard user.range(of: #"^[A-Za-z0-9_][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil,
              user != "ALL"
        else { return nil }
        let commands = PowerCommand.all.map { (["/usr/bin/pmset"] + $0.pmsetArguments).joined(separator: " ") }
        return "\(user) ALL=(root) NOPASSWD: " + commands.joined(separator: ", ")
    }

    /// Runs as root in the admin prompt. visudo checks the file before it is
    /// installed, so a bad rule can never break sudo. Its last command's
    /// status is the script's.
    static func installScript(user: String) -> String? {
        guard let rule = rule(user: user) else { return nil }
        return """
        tmp=$(/usr/bin/mktemp /tmp/lostty-sudoers.XXXXXX) && /usr/bin/printf '%s\\n' '# Lostty: Stay Awake for Phone. Phone Access, Turn Off removes it.' '\(rule)' > "$tmp" && /usr/sbin/visudo -cf "$tmp" >/dev/null && /usr/bin/install -m 0440 -o root -g wheel "$tmp" \(path); rc=$?; /bin/rm -f "$tmp"; [ $rc -eq 0 ]
        """
    }

    static var removeScript: String { "rm -f \(path)" }
}
#endif
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `macos/skins-test.sh PowerParseTests` then `macos/skins-test.sh StayAwakeSudoersTests`
Expected: `** TEST SUCCEEDED **` for both.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/StayAwake/PowerControl.swift macos/Sources/Features/StayAwake/StayAwakeSudoers.swift macos/Tests/StayAwake/PowerControlTests.swift
git commit -m "lostty: pmset control and the Stay Awake sudoers rule

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: StayAwakeModel

**Files:**
- Create: `macos/Sources/Features/StayAwake/StayAwakeModel.swift`
- Test: `macos/Tests/StayAwake/StayAwakeModelTests.swift`

**Interfaces:**
- Consumes: `PowerSettings`, `PowerCommand`, `PowerSource`, `PowerControlError` (Task 2).
- Produces:
  - `enum Thermal: Equatable { case nominal, fair, serious, critical }`
  - `struct PowerState: Equatable { var lidClosed: Bool; var onBattery: Bool; var batteryPercent: Int?; var thermal: Thermal }`
  - `struct StayAwakeRecord: Codable, Equatable { var settings: PowerSettings; var lowPowerApplied: Bool }`
  - `enum StayAwakeReason: Equatable { case turnedOff, timer, battery(Int), heat, permissionMissing, failed(String), restoreFailed }`
  - `enum StayAwakeDuration: String, CaseIterable { case untilOff, oneHour, fourHours, eightHours; var title: String; var seconds: TimeInterval? }`
  - `enum StayAwakeAction: Equatable { case saveRecord(StayAwakeRecord), clearRecord, run(PowerCommand), notifyMac(String), notifyPhone(String) }`
  - `struct StayAwakeModel` with `enum State: Equatable { case off(reason: StayAwakeReason?, at: Date?), on(until: Date?, record: StayAwakeRecord) }`, `var state`, `var batteryFloor: Int`, `var power: PowerState?`, `var isOn: Bool`, and `mutating func handle(_ event: Event, now: Date) -> [StayAwakeAction]`
  - `enum StayAwakeModel.Event: Equatable { case turnOn(until: Date?, current: PowerSettings), turnOff, power(PowerState), tick, quit, launch(StayAwakeRecord?), controlFailed(PowerControlError, command: PowerCommand) }`
  - `enum StayAwakeCopy { static let restoreFailed: String; static func goingToSleep(_ reason: StayAwakeReason) -> String? }`

- [ ] **Step 1: Write the failing tests**

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct StayAwakeModelTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let before = PowerSettings(disableSleep: false, lowPowerOnBattery: true, lowPowerOnAC: false)
    let open = PowerState(lidClosed: false, onBattery: true, batteryPercent: 80, thermal: .nominal)
    var closed: PowerState { PowerState(lidClosed: true, onBattery: true, batteryPercent: 80, thermal: .nominal) }

    func onModel(lid: PowerState? = nil, until: Date? = nil) -> StayAwakeModel {
        var m = StayAwakeModel()
        _ = m.handle(.power(lid ?? open), now: t0)
        _ = m.handle(.turnOn(until: until, current: before), now: t0)
        return m
    }

    @Test func turningOnSavesTheRecordBeforeDisablingSleep() {
        var m = StayAwakeModel()
        _ = m.handle(.power(open), now: t0)
        let actions = m.handle(.turnOn(until: nil, current: before), now: t0)
        #expect(actions == [.saveRecord(.init(settings: before, lowPowerApplied: false)), .run(.disableSleep(true))])
        #expect(m.isOn)
    }

    @Test func turningOnWithTheLidClosedAppliesLowPowerToo() {
        var m = StayAwakeModel()
        _ = m.handle(.power(closed), now: t0)
        let actions = m.handle(.turnOn(until: nil, current: before), now: t0)
        #expect(actions == [
            .saveRecord(.init(settings: before, lowPowerApplied: false)), .run(.disableSleep(true)),
            .saveRecord(.init(settings: before, lowPowerApplied: true)), .run(.lowPowerEverywhere),
        ])
    }

    @Test func lowPowerOnlyWhileTheLidIsClosed() {
        var m = onModel()
        #expect(m.handle(.power(closed), now: t0) == [
            .saveRecord(.init(settings: before, lowPowerApplied: true)), .run(.lowPowerEverywhere),
        ])
        #expect(m.handle(.power(closed), now: t0) == [])
        #expect(m.handle(.power(open), now: t0) == [
            .run(.lowPower(.battery, true)), .run(.lowPower(.ac, false)),
            .saveRecord(.init(settings: before, lowPowerApplied: false)),
        ])
    }

    @Test func restoresLowPowerPerSource() {
        var m = onModel(lid: closed)
        let actions = m.handle(.turnOff, now: t0)
        #expect(actions == [
            .run(.lowPower(.battery, true)), .run(.lowPower(.ac, false)),
            .run(.disableSleep(false)), .clearRecord,
        ])
        #expect(m.state == .off(reason: .turnedOff, at: t0))
    }

    @Test func aHandSetDisableSleepStaysSet() {
        var m = StayAwakeModel()
        _ = m.handle(.power(open), now: t0)
        let mine = PowerSettings(disableSleep: true, lowPowerOnBattery: nil, lowPowerOnAC: false)
        _ = m.handle(.turnOn(until: nil, current: mine), now: t0)
        _ = m.handle(.power(closed), now: t0)
        #expect(m.handle(.turnOff, now: t0) == [
            .run(.lowPower(.ac, false)), .run(.disableSleep(true)), .clearRecord,
        ])
    }

    @Test func batteryFloorCutsOffOnlyOnBattery() {
        var m = onModel()
        m.batteryFloor = 15
        #expect(m.handle(.power(.init(lidClosed: false, onBattery: false, batteryPercent: 10, thermal: .nominal)), now: t0) == [])
        #expect(m.isOn)
        let actions = m.handle(.power(.init(lidClosed: false, onBattery: true, batteryPercent: 15, thermal: .nominal)), now: t0)
        #expect(actions == [
            .notifyMac("Mac is going to sleep — battery at 15%."), .notifyPhone("Mac is going to sleep — battery at 15%."),
            .run(.disableSleep(false)), .clearRecord,
        ])
        #expect(m.state == .off(reason: .battery(15), at: t0))
    }

    @Test func criticalHeatCutsOff() {
        var m = onModel()
        _ = m.handle(.power(.init(lidClosed: false, onBattery: true, batteryPercent: 80, thermal: .serious)), now: t0)
        #expect(m.isOn)
        let actions = m.handle(.power(.init(lidClosed: false, onBattery: true, batteryPercent: 80, thermal: .critical)), now: t0)
        #expect(actions.first == .notifyMac("Mac is going to sleep — it's too hot."))
        #expect(m.state == .off(reason: .heat, at: t0))
    }

    @Test func timerEndsIt() {
        var m = onModel(until: t0.addingTimeInterval(3600))
        #expect(m.handle(.tick, now: t0.addingTimeInterval(3599)) == [])
        let actions = m.handle(.tick, now: t0.addingTimeInterval(3600))
        #expect(actions.first == .notifyMac("Mac is going to sleep — Stay Awake time is up."))
        #expect(m.state == .off(reason: .timer, at: t0.addingTimeInterval(3600)))
    }

    @Test func noRearmingAfterACutOff() {
        var m = onModel()
        m.batteryFloor = 15
        _ = m.handle(.power(.init(lidClosed: false, onBattery: true, batteryPercent: 10, thermal: .nominal)), now: t0)
        #expect(m.handle(.power(.init(lidClosed: false, onBattery: false, batteryPercent: 90, thermal: .nominal)), now: t0) == [])
        #expect(!m.isOn)
    }

    @Test func refusesToTurnOnBelowTheFloorOrHot() {
        var m = StayAwakeModel()
        m.batteryFloor = 15
        _ = m.handle(.power(.init(lidClosed: false, onBattery: true, batteryPercent: 12, thermal: .nominal)), now: t0)
        #expect(m.handle(.turnOn(until: nil, current: before), now: t0) == [])
        #expect(m.state == .off(reason: .battery(12), at: t0))

        var hot = StayAwakeModel()
        _ = hot.handle(.power(.init(lidClosed: false, onBattery: false, batteryPercent: nil, thermal: .critical)), now: t0)
        #expect(hot.handle(.turnOn(until: nil, current: before), now: t0) == [])
        #expect(hot.state == .off(reason: .heat, at: t0))
    }

    @Test func quitRestoresWithoutNotifying() {
        var m = onModel(lid: closed)
        let actions = m.handle(.quit, now: t0)
        #expect(!actions.contains { if case .notifyMac = $0 { true } else { false } })
        #expect(actions.last == .clearRecord)
        #expect(!m.isOn)
    }

    @Test func launchRestoresALeftoverRecord() {
        var m = StayAwakeModel()
        let record = StayAwakeRecord(settings: before, lowPowerApplied: true)
        #expect(m.handle(.launch(record), now: t0) == [
            .run(.lowPower(.battery, true)), .run(.lowPower(.ac, false)),
            .run(.disableSleep(false)), .clearRecord,
        ])
        #expect(m.handle(.launch(nil), now: t0) == [])
    }

    @Test func permissionMissingWhileTurningOnLeavesNothingChanged() {
        var m = onModel()
        let actions = m.handle(.controlFailed(.permissionMissing, command: .disableSleep(true)), now: t0)
        #expect(actions == [.clearRecord])
        #expect(m.state == .off(reason: .permissionMissing, at: t0))
    }

    @Test func failedRestoreKeepsTheRecordAndSaysHowToUndo() {
        var m = onModel()
        _ = m.handle(.turnOff, now: t0)
        let actions = m.handle(.controlFailed(.failed("nope"), command: .disableSleep(false)), now: t0)
        #expect(actions == [.notifyMac(StayAwakeCopy.restoreFailed)])
        #expect(!actions.contains(.clearRecord))
        #expect(m.state == .off(reason: .restoreFailed, at: t0))
        #expect(StayAwakeCopy.restoreFailed == "Lostty couldn't let your Mac sleep again. Run: sudo pmset -a disablesleep 0")
    }

    @Test func lowPowerFailureWhileOnOnlyNotifies() {
        var m = onModel()
        _ = m.handle(.power(closed), now: t0)
        let actions = m.handle(.controlFailed(.failed("x"), command: .lowPowerEverywhere), now: t0)
        #expect(actions == [.notifyMac("Lostty couldn't change Low Power Mode.")])
        #expect(m.isOn)
    }

    @Test func durations() {
        #expect(StayAwakeDuration.allCases.map(\.title) == ["Until I Turn It Off", "1 Hour", "4 Hours", "8 Hours"])
        #expect(StayAwakeDuration.untilOff.seconds == nil)
        #expect(StayAwakeDuration.fourHours.seconds == 4 * 3600)
    }
}
#endif
```

- [ ] **Step 2: Run to verify they fail**

Run: `macos/skins-test.sh StayAwakeModelTests`
Expected: build FAILS, "cannot find 'StayAwakeModel' in scope".

- [ ] **Step 3: Implement `StayAwakeModel.swift`**

```swift
#if os(macOS)
import Foundation

enum Thermal: Equatable {
    case nominal, fair, serious, critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }
}

struct PowerState: Equatable {
    var lidClosed: Bool
    var onBattery: Bool
    /// nil on Macs without a battery.
    var batteryPercent: Int?
    var thermal: Thermal
}

/// What to put back, saved before anything changes.
struct StayAwakeRecord: Codable, Equatable {
    var settings: PowerSettings
    var lowPowerApplied: Bool
}

enum StayAwakeReason: Equatable {
    case turnedOff, timer, battery(Int), heat, permissionMissing, failed(String), restoreFailed
}

enum StayAwakeDuration: String, CaseIterable {
    case untilOff, oneHour, fourHours, eightHours

    var title: String {
        switch self {
        case .untilOff: "Until I Turn It Off"
        case .oneHour: "1 Hour"
        case .fourHours: "4 Hours"
        case .eightHours: "8 Hours"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .untilOff: nil
        case .oneHour: 3600
        case .fourHours: 4 * 3600
        case .eightHours: 8 * 3600
        }
    }
}

enum StayAwakeAction: Equatable {
    case saveRecord(StayAwakeRecord)
    case clearRecord
    case run(PowerCommand)
    case notifyMac(String)
    case notifyPhone(String)
}

enum StayAwakeCopy {
    static let restoreFailed = "Lostty couldn't let your Mac sleep again. Run: sudo pmset -a disablesleep 0"
    static let lowPowerFailed = "Lostty couldn't change Low Power Mode."

    static func goingToSleep(_ reason: StayAwakeReason) -> String? {
        switch reason {
        case .battery(let percent): "Mac is going to sleep — battery at \(percent)%."
        case .heat: "Mac is going to sleep — it's too hot."
        case .timer: "Mac is going to sleep — Stay Awake time is up."
        default: nil
        }
    }
}

/// Stay Awake for Phone's rules, with no system calls: events in, actions
/// out. The store performs the actions in order and stops at the first
/// failure, reporting it back as `controlFailed`; `clearRecord` always comes
/// last, so a failed restore leaves the record for the next launch.
struct StayAwakeModel {
    enum State: Equatable {
        case off(reason: StayAwakeReason?, at: Date?)
        case on(until: Date?, record: StayAwakeRecord)
    }

    enum Event: Equatable {
        case turnOn(until: Date?, current: PowerSettings)
        case turnOff
        case power(PowerState)
        case tick
        case quit
        case launch(StayAwakeRecord?)
        case controlFailed(PowerControlError, command: PowerCommand)
    }

    private(set) var state: State = .off(reason: nil, at: nil)
    private(set) var power: PowerState?
    var batteryFloor = 15

    var isOn: Bool { if case .on = state { true } else { false } }

    mutating func handle(_ event: Event, now: Date) -> [StayAwakeAction] {
        switch event {
        case .turnOn(let until, let current):
            guard !isOn else { return [] }
            if let power, let reason = cutOff(power) {
                state = .off(reason: reason, at: now)
                return []
            }
            var record = StayAwakeRecord(settings: current, lowPowerApplied: false)
            var actions: [StayAwakeAction] = [.saveRecord(record), .run(.disableSleep(true))]
            if power?.lidClosed == true {
                record.lowPowerApplied = true
                actions += [.saveRecord(record), .run(.lowPowerEverywhere)]
            }
            state = .on(until: until, record: record)
            return actions

        case .turnOff:
            return finish(.turnedOff, now: now)

        case .quit:
            return finish(.turnedOff, now: now)

        case .power(let next):
            power = next
            guard case .on(let until, var record) = state else { return [] }
            if let reason = cutOff(next) { return finish(reason, now: now) }
            if next.lidClosed && !record.lowPowerApplied {
                record.lowPowerApplied = true
                state = .on(until: until, record: record)
                return [.saveRecord(record), .run(.lowPowerEverywhere)]
            }
            if !next.lidClosed && record.lowPowerApplied {
                record.lowPowerApplied = false
                state = .on(until: until, record: record)
                return restoreLowPower(record.settings) + [.saveRecord(record)]
            }
            return []

        case .tick:
            guard case .on(let until?, _) = state, now >= until else { return [] }
            return finish(.timer, now: now)

        case .launch(let record):
            guard let record else { return [] }
            state = .off(reason: nil, at: nil)
            return restore(record) + [.clearRecord]

        case .controlFailed(let error, let command):
            if isOn {
                if command == .disableSleep(true) {
                    state = .off(reason: error == .permissionMissing ? .permissionMissing : .failed(Self.text(error)), at: now)
                    return [.clearRecord]
                }
                return [.notifyMac(StayAwakeCopy.lowPowerFailed)]
            }
            state = .off(reason: .restoreFailed, at: now)
            return [.notifyMac(StayAwakeCopy.restoreFailed)]
        }
    }

    private func cutOff(_ power: PowerState) -> StayAwakeReason? {
        if power.thermal == .critical { return .heat }
        if power.onBattery, let percent = power.batteryPercent, percent <= batteryFloor { return .battery(percent) }
        return nil
    }

    private mutating func finish(_ reason: StayAwakeReason, now: Date) -> [StayAwakeAction] {
        guard case .on(_, let record) = state else { return [] }
        state = .off(reason: reason, at: now)
        let notices = StayAwakeCopy.goingToSleep(reason).map { [StayAwakeAction.notifyMac($0), .notifyPhone($0)] } ?? []
        return notices + restore(record) + [.clearRecord]
    }

    private func restore(_ record: StayAwakeRecord) -> [StayAwakeAction] {
        (record.lowPowerApplied ? restoreLowPower(record.settings) : [])
            + [.run(.disableSleep(record.settings.disableSleep))]
    }

    private func restoreLowPower(_ settings: PowerSettings) -> [StayAwakeAction] {
        var actions: [StayAwakeAction] = []
        if let battery = settings.lowPowerOnBattery { actions.append(.run(.lowPower(.battery, battery))) }
        actions.append(.run(.lowPower(.ac, settings.lowPowerOnAC)))
        return actions
    }

    private static func text(_ error: PowerControlError) -> String {
        switch error {
        case .permissionMissing: "needs the stay-awake permission"
        case .failed(let message): message
        case .unreadable: "couldn't read the power settings"
        }
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh StayAwakeModelTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/StayAwake/StayAwakeModel.swift macos/Tests/StayAwake/StayAwakeModelTests.swift
git commit -m "lostty: Stay Awake rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: PowerReader

Reads lid, battery and heat. The store polls it every 5 s while Stay Awake is on (simpler than IOKit notifications and covers the spec's fallback; the spike confirmed the lid is readable).

**Files:**
- Create: `macos/Sources/Features/StayAwake/PowerReader.swift`
- Test: `macos/Tests/StayAwake/PowerReaderTests.swift`

**Interfaces:**
- Consumes: `PowerState`, `Thermal` (Task 3).
- Produces: `enum PowerReader { static func read() -> PowerState; static func battery(providing: String, descriptions: [[String: Any]]) -> (onBattery: Bool, percent: Int?) }`

- [ ] **Step 1: Write the failing test**

```swift
#if os(macOS)
import IOKit.ps
import Testing
@testable import Ghostty

struct PowerReaderTests {
    @Test func percentFromTheInternalBattery() {
        let internalBattery: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 64, kIOPSMaxCapacityKey: 100,
        ]
        let ups: [String: Any] = [kIOPSTypeKey: kIOPSUPSType, kIOPSCurrentCapacityKey: 10, kIOPSMaxCapacityKey: 100]
        let r = PowerReader.battery(providing: kIOPSBatteryPowerValue, descriptions: [ups, internalBattery])
        #expect(r.onBattery)
        #expect(r.percent == 64)
    }

    @Test func onPowerAndNoBattery() {
        let r = PowerReader.battery(providing: kIOPSACPowerValue, descriptions: [])
        #expect(!r.onBattery)
        #expect(r.percent == nil)
    }

    @Test func scalesWhenMaxIsNotHundred() {
        let b: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 2500, kIOPSMaxCapacityKey: 5000]
        #expect(PowerReader.battery(providing: kIOPSACPowerValue, descriptions: [b]).percent == 50)
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh PowerReaderTests`
Expected: build FAILS, "cannot find 'PowerReader' in scope".

- [ ] **Step 3: Implement**

```swift
#if os(macOS)
import Foundation
import IOKit
import IOKit.ps

enum PowerReader {
    static func read() -> PowerState {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? ?? kIOPSACPowerValue
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as Array
        let descriptions = list.compactMap {
            IOPSGetPowerSourceDescription(info, $0 as CFTypeRef)?.takeUnretainedValue() as? [String: Any]
        }
        let battery = battery(providing: providing, descriptions: descriptions)
        return PowerState(
            lidClosed: lidClosed(), onBattery: battery.onBattery, batteryPercent: battery.percent,
            thermal: Thermal(ProcessInfo.processInfo.thermalState))
    }

    static func battery(providing: String, descriptions: [[String: Any]]) -> (onBattery: Bool, percent: Int?) {
        let internalBattery = descriptions.first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
        let percent: Int? = internalBattery.flatMap { d in
            guard let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { return nil }
            return current * 100 / max
        }
        return (providing == kIOPSBatteryPowerValue, percent)
    }

    /// `AppleClamshellState` on the power-management root.
    private static func lidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }
}
#endif
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `macos/skins-test.sh PowerReaderTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/StayAwake/PowerReader.swift macos/Tests/StayAwake/PowerReaderTests.swift
git commit -m "lostty: read lid, battery and heat for Stay Awake

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: StayAwakeStore

**Files:**
- Create: `macos/Sources/Features/StayAwake/StayAwakeStore.swift`
- Test: `macos/Tests/StayAwake/StayAwakeStoreTests.swift`

**Interfaces:**
- Consumes: `PowerControl`, `PowerControlError`, `PowerCommand` (Task 2); `StayAwakeModel`, `StayAwakeAction`, `StayAwakeRecord`, `StayAwakeDuration`, `PowerState` (Task 3); `PowerReader.read()` (Task 4); `AuthorizedKeysFile.standard`, `AuthorizedKeys.phones(in:)` (LosttyRemote).
- Produces:
  - `protocol PhoneNotifier { func notify(_ text: String) }`, `struct NoPhoneNotifier: PhoneNotifier`
  - `struct StayAwakeRecordStore { var defaults: UserDefaults; func load() -> StayAwakeRecord?; func save(_:); func clear() }` (key `LosttyStayAwakeRecord`)
  - `@MainActor final class StayAwakeStore: ObservableObject` with `static let shared`, `init(control:defaults:phone:readPower:hasPairedPhone:notifyMac:now:)`, `@Published private(set) var model: StayAwakeModel`, `var isOn: Bool`, `var until: Date?`, `var batteryFloor: Int { get set }` (key `LosttyStayAwakeFloor`), `var lastDuration: StayAwakeDuration` (key `LosttyStayAwakeDuration`), `func start()`, `func refreshAvailability()`, `@Published private(set) var available: Bool`, `@Published private(set) var permissionInstalled: Bool`, `func turnOn(_ duration: StayAwakeDuration)`, `func turnOff()`, `func quit()`, `func pollPower()`

- [ ] **Step 1: Write the failing tests**

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct StayAwakeStoreTests {
    final class FakeControl: PowerControl {
        var settings = PowerSettings(disableSleep: false, lowPowerOnBattery: true, lowPowerOnAC: false)
        var ran: [PowerCommand] = []
        var failOn: PowerCommand?
        var permission = true
        func read() throws -> PowerSettings { settings }
        func run(_ command: PowerCommand) throws {
            if command == failOn { throw PowerControlError.failed("boom") }
            ran.append(command)
        }
        func hasPermission() -> Bool { permission }
    }

    final class Notes { var mac: [String] = [] }

    func make(_ control: FakeControl, power: PowerState, defaults: UserDefaults, notes: Notes = Notes()) -> StayAwakeStore {
        StayAwakeStore(
            control: control, defaults: defaults, phone: NoPhoneNotifier(),
            readPower: { power }, hasPairedPhone: { true },
            notifyMac: { notes.mac.append($0) }, now: { Date(timeIntervalSince1970: 1_000) })
    }

    func freshDefaults() -> UserDefaults {
        let name = "StayAwakeStoreTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    let open = PowerState(lidClosed: false, onBattery: true, batteryPercent: 80, thermal: .nominal)

    @Test func turnOnSavesTheRecordAndDisablesSleep() {
        let control = FakeControl()
        let defaults = freshDefaults()
        let store = make(control, power: open, defaults: defaults)
        store.refreshAvailability()
        store.turnOn(.untilOff)
        #expect(store.isOn)
        #expect(control.ran == [.disableSleep(true)])
        #expect(StayAwakeRecordStore(defaults: defaults).load()?.settings == control.settings)
    }

    @Test func turnOffRestoresAndClearsTheRecord() {
        let control = FakeControl()
        let defaults = freshDefaults()
        let store = make(control, power: open, defaults: defaults)
        store.refreshAvailability()
        store.turnOn(.untilOff)
        store.turnOff()
        #expect(control.ran == [.disableSleep(true), .disableSleep(false)])
        #expect(StayAwakeRecordStore(defaults: defaults).load() == nil)
    }

    @Test func stopsAtTheFirstFailureSoTheRecordSurvives() {
        let control = FakeControl()
        let defaults = freshDefaults()
        let notes = Notes()
        let store = make(control, power: open, defaults: defaults, notes: notes)
        store.refreshAvailability()
        store.turnOn(.untilOff)
        control.failOn = .disableSleep(false)
        store.turnOff()
        #expect(StayAwakeRecordStore(defaults: defaults).load() != nil)
        #expect(notes.mac == [StayAwakeCopy.restoreFailed])
    }

    @Test func startRestoresALeftoverRecord() {
        let control = FakeControl()
        let defaults = freshDefaults()
        StayAwakeRecordStore(defaults: defaults).save(.init(settings: control.settings, lowPowerApplied: false))
        let store = make(control, power: open, defaults: defaults)
        store.start()
        #expect(control.ran == [.disableSleep(false)])
        #expect(StayAwakeRecordStore(defaults: defaults).load() == nil)
    }

    @Test func notAvailableWithoutPermission() {
        let control = FakeControl()
        control.permission = false
        let store = make(control, power: open, defaults: freshDefaults())
        store.refreshAvailability()
        #expect(!store.available)
        store.turnOn(.untilOff)
        #expect(!store.isOn)
        #expect(control.ran.isEmpty)
    }

    @Test func floorDefaultsToFifteenAndPersists() {
        let defaults = freshDefaults()
        let store = make(FakeControl(), power: open, defaults: defaults)
        #expect(store.batteryFloor == 15)
        store.batteryFloor = 30
        #expect(make(FakeControl(), power: open, defaults: defaults).batteryFloor == 30)
    }
}
#endif
```

- [ ] **Step 2: Run to verify they fail**

Run: `macos/skins-test.sh StayAwakeStoreTests`
Expected: build FAILS, "cannot find 'StayAwakeStore' in scope".

- [ ] **Step 3: Implement**

```swift
#if os(macOS)
import AppKit
import LosttyRemote
import UserNotifications

/// Tells the phone something happened. Does nothing until "Lostty phone
/// push" adds APNs.
protocol PhoneNotifier {
    func notify(_ text: String)
}

struct NoPhoneNotifier: PhoneNotifier {
    func notify(_ text: String) {}
}

struct StayAwakeRecordStore {
    static let key = "LosttyStayAwakeRecord"
    var defaults: UserDefaults

    func load() -> StayAwakeRecord? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(StayAwakeRecord.self, from: $0) }
    }

    func save(_ record: StayAwakeRecord) {
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: Self.key) }
    }

    func clear() { defaults.removeObject(forKey: Self.key) }
}

/// Runs `StayAwakeModel`: feeds it power readings every 5 s while on, and
/// performs its actions in order, stopping at the first failure.
@MainActor
final class StayAwakeStore: ObservableObject {
    static let shared = StayAwakeStore()

    static let floorKey = "LosttyStayAwakeFloor"
    static let durationKey = "LosttyStayAwakeDuration"
    static let floors = [10, 15, 20, 30]

    @Published private(set) var model = StayAwakeModel()
    @Published private(set) var available = false
    @Published private(set) var permissionInstalled = false

    private let control: PowerControl
    private let defaults: UserDefaults
    private let phone: PhoneNotifier
    private let readPower: () -> PowerState
    private let hasPairedPhone: () -> Bool
    private let notifyMac: (String) -> Void
    private let now: () -> Date
    private var timer: Timer?

    init(
        control: PowerControl = SystemPowerControl(),
        defaults: UserDefaults = .ghostty,
        phone: PhoneNotifier = NoPhoneNotifier(),
        readPower: @escaping () -> PowerState = PowerReader.read,
        hasPairedPhone: @escaping () -> Bool = StayAwakeStore.anyPhonePaired,
        notifyMac: @escaping (String) -> Void = StayAwakeStore.postMacNotification,
        now: @escaping () -> Date = Date.init
    ) {
        self.control = control
        self.defaults = defaults
        self.phone = phone
        self.readPower = readPower
        self.hasPairedPhone = hasPairedPhone
        self.notifyMac = notifyMac
        self.now = now
        model.batteryFloor = batteryFloor
    }

    var isOn: Bool { model.isOn }
    var until: Date? { if case .on(let until, _) = model.state { until } else { nil } }
    var power: PowerState? { model.power }

    var batteryFloor: Int {
        get { (defaults.object(forKey: Self.floorKey) as? Int) ?? 15 }
        set {
            defaults.set(newValue, forKey: Self.floorKey)
            model.batteryFloor = newValue
        }
    }

    var lastDuration: StayAwakeDuration {
        get { defaults.string(forKey: Self.durationKey).flatMap(StayAwakeDuration.init(rawValue:)) ?? .untilOff }
        set { defaults.set(newValue.rawValue, forKey: Self.durationKey) }
    }

    /// At launch: put back whatever a crashed Lostty left changed.
    func start() {
        send(.launch(StayAwakeRecordStore(defaults: defaults).load()))
    }

    func refreshAvailability() {
        permissionInstalled = control.hasPermission()
        available = permissionInstalled && hasPairedPhone()
    }

    func turnOn(_ duration: StayAwakeDuration) {
        refreshAvailability()
        guard available, !isOn else { return }
        lastDuration = duration
        let current: PowerSettings
        do {
            current = try control.read()
        } catch {
            send(.controlFailed(.unreadable, command: .disableSleep(true)))
            return
        }
        send(.power(readPower()))
        send(.turnOn(until: duration.seconds.map { now().addingTimeInterval($0) }, current: current))
        if isOn { startPolling() }
    }

    func turnOff() {
        send(.turnOff)
    }

    /// Synchronous: AppKit is about to exit.
    func quit() {
        send(.quit)
    }

    func pollPower() {
        send(.power(readPower()))
        send(.tick)
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPower() }
        }
    }

    private func send(_ event: StayAwakeModel.Event) {
        let actions = model.handle(event, now: now())
        perform(actions)
        if !isOn {
            timer?.invalidate()
            timer = nil
        }
    }

    private func perform(_ actions: [StayAwakeAction]) {
        let records = StayAwakeRecordStore(defaults: defaults)
        for action in actions {
            switch action {
            case .saveRecord(let record): records.save(record)
            case .clearRecord: records.clear()
            case .notifyMac(let text): notifyMac(text)
            case .notifyPhone(let text): phone.notify(text)
            case .run(let command):
                do {
                    try control.run(command)
                } catch {
                    let failure = error as? PowerControlError ?? .failed(error.localizedDescription)
                    perform(model.handle(.controlFailed(failure, command: command), now: now()))
                    return
                }
            }
        }
    }

    static func anyPhonePaired() -> Bool {
        !AuthorizedKeys.phones(in: (try? AuthorizedKeysFile.standard.read()) ?? "").isEmpty
    }

    static func postMacNotification(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Lostty"
        content.body = text
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh StayAwakeStoreTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/StayAwake/StayAwakeStore.swift macos/Tests/StayAwake/StayAwakeStoreTests.swift
git commit -m "lostty: Stay Awake store with crash-safe restore record

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: AttachedPhones

**Files:**
- Create: `macos/Sources/Features/StayAwake/AttachedPhones.swift`
- Test: `macos/Tests/StayAwake/AttachedPhonesTests.swift`

**Interfaces:**
- Consumes: `TmuxClient.run(_:)` (`TmuxClient.swift`).
- Produces: `enum AttachedPhones { static let listFormat: String; static func sessions(clients: String, parent: (Int32) -> (ppid: Int32, name: String)?) -> [String]; static func current() -> [String] }`

- [ ] **Step 1: Write the failing test**

```swift
#if os(macOS)
import Testing
@testable import Ghostty

struct AttachedPhonesTests {
    // pid: (ppid, name)
    let table: [Int32: (Int32, String)] = [
        500: (400, "tmux"), 400: (300, "zsh"), 300: (200, "sshd-session"), 200: (1, "sshd"),  // over SSH
        600: (550, "tmux"), 550: (1, "Lostty"),                                             // Mac window
        700: (690, "tmux"), 690: (1, "sshd"),                                               // older sshd name
    ]

    func parent(_ pid: Int32) -> (ppid: Int32, name: String)? { table[pid].map { (ppid: $0.0, name: $0.1) } }

    @Test func anySSHClientCountsAndMacClientsDont() {
        let clients = "500\tapi-server\n600\tidfk\n700\tapi-server\n"
        #expect(AttachedPhones.sessions(clients: clients, parent: parent) == ["api-server"])
    }

    @Test func junkAndUnknownPidsAreIgnored() {
        #expect(AttachedPhones.sessions(clients: "x\ty\n\n999\tlost\n", parent: parent) == [])
    }

    @Test func aLoopInTheTableEnds() {
        let loop: (Int32) -> (ppid: Int32, name: String)? = { pid in (ppid: pid == 10 ? 11 : 10, name: "zsh") }
        #expect(AttachedPhones.sessions(clients: "10\ts\n", parent: loop) == [])
    }
}
#endif
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh AttachedPhonesTests`
Expected: build FAILS, "cannot find 'AttachedPhones' in scope".

- [ ] **Step 3: Implement**

```swift
#if os(macOS)
import Darwin
import Foundation

/// Sessions a client attached to over SSH right now: the phone, or any
/// other SSH login. They can't be told apart, so the menu never names a phone.
enum AttachedPhones {
    static let listFormat = "#{client_pid}\t#{session_name}"

    static func current() -> [String] {
        guard let out = TmuxClient().run(["list-clients", "-F", listFormat]) else { return [] }
        return sessions(clients: out, parent: processParent)
    }

    static func sessions(clients: String, parent: (Int32) -> (ppid: Int32, name: String)?) -> [String] {
        var names = Set<String>()
        for line in clients.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 1)
            guard fields.count == 2, let pid = Int32(fields[0]) else { continue }
            if cameThroughSSH(pid, parent: parent) { names.insert(String(fields[1])) }
        }
        return names.sorted()
    }

    /// Walks up at most 10 parents looking for sshd (or sshd-session).
    private static func cameThroughSSH(_ pid: Int32, parent: (Int32) -> (ppid: Int32, name: String)?) -> Bool {
        var current = pid
        for _ in 0..<10 {
            guard current > 1, let info = parent(current) else { return false }
            if info.name.hasPrefix("sshd") { return true }
            current = info.ppid
        }
        return false
    }

    private static func processParent(_ pid: Int32) -> (ppid: Int32, name: String)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return (info.kp_eproc.e_ppid, name)
    }
}
#endif
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `macos/skins-test.sh AttachedPhonesTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/StayAwake/AttachedPhones.swift macos/Tests/StayAwake/AttachedPhonesTests.swift
git commit -m "lostty: detect SSH-attached tmux clients

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Menu bar item and AppDelegate wiring

**Files:**
- Create: `macos/Sources/Features/MenuBar/StayAwakeMenuText.swift`
- Create: `macos/Sources/Features/MenuBar/LosttyStatusItem.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (launch near `PhoneAccessUI.installMenuItem`, `applicationShouldTerminate` after the shutdown check, `applicationWillTerminate`)
- Test: `macos/Tests/MenuBar/StayAwakeMenuTextTests.swift`

**Interfaces:**
- Consumes: `StayAwakeStore` (Task 5), `StayAwakeModel.State`, `StayAwakeReason`, `PowerState`, `StayAwakeDuration` (Task 3), `AttachedPhones.current()` (Task 6), `ClaudeRuntime.shared.phases/awaiting`, `PhoneAccessUI.show()`, `PhoneAccessStore`'s phones via `PhoneAccessNames.phones(keysText:names:)`, `AppDelegate.findSurface(forUUID:)`, `BaseTerminalController.focusSurface(_:)`, `AxolotlBody`, `AxolotlStalks`, `AxolotlFronds`, `AxolotlEyes`.
- Produces:
  - `enum StayAwakeMenuText { static func status(_ state: StayAwakeModel.State, power: PowerState?, permissionInstalled: Bool, now: Date) -> String?; static func attached(_ session: String) -> String; struct ClaudeRow: Equatable { var id: UUID; var title: String; var waiting: Bool }; static func claudeRows(phases: Set<UUID>, awaiting: Set<UUID>, title: (UUID) -> String?) -> [ClaudeRow] }`
  - `@MainActor final class LosttyStatusItem: NSObject, NSMenuDelegate` with `static let shared`, `static let enabledKey = "LosttyMenuBarIcon"`, `static var isEnabled: Bool { get set }`, `func install()`, `func remove()`, `func installIfEnabled()`

- [ ] **Step 1: Write the failing tests**

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct StayAwakeMenuTextTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let battery = PowerState(lidClosed: false, onBattery: true, batteryPercent: 64, thermal: .nominal)
    let record = StayAwakeRecord(settings: .init(disableSleep: false, lowPowerOnBattery: nil, lowPowerOnAC: false), lowPowerApplied: false)

    @Test func onWithTimeLeftBatteryAndHeat() {
        let s = StayAwakeMenuText.status(.on(until: now.addingTimeInterval(2 * 3600 + 40 * 60), record: record),
                                         power: battery, permissionInstalled: true, now: now)
        #expect(s == "2h 40m left · 64% on battery · normal")
    }

    @Test func onUntilTurnedOffOnPowerHot() {
        let s = StayAwakeMenuText.status(.on(until: nil, record: record),
                                         power: .init(lidClosed: true, onBattery: false, batteryPercent: 90, thermal: .serious),
                                         permissionInstalled: true, now: now)
        #expect(s == "On until you turn it off · on power · hot")
    }

    @Test func lessThanAnHourAndRoundsUp() {
        let s = StayAwakeMenuText.status(.on(until: now.addingTimeInterval(61), record: record), power: nil, permissionInstalled: true, now: now)
        #expect(s == "2m left")
    }

    @Test func offReasons() {
        #expect(StayAwakeMenuText.status(.off(reason: .battery(15), at: now), power: nil, permissionInstalled: true, now: now)?.hasPrefix("Turned off at 15% battery · ") == true)
        #expect(StayAwakeMenuText.status(.off(reason: .heat, at: now), power: nil, permissionInstalled: true, now: now)?.hasPrefix("Turned off: the Mac got too hot · ") == true)
        #expect(StayAwakeMenuText.status(.off(reason: .timer, at: now), power: nil, permissionInstalled: true, now: now)?.hasPrefix("Time ran out · ") == true)
        #expect(StayAwakeMenuText.status(.off(reason: .restoreFailed, at: now), power: nil, permissionInstalled: true, now: now) == StayAwakeCopy.restoreFailed)
        #expect(StayAwakeMenuText.status(.off(reason: .turnedOff, at: now), power: nil, permissionInstalled: true, now: now) == nil)
        #expect(StayAwakeMenuText.status(.off(reason: nil, at: nil), power: nil, permissionInstalled: false, now: now) == "Needs the stay-awake permission")
    }

    @Test func attachedLineNamesNoPhone() {
        #expect(StayAwakeMenuText.attached("api-server") == "A phone or SSH client is attached to api-server")
    }

    @Test func claudeRowsWaitingFirstThenByTitle() {
        let a = UUID(), b = UUID(), c = UUID()
        let titles = [a: "zeta", b: "alpha", c: "mid"]
        let rows = StayAwakeMenuText.claudeRows(phases: [a, b], awaiting: [c], title: { titles[$0] })
        #expect(rows.map(\.title) == ["mid", "alpha", "zeta"])
        #expect(rows.map(\.waiting) == [true, false, false])
    }

    @Test func untitledPanesAreCalledClaude() {
        let a = UUID()
        #expect(StayAwakeMenuText.claudeRows(phases: [a], awaiting: [], title: { _ in "" }).first?.title == "Claude")
    }
}
#endif
```

- [ ] **Step 2: Run to verify they fail**

Run: `macos/skins-test.sh StayAwakeMenuTextTests`
Expected: build FAILS, "cannot find 'StayAwakeMenuText' in scope".

- [ ] **Step 3: Implement `StayAwakeMenuText.swift`**

```swift
#if os(macOS)
import Foundation

enum StayAwakeMenuText {
    static func status(_ state: StayAwakeModel.State, power: PowerState?, permissionInstalled: Bool, now: Date) -> String? {
        switch state {
        case .on(let until, _):
            var parts = [until.map { timeLeft($0.timeIntervalSince(now)) } ?? "On until you turn it off"]
            if let power {
                if power.onBattery, let percent = power.batteryPercent {
                    parts.append("\(percent)% on battery")
                } else {
                    parts.append("on power")
                }
                parts.append(heat(power.thermal))
            }
            return parts.joined(separator: " · ")
        case .off(let reason, let at):
            let time = at.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
            switch reason {
            case .battery(let percent): return "Turned off at \(percent)% battery" + time
            case .heat: return "Turned off: the Mac got too hot" + time
            case .timer: return "Time ran out" + time
            case .restoreFailed: return StayAwakeCopy.restoreFailed
            case .failed(let message): return "Couldn't turn on: \(message)"
            case .permissionMissing: return "Needs the stay-awake permission"
            case .turnedOff, nil: return permissionInstalled ? nil : "Needs the stay-awake permission"
            }
        }
    }

    static func attached(_ session: String) -> String { "A phone or SSH client is attached to \(session)" }

    struct ClaudeRow: Equatable {
        var id: UUID
        var title: String
        var waiting: Bool
    }

    /// Waiting panes first, then working ones, each by title.
    static func claudeRows(phases: Set<UUID>, awaiting: Set<UUID>, title: (UUID) -> String?) -> [ClaudeRow] {
        phases.union(awaiting).map { id in
            let t = title(id)?.trimmingCharacters(in: .whitespaces) ?? ""
            return ClaudeRow(id: id, title: t.isEmpty ? "Claude" : t, waiting: awaiting.contains(id))
        }
        .sorted { ($0.waiting ? 0 : 1, $0.title) < ($1.waiting ? 0 : 1, $1.title) }
    }

    private static func timeLeft(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.up))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left"
    }

    private static func heat(_ thermal: Thermal) -> String {
        switch thermal {
        case .nominal: "normal"
        case .fair: "warm"
        case .serious, .critical: "hot"
        }
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh StayAwakeMenuTextTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Implement `LosttyStatusItem.swift`**

```swift
#if os(macOS)
import AppKit
import Combine
import LosttyRemote
import SwiftUI

/// Lostty's menu bar icon and menu.
@MainActor
final class LosttyStatusItem: NSObject, NSMenuDelegate {
    static let shared = LosttyStatusItem()
    static let enabledKey = "LosttyMenuBarIcon"

    static var isEnabled: Bool {
        get { UserDefaults.ghostty.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.ghostty.set(newValue, forKey: enabledKey)
            newValue ? shared.install() : shared.remove()
        }
    }

    private var item: NSStatusItem?
    private var watchers: Set<AnyCancellable> = []
    private let stayAwake = StayAwakeStore.shared

    func installIfEnabled() {
        if Self.isEnabled { install() }
    }

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "Lostty"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        updateIcon()
        stayAwake.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &watchers)
        ClaudeRuntime.shared.$awaiting.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &watchers)
    }

    func remove() {
        watchers.removeAll()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func updateIcon() {
        item?.button?.image = StatusIcon.image(on: stayAwake.isOn, dot: !ClaudeRuntime.shared.awaiting.isEmpty)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        stayAwake.refreshAvailability()
        if stayAwake.isOn { stayAwake.pollPower() }

        let toggle = NSMenuItem(title: "Stay Awake for Phone", action: stayAwake.isOn ? #selector(turnOff) : nil, keyEquivalent: "")
        toggle.target = self
        toggle.state = stayAwake.isOn ? .on : .off
        if !stayAwake.isOn {
            let durations = NSMenu()
            for duration in StayAwakeDuration.allCases {
                let d = NSMenuItem(title: duration.title, action: #selector(turnOn(_:)), keyEquivalent: "")
                d.target = self
                d.representedObject = duration.rawValue
                d.isEnabled = stayAwake.available
                durations.addItem(d)
            }
            toggle.submenu = durations
        }
        menu.addItem(toggle)
        if let status = StayAwakeMenuText.status(stayAwake.model.state, power: stayAwake.power,
                                                 permissionInstalled: stayAwake.permissionInstalled, now: Date()) {
            menu.addItem(disabled("   " + status))
        }
        if !stayAwake.available && !stayAwake.isOn {
            menu.addItem(action("Set Up Phone Access…", #selector(openPhoneAccess)))
        }

        menu.addItem(.separator())
        menu.addItem(disabled("Phones"))
        let names = PhoneAccessNames(defaults: .ghostty).entries()
        let phones = PhoneAccessNames.phones(keysText: (try? AuthorizedKeysFile.standard.read()) ?? "", names: names)
        if phones.isEmpty { menu.addItem(disabled("   None paired")) }
        for phone in phones { menu.addItem(disabled("   " + phone.name)) }
        for session in AttachedPhones.current() { menu.addItem(disabled("   " + StayAwakeMenuText.attached(session))) }

        let rows = StayAwakeMenuText.claudeRows(
            phases: Set(ClaudeRuntime.shared.phases.keys), awaiting: ClaudeRuntime.shared.awaiting,
            title: { (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: $0)?.title })
        if !rows.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled("Claude"))
            for row in rows {
                let r = NSMenuItem(title: "   \(row.waiting ? "●" : "○") \(row.title) — \(row.waiting ? "waiting for you" : "working")",
                                   action: #selector(focusPane(_:)), keyEquivalent: "")
                r.target = self
                r.representedObject = row.id
                menu.addItem(r)
            }
        }

        menu.addItem(.separator())
        menu.addItem(action("New Window", #selector(newWindow)))
        menu.addItem(action("Phone Access…", #selector(openPhoneAccess)))
        menu.addItem(action("Pair a Phone…", #selector(pairPhone)))
        let floors = NSMenu()
        for floor in StayAwakeStore.floors {
            let f = NSMenuItem(title: "\(floor)%", action: #selector(setFloor(_:)), keyEquivalent: "")
            f.target = self
            f.representedObject = floor
            f.state = floor == stayAwake.batteryFloor ? .on : .off
            floors.addItem(f)
        }
        let floorItem = NSMenuItem(title: "Battery Floor", action: nil, keyEquivalent: "")
        floorItem.submenu = floors
        menu.addItem(floorItem)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func turnOn(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let duration = StayAwakeDuration(rawValue: raw) else { return }
        stayAwake.turnOn(duration)
        updateIcon()
    }

    @objc private func turnOff() {
        stayAwake.turnOff()
        updateIcon()
    }

    @objc private func setFloor(_ sender: NSMenuItem) {
        if let floor = sender.representedObject as? Int { stayAwake.batteryFloor = floor }
    }

    @objc private func openPhoneAccess() { PhoneAccessUI.show() }

    @objc private func pairPhone() {
        PhoneAccessUI.show()
        PhoneAccessUI.startPairingWhenReady()
    }

    @objc private func newWindow() {
        NSApp.activate(ignoringOtherApps: true)
        (NSApp.delegate as? AppDelegate)?.newWindow(nil)
    }

    @objc private func focusPane(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let surface = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: id),
              let controller = surface.window?.windowController as? BaseTerminalController
        else { return }
        NSApp.activate(ignoringOtherApps: true)
        surface.window?.makeKeyAndOrderFront(nil)
        controller.focusSurface(surface)
    }
}

/// The axolotl as an 18 pt template image: outline when off, body filled
/// when Stay Awake is on, a dot when a Claude is waiting.
enum StatusIcon {
    @MainActor
    static func image(on: Bool, dot: Bool) -> NSImage? {
        let view = ZStack(alignment: .topTrailing) {
            ZStack {
                if on { AxolotlBody().fill(.black) }
                AxolotlBody().stroke(.black, lineWidth: 1.4)
                AxolotlStalks(side: .left).stroke(.black, lineWidth: 1.2)
                AxolotlStalks(side: .right).stroke(.black, lineWidth: 1.2)
                AxolotlFronds(side: .left).stroke(.black, lineWidth: 1)
                AxolotlFronds(side: .right).stroke(.black, lineWidth: 1)
                if !on { AxolotlEyes().stroke(.black, lineWidth: 1.2) }
            }
            if dot { Circle().fill(.black).frame(width: 5, height: 5) }
        }
        .frame(width: 18, height: 18)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = "Lostty"
        return image
    }
}
#endif
```

Before writing `StatusIcon`, open `macos/Sources/Features/LosttyDesign/AxolotlShapes.swift` and use the real initializers of `AxolotlBody`, `AxolotlStalks(side:)`, `AxolotlFronds(side:)`, `AxolotlEyes` (if `AxolotlEyes` takes a parameter such as the cursor state, pass the resting value used by `Axolotl`'s `.resting` pose).

- [ ] **Step 6: Add `startPairingWhenReady` to `PhoneAccessUI`**

In `macos/Sources/Features/PhoneAccess/PhoneAccessUI.swift`, inside `enum PhoneAccessUI` after `show()`:

```swift
    /// Pair a Phone from the menu bar: opening the window runs the checks;
    /// pair once they say it can (up to 5 s), else leave the checklist showing.
    static func startPairingWhenReady() {
        Task { @MainActor in
            for _ in 0..<20 {
                if store.canPair {
                    store.startPairing()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
```

- [ ] **Step 7: Wire AppDelegate**

In `applicationDidFinishLaunching`, right after `PhoneAccessUI.installMenuItem(after: menuOpenConfig)`:

```swift
        // Lostty Mobile: put back power settings a crashed Lostty left
        // changed, then the menu bar icon (Stay Awake for Phone).
        StayAwakeStore.shared.start()
        LosttyStatusItem.shared.installIfEnabled()
```

In `applicationShouldTerminate`, as its very first lines (before `let windows = …`, whose early returns would skip the question when no window is open, which is exactly the menu-bar-only case), insert:

```swift
        // Lostty Mobile: quitting ends Stay Awake for Phone and this Mac's
        // sessions; one confirmation covers both. Never on shutdown.
        if StayAwakeStore.shared.isOn && !Self.systemIsEnding() {
            let alert = NSAlert()
            alert.messageText = "Stay Awake for Phone is on."
            alert.informativeText = "Quitting lets the Mac sleep and ends this Mac's sessions."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
        }
```

Add next to `anyPaneNeedsConfirmQuit()`:

```swift
    /// Lostty Mobile: shutdown, restart or logout, which never ask first.
    private static func systemIsEnding() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let keyword = AEKeyword("why?"),
              let why = event.attributeDescriptor(forKeyword: keyword)
        else { return false }
        switch why.typeCodeValue {
        case kAEShutDown, kAERestart, kAEReallyLogOut: return true
        default: return false
        }
    }
```

In `applicationWillTerminate`, before the `TmuxClient().endSessions` line:

```swift
        // Lostty Mobile: let the Mac sleep again as it did before.
        StayAwakeStore.shared.quit()
```

- [ ] **Step 8: Build both apps**

Run: `macos/build.nu --configuration Debug --action build`
Expected: build succeeds.
Run the iOS build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add macos/Sources/Features/MenuBar/StayAwakeMenuText.swift macos/Sources/Features/MenuBar/LosttyStatusItem.swift macos/Tests/MenuBar/StayAwakeMenuTextTests.swift macos/Sources/Features/PhoneAccess/PhoneAccessUI.swift macos/Sources/App/macOS/AppDelegate.swift
git commit -m "lostty: menu bar icon with Stay Awake for Phone

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Phone Access permission row, Turn Off and menu bar checkbox

**Files:**
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessChecks.swift` (`PhoneAccessStatus`, `PhoneAccessProbe.run`)
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessModel.swift` (`PhoneAccessRow`)
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessStore.swift` (`fix`, `runAdmin`, `turnOff`)
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift` (labels, note, checkbox)
- Test: `macos/Tests/PhoneAccess/PhoneAccessModelTests.swift`

**Interfaces:**
- Consumes: `SystemPowerControl().hasPermission()`, `StayAwakeSudoers.installScript(user:)`, `StayAwakeSudoers.removeScript`, `StayAwakeSudoers.path` (Task 2); `StayAwakeStore.shared.turnOff()`, `.refreshAvailability()` (Task 5); `LosttyStatusItem.isEnabled` (Task 7).
- Produces: `PhoneAccessStatus.stayAwakePermission: Bool` (default `false`), `PhoneAccessRow.Kind.stayAwake`, `PhoneAccessRow.Fix.installStayAwake`.

- [ ] **Step 1: Write the failing tests**

In `PhoneAccessModelTests.swift`, change the `ready` fixture to pass `stayAwakePermission: true` (after `folders:`), change `allDoneIsAllOK`'s expected ids to `[.tailscale, .tmux, .remoteLogin, .passwords, .firewall, .terminfo, .stayAwake, .folders]`, and add:

```swift
    @Test func stayAwakePermissionIsOfferedAndNeverBlocksPairing() {
        var s = ready
        s.stayAwakePermission = false
        let r = row(.stayAwake, s)
        #expect(r.state == .missing)
        #expect(r.fixes == [.installStayAwake])
        #expect(r.title == "Stay-awake permission")
        #expect(s.readyToPair(lockdownSkipped: false))
        s.stayAwakePermission = true
        #expect(row(.stayAwake, s).state == .ok)
        #expect(row(.stayAwake, s).fixes.isEmpty)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `macos/skins-test.sh PhoneAccessRowsTests`
Expected: build FAILS, "extra argument 'stayAwakePermission'".

- [ ] **Step 3: Implement status, probe and row**

In `PhoneAccessStatus`, after `var folders: [String: Bool]? = nil`:

```swift
    /// The sudoers rule Stay Awake for Phone needs. Optional: never blocks
    /// pairing.
    var stayAwakePermission: Bool = false
```

In `PhoneAccessProbe.run`, add the argument to the returned status after `folders:`:

```swift
            folders: foldersRequested ? PhoneAccessFolders.check() : nil,
            stayAwakePermission: SystemPowerControl().hasPermission())
```

(replace the existing `folders: …)` line accordingly).

In `PhoneAccessRow`: add `stayAwake` to `Kind` (after `terminfo`), `installStayAwake` to `Fix`, and in `rows(for:lockdownSkipped:)` just before the `// Optional: never blocks pairing.` folders block:

```swift
        rows.append(s.stayAwakePermission
            ? .init(id: .stayAwake, title: "Stay-awake permission", detail: "Lostty can keep this Mac awake for your phone.", state: .ok, fixes: [])
            : .init(id: .stayAwake, title: "Stay-awake permission",
                    detail: "Lets Stay Awake for Phone keep this Mac awake with the lid closed. Lostty may then run only pmset's sleep and Low Power Mode settings as root.",
                    state: .missing, fixes: [.installStayAwake]))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh PhoneAccessRowsTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Store: install fix, one prompt for setup, Turn Off removal**

In `PhoneAccessStore`, next to `skipDefaultsKey`:

```swift
    static let stayAwakePrompt = "Lostty wants to keep this Mac awake for your phone when you ask it to."
```

In `PhoneAccessStore.fix(_:)` add the case:

```swift
        case .installStayAwake:
            guard let script = StayAwakeSudoers.installScript(user: NSUserName()) else {
                message = "Stay Awake for Phone can't be set up for this account name."
                return
            }
            if case .failed(let text) = PhoneAccessAdmin.run(script, prompt: Self.stayAwakePrompt) {
                message = text
            }
            StayAwakeStore.shared.refreshAvailability()
            refresh()
```

Replace `runAdmin` so the first admin prompt also installs a missing rule:

```swift
    private func runAdmin(enableRemoteLogin: Bool, lockPasswords: Bool) {
        let setup = PhoneAccessAdmin.setupScript(enableRemoteLogin: enableRemoteLogin, lockPasswords: lockPasswords)
        let stayAwake = status?.stayAwakePermission == false ? StayAwakeSudoers.installScript(user: NSUserName()) : nil
        let script = [setup, stayAwake].compactMap { $0 }.joined(separator: "\n")
        guard !script.isEmpty else {
            refresh()
            return
        }
        var prompt = setup == nil
            ? Self.stayAwakePrompt
            : PhoneAccessAdmin.prompt(enableRemoteLogin: enableRemoteLogin, lockPasswords: lockPasswords)
        if setup != nil && stayAwake != nil { prompt += " It also lets Lostty keep this Mac awake for your phone when you ask." }
        switch PhoneAccessAdmin.run(script, prompt: prompt) {
        case .done, .cancelled: break
        case .failed(let text): message = text
        }
        StayAwakeStore.shared.refreshAvailability()
        refresh()
    }
```

In `turnOff()`, right after `stopPairing()`:

```swift
        StayAwakeStore.shared.turnOff()
```

and replace the password-unlock block with one that removes the rule in the same prompt:

```swift
        var adminScripts: [String] = []
        var prompts: [String] = []
        if FileManager.default.fileExists(atPath: StayAwakeSudoers.path) {
            adminScripts.append(StayAwakeSudoers.removeScript)
            prompts.append("remove its permission to keep this Mac awake")
        }
        if FileManager.default.fileExists(atPath: PhoneAccessProbe.lockdownPath) {
            let unlock = NSAlert()
            unlock.messageText = "Turn password logins back on?"
            unlock.informativeText = "Lostty turned them off for Phone Access. Keeping them off is safer."
            unlock.addButton(withTitle: "Keep Them Off")
            unlock.addButton(withTitle: "Turn Back On")
            if unlock.runModal() == .alertSecondButtonReturn {
                adminScripts.append(PhoneAccessAdmin.unlockScript)
                prompts.append("turn password logins back on")
            }
        }
        if !adminScripts.isEmpty,
           case .failed(let text) = PhoneAccessAdmin.run(adminScripts.joined(separator: "\n"),
                                                         prompt: "Lostty wants to " + prompts.joined(separator: " and ") + ".") {
            message = text
        }
        StayAwakeStore.shared.refreshAvailability()
```

- [ ] **Step 6: View: fix label, awake note, menu bar checkbox**

In `PhoneAccessView.label(_:)` add `case .installStayAwake: "Install…"`.

Replace the awake note `Text(...)` with:

```swift
                Text("Your phone can reach this Mac only while it's awake. Stay Awake for Phone in the menu bar keeps it awake with the lid closed.")
                    .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                Toggle("Show Lostty in the menu bar", isOn: Binding(
                    get: { LosttyStatusItem.isEnabled },
                    set: { LosttyStatusItem.isEnabled = $0 }))
                    .font(LosttyFont.body).foregroundStyle(LosttyTheme.textPrimary)
```

- [ ] **Step 7: Run Phone Access suites and build**

Run: `macos/skins-test.sh PhoneAccessRowsTests`, `macos/skins-test.sh PhoneAccessAdminTests`, `macos/skins-test.sh PhoneAccessChecksTests`, `macos/skins-test.sh PhoneAccessGalleryTests`
Expected: `** TEST SUCCEEDED **` for each. Galleries that build a status by memberwise init compile unchanged thanks to the default; if a gallery test asserts a row count or "n of 7 ready", update it to the new row (8) and set `stayAwakePermission: true` in its all-ready state.
Run: `macos/build.nu --configuration Debug --action build`
Expected: succeeds.

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/PhoneAccess/PhoneAccessChecks.swift macos/Sources/Features/PhoneAccess/PhoneAccessModel.swift macos/Sources/Features/PhoneAccess/PhoneAccessStore.swift macos/Sources/Features/PhoneAccess/PhoneAccessView.swift macos/Tests/PhoneAccess/PhoneAccessModelTests.swift
git commit -m "lostty: Phone Access installs and removes the stay-awake permission

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: HotspotFallbackModel (skip if the spike cut the no-internet half)

**Files:**
- Create: `macos/Sources/Features/StayAwake/HotspotFallback.swift` (model part)
- Test: `macos/Tests/StayAwake/HotspotFallbackModelTests.swift`

**Interfaces:**
- Produces: `struct HotspotFallbackModel { var hotspot: String?; mutating func observe(internetOK: Bool, onWiFi: Bool, currentSSID: String?, active: Bool, now: Date) -> Bool }` (true: switch to the hotspot now). Constants `failAfter = 60`, `cooldown = 600`.

- [ ] **Step 1: Write the failing tests**

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct HotspotFallbackModelTests {
    let t0 = Date(timeIntervalSince1970: 0)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func failing(_ m: inout HotspotFallbackModel, from: TimeInterval, to: TimeInterval, ssid: String? = "Cafe") -> [Bool] {
        stride(from: from, through: to, by: 15).map {
            m.observe(internetOK: false, onWiFi: true, currentSSID: ssid, active: true, now: at($0))
        }
    }

    @Test func switchesAfterSixtySecondsOfFailedProbes() {
        var m = HotspotFallbackModel(hotspot: "Phone")
        #expect(failing(&m, from: 0, to: 45) == [false, false, false, false])
        #expect(m.observe(internetOK: false, onWiFi: true, currentSSID: "Cafe", active: true, now: at(60)))
    }

    @Test func aGoodProbeResetsTheClock() {
        var m = HotspotFallbackModel(hotspot: "Phone")
        _ = failing(&m, from: 0, to: 45)
        #expect(!m.observe(internetOK: true, onWiFi: true, currentSSID: "Cafe", active: true, now: at(50)))
        #expect(!m.observe(internetOK: false, onWiFi: true, currentSSID: "Cafe", active: true, now: at(60)))
    }

    @Test func neverWhenAlreadyOnTheHotspotOffWiFiInactiveOrUnchosen() {
        var onHotspot = HotspotFallbackModel(hotspot: "Phone")
        #expect(!failing(&onHotspot, from: 0, to: 120, ssid: "Phone").contains(true))
        var noWiFi = HotspotFallbackModel(hotspot: "Phone")
        #expect(!(0...8).map { noWiFi.observe(internetOK: false, onWiFi: false, currentSSID: nil, active: true, now: at(Double($0) * 15)) }.contains(true))
        var inactive = HotspotFallbackModel(hotspot: "Phone")
        #expect(!(0...8).map { inactive.observe(internetOK: false, onWiFi: true, currentSSID: "Cafe", active: false, now: at(Double($0) * 15)) }.contains(true))
        var unchosen = HotspotFallbackModel(hotspot: nil)
        #expect(!failing(&unchosen, from: 0, to: 120).contains(true))
    }

    @Test func tenMinuteCooldown() {
        var m = HotspotFallbackModel(hotspot: "Phone")
        _ = failing(&m, from: 0, to: 60)
        #expect(!failing(&m, from: 75, to: 645).contains(true))
        #expect(failing(&m, from: 660, to: 720).contains(true))
    }
}
#endif
```

- [ ] **Step 2: Run to verify they fail**

Run: `macos/skins-test.sh HotspotFallbackModelTests`
Expected: build FAILS, "cannot find 'HotspotFallbackModel' in scope".

- [ ] **Step 3: Implement the model**

```swift
#if os(macOS)
import Foundation

/// When to give up on a Wi-Fi network with no internet and move to the
/// iPhone hotspot. Never switches back: macOS rejoins known Wi-Fi itself.
struct HotspotFallbackModel {
    static let failAfter: TimeInterval = 60
    static let cooldown: TimeInterval = 600

    var hotspot: String?
    private(set) var failingSince: Date?
    private(set) var lastSwitch: Date?

    init(hotspot: String?) { self.hotspot = hotspot }

    mutating func observe(internetOK: Bool, onWiFi: Bool, currentSSID: String?, active: Bool, now: Date) -> Bool {
        guard active, let hotspot, onWiFi, currentSSID != hotspot, !internetOK else {
            failingSince = nil
            return false
        }
        let since = failingSince ?? now
        failingSince = since
        guard now.timeIntervalSince(since) >= Self.failAfter else { return false }
        if let lastSwitch, now.timeIntervalSince(lastSwitch) < Self.cooldown { return false }
        lastSwitch = now
        failingSince = nil
        return true
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh HotspotFallbackModelTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/StayAwake/HotspotFallback.swift macos/Tests/StayAwake/HotspotFallbackModelTests.swift
git commit -m "lostty: rules for moving to the iPhone hotspot

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Hotspot runtime, picker and auto-join row

If the spike cut the no-internet half, do only Step 4 (the auto-join row) and Step 6.

**Files:**
- Modify: `macos/Sources/Features/StayAwake/HotspotFallback.swift` (runtime)
- Modify: `macos/Sources/Features/StayAwake/StayAwakeStore.swift` (start/stop the watcher)
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift` (picker, auto-join note)

**Interfaces:**
- Consumes: `HotspotFallbackModel` (Task 9), `StayAwakeStore.isOn`, `StayAwakeStore.notifyMac`/`phone` (Task 5).
- Produces: `@MainActor final class HotspotFallback { static let ssidKey = "LosttyHotspotSSID"; static var chosen: String? { get set }; static func knownNetworks() -> [String]; init(onSwitch: @escaping (String) -> Void); func start(); func stop() }`

- [ ] **Step 1: Implement the runtime**

Append to `HotspotFallback.swift`, inside the `#if os(macOS)` block:

```swift
import CoreWLAN
import Network

/// While Stay Awake is on: probe the internet every 15 s on Wi-Fi and move
/// to the chosen hotspot when `HotspotFallbackModel` says so.
@MainActor
final class HotspotFallback {
    static let ssidKey = "LosttyHotspotSSID"
    static let probeURL = URL(string: "https://captive.apple.com/hotspot-detect.html")!

    static var chosen: String? {
        get { UserDefaults.ghostty.string(forKey: ssidKey) }
        set { UserDefaults.ghostty.set(newValue, forKey: ssidKey) }
    }

    /// Wi-Fi networks this Mac remembers, for the picker.
    static func knownNetworks() -> [String] {
        let profiles = CWWiFiClient.shared().interface()?.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
        return profiles.compactMap(\.ssid).sorted()
    }

    private var model = HotspotFallbackModel(hotspot: nil)
    private let monitor = NWPathMonitor()
    private var onWiFi = false
    private var timer: Timer?
    private let onSwitch: (String) -> Void

    init(onSwitch: @escaping (String) -> Void) { self.onSwitch = onSwitch }

    func start() {
        model = HotspotFallbackModel(hotspot: Self.chosen)
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.usesInterfaceType(.wifi)
            DispatchQueue.main.async { self?.onWiFi = wifi }
        }
        monitor.start(queue: .global(qos: .utility))
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.probe() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        monitor.cancel()
    }

    private func probe() {
        var request = URLRequest(url: Self.probeURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
                && String(decoding: data ?? Data(), as: UTF8.self).contains("Success")
            DispatchQueue.main.async { MainActor.assumeIsolated { self.decide(internetOK: ok) } }
        }.resume()
    }

    private func decide(internetOK: Bool) {
        let iface = CWWiFiClient.shared().interface()
        guard model.observe(internetOK: internetOK, onWiFi: onWiFi, currentSSID: iface?.ssid(),
                            active: StayAwakeStore.shared.isOn, now: Date()),
              let hotspot = model.hotspot, let iface else { return }
        do {
            let target = try iface.scanForNetworks(withName: hotspot).first
            guard let target else { throw HotspotNotVisible() }
            var password: NSString?
            _ = CWKeychainFindWiFiPassword(.system, Data(hotspot.utf8), &password)
            try iface.associate(to: target, password: password as String?)
            onSwitch("Moved to \(hotspot): the Wi-Fi had no internet.")
        } catch {
            onSwitch("Couldn't reach \(hotspot). Lostty tries again in 10 minutes.")
        }
    }
}

private struct HotspotNotVisible: Error {}
```

Adjust the keychain call to what the spike found works (Task 1 Step 5); if the spike needed `.user` instead of `.system`, use that.

- [ ] **Step 2: Start and stop it with Stay Awake**

In `StayAwakeStore`, add a property and use it where polling starts and stops:

```swift
    private lazy var hotspot = HotspotFallback { [weak self] text in
        self?.notifyMac(text)
        self?.phone.notify(text)
    }
```

In `turnOn(_:)`, after `if isOn { startPolling() }` change to `if isOn { startPolling(); hotspot.start() }`. In `send(_:)`, inside `if !isOn { … }` add `hotspot.stop()`.

- [ ] **Step 3: Picker in Phone Access**

In `PhoneAccessView`, below the menu bar `Toggle`:

```swift
                Picker("Your iPhone's hotspot", selection: Binding(
                    get: { HotspotFallback.chosen ?? "" },
                    set: { HotspotFallback.chosen = $0.isEmpty ? nil : $0 })) {
                    Text("None").tag("")
                    ForEach(HotspotFallback.knownNetworks(), id: \.self) { Text($0).tag($0) }
                }
                .font(LosttyFont.body)
                Text("While Stay Awake is on, if the Wi-Fi has no internet for a minute, Lostty moves this Mac to this hotspot.")
                    .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                if HotspotFallback.knownNetworks().isEmpty {
                    Text("No networks to pick from? Allow Lostty in System Settings → Privacy & Security → Location Services; macOS hides Wi-Fi names without it.")
                        .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                }
```

- [ ] **Step 4: Auto-join note**

Below the picker (or below the menu bar `Toggle` if the no-internet half was cut):

```swift
                HStack {
                    Text("Turn on joining your iPhone's hotspot automatically, so the Mac moves to it when Wi-Fi is gone.")
                        .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                    Button("Open Wi-Fi Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
                    }
                    .buttonStyle(.lostty(.quiet))
                }
```

If the spike found a readable domain/key for the setting, also show `✓ On` instead of the button when it reads as on, using `Command.run("/usr/bin/defaults", ["read", "<domain>", "<key>"])` with the exact domain and key recorded in spec §10.

- [ ] **Step 5: Build**

Run: `macos/build.nu --configuration Debug --action build` and the iOS build.
Expected: both succeed.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/StayAwake/HotspotFallback.swift macos/Sources/Features/StayAwake/StayAwakeStore.swift macos/Sources/Features/PhoneAccess/PhoneAccessView.swift
git commit -m "lostty: move to the iPhone hotspot when Wi-Fi has no internet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Docs and desk checks (needs the human)

**Files:**
- Modify: `docs/lostty-mobile-host-setup.md` (step 7)
- Modify: `docs/lostty-mobile-phone-access.md`

- [ ] **Step 1: Host setup step 7**

Replace step 7 with:

```markdown
7. **Awake in a bag** (optional): Phone Access → Stay-awake permission →
   Install, then menu bar → Lostty → Stay Awake for Phone. By hand instead:
   `sudo pmset -a disablesleep 1` (and `sudo pmset -a disablesleep 0` to
   undo). Set the Mac's Wi-Fi to join the iPhone's hotspot automatically.
   Expect heat under heavy builds and battery drain.
```

- [ ] **Step 2: Phone access doc**

Replace `Your phone can reach the Mac only while the Mac is awake and Lostty is open.` with:

```markdown
Your phone can reach the Mac only while the Mac is awake and Lostty is open.
To keep it awake with the lid closed, install the **Stay-awake permission** in
Phone Access, then choose **Stay Awake for Phone** from Lostty's menu bar icon.
While it's on, Low Power Mode is on whenever the lid is closed, and it turns
itself off at your battery floor (15% by default) or if the Mac gets too hot.
Pick **Your iPhone's hotspot** in Phone Access and Lostty moves the Mac to it
when the Wi-Fi has no internet.
```

Add to Troubleshooting:

```markdown
- **The Mac never sleeps** after Lostty was force-quit while Stay Awake was
  on: open Lostty once (it puts things back), or run
  `sudo pmset -a disablesleep 0`.
```

Add to the "If you deleted Lostty instead" list:

```markdown
- `sudo rm /etc/sudoers.d/lostty` and `sudo pmset -a disablesleep 0`;
```

- [ ] **Step 3: Commit docs**

```bash
git add docs/lostty-mobile-host-setup.md docs/lostty-mobile-phone-access.md
git commit -m "lostty: document Stay Awake for Phone

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Desk checks (human, on the MacBook)**

Run the spec's manual checklist and note each result:

1. Phone Access → Install the permission; `sudo -n -l /usr/bin/pmset -a disablesleep 0` succeeds; `ls -l /etc/sudoers.d/lostty` shows `-r--r----- root wheel`.
2. Stay Awake for Phone → Until I Turn It Off; close the lid on battery; from the phone over LTE attach a session and run a command; the menu (after opening the lid) showed "A phone or SSH client is attached to …"; `pmset -g custom` shows the original Low Power Mode values.
3. Battery Floor 30% with the battery below 30%: turning on is refused with "Turned off at …% battery".
4. Battery Floor just under the current level, unplug, wait: notification "Mac is going to sleep — battery at …%", `pmset -g` has no `SleepDisabled 1`.
5. `kill -9` Lostty while on; relaunch; `pmset -g` has no `SleepDisabled 1`.
6. `sudo pmset -a disablesleep 1` by hand, turn on then off: still `SleepDisabled 1`; then undo by hand.
7. Quit while on: the confirmation appears; after Quit, `SleepDisabled` is gone.
8. Turn Off Phone Access: `/etc/sudoers.d/lostty` is gone.
9. Icon: outline when off, filled when on, dot when a Claude waits; Show Lostty in the menu bar off/on removes and restores it.
10. If built: lid closed, router Wi-Fi off → Mac on the hotspot and the phone reattaches; router uplink unplugged → within ~75 s the Mac is on the hotspot.

Any failure: use superpowers:systematic-debugging, fix in the owning task's files, rerun that task's tests, and commit with a message naming the check.
