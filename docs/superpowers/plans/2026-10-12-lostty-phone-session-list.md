# Lostty Phone Session List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the phone, each session reads as what it is (a typed name, a Claude task, or a project, with Waiting/Working), the list updates live while it's on screen, and a session that ends while you're attached says why in an overlay; the Mac's menu bar lists sessions with the same labels and order, and Rename Tab… and the phone's Rename share one name.

**Architecture:** All new per-session state lives in tmux user options (`@lostty_label`, `@lostty_claude`, global `@lostty_end_<n>`) that the phone reads with its one `list-sessions` command. A single `wait-for` channel (`lostty-changed`), signalled by tmux hooks, the Mac and the phone, drives a streaming SSH exec on the phone (Citadel `executeCommandStream`) and a watcher thread on the Mac. Pure, package-tested logic in `LosttyRemote` (`SessionLabel`, `SessionEnd`, `TerminalOverlay`, the commands) is shared by the iPhone app and the Mac menu bar; thin Mac and iOS adapters run it.

**Tech Stack:** Swift 5 mode, SwiftUI (iOS 17) and AppKit (macOS 14), Combine, Citadel 0.12.1 (SSH, pinned exact in `macos/LosttyRemote/Package.swift`), tmux 3.8 (`wait-for`, `set-hook`, user options), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-12-lostty-phone-session-list-design.md`

## Global Constraints

- New Mac-only files under `macos/Sources` and `macos/Tests` are wrapped in `#if os(macOS)` … `#endif` (the iOS target compiles every file under `macos/Sources`). Existing Mac-only files (`AppDelegate.swift`, `BaseTerminalController.swift`, `TerminalWindow.swift`, the macOS half of `Ghostty.App.swift`, `SurfaceView_AppKit.swift`) are already kept out of iOS; edit them in place. iOS-only code follows the existing iOS files (`#if os(iOS)` … `#endif`, as `MobileStore.swift`). The project uses synchronized folders: new files need no `project.pbxproj` edits.
- Shared label, command and decision logic lives in `macos/LosttyRemote` (public API), so the phone and the Mac use one implementation.
- tmux names, exactly: session option `@lostty_label` (the typed name; unset when cleared), session option `@lostty_claude` (`waiting` or `working`; unset otherwise), global option `@lostty_end_<n>` for session `$n` (`mac-close`, `mac-quit`, `phone:<device name>`), wait-for channel `lostty-changed`. Hooks: `session-created`, `session-closed`, `session-renamed`, `client-attached`, `client-detached`, each `wait-for -S lostty-changed`.
- Copy (exact): `Closed on your Mac`, `Lostty quit on your Mac`, `Closed from <device name>`, `The shell exited`, `This terminal was closed` (reason unreadable), `Connection lost — reconnecting…`, `Back to Sessions`, `Waiting`, `Working`, `Open on Mac`, `Not open on Mac`, `shell`, `claude`.
- Timings: the phone re-lists at most every 300 ms; the Mac's title signal fires at most once per second; "you typed it" means input in the last 3 s; Back to Sessions appears on the connection overlay after 30 s; the terminal dims to 35 % under an overlay.
- `<device name>` is `DeviceModel.current` (the model, e.g. "iPhone 15 Pro"): iOS gives apps the user's own device name only with a special entitlement, and pairing already sends the model.
- Tests never touch the user's live `tmux -L lostty` server, real SSH, or the network: fakes (a stand-in tmux script, as `TmuxClientTests` does), pure functions, string/argv assertions. A test that needs a real tmux uses its own `-L` socket and kills its server. (None in this plan does.)
- Package tests: `swift test --package-path macos/LosttyRemote --filter <Suite>` from the worktree root (the first run fetches Citadel 0.12.1 and its dependencies into `macos/LosttyRemote/.build`; that is a build step, not a test touching the network). Mac app tests: `macos/skins-test.sh <SuiteName>` from the worktree root (log at `macos/build/last-test.log`). Builds: Mac `macos/build.nu --configuration Debug --action build`; iOS `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SYMROOT="$PWD/macos/build" CODE_SIGNING_ALLOWED=NO build`. The prebuilt `macos/GhosttyKit.xcframework` and `zig-out` are in place: no `zig build` (this plan changes no Zig; the `tmux.conf` edit reaches the app bundle on the next `zig build`, and the Mac sets the hooks itself meanwhile).
- If a Mac test run fails with "The test runner timed out while preparing to run tests", don't retry in a loop: stop and report it (an orphaned tmux session blocks the test host).
- Commits: stage files by path (never `default.profraw`, never other people's work in progress); end each message with your own session's `Co-Authored-By:` attribution line (shown below as `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; use yours if it differs). Never push, never create a PR or issue. swiftlint is not installed. Don't wrap commands in `sh -c`/`bash -c`.

## Review Focus

1. **A title or typed name containing a tab, newline or trailing `;`** (a program can set any pane title; a person can paste anything into Rename). Columns must not shift, and a name must never become a tmux command separator. Pinned by `TmuxRemoteTests.aTabInTheTitleStaysInTheTitle` and `SessionLabelTests.typedNamesLoseControlCharactersAndTrailingSemicolons` (Task 1).
2. **The Mac both listens on and signals `lostty-changed`.** A wake that writes state that wakes it again would spin forever; writes must happen only when tmux disagrees. Pinned by `ClaudeTmuxSyncTests.nothingToWriteWhenTmuxAlreadyAgrees` (Task 4).
3. **The Mac closes the tab while the phone user is typing.** The tag must win over the 3-second "you typed exit" rule, or the person is thrown back to the list with no explanation. Pinned by `SessionEndTests.aTagBeatsRecentTyping` (Task 2).
4. **Two phones of the same model.** "This phone closed it" must come from the phone's own state, never from comparing the `phone:<model>` tag, or the other phone silently drops back to the list. Pinned by `SessionEndTests.anotherPhoneOfTheSameModelStillGetsTheOverlay` (Task 2).
5. **No tmux server on the Mac** (nothing open yet, or tmux missing). `wait-for` fails at once; the Mac's watcher must pause instead of spinning a core. Pinned by `SessionWatcherTests.aWaitThatFailsAtOncePauses` (Task 3).

---

## Streaming exec: what the SSH library offers

`macos/LosttyRemote/Package.swift` pins Citadel `exact: "0.12.1"` (resolved revision `ae8562f895de06ccb86fdb1cbb65fd99c8976e12`). Its source (in `~/Library/Developer/Xcode/DerivedData/Ghostty-*/SourcePackages/checkouts/Citadel/Sources/Citadel/TTY/Client/TTY.swift`) has:

```swift
public func executeCommandStream(
    _ command: String,
    environment: [SSHChannelRequestEvent.EnvironmentRequest] = [],
    inShell: Bool = false
) async throws -> AsyncThrowingStream<ExecCommandOutput, Error>
```

It yields `.stdout(ByteBuffer)` / `.stderr(ByteBuffer)` as data arrives and finishes (throwing `SSHClient.CommandFailed(exitCode:)` on a non-zero exit) when the channel ends. The stream has no `onTermination` that closes the channel, so the only way to stop a watch early is to close its connection; the phone's watch owns a dedicated connection for that reason. The spec's 3-second re-list fallback is not needed.

## File Structure

| File | Responsibility |
|---|---|
| `macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift` | Longer list format and parse; option/channel names; rename, tagged kill, end probe and watch commands; `ListPacing`. |
| `macos/LosttyRemote/Sources/LosttyRemote/SessionLabel.swift` (new) | `SessionRow`, `SessionGroups`, `SessionLabel`: main line, project, Claude detection, relative time, order, typed-name cleaning. |
| `macos/LosttyRemote/Sources/LosttyRemote/SessionEnd.swift` (new) | `EndProbe`, `SessionEnd.decide`: what the phone does when its attach ends. |
| `macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift` | `killSession(_:name:device:)`, `setLabel`, `endProbe`, `watchChanges()`. |
| `macos/LosttyRemote/Sources/LosttyRemote/AttachEnd.swift` | + `RemoteLinkStatus`. |
| `macos/LosttyRemote/Sources/LosttyRemote/TerminalOverlay.swift` (new) | The phone terminal's overlay state. |
| `src/shell-integration/lostty-tmux/tmux.conf` | The five change hooks. |
| `macos/Sources/Features/Sessions/TmuxHooks.swift` (new) | The hook lines and the one-call `set-hook` argv. |
| `macos/Sources/Features/Sessions/SessionWatcher.swift` (new) | Mac `wait-for` thread; re-applies hooks; posts `.losttySessionsChanged`. |
| `macos/Sources/Features/Sessions/TmuxClient.swift` | Tagged ends, `remoteSessions()`, `signalChanged()`, `setLabel`. |
| `macos/Sources/Features/Claude/ClaudeTmuxSync.swift` (new) | Writes `@lostty_claude` from `ClaudeRuntime`. |
| `macos/Sources/Features/Sessions/SessionTitleSignal.swift` (new) | `SignalThrottle`; signals when a Claude pane's cleaned title changes. |
| `macos/Sources/Features/Sessions/SessionSync.swift` (new) | Labels → tab titles; a phone attaching marks a waiting pane seen; `SessionTitleOverride`. |
| `macos/Sources/Features/Claude/ClaudeRuntime.swift` | + `seenElsewhere(_:)`. |
| `macos/Sources/Features/StayAwake/AttachedPhones.swift` | + `currentSessionIDs()`. |
| `macos/Sources/Features/Terminal/BaseTerminalController.swift`, `Window Styles/TerminalWindow.swift` | Rename Tab… sets the label; a label shows as the tab title. |
| `macos/Sources/Features/MenuBar/LosttyStatusItem.swift`, `StayAwakeMenuText.swift` | Sessions section replaces the Claude section. |
| `macos/Sources/Features/Remote/RemoteSurfaceIO.swift` (shared Mac/iOS) | Link status to the screen; the phone's overlaid surface calls; recent-input check. |
| `macos/Sources/App/iOS/MobileStore.swift` | Live watch, rename, tagged kill, end probe, terminal link. |
| `macos/Sources/App/iOS/SessionsScreen.swift` | Rows, sections, swipe Rename, rename alert. |
| `macos/Sources/App/iOS/TerminalScreen.swift` | Overlay for closed reasons and connection lost; ⋯ Rename. |
| `macos/Sources/App/iOS/DesignGallery.swift` | Sample sessions with labels. |
| `macos/Sources/App/macOS/AppDelegate.swift`, `macos/Sources/Ghostty/Ghostty.App.swift`, `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | One-line wiring each. |
| `docs/lostty-mobile-phone-access.md` | User docs. |

## Task order and parallelism

1 → 2 → 3, then:
- Task 4 → Task 5 (both edit `AppDelegate.swift`; Task 5 uses Task 4's files).
- Task 6 needs 1 and 3; runs in parallel with 4 and 5 (no shared files).
- Task 7 needs nothing; runs in parallel with 1–6 (no shared files).
- Task 8 needs 2; runs in parallel with 3–7.
- Task 9 needs 7 and 8.
- Task 10 last.

Parallel tasks share no files, but they share build folders (`macos/build`, `macos/LosttyRemote/.build`): run parallel tasks in separate worktrees, never two builds in one.

---

### Task 1: Richer session list and `SessionLabel` (LosttyRemote)

**Files:**
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift` (`RemoteSession`, `listFormat`, `parse`)
- Create: `macos/LosttyRemote/Sources/LosttyRemote/SessionLabel.swift`
- Modify: `macos/LosttyRemote/Tests/LosttyRemoteTests/TmuxRemoteTests.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/SessionLabelTests.swift` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `public enum ClaudeActivity: String, Sendable { case waiting, working }`
  - `RemoteSession` gains `label: String?`, `claude: ClaudeActivity?`, `title: String`, `path: String`, `command: String`, `activity: Date?`; `public init(id:name:surface:owner:label:claude:title:path:command:activity:)` with defaults `nil, nil, "", "", "", nil` for the new ones (existing 4-argument calls still compile).
  - `TmuxRemote.labelOption = "@lostty_label"`, `TmuxRemote.claudeOption = "@lostty_claude"`, `TmuxRemote.listFormat` (10 tab-separated columns, title last), `TmuxRemote.parse(_:) -> [RemoteSession]`.
  - `public struct SessionRow: Equatable, Sendable { id: String; title: String; project: String; kind: Kind (.shell/.claude, rawValue "shell"/"claude"); openOnMac: Bool; status: Status (.waiting/.working/.lastUsed(String)); var detail: String; var statusText: String }`
  - `public struct SessionGroups: Equatable, Sendable { var open: [RemoteSession]; var notOpen: [RemoteSession] }`
  - `public enum SessionLabel { static func row(for: RemoteSession, now: Date) -> SessionRow; static func ordered(_: [RemoteSession]) -> SessionGroups; static func project(path: String, name: String) -> String; static func isClaude(_: RemoteSession) -> Bool; static func hasClaudeGlyph(_: String) -> Bool; static func cleanTitle(_: String) -> String; static func relative(_: Date?, now: Date) -> String; static func cleanLabel(_: String) -> String? }`

Decisions (spec leaves open): Claude glyphs are `◐◑◒◓` (spinner), `✳` (idle, with or without U+FE0F), `✶✻✽✢` (Claude Code's other frames) and the braille block U+2800–28FF (Codex), matching and extending `ClaudeRuntime.isSpinner`. "Looks like a version" means starts with a digit, only digits and dots, at least one dot. A typed name keeps at most 80 characters, control characters become spaces, and trailing `;` is dropped (tmux reads an argument ending in `;` as a command separator). `pane_title` is the last column and parsed with `maxSplits`, so a tab in it stays in it. Ties in the order fall back to the session number.

- [ ] **Step 1: Write the failing tests**

Create `macos/LosttyRemote/Tests/LosttyRemoteTests/SessionLabelTests.swift`:

```swift
import Foundation
import Testing
@testable import LosttyRemote

struct SessionLabelTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func session(
        _ id: String = "$1", name: String = "lostty", owner: Int32? = 4242, label: String? = nil,
        claude: ClaudeActivity? = nil, title: String = "", path: String = "/Users/me/projectrepos/lostty",
        command: String = "zsh", ago: TimeInterval? = 60
    ) -> RemoteSession {
        RemoteSession(
            id: id, name: name, surface: owner == nil ? nil : "PANE", owner: owner, label: label, claude: claude,
            title: title, path: path, command: command, activity: ago.map { now.addingTimeInterval(-$0) })
    }

    func row(_ s: RemoteSession) -> SessionRow { SessionLabel.row(for: s, now: now) }

    @Test func aTypedNameWinsOverEverything() {
        #expect(row(session(label: "Deploy watch", claude: .working, title: "◐ Fix login", command: "2.1.296")).title == "Deploy watch")
    }

    @Test func aClaudeSessionReadsAsItsTask() {
        let titles = [
            "◐ Lostty UI redesign plan", "◑ Lostty UI redesign plan", "◒ Lostty UI redesign plan",
            "◓ Lostty UI redesign plan", "✳ Lostty UI redesign plan", "✳\u{FE0F} Lostty UI redesign plan",
            "✻ Lostty UI redesign plan", "⠋ Lostty UI redesign plan",
        ]
        for title in titles {
            #expect(row(session(title: title, command: "2.1.296")).title == "Lostty UI redesign plan", "\(title)")
        }
    }

    @Test func aClaudeTitleWithoutAGlyphShowsAsIs() {
        #expect(row(session(claude: .waiting, title: "Lostty UI redesign plan", command: "node")).title == "Lostty UI redesign plan")
    }

    @Test func anEmptyClaudeTitleFallsBackToTheProject() {
        #expect(row(session(claude: .working, title: "✳ ", command: "2.1.296")).title == "lostty")
    }

    @Test func aShellReadsAsItsProject() {
        #expect(row(session(name: "lostty-2", title: "~/projectrepos/lostty", command: "zsh")).title == "lostty")
    }

    @Test func claudeIsTheOptionOrAVersionLikeCommand() {
        #expect(SessionLabel.isClaude(session(command: "2.1.296")))
        #expect(SessionLabel.isClaude(session(claude: .waiting, command: "node")))
        #expect(!SessionLabel.isClaude(session(command: "zsh")))
        #expect(!SessionLabel.isClaude(session(command: "2")))
        #expect(!SessionLabel.isClaude(session(command: "")))
        #expect(!SessionLabel.isClaude(session(command: ".1")))
    }

    @Test func worktreesShowAsRepoSlashName() {
        let base = "/Users/me/projectrepos/lostty/.claude/worktrees/stay-awake"
        #expect(SessionLabel.project(path: base, name: "lostty") == "lostty/stay-awake")
        #expect(SessionLabel.project(path: base + "/", name: "lostty") == "lostty/stay-awake")
        #expect(SessionLabel.project(path: base + "/macos/Sources", name: "lostty") == "lostty/stay-awake")
        #expect(SessionLabel.project(path: "/Users/me/projectrepos/lostty/macos", name: "lostty-3") == "lostty")
        #expect(SessionLabel.project(path: "/Users/me/x/.claude/worktrees/", name: "x") == "x")
        #expect(SessionLabel.project(path: "/.claude/worktrees/a", name: "home") == "home")
    }

    @Test func copyNumbersAreStripped() {
        #expect(SessionLabel.project(path: "", name: "lostty-2") == "lostty")
        #expect(SessionLabel.project(path: "", name: "home-12") == "home")
        #expect(SessionLabel.project(path: "", name: "api-server") == "api-server")
        #expect(SessionLabel.project(path: "", name: "-3") == "-3")
        #expect(SessionLabel.project(path: "", name: "v2-") == "v2-")
    }

    @Test func lastUsedReadsShort() {
        #expect(SessionLabel.relative(now.addingTimeInterval(-20), now: now) == "now")
        #expect(SessionLabel.relative(now.addingTimeInterval(-300), now: now) == "5m ago")
        #expect(SessionLabel.relative(now.addingTimeInterval(-7200), now: now) == "2h ago")
        #expect(SessionLabel.relative(now.addingTimeInterval(-3 * 86400), now: now) == "3d ago")
        #expect(SessionLabel.relative(now.addingTimeInterval(30), now: now) == "now")
        #expect(SessionLabel.relative(nil, now: now) == "")
    }

    @Test func detailLineSaysProjectKindAndMac() {
        #expect(row(session(title: "✳ X", command: "2.1.296")).detail == "lostty · claude · Open on Mac")
        #expect(row(session(owner: nil)).detail == "lostty · shell")
    }

    @Test func waitingAndWorkingOnlyForSessionsOpenOnTheMac() {
        #expect(row(session(claude: .waiting)).status == .waiting)
        #expect(row(session(claude: .waiting)).statusText == "Waiting")
        #expect(row(session(claude: .working)).statusText == "Working")
        #expect(row(session(owner: nil, claude: .waiting, ago: 300)).status == .lastUsed("5m ago"))
    }

    @Test func anOlderMacStillGivesARow() {
        // No @lostty_label / @lostty_claude: tmux prints empty columns.
        let r = row(session(name: "api-2", title: "Lawrences-MacBook.local", path: "/Users/me/api", command: "zsh"))
        #expect(r.title == "api")
        #expect(r.kind == .shell)
        #expect(r.status == .lastUsed("1m ago"))
    }

    @Test func waitingFirstThenMostRecentNotOpenLast() {
        let groups = SessionLabel.ordered([
            session("$1", owner: 1, ago: 10),
            session("$2", owner: nil, ago: 5),
            session("$3", owner: 1, claude: .waiting, ago: 900),
            session("$4", owner: 1, ago: 100),
            session("$5", owner: nil, ago: 50),
            // Not open on the Mac: a leftover "waiting" earns no place at the top.
            session("$6", owner: nil, claude: .waiting, ago: 500),
        ])
        #expect(groups.open.map(\.id) == ["$3", "$1", "$4"])
        #expect(groups.notOpen.map(\.id) == ["$2", "$5", "$6"])
    }

    @Test func tiesFallBackToTheSessionNumber() {
        let groups = SessionLabel.ordered([session("$10", ago: nil), session("$9", ago: nil)])
        #expect(groups.open.map(\.id) == ["$9", "$10"])
    }

    @Test func typedNamesLoseControlCharactersAndTrailingSemicolons() {
        #expect(SessionLabel.cleanLabel("  Deploy\twatch\n") == "Deploy watch")
        #expect(SessionLabel.cleanLabel("x;") == "x")
        #expect(SessionLabel.cleanLabel("a ; ;") == "a")
        #expect(SessionLabel.cleanLabel(";") == nil)
        #expect(SessionLabel.cleanLabel("   ") == nil)
        #expect(SessionLabel.cleanLabel("👩‍💻 pair") == "👩‍💻 pair")
        #expect(SessionLabel.cleanLabel(String(repeating: "a", count: 100))?.count == 80)
    }
}
```

In `TmuxRemoteTests.swift`, replace `parsesTheSessionList` with:

```swift
    @Test func parsesTheSessionList() {
        let out = "$1\tlostty\tABCD-1\t4242\tDeploy\twaiting\t1700000000\t2.1.296\t/Users/me/lostty\t✳ Fix login\n"
            + "$2\tnotes\t\t\t\t\t\tzsh\t/Users/me/notes\t~/notes\n"
        #expect(TmuxRemote.parse(out) == [
            RemoteSession(
                id: "$1", name: "lostty", surface: "ABCD-1", owner: 4242, label: "Deploy", claude: .waiting,
                title: "✳ Fix login", path: "/Users/me/lostty", command: "2.1.296",
                activity: Date(timeIntervalSince1970: 1_700_000_000)),
            RemoteSession(
                id: "$2", name: "notes", surface: nil, owner: nil, label: nil, claude: nil,
                title: "~/notes", path: "/Users/me/notes", command: "zsh", activity: nil),
        ])
    }

    @Test func aTabInTheTitleStaysInTheTitle() {
        let out = "$1\tx\t\t\t\t\t1\tzsh\t/x\tleft\tright 🚀\n"
        #expect(TmuxRemote.parse(out).first?.title == "left\tright 🚀")
    }

    @Test func theListAsksForEveryColumnTitleLast() {
        #expect(TmuxRemote.listFormat == "#{session_id}\t#{session_name}\t#{@lostty_surface}\t#{@lostty_owner}\t"
            + "#{@lostty_label}\t#{@lostty_claude}\t#{session_activity}\t#{pane_current_command}\t"
            + "#{pane_current_path}\t#{pane_title}")
    }

    @Test func anUnknownClaudeValueIsNone() {
        #expect(TmuxRemote.parse("$1\tx\t\t\t\tthinking\t1\tzsh\t/x\tt\n").first?.claude == nil)
    }
```

Add `import Foundation` at the top of `TmuxRemoteTests.swift` (above `import Testing`).

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path macos/LosttyRemote --filter SessionLabelTests`
Expected: build FAILS, "cannot find 'SessionLabel' in scope" (and "extra arguments" for the new `RemoteSession` init).

- [ ] **Step 3: Implement the list changes in `TmuxRemote.swift`**

Replace the `RemoteSession` struct (top of the file) with:

```swift
/// What the Mac says a session's Claude is doing (`@lostty_claude`).
public enum ClaudeActivity: String, Sendable {
    case waiting
    case working
}

/// A session on the Mac's Lostty tmux (`tmux -L lostty`).
public struct RemoteSession: Equatable, Sendable {
    public var id: String
    public var name: String
    /// The Mac pane showing it, if any.
    public var surface: String?
    /// The Mac Lostty's pid, if a Mac window shows it.
    public var owner: Int32?
    /// The name typed on the Mac (Rename Tab…) or the phone (Rename).
    public var label: String?
    /// Set by the Mac for sessions it shows; nil otherwise.
    public var claude: ClaudeActivity?
    /// `#{pane_title}`: Claude Code's task, or a shell's folder.
    public var title: String
    /// `#{pane_current_path}`: the running program's folder.
    public var path: String
    /// `#{pane_current_command}`; Claude Code reports its version ("2.1.296").
    public var command: String
    /// `#{session_activity}`: last use.
    public var activity: Date?

    public init(
        id: String, name: String, surface: String?, owner: Int32?, label: String? = nil,
        claude: ClaudeActivity? = nil, title: String = "", path: String = "", command: String = "",
        activity: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.surface = surface
        self.owner = owner
        self.label = label
        self.claude = claude
        self.title = title
        self.path = path
        self.command = command
        self.activity = activity
    }
}
```

Replace the `listFormat` declaration and its comment with:

```swift
    /// The name typed on the Mac or the phone.
    public static let labelOption = "@lostty_label"
    /// "waiting" or "working", written by the Mac.
    public static let claudeOption = "@lostty_claude"

    /// id, name, Mac pane, Mac Lostty pid, label, Claude state, last use,
    /// command, folder, title — tab separated. The title goes last: any
    /// program sets it, so a tab inside it stays inside it.
    public static let listFormat = [
        "#{session_id}", "#{session_name}", "#{@lostty_surface}", "#{@lostty_owner}",
        "#{\(labelOption)}", "#{\(claudeOption)}", "#{session_activity}",
        "#{pane_current_command}", "#{pane_current_path}", "#{pane_title}",
    ].joined(separator: "\t")
```

Replace `parse(_:)` with:

```swift
    public static func parse(_ output: String) -> [RemoteSession] {
        output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", maxSplits: 9, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 10, isSessionID(f[0]) else { return nil }
            return RemoteSession(
                id: f[0],
                name: f[1],
                surface: f[2].isEmpty ? nil : f[2],
                owner: Int32(f[3]),
                label: f[4].isEmpty ? nil : f[4],
                claude: ClaudeActivity(rawValue: f[5]),
                title: f[9],
                path: f[8],
                command: f[7],
                activity: TimeInterval(f[6]).map { Date(timeIntervalSince1970: $0) })
        }
    }
```

- [ ] **Step 4: Implement `SessionLabel.swift`**

```swift
import Foundation

/// What a session's row says, on the phone and in the Mac's menu bar.
public struct SessionRow: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case shell
        case claude
    }

    public enum Status: Equatable, Sendable {
        case waiting
        case working
        /// "now", "5m ago", …; empty when tmux didn't say.
        case lastUsed(String)
    }

    public var id: String
    /// A name you typed, else the Claude task, else the project.
    public var title: String
    public var project: String
    public var kind: Kind
    public var openOnMac: Bool
    public var status: Status

    /// "lostty · claude · Open on Mac"
    public var detail: String {
        ([project, kind.rawValue] + (openOnMac ? ["Open on Mac"] : [])).joined(separator: " · ")
    }

    /// "Waiting", "Working", or when it was last used.
    public var statusText: String {
        switch status {
        case .waiting: "Waiting"
        case .working: "Working"
        case .lastUsed(let text): text
        }
    }
}

/// Sessions in list order: those open on the Mac, then the rest.
public struct SessionGroups: Equatable, Sendable {
    public var open: [RemoteSession]
    public var notOpen: [RemoteSession]
}

/// Turns tmux's view of a session into what a person reads. One
/// implementation for the phone's list and the Mac's menu bar.
public enum SessionLabel {
    public static func row(for session: RemoteSession, now: Date) -> SessionRow {
        let project = Self.project(path: session.path, name: session.name)
        let claude = Self.isClaude(session)
        let openOnMac = session.owner != nil
        let typed = session.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let task = claude ? Self.cleanTitle(session.title) : ""
        let title = !typed.isEmpty ? typed : (!task.isEmpty ? task : project)
        let status: SessionRow.Status
        switch openOnMac ? session.claude : nil {
        case .waiting?: status = .waiting
        case .working?: status = .working
        case nil: status = .lastUsed(Self.relative(session.activity, now: now))
        }
        return SessionRow(
            id: session.id, title: title, project: project, kind: claude ? .claude : .shell,
            openOnMac: openOnMac, status: status)
    }

    /// Waiting first, then most recently used; sessions no Mac window shows
    /// go in their own group after.
    public static func ordered(_ sessions: [RemoteSession]) -> SessionGroups {
        func waiting(_ s: RemoteSession) -> Bool { s.owner != nil && s.claude == .waiting }
        func number(_ s: RemoteSession) -> Int { Int(s.id.dropFirst()) ?? 0 }
        let sorted = sessions.sorted { a, b in
            if waiting(a) != waiting(b) { return waiting(a) }
            let ta = a.activity ?? .distantPast
            let tb = b.activity ?? .distantPast
            if ta != tb { return ta > tb }
            return number(a) < number(b)
        }
        return SessionGroups(open: sorted.filter { $0.owner != nil }, notOpen: sorted.filter { $0.owner == nil })
    }

    /// `.../<repo>/.claude/worktrees/<name>/...` reads `<repo>/<name>`;
    /// anything else is the session name without a trailing `-<digits>`.
    public static func project(path: String, name: String) -> String {
        if let marker = path.range(of: "/.claude/worktrees/") {
            let repo = (String(path[..<marker.lowerBound]) as NSString).lastPathComponent
            let worktree = path[marker.upperBound...].split(separator: "/").first.map(String.init) ?? ""
            if !repo.isEmpty, !worktree.isEmpty { return "\(repo)/\(worktree)" }
        }
        guard let dash = name.lastIndex(of: "-"), dash > name.startIndex else { return name }
        let digits = name[name.index(after: dash)...]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return name }
        return String(name[..<dash])
    }

    /// The Mac says so, or the command is Claude Code's version number.
    public static func isClaude(_ session: RemoteSession) -> Bool {
        session.claude != nil || looksLikeVersion(session.command)
    }

    static func looksLikeVersion(_ command: String) -> Bool {
        guard let first = command.first, first.isASCII, first.isNumber, command.contains(".") else { return false }
        return command.allSatisfy { ($0.isASCII && $0.isNumber) || $0 == "." }
    }

    public static func hasClaudeGlyph(_ title: String) -> Bool {
        title.unicodeScalars.first.map(isGlyph) ?? false
    }

    /// The title without a leading spinner or "✳" (and what follows it up
    /// to the text).
    public static func cleanTitle(_ title: String) -> String {
        var scalars = Substring(title).unicodeScalars
        if let first = scalars.first, isGlyph(first) {
            scalars = scalars.dropFirst()
            while scalars.first == "\u{FE0F}" { scalars = scalars.dropFirst() }
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    /// Claude Code's spinner frames and idle "✳", and Codex's braille dots.
    static func isGlyph(_ scalar: Unicode.Scalar) -> Bool {
        "◐◑◒◓✳✶✻✽✢".unicodeScalars.contains(scalar) || (0x2800...0x28FF).contains(scalar.value)
    }

    /// "now", "5m ago", "2h ago", "3d ago"; empty when unknown.
    public static func relative(_ activity: Date?, now: Date) -> String {
        guard let activity else { return "" }
        let seconds = max(0, now.timeIntervalSince(activity))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86400))d ago"
        }
    }

    /// A typed name as stored: control characters (tabs, newlines) become
    /// spaces, at most 80 characters, no trailing ";" (tmux would read one
    /// as a command separator). nil when nothing is left: that clears it.
    public static func cleanLabel(_ typed: String) -> String? {
        let scalars = typed.unicodeScalars.map { (s: Unicode.Scalar) -> Unicode.Scalar in
            s.properties.generalCategory == .control ? " " : s
        }
        var text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
        if text.count > 80 { text = String(text.prefix(80)) }
        while text.hasSuffix(";") || text.hasSuffix(" ") { text.removeLast() }
        return text.isEmpty ? nil : text
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path macos/LosttyRemote --filter SessionLabelTests` then `swift test --package-path macos/LosttyRemote --filter TmuxRemoteTests`
Expected: `✔ Test run with … tests passed` for both.

- [ ] **Step 6: Run the whole package**

Run: `swift test --package-path macos/LosttyRemote`
Expected: `✔ Test run with … tests passed`.

- [ ] **Step 7: Commit**

```bash
git add macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift macos/LosttyRemote/Sources/LosttyRemote/SessionLabel.swift macos/LosttyRemote/Tests/LosttyRemoteTests/TmuxRemoteTests.swift macos/LosttyRemote/Tests/LosttyRemoteTests/SessionLabelTests.swift
git commit -m "lostty: session labels from tmux (task, project, waiting) shared by phone and Mac

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Commands, end decision and streaming watch (LosttyRemote)

**Files:**
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift`
- Create: `macos/LosttyRemote/Sources/LosttyRemote/SessionEnd.swift`
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift`
- Modify: `macos/Sources/App/iOS/MobileStore.swift:140` (the kill call)
- Modify: `macos/LosttyRemote/Tests/LosttyRemoteTests/TmuxRemoteTests.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/SessionEndTests.swift` (new)

**Interfaces:**
- Consumes: `TmuxRemote.labelOption` (Task 1).
- Produces:
  - `TmuxRemote.changedChannel = "lostty-changed"`
  - `TmuxRemote.EndTag { macClose = "mac-close"; macQuit = "mac-quit"; phonePrefix = "phone:"; static func phone(_ device: String) -> String }`
  - `TmuxRemote.endOption(sessionID:) throws -> String` ("$3" → "@lostty_end_3")
  - `TmuxRemote.watchCommand: String`, `killCommand(sessionID:name:device:) throws -> String` (replaces `killCommand(sessionID:name:)`), `renameCommand(sessionID:name:label:) throws -> String`, `endProbeCommand(sessionID:) throws -> String`, `parseEndProbe(_:) -> EndProbe?`
  - `public enum ListPacing { static let interval: TimeInterval = 0.3; static func delay(sinceLastList: Date, now: Date) -> TimeInterval }`
  - `public struct EndProbe: Equatable, Sendable { var exists: Bool; var tag: String?; init(exists:tag:) }`
  - `public enum SessionEnd: Equatable, Sendable { case backToList, stillRunning, closed(String); static let typedWindow: TimeInterval = 3; static let unreadable: String; static func decide(probe: EndProbe?, endedHere: Bool, typedRecently: Bool) -> SessionEnd }`
  - `RemoteConnection.killSession(_:name:device:) async throws` (replaces `killSession(_:name:)`), `setLabel(_ label: String?, sessionID: String, name: String) async throws -> Bool`, `endProbe(_ sessionID: String) async throws -> EndProbe?`, `watchChanges() async throws -> AsyncStream<Void>`

Decisions: kill and rename run in one `tmux` invocation with an escaped `\;` separator, after the existing name guard. The end probe prints `present`/`gone` on line 1 and the tag on line 2. `watchChanges()` folds changes that arrive while one is unread into one event (`bufferingNewest(1)`) rather than "one event per line": the consumer re-lists anyway and a burst should cost one list, not one per line. An empty device after `phone:`, or an unknown tag, reads as unreadable.

- [ ] **Step 1: Write the failing tests**

Create `macos/LosttyRemote/Tests/LosttyRemoteTests/SessionEndTests.swift`:

```swift
import Testing
@testable import LosttyRemote

struct SessionEndTests {
    func gone(_ tag: String?) -> EndProbe { EndProbe(exists: false, tag: tag) }

    @Test func eachTagSaysWhy() {
        #expect(SessionEnd.decide(probe: gone("mac-close"), endedHere: false, typedRecently: false) == .closed("Closed on your Mac"))
        #expect(SessionEnd.decide(probe: gone("mac-quit"), endedHere: false, typedRecently: false) == .closed("Lostty quit on your Mac"))
        #expect(SessionEnd.decide(probe: gone("phone:iPad Pro"), endedHere: false, typedRecently: false) == .closed("Closed from iPad Pro"))
    }

    @Test func noTagAndRecentTypingIsYouTypingExit() {
        #expect(SessionEnd.decide(probe: gone(nil), endedHere: false, typedRecently: true) == .backToList)
    }

    @Test func noTagAndNoTypingIsTheShellExiting() {
        #expect(SessionEnd.decide(probe: gone(nil), endedHere: false, typedRecently: false) == .closed("The shell exited"))
    }

    @Test func closingFromHereGoesStraightBack() {
        #expect(SessionEnd.decide(probe: gone("phone:iPhone 15 Pro"), endedHere: true, typedRecently: false) == .backToList)
        #expect(SessionEnd.decide(probe: nil, endedHere: true, typedRecently: false) == .backToList)
    }

    @Test func aSessionStillThereWasOnlyDetached() {
        #expect(SessionEnd.decide(probe: EndProbe(exists: true, tag: "mac-close"), endedHere: false, typedRecently: false) == .stillRunning)
    }

    @Test func unreadableSaysTheTerminalWasClosed() {
        #expect(SessionEnd.decide(probe: nil, endedHere: false, typedRecently: true) == .closed("This terminal was closed"))
        #expect(SessionEnd.decide(probe: gone("something-new"), endedHere: false, typedRecently: false) == .closed("This terminal was closed"))
        #expect(SessionEnd.decide(probe: gone("phone:"), endedHere: false, typedRecently: false) == .closed("This terminal was closed"))
    }

    @Test func aTagBeatsRecentTyping() {
        #expect(SessionEnd.decide(probe: gone("mac-close"), endedHere: false, typedRecently: true) == .closed("Closed on your Mac"))
    }

    @Test func anotherPhoneOfTheSameModelStillGetsTheOverlay() {
        // This phone is also an "iPhone 15 Pro", but it didn't close it.
        #expect(SessionEnd.decide(probe: gone("phone:iPhone 15 Pro"), endedHere: false, typedRecently: false)
            == .closed("Closed from iPhone 15 Pro"))
    }
}
```

In `TmuxRemoteTests.swift`, add below `guardPrefix`:

```swift
    private static let tmux = "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -u -L lostty"

    private static func nameGuard(_ id: String, _ name: String) -> String {
        "[ \"$(\(guardPrefix) '\(id)' '#{session_name}' 2>/dev/null)\" = '\(name)' ] || exit 1; "
    }
```

Replace `aNameWithAQuoteIsShellQuotedInTheGuard` and `killChecksTheNameThenQuotesTheSessionID` with:

```swift
    @Test func aNameWithAQuoteIsShellQuotedInTheGuard() throws {
        let cmd = try TmuxRemote.attachCommand(sessionID: "$1", name: "it's; rm -rf ~", terminfoDir: "/t")
        #expect(cmd.contains("= 'it'\\''s; rm -rf ~' ] || exit 1; exec "))
        let kill = try TmuxRemote.killCommand(sessionID: "$1", name: "it's", device: "iPhone")
        #expect(kill.contains("= 'it'\\''s' ] || exit 1; "))
    }

    @Test func killChecksTheNameThenTagsTheEndAndKills() throws {
        #expect(try TmuxRemote.killCommand(sessionID: "$4", name: "proj", device: "iPhone 15 Pro") ==
            Self.nameGuard("$4", "proj")
            + "\(Self.tmux) set-option -g @lostty_end_4 'phone:iPhone 15 Pro' \\; kill-session -t '$4'")
        #expect(throws: TmuxRemoteError.badSessionID("main")) {
            try TmuxRemote.killCommand(sessionID: "main", name: "n", device: "iPhone")
        }
    }

    @Test func aDeviceNameWithAQuoteIsQuoted() throws {
        let kill = try TmuxRemote.killCommand(sessionID: "$4", name: "p", device: "Alex's iPhone")
        #expect(kill.contains("@lostty_end_4 'phone:Alex'\\''s iPhone' \\; "))
    }

    @Test func renameSetsTheLabelThenSignals() throws {
        #expect(try TmuxRemote.renameCommand(sessionID: "$4", name: "proj", label: "Deploy watch") ==
            Self.nameGuard("$4", "proj")
            + "\(Self.tmux) set-option -t '$4' @lostty_label 'Deploy watch' \\; wait-for -S lostty-changed")
    }

    @Test func renameToNothingClearsTheLabel() throws {
        #expect(try TmuxRemote.renameCommand(sessionID: "$4", name: "proj", label: nil) ==
            Self.nameGuard("$4", "proj")
            + "\(Self.tmux) set-option -u -t '$4' @lostty_label \\; wait-for -S lostty-changed")
    }

    @Test func renameQuotesTheLabelAndRefusesBadIDs() throws {
        let cmd = try TmuxRemote.renameCommand(sessionID: "$4", name: "p", label: "x'; rm -rf ~")
        #expect(cmd.contains("@lostty_label 'x'\\''; rm -rf ~' \\; "))
        #expect(throws: TmuxRemoteError.badSessionID("$4;x")) {
            try TmuxRemote.renameCommand(sessionID: "$4;x", name: "p", label: "x")
        }
    }

    @Test func theEndProbeReadsTheTagAndWhetherTheSessionIsThere() throws {
        #expect(try TmuxRemote.endProbeCommand(sessionID: "$7") ==
            "T=$(\(Self.tmux) -f /dev/null show-options -gqv '@lostty_end_7' 2>/dev/null); "
            + "if \(Self.tmux) -f /dev/null has-session -t '$7' 2>/dev/null; then echo present; else echo gone; fi; "
            + "printf '%s\\n' \"$T\"")
    }

    @Test func parsesTheEndProbe() {
        #expect(TmuxRemote.parseEndProbe("gone\nmac-close\n") == EndProbe(exists: false, tag: "mac-close"))
        #expect(TmuxRemote.parseEndProbe("present\n\n") == EndProbe(exists: true, tag: nil))
        #expect(TmuxRemote.parseEndProbe("gone\n") == EndProbe(exists: false, tag: nil))
        #expect(TmuxRemote.parseEndProbe("") == nil)
        #expect(TmuxRemote.parseEndProbe("no server running\n") == nil)
    }

    @Test func theWatchLoopsOnTheChannelWithoutStartingAServer() {
        #expect(TmuxRemote.watchCommand == "while \(Self.tmux) -f /dev/null wait-for lostty-changed; do echo; done")
    }

    @Test func eachSessionHasItsOwnEndOption() throws {
        #expect(try TmuxRemote.endOption(sessionID: "$12") == "@lostty_end_12")
        #expect(throws: TmuxRemoteError.badSessionID("12")) { try TmuxRemote.endOption(sessionID: "12") }
    }

    @Test func listsAreAtLeast300msApart() {
        let t = Date(timeIntervalSince1970: 100)
        #expect(ListPacing.delay(sinceLastList: t, now: t) == 0.3)
        #expect(abs(ListPacing.delay(sinceLastList: t, now: t.addingTimeInterval(0.1)) - 0.2) < 0.0001)
        #expect(ListPacing.delay(sinceLastList: t, now: t.addingTimeInterval(1)) == 0)
        #expect(ListPacing.delay(sinceLastList: .distantPast, now: t) == 0)
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path macos/LosttyRemote --filter SessionEndTests`
Expected: build FAILS, "cannot find 'SessionEnd' in scope".

- [ ] **Step 3: Implement `SessionEnd.swift`**

```swift
import Foundation

/// What the Mac says about a session whose attach just ended.
public struct EndProbe: Equatable, Sendable {
    /// Still there: this client was detached, or the attach failed.
    public var exists: Bool
    /// `@lostty_end_<n>`: who ended it. nil: it ended by itself.
    public var tag: String?

    public init(exists: Bool, tag: String?) {
        self.exists = exists
        self.tag = tag
    }
}

/// What the phone's terminal does when its attach ends.
public enum SessionEnd: Equatable, Sendable {
    /// You ended it here (Close Session, or typing `exit`): back to the list.
    case backToList
    /// It is still on the Mac: back to the list, which says if the attach failed.
    case stillRunning
    /// Ended elsewhere: the overlay says why until Back to Sessions.
    case closed(String)

    /// Input this recent means the person typed `exit` (or Ctrl-D).
    public static let typedWindow: TimeInterval = 3
    public static let unreadable = "This terminal was closed"

    /// `probe` nil: the Mac couldn't be asked. A tag always wins over recent
    /// typing; "this phone closed it" comes only from `endedHere`, never from
    /// the tag (two phones can be the same model).
    public static func decide(probe: EndProbe?, endedHere: Bool, typedRecently: Bool) -> SessionEnd {
        if endedHere { return .backToList }
        guard let probe else { return .closed(unreadable) }
        if probe.exists { return .stillRunning }
        guard let tag = probe.tag else {
            return typedRecently ? .backToList : .closed("The shell exited")
        }
        if tag == TmuxRemote.EndTag.macClose { return .closed("Closed on your Mac") }
        if tag == TmuxRemote.EndTag.macQuit { return .closed("Lostty quit on your Mac") }
        if tag.hasPrefix(TmuxRemote.EndTag.phonePrefix) {
            let device = tag.dropFirst(TmuxRemote.EndTag.phonePrefix.count).trimmingCharacters(in: .whitespaces)
            if !device.isEmpty { return .closed("Closed from \(device)") }
        }
        return .closed(unreadable)
    }
}
```

- [ ] **Step 4: Implement the commands in `TmuxRemote.swift`**

Below `claudeOption`, add:

```swift
    /// The wait-for channel tmux hooks, the Mac and the phone signal when
    /// sessions change.
    public static let changedChannel = "lostty-changed"

    /// Who ended a session, kept in `@lostty_end_<n>` after it is gone.
    public enum EndTag {
        public static let macClose = "mac-close"
        public static let macQuit = "mac-quit"
        public static let phonePrefix = "phone:"

        public static func phone(_ device: String) -> String { phonePrefix + device }
    }

    /// The global option that keeps why session `sessionID` ended
    /// ("$3" → "@lostty_end_3"). Ids restart only with the server, which
    /// drops the options too.
    public static func endOption(sessionID: String) throws -> String {
        guard isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        return "@lostty_end_\(sessionID.dropFirst())"
    }

    private static var tmux: String { "\(pathPrefix) tmux -u -L lostty" }

    /// Prints a line each time sessions change, until the Mac has no tmux
    /// server (wait-for exits 1). `-f /dev/null`: never starts a server.
    public static var watchCommand: String {
        "while \(tmux) -f /dev/null wait-for \(changedChannel); do echo; done"
    }
```

Replace `killCommand(sessionID:name:)` with:

```swift
    /// Ends session `sessionID` (and with it the Mac window showing it),
    /// first noting that this phone (`device`) closed it. Exits 1 (without
    /// killing) if the id now names a different session.
    public static func killCommand(sessionID: String, name: String, device: String) throws -> String {
        let option = try endOption(sessionID: sessionID)
        return nameGuard(sessionID: sessionID, name: name)
            + "\(tmux) set-option -g \(option) \(shellQuote(EndTag.phone(device))) \\; kill-session -t \(shellQuote(sessionID))"
    }

    /// Names session `sessionID` (nil: back to the automatic name), then
    /// wakes every watcher. Exits 1 if the id now names a different session.
    public static func renameCommand(sessionID: String, name: String, label: String?) throws -> String {
        guard isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        let set = label.map { "set-option -t \(shellQuote(sessionID)) \(labelOption) \(shellQuote($0))" }
            ?? "set-option -u -t \(shellQuote(sessionID)) \(labelOption)"
        return nameGuard(sessionID: sessionID, name: name) + "\(tmux) \(set) \\; wait-for -S \(changedChannel)"
    }

    /// Line 1: `present` or `gone`; line 2: the end tag, if any.
    public static func endProbeCommand(sessionID: String) throws -> String {
        let option = try endOption(sessionID: sessionID)
        return "T=$(\(tmux) -f /dev/null show-options -gqv \(shellQuote(option)) 2>/dev/null); "
            + "if \(tmux) -f /dev/null has-session -t \(shellQuote(sessionID)) 2>/dev/null; then echo present; else echo gone; fi; "
            + "printf '%s\\n' \"$T\""
    }

    public static func parseEndProbe(_ output: String) -> EndProbe? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, first == "present" || first == "gone" else { return nil }
        let tag = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespaces) : ""
        return EndProbe(exists: first == "present", tag: tag.isEmpty ? nil : tag)
    }
```

At the end of the file, add:

```swift
/// The phone re-lists at most this often while changes stream in.
public enum ListPacing {
    public static let interval: TimeInterval = 0.3

    public static func delay(sinceLastList last: Date, now: Date) -> TimeInterval {
        max(0, interval - now.timeIntervalSince(last))
    }
}
```

- [ ] **Step 5: Implement the connection methods in `RemoteConnection.swift`**

Replace `killSession(_:name:)` with:

```swift
    /// Ends session `sessionID` (named `name`) on the Mac, noting that this
    /// phone (`device`) closed it. A session that already ended, or whose id
    /// now names another session (tmux exits 1), is left alone.
    public func killSession(_ sessionID: String, name: String, device: String) async throws {
        do {
            _ = try await client.executeCommand(try TmuxRemote.killCommand(sessionID: sessionID, name: name, device: device))
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 1 {
            return
        }
    }

    /// Names session `sessionID` (nil: back to automatic). False when it
    /// ended or its id now names another session.
    public func setLabel(_ label: String?, sessionID: String, name: String) async throws -> Bool {
        do {
            _ = try await client.executeCommand(try TmuxRemote.renameCommand(sessionID: sessionID, name: name, label: label))
            return true
        } catch let failed as SSHClient.CommandFailed where failed.exitCode == 1 {
            return false
        }
    }

    /// Why session `sessionID` ended: its end tag, and whether it is in
    /// fact still there. nil when the answer is unreadable.
    public func endProbe(_ sessionID: String) async throws -> EndProbe? {
        let out = try await client.executeCommand(try TmuxRemote.endProbeCommand(sessionID: sessionID))
        return TmuxRemote.parseEndProbe(String(buffer: out))
    }

    /// One event per change to the Mac's sessions (tmux's `lostty-changed`
    /// channel), on its own channel of this connection. Changes that arrive
    /// while one is unread fold into it. Ends when the Mac has no tmux
    /// server or the connection drops; closing the connection is the only
    /// way to stop it early (Citadel's stream doesn't close its channel).
    public func watchChanges() async throws -> AsyncStream<Void> {
        let output = try await client.executeCommandStream(TmuxRemote.watchCommand)
        return AsyncStream(Void.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let reader = Task {
                do {
                    for try await chunk in output {
                        if case .stdout(let buffer) = chunk, buffer.readableBytes > 0 { continuation.yield(()) }
                    }
                } catch {
                    // Exit 1 (no server) or a dropped connection: the watch ends.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }
```

- [ ] **Step 6: Keep the phone building**

In `macos/Sources/App/iOS/MobileStore.swift`, in `kill(_:)`, replace

```swift
                try await connection.killSession(session.id, name: session.name)
```

with

```swift
                try await connection.killSession(session.id, name: session.name, device: DeviceModel.current)
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --package-path macos/LosttyRemote`
Expected: `✔ Test run with … tests passed` (SessionEndTests and TmuxRemoteTests included).

- [ ] **Step 8: Build the iOS app**

Run the iOS build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add macos/LosttyRemote/Sources/LosttyRemote/TmuxRemote.swift macos/LosttyRemote/Sources/LosttyRemote/SessionEnd.swift macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift macos/LosttyRemote/Tests/LosttyRemoteTests/TmuxRemoteTests.swift macos/LosttyRemote/Tests/LosttyRemoteTests/SessionEndTests.swift macos/Sources/App/iOS/MobileStore.swift
git commit -m "lostty: rename, tagged close, end reason and live watch commands for the phone

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Mac change hooks, tagged ends and the watcher

**Files:**
- Modify: `src/shell-integration/lostty-tmux/tmux.conf` (append)
- Create: `macos/Sources/Features/Sessions/TmuxHooks.swift`
- Create: `macos/Sources/Features/Sessions/SessionWatcher.swift`
- Modify: `macos/Sources/Features/Sessions/TmuxClient.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (after `SessionsUI.offerOrphansAtLaunch(ghostty)`)
- Modify: `macos/Tests/Sessions/TmuxSessionTests.swift` (`TmuxClientTests`)
- Test: `macos/Tests/Sessions/TmuxHooksTests.swift` (new)

**Interfaces:**
- Consumes: `TmuxRemote.changedChannel`, `TmuxRemote.EndTag`, `TmuxRemote.endOption(sessionID:)` (Task 2); `TmuxRemote.listFormat`, `TmuxRemote.parse` (Task 1).
- Produces:
  - `enum TmuxHooks { static let events: [String]; static let command: String; static var confLines: [String]; static var setArgs: [String] }`
  - `extension Notification.Name { static let losttySessionsChanged }` (posted on the main queue after every wake)
  - `final class SessionWatcher { static let shared; func start(); static let waitArgs: [String]; static func pause(woke: Bool, waited: TimeInterval) -> TimeInterval }`
  - `TmuxClient.remoteSessions() -> [RemoteSession]`, `TmuxClient.signalChanged()`, `TmuxClient.end(_ session: TmuxSession, reason: String)`, `static TmuxClient.endArgs(_:reason:) -> [String]` (replaces `end(_:)`)

Decision: the spec says the Mac re-applies the hooks "at launch". The bundled `tmux.conf` comes from `zig-out` and the tmux server is started by the first pane, often after launch, so the watcher sets the hooks whenever a wait fails (no server, or the server went away) and the server is back, not only once at launch.

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/Sessions/TmuxHooksTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct TmuxHooksTests {
    @Test func tmuxConfSetsEveryHook() throws {
        // macos/Tests/Sessions/<this file> → repository root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let conf = try String(
            contentsOf: root.appendingPathComponent("src/shell-integration/lostty-tmux/tmux.conf"), encoding: .utf8)
        for line in TmuxHooks.confLines {
            #expect(conf.contains(line + "\n"), "tmux.conf is missing: \(line)")
        }
    }

    @Test func confLinesSignalTheChannel() {
        #expect(TmuxHooks.confLines.first == "set-hook -g session-created 'wait-for -S lostty-changed'")
        #expect(TmuxHooks.confLines.count == 5)
    }

    @Test func launchSetsTheSameHooksInOneCall() {
        let signal = "wait-for -S lostty-changed"
        #expect(TmuxHooks.setArgs == [
            "set-hook", "-g", "session-created", signal, ";",
            "set-hook", "-g", "session-closed", signal, ";",
            "set-hook", "-g", "session-renamed", signal, ";",
            "set-hook", "-g", "client-attached", signal, ";",
            "set-hook", "-g", "client-detached", signal,
        ])
    }
}

struct SessionWatcherTests {
    @Test func aWaitThatFailsAtOncePauses() {
        #expect(SessionWatcher.pause(woke: false, waited: 0.05) == 5)
    }

    @Test func aWakeOrATimeoutWaitsAgainAtOnce() {
        #expect(SessionWatcher.pause(woke: true, waited: 0.01) == 0)
        #expect(SessionWatcher.pause(woke: false, waited: 600) == 0)
    }

    @Test func theWaitNeverStartsAServerWithTheUsersConfig() {
        #expect(SessionWatcher.waitArgs == ["-f", "/dev/null", "wait-for", "lostty-changed"])
    }
}
#endif
```

In `macos/Tests/Sessions/TmuxSessionTests.swift`, add `import LosttyRemote` after `import Foundation`, then add to `final class TmuxClientTests` (after `runReportsFailure`):

```swift
    /// A stand-in tmux that lists `sessions` (4 columns) and appends every
    /// other call's arguments to `log`.
    private func loggingTmux(sessions: String, log: URL) throws -> TmuxClient {
        TmuxClient(tmuxPath: try fakeTmux("""
            if [ "$4" = list-sessions ]; then printf '\(sessions)'; exit 0; fi
            echo "$@" >> '\(log.path)'
            """))
    }

    private func tempLog() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake-tmux-log-\(UUID().uuidString)")
        fakes.append(url)
        return url
    }

    @Test func quittingTagsEachOwnSessionBeforeEndingIt() throws {
        let log = tempLog()
        let client = try loggingTmux(sessions: "$3\\tlostty\\t\(paneA.uuidString)\\t100\\n$4\\tnotes\\t\\t200\\n", log: log)
        client.endSessions(ownedBy: 100)
        #expect(try String(contentsOf: log, encoding: .utf8)
            == "-u -L lostty set-option -g @lostty_end_3 mac-quit ; kill-session -t $3\n")
    }

    @Test func closingAPaneTagsItsSessionMacClose() throws {
        let log = tempLog()
        let client = try loggingTmux(sessions: "$5\\tapi\\t\(paneA.uuidString)\\t100\\n", log: log)
        client.endSessions(showing: paneA, ownedBy: 100)
        #expect(try String(contentsOf: log, encoding: .utf8)
            == "-u -L lostty set-option -g @lostty_end_5 mac-close ; kill-session -t $5\n")
    }

    @Test func aBadIDIsKilledWithoutATag() {
        let odd = TmuxSession(id: "$x", name: "n", surface: nil, owner: nil)
        #expect(TmuxClient.endArgs(odd, reason: "mac-close") == ["kill-session", "-t", "$x"])
    }

    @Test func signallingNeverStartsAServerWithTheUsersConfig() throws {
        let log = tempLog()
        let client = try loggingTmux(sessions: "", log: log)
        client.signalChanged()
        #expect(try String(contentsOf: log, encoding: .utf8) == "-u -L lostty -f /dev/null wait-for -S lostty-changed\n")
    }

    @Test func remoteSessionsAskForThePhonesColumns() throws {
        let client = TmuxClient(tmuxPath: try fakeTmux("""
            [ "$6" = '\(TmuxRemote.listFormat)' ] || exit 1
            printf '$1\\tlostty\\t\\t\\tDeploy\\twaiting\\t100\\t2.1.296\\t/x\\t✳ Fix login\\n'
            """))
        let found = client.remoteSessions()
        #expect(found.map(\.label) == ["Deploy"])
        #expect(found.first?.claude == .waiting)
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh TmuxHooksTests`
Expected: build FAILS, "cannot find 'TmuxHooks' in scope".

- [ ] **Step 3: Add the hooks to `tmux.conf`**

Append to `src/shell-integration/lostty-tmux/tmux.conf`:

```
# Lostty Mobile: one wait-for channel says "sessions changed" to the phone's
# list and the Mac's watcher. The Mac app sets these again for a server
# started without them.
set-hook -g session-created 'wait-for -S lostty-changed'
set-hook -g session-closed 'wait-for -S lostty-changed'
set-hook -g session-renamed 'wait-for -S lostty-changed'
set-hook -g client-attached 'wait-for -S lostty-changed'
set-hook -g client-detached 'wait-for -S lostty-changed'
```

- [ ] **Step 4: Implement `TmuxHooks.swift`**

```swift
#if os(macOS)
import LosttyRemote

/// The tmux hooks that signal `lostty-changed`, so the phone's list and the
/// Mac's watcher hear about sessions coming, going, being renamed, and
/// clients attaching or leaving. tmux.conf has the same lines; the Mac sets
/// them again for a server started without them.
enum TmuxHooks {
    static let events = ["session-created", "session-closed", "session-renamed", "client-attached", "client-detached"]
    static let command = "wait-for -S \(TmuxRemote.changedChannel)"

    /// As written in tmux.conf.
    static var confLines: [String] {
        events.map { "set-hook -g \($0) '\(command)'" }
    }

    /// One `tmux` call setting all of them.
    static var setArgs: [String] {
        events.enumerated().flatMap { index, event in
            (index == 0 ? [] : [";"]) + ["set-hook", "-g", event, command]
        }
    }
}
#endif
```

- [ ] **Step 5: Implement `SessionWatcher.swift`**

```swift
#if os(macOS)
import Foundation
import LosttyRemote

extension Notification.Name {
    /// Lostty's tmux sessions changed. Posted on the main queue.
    static let losttySessionsChanged = Notification.Name("LosttySessionsChanged")
}

/// Lostty Mobile: waits on tmux's `lostty-changed` channel on its own thread
/// and posts `.losttySessionsChanged` after every wake. Gives the tmux server
/// the change hooks whenever it (re)appears: one started by an older Lostty,
/// or from an older bundled tmux.conf, has none.
final class SessionWatcher: @unchecked Sendable {
    static let shared = SessionWatcher()

    /// `-f /dev/null`: waiting must never start a server that reads the
    /// user's ~/.tmux.conf.
    static let waitArgs = ["-f", "/dev/null", "wait-for", TmuxRemote.changedChannel]

    private let lock = NSLock()
    private var started = false

    func start() {
        let first: Bool = lock.withLock {
            defer { started = true }
            return !started
        }
        guard first else { return }
        let thread = Thread { [self] in loop() }
        thread.name = "Lostty session watcher"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// Seconds to rest before waiting again. A wait that failed at once
    /// means no server: look again in 5 s instead of spinning.
    static func pause(woke: Bool, waited: TimeInterval) -> TimeInterval {
        !woke && waited < 1 ? 5 : 0
    }

    private func loop() {
        let client = TmuxClient()
        guard client.tmuxPath != nil else { return }
        // Up to 10 minutes per wait; a timeout just waits again.
        let waiter = TmuxClient(timeout: 600)
        var hooksSet = false
        while true {
            if !hooksSet { hooksSet = client.run(TmuxHooks.setArgs) != nil }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .losttySessionsChanged, object: nil)
            }
            let start = Date()
            let woke = waiter.run(Self.waitArgs) != nil
            // A failed wait may mean a new server: set the hooks again.
            if !woke { hooksSet = false }
            let rest = Self.pause(woke: woke, waited: Date().timeIntervalSince(start))
            if rest > 0 { Thread.sleep(forTimeInterval: rest) }
        }
    }
}
#endif
```

- [ ] **Step 6: Tagged ends and the new calls in `TmuxClient.swift`**

Add `import LosttyRemote` after `import Foundation`. Replace `end(_:)`, `endSessions(showing:ownedBy:)` and `endSessions(ownedBy:)` with:

```swift
    /// Every session with the phone's columns (label, Claude state, title,
    /// folder, last use), for the menu bar and the sync.
    func remoteSessions() -> [RemoteSession] {
        run(["list-sessions", "-F", TmuxRemote.listFormat]).map(TmuxRemote.parse) ?? []
    }

    /// Wakes everything waiting on `lostty-changed`: the phone's list, other
    /// Lostty processes, this one's watcher.
    func signalChanged() {
        run(["-f", "/dev/null", "wait-for", "-S", TmuxRemote.changedChannel])
    }

    /// Ends `session`, first noting why (`@lostty_end_<n>`), so a phone
    /// attached to it can say so.
    func end(_ session: TmuxSession, reason: String) {
        run(Self.endArgs(session, reason: reason))
    }

    static func endArgs(_ session: TmuxSession, reason: String) -> [String] {
        guard let option = try? TmuxRemote.endOption(sessionID: session.id) else {
            return ["kill-session", "-t", session.id]
        }
        return ["set-option", "-g", option, reason, ";", "kill-session", "-t", session.id]
    }

    /// Ends the session showing pane `surface`: closing a pane ends its
    /// shell, as on a plain terminal.
    func endSessions(showing surface: UUID, ownedBy pid: Int32) {
        for session in TmuxOwnership.showing(surface, ownedBy: pid, in: sessions()) {
            end(session, reason: TmuxRemote.EndTag.macClose)
        }
    }

    /// Ends every session Lostty `pid` shows: quitting ends its shells.
    func endSessions(ownedBy pid: Int32) {
        for session in TmuxOwnership.owned(by: pid, in: sessions()) {
            end(session, reason: TmuxRemote.EndTag.macQuit)
        }
    }
```

- [ ] **Step 7: Start the watcher**

In `AppDelegate.applicationDidFinishLaunching`, right after `SessionsUI.offerOrphansAtLaunch(ghostty)`:

```swift
        // Lostty Mobile: watch tmux for session changes (labels, a phone
        // attaching) and give a tmux server without them the change hooks.
        SessionWatcher.shared.start()
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `macos/skins-test.sh TmuxHooksTests`, `macos/skins-test.sh SessionWatcherTests`, `macos/skins-test.sh TmuxClientTests`, `macos/skins-test.sh TmuxSessionTests`
Expected: `** TEST SUCCEEDED **` for each.

- [ ] **Step 9: Build the Mac app**

Run: `macos/build.nu --configuration Debug --action build`
Expected: build succeeds.

- [ ] **Step 10: Commit**

```bash
git add src/shell-integration/lostty-tmux/tmux.conf macos/Sources/Features/Sessions/TmuxHooks.swift macos/Sources/Features/Sessions/SessionWatcher.swift macos/Sources/Features/Sessions/TmuxClient.swift macos/Sources/App/macOS/AppDelegate.swift macos/Tests/Sessions/TmuxHooksTests.swift macos/Tests/Sessions/TmuxSessionTests.swift
git commit -m "lostty: tmux change hooks, tagged session ends and a Mac watcher

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Mac writes Claude state and signals task-title changes

**Files:**
- Create: `macos/Sources/Features/Claude/ClaudeTmuxSync.swift`
- Create: `macos/Sources/Features/Sessions/SessionTitleSignal.swift`
- Modify: `macos/Sources/Ghostty/Ghostty.App.swift` (`setTitle`, the `ClaudeRuntime.shared.titleChanged` line)
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (deinit's `Task { @MainActor in … }`)
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (after `SessionWatcher.shared.start()`)
- Test: `macos/Tests/Claude/ClaudeTmuxSyncTests.swift` (new), `macos/Tests/Sessions/SessionTitleSignalTests.swift` (new)

**Interfaces:**
- Consumes: `ClaudeRuntime.shared.$phases`, `$awaiting`; `TmuxClient.remoteSessions()`, `TmuxClient.signalChanged()`, `.losttySessionsChanged` (Task 3); `TmuxRemote.claudeOption`, `ClaudeActivity`, `SessionLabel.hasClaudeGlyph`, `SessionLabel.cleanTitle` (Task 1); `TmuxRemote.changedChannel` (Task 2).
- Produces:
  - `@MainActor final class ClaudeTmuxSync { static let shared; func start(); nonisolated static func desired(phases: Set<UUID>, awaiting: Set<UUID>) -> [String: ClaudeActivity]; nonisolated static func args(desired: [String: ClaudeActivity], sessions: [RemoteSession], pid: Int32) -> [String] }`
  - `struct SignalThrottle { enum Decision: Equatable { case fireNow, fireAfter(TimeInterval), alreadyPending }; init(interval:); mutating func request(now: Date) -> Decision; mutating func firedPending(now: Date) }`
  - `@MainActor final class SessionTitleSignal { static let shared; init(now:schedule:signal:); func titleChanged(_ id: UUID, title: String); func surfaceClosed(_ id: UUID) }`

Decisions: `waiting` = the pane is in `ClaudeRuntime.awaiting` (an unseen wait); `working` = it has a non-off trace phase; otherwise unset (an idle Claude already seen reads as last used). The writer compares against what tmux holds (`@lostty_claude` is in the list), so it writes only differences and signals only after writing. It also re-syncs on every watcher wake, so a session created after the change catches up.

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/Claude/ClaudeTmuxSyncTests.swift`:

```swift
#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Ghostty

struct ClaudeTmuxSyncTests {
    let a = UUID(uuidString: "ABCDEF01-0000-4000-8000-000000000001")!
    let b = UUID(uuidString: "ABCDEF02-0000-4000-8000-000000000002")!

    func session(_ id: String, _ pane: UUID?, owner: Int32?, claude: ClaudeActivity?) -> RemoteSession {
        RemoteSession(id: id, name: "p", surface: pane?.uuidString, owner: owner, claude: claude)
    }

    @Test func waitingBeatsWorking() {
        #expect(ClaudeTmuxSync.desired(phases: [a, b], awaiting: [a]) == [a.uuidString: .waiting, b.uuidString: .working])
    }

    @Test func writesOnlyWhatChangedThenSignals() {
        let sessions = [session("$1", a, owner: 100, claude: nil), session("$2", b, owner: 100, claude: .working)]
        #expect(ClaudeTmuxSync.args(desired: [a.uuidString: .waiting], sessions: sessions, pid: 100) == [
            "set-option", "-t", "$1", "@lostty_claude", "waiting", ";",
            "set-option", "-u", "-t", "$2", "@lostty_claude", ";",
            "wait-for", "-S", "lostty-changed",
        ])
    }

    @Test func nothingToWriteWhenTmuxAlreadyAgrees() {
        let sessions = [session("$1", a, owner: 100, claude: .waiting), session("$2", b, owner: 100, claude: nil)]
        #expect(ClaudeTmuxSync.args(desired: [a.uuidString: .waiting], sessions: sessions, pid: 100).isEmpty)
    }

    @Test func otherLosttysAndPaneLessSessionsAreLeftAlone() {
        let sessions = [session("$1", a, owner: 200, claude: nil), session("$2", nil, owner: 100, claude: .working)]
        #expect(ClaudeTmuxSync.args(desired: [a.uuidString: .working], sessions: sessions, pid: 100).isEmpty)
    }
}
#endif
```

Create `macos/Tests/Sessions/SessionTitleSignalTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SessionTitleSignalTests {
    final class Harness {
        var clock = Date(timeIntervalSince1970: 1_000)
        var signals = 0
        var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    }

    let harness = Harness()
    let pane = UUID()

    func make() -> SessionTitleSignal {
        let harness = self.harness
        return SessionTitleSignal(
            now: { harness.clock },
            schedule: { delay, work in harness.pending.append((delay, work)) },
            signal: { harness.signals += 1 })
    }

    func advance(_ seconds: TimeInterval) { harness.clock = harness.clock.addingTimeInterval(seconds) }

    @Test func spinnerFramesDoNotSignal() {
        let signal = make()
        signal.titleChanged(pane, title: "◐ Fix the login bug")
        advance(5)
        signal.titleChanged(pane, title: "◓ Fix the login bug")
        signal.titleChanged(pane, title: "✳ Fix the login bug")
        #expect(harness.signals == 1)
        #expect(harness.pending.isEmpty)
    }

    @Test func aNewTaskTitleSignals() {
        let signal = make()
        signal.titleChanged(pane, title: "◐ Fix the login bug")
        advance(5)
        signal.titleChanged(pane, title: "◐ Write the release notes")
        #expect(harness.signals == 2)
    }

    @Test func atMostOncePerSecond() {
        let signal = make()
        signal.titleChanged(pane, title: "◐ A")
        advance(0.2)
        signal.titleChanged(pane, title: "◐ B")
        advance(0.1)
        signal.titleChanged(pane, title: "◐ C")
        #expect(harness.signals == 1)
        #expect(harness.pending.count == 1)
        #expect(abs((harness.pending.first?.delay ?? 0) - 0.8) < 0.0001)
        advance(0.7)
        harness.pending.removeFirst().work()
        #expect(harness.signals == 2)
    }

    @Test func plainShellTitlesNeverSignal() {
        let signal = make()
        signal.titleChanged(pane, title: "~/projectrepos/lostty")
        advance(5)
        signal.titleChanged(pane, title: "~/projectrepos/lostty/macos")
        #expect(harness.signals == 0)
    }

    @Test func leavingClaudeSignals() {
        let signal = make()
        signal.titleChanged(pane, title: "✳ Fix the login bug")
        advance(5)
        signal.titleChanged(pane, title: "~/projectrepos/lostty")
        #expect(harness.signals == 2)
    }
}
#endif
```

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh ClaudeTmuxSyncTests`
Expected: build FAILS, "cannot find 'ClaudeTmuxSync' in scope".

- [ ] **Step 3: Implement `ClaudeTmuxSync.swift`**

```swift
#if os(macOS)
import Combine
import Foundation
import LosttyRemote

/// Lostty Mobile: writes each of this Lostty's sessions' Claude state into
/// tmux (`@lostty_claude`: waiting, working, or unset) whenever
/// `ClaudeRuntime` changes, then wakes watchers, so the phone shows
/// "Waiting" and "Working". Only sessions this process owns: several Lostty
/// processes share the server and must not fight.
@MainActor
final class ClaudeTmuxSync {
    static let shared = ClaudeTmuxSync()

    private var watchers: Set<AnyCancellable> = []

    func start() {
        guard watchers.isEmpty else { return }
        let runtime = ClaudeRuntime.shared
        runtime.$phases.combineLatest(runtime.$awaiting)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { phases, awaiting in
                Self.sync(Self.desired(phases: Set(phases.keys), awaiting: awaiting))
            }
            .store(in: &watchers)
        // A session made after the change, or a write tmux dropped, catches up.
        NotificationCenter.default.publisher(for: .losttySessionsChanged)
            .sink { _ in
                MainActor.assumeIsolated {
                    let runtime = ClaudeRuntime.shared
                    Self.sync(Self.desired(phases: Set(runtime.phases.keys), awaiting: runtime.awaiting))
                }
            }
            .store(in: &watchers)
    }

    nonisolated private static func sync(_ desired: [String: ClaudeActivity]) {
        let pid = ProcessInfo.processInfo.processIdentifier
        Task.detached(priority: .utility) {
            let client = TmuxClient()
            let changes = Self.args(desired: desired, sessions: client.remoteSessions(), pid: pid)
            if !changes.isEmpty { client.run(changes) }
        }
    }

    /// Pane (uuidString) → what tmux should hold. A pane missing is unset.
    nonisolated static func desired(phases: Set<UUID>, awaiting: Set<UUID>) -> [String: ClaudeActivity] {
        var result: [String: ClaudeActivity] = [:]
        for id in phases { result[id.uuidString] = .working }
        for id in awaiting { result[id.uuidString] = .waiting }
        return result
    }

    /// One tmux call writing only what differs, then the signal; empty when
    /// tmux already agrees (so a wake never causes another wake).
    nonisolated static func args(desired: [String: ClaudeActivity], sessions: [RemoteSession], pid: Int32) -> [String] {
        var args: [String] = []
        for session in sessions where session.owner == pid {
            guard let pane = session.surface else { continue }
            let want = desired[pane]
            guard want != session.claude else { continue }
            if !args.isEmpty { args.append(";") }
            if let want {
                args += ["set-option", "-t", session.id, TmuxRemote.claudeOption, want.rawValue]
            } else {
                args += ["set-option", "-u", "-t", session.id, TmuxRemote.claudeOption]
            }
        }
        if !args.isEmpty { args += [";", "wait-for", "-S", TmuxRemote.changedChannel] }
        return args
    }
}
#endif
```

- [ ] **Step 4: Implement `SessionTitleSignal.swift`**

```swift
#if os(macOS)
import Foundation
import LosttyRemote

/// At most one signal per `interval`: a change fires at once; changes in
/// the window after it fire once, at its end.
struct SignalThrottle {
    enum Decision: Equatable {
        case fireNow
        case fireAfter(TimeInterval)
        case alreadyPending
    }

    let interval: TimeInterval
    private(set) var lastFired: Date?
    private(set) var pending = false

    init(interval: TimeInterval) {
        self.interval = interval
    }

    mutating func request(now: Date) -> Decision {
        if pending { return .alreadyPending }
        if let last = lastFired, now.timeIntervalSince(last) < interval {
            pending = true
            return .fireAfter(interval - now.timeIntervalSince(last))
        }
        lastFired = now
        return .fireNow
    }

    mutating func firedPending(now: Date) {
        pending = false
        lastFired = now
    }
}

/// Lostty Mobile: wakes the phone's list when a Claude pane's task title
/// changes; tmux has no hook for title changes. Spinner frames are not
/// changes: only the title without its leading glyph counts, at most once
/// a second.
@MainActor
final class SessionTitleSignal {
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    static let shared = SessionTitleSignal()

    private let now: () -> Date
    private let schedule: Scheduler
    private let signal: () -> Void
    private var throttle = SignalThrottle(interval: 1)
    /// The cleaned title of each pane whose title is a Claude task.
    private var tasks: [UUID: String] = [:]

    init(
        now: @escaping () -> Date = Date.init,
        schedule: @escaping Scheduler = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { work() }
            }
        },
        signal: @escaping () -> Void = {
            Task.detached(priority: .utility) { TmuxClient().signalChanged() }
        }
    ) {
        self.now = now
        self.schedule = schedule
        self.signal = signal
    }

    func titleChanged(_ id: UUID, title: String) {
        let task: String? = SessionLabel.hasClaudeGlyph(title) ? SessionLabel.cleanTitle(title) : nil
        guard tasks[id] != task else { return }
        tasks[id] = task
        switch throttle.request(now: now()) {
        case .fireNow:
            signal()
        case .fireAfter(let delay):
            schedule(delay) { [weak self] in
                guard let self else { return }
                throttle.firedPending(now: now())
                signal()
            }
        case .alreadyPending:
            break
        }
    }

    func surfaceClosed(_ id: UUID) {
        tasks[id] = nil
    }
}
#endif
```

- [ ] **Step 5: Wire titles, closes and start**

In `macos/Sources/Ghostty/Ghostty.App.swift`, `setTitle`, replace

```swift
                MainActor.assumeIsolated { ClaudeRuntime.shared.titleChanged(surfaceView.id, title: title) }
```

with

```swift
                MainActor.assumeIsolated {
                    ClaudeRuntime.shared.titleChanged(surfaceView.id, title: title)
                    // Lostty Mobile: a Claude task title changed; phones re-list.
                    SessionTitleSignal.shared.titleChanged(surfaceView.id, title: title)
                }
```

In `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`, deinit, replace

```swift
            Task { @MainActor in
                ClaudeRuntime.shared.surfaceClosed(closedID)
                ClaudeUsageRuntime.shared.surfaceClosed(closedID)
            }
```

with

```swift
            Task { @MainActor in
                ClaudeRuntime.shared.surfaceClosed(closedID)
                ClaudeUsageRuntime.shared.surfaceClosed(closedID)
                SessionTitleSignal.shared.surfaceClosed(closedID)
            }
```

In `AppDelegate.applicationDidFinishLaunching`, right after `SessionWatcher.shared.start()`:

```swift
        // Lostty Mobile: each pane's Claude state, for the phone's badges.
        ClaudeTmuxSync.shared.start()
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `macos/skins-test.sh ClaudeTmuxSyncTests` then `macos/skins-test.sh SessionTitleSignalTests` then `macos/skins-test.sh ClaudeRuntimeTests`
Expected: `** TEST SUCCEEDED **` for each.

- [ ] **Step 7: Build both apps**

Run: `macos/build.nu --configuration Debug --action build`
Expected: build succeeds.
Run the iOS build command from Global Constraints (`Ghostty.App.swift` is shared).
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/Claude/ClaudeTmuxSync.swift macos/Sources/Features/Sessions/SessionTitleSignal.swift macos/Sources/Ghostty/Ghostty.App.swift "macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift" macos/Sources/App/macOS/AppDelegate.swift macos/Tests/Claude/ClaudeTmuxSyncTests.swift macos/Tests/Sessions/SessionTitleSignalTests.swift
git commit -m "lostty: Mac publishes Claude waiting/working and task titles to tmux

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Labels ↔ Rename Tab…, and a phone attaching counts as seen

**Files:**
- Create: `macos/Sources/Features/Sessions/SessionSync.swift`
- Modify: `macos/Sources/Features/Sessions/TmuxClient.swift` (+ `setLabel`, `labelArgs`)
- Modify: `macos/Sources/Features/StayAwake/AttachedPhones.swift` (+ `idFormat`, `currentSessionIDs()`)
- Modify: `macos/Sources/Features/Claude/ClaudeRuntime.swift` (+ `seenElsewhere(_:)`)
- Modify: `macos/Sources/Features/Terminal/BaseTerminalController.swift` (`titleOverride` neighbours, `promptTabTitle`, `focusedSurfaceDidChange`)
- Modify: `macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift` (`tabTitleEditor(_:didCommitTitle:for:)`)
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (after `ClaudeTmuxSync.shared.start()`)
- Test: `macos/Tests/Sessions/SessionSyncTests.swift` (new); add to `macos/Tests/Claude/ClaudeRuntimeTests.swift`, `macos/Tests/StayAwake/AttachedPhonesTests.swift`, `macos/Tests/Sessions/TmuxSessionTests.swift`

**Interfaces:**
- Consumes: `.losttySessionsChanged`, `TmuxClient.remoteSessions()` (Task 3); `SessionLabel.cleanLabel`, `TmuxRemote.labelOption` (Task 1); `TmuxRemote.changedChannel` (Task 2); `AttachedPhones.sessions(clients:parent:)`; `TmuxOwnership.showing`.
- Produces:
  - `@MainActor final class SessionSync { static let shared; private(set) var labels: [UUID: String]; func start(); func refresh(); func apply(_: [RemoteSession], phoneAttached: Set<String>); func setLabel(_ typed: String?, forPane: UUID); nonisolated static func labels(_: [RemoteSession], pid: Int32) -> [UUID: String]; nonisolated static func panesWithAPhone(_: [RemoteSession], phoneAttached: Set<String>, pid: Int32) -> [UUID] }`
  - `struct SessionTitleOverride: Equatable { var title: String?; var fromLabel: Bool; static func next(current: String?, fromLabel: Bool, label: String?) -> SessionTitleOverride }`
  - `ClaudeRuntime.seenElsewhere(_ id: UUID)`
  - `AttachedPhones.idFormat`, `AttachedPhones.currentSessionIDs() -> [String]`
  - `TmuxClient.setLabel(_ label: String?, surface: UUID, ownedBy: Int32)`, `static TmuxClient.labelArgs(_:sessionID:) -> [String]`
  - `BaseTerminalController.applySessionLabel()`, `BaseTerminalController.renameTab(to: String?)`

Decisions: `titleOverride` belongs to a tab (controller), a label to a pane's session, so the label follows focus: the focused pane's label becomes the tab's override; focusing a pane without one clears an override that came from a label, while a title typed for a plain (non-tmux) pane stays. The watcher can't tell which hook woke it, so it checks for SSH-attached clients on every wake; a phone that stays attached to a pane also counts later waits as seen, as a focused Mac pane does. The local label map is updated only from tmux (after the write's own signal), never optimistically, so a stale refresh can't flicker the title back.

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/Sessions/SessionSyncTests.swift`:

```swift
#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Ghostty

private let paneA = UUID(uuidString: "ABCDEF01-0000-4000-8000-000000000001")!
private let paneB = UUID(uuidString: "ABCDEF02-0000-4000-8000-000000000002")!

struct SessionSyncTests {
    let sessions = [
        RemoteSession(id: "$1", name: "a", surface: paneA.uuidString, owner: 100, label: "Deploy"),
        RemoteSession(id: "$2", name: "b", surface: paneB.uuidString, owner: 200, label: "Other Lostty"),
        RemoteSession(id: "$3", name: "c", surface: nil, owner: nil, label: "Made on the phone"),
        RemoteSession(id: "$4", name: "d", surface: "not-a-uuid", owner: 100, label: "Junk"),
        RemoteSession(id: "$5", name: "e", surface: paneB.uuidString, owner: 100, label: nil),
    ]

    @Test func labelsAreThisLosttysPanes() {
        #expect(SessionSync.labels(sessions, pid: 100) == [paneA: "Deploy"])
    }

    @Test func aPhoneOnOneOfOurSessionsNamesItsPane() {
        #expect(SessionSync.panesWithAPhone(sessions, phoneAttached: ["$1", "$2", "$3"], pid: 100) == [paneA])
    }
}

struct SessionTitleOverrideTests {
    @Test func aLabelBecomesTheTabTitle() {
        #expect(SessionTitleOverride.next(current: nil, fromLabel: false, label: "Deploy")
            == SessionTitleOverride(title: "Deploy", fromLabel: true))
    }

    @Test func clearingALabelClearsTheTitleItSet() {
        #expect(SessionTitleOverride.next(current: "Deploy", fromLabel: true, label: nil)
            == SessionTitleOverride(title: nil, fromLabel: false))
    }

    @Test func aTitleTypedForAPlainPaneStays() {
        #expect(SessionTitleOverride.next(current: "Notes", fromLabel: false, label: nil)
            == SessionTitleOverride(title: "Notes", fromLabel: false))
    }
}
#endif
```

Add to `ClaudeRuntimeTests` in `macos/Tests/Claude/ClaudeRuntimeTests.swift`:

```swift
    @Test func aPhoneAttachingCountsAsSeeingTheWait() {
        let runtime = makeRuntime()
        runtime.focusChanged(pane, focused: false)
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        #expect(runtime.awaiting == [pane])
        runtime.seenElsewhere(pane)
        #expect(runtime.awaiting.isEmpty)
        // The same wait doesn't come back.
        runtime.apply(.idle, to: pane)
        #expect(runtime.awaiting.isEmpty)
    }
```

Add to `AttachedPhonesTests` in `macos/Tests/StayAwake/AttachedPhonesTests.swift`:

```swift
    @Test func sessionIDsComeFromTheSameWalk() {
        #expect(AttachedPhones.idFormat == "#{client_pid}\t#{session_id}")
        #expect(AttachedPhones.sessions(clients: "500\t$3\n600\t$4\n", parent: parent) == ["$3"])
    }
```

Add to `TmuxClientTests` in `macos/Tests/Sessions/TmuxSessionTests.swift`:

```swift
    @Test func renamingSetsOrClearsTheLabelThenSignals() {
        #expect(TmuxClient.labelArgs("Deploy", sessionID: "$3")
            == ["set-option", "-t", "$3", "@lostty_label", "Deploy", ";", "wait-for", "-S", "lostty-changed"])
        #expect(TmuxClient.labelArgs(nil, sessionID: "$3")
            == ["set-option", "-u", "-t", "$3", "@lostty_label", ";", "wait-for", "-S", "lostty-changed"])
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh SessionSyncTests`
Expected: build FAILS, "cannot find 'SessionSync' in scope".

- [ ] **Step 3: Implement `SessionSync.swift`**

```swift
#if os(macOS)
import AppKit
import LosttyRemote

/// Lostty Mobile on the Mac: after every tmux change, shows session labels
/// (set here or on the phone) as tab titles, and counts a phone attached to
/// a waiting Claude as seeing it.
@MainActor
final class SessionSync {
    static let shared = SessionSync()

    /// This Lostty's panes whose session has a label.
    private(set) var labels: [UUID: String] = [:]
    private var observer: NSObjectProtocol?
    private let pid = ProcessInfo.processInfo.processIdentifier

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .losttySessionsChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SessionSync.shared.refresh() }
        }
    }

    func refresh() {
        Task {
            let (sessions, phones) = await Task.detached(priority: .utility) {
                (TmuxClient().remoteSessions(), Set(AttachedPhones.currentSessionIDs()))
            }.value
            apply(sessions, phoneAttached: phones)
        }
    }

    func apply(_ sessions: [RemoteSession], phoneAttached: Set<String>) {
        let next = Self.labels(sessions, pid: pid)
        if next != labels {
            labels = next
            for controller in NSApp.windows.compactMap({ $0.windowController as? BaseTerminalController }) {
                controller.applySessionLabel()
            }
        }
        for pane in Self.panesWithAPhone(sessions, phoneAttached: phoneAttached, pid: pid) {
            ClaudeRuntime.shared.seenElsewhere(pane)
        }
    }

    /// Rename Tab…: names the session showing `pane` (nil clears it). The
    /// label map follows on the change event the write sends.
    func setLabel(_ typed: String?, forPane pane: UUID) {
        let label = typed.flatMap(SessionLabel.cleanLabel)
        let pid = self.pid
        Task.detached(priority: .utility) {
            TmuxClient().setLabel(label, surface: pane, ownedBy: pid)
        }
    }

    nonisolated static func labels(_ sessions: [RemoteSession], pid: Int32) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for session in sessions where session.owner == pid {
            guard let label = session.label, let pane = session.surface.flatMap(UUID.init(uuidString:)) else { continue }
            result[pane] = label
        }
        return result
    }

    nonisolated static func panesWithAPhone(_ sessions: [RemoteSession], phoneAttached: Set<String>, pid: Int32) -> [UUID] {
        sessions
            .filter { $0.owner == pid && phoneAttached.contains($0.id) }
            .compactMap { $0.surface.flatMap(UUID.init(uuidString:)) }
    }
}

/// The tab title a label gives the focused pane.
struct SessionTitleOverride: Equatable {
    var title: String?
    /// The title came from a label, so it goes when the label does (or
    /// focus moves to a pane without one).
    var fromLabel: Bool

    static func next(current: String?, fromLabel: Bool, label: String?) -> SessionTitleOverride {
        if let label { return SessionTitleOverride(title: label, fromLabel: true) }
        if fromLabel { return SessionTitleOverride(title: nil, fromLabel: false) }
        return SessionTitleOverride(title: current, fromLabel: false)
    }
}
#endif
```

- [ ] **Step 4: TmuxClient, AttachedPhones, ClaudeRuntime**

In `TmuxClient.swift`, after `disown(_:)`:

```swift
    /// Names the session showing pane `surface` (nil: back to automatic),
    /// then wakes watchers so the phone shows it.
    func setLabel(_ label: String?, surface: UUID, ownedBy pid: Int32) {
        for session in TmuxOwnership.showing(surface, ownedBy: pid, in: sessions()) {
            run(Self.labelArgs(label, sessionID: session.id))
        }
    }

    static func labelArgs(_ label: String?, sessionID: String) -> [String] {
        let set = label.map { ["set-option", "-t", sessionID, TmuxRemote.labelOption, $0] }
            ?? ["set-option", "-u", "-t", sessionID, TmuxRemote.labelOption]
        return set + [";", "wait-for", "-S", TmuxRemote.changedChannel]
    }
```

In `AttachedPhones.swift`, after `current()`:

```swift
    static let idFormat = "#{client_pid}\t#{session_id}"

    /// Session ids ("$3") with an SSH-attached client.
    static func currentSessionIDs() -> [String] {
        guard let out = TmuxClient().run(["list-clients", "-F", idFormat]) else { return [] }
        return sessions(clients: out, parent: processParent)
    }
```

In `ClaudeRuntime.swift`, after `focusChanged(_:focused:)`:

```swift
    /// Lostty Mobile: a phone attached to this pane's session. Seeing it
    /// there counts like focusing it here.
    func seenElsewhere(_ id: UUID) {
        guard awaiting.contains(id) else { return }
        seen.insert(id)
        awaiting.remove(id)
    }
```

- [ ] **Step 5: Rename Tab… and the tab title**

In `BaseTerminalController.swift`, right after the `titleOverride` property:

```swift
    /// Lostty Mobile: the override came from the focused pane's session
    /// label, so it follows focus and goes when the label does.
    private var titleOverrideFromLabel = false
```

After `promptTabTitle()`:

```swift
    /// Lostty Mobile: shows the focused pane's session label (set here or
    /// on the phone) as the tab title.
    func applySessionLabel() {
        let label = focusedSurface.flatMap { $0.inTmuxSession ? SessionSync.shared.labels[$0.id] : nil }
        let next = SessionTitleOverride.next(current: titleOverride, fromLabel: titleOverrideFromLabel, label: label)
        titleOverrideFromLabel = next.fromLabel
        if titleOverride != next.title { titleOverride = next.title }
    }

    /// Rename Tab…: the tab's title, and the focused pane's session label,
    /// so the phone shows the same name. nil restores both.
    func renameTab(to title: String?) {
        titleOverride = title
        guard let surface = focusedSurface, surface.inTmuxSession else {
            titleOverrideFromLabel = false
            return
        }
        titleOverrideFromLabel = title != nil
        SessionSync.shared.setLabel(title, forPane: surface.id)
    }
```

In `promptTabTitle()`'s completion, replace

```swift
            let newTitle = textField.stringValue
            if newTitle.isEmpty {
                self.titleOverride = nil
            } else {
                self.titleOverride = newTitle
            }
```

with

```swift
            let newTitle = textField.stringValue
            self.renameTab(to: newTitle.isEmpty ? nil : newTitle)
```

At the end of `focusedSurfaceDidChange(to:)` (after the `if … else { titleDidChange(to: "👻") }` block), add:

```swift

        // Lostty Mobile: the newly focused pane's session label, if any.
        applySessionLabel()
```

In `TerminalWindow.swift`, `tabTitleEditor(_:didCommitTitle:for:)`, replace

```swift
        targetController.titleOverride = editedTitle.isEmpty ? nil : editedTitle
```

with

```swift
        targetController.renameTab(to: editedTitle.isEmpty ? nil : editedTitle)
```

In `AppDelegate.applicationDidFinishLaunching`, right after `ClaudeTmuxSync.shared.start()`:

```swift
        // Lostty Mobile: session labels as tab titles; a phone attaching
        // counts as seeing a waiting Claude.
        SessionSync.shared.start()
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `macos/skins-test.sh SessionSyncTests`, `macos/skins-test.sh SessionTitleOverrideTests`, `macos/skins-test.sh ClaudeRuntimeTests`, `macos/skins-test.sh AttachedPhonesTests`, `macos/skins-test.sh TmuxClientTests`
Expected: `** TEST SUCCEEDED **` for each.

- [ ] **Step 7: Build the Mac app**

Run: `macos/build.nu --configuration Debug --action build`
Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/Sessions/SessionSync.swift macos/Sources/Features/Sessions/TmuxClient.swift macos/Sources/Features/StayAwake/AttachedPhones.swift macos/Sources/Features/Claude/ClaudeRuntime.swift macos/Sources/Features/Terminal/BaseTerminalController.swift "macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift" macos/Sources/App/macOS/AppDelegate.swift macos/Tests/Sessions/SessionSyncTests.swift macos/Tests/Claude/ClaudeRuntimeTests.swift macos/Tests/StayAwake/AttachedPhonesTests.swift macos/Tests/Sessions/TmuxSessionTests.swift
git commit -m "lostty: Rename Tab names the session; phone names and attaches reach the Mac

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Menu bar Sessions list

**Files:**
- Modify: `macos/Sources/Features/MenuBar/StayAwakeMenuText.swift` (drop `ClaudeRow`/`claudeRows`, add `sessionLine`)
- Modify: `macos/Sources/Features/MenuBar/LosttyStatusItem.swift` (Claude block → Sessions block; `focusPane` → `openSession`)
- Modify: `macos/Tests/MenuBar/StayAwakeMenuTextTests.swift` (replace the two `claudeRows` tests)

**Interfaces:**
- Consumes: `SessionLabel.row(for:now:)`, `SessionLabel.ordered`, `SessionRow` (Task 1); `TmuxClient.remoteSessions()` (Task 3); `SessionsUI.open(_:ghostty:)`, `AppDelegate.ghostty`, `AppDelegate.findSurface(forUUID:)`, `ProcessLiveness.isAlive`.
- Produces: `StayAwakeMenuText.sessionLine(_ row: SessionRow) -> String`.

Decision: the menu has no "Sessions list" today; its "Claude" section lists Claude panes from `ClaudeRuntime`. This task replaces that section with "Sessions" (every session, same labels and order as the phone, "Not open on Mac" group last). Clicking one of this Lostty's sessions focuses its pane; clicking a session no running Lostty shows opens it in a new window; another running Lostty's (a Debug build's) session is shown disabled. Claude panes outside tmux (tmux turned off) no longer appear in the menu; the waiting dot on the icon is unchanged. The second line goes in `NSMenuItem.subtitle` on macOS 14.4+.

- [ ] **Step 1: Write the failing tests**

In `macos/Tests/MenuBar/StayAwakeMenuTextTests.swift`, add `import LosttyRemote` after `import Foundation`, and replace `claudeRowsWaitingFirstThenByTitle` and `untitledPanesAreCalledClaude` with:

```swift
    @Test func sessionLinesMarkWaitingAndWorking() {
        let waiting = SessionLabel.row(for: RemoteSession(
            id: "$1", name: "lostty", surface: "A", owner: 1, claude: .waiting,
            title: "✳ Fix login", command: "2.1.296"), now: now)
        #expect(StayAwakeMenuText.sessionLine(waiting) == "   ● Fix login — Waiting")
        let working = SessionLabel.row(for: RemoteSession(
            id: "$1", name: "lostty", surface: "A", owner: 1, claude: .working,
            title: "◐ Fix login", command: "2.1.296"), now: now)
        #expect(StayAwakeMenuText.sessionLine(working) == "   ○ Fix login — Working")
    }

    @Test func otherSessionsSayWhenTheyWereUsed() {
        let used = SessionLabel.row(for: RemoteSession(
            id: "$2", name: "notes-2", surface: nil, owner: nil, command: "zsh",
            activity: now.addingTimeInterval(-300)), now: now)
        #expect(StayAwakeMenuText.sessionLine(used) == "   notes — 5m ago")
        let unknown = SessionLabel.row(for: RemoteSession(id: "$3", name: "notes", surface: nil, owner: nil), now: now)
        #expect(StayAwakeMenuText.sessionLine(unknown) == "   notes")
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `macos/skins-test.sh StayAwakeMenuTextTests`
Expected: build FAILS, "type 'StayAwakeMenuText' has no member 'sessionLine'".

- [ ] **Step 3: Implement `sessionLine`**

In `StayAwakeMenuText.swift`, add `import LosttyRemote` after `import Foundation`, delete `struct ClaudeRow` and `claudeRows(phases:awaiting:title:)`, and add in their place:

```swift
    /// A Sessions row: "● task — Waiting", "○ task — Working", "project — 5m ago".
    static func sessionLine(_ row: SessionRow) -> String {
        let marker: String
        switch row.status {
        case .waiting: marker = "● "
        case .working: marker = "○ "
        case .lastUsed: marker = ""
        }
        let right = row.statusText.isEmpty ? "" : " — \(row.statusText)"
        return "   \(marker)\(row.title)\(right)"
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh StayAwakeMenuTextTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: The Sessions section in `LosttyStatusItem.swift`**

In `menuNeedsUpdate(_:)`, replace the block from `let rows = StayAwakeMenuText.claudeRows(` through its closing `}` (the `if !rows.isEmpty { … }` block) with:

```swift
        let sessions = TmuxClient().remoteSessions()
        if !sessions.isEmpty {
            let groups = SessionLabel.ordered(sessions)
            let now = Date()
            menu.addItem(.separator())
            menu.addItem(disabled("Sessions"))
            for session in groups.open { menu.addItem(sessionItem(session, now: now)) }
            if !groups.notOpen.isEmpty {
                menu.addItem(disabled("Not open on Mac"))
                for session in groups.notOpen { menu.addItem(sessionItem(session, now: now)) }
            }
        }
```

After `action(_:_:)`, add:

```swift
    private func sessionItem(_ session: RemoteSession, now: Date) -> NSMenuItem {
        let row = SessionLabel.row(for: session, now: now)
        let item = NSMenuItem(title: StayAwakeMenuText.sessionLine(row), action: #selector(openSession(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = session
        if #available(macOS 14.4, *) { item.subtitle = row.detail }
        // Another running Lostty (a Debug build) shows it: nothing to do here.
        if let owner = session.owner, owner != ProcessInfo.processInfo.processIdentifier, ProcessLiveness.isAlive(owner) {
            item.action = nil
        }
        return item
    }
```

Replace `focusPane(_:)` with:

```swift
    /// This Lostty's session: focus its pane. One no Lostty shows: open it.
    @objc private func openSession(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? RemoteSession,
              let delegate = NSApp.delegate as? AppDelegate
        else { return }
        if session.owner == ProcessInfo.processInfo.processIdentifier,
           let pane = session.surface.flatMap(UUID.init(uuidString:)),
           let surface = delegate.findSurface(forUUID: pane),
           let controller = surface.window?.windowController as? BaseTerminalController {
            NSApp.activate(ignoringOtherApps: true)
            surface.window?.makeKeyAndOrderFront(nil)
            controller.focusSurface(surface)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        SessionsUI.open(
            TmuxSession(id: session.id, name: session.name, surface: session.surface, owner: session.owner),
            ghostty: delegate.ghostty)
    }
```

- [ ] **Step 6: Build the Mac app and rerun the suite**

Run: `macos/build.nu --configuration Debug --action build`
Expected: build succeeds (no remaining reference to `claudeRows` or `focusPane`).
Run: `macos/skins-test.sh StayAwakeMenuTextTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/MenuBar/StayAwakeMenuText.swift macos/Sources/Features/MenuBar/LosttyStatusItem.swift macos/Tests/MenuBar/StayAwakeMenuTextTests.swift
git commit -m "lostty: menu bar lists sessions with the phone's labels and order

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Link status for the phone's overlay (shared)

**Files:**
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/AttachEnd.swift` (+ `RemoteLinkStatus`)
- Create: `macos/LosttyRemote/Sources/LosttyRemote/TerminalOverlay.swift`
- Modify: `macos/Sources/Features/Remote/RemoteSurfaceIO.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/TerminalOverlayTests.swift` (new); add to `macos/Tests/Remote/RemoteSurfaceIOTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `public enum RemoteLinkStatus: Equatable, Sendable { case attached, lost, exited(Int32), stopped }`
  - `public enum TerminalOverlay: Equatable, Sendable { case none, reconnecting(since: Date), closed(String); static let reconnectingText; static let backAfter: TimeInterval = 30; var message: String?; var isReconnecting: Bool; func offersBack(now: Date) -> Bool; func after(_: RemoteLinkStatus, now: Date) -> TerminalOverlay }`
  - `RemoteSurfaceIO.SurfaceCalls.status: @Sendable (RemoteLinkStatus) -> Void` (default no-op, main thread), `static func overlaid(status:) -> SurfaceCalls`
  - `RemoteSurfaceIO.init(attacher:surfaceCalls:delays:onMain:now:)` (`now` defaults to `{ Date() }`), `RemoteSurfaceIO.wroteRecently(within: TimeInterval) -> Bool`

Decisions: a failed connect (before or between attaches) reports `.lost` too, so a phone that can't reach the Mac on open shows the reconnecting overlay rather than a blank terminal. A `RemoteError` stop (host key changed, key refused) reports `.stopped`, which clears the reconnecting overlay so the red message in the terminal is readable. Only input that reached an open terminal counts as typing.

- [ ] **Step 1: Write the failing tests**

Create `macos/LosttyRemote/Tests/LosttyRemoteTests/TerminalOverlayTests.swift`:

```swift
import Foundation
import Testing
@testable import LosttyRemote

struct TerminalOverlayTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func aDropShowsReconnectingAndAReattachClearsIt() {
        let lost = TerminalOverlay.none.after(.lost, now: t0)
        #expect(lost == .reconnecting(since: t0))
        #expect(lost.message == "Connection lost — reconnecting…")
        #expect(lost.isReconnecting)
        // Another failed try keeps the original start, for the 30 s clock.
        #expect(lost.after(.lost, now: t0.addingTimeInterval(20)) == .reconnecting(since: t0))
        #expect(lost.after(.attached, now: t0.addingTimeInterval(21)) == .none)
    }

    @Test func backToSessionsAfterThirtySeconds() {
        let reconnecting = TerminalOverlay.reconnecting(since: t0)
        #expect(!reconnecting.offersBack(now: t0.addingTimeInterval(29)))
        #expect(reconnecting.offersBack(now: t0.addingTimeInterval(30)))
        #expect(TerminalOverlay.closed("Closed on your Mac").offersBack(now: t0))
        #expect(!TerminalOverlay.none.offersBack(now: t0))
    }

    @Test func aClosedOverlayStaysUntilTapped() {
        let closed = TerminalOverlay.closed("Closed on your Mac")
        #expect(closed.message == "Closed on your Mac")
        for status in [RemoteLinkStatus.attached, .lost, .stopped, .exited(0)] {
            #expect(closed.after(status, now: t0) == closed)
        }
    }

    @Test func givingUpWithAMessageClearsTheOverlaySoTheMessageShows() {
        #expect(TerminalOverlay.reconnecting(since: t0).after(.stopped, now: t0) == .none)
    }

    @Test func withoutAnOverlayOnlyADropChangesAnything() {
        #expect(TerminalOverlay.none.after(.attached, now: t0) == .none)
        #expect(TerminalOverlay.none.after(.exited(0), now: t0) == .none)
        #expect(TerminalOverlay.none.message == nil)
    }
}
```

In `macos/Tests/Remote/RemoteSurfaceIOTests.swift`, after `OnceFlag`, add:

```swift
private final class StatusLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [RemoteLinkStatus] = []
    var values: [RemoteLinkStatus] { lock.withLock { _values } }
    func add(_ s: RemoteLinkStatus) { lock.withLock { _values.append(s) } }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSince1970: 1_000)
    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now = _now.addingTimeInterval(seconds) } }
}
```

and add to `struct RemoteSurfaceIOTests`:

```swift
    @Test func statusFollowsTheConnection() async {
        struct Down: Error {}
        let log = SurfaceLog()
        let statuses = StatusLog()
        var calls = log.calls
        calls.status = { statuses.add($0) }
        let attacher = ScriptedAttacher([.failure(Down()), .success(.lost), .success(.exited(3))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(statuses.values == [.lost, .attached, .lost, .attached, .exited(3)])
        #expect(log.events == ["disconnected", "exited 3"])
    }

    @Test func aStopWithAMessageSaysStopped() async {
        let statuses = StatusLog()
        var calls = SurfaceLog().calls
        calls.status = { statuses.add($0) }
        let attacher = ScriptedAttacher([.failure(RemoteError.hostKeyChanged(host: "h", pinned: "A", offered: "B"))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(statuses.values == [.stopped])
    }

    @Test func thePhoneShowsNoLineAndKeepsThePaneOnExit() async {
        let log = SurfaceLog()
        let statuses = StatusLog()
        var calls = RemoteSurfaceIO.SurfaceCalls.overlaid(status: { statuses.add($0) })
        calls.feed = log.calls.feed
        let attacher = ScriptedAttacher([.success(.lost), .success(.exited(0))])
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        await io.finished()
        #expect(log.events.isEmpty, "no disconnected line, no exit to the core")
        #expect(log.fed == Data("hihi".utf8))
        #expect(statuses.values == [.attached, .lost, .attached, .exited(0)])
    }

    @Test func typingCountsAsRecentForThreeSeconds() async throws {
        let clock = TestClock()
        let statuses = StatusLog()
        var calls = SurfaceLog().calls
        calls.status = { statuses.add($0) }
        let attacher = HoldingAttacher()
        let io = RemoteSurfaceIO(
            attacher: attacher, surfaceCalls: calls, delays: { _ in }, onMain: { $0() },
            now: { clock.now })
        Data("x".utf8).withUnsafeBytes { io.write($0) }
        #expect(!io.wroteRecently(within: 3), "nothing was attached to send it to")
        io.attach(to: fakeSurface)
        // `.attached` is reported after the IO holds the terminal.
        try await waitUntil { statuses.values.contains(.attached) }
        Data("exit\r".utf8).withUnsafeBytes { io.write($0) }
        clock.advance(2)
        #expect(io.wroteRecently(within: 3))
        clock.advance(2)
        #expect(!io.wroteRecently(within: 3))
        io.detach()
        await io.finished()
    }

    @Test func noStatusAfterThePaneCloses() async throws {
        let statuses = StatusLog()
        var calls = SurfaceLog().calls
        calls.status = { statuses.add($0) }
        let attacher = GatedAttacher()
        let io = RemoteSurfaceIO(attacher: attacher, surfaceCalls: calls, delays: { _ in }, onMain: { $0() })
        io.attach(to: fakeSurface)
        try await waitUntil { attacher.isOpen }
        io.detach()
        attacher.release()
        await io.finished()
        #expect(statuses.values == [.attached])
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --package-path macos/LosttyRemote --filter TerminalOverlayTests`
Expected: build FAILS, "cannot find 'TerminalOverlay' in scope".

- [ ] **Step 3: Implement `RemoteLinkStatus` and `TerminalOverlay`**

Append to `AttachEnd.swift`:

```swift
/// What the screen showing a remote terminal hears about its connection.
public enum RemoteLinkStatus: Equatable, Sendable {
    /// Attached (again).
    case attached
    /// Dropped, or couldn't connect; reconnecting with backoff.
    case lost
    /// tmux exited: the session ended or this client was detached.
    case exited(Int32)
    /// Gave up with a message in the terminal (host key changed, key refused).
    case stopped
}
```

Create `TerminalOverlay.swift`:

```swift
import Foundation

/// What covers the phone's terminal: nothing, "reconnecting", or why the
/// session ended. A closed overlay stays until Back to Sessions.
public enum TerminalOverlay: Equatable, Sendable {
    case none
    case reconnecting(since: Date)
    case closed(String)

    public static let reconnectingText = "Connection lost — reconnecting…"
    /// Reconnecting this long also offers Back to Sessions.
    public static let backAfter: TimeInterval = 30

    public var message: String? {
        switch self {
        case .none: nil
        case .reconnecting: Self.reconnectingText
        case .closed(let reason): reason
        }
    }

    public var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }

    public func offersBack(now: Date) -> Bool {
        switch self {
        case .none: false
        case .reconnecting(let since): now.timeIntervalSince(since) >= Self.backAfter
        case .closed: true
        }
    }

    /// The overlay after a link event. `.exited` changes nothing here: the
    /// screen asks the Mac why, then shows `.closed` or leaves.
    public func after(_ status: RemoteLinkStatus, now: Date) -> TerminalOverlay {
        switch (self, status) {
        case (.closed, _): self
        case (.none, .lost): .reconnecting(since: now)
        case (.reconnecting, .attached), (.reconnecting, .stopped): .none
        default: self
        }
    }
}
```

- [ ] **Step 4: Run the package tests to verify they pass**

Run: `swift test --package-path macos/LosttyRemote --filter TerminalOverlayTests`
Expected: `✔ Test run with … tests passed`.

- [ ] **Step 5: Report status from `RemoteSurfaceIO.swift`**

Update the class comment's last two sentences to: `The session ending reports an exit (the Mac closes the pane; the phone's screen decides). Closing the pane closes only the channel.`

Replace the `SurfaceCalls` struct with:

```swift
    /// The surface calls this makes; tests replace them.
    struct SurfaceCalls: Sendable {
        var feed: @Sendable (ghostty_surface_t, Data) -> Void
        var disconnected: @Sendable (ghostty_surface_t) -> Void
        var exited: @Sendable (ghostty_surface_t, UInt32) -> Void
        /// Connection events for the screen showing the pane (the phone's
        /// overlay). On the main thread.
        var status: @Sendable (RemoteLinkStatus) -> Void = { _ in }

        static let live = SurfaceCalls(
            feed: { surface, data in
                data.withUnsafeBytes { raw in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                    ghostty_surface_io_feed(surface, base, raw.count)
                }
            },
            disconnected: { ghostty_surface_io_disconnected($0) },
            // Called on the main thread (see `reportExit`).
            exited: { ghostty_surface_io_exited($0, $1) })

        /// The phone: no "reconnecting…" line and no exit in the terminal.
        /// Its screen shows an overlay over the last screen instead, and
        /// decides when to close.
        static func overlaid(status: @escaping @Sendable (RemoteLinkStatus) -> Void) -> SurfaceCalls {
            SurfaceCalls(feed: live.feed, disconnected: { _ in }, exited: { _, _ in }, status: status)
        }
    }
```

After `private var delay: Task<Void, Error>?`, add:

```swift
    private let now: @Sendable () -> Date
    /// When input last reached an open terminal.
    private var lastWrite: Date?
```

Replace the `init` with:

```swift
    init(
        attacher: RemoteAttacher,
        surfaceCalls: SurfaceCalls = .live,
        delays: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        onMain: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.attacher = attacher
        self.calls = surfaceCalls
        self.delays = delays
        self.onMain = onMain
        self.now = now
    }
```

Replace `write(_:)` with:

```swift
    func write(_ bytes: UnsafeRawBufferPointer) {
        let data = Data(bytes)
        // Typing while not attached (connecting, reconnecting) is dropped.
        let open: RemoteTerminal? = stateLock.withLock {
            if terminal != nil { lastWrite = now() }
            return terminal
        }
        open?.write(data)
    }
```

After `finished()`, add:

```swift
    /// Whether input reached the session in the last `seconds`: the person
    /// typed `exit` (or Ctrl-D) rather than the session ending elsewhere.
    func wroteRecently(within seconds: TimeInterval) -> Bool {
        let last = stateLock.withLock { lastWrite }
        guard let last else { return false }
        return now().timeIntervalSince(last) <= seconds
    }
```

In `run()`, replace

```swift
                received(Data("\r\n\u{1b}[31m\(error.message)\u{1b}[0m\r\n".utf8))
                return
```

with

```swift
                received(Data("\r\n\u{1b}[31m\(error.message)\u{1b}[0m\r\n".utf8))
                report(.stopped)
                return
```

replace

```swift
                if takeRestart() { policy.reset(); continue }
                guard await pause(policy.nextDelay()) else { return }
                continue
            }
```

with

```swift
                if takeRestart() { policy.reset(); continue }
                report(.lost)
                guard await pause(policy.nextDelay()) else { return }
                continue
            }
```

and replace the `switch end { … }` with:

```swift
            switch end {
            case .exited(let code):
                reportExit(UInt32(bitPattern: code))
                report(.exited(code))
                return
            case .lost:
                // A connection that worked starts the backoff over.
                if stateLock.withLock({ didOpen }) { policy.reset() }
                withSurface { calls.disconnected($0) }
                report(.lost)
                guard await pause(policy.nextDelay()) else { return }
            }
```

After `reportExit(_:)`, add:

```swift
    /// Tells the screen, on the main thread, unless the pane has closed.
    private func report(_ status: RemoteLinkStatus) {
        onMain { [self] in
            guard !stateLock.withLock({ detached }) else { return }
            calls.status(status)
        }
    }
```

In `opened(_:)`, replace

```swift
        if !keep { terminal.close() }
```

with

```swift
        if !keep { terminal.close() } else { report(.attached) }
```

- [ ] **Step 6: Run the Mac suite to verify it passes**

Run: `macos/skins-test.sh RemoteSurfaceIOTests`
Expected: `** TEST SUCCEEDED **` (the existing tests unchanged: the default `status` is a no-op).

- [ ] **Step 7: Build both apps**

Run: `macos/build.nu --configuration Debug --action build`
Expected: build succeeds.
Run the iOS build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add macos/LosttyRemote/Sources/LosttyRemote/AttachEnd.swift macos/LosttyRemote/Sources/LosttyRemote/TerminalOverlay.swift macos/LosttyRemote/Tests/LosttyRemoteTests/TerminalOverlayTests.swift macos/Sources/Features/Remote/RemoteSurfaceIO.swift macos/Tests/Remote/RemoteSurfaceIOTests.swift
git commit -m "lostty: remote terminals report link status for the phone's overlay

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Phone live list, rows, sections and Rename

**Files:**
- Modify: `macos/Sources/App/iOS/MobileStore.swift`
- Modify (rewrite): `macos/Sources/App/iOS/SessionsScreen.swift`
- Modify: `macos/Sources/App/iOS/DesignGallery.swift` (`sessions`)

**Interfaces:**
- Consumes: `RemoteConnection.watchChanges()`, `setLabel(_:sessionID:name:)`, `ListPacing` (Task 2); `SessionLabel`, `SessionRow`, `SessionGroups` (Task 1); `ReconnectPolicy`, `DeviceModel.current`.
- Produces:
  - `MobileStore.listAppeared()`, `listDisappeared()`, `restartWatch()`, `rename(_ session: RemoteSession, to typed: String) async -> Bool`, `static let renameGoneMessage`
  - `struct RenameSessionAlert: ViewModifier` and `View.renameSession(_ session: Binding<RemoteSession?>, renamed: @escaping (String?) -> Void = { _ in }) -> some View` (in `SessionsScreen.swift`, used by Task 9)

Decisions: the watch owns its own connection; leaving the list (pushing a terminal) or backgrounding cancels it and closes that connection. A refused key or changed host key stops the watch (only pairing again fixes those); other failures retry with `ReconnectPolicy`. The store keeps the raw list and the screen orders it (`RemoteSession.forPicking` stays in the package, unused by the phone). Rename's failure copy (not in the spec): "Couldn't rename: that session has ended." Rows refresh their "5m ago" once a minute. Close stays on every row's swipe (the spec mentions it for the bottom section; nothing says to remove it from the others).

- [ ] **Step 1: Live watch and rename in `MobileStore.swift`**

In `refresh()`, replace

```swift
            sessions = RemoteSession.forPicking(try await connection.sessions())
```

with

```swift
            sessions = try await connection.sessions()
```

In `runPairingTest(attempt:)`, replace `sessions = RemoteSession.forPicking(found)` with `sessions = found`.

After `kill(_:)`, add:

```swift
    static let renameGoneMessage = "Couldn't rename: that session has ended."

    /// Names `session` on the Mac (blank: back to the automatic name); the
    /// Mac tab shows it too. False (with `message` set) when it failed.
    @discardableResult
    func rename(_ session: RemoteSession, to typed: String) async -> Bool {
        #if DEBUG
        if isGallery { return false }
        #endif
        let hosts = settings.remoteHosts
        guard !hosts.isEmpty else { return false }
        let label = SessionLabel.cleanLabel(typed)
        do {
            let connection = try await RemoteConnection.connect(toFirstReachable: hosts, key: try remoteKey(), knownHosts: knownHosts)
            let renamed: Bool
            do {
                renamed = try await connection.setLabel(label, sessionID: session.id, name: session.name)
            } catch {
                await connection.close()
                throw error
            }
            await connection.close()
            guard renamed else {
                message = Self.renameGoneMessage
                return false
            }
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index].label = label }
            return true
        } catch {
            message = describe(error)
            noteNeedsPairing(error)
            return false
        }
    }
```

Before `// MARK: Pairing`, add:

```swift
    // MARK: Live list

    /// The list is on screen; with the app active, one connection watches
    /// tmux and re-lists on every change.
    private var listVisible = false
    private var appActive = true
    private var watchTask: Task<Void, Never>?

    func listAppeared() {
        listVisible = true
        updateWatch()
    }

    func listDisappeared() {
        listVisible = false
        updateWatch()
    }

    /// Settings or pairing may have changed the Mac: watch the current one.
    func restartWatch() {
        watchTask?.cancel()
        watchTask = nil
        updateWatch()
    }

    private func updateWatch() {
        #if DEBUG
        if isGallery { return }
        #endif
        let wanted = listVisible && appActive && !settings.remoteHosts.isEmpty
        if wanted, watchTask == nil {
            watchTask = Task { [weak self] in await self?.watchLoop() }
        } else if !wanted, let task = watchTask {
            task.cancel()
            watchTask = nil
        }
    }

    private func watchLoop() async {
        var policy = ReconnectPolicy()
        while !Task.isCancelled {
            let hosts = settings.remoteHosts
            guard !hosts.isEmpty else { break }
            if sessions.isEmpty { loading = true }
            do {
                let connection = try await RemoteConnection.connect(toFirstReachable: hosts, key: try remoteKey(), knownHosts: knownHosts)
                // Leaving the list cancels this task; closing the connection
                // is what ends the watch's channel.
                let listed = await withTaskCancellationHandler {
                    await watch(on: connection)
                } onCancel: {
                    Task { await connection.close() }
                }
                await connection.close()
                if listed { policy.reset() }
            } catch {
                loading = false
                if Task.isCancelled { break }
                message = describe(error)
                noteNeedsPairing(error)
                // Only pairing again fixes these; don't keep knocking.
                if needsPairing { break }
            }
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(policy.nextDelay()))
        }
        if !Task.isCancelled { watchTask = nil }
    }

    /// Lists, then lists again after each change (at most every 300 ms)
    /// until the watch ends: no tmux server, or the connection dropped.
    /// True when the first list worked.
    private func watch(on connection: RemoteConnection) async -> Bool {
        var lastList = Date.distantPast
        func relist() async throws {
            let found = try await connection.sessions()
            lastList = Date()
            show(found)
        }
        do {
            try await relist()
        } catch {
            loading = false
            if !Task.isCancelled { message = describe(error) }
            return false
        }
        do {
            let changes = try await connection.watchChanges()
            for await _ in changes {
                let wait = ListPacing.delay(sinceLastList: lastList, now: Date())
                if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
                try await relist()
            }
        } catch {
            // The watch ended: cancelled, or the connection dropped.
        }
        // One more look, so a server that went away shows the empty state.
        if !Task.isCancelled { try? await relist() }
        return true
    }

    private func show(_ found: [RemoteSession]) {
        sessions = found
        loading = false
        message = found.isEmpty ? Self.noSessionsMessage : nil
        needsPairing = false
    }
```

In `scenePhaseChanged(_:)`, replace the `.active` and `.background` cases with:

```swift
        case .active:
            appActive = true
            updateWatch()
            // .inactive -> .active also happens for the Face ID sheet and
            // Control Center; only a real trip to the background restarts.
            if wasBackgrounded {
                wasBackgrounded = false
                openIO?.restart()
            }
        case .background:
            wasBackgrounded = true
            appActive = false
            updateWatch()
            // Face ID again after the app has been away.
            context.invalidate()
            context = LAContext()
            key = nil
```

- [ ] **Step 2: Rewrite `SessionsScreen.swift`**

```swift
#if os(iOS)
import GhosttyKit
import LosttyRemote
import SwiftUI

/// Home: the Mac's Lostty sessions, kept current while on screen; the
/// welcome screen while no Mac is set up.
struct SessionsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var ghostty: Ghostty.App
    @State private var path: [String] = []
    @State private var open: (session: RemoteSession, view: Ghostty.SurfaceView, io: RemoteSurfaceIO)?
    @State private var showSettings = false
    @State private var showPairing = false
    @State private var confirmKill: RemoteSession?
    @State private var renaming: RemoteSession?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.settings.remoteHost == nil {
                    WelcomeScreen(pair: { showPairing = true }, settings: { showSettings = true })
                } else {
                    sessionList
                }
            }
            .navigationTitle("Lostty")
            .losttyScreen()
            .toolbar {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").foregroundStyle(LosttyTheme.textSecondary)
                }
            }
            .navigationDestination(for: String.self) { _ in
                if let open {
                    TerminalScreen(session: open.session, surfaceView: open.view, io: open.io)
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { store.restartWatch() }) {
                NavigationStack { SettingsScreen() }
            }
            .sheet(isPresented: $showPairing, onDismiss: { store.restartWatch() }) {
                NavigationStack { PairingScreen() }
            }
            .confirmationDialog(
                "Close \(confirmKill.map { SessionLabel.row(for: $0, now: Date()).title } ?? "")?",
                isPresented: Binding(get: { confirmKill != nil }, set: { if !$0 { confirmKill = nil } }),
                titleVisibility: .visible,
                presenting: confirmKill
            ) { session in
                Button("Close Session", role: .destructive) {
                    Task { await store.kill(session) }
                }
            } message: { _ in
                Text("This ends the session on the Mac and closes its window there.")
            }
            .renameSession($renaming)
            .onAppear {
                if path.isEmpty { store.listAppeared() }
                if store.pendingPairingLink != nil { showPairing = true }
            }
            .onChange(of: store.pendingPairingLink) { _, link in if link != nil { showPairing = true } }
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty {
                    // Back from the terminal: drop it; the live list resumes.
                    open = nil
                    store.listAppeared()
                } else {
                    store.listDisappeared()
                }
            }
        }
    }

    private var sessionList: some View {
        // Once a minute, so "5m ago" stays true.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let groups = SessionLabel.ordered(store.sessions)
            List {
                if let message = store.message, !showsEmptyState {
                    LosttyCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message).font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                            if store.needsPairing {
                                Button("Pair Again") { showPairing = true }.buttonStyle(.lostty(.primary))
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: LosttyTheme.margin, bottom: 6, trailing: LosttyTheme.margin))
                }
                ForEach(groups.open, id: \.id) { session in
                    row(session, now: context.date)
                }
                if !groups.notOpen.isEmpty {
                    Section {
                        ForEach(groups.notOpen, id: \.id) { session in
                            row(session, now: context.date).opacity(0.55)
                        }
                    } header: {
                        Text("Not open on Mac")
                            .font(LosttyFont.detail)
                            .foregroundStyle(LosttyTheme.textSecondary)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if showsEmptyState {
                    // Let pulls reach the list underneath (pull to refresh).
                    EmptySessions().allowsHitTesting(false)
                } else if store.loading && store.sessions.isEmpty {
                    ProgressView().tint(LosttyTheme.accent)
                }
            }
            .refreshable { await store.refresh() }
        }
    }

    private func row(_ session: RemoteSession, now: Date) -> some View {
        Button {
            guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else { return }
            open = (session, terminal.view, terminal.io)
            path = ["terminal"]
        } label: {
            SessionRowView(row: SessionLabel.row(for: session, now: now))
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: LosttyTheme.margin, bottom: 6, trailing: LosttyTheme.margin))
        .swipeActions {
            Button("Close", role: .destructive) { confirmKill = session }
            Button("Rename") { renaming = session }.tint(LosttyTheme.accent)
        }
    }

    /// No sessions and nothing else to say: the friendly empty state.
    private var showsEmptyState: Bool {
        store.sessions.isEmpty && !store.loading && store.message == MobileStore.noSessionsMessage
    }
}

/// One session: what it is, its project and kind, and Waiting/Working or
/// when it was last used.
private struct SessionRowView: View {
    let row: SessionRow

    var body: some View {
        LosttyCard(padding: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(LosttyFont.bodyEmphasis)
                        .foregroundStyle(LosttyTheme.textPrimary)
                        .lineLimit(1)
                    Text(row.detail)
                        .font(LosttyFont.mono(.footnote, size: 13))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if !row.statusText.isEmpty {
                    Text(row.statusText)
                        .font(row.status == .waiting ? LosttyFont.bodyEmphasis : LosttyFont.detail)
                        .foregroundStyle(row.status == .waiting ? LosttyTheme.accent : LosttyTheme.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LosttyTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rename: one name everywhere (the Mac tab shows it too); blank goes back
/// to the automatic name.
struct RenameSessionAlert: ViewModifier {
    @Binding var session: RemoteSession?
    var renamed: (String?) -> Void
    @EnvironmentObject private var store: MobileStore
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(
                "Rename",
                isPresented: Binding(get: { session != nil }, set: { if !$0 { session = nil } }),
                presenting: session
            ) { target in
                TextField("Name", text: $text)
                Button("Save") {
                    let typed = text
                    Task {
                        if await store.rename(target, to: typed) { renamed(SessionLabel.cleanLabel(typed)) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Leave blank to use the automatic name.")
            }
            .onChange(of: session?.id) { _, id in
                if id != nil { text = session?.label ?? "" }
            }
    }
}

extension View {
    func renameSession(_ session: Binding<RemoteSession?>, renamed: @escaping (String?) -> Void = { _ in }) -> some View {
        modifier(RenameSessionAlert(session: session, renamed: renamed))
    }
}

private struct EmptySessions: View {
    var body: some View {
        VStack(spacing: 10) {
            Axolotl(pose: .resting).frame(width: 104, height: 104).losttyGlow(diameter: 260)
                .padding(.bottom, 6)
            Text("Nothing running yet")
                .font(LosttyFont.bodyEmphasis)
                .foregroundStyle(LosttyTheme.textPrimary)
            Text("Open Lostty on your Mac.")
                .font(LosttyFont.detail)
                .foregroundStyle(LosttyTheme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(LosttyTheme.margin)
    }
}
#endif
```

- [ ] **Step 3: Gallery samples that show the new rows**

In `DesignGallery.swift`, replace the `sessions` array with:

```swift
    private static let sessions = [
        RemoteSession(
            id: "$1", name: "lostty", surface: "A", owner: 1, claude: .waiting,
            title: "✳ Lostty UI redesign plan", path: "/Users/alex/projectrepos/lostty",
            command: "2.1.296", activity: Date().addingTimeInterval(-120)),
        RemoteSession(
            id: "$3", name: "home", surface: "B", owner: 1, label: "Deploy watch",
            title: "~", path: "/Users/alex", command: "zsh", activity: Date().addingTimeInterval(-300)),
        RemoteSession(
            id: "$4", name: "lostty-2", surface: "C", owner: 1, claude: .working,
            title: "◐ Fix the login bug", path: "/Users/alex/projectrepos/lostty/.claude/worktrees/stay-awake",
            command: "2.1.296", activity: Date().addingTimeInterval(-10)),
        RemoteSession(
            id: "$2", name: "ghostty-skins-experiments-with-a-very-long-name", surface: nil, owner: nil,
            title: "~/projectrepos/ghostty-skins-experiments-with-a-very-long-name", command: "zsh",
            activity: Date().addingTimeInterval(-3 * 86400)),
    ]
```

and rename the two entries `"Three sessions"` / `"Three sessions — large text"` to `"Sessions"` / `"Sessions — large text"`.

- [ ] **Step 4: Build the iOS app**

Run the iOS build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Package tests still pass**

Run: `swift test --package-path macos/LosttyRemote`
Expected: `✔ Test run with … tests passed`.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/App/iOS/MobileStore.swift macos/Sources/App/iOS/SessionsScreen.swift macos/Sources/App/iOS/DesignGallery.swift
git commit -m "lostty: phone session list is live, labelled and sectioned, with Rename

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Phone terminal overlay for closed sessions and lost connections

**Files:**
- Modify (rewrite): `macos/Sources/App/iOS/TerminalScreen.swift`
- Modify: `macos/Sources/App/iOS/MobileStore.swift` (`terminal(for:app:)`, + `endProbe(_:)`)
- Modify: `macos/Sources/App/iOS/SessionsScreen.swift` (`open` tuple, `TerminalScreen(…)`, row button)

**Interfaces:**
- Consumes: `RemoteLinkStatus`, `TerminalOverlay`, `RemoteSurfaceIO.SurfaceCalls.overlaid(status:)`, `RemoteSurfaceIO.wroteRecently(within:)` (Task 7); `SessionEnd`, `EndProbe`, `RemoteConnection.endProbe` (Task 2); `SessionLabel` (Task 1); `View.renameSession` (Task 8).
- Produces:
  - `@MainActor final class TerminalLink { let events: PassthroughSubject<RemoteLinkStatus, Never> }`
  - `MobileStore.terminal(for:app:) -> (view: Ghostty.SurfaceView, io: RemoteSurfaceIO, link: TerminalLink)?`
  - `MobileStore.endProbe(_ session: RemoteSession) async -> EndProbe?`
  - `TerminalScreen(session:surfaceView:io:link:)`

Decisions: the phone never reports exit to the core, so the last screen stays to dim under the overlay. An attach that ends while the app isn't active waits for the app to become active before asking the Mac why (the key and Face ID need the foreground); the overlay then shows on return. A reattach on return that finds the session gone arrives as `.exited(1)` from the name guard and takes the same path. When the overlay clears after a reconnect, the keyboard comes back.

- [ ] **Step 1: Link and end probe in `MobileStore.swift`**

Replace `terminal(for:app:)` with:

```swift
    /// A terminal view attached to `session`, with its IO and its link
    /// events; nil (with a message) when the settings or key aren't ready.
    func terminal(for session: RemoteSession, app: ghostty_app_t) -> (view: Ghostty.SurfaceView, io: RemoteSurfaceIO, link: TerminalLink)? {
        #if DEBUG
        if isGallery { return nil }
        #endif
        let hosts = settings.remoteHosts
        guard !hosts.isEmpty else {
            message = settings.problem
            return nil
        }
        do {
            _ = try remoteKey()  // surface a key problem now, not after the screen opens
            let link = TerminalLink()
            let io = RemoteSurfaceIO(
                attacher: SSHAttacher(
                    hosts: hosts,
                    key: { [weak self] in
                        guard let self else { throw CancellationError() }
                        return try await self.remoteKey()
                    },
                    knownHosts: knownHosts,
                    sessionID: session.id,
                    sessionName: session.name),
                surfaceCalls: .overlaid { status in
                    MainActor.assumeIsolated { link.events.send(status) }
                })
            var config = Ghostty.SurfaceConfiguration()
            config.remoteIO = io
            openIO = io
            return (Ghostty.SurfaceView(app, baseConfig: config), io, link)
        } catch {
            message = describe(error)
            return nil
        }
    }

    /// Why `session` ended, read from the Mac: its end tag and whether it
    /// is still there. nil when that can't be read.
    func endProbe(_ session: RemoteSession) async -> EndProbe? {
        #if DEBUG
        if isGallery { return nil }
        #endif
        let hosts = settings.remoteHosts
        guard !hosts.isEmpty else { return nil }
        do {
            let connection = try await RemoteConnection.connect(toFirstReachable: hosts, key: try remoteKey(), knownHosts: knownHosts)
            let probe = try? await connection.endProbe(session.id)
            await connection.close()
            return probe
        } catch {
            return nil
        }
    }
```

- [ ] **Step 2: Rewrite `TerminalScreen.swift`**

```swift
#if os(iOS)
import Combine
import GhosttyKit
import LosttyRemote
import SwiftUI

/// The open terminal's connection events, from its `RemoteSurfaceIO`
/// (delivered on the main thread).
@MainActor
final class TerminalLink {
    let events = PassthroughSubject<RemoteLinkStatus, Never>()
}

/// One remote session. Back closes only the connection; "Close Session"
/// ends the session (and its Mac window) after asking. When the session
/// ends from elsewhere, or the connection drops, an overlay over the dimmed
/// last screen says so.
struct TerminalScreen: View {
    let surfaceView: Ghostty.SurfaceView
    let io: RemoteSurfaceIO
    let link: TerminalLink
    @State private var session: RemoteSession
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmClose = false
    @State private var closeError: String?
    @State private var overlay: TerminalOverlay = .none
    /// Close Session from this screen is under way: its end is ours.
    @State private var closingHere = false
    /// The attach ended while the app was away: explain it on return.
    /// The value is whether input had just been sent.
    @State private var endWhileAway: Bool?
    @State private var renaming: RemoteSession?

    init(session: RemoteSession, surfaceView: Ghostty.SurfaceView, io: RemoteSurfaceIO, link: TerminalLink) {
        _session = State(initialValue: session)
        self.surfaceView = surfaceView
        self.io = io
        self.link = link
    }

    private var title: String { SessionLabel.row(for: session, now: Date()).title }

    var body: some View {
        GeometryReader { geo in
            Ghostty.SurfaceRepresentable(view: surfaceView, size: geo.size)
        }
        .opacity(overlay == .none ? 1 : 0.35)
        .allowsHitTesting(overlay == .none)
        .overlay {
            if overlay != .none {
                TerminalOverlayCard(overlay: overlay, title: title) { dismiss() }
                    .transition(.opacity)
            }
        }
        .animation(LosttyTheme.motion, value: overlay)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .losttyScreen()
        .toolbar {
            ToolbarItem(placement: .principal) { TerminalTitle(name: title) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename") { renaming = session }
                    Button("Close Session", role: .destructive) { confirmClose = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Close \(title)?", isPresented: $confirmClose, titleVisibility: .visible
        ) {
            Button("Close Session", role: .destructive) {
                closingHere = true
                Task {
                    if await store.kill(session) {
                        dismiss()
                    } else {
                        closingHere = false
                        closeError = store.message ?? "Couldn't close the session."
                    }
                }
            }
        } message: {
            Text("This ends the session on the Mac and closes its window there.")
        }
        .alert("Couldn't Close Session", isPresented: Binding(get: { closeError != nil }, set: { if !$0 { closeError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(closeError ?? "")
        }
        .renameSession($renaming) { label in session.label = label }
        .onAppear { surfaceView.showKeyboard() }
        .onDisappear { store.terminalClosed(io) }
        .onReceive(link.events) { handle($0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let typed = endWhileAway {
                endWhileAway = nil
                explainEnd(typedRecently: typed)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .losttySurfaceClosed)) { note in
            if (note.object as AnyObject?) === surfaceView {
                dismiss()
                Task { await store.terminalClosedItself(session) }
            }
        }
    }

    private func handle(_ status: RemoteLinkStatus) {
        if case .exited = status {
            guard !closingHere else { return }
            let typed = io.wroteRecently(within: SessionEnd.typedWindow)
            if scenePhase == .active {
                explainEnd(typedRecently: typed)
            } else {
                endWhileAway = typed
            }
            return
        }
        let next = overlay.after(status, now: Date())
        guard next != overlay else { return }
        let wasShowing = overlay != .none
        overlay = next
        if next == .none, wasShowing {
            surfaceView.showKeyboard()
        } else if next != .none {
            _ = surfaceView.resignFirstResponder()
        }
    }

    /// Asks the Mac why the session ended, then goes back to the list or
    /// says why over the dimmed screen.
    private func explainEnd(typedRecently: Bool) {
        Task {
            let probe = await store.endProbe(session)
            switch SessionEnd.decide(probe: probe, endedHere: closingHere, typedRecently: typedRecently) {
            case .backToList:
                dismiss()
            case .stillRunning:
                dismiss()
                await store.terminalClosedItself(session)
            case .closed(let reason):
                overlay = .closed(reason)
                _ = surfaceView.resignFirstResponder()
            }
        }
    }
}

/// The card over a dimmed terminal: why, which session, and (when closed,
/// or after 30 s of reconnecting) Back to Sessions.
private struct TerminalOverlayCard: View {
    let overlay: TerminalOverlay
    let title: String
    let back: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            LosttyCard(padding: 20) {
                VStack(spacing: 12) {
                    if overlay.isReconnecting {
                        ProgressView().tint(LosttyTheme.accent)
                    }
                    Text(overlay.message ?? "")
                        .font(LosttyFont.bodyEmphasis)
                        .foregroundStyle(LosttyTheme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(title)
                        .font(LosttyFont.mono(.footnote, size: 13))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if overlay.offersBack(now: context.date) {
                        Button("Back to Sessions", action: back)
                            .buttonStyle(.lostty(.primary, fullWidth: true))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 340)
            .padding(LosttyTheme.margin)
        }
    }
}

/// The session's name in the terminal's top bar.
struct TerminalTitle: View {
    var name: String
    var body: some View {
        Text(name)
            .font(LosttyFont.mono(.headline, weight: .semibold))
            .foregroundStyle(LosttyTheme.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
#endif
```

- [ ] **Step 3: Pass the link from `SessionsScreen.swift`**

Replace

```swift
    @State private var open: (session: RemoteSession, view: Ghostty.SurfaceView, io: RemoteSurfaceIO)?
```

with

```swift
    @State private var open: (session: RemoteSession, view: Ghostty.SurfaceView, io: RemoteSurfaceIO, link: TerminalLink)?
```

replace

```swift
                    TerminalScreen(session: open.session, surfaceView: open.view, io: open.io)
```

with

```swift
                    TerminalScreen(session: open.session, surfaceView: open.view, io: open.io, link: open.link)
```

and in `row(_:now:)` replace

```swift
            open = (session, terminal.view, terminal.io)
```

with

```swift
            open = (session, terminal.view, terminal.io, terminal.link)
```

- [ ] **Step 4: Build the iOS app**

Run the iOS build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Mac still builds; shared tests still pass**

Run: `macos/build.nu --configuration Debug --action build`
Expected: build succeeds.
Run: `macos/skins-test.sh RemoteSurfaceIOTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/App/iOS/TerminalScreen.swift macos/Sources/App/iOS/MobileStore.swift macos/Sources/App/iOS/SessionsScreen.swift
git commit -m "lostty: phone terminal says why a session closed and when the connection drops

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Docs and desk checks (needs the human)

**Files:**
- Modify: `docs/lostty-mobile-phone-access.md`

- [ ] **Step 1: Using the phone**

In `docs/lostty-mobile-phone-access.md`, insert before `## Lost phone`:

```markdown
## Using it

Lostty on your phone lists your Mac's sessions and keeps the list current
while it's open. Each row says what's running:

- A Claude Code session shows its task ("Lostty UI redesign plan"), with
  **Waiting** when it's waiting for you or **Working** while it works.
  Waiting sessions come first. Opening one on the phone counts as seeing
  it, on the Mac too.
- Other sessions show their project. A session in `.claude/worktrees/<name>`
  shows as `<repo>/<name>`.
- Sessions no Mac window shows are under **Not open on Mac**.
- Swipe left on a row → **Rename** (or ⋯ → **Rename** in a terminal) to name
  a session. It's the same name as **Rename Tab…** on the Mac; leave it blank
  to go back to the automatic name.

If a session ends while you're in it, the terminal dims and says why
(closed on your Mac, Lostty quit on your Mac, closed from another phone, or
the shell exited) until you tap **Back to Sessions**. Typing `exit` yourself
goes straight back to the list. A dropped connection shows **Connection
lost — reconnecting…** and clears itself when the phone is back.

The Mac's menu bar icon lists the same sessions, with the same names and
order.
```

Add to `## Troubleshooting`:

```markdown
- **Rows show only folder names and never "Waiting"**: the Mac's Lostty is
  older than the phone app. Update Lostty on the Mac.
```

- [ ] **Step 2: Commit docs**

```bash
git add docs/lostty-mobile-phone-access.md
git commit -m "lostty: document the phone's live session list, names and close reasons

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Desk checks (human, MacBook + iPhone)**

Build and run the Debug Mac app (`macos/build.nu --configuration Debug --action build`, then open `macos/build/Debug/Ghostty.app`) and install the iOS app on the phone. Run the spec's checklist and note each result:

1. Phone list open; close a Mac tab → its row disappears within ~1 s.
2. Open a Mac tab → a row appears.
3. Attached on the phone; close that tab on the Mac → overlay "Closed on your Mac" over the dimmed screen; Back to Sessions returns to the list.
4. Quit Lostty on the Mac while attached → "Lostty quit on your Mac".
5. Type `exit` on the phone → straight back to the list.
6. Background the phone app, close the tab on the Mac, return → overlay.
7. Turn the phone's Wi-Fi off and on while attached → "Connection lost — reconnecting…", then it clears.
8. A Claude waiting on the Mac shows "Waiting" first in the list; attaching from the phone clears it and the menu bar dot.
9. Rename on the phone → the Mac tab shows it when focused; Rename Tab… on the Mac → the phone row shows it; clearing restores the automatic label.
10. A Claude in `.claude/worktrees/stay-awake` reads `lostty/stay-awake`.

Also check: with Lostty quit and no tmux server, the phone list shows the empty state and recovers by itself when Lostty opens (watch retry), and the Mac's `tmux -L lostty show-hooks -g` lists the five `wait-for -S lostty-changed` hooks after Lostty starts.

Any failure: use superpowers:systematic-debugging, fix in the owning task's files, rerun that task's tests, and commit with a message naming the check.
