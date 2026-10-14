# Lostty Restart to Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Installing a new Lostty never costs you your terminals: Lostty notices it was replaced, offers Restart to Update, and comes back with every window, tab and split still attached to the same tmux sessions, Claude state and Stay Awake intact.

**Architecture:** A restart writes a small handoff file, forces macOS window restoration on, starts a detached helper that reopens the app once this process has exited, and terminates without ending its sessions. At launch, existing Ghostty state restoration plus the launcher's `claimOrphan` reattach every pane; the handoff restores Claude state, Stay Awake, the window setting, and (if needed) the Claude hooks. A bundle watch shows the menu items; the install script keeps the previous build for going back.

**Tech Stack:** Swift / AppKit (macOS), Swift Testing, POSIX `posix_spawn`, AppleScript (`Ghostty.sdef`), POSIX sh.

**Spec:** `docs/superpowers/specs/2026-10-13-lostty-restart-to-update-design.md`

## Global Constraints

- Another Claude session edits this working tree (it touched `AppDelegate.swift`, `ClaudeTmuxSync.swift`, `ClaudeWorkingLineWatch.swift` today). Re-read a file right before editing it, anchor edits on quoted text, never revert others' changes.
- No commits, no branch switches: the user commits.
- Mac-only code: every new Swift file wrapped in `#if os(macOS)`. New tests go in `macos/Tests/Restart/` (Swift Testing, `@testable import Lostty`).
- Run one Mac suite: `macos/skins-test.sh <Suite>`; build: `macos/build.nu`. `swiftlint` isn't installed; skip it.
- Handoff file: `~/Library/Application Support/Lostty/restart-<bundle id>.json`; fresh = written by a pid that's no longer running, at most 120 seconds ago.
- Previous build: `/Applications/Lostty (previous).app`.
- Never quit or kill the user's running Lostty without asking: Quit ends every session it owns.
- Menu titles: "Restart to Update (Keeps Terminals)", "Go Back to Previous Build". AppleScript command: `restart to update`.

## Review Focus

1. **A stale or foreign handoff** (Lostty crashed mid-restart and was opened 10 minutes later, or the handoff names a pid still running) must change nothing: the crash prompt shows as today, no Claude state is invented. Pinned in Task 2 (`aStaleOrLiveHandoffIsNotFresh`).
2. **The helper must not inherit Lostty's file descriptors** (the notes lock leaked that way today): pinned in Task 3 (`theHelperDoesNotInheritDescriptors`).
3. **The Debug build and the installed app** restarting near each other must not consume each other's handoff: pinned in Task 2 (`eachBuildHasItsOwnHandoff`).
4. **A half-copied bundle** (install still running when the watch checks) must not light up Restart: pinned in Task 4 (`aMissingExecutableIsNotAnUpdate`).
5. **A second click** on Restart while one is underway must not spawn a second helper: pinned in Task 3 (`restartingTwiceIsOnce` via `LosttyRestart.begin`).

---

## File Structure

| File | Responsibility |
|---|---|
| Modify `macos/Sources/Features/Claude/ClaudeRuntime.swift` | `ClaudeCarry`; `carry()` and `restore(_:)` |
| Create `macos/Sources/Features/Restart/RestartHandoff.swift` | The handoff: Codable model, file per bundle id, freshness, take-and-delete |
| Create `macos/Sources/Features/Restart/LosttyRestart.swift` | `restart(reason:)`, `resumeIfRestarted()`, the detached helper, the termination switch |
| Create `macos/Sources/Features/Restart/BundleWatch.swift` | Notices the app was replaced (`updateReady`) |
| Create `macos/Sources/Features/Restart/PreviousBuild.swift` | Swapping `Lostty.app` and `Lostty (previous).app` |
| Create `macos/Sources/Features/Restart/RestartUI.swift` | The app-menu item |
| Create `macos/Sources/Features/Restart/ScriptRestartCommand.swift` | AppleScript `restart to update` |
| Modify `macos/Sources/App/macOS/AppDelegate.swift` | Termination keeps sessions while restarting; resume at launch; start the watch; menu item |
| Modify `macos/Sources/Features/MenuBar/LosttyStatusItem.swift` | Menu items and the icon's update arrow |
| Modify `macos/Ghostty.sdef` | The `restart to update` command |
| Modify `macos/install-skins.sh` | Keep the previous build; `--previous` |
| Modify `macos/AGENTS.md` | How agents update Lostty |
| Tests: `macos/Tests/Claude/ClaudeRuntimeTests.swift` (add), `macos/Tests/Restart/*.swift` (new) | |

---

### Task 1: Carry Claude state across a restart

**Files:**
- Modify: `macos/Sources/Features/Claude/ClaudeRuntime.swift` (append before the final `#endif`)
- Test: `macos/Tests/Claude/ClaudeRuntimeTests.swift` (append tests inside `struct ClaudeRuntimeTests`)

**Interfaces:**
- Produces: `struct ClaudeCarry: Codable, Equatable` with `enum Activity: String, Codable { case working, subagents, waiting }`, `activity`, `action: String?`; `ClaudeRuntime.carry() -> [UUID: ClaudeCarry]`; `ClaudeRuntime.restore(_ carried: [UUID: ClaudeCarry])`.

- [ ] **Step 1: Write the failing tests**

Append inside `struct ClaudeRuntimeTests { … }` (before its closing brace):

```swift
    // MARK: Restart

    @Test func carryReadsWhatThePanesShow() {
        let runtime = makeRuntime()
        let working = UUID(), agents = UUID(), waiting = UUID()
        runtime.apply(.busy, to: working)
        runtime.apply(.agents, to: agents)
        runtime.focusChanged(waiting, focused: false)
        runtime.apply(.busy, to: waiting)
        runtime.apply(.idle, to: waiting, permission: true)
        let carried = runtime.carry()
        #expect(carried[working]?.activity == .working)
        #expect(carried[agents]?.activity == .subagents)
        #expect(carried[waiting]?.activity == .waiting)
        #expect(carried.count == 3)
    }

    @Test func restoreShowsThemAgain() {
        let runtime = makeRuntime()
        let working = UUID(), agents = UUID(), waiting = UUID()
        runtime.restore([
            working: ClaudeCarry(activity: .working, action: "Editing Foo.swift"),
            agents: ClaudeCarry(activity: .subagents, action: nil),
            waiting: ClaudeCarry(activity: .waiting, action: "Run the iOS tests"),
        ])
        #expect(runtime.phase(working) == .racing(since: harness.clock))
        #expect(runtime.phase(agents) == .racing(since: harness.clock, subagents: true))
        #expect(runtime.awaiting == [waiting])
        #expect(runtime.actions == [working: "Editing Foo.swift", waiting: "Run the iOS tests"])
    }

    @Test func aCarryRoundTripsThroughJSON() throws {
        let carry = ClaudeCarry(activity: .waiting, action: "Run the iOS tests")
        #expect(try JSONDecoder().decode(ClaudeCarry.self, from: JSONEncoder().encode(carry)) == carry)
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh ClaudeRuntimeTests`
Expected: build FAILS: "cannot find 'ClaudeCarry' in scope" / "value of type 'ClaudeRuntime' has no member 'carry'".

- [ ] **Step 3: Implement**

Append to `macos/Sources/Features/Claude/ClaudeRuntime.swift`, just before its final `#endif` (same file, so the extension can use the private `store`, `setAction` and `now`):

```swift
/// A pane's Claude as a restart hands it on (`LosttyRestart`): hooks fired
/// while Lostty is down are lost, so the new Lostty starts from this.
struct ClaudeCarry: Codable, Equatable {
    enum Activity: String, Codable {
        case working, subagents, waiting
    }

    var activity: Activity
    var action: String?
}

extension ClaudeRuntime {
    /// What each pane's Claude is doing now, for a restart to hand on.
    func carry() -> [UUID: ClaudeCarry] {
        var carried: [UUID: ClaudeCarry] = [:]
        for (id, phase) in phases {
            guard case .racing(_, let subagents) = phase else { continue }
            carried[id] = ClaudeCarry(activity: subagents ? .subagents : .working, action: actions[id])
        }
        for id in awaiting {
            carried[id] = ClaudeCarry(activity: .waiting, action: actions[id])
        }
        return carried
    }

    /// After a restart: the panes' Claudes as the old Lostty last saw them.
    /// The restored panes keep their UUIDs.
    func restore(_ carried: [UUID: ClaudeCarry]) {
        for (id, carry) in carried {
            switch carry.activity {
            case .working: store(.racing(since: now()), for: id)
            case .subagents: store(.racing(since: now(), subagents: true), for: id)
            case .waiting: awaiting.insert(id)
            }
            setAction(carry.action, for: id)
        }
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `macos/skins-test.sh ClaudeRuntimeTests`
Expected: `** TEST SUCCEEDED **`. If `carryReadsWhatThePanesShow` finds no waiting pane, check `apply(.idle, …)` keeps `awaiting` for an unfocused pane (it does when `unfocused` contains it and it wasn't `seen`).

---

### Task 2: The handoff file

**Files:**
- Create: `macos/Sources/Features/Restart/RestartHandoff.swift`
- Test: `macos/Tests/Restart/RestartHandoffTests.swift`

**Interfaces:**
- Consumes: `ClaudeCarry` (Task 1).
- Produces: `struct RestartHandoff: Codable, Equatable` with `pid: Int32`, `at: Date`, `claude: [String: ClaudeCarry]`, `stayAwakeOn: Bool`, `stayAwakeUntil: Date?`, `hooksInstalled: Bool`, `keepWindows: Bool?`; `static let maxAge: TimeInterval = 120`; `static func url(bundleID: String, in folder: URL) -> URL`; `static var standardURL: URL`; `func isFresh(now: Date, isAlive: (Int32) -> Bool) -> Bool`; `func save(to: URL) throws`; `static func take(from: URL) -> RestartHandoff?`.

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/Restart/RestartHandoffTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct RestartHandoffTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func handoff(pid: Int32 = 4242, ago: TimeInterval = 5) -> RestartHandoff {
        RestartHandoff(
            pid: pid, at: now.addingTimeInterval(-ago),
            claude: ["ABCDEF01-0000-4000-8000-000000000001": ClaudeCarry(activity: .waiting, action: "Run the tests")],
            stayAwakeOn: true, stayAwakeUntil: nil, hooksInstalled: true, keepWindows: nil)
    }

    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aRecentHandoffFromAnExitedLosttyIsFresh() {
        #expect(handoff().isFresh(now: now, isAlive: { _ in false }))
    }

    @Test func aStaleOrLiveHandoffIsNotFresh() {
        #expect(!handoff(ago: RestartHandoff.maxAge + 1).isFresh(now: now, isAlive: { _ in false }))
        #expect(!handoff().isFresh(now: now, isAlive: { _ in true }))
        #expect(!handoff(ago: -30).isFresh(now: now, isAlive: { _ in false }))
    }

    @Test func takeReadsItOnceAndDeletesIt() throws {
        let url = RestartHandoff.url(bundleID: "com.lawliang.lostty", in: try folder())
        try handoff().save(to: url)
        #expect(RestartHandoff.take(from: url) == handoff())
        #expect(RestartHandoff.take(from: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func anUnreadableHandoffIsDeletedAndIgnored() throws {
        let url = RestartHandoff.url(bundleID: "com.lawliang.lostty", in: try folder())
        try Data("{not json".utf8).write(to: url)
        #expect(RestartHandoff.take(from: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func eachBuildHasItsOwnHandoff() throws {
        let dir = try folder()
        #expect(RestartHandoff.url(bundleID: "com.lawliang.lostty", in: dir)
            != RestartHandoff.url(bundleID: "com.lawliang.lostty.debug", in: dir))
    }
}
#endif
```

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh RestartHandoffTests`
Expected: build FAILS: "cannot find 'RestartHandoff' in scope".

- [ ] **Step 3: Implement**

Create `macos/Sources/Features/Restart/RestartHandoff.swift`:

```swift
#if os(macOS)
import Foundation

/// What a restarting Lostty leaves for the one it starts (`LosttyRestart`):
/// written just before it exits, read and deleted at the next launch. One
/// file per build (bundle id), so a Debug build and the installed app never
/// take each other's.
struct RestartHandoff: Codable, Equatable {
    /// The Lostty that wrote it; it must have exited for this to count.
    var pid: Int32
    var at: Date
    /// Each pane's Claude, by pane UUID (restored panes keep their UUIDs).
    var claude: [String: ClaudeCarry]
    var stayAwakeOn: Bool
    /// When Stay Awake was due to end; nil for "until I turn it off".
    var stayAwakeUntil: Date?
    /// The Claude hooks were installed: out of date after the restart means
    /// update them, not that you chose not to have them.
    var hooksInstalled: Bool
    /// `NSQuitAlwaysKeepsWindows` before the restart forced it on; nil when unset.
    var keepWindows: Bool?

    /// Older than this, it's not a restart's: a crash's prompt applies.
    static let maxAge: TimeInterval = 120

    static func url(bundleID: String, in folder: URL) -> URL {
        folder.appendingPathComponent("restart-\(bundleID).json")
    }

    static var standardURL: URL {
        url(
            bundleID: Bundle.main.bundleIdentifier ?? "com.lawliang.lostty",
            in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lostty", isDirectory: true))
    }

    /// From a Lostty that has exited, in the last `maxAge` seconds.
    func isFresh(now: Date, isAlive: (Int32) -> Bool) -> Bool {
        let age = now.timeIntervalSince(at)
        return !isAlive(pid) && age >= 0 && age <= Self.maxAge
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// The handoff at `url`, deleted whether or not it reads.
    static func take(from url: URL) -> RestartHandoff? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(RestartHandoff.self, from: data)
    }
}
#endif
```

- [ ] **Step 4: Run them to verify they pass**

Run: `macos/skins-test.sh RestartHandoffTests`
Expected: `** TEST SUCCEEDED **`.

---

### Task 3: Restart and resume

**Files:**
- Create: `macos/Sources/Features/Restart/LosttyRestart.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (`applicationShouldTerminate`, `applicationWillTerminate`, the launch block after `StayAwakeStore.shared.start()`)
- Test: `macos/Tests/Restart/LosttyRestartTests.swift`

**Interfaces:**
- Consumes: `RestartHandoff` (Task 2); `ClaudeRuntime.carry()/restore(_:)` (Task 1); `StayAwakeStore.shared.isOn/until/lastDuration/turnOn(_:)`; `ClaudeHooksCLI().status()/run("install")`; `TmuxRemote.shellQuote`; `ProcessLiveness.isAlive`; `UserDefaults.ghostty`.
- Produces: `enum LosttyRestart` with `enum Reason { case menu, script, sparkle }`, `static var isRestarting: Bool`, `static func begin() -> Bool`, `static func restart(reason:)`, `static func resumeIfRestarted()`, `nonisolated static func reopenScript(pid:bundle:) -> String`, `nonisolated static func spawnDetached(_ script: String) -> Bool`, `static let keepWindowsKey = "NSQuitAlwaysKeepsWindows"`, `static var bundlePath: String` (the bundle path at launch).

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/Restart/LosttyRestartTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct LosttyRestartTests {
    @Test func theReopenScriptWaitsThenOpensThisBundle() {
        let script = LosttyRestart.reopenScript(pid: 4242, bundle: "/Applications/Lostty (previous).app")
        #expect(script == "while kill -0 4242 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open -n '/Applications/Lostty (previous).app'")
    }

    @Test func theHelperRunsDetached() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("helper-\(UUID().uuidString)")
        #expect(LosttyRestart.spawnDetached("echo ok > '\(marker.path)'"))
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline { usleep(50_000) }
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    /// The helper outlives Lostty: it must not hold Lostty's files (a lock,
    /// say) after Lostty exits.
    @Test func theHelperDoesNotInheritDescriptors() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lock-\(UUID().uuidString)")
        // Inheritable on purpose: the helper must close it anyway.
        let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        #expect(LosttyRestart.spawnDetached("sleep 3"))
        close(fd)
        let again = open(url.path, O_RDWR | O_CLOEXEC)
        defer { close(again) }
        #expect(flock(again, LOCK_EX | LOCK_NB) == 0)
    }

    @Test func restartingTwiceIsOnce() {
        LosttyRestart.isRestarting = false
        #expect(LosttyRestart.begin())
        #expect(!LosttyRestart.begin())
        LosttyRestart.isRestarting = false
    }
}
#endif
```

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh LosttyRestartTests`
Expected: build FAILS: "cannot find 'LosttyRestart' in scope".

- [ ] **Step 3: Implement `LosttyRestart`**

Create `macos/Sources/Features/Restart/LosttyRestart.swift`:

```swift
#if os(macOS)
import AppKit
import Foundation
import LosttyRemote

/// Restart to Update: quit into the Lostty installed now without ending a
/// single session. This Lostty leaves a `RestartHandoff`, forces window
/// restoration on, starts a helper that reopens the app once it has exited,
/// and terminates keeping its sessions (`isRestarting`). The new Lostty
/// restores every window, tab and split; each pane's launcher reattaches
/// to its session (`claimOrphan`), and `resumeIfRestarted` puts back the
/// rest.
@MainActor
enum LosttyRestart {
    enum Reason {
        case menu, script
        /// Sparkle relaunches the app itself once it has installed.
        case sparkle
    }

    /// While restarting, termination keeps the sessions and asks nothing.
    static var isRestarting = false

    static let keepWindowsKey = "NSQuitAlwaysKeepsWindows"

    /// The bundle this Lostty launched from: where the new build is
    /// installed, even after the old one was moved aside.
    static let bundlePath = Bundle.main.bundlePath

    /// Claims the restart; false when one is already underway.
    static func begin() -> Bool {
        guard !isRestarting else { return false }
        isRestarting = true
        return true
    }

    static func restart(reason: Reason) {
        guard begin() else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let stayAwake = StayAwakeStore.shared
        let handoff = RestartHandoff(
            pid: pid, at: Date(),
            claude: Dictionary(uniqueKeysWithValues: ClaudeRuntime.shared.carry().map { ($0.key.uuidString, $0.value) }),
            stayAwakeOn: stayAwake.isOn, stayAwakeUntil: stayAwake.until,
            hooksInstalled: ClaudeHooksCLI().status() == .installed,
            keepWindows: UserDefaults.ghostty.object(forKey: keepWindowsKey) as? Bool)
        do {
            try handoff.save(to: RestartHandoff.standardURL)
        } catch {
            fail("Lostty couldn't save what to restore (\(error.localizedDescription)).")
            return
        }
        if reason != .sparkle, !spawnDetached(reopenScript(pid: pid, bundle: bundlePath)) {
            try? FileManager.default.removeItem(at: RestartHandoff.standardURL)
            fail("Lostty couldn't start its relauncher.")
            return
        }
        // Every window comes back, whatever "Close windows when quitting" says.
        UserDefaults.ghostty.set(true, forKey: keepWindowsKey)
        NSApp.invalidateRestorableState()
        for window in NSApp.windows { window.invalidateRestorableState() }
        if reason != .sparkle { NSApp.terminate(nil) }
    }

    /// At launch: if the last Lostty restarted (not crashed), put back what
    /// window restoration doesn't: the window setting, Claude's state, Stay
    /// Awake, and up-to-date hooks.
    static func resumeIfRestarted() {
        guard let handoff = RestartHandoff.take(from: RestartHandoff.standardURL),
              handoff.isFresh(now: Date(), isAlive: ProcessLiveness.isAlive) else { return }
        if let keep = handoff.keepWindows {
            UserDefaults.ghostty.set(keep, forKey: keepWindowsKey)
        } else {
            UserDefaults.ghostty.removeObject(forKey: keepWindowsKey)
        }
        ClaudeRuntime.shared.restore(Dictionary(uniqueKeysWithValues: handoff.claude.compactMap { key, carry in
            UUID(uuidString: key).map { ($0, carry) }
        }))
        if handoff.stayAwakeOn, handoff.stayAwakeUntil.map({ $0 > Date() }) ?? true {
            StayAwakeStore.shared.turnOn(StayAwakeStore.shared.lastDuration)
        }
        if handoff.hooksInstalled, ClaudeHooksCLI().status() == .partial {
            _ = ClaudeHooksCLI().run("install")
        }
    }

    /// Waits for `pid` to exit, then opens `bundle` as a new instance.
    nonisolated static func reopenScript(pid: Int32, bundle: String) -> String {
        "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open -n \(TmuxRemote.shellQuote(bundle))"
    }

    /// Runs `script` with /bin/sh in its own session, outliving Lostty, with
    /// none of Lostty's file descriptors (stdio on /dev/null).
    nonisolated static func spawnDetached(_ script: String) -> Bool {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sh"), strdup("-c"), strdup(script), nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        return posix_spawn(&pid, "/bin/sh", &actions, &attributes, argv, environ) == 0
    }

    private static func fail(_ message: String) {
        isRestarting = false
        let alert = NSAlert()
        alert.messageText = "Couldn't restart Lostty"
        alert.informativeText = message + " Nothing was closed."
        alert.runModal()
    }
}
#endif
```

If `POSIX_SPAWN_SETSID` / `POSIX_SPAWN_CLOEXEC_DEFAULT` import as `Int32`, the `Int16(...)` conversion above is what's needed; if the compiler reports a different type, convert accordingly.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh LosttyRestartTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Keep sessions while restarting (AppDelegate)**

In `macos/Sources/App/macOS/AppDelegate.swift` (re-read it first):

1. At the very top of `func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {`, before the Stay Awake alert, insert:

```swift
        // Restart to Update (and Sparkle's install-and-relaunch): keep every
        // session, ask nothing (LosttyRestart).
        if updateController.isInstalling { LosttyRestart.restart(reason: .sparkle) }
        if LosttyRestart.isRestarting { return .terminateNow }
```

2. In `func applicationWillTerminate(_ notification: Notification)`, replace:

```swift
        // Lostty Mobile: let the Mac sleep again as it did before.
        StayAwakeStore.shared.quit()

        // Lostty Mobile: quitting ends this Lostty's tmux sessions, as
        // quitting a plain terminal ends its shells. Sessions made on the
        // phone, and other Lostty processes' sessions, stay.
        TmuxClient().endSessions(ownedBy: ProcessInfo.processInfo.processIdentifier)
```

with:

```swift
        // Restart to Update: the next Lostty takes over the sessions and
        // Stay Awake (LosttyRestart.resumeIfRestarted).
        guard !LosttyRestart.isRestarting else { return }

        // Lostty Mobile: let the Mac sleep again as it did before.
        StayAwakeStore.shared.quit()

        // Lostty Mobile: quitting ends this Lostty's tmux sessions, as
        // quitting a plain terminal ends its shells. Sessions made on the
        // phone, and other Lostty processes' sessions, stay.
        TmuxClient().endSessions(ownedBy: ProcessInfo.processInfo.processIdentifier)
```

3. After the line `StayAwakeStore.shared.start()` (in the launch block), insert:

```swift
        // Restart to Update: put back what window restoration doesn't
        // (Claude's state, Stay Awake, the window setting, hooks). Before
        // the hooks check and the Claude sync below.
        LosttyRestart.resumeIfRestarted()
```

- [ ] **Step 6: Build the Mac app**

Run: `macos/build.nu`
Expected: build succeeds.

---

### Task 4: Noticing a new build, and going back

**Files:**
- Create: `macos/Sources/Features/Restart/BundleWatch.swift`
- Create: `macos/Sources/Features/Restart/PreviousBuild.swift`
- Create: `macos/Sources/Features/Restart/RestartUI.swift`
- Modify: `macos/Sources/Features/MenuBar/LosttyStatusItem.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (launch block)
- Test: `macos/Tests/Restart/BundleWatchTests.swift`

**Interfaces:**
- Consumes: `LosttyRestart.restart(reason:)`, `LosttyRestart.bundlePath` (Task 3).
- Produces: `final class BundleWatch: ObservableObject` with `static let shared`, `@Published private(set) var updateReady: Bool`, `start()`, `check()`, `struct Stamp: Equatable`, `nonisolated static func stamp(atPath:) -> Stamp?`, `nonisolated static func changed(_ old: Stamp?, _ new: Stamp?) -> Bool`; `enum PreviousBuild` with `static func swap(installed: URL, previous: URL) throws`, `static var available: Bool`, `static let installedURL`, `static let previousURL`; `enum RestartUI` with `static func installMenuItem(after:)`.

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/Restart/BundleWatchTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct BundleWatchTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aReplacedExecutableIsAnUpdate() throws {
        let exe = try folder().appendingPathComponent("lostty")
        try Data("old".utf8).write(to: exe)
        let before = BundleWatch.stamp(atPath: exe.path)
        // As install-skins.sh does: remove, then copy in a new one.
        try FileManager.default.removeItem(at: exe)
        try Data("new".utf8).write(to: exe)
        #expect(BundleWatch.changed(before, BundleWatch.stamp(atPath: exe.path)))
    }

    @Test func theSameExecutableIsNot() throws {
        let exe = try folder().appendingPathComponent("lostty")
        try Data("old".utf8).write(to: exe)
        let stamp = BundleWatch.stamp(atPath: exe.path)
        #expect(!BundleWatch.changed(stamp, BundleWatch.stamp(atPath: exe.path)))
    }

    @Test func aMissingExecutableIsNotAnUpdate() throws {
        let exe = try folder().appendingPathComponent("lostty")
        try Data("old".utf8).write(to: exe)
        let stamp = BundleWatch.stamp(atPath: exe.path)
        try FileManager.default.removeItem(at: exe)
        #expect(!BundleWatch.changed(stamp, BundleWatch.stamp(atPath: exe.path)))
    }

    @Test func goingBackSwapsTheTwoBuilds() throws {
        let dir = try folder()
        let installed = dir.appendingPathComponent("Lostty.app")
        let previous = dir.appendingPathComponent("Lostty (previous).app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: installed.appendingPathComponent("which"))
        try Data("old".utf8).write(to: previous.appendingPathComponent("which"))
        try PreviousBuild.swap(installed: installed, previous: previous)
        #expect(try String(contentsOf: installed.appendingPathComponent("which"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: previous.appendingPathComponent("which"), encoding: .utf8) == "new")
    }
}
#endif
```

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh BundleWatchTests`
Expected: build FAILS: "cannot find 'BundleWatch' in scope".

- [ ] **Step 3: Implement the watch and the swap**

Create `macos/Sources/Features/Restart/BundleWatch.swift`:

```swift
#if os(macOS)
import Foundation

/// Notices this Lostty's app was replaced on disk (install-skins.sh, a new
/// Debug build): its executable is a different file than at launch. Then
/// Restart to Update shows.
@MainActor
final class BundleWatch: ObservableObject {
    static let shared = BundleWatch()

    struct Stamp: Equatable {
        var inode: UInt64
        var modified: Date
    }

    @Published private(set) var updateReady = false

    private let executablePath = Bundle.main.executablePath
    private lazy var atLaunch: Stamp? = executablePath.flatMap(Self.stamp(atPath:))
    private var timer: Timer?

    func start() {
        _ = atLaunch
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { BundleWatch.shared.check() }
        }
    }

    func check() {
        guard !updateReady, let executablePath else { return }
        if Self.changed(atLaunch, Self.stamp(atPath: executablePath)) { updateReady = true }
    }

    nonisolated static func stamp(atPath path: String) -> Stamp? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let modified = Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9)
        return Stamp(inode: UInt64(info.st_ino), modified: modified)
    }

    /// A different file is there now. Missing (mid-install) is not a change.
    nonisolated static func changed(_ old: Stamp?, _ new: Stamp?) -> Bool {
        guard let old, let new else { return false }
        return old != new
    }
}
#endif
```

Create `macos/Sources/Features/Restart/PreviousBuild.swift`:

```swift
#if os(macOS)
import Foundation

/// The build install-skins.sh replaced, kept as "Lostty (previous).app":
/// Go Back to Previous Build swaps the two and restarts.
enum PreviousBuild {
    static let installedURL = URL(fileURLWithPath: "/Applications/Lostty.app")
    static let previousURL = URL(fileURLWithPath: "/Applications/Lostty (previous).app")

    /// This is the installed Lostty, and a previous one is there to go back to.
    static var available: Bool {
        LosttyRestart.bundlePath == installedURL.path && FileManager.default.fileExists(atPath: previousURL.path)
    }

    static func swap(installed: URL = installedURL, previous: URL = previousURL) throws {
        let fm = FileManager.default
        let aside = installed.deletingLastPathComponent().appendingPathComponent("Lostty (swap).app")
        try? fm.removeItem(at: aside)
        try fm.moveItem(at: installed, to: aside)
        try fm.moveItem(at: previous, to: installed)
        try fm.moveItem(at: aside, to: previous)
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh BundleWatchTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: The menus**

Create `macos/Sources/Features/Restart/RestartUI.swift`:

```swift
#if os(macOS)
import AppKit
import Combine

/// Restart to Update in Lostty's app menu, shown once a new build is
/// installed (BundleWatch).
@MainActor
enum RestartUI {
    private static var watcher: AnyCancellable?

    static func installMenuItem(after anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Restart to Update (Keeps Terminals)", action: #selector(Target.restart), keyEquivalent: "")
        item.target = Target.shared
        item.isHidden = true
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
        watcher = BundleWatch.shared.$updateReady.sink { item.isHidden = !$0 }
    }

    final class Target: NSObject {
        static let shared = Target()

        @objc func restart() {
            MainActor.assumeIsolated { LosttyRestart.restart(reason: .menu) }
        }
    }
}
#endif
```

In `macos/Sources/Features/MenuBar/LosttyStatusItem.swift` (re-read it first):

1. In `install()`, after the `ClaudeRuntime.shared.$awaiting.sink { … }.store(in: &watchers)` block, add:

```swift
        BundleWatch.shared.$updateReady.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &watchers)
```

2. Replace `updateIcon()`'s body line with:

```swift
        item?.button?.image = StatusIcon.image(
            on: stayAwake.isOn, dot: !ClaudeRuntime.shared.awaiting.isEmpty, update: BundleWatch.shared.updateReady)
```

3. In `menuNeedsUpdate(_:)`, right after `menu.removeAllItems()`, insert:

```swift
        // A new build is installed: the first thing in the menu.
        BundleWatch.shared.check()
        if BundleWatch.shared.updateReady {
            menu.addItem(action("Restart to Update (Keeps Terminals)", #selector(restartToUpdate)))
            menu.addItem(.separator())
        }
```

4. Right after `menu.addItem(action("Pair a Phone…", #selector(pairPhone)))`, insert:

```swift
        if PreviousBuild.available {
            menu.addItem(action("Go Back to Previous Build", #selector(goBackToPreviousBuild)))
        }
```

5. Next to the other `@objc private func` actions in `LosttyStatusItem`, add:

```swift
    @objc private func restartToUpdate() {
        LosttyRestart.restart(reason: .menu)
    }

    @objc private func goBackToPreviousBuild() {
        do {
            try PreviousBuild.swap()
            LosttyRestart.restart(reason: .menu)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't go back to the previous build"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
```

6. In `enum StatusIcon`, change `static func image(on: Bool, dot: Bool) -> NSImage?` to `static func image(on: Bool, dot: Bool, update: Bool = false) -> NSImage?`, and after the line `if dot { Circle().fill(.black).frame(width: 5, height: 5) }` add (it sits in the same top-trailing `ZStack`; the arrow goes bottom-trailing):

```swift
        }
        .overlay(alignment: .bottomTrailing) {
            if update {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 7, weight: .bold))
            }
```

so the view reads `ZStack(alignment: .topTrailing) { … if dot { … } }.overlay(alignment: .bottomTrailing) { if update { … } }.frame(width: 18, height: 18)`. Keep the existing `.frame(width: 18, height: 18)` after the overlay.

In `macos/Sources/App/macOS/AppDelegate.swift`, after `LosttyStatusItem.shared.installIfEnabled()`, add:

```swift
        // Restart to Update: notice a new build installed over this one.
        BundleWatch.shared.start()
```

and after `SettingsUI.installMenuItem(after: menuOpenConfig)`, add:

```swift
        RestartUI.installMenuItem(after: menuOpenConfig)
```

- [ ] **Step 6: Build**

Run: `macos/build.nu`
Expected: build succeeds.

---

### Task 5: AppleScript `restart to update`

**Files:**
- Create: `macos/Sources/Features/Restart/ScriptRestartCommand.swift`
- Modify: `macos/Ghostty.sdef` (Lostty Suite)

**Interfaces:**
- Consumes: `LosttyRestart.restart(reason: .script)`.
- Produces: the AppleScript command `restart to update` (`code="GhstRsUp"`).

- [ ] **Step 1: Add the command**

In `macos/Ghostty.sdef`, inside `<suite name="Lostty Suite" …>`, right after the `input text` command's closing `</command>`, add:

```xml

    <command name="restart to update" code="GhstRsUp" description="Restart Lostty into the build installed now, keeping every terminal session and window.">
      <cocoa class="LosttyScriptRestartCommand"/>
    </command>
```

Create `macos/Sources/Features/Restart/ScriptRestartCommand.swift`:

```swift
#if os(macOS)
import AppKit

/// Handler for the `restart to update` AppleScript command (`Ghostty.sdef`):
/// for `install-skins.sh --previous` and agents.
@MainActor
@objc(LosttyScriptRestartCommand)
final class ScriptRestartCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard NSApp.validateScript(command: self) else { return nil }
        // After this event's reply: quitting inside it leaves the script waiting.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { LosttyRestart.restart(reason: .script) }
        }
        return nil
    }
}
#endif
```

- [ ] **Step 2: Build and check the dictionary**

Run: `macos/build.nu`
Expected: build succeeds. Then `sdef macos/build/Debug/Lostty.app | grep -c 'restart to update'` → `1`.

---

### Task 6: Install script and agent instructions

**Files:**
- Modify: `macos/install-skins.sh`
- Modify: `macos/AGENTS.md`

- [ ] **Step 1: `--previous`, and keep the replaced build**

In `macos/install-skins.sh` (re-read it first), right after `cd "$(dirname "$0")/.."`, insert:

```sh

# --previous: back to the build this one replaced, then restart into it
# (or open it, when the current one isn't running).
if [ "${1:-}" = "--previous" ]; then
  PREV="/Applications/Lostty (previous).app"
  [ -d "$PREV" ] || { echo "No previous build to go back to." >&2; exit 1; }
  rm -rf "/Applications/Lostty (swap).app"
  mv /Applications/Lostty.app "/Applications/Lostty (swap).app"
  mv "$PREV" /Applications/Lostty.app
  mv "/Applications/Lostty (swap).app" "$PREV"
  if pgrep -xf /Applications/Lostty.app/Contents/MacOS/lostty >/dev/null; then
    osascript -e 'tell application id "com.lawliang.lostty" to restart to update'
  else
    open /Applications/Lostty.app
  fi
  echo "Back on the previous build."
  exit 0
fi
```

Replace:

```sh
rm -rf "/Applications/Lostty.app" "/Applications/Ghostty Skins.app"
cp -R "$APP" "/Applications/Lostty.app"
```

with:

```sh
# Keep the build being replaced: the menu bar's Go Back to Previous Build,
# or `install-skins.sh --previous` when the new one won't start.
rm -rf "/Applications/Lostty (previous).app" "/Applications/Ghostty Skins.app"
if [ -d /Applications/Lostty.app ]; then
  mv /Applications/Lostty.app "/Applications/Lostty (previous).app"
fi
cp -R "$APP" "/Applications/Lostty.app"
```

Replace the last line `echo "Installed /Applications/Lostty.app"` with:

```sh
echo "Installed /Applications/Lostty.app"
echo "Switch with Lostty's menu bar → Restart to Update (keeps your terminals)."
echo "Don't Quit Lostty to update: Quit ends every terminal session."
```

- [ ] **Step 2: Agent instructions**

In `macos/AGENTS.md`, after the line `  - Output: \`macos/build/<configuration>/Lostty.app\` (e.g. \`macos/build/Debug/Lostty.app\`)`, add:

```markdown
- Install a new build for the user with `macos/install-skins.sh`, then
  switch to it with Lostty's menu bar → **Restart to Update** (or
  `osascript -e 'tell application id "com.lawliang.lostty" to «event GhstRsUp»'`
  once the running Lostty has the command). Never Quit Lostty to update:
  Quit ends every terminal session it owns. Back out with
  `macos/install-skins.sh --previous`.
```

- [ ] **Step 3: Check the script parses**

Run: `sh -n macos/install-skins.sh && echo ok`
Expected: `ok`.

---

### Task 7: The real thing, on this Mac (with the user)

The running Lostty predates this feature, so the first switch still needs the manual path; every later one uses Restart to Update. Ask the user before each step that touches their Lostty.

- [ ] **Step 1: Install**

Run: `macos/install-skins.sh` → "Installed /Applications/Lostty.app".

- [ ] **Step 2: First switch, manually (ask first)**

Tell the user, then: `kill -9 <pid of /Applications/Lostty.app/Contents/MacOS/lostty whose parent is 1>`; they reopen Lostty and click **Reopen** on "Reopen N terminal sessions?".

- [ ] **Step 3: Second install and a real Restart to Update (ask first)**

Have a split and two tabs open, one Claude working and one waiting. Run `macos/install-skins.sh` again. Within 30 s the menu bar icon shows the arrow; menu → **Restart to Update (Keeps Terminals)**.
Expected: Lostty is back in a few seconds with the same windows, tabs and split, each pane in the same tmux session (`tmux -L lostty list-sessions -F '#{session_name} #{@lostty_owner}'` shows the new pid), the working row still "Working", the waiting one still "Waiting", Stay Awake still on (`pmset -g | grep SleepDisabled` → 1), no prompt.

- [ ] **Step 4: Go back**

Menu bar → **Go Back to Previous Build**. Expected: restarts into the previous build, same terminals. Then `macos/install-skins.sh --previous` to return.

- [ ] **Step 5: A real crash still prompts**

`kill -9` the app; reopen: "Reopen N terminal sessions?" as before.
