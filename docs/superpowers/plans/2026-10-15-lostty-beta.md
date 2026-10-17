# Lostty Beta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `main`, two Mac builds. Stable leaves out the mascot and
Branches. Lostty Beta has them, with its own name, icon, download and update
feed. The "+" sidebar button goes from both.

**Architecture:** A `LosttyChannel` value is read once from the signed
Info.plist; a build setting `LOSTTY_CHANNEL` writes it there. Beta-only
features ask the channel through named checks (`showsMascot`, `hasBranches`).
`install.sh` and `release.sh` pass the beta build settings on the
`xcodebuild` command line. `release_helper.py` gains beta version numbers and
a beta appcast. `release.sh` builds both, then publishes stable and then the
beta.

**Tech Stack:** Swift/SwiftUI (Mac app, Swift Testing), POSIX sh,
Python 3 standard library (`unittest`), Sparkle feeds, `gh`.

**Spec:** `docs/superpowers/specs/2026-10-15-lostty-beta-design.md`

## Global Constraints

- Work in the worktree `.claude/worktrees/lostty-beta` (branch `lostty-beta`). Never `cd` to the main checkout.
- Bundle ID stays `com.lawliang.lostty`. The app is always `/Applications/Lostty.app`.
- Info.plist keys: `LosttyChannel` = `$(LOSTTY_CHANNEL)`, `LosttyBetaNumber` = `$(LOSTTY_BETA_NUMBER)`.
- Only the exact value `beta` means beta. Anything else (empty, unknown, unexpanded) means stable.
- Beta build settings, all three together: `LOSTTY_CHANNEL=beta`, `INFOPLIST_KEY_CFBundleDisplayName=Lostty Beta`, `ASSETCATALOG_COMPILER_APPICON_NAME=LosttyMacBetaIcon` (plus `LOSTTY_BETA_NUMBER=N` in releases only).
- Beta feed: `https://github.com/Lawliang/lostty/releases/download/beta/appcast-beta.xml`. Stable feed unchanged: `https://github.com/Lawliang/lostty/releases/latest/download/appcast.xml`.
- Beta tags `vX.Y-beta.N`; beta DMG `Lostty-Beta.dmg`; fixed feed release tag `beta`.
- Version text "X.Y beta N" (lowercase "beta", spaces); `MARKETING_VERSION` stays `X.Y`.
- Mac source files are wrapped in `#if os(macOS)` … `#endif` like their neighbors. Tests use Swift Testing (`import Testing`, `@testable import Lostty`).
- New files under `macos/Sources` and `macos/Tests` join their targets by themselves (synchronized folders): no `project.pbxproj` edit for them.
- Mac test command (run from `macos/`), `<Suite>` being the test struct's name:
  `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project Lostty.xcodeproj -scheme Lostty -configuration Debug SYMROOT="$PWD/build" -skip-testing LosttyUITests -only-testing:LosttyTests/<Suite> test 2>&1 | tail -30`
  If it reports "test runner timed out", a tmux session with a dead `@lostty_owner` is blocking it. Detach that session and rerun.
- Python tests: `python3 -I macos/release_helper_test.py` (from the worktree root).
- Commit messages: `lostty: <area>: <what>`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Don't install Lostty or run `install.sh` except in the steps that say to. The owner switches builds with the menu bar's Restart to Update, never Quit.

## Review Focus

1. **The usage breakdown in stable.** `ClaudeRuntime.turnEnded` also feeds `UsageLedger`. Gating the observer must not stop the ledger hearing turns. Test: Task 3 `TurnEndTests`.
2. **New users building from source get stable.** `setup.sh` runs `install.sh`, which now defaults to beta, so it must pass `--stable`. Test: Task 5, step 4.
3. **Switching between versions across a restart.** A beta's restart handoff carries transcripts that a stable build reads, and the reverse. Stable must ignore them and carry none. Test: Task 3 `LosttyRestartTests`.
4. **A beta with no number** (Debug or `install.sh`, where `LOSTTY_BETA_NUMBER` is empty or unexpanded) shows plain "0.4", never "0.4 beta " or "0.4 beta $(…)". Test: Task 1.
5. **Tags that aren't versions.** The fixed `beta` release's tag, and betas of an older stable, must not break or skew the next version and beta number. Test: Task 6 `Betas`.

---

### Task 1: The channel

**Files:**
- Create: `macos/Sources/Features/Channel/LosttyChannel.swift`
- Create: `macos/Tests/Channel/LosttyChannelTests.swift`
- Modify: `macos/Lostty-Info.plist` (beside `LosttyUpdateFeed`, ~line 113)
- Modify: `macos/Lostty.xcodeproj/project.pbxproj` (the Mac target's Debug configuration, the block holding `INFOPLIST_KEY_CFBundleDisplayName = "Lostty[DEBUG]";`, ~line 1165)
- Modify: `macos/Sources/Features/About/AboutView.swift:13`

**Interfaces:**
- Produces: `enum LosttyChannel: String { case stable, beta }`, with:
  - `init(info: [String: Any]?)`
  - `static let current: LosttyChannel`
  - `var isBeta: Bool`, `var showsMascot: Bool`, `var hasBranches: Bool`
  - `static let infoKey = "LosttyChannel"`, `static let betaNumberKey = "LosttyBetaNumber"`
  - `static func displayVersion(info: [String: Any]?) -> String?`

- [ ] **Step 0: Build the engine in the worktree** (GhosttyKit isn't checked in, so a new worktree has none)

Run from the worktree root: `export PATH="$(brew --prefix zig@0.15)/bin:$PATH"; zig build -Demit-macos-app=false`
Expected: exits 0, and `macos/GhosttyKit.xcframework` exists.

- [ ] **Step 1: Write the failing test** at `macos/Tests/Channel/LosttyChannelTests.swift`

```swift
#if os(macOS)
import Testing
@testable import Lostty

struct LosttyChannelTests {
    @Test func onlyBetaIsTheBeta() {
        #expect(LosttyChannel(info: [LosttyChannel.infoKey: "beta"]) == .beta)
        let others: [Any] = ["stable", "", "$(LOSTTY_CHANNEL)", "Beta", 1]
        for other in others {
            #expect(LosttyChannel(info: [LosttyChannel.infoKey: other]) == .stable)
        }
        #expect(LosttyChannel(info: nil) == .stable)
        #expect(LosttyChannel(info: [:]) == .stable)
    }

    @Test func theUnfinishedFeaturesAreOnlyInTheBeta() {
        #expect(LosttyChannel.beta.isBeta && LosttyChannel.beta.showsMascot && LosttyChannel.beta.hasBranches)
        #expect(!LosttyChannel.stable.isBeta && !LosttyChannel.stable.showsMascot && !LosttyChannel.stable.hasBranches)
    }

    @Test func aBetaShowsItsNumberBesideTheVersion() {
        let info: [String: Any] = [
            "CFBundleShortVersionString": "0.4",
            LosttyChannel.infoKey: "beta",
            LosttyChannel.betaNumberKey: "2",
        ]
        #expect(LosttyChannel.displayVersion(info: info) == "0.4 beta 2")
    }

    @Test func withoutANumberOnlyTheVersion() {
        // A Debug or install.sh beta has no number; stable never shows one.
        let numbers: [Any?] = [nil, "", "$(LOSTTY_BETA_NUMBER)", "x"]
        for number in numbers {
            var info: [String: Any] = ["CFBundleShortVersionString": "0.4", LosttyChannel.infoKey: "beta"]
            info[LosttyChannel.betaNumberKey] = number
            #expect(LosttyChannel.displayVersion(info: info) == "0.4")
        }
        let stable: [String: Any] = ["CFBundleShortVersionString": "0.4", LosttyChannel.betaNumberKey: "2"]
        #expect(LosttyChannel.displayVersion(info: stable) == "0.4")
        #expect(LosttyChannel.displayVersion(info: [:]) == nil)
    }
}
#endif
```

- [ ] **Step 2: Run it to see it fail**

Run the Mac test command with `<Suite>` = `LosttyChannelTests`.
Expected: build fails with "cannot find 'LosttyChannel' in scope".

- [ ] **Step 3: Write `macos/Sources/Features/Channel/LosttyChannel.swift`**

```swift
#if os(macOS)
import Foundation

/// Which Lostty this is: stable, the finished build people download, or
/// the beta, the same main with unfinished features on (CONTRIBUTING.md →
/// Stable and beta). Read from the signed Info.plist, so a stable copy
/// can't be switched to the beta.
enum LosttyChannel: String, Equatable {
    case stable
    case beta

    static let infoKey = "LosttyChannel"
    static let betaNumberKey = "LosttyBetaNumber"

    /// Only "beta" is the beta: an empty, unknown or unexpanded value is
    /// stable, so a build that forgets the setting ships the finished one.
    init(info: [String: Any]?) {
        self = (info?[Self.infoKey] as? String) == Self.beta.rawValue ? .beta : .stable
    }

    static let current = LosttyChannel(info: Bundle.main.infoDictionary)

    var isBeta: Bool { self == .beta }
    /// The axolotl in each terminal's corner and the turn observer behind
    /// its bubble.
    var showsMascot: Bool { isBeta }
    /// Branches in the sidebar.
    var hasBranches: Bool { isBeta }

    /// The version as the About window shows it: "0.4", or "0.4 beta 2"
    /// for a released beta (`LOSTTY_BETA_NUMBER`).
    static func displayVersion(info: [String: Any]?) -> String? {
        guard let version = info?["CFBundleShortVersionString"] as? String else { return nil }
        guard LosttyChannel(info: info).isBeta,
              let number = info?[betaNumberKey] as? String, Int(number) != nil else { return version }
        return "\(version) beta \(number)"
    }
}
#endif
```

- [ ] **Step 4: Run the test to see it pass**

Run the Mac test command with `<Suite>` = `LosttyChannelTests`.
Expected: 4 tests pass.

- [ ] **Step 5: Add the Info.plist keys**

In `macos/Lostty-Info.plist`, right after the two `LosttyUpdateFeed` lines:

```xml
	<key>LosttyChannel</key>
	<string>$(LOSTTY_CHANNEL)</string>
	<key>LosttyBetaNumber</key>
	<string>$(LOSTTY_BETA_NUMBER)</string>
```

- [ ] **Step 6: Make Debug builds the beta**

In `macos/Lostty.xcodeproj/project.pbxproj`, find the build settings block that has `INFOPLIST_KEY_CFBundleDisplayName = "Lostty[DEBUG]";` (the Mac target's Debug). Its keys are in alphabetical order. Add this line just before the block's first key that sorts after `LOSTTY_CHANNEL` (such as `MACOSX_DEPLOYMENT_TARGET`):

```
				LOSTTY_CHANNEL = beta;
```

Don't add it to ReleaseLocal or Release.

- [ ] **Step 7: The About window shows the beta number**

In `macos/Sources/Features/About/AboutView.swift:13`, replace:

```swift
    private var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
```

with:

```swift
    private var version: String? { LosttyChannel.displayVersion(info: Bundle.main.infoDictionary) }
```

- [ ] **Step 8: Check that the Debug build is the beta**

Run (from `macos/`): `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project Lostty.xcodeproj -scheme Lostty -configuration Debug SYMROOT="$PWD/build" build 2>&1 | tail -3 && /usr/libexec/PlistBuddy -c 'Print :LosttyChannel' build/Debug/Lostty.app/Contents/Info.plist`
Expected: `** BUILD SUCCEEDED **`, then `beta`.

- [ ] **Step 9: Commit**

```bash
git add macos/Sources/Features/Channel macos/Tests/Channel macos/Lostty-Info.plist macos/Lostty.xcodeproj/project.pbxproj macos/Sources/Features/About/AboutView.swift
git commit -m "lostty: beta: the channel a build belongs to

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The sidebar: Branches in the beta only, no "+" button

**Files:**
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarModel.swift` (`LosttyExtension`, `init`, `select`)
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarView.swift:11,15,43-52,169-182`
- Test: `macos/Tests/Extensions/ExtensionSidebarModelTests.swift`

**Interfaces:**
- Consumes: `LosttyChannel` (Task 1)
- Produces:
  - `static func LosttyExtension.available(in channel: LosttyChannel) -> [LosttyExtension]`
  - `ExtensionSidebarModel.init(branches: BranchesModel? = nil, channel: LosttyChannel = .current)`
  - `let ExtensionSidebarModel.available: [LosttyExtension]`
  - `let ExtensionSidebarModel.showsMascot: Bool` (used by Task 3)

- [ ] **Step 1: Write the failing tests**

In `macos/Tests/Extensions/ExtensionSidebarModelTests.swift`, change `makeModel` so the existing tests (which open Branches) keep running against the beta, and add the new tests to the struct:

```swift
    /// A sidebar whose Branches model reads a scripted world.
    private func makeModel(channel: LosttyChannel = .beta) throws -> (ExtensionSidebarModel, BranchesModel) {
        let branches = BranchesModel(env: try FakeBranchesWorld().environment())
        return (ExtensionSidebarModel(branches: branches, channel: channel), branches)
    }
```

```swift
    @Test func branchesIsInTheBetaOnly() {
        #expect(LosttyExtension.available(in: .beta) == [.branches, .skins])
        #expect(LosttyExtension.available(in: .stable) == [.skins])
    }

    @Test func stableNeverOpensBranches() throws {
        let (model, branches) = try makeModel(channel: .stable)
        #expect(model.available == [.skins])
        model.select(.branches)
        #expect(model.active == nil)
        #expect(branches.isOpen == false)
        model.select(.skins)
        #expect(model.active == .skins)
    }

    @Test func theMascotIsInTheBetaOnly() throws {
        #expect(try makeModel(channel: .beta).0.showsMascot)
        #expect(try makeModel(channel: .stable).0.showsMascot == false)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run the Mac test command with `<Suite>` = `ExtensionSidebarModelTests`.
Expected: build fails with "extra argument 'channel' in call" / "type 'LosttyExtension' has no member 'available'".

- [ ] **Step 3: Implement in `ExtensionSidebarModel.swift`**

Inside `enum LosttyExtension`, after `var id: String { rawValue }`:

```swift
    /// The extensions `channel` offers, in sidebar order: Branches is beta
    /// only.
    static func available(in channel: LosttyChannel) -> [LosttyExtension] {
        allCases.filter { $0 != .branches || channel.hasBranches }
    }
```

In `ExtensionSidebarModel`, replace the `init` and `select` with:

```swift
    /// The extensions this build offers, in sidebar order.
    let available: [LosttyExtension]
    /// The axolotl in the terminal's corner (beta only).
    let showsMascot: Bool

    init(branches: BranchesModel? = nil, channel: LosttyChannel = .current) {
        self.branches = branches ?? BranchesModel()
        available = LosttyExtension.available(in: channel)
        showsMascot = channel.showsMascot
    }

    /// Clicking an icon opens its extension; clicking the open one closes it.
    /// One this build doesn't offer stays shut.
    func select(_ ext: LosttyExtension) {
        guard available.contains(ext) else { return }
        active = active == ext ? nil : ext
    }
```

(`BranchesModel` is idle until `open`, which only `active = .branches` calls, so stable never watches git.)

- [ ] **Step 4: Implement in `ExtensionSidebarView.swift`**

- Line 15: `ForEach(LosttyExtension.allCases) { ext in` becomes `ForEach(model.available) { ext in`.
- Delete `@State private var showingAddNote = false` (line 11).
- Delete the whole "+" button: from `Button { showingAddNote.toggle() } label: {` through the closing `}` of its `.popover { … }` (lines 43-52), keeping the `Spacer(minLength: 0)` that follows.
- Delete `private struct AddExtensionIcon: View { … }` (lines 169-182).

- [ ] **Step 5: Run the tests to see them pass**

Run the Mac test command with `<Suite>` = `ExtensionSidebarModelTests`.
Expected: every test passes, the 3 new ones included.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Extensions macos/Tests/Extensions/ExtensionSidebarModelTests.swift
git commit -m "lostty: sidebar: Branches in the beta only, and no + button

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The mascot in the beta only

**Files:**
- Create: `macos/Sources/Features/Observer/TurnEnd.swift`
- Create: `macos/Tests/Observer/TurnEndTests.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift:355-365`
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift:45-49`
- Modify: `macos/Sources/Features/Settings/SettingsView.swift:7-27`
- Modify: `macos/Sources/Features/Restart/LosttyRestart.swift:56,98-100`
- Test: `macos/Tests/Restart/LosttyRestartTests.swift`

**Interfaces:**
- Consumes: `LosttyChannel` (Task 1), `ExtensionSidebarModel.showsMascot` (Task 2)
- Produces:
  - `enum TurnEnd { static func handler(channel:observe:report:) -> @MainActor (UUID, String) -> Void }`
  - `LosttyRestart.transcripts(_ carried: [UUID: String], channel: LosttyChannel) -> [String: String]?`
  - `LosttyRestart.restoredTranscripts(_ saved: [String: String]?, channel: LosttyChannel) -> [UUID: String]`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/Observer/TurnEndTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct TurnEndTests {
    @Test func theBetaTellsTheObserverAndTheUsageBreakdown() {
        var observed: [String] = []
        var reported: [String] = []
        let handler = TurnEnd.handler(channel: .beta, observe: { _, path in observed.append(path) },
                                      report: { reported.append($0) })
        handler(UUID(), "/t.jsonl")
        #expect(observed == ["/t.jsonl"])
        #expect(reported == ["/t.jsonl"])
    }

    @Test func stableStillCountsUsageButNeverSummarizes() {
        var observed: [String] = []
        var reported: [String] = []
        let handler = TurnEnd.handler(channel: .stable, observe: { _, path in observed.append(path) },
                                      report: { reported.append($0) })
        handler(UUID(), "/t.jsonl")
        #expect(observed.isEmpty)
        #expect(reported == ["/t.jsonl"])
    }
}
#endif
```

Add to the struct in `macos/Tests/Restart/LosttyRestartTests.swift`:

```swift
    @Test func onlyABuildWithTheMascotHandsOverItsConversations() {
        let pane = UUID()
        #expect(LosttyRestart.transcripts([pane: "/t.jsonl"], channel: .beta) == [pane.uuidString: "/t.jsonl"])
        #expect(LosttyRestart.transcripts([pane: "/t.jsonl"], channel: .stable) == nil)
    }

    @Test func stableIgnoresConversationsABetaHandedOver() {
        let pane = UUID()
        let saved = [pane.uuidString: "/t.jsonl", "not a uuid": "/x.jsonl"]
        #expect(LosttyRestart.restoredTranscripts(saved, channel: .beta) == [pane: "/t.jsonl"])
        #expect(LosttyRestart.restoredTranscripts(saved, channel: .stable).isEmpty)
        #expect(LosttyRestart.restoredTranscripts(nil, channel: .beta).isEmpty)
    }
```

(If `LosttyRestartTests` isn't marked `@MainActor` and `LosttyRestart` is `@MainActor`, mark the two new tests `@MainActor`.)

- [ ] **Step 2: Run them to see them fail**

Run the Mac test command twice: `<Suite>` = `TurnEndTests`, then `LosttyRestartTests`.
Expected: build fails with "cannot find 'TurnEnd' in scope" / "type 'LosttyRestart' has no member 'transcripts'".

- [ ] **Step 3: Write `macos/Sources/Features/Observer/TurnEnd.swift`**

```swift
#if os(macOS)
import Foundation

/// What hears a finished agent turn: the usage breakdown in every build,
/// the mascot's turn observer only where the mascot is.
enum TurnEnd {
    static func handler(
        channel: LosttyChannel,
        observe: @escaping @MainActor (UUID, String) -> Void,
        report: @escaping @MainActor (String) -> Void
    ) -> @MainActor (UUID, String) -> Void {
        let observes = channel.showsMascot
        return { pane, path in
            if observes { observe(pane, path) }
            // The usage breakdown counts this conversation as Claude Code in Lostty.
            report(path)
        }
    }
}
#endif
```

- [ ] **Step 4: Add the restart helpers to `LosttyRestart`**

In `macos/Sources/Features/Restart/LosttyRestart.swift`, add inside the `LosttyRestart` type:

```swift
    /// The mascot's conversations to hand over, by pane: none from a build
    /// without the mascot.
    static func transcripts(_ carried: [UUID: String], channel: LosttyChannel) -> [String: String]? {
        guard channel.showsMascot else { return nil }
        return Dictionary(uniqueKeysWithValues: carried.map { ($0.key.uuidString, $0.value) })
    }

    /// The conversations to give back to the observer: none in a build
    /// without the mascot, whatever the build before handed over.
    static func restoredTranscripts(_ saved: [String: String]?, channel: LosttyChannel) -> [UUID: String] {
        guard channel.showsMascot else { return [:] }
        return Dictionary(uniqueKeysWithValues: (saved ?? [:]).compactMap { key, path in
            UUID(uuidString: key).map { ($0, path) }
        })
    }
```

Then line 56:

```swift
            transcripts: Dictionary(uniqueKeysWithValues: TurnObserver.shared.carry().map { ($0.key.uuidString, $0.value) }))
```

becomes:

```swift
            transcripts: LosttyRestart.transcripts(TurnObserver.shared.carry(), channel: .current))
```

and lines 98-100:

```swift
        TurnObserver.shared.restore(Dictionary(uniqueKeysWithValues: (handoff.transcripts ?? [:]).compactMap { key, path in
            UUID(uuidString: key).map { ($0, path) }
        }))
```

become:

```swift
        TurnObserver.shared.restore(LosttyRestart.restoredTranscripts(handoff.transcripts, channel: .current))
```

- [ ] **Step 5: Wire it in `AppDelegate.swift:355-365`**

Replace:

```swift
        // The mascot's turn observer: hears each turn's end from the agent
        // hooks, and finds out which summarizer it can use. Before the
        // restart resume, which hands it each pane's conversation.
        ClaudeRuntime.shared.turnEnded = { pane, path in
            TurnObserver.shared.turnEnded(pane: pane, path: path)
            // The usage breakdown counts this conversation as Claude Code in Lostty.
            UsageLedger.shared.reported(path)
        }
        TurnObserver.shared.start()
```

with:

```swift
        // Each turn's end, from the agent hooks: the usage breakdown, and in
        // the beta the mascot's turn observer, which also finds out which
        // summarizer it can use. Before the restart resume, which hands it
        // each pane's conversation.
        ClaudeRuntime.shared.turnEnded = TurnEnd.handler(
            channel: .current,
            observe: { pane, path in TurnObserver.shared.turnEnded(pane: pane, path: path) },
            report: { UsageLedger.shared.reported($0) })
        if LosttyChannel.current.showsMascot { TurnObserver.shared.start() }
```

- [ ] **Step 6: Hide the axolotl in `ExtensionSidebarLayout.swift:45-49`**

Replace:

```swift
                    .overlay(alignment: .bottomTrailing) {
                        SidebarMascot(surfaceID: model.focusedSurfaceID, bubbleMaxHeight: max(160, terminalHeight / 2))
                            .padding(.trailing, 14)
                            .padding(.bottom, 10)
                    }
```

with:

```swift
                    .overlay(alignment: .bottomTrailing) {
                        if model.showsMascot {
                            SidebarMascot(surfaceID: model.focusedSurfaceID, bubbleMaxHeight: max(160, terminalHeight / 2))
                                .padding(.trailing, 14)
                                .padding(.bottom, 10)
                        }
                    }
```

- [ ] **Step 7: Hide Settings → Mascot in `SettingsView.swift`**

After `@ObservedObject var observer: ObserverPreferences` add:

```swift
    /// The Mascot section is for the beta, the only build with the mascot.
    var showsMascot = LosttyChannel.current.showsMascot
```

and wrap the section: `Section("Mascot") { … }` becomes `if showsMascot { Section("Mascot") { … } }` (the section's contents unchanged).

- [ ] **Step 8: Run the tests to see them pass**

Run the Mac test command for `TurnEndTests`, `LosttyRestartTests`, `TurnObserverTests` and `SidebarMascotTests`.
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add macos/Sources/Features/Observer/TurnEnd.swift macos/Tests/Observer/TurnEndTests.swift macos/Sources/App/macOS/AppDelegate.swift macos/Sources/Features/Extensions/ExtensionSidebarLayout.swift macos/Sources/Features/Settings/SettingsView.swift macos/Sources/Features/Restart/LosttyRestart.swift macos/Tests/Restart/LosttyRestartTests.swift
git commit -m "lostty: mascot: in the beta only, with its turn observer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The beta icon

**Files:**
- Create: `macos/make-beta-icon.swift`
- Create: `macos/Assets.xcassets/LosttyMacBetaIcon.appiconset/` (10 PNGs + `Contents.json`, generated)

**Interfaces:**
- Produces: the asset catalog icon set `LosttyMacBetaIcon`, the value of `ASSETCATALOG_COMPILER_APPICON_NAME` for beta builds (Tasks 5 and 7).

- [ ] **Step 1: Write `macos/make-beta-icon.swift`**

```swift
// Makes LosttyMacBetaIcon.appiconset from LosttyMacIcon.appiconset: each
// image with a band reading "BETA" across the bottom, in Lostty's accent,
// clipped to the icon's own shape. Run again whenever the icon changes:
//   cd macos && swift make-beta-icon.swift
import AppKit

let assets = URL(fileURLWithPath: "Assets.xcassets")
let source = assets.appendingPathComponent("LosttyMacIcon.appiconset")
let target = assets.appendingPathComponent("LosttyMacBetaIcon.appiconset")
let accent = NSColor(srgbRed: 0xE5 / 255.0, green: 0x19 / 255.0, blue: 0x9C / 255.0, alpha: 1)
let files = FileManager.default

try? files.removeItem(at: target)
try files.createDirectory(at: target, withIntermediateDirectories: true)

for name in try files.contentsOfDirectory(atPath: source.path) where name.hasSuffix(".png") {
    guard let image = NSImage(contentsOf: source.appendingPathComponent(name)),
          let pixels = image.representations.first else { fatalError("can't read \(name)") }
    let width = pixels.pixelsWide, height = pixels.pixelsHigh
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("can't draw \(name)") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let size = CGSize(width: width, height: height)
    image.draw(in: CGRect(origin: .zero, size: size))
    // Only where the icon already is: the band follows its rounded corners.
    context.compositingOperation = .sourceAtop
    let band = CGRect(x: 0, y: size.height * 0.14, width: size.width, height: size.height * 0.17)
    accent.setFill()
    band.fill()
    let font = NSFont.systemFont(ofSize: band.height * 0.62, weight: .heavy)
    let text = NSAttributedString(string: "BETA", attributes: [
        .font: font, .foregroundColor: NSColor.white, .kern: band.height * 0.08,
    ])
    let textSize = text.size()
    text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: band.midY - textSize.height / 2))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("can't encode \(name)") }
    try png.write(to: target.appendingPathComponent(name.replacingOccurrences(of: "LosttyMacIcon", with: "LosttyMacBetaIcon")))
}

let contents = try String(contentsOf: source.appendingPathComponent("Contents.json"), encoding: .utf8)
try contents.replacingOccurrences(of: "LosttyMacIcon", with: "LosttyMacBetaIcon")
    .write(to: target.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(target.path)")
```

- [ ] **Step 2: Generate it**

Run: `cd macos && swift make-beta-icon.swift && ls Assets.xcassets/LosttyMacBetaIcon.appiconset | wc -l`
Expected: `Wrote …/LosttyMacBetaIcon.appiconset`, then `11`.

- [ ] **Step 3: Show the owner, and stop until they approve**

Open `macos/Assets.xcassets/LosttyMacBetaIcon.appiconset/LosttyMacBetaIcon-512x512@2x.png` and `LosttyMacBetaIcon-32x32@2x.png` (Read tool), and show the owner both next to the stable icon. Adjust the band's height or position, or the text size, in the script, regenerate, and show again until the owner says it's right.

- [ ] **Step 4: Commit**

```bash
git add macos/make-beta-icon.swift macos/Assets.xcassets/LosttyMacBetaIcon.appiconset
git commit -m "lostty: beta: its icon, with a BETA band

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `install.sh` builds the beta; `setup.sh` builds stable

**Files:**
- Modify: `macos/install.sh` (after the `--previous` block; the `xcodebuild` call; the final `echo`s)
- Modify: `macos/setup.sh:47`

**Interfaces:**
- Consumes: the beta build settings (Global Constraints), `LosttyMacBetaIcon` (Task 4).

- [ ] **Step 1: Choose the channel in `install.sh`**

Right after the `--previous` block's closing `fi`, add:

```sh
# The beta by default: this Mac runs the beta features (CONTRIBUTING.md →
# Stable and beta). --stable builds what people download.
CHANNEL=beta
if [ "${1:-}" = "--stable" ]; then CHANNEL=stable; shift; fi
if [ "$CHANNEL" = beta ]; then
  set -- LOSTTY_CHANNEL=beta "INFOPLIST_KEY_CFBundleDisplayName=Lostty Beta" \
    ASSETCATALOG_COMPILER_APPICON_NAME=LosttyMacBetaIcon
else
  set --
fi
```

Update the header comment's usage lines to mention `--stable` next to `--previous`.

- [ ] **Step 2: Pass it to `xcodebuild`**

In the `env -i … xcodebuild` call, add `"$@"` right before the final `build` argument:

```sh
  SYMROOT="$PWD/macos/build" ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO \
  "$@" build > macos/build/last-install.log 2>&1 || true
```

After the existing `BUILD SUCCEEDED` check, add:

```sh
WANT=""; [ "$CHANNEL" = beta ] && WANT=beta
[ "$(/usr/libexec/PlistBuddy -c 'Print :LosttyChannel' "$APP/Contents/Info.plist")" = "$WANT" ] || {
  echo "The build isn't the $CHANNEL channel; see macos/build/last-install.log" >&2
  exit 1
}
```

(Place it after `APP=` is set.) Change the final `echo "Installed /Applications/Lostty.app"` to:

```sh
if [ "$CHANNEL" = beta ]; then echo "Installed /Applications/Lostty.app (Lostty Beta)"
else echo "Installed /Applications/Lostty.app (stable)"; fi
```

- [ ] **Step 3: Syntax check**

Run: `sh -n macos/install.sh && echo ok`
Expected: `ok`

- [ ] **Step 4: New users get stable**

In `macos/setup.sh:47`, `macos/install.sh` becomes `macos/install.sh --stable`, and the header comment (line 4) says "runs install.sh --stable (the finished build)".
Run: `grep -n 'install.sh' macos/setup.sh`
Expected: line 47 reads `macos/install.sh --stable`.

- [ ] **Step 5: Build both without installing**

`install.sh` installs, which the owner's Mac must not get unasked. Check the build half instead, with the same settings, into a scratch folder (from the worktree root):

```sh
S="$PWD/macos/build/channel-check"
for CH in stable beta; do
  if [ "$CH" = beta ]; then set -- LOSTTY_CHANNEL=beta "INFOPLIST_KEY_CFBundleDisplayName=Lostty Beta" ASSETCATALOG_COMPILER_APPICON_NAME=LosttyMacBetaIcon; else set --; fi
  env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project macos/Lostty.xcodeproj -scheme Lostty \
    -configuration ReleaseLocal SYMROOT="$S/$CH" ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO "$@" build 2>&1 | tail -1
  P="$S/$CH/ReleaseLocal/Lostty.app/Contents/Info.plist"
  echo "$CH: channel=$(/usr/libexec/PlistBuddy -c 'Print :LosttyChannel' "$P") name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$P") icon=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$P")"
done
```

Expected:
- `** BUILD SUCCEEDED **` twice
- `stable: channel= name=Lostty icon=LosttyMacIcon`
- `beta: channel=beta name=Lostty Beta icon=LosttyMacBetaIcon`

- [ ] **Step 6: Commit**

```bash
git add macos/install.sh macos/setup.sh
git commit -m "lostty: install: the beta by default, --stable for the finished build

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `release_helper.py`: beta numbers, newest tag, beta appcast

**Files:**
- Modify: `macos/release_helper.py`
- Test: `macos/release_helper_test.py`

**Interfaces:**
- Produces, used by Task 7:
  - `next-beta --stable vX.Y`: reads tags (one per line) on stdin, prints N
  - `newest-tag`: reads tags on stdin, prints the newest `vX.Y` or `vX.Y-beta.N`, or an empty line
  - `appcast … [--beta-number N]`: the beta's item title "Lostty X.Y beta N", `shortVersionString` "X.Y beta N", and channel title "Lostty Beta"

- [ ] **Step 1: Write the failing tests**

Add to `macos/release_helper_test.py`, before `if __name__ == "__main__":`:

```python
class Betas(unittest.TestCase):
    TAGS = ["beta", "v0.4-beta.2", "v0.4-beta.1", "v0.4", "v0.3-beta.7", "v0.3", "nightly"]

    def test_the_first_beta_of_a_stable_is_1(self):
        self.assertEqual(helper.next_beta("v0.5", self.TAGS), 1)
        self.assertEqual(helper.next_beta("v0.4", []), 1)

    def test_each_beta_is_one_more(self):
        self.assertEqual(helper.next_beta("v0.4", self.TAGS), 3)

    def test_an_older_stables_betas_dont_count(self):
        self.assertEqual(helper.next_beta("v0.3", ["v0.4-beta.9", "v0.3"]), 1)

    def test_the_newest_tag_of_either_kind(self):
        self.assertEqual(helper.newest_tag(self.TAGS), "v0.4-beta.2")
        self.assertEqual(helper.newest_tag(["v0.4", "v0.4-beta.1"]), "v0.4-beta.1")
        self.assertEqual(helper.newest_tag(["v0.5", "v0.4-beta.2"]), "v0.5")
        self.assertEqual(helper.newest_tag(["beta", "nightly"]), "")
        self.assertEqual(helper.newest_tag([]), "")

    def test_the_fixed_beta_tag_isnt_a_version(self):
        self.assertIsNone(helper.parse_tag("beta"))
        self.assertEqual(helper.parse_tag("v0.4-beta.2"), (0, 4, 2))
        self.assertEqual(helper.parse_tag("v0.4"), (0, 4, 0))


class BetaAppcast(unittest.TestCase):
    def test_a_beta_item_names_its_number(self):
        xml = helper.appcast(
            "0.4", "202610151200", "14.0", ["- Mascot"],
            "https://github.com/Lawliang/lostty/releases/download/v0.4-beta.2/Lostty-Beta.dmg",
            "sig==", 5678, datetime(2026, 10, 15, 12, 0, tzinfo=timezone.utc), beta=2)
        root = ET.fromstring(xml)
        self.assertEqual(root.find("channel/title").text, "Lostty Beta")
        item = root.find("channel/item")
        self.assertEqual(item.find("title").text, "Lostty 0.4 beta 2")
        self.assertEqual(item.find(SPARKLE + "shortVersionString").text, "0.4 beta 2")
        self.assertEqual(item.find(SPARKLE + "version").text, "202610151200")
        self.assertEqual(item.find("enclosure").get("url"),
                         "https://github.com/Lawliang/lostty/releases/download/v0.4-beta.2/Lostty-Beta.dmg")

    def test_stable_is_unchanged(self):
        root = ET.fromstring(helper.appcast(
            "0.4", "1", "14.0", [], "https://x/Lostty.dmg", "s", 1,
            datetime(2026, 10, 15, tzinfo=timezone.utc)))
        self.assertEqual(root.find("channel/title").text, "Lostty")
        self.assertEqual(root.find("channel/item/" + SPARKLE + "shortVersionString").text, "0.4")
```

- [ ] **Step 2: Run them to see them fail**

Run: `python3 -I macos/release_helper_test.py`
Expected: errors such as `AttributeError: module 'release_helper' has no attribute 'next_beta'` and `TypeError: appcast() got an unexpected keyword argument 'beta'`.

- [ ] **Step 3: Implement in `macos/release_helper.py`**

Update the docstring's command list:

```
  next-version --latest TAG --override X.Y   prints the stable version to release
  next-beta --stable TAG                     tags (stdin) → the next beta's number
  newest-tag                                 tags (stdin) → the newest release's tag
  notes                                      commit subjects (stdin) → "- …" lines
  appcast --version X.Y --build N --min-system V --notes-file F --url U --sign-output S [--beta-number N]
```

After `VERSION = …`, add:

```python
TAG = re.compile(r"^v(\d+)\.(\d+)(?:-beta\.(\d+))?$")
```

After `next_version`, add:

```python
def parse_tag(tag):
    """(major, minor, beta) for vX.Y (beta 0) or vX.Y-beta.N; None for any
    other tag, such as the fixed `beta` release's."""
    match = TAG.match(tag.strip())
    if not match:
        return None
    return int(match.group(1)), int(match.group(2)), int(match.group(3) or 0)


def next_beta(stable, tags):
    """The number of the next beta of `stable` (a tag like v0.4): one more
    than its highest among `tags`, or 1."""
    base = parse_version(stable)
    numbers = [parsed[2] for parsed in map(parse_tag, tags)
               if parsed and parsed[:2] == base and parsed[2] > 0]
    return max(numbers, default=0) + 1


def newest_tag(tags):
    """The newest release among `tags`, stable or beta: v0.4-beta.2 comes
    after v0.4, and v0.5 after both. "" when none is a release tag."""
    releases = [(parsed, tag.strip()) for tag in tags if (parsed := parse_tag(tag))]
    return max(releases)[1] if releases else ""
```

Change `appcast` to take the beta number:

```python
def appcast(version, build, min_system, bullets, url, signature, length, now, beta=None):
    """Sparkle's feed: one item. With `beta`, the beta's ("0.4 beta 2")."""
    short = f"{version} beta {beta}" if beta else version
    channel = "Lostty Beta" if beta else "Lostty"
    # Escaping turns any "]]>" into "]]&gt;", so the CDATA can't end early.
    items = "".join(
        "<li>%s</li>" % html.escape(b[2:] if b.startswith("- ") else b, quote=False)
        for b in bullets)
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>{channel}</title>
    <item>
      <title>Lostty {short}</title>
      <pubDate>{email.utils.format_datetime(now)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{short}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_system}</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>{items}</ul>]]></description>
      <enclosure url="{html.escape(url)}" length="{length}" type="application/octet-stream" sparkle:edSignature="{html.escape(signature)}"/>
    </item>
  </channel>
</rss>
"""
```

In `main`, register the commands and the option:

```python
    beta = commands.add_parser("next-beta")
    beta.add_argument("--stable", required=True)
    commands.add_parser("newest-tag")
```

```python
    feed.add_argument("--beta-number", default="")
```

and handle them in the `try` block (before the final `else`):

```python
        elif args.command == "next-beta":
            print(next_beta(args.stable, sys.stdin.read().splitlines()))
        elif args.command == "newest-tag":
            print(newest_tag(sys.stdin.read().splitlines()))
```

In the `appcast` branch, pass the number:

```python
            beta_number = int(args.beta_number) if args.beta_number else None
            sys.stdout.write(appcast(args.version, args.build, args.min_system, bullets,
                                     args.url, signature, length, datetime.now(timezone.utc),
                                     beta=beta_number))
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `python3 -I macos/release_helper_test.py`
Expected: `OK`, every test included.

- [ ] **Step 5: Check the command line**

Run: `printf 'beta\nv0.4-beta.1\nv0.4\n' | python3 -I macos/release_helper.py next-beta --stable v0.4; printf 'beta\nv0.4-beta.1\nv0.4\n' | python3 -I macos/release_helper.py newest-tag`
Expected: `2`, then `v0.4-beta.1`.

- [ ] **Step 6: Commit**

```bash
git add macos/release_helper.py macos/release_helper_test.py
git commit -m "lostty: release: beta numbers and the beta's feed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `release.sh`: stable plus its beta, and `--beta`

**Files:**
- Modify: `macos/release.sh` (rewritten below; `--make-key` and the checks are unchanged)

**Interfaces:**
- Consumes: `next-beta`, `newest-tag`, `appcast --beta-number` (Task 6); the beta build settings; `LosttyMacBetaIcon` (Task 4); `LosttyChannel`/`LosttyBetaNumber` Info.plist keys (Task 1).

- [ ] **Step 1: Header, feeds and options**

Replace the header comment with:

```sh
# Publishes Lostty for Mac: builds it, signs it as Developer ID, makes the
# DMG, has Apple notarize it, writes Sparkle's feed, then tags it and creates
# the GitHub release. A stable release also publishes its matching Lostty
# Beta (CONTRIBUTING.md → Stable and beta). Run it only when the owner says
# "release". One-time setup: CONTRIBUTING.md → Release.
#   macos/release.sh [--version X.Y] [--dry-run]   stable X.Y, then X.Y beta 1
#   macos/release.sh --beta [--dry-run]             the next beta of the latest stable
#   macos/release.sh --make-key                     the update-signing key, into the app
#   --dry-run: everything but publishing
```

After `FEED=…`, add:

```sh
BETA_FEED="https://github.com/$REPO/releases/download/beta/appcast-beta.xml"
```

Replace the option loop with:

```sh
OVERRIDE=""; DRY_RUN=0; MAKE_KEY=0; BETA_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) OVERRIDE=${2:?"--version needs X.Y"}; shift 2 ;;
    --beta) BETA_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --make-key) MAKE_KEY=1; shift ;;
    *) echo "Usage: macos/release.sh [--version X.Y | --beta] [--dry-run] | --make-key" >&2; exit 2 ;;
  esac
done
```

Replace `fail()` with one that says how to finish a stable release whose beta failed:

```sh
# Set once stable is out, so a failure after it says how to finish the beta.
STABLE_OUT=0
fail() {
  echo "release: $*" >&2
  [ "$STABLE_OUT" = 0 ] || echo "release: Lostty $VERSION is out; publish its beta with: macos/release.sh --beta" >&2
  exit 1
}
```

After the `--make-key` block, add:

```sh
[ "$BETA_ONLY" = 0 ] || [ -z "$OVERRIDE" ] || fail "--version names a stable release; a beta takes the latest stable's."
```

- [ ] **Step 2: Versions and notes**

Replace everything from `LATEST=$(gh release list …` through the `grep -q '[^[:space:]]' "$NOTES" …` line with:

```sh
# Stable's "latest" skips pre-releases, so betas never count toward it.
STABLE_LATEST=$(gh release list --repo "$REPO" --limit 1 --exclude-drafts --exclude-pre-releases \
  --json tagName --jq '.[0].tagName // ""')
TAGS=$(gh release list --repo "$REPO" --limit 1000 --exclude-drafts --json tagName --jq '.[].tagName')
if [ "$BETA_ONLY" = 1 ]; then
  [ -n "$STABLE_LATEST" ] || fail "make a stable release first: betas are numbered after it."
  VERSION=${STABLE_LATEST#v}
  BETA=$(echo "$TAGS" | $HELPER next-beta --stable "$STABLE_LATEST") || exit 1
  # Notes since the last release of either kind.
  SINCE=$(echo "$TAGS" | $HELPER newest-tag)
  NAME="Lostty $VERSION beta $BETA"
else
  VERSION=$($HELPER next-version --latest "$STABLE_LATEST" --override "$OVERRIDE") || exit 1
  BETA=1
  SINCE=$STABLE_LATEST
  NAME="Lostty $VERSION"
fi
TAG="v$VERSION"
BETA_TAG="v$VERSION-beta.$BETA"
BUILD=$(date +%Y%m%d%H%M)
if [ "$BETA_ONLY" = 0 ] && git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
  fail "the tag $TAG already exists on this Mac."
fi
! git rev-parse -q --verify "refs/tags/$BETA_TAG" > /dev/null || fail "the tag $BETA_TAG already exists on this Mac."

# The matching beta reuses stable's notes; a beta by itself gets its own.
step "Notes for $NAME"
NOTES="$OUT/notes.md"
RANGE="-30 HEAD"
if [ -n "$SINCE" ]; then
  git fetch -q origin "refs/tags/$SINCE:refs/tags/$SINCE" 2> /dev/null || true
  git rev-parse -q --verify "refs/tags/$SINCE" > /dev/null && RANGE="$SINCE..HEAD"
fi
# shellcheck disable=SC2086 # RANGE is one or two words on purpose
git log --no-merges --format=%s $RANGE | $HELPER notes > "$NOTES"
${EDITOR:-nano} "$NOTES"
grep -q '[^[:space:]]' "$NOTES" || fail "the notes are empty; nothing was released."
```

- [ ] **Step 3: One build function for both**

Replace everything from `step "Building Lostty $VERSION ($BUILD)"` through the `$HELPER appcast … > "$OUT/appcast.xml" || exit 1` line with:

```sh
step "Building the engine"
zig build -Demit-macos-app=false -Doptimize=ReleaseFast > "$OUT/zig.log" 2>&1 \
  || failed "$OUT/zig.log" "the engine build failed"
cat > "$OUT/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF

# build_dmg stable|beta: archives, signs, notarizes and staples one build in
# $OUT/<channel>, then writes its feed there. Stable: Lostty.dmg and
# appcast.xml. Beta: Lostty-Beta.dmg and appcast-beta.xml, its enclosure on
# the versioned pre-release so an offered update outlives the next beta.
build_dmg() {
  CH=$1
  DIR="$OUT/$CH"
  if [ "$CH" = beta ]; then
    DMG=Lostty-Beta.dmg; FEED_FILE=appcast-beta.xml; VOLUME="Lostty Beta"
    CH_FEED=$BETA_FEED; CH_TAG=$BETA_TAG; CH_NAME="Lostty $VERSION beta $BETA"; WANT=beta
    set -- LOSTTY_CHANNEL=beta LOSTTY_BETA_NUMBER="$BETA" "INFOPLIST_KEY_CFBundleDisplayName=Lostty Beta" \
      ASSETCATALOG_COMPILER_APPICON_NAME=LosttyMacBetaIcon
  else
    DMG=Lostty.dmg; FEED_FILE=appcast.xml; VOLUME=Lostty
    CH_FEED=$FEED; CH_TAG=$TAG; CH_NAME="Lostty $VERSION"; WANT=""
    set --
  fi
  step "Building $CH_NAME ($BUILD)"
  rm -rf "$DIR"
  mkdir -p "$DIR"
  xcodebuild archive -project macos/Lostty.xcodeproj -scheme Lostty -configuration Release \
    -destination generic/platform=macOS -archivePath "$DIR/Lostty.xcarchive" -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM=$TEAM CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" LOSTTY_UPDATE_FEED="$CH_FEED" \
    ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO "$@" \
    > "$DIR/archive.log" 2>&1 || failed "$DIR/archive.log" "the $CH archive failed"
  xcodebuild -exportArchive -archivePath "$DIR/Lostty.xcarchive" -exportPath "$DIR/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates \
    > "$DIR/export.log" 2>&1 || failed "$DIR/export.log" "signing the $CH build as Developer ID failed"
  APP="$DIR/export/Lostty.app"
  codesign --verify --deep --strict "$APP" 2> "$DIR/codesign.log" || failed "$DIR/codesign.log" "the signature doesn't verify"
  # Notarization needs every helper (Sparkle's Autoupdate, Updater.app, its
  # XPC services) signed as Developer ID with a timestamp, not just the app.
  # (Not the symlinks inside Sparkle.framework, nor resource bundles with no code.)
  { echo "$APP"; find "$APP/Contents" ! -type l \( -name "*.app" -o -name "*.xpc" -o -name "*.framework" \
    -o -name "*.plugin" -o -name "*.bundle" -o -name Autoupdate \) -print; } > "$DIR/signed-parts.txt"
  while read -r part; do
    case "$part" in *.bundle | *.plugin) [ -d "$part/Contents/MacOS" ] || continue ;; esac
    codesign -dvv "$part" > "$DIR/part.log" 2>&1
    grep -q "^Authority=Developer ID Application" "$DIR/part.log" && grep -q "^Timestamp=" "$DIR/part.log" \
      || failed "$DIR/part.log" "${part#"$DIR/export/"} isn't signed as Developer ID with a timestamp"
  done < "$DIR/signed-parts.txt"
  INFO="$APP/Contents/Info.plist"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :LosttyUpdateFeed' "$INFO")" = "$CH_FEED" ] \
    || fail "the $CH app doesn't carry the update feed $CH_FEED"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")" = "$VERSION" ] \
    || fail "the $CH app's version isn't $VERSION"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :LosttyChannel' "$INFO")" = "$WANT" ] \
    || fail "the $CH app isn't the $CH channel"

  step "Making $DMG"
  rm -rf "$DIR/dmg"
  mkdir -p "$DIR/dmg"
  cp -R "$APP" "$DIR/dmg/"
  ln -s /Applications "$DIR/dmg/Applications"
  hdiutil create -volname "$VOLUME" -srcfolder "$DIR/dmg" -fs HFS+ -format UDZO "$DIR/$DMG" \
    > "$DIR/dmg.log" 2>&1 || failed "$DIR/dmg.log" "hdiutil failed"
  codesign --sign "$IDENTITY" --timestamp "$DIR/$DMG" 2> "$DIR/dmg-sign.log" \
    || failed "$DIR/dmg-sign.log" "signing the DMG failed"

  step "Notarizing $DMG (a few minutes)"
  xcrun notarytool submit "$DIR/$DMG" --keychain-profile "$PROFILE" --wait --output-format json \
    > "$DIR/notary.json" 2> "$DIR/notary.log" || true
  if [ "$(field status)" != Accepted ]; then
    ID=$(field id)
    [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "$DIR/notary-log.json" > /dev/null 2>&1 \
      && head -40 "$DIR/notary-log.json" >&2
    fail "Apple didn't notarize $DMG (status: $(field status)); see $DIR/notary.log and $DIR/notary-log.json"
  fi
  xcrun stapler staple "$DIR/$DMG" > "$DIR/staple.log" 2>&1 || failed "$DIR/staple.log" "stapling failed"
  spctl -a -t open --context context:primary-signature -v "$DIR/$DMG" > "$DIR/spctl.log" 2>&1 \
    || failed "$DIR/spctl.log" "Gatekeeper rejects the DMG"
  MOUNT=$(mktemp -d)
  hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DIR/$DMG" > /dev/null
  if spctl -a -vv "$MOUNT/Lostty.app" > "$DIR/spctl-app.log" 2>&1 \
      && grep -q "Notarized Developer ID" "$DIR/spctl-app.log"; then OK=1; else OK=0; fi
  hdiutil detach "$MOUNT" -quiet || true
  [ "$OK" = 1 ] || failed "$DIR/spctl-app.log" "Gatekeeper rejects the app in $DMG"

  step "Writing $FEED_FILE"
  SIGNED=$("$SPARKLE_BIN/sign_update" "$DIR/$DMG") || fail "sign_update failed"
  MIN=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")
  if [ "$CH" = beta ]; then set -- --beta-number "$BETA"; else set --; fi
  $HELPER appcast --version "$VERSION" --build "$BUILD" --min-system "$MIN" --notes-file "$NOTES" \
    --url "https://github.com/$REPO/releases/download/$CH_TAG/$DMG" --sign-output "$SIGNED" "$@" \
    > "$DIR/$FEED_FILE" || exit 1
}
# A field of the last notarization's answer ($DIR/notary.json).
field() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$DIR/notary.json" "$1" 2> /dev/null || true; }

[ "$BETA_ONLY" = 1 ] || build_dmg stable
build_dmg beta
```

- [ ] **Step 4: Dry run, then publish both**

Replace the dry-run block and everything after it with:

```sh
if [ "$DRY_RUN" = 1 ]; then
  [ "$BETA_ONLY" = 1 ] || echo "Dry run: $OUT/stable/Lostty.dmg and $OUT/stable/appcast.xml ($TAG)."
  echo "Dry run: $OUT/beta/Lostty-Beta.dmg and $OUT/beta/appcast-beta.xml ($BETA_TAG, then the beta release)."
  echo "Nothing was published."
  exit 0
fi

# push_tag TAG MESSAGE: tags this commit and pushes it; a tag that never
# reached GitHub goes, so the next run can make it again.
push_tag() {
  git tag -a "$1" -m "$2" "$COMMIT"
  if ! GIT_NO_REPLACE_OBJECTS=1 git push origin "refs/tags/$1" > "$OUT/push.log" 2>&1; then
    git tag -d "$1" > /dev/null
    failed "$OUT/push.log" "couldn't push the tag $1; it wasn't published"
  fi
}

if [ "$BETA_ONLY" = 0 ]; then
  step "Publishing Lostty $VERSION"
  push_tag "$TAG" "Lostty $VERSION"
  gh release create "$TAG" "$OUT/stable/Lostty.dmg" "$OUT/stable/appcast.xml" --repo "$REPO" --verify-tag \
    --title "Lostty $VERSION" --notes-file "$NOTES" > "$OUT/gh.log" 2>&1 || {
    cat "$OUT/gh.log" >&2
    fail "the tag $TAG is on GitHub, but the release wasn't created. Retry with: gh release create $TAG '$OUT/stable/Lostty.dmg' '$OUT/stable/appcast.xml' --repo $REPO --verify-tag --title 'Lostty $VERSION' --notes-file '$NOTES'"
  }
  curl -fsSL "$FEED" | grep -q "<sparkle:shortVersionString>$VERSION<" \
    || fail "released, but $FEED doesn't show $VERSION yet; check https://github.com/$REPO/releases"
  echo "Released Lostty $VERSION: https://github.com/$REPO/releases/tag/$TAG"
  STABLE_OUT=1
fi

BETA_NAME="Lostty $VERSION beta $BETA"
step "Publishing $BETA_NAME"
push_tag "$BETA_TAG" "$BETA_NAME"
gh release create "$BETA_TAG" "$OUT/beta/Lostty-Beta.dmg" "$OUT/beta/appcast-beta.xml" --repo "$REPO" \
  --verify-tag --prerelease --title "$BETA_NAME" --notes-file "$NOTES" > "$OUT/gh-beta.log" 2>&1 || {
  cat "$OUT/gh-beta.log" >&2
  fail "the tag $BETA_TAG is on GitHub, but its release wasn't created. Retry with: gh release create $BETA_TAG '$OUT/beta/Lostty-Beta.dmg' '$OUT/beta/appcast-beta.xml' --repo $REPO --verify-tag --prerelease --title '$BETA_NAME' --notes-file '$NOTES', then run this script's beta release step by hand: gh release upload beta … --clobber"
}
# The beta feed's fixed home: the newest beta's DMG and feed, replaced each time.
if gh release view beta --repo "$REPO" > /dev/null 2>&1; then
  { gh release upload beta "$OUT/beta/Lostty-Beta.dmg" "$OUT/beta/appcast-beta.xml" --repo "$REPO" --clobber \
    && gh release edit beta --repo "$REPO" --title "Lostty Beta ($VERSION beta $BETA)" --notes-file "$NOTES"; } \
    > "$OUT/gh-beta-feed.log" 2>&1 || failed "$OUT/gh-beta-feed.log" "$BETA_NAME is out, but the beta release wasn't refreshed"
else
  gh release create beta "$OUT/beta/Lostty-Beta.dmg" "$OUT/beta/appcast-beta.xml" --repo "$REPO" \
    --prerelease --latest=false --target "$COMMIT" --title "Lostty Beta ($VERSION beta $BETA)" \
    --notes-file "$NOTES" > "$OUT/gh-beta-feed.log" 2>&1 \
    || failed "$OUT/gh-beta-feed.log" "$BETA_NAME is out, but the beta release wasn't created"
fi
curl -fsSL "$BETA_FEED" | grep -q "<sparkle:shortVersionString>$VERSION beta $BETA<" \
  || fail "released, but $BETA_FEED doesn't show $VERSION beta $BETA yet; check https://github.com/$REPO/releases/tag/beta"
echo "Released $BETA_NAME: https://github.com/$REPO/releases/tag/beta"
```

- [ ] **Step 5: Check it**

Run: `sh -n macos/release.sh && echo ok`
Expected: `ok`
Run: `grep -n '"\$OUT/Lostty.dmg"\|"\$OUT/appcast.xml"\|"\$OUT/export' macos/release.sh`
Expected: no output (every path now goes through `$DIR`, `$OUT/stable` or `$OUT/beta`).
Run: `macos/release.sh --bogus; echo "exit $?"`
Expected: the usage line, then `exit 2`.

A real `--dry-run` needs a clean `main` equal to `origin/main`, so it runs after this branch is merged. It's in Task 8's hand-off, not here.

- [ ] **Step 6: Commit**

```bash
git add macos/release.sh
git commit -m "lostty: release: every stable release publishes its beta, and --beta

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Docs, and the whole branch checked

**Files:**
- Modify: `CONTRIBUTING.md` (a new `### Stable and beta` section before `### Release`, line ~152; a line in `### Release` about `--beta`)

- [ ] **Step 1: Write the section**

Before `### Release` in `CONTRIBUTING.md`:

```markdown
### Stable and beta

Lostty comes in two builds of the same `main`:

- **Lostty**, stable: the finished build people download.
- **Lostty Beta**: the same, plus features that aren't finished yet. Today
  that's the mascot (and its turn summaries) and Branches.

Both are `/Applications/Lostty.app` with the same settings, terminals and
phone pairing, so a Mac has one or the other. The beta says "Lostty Beta" and
has a BETA band on its icon. Each follows its own update feed. To switch, you
download the other one.

- `macos/install.sh` builds the beta; `macos/install.sh --stable` builds
  stable. `macos/setup.sh` installs stable.
- Debug builds from Xcode are the beta.
- To keep a feature in the beta, check `LosttyChannel.current` (add a named
  check like `showsMascot`) and make sure stable does none of its work.
- `macos/make-beta-icon.swift` remakes the beta icon after the icon changes.
```

In `### Release`, add after the paragraph that introduces `macos/release.sh`:

```markdown
Each stable release also publishes its matching beta (`vX.Y-beta.1`). To
publish a beta by itself, run `macos/release.sh --beta`: the next beta of the
latest stable, with notes since the last release of either kind.
```

- [ ] **Step 2: Format**

Run (from the worktree root): `prettier --check CONTRIBUTING.md || prettier -w CONTRIBUTING.md`
Expected: formatted (if prettier isn't installed, skip and say so).

- [ ] **Step 3: The whole test suite**

Run: `cd macos && env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project Lostty.xcodeproj -scheme Lostty -configuration Debug SYMROOT="$PWD/build" -skip-testing LosttyUITests test 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`.
Run: `python3 -I macos/release_helper_test.py`
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: stable and beta

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand back to the owner**

Report:
- what's on `lostty-beta`
- the two builds checked in Task 5 step 5
- that the "+" button is gone from both, the mascot and Branches only in the beta

Ask before installing anything. The next steps are the owner's:
1. Merge.
2. Install the beta with `macos/install.sh`, then use Restart to Update.
3. On `main`, run `macos/release.sh --dry-run` and `macos/release.sh --beta --dry-run` before the first real release.
