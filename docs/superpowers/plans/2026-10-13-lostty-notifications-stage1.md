# Lostty Notifications (Stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Mac keeps a list of notes (a terminal waiting on you, a new build to install); the phone shows them in an inbox under 👋 with an unread badge, styled like the terminal each came from, and lets you pick per kind Off / Wave / Wave + Push (push itself is stage 2).

**Architecture:** One shared model (`NoteLog`, in the `LosttyRemote` package) holds every rule. The Mac app is the only writer of `~/Library/Application Support/Lostty/notifications/notes.json`; it builds waiting notes from the same tmux listing the phone reads, and applies small "drop" files that the phone and the ship scripts leave in `notifications/inbox/`. After each change it signals tmux's `lostty-changed` channel, so the phone's existing watch re-lists and reads the notes with one more SSH command.

**Tech Stack:** Swift 5.9+, SwiftUI (iOS 17), Swift Testing, Citadel SSH (already used), POSIX `flock` and `DispatchSource` on the Mac, POSIX sh + `python3 -I` in the ship scripts.

**Spec:** `docs/superpowers/specs/2026-10-13-lostty-notifications-design.md`

## Global Constraints

- Another Claude session edits this same working tree (notably `SessionsScreen.swift`, `MobileStore.swift`, `DesignGallery.swift`). Re-read a file right before editing it, anchor edits on the quoted text (never on line numbers), and never revert changes you didn't make.
- No commits and no branch switches during this plan: the tree holds the other session's uncommitted work. The user commits.
- Kinds in v1: `waiting` ("Waiting on You") and `build` ("New Builds"). Delivery per kind: `off`, `wave`, `push` shown as "Off", "Wave", "Wave + Push". Default `wave`. `push` is not selectable in stage 1 and says "Push isn't set up yet".
- Notes folder on the Mac: `~/Library/Application Support/Lostty/notifications/` with `notes.json`, `phones.json`, `.lock`, `inbox/`.
- Drop file names: `<type>-<UUID>.json`; written as `.<name>` then renamed, so a name starting with "." is unfinished.
- Keeping: read notes go 7 days after their last update; at most 100 notes, oldest read first.
- Waiting note text: title = the row's title (`SessionLabel.row(for:now:).title`), body = Claude's question (`RemoteSession.action`), or "Waiting on you" when there is none.
- Build note text: title "<app> is ready to install", body "Build <build> · <branch> · <terminal title, else project>".
- Mac code under `macos/Sources/Features/PhoneNotes/` (not `Features/Notifications/`, which is the Mac's own desktop notifications). Mac files wrapped in `#if os(macOS)`, phone files in `#if os(iOS)` (the Xcode project's synchronized `Sources` folder feeds both targets).
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), as the existing suites do.
- Commands: shared package `cd macos/LosttyRemote && swift test --filter <Suite>`; one Mac suite `macos/skins-test.sh <Suite>`; Mac build `macos/build.nu`; phone build via XcodeBuildMCP `build_sim` (scheme `Lostty-iOS`, simulator "Lostty iPhone"). `swiftlint` isn't installed on this Mac; skip it.

## Review Focus

1. **A note you deleted while its terminal still waits** must not come back on the next listing; only the terminal's next waiting episode brings it back. Pinned in Task 1 (`aDeletedNoteStaysGoneUntilTheNextEpisode`).
2. **Restarting the Mac app while terminals wait** must not repeat or revive notes. Pinned in Task 1 (`aRestartDoesNotRepeatNotes`).
3. **Claude's question or a terminal title containing quotes, `$` or newlines** must reach the Mac byte for byte through the phone's shell command. Pinned in Task 2 (`aDropSurvivesTheShellByteForByte`).
4. **A half-written or malformed drop file** must never be applied in part; unfinished (".") files are left for later, malformed ones deleted. Pinned in Task 3 (`drainSkipsUnfinishedAndDropsMalformed`).
5. **Debug and release Lostty running at once** (they share the tmux server) must not both keep notes. Pinned in Task 3 (`onlyOneKeeperHoldsTheLock`).

---

## File Structure

| File | Responsibility |
|---|---|
| Create `macos/LosttyRemote/Sources/LosttyRemote/Notes.swift` | `LosttyNote`, `NoteBuild`, `NoteLog` (all rules), `NoteDrop` (drop files and their JSON), `NoteDelivery`, `NoteSettings`, `PhoneNoteSettings` |
| Create `macos/LosttyRemote/Sources/LosttyRemote/NotesRemote.swift` | The shell commands the phone runs on the Mac: read notes, leave a drop |
| Modify `macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift` | `notes()` and `drop(_:)` on the connection |
| Create `macos/LosttyRemote/Tests/LosttyRemoteTests/NotesTests.swift`, `NotesRemoteTests.swift` | Tests for the above |
| Create `macos/Sources/Features/PhoneNotes/NotesFolder.swift` | The folder on disk: load, save, drain the inbox, the keeper lock |
| Create `macos/Sources/Features/PhoneNotes/NotesKeeper.swift` | The Mac app's keeper: lock, watch the inbox, re-sync on session changes, save and signal |
| Modify `macos/Sources/App/macOS/AppDelegate.swift` | Start the keeper with the other Lostty Mobile services |
| Create `macos/Tests/PhoneNotes/NotesFolderTests.swift` | Tests for `NotesFolder` |
| Modify `macos/Sources/App/iOS/MobileStore.swift` | `notes`, `noteSettings` stored properties; read notes on each listing; widen two members to internal |
| Create `macos/Sources/App/iOS/MobileStore+Notes.swift` | Phone-side notes actions: read, delete, mark all, settings, build report |
| Create `macos/Sources/App/iOS/NotificationsInbox.swift` | The inbox sheet, its rows, the badge |
| Modify `macos/Sources/App/iOS/SessionsScreen.swift` | 👋 opens the inbox, shows the badge; `openTerminal(_:)`; `RowColors` internal |
| Create `macos/Sources/App/iOS/NotificationSettingsScreen.swift` | Settings → Notifications |
| Modify `macos/Sources/App/iOS/SettingsScreen.swift` | A "Notifications" row above Terminal Text Size |
| Modify `macos/Sources/App/iOS/DesignGallery.swift` | Gallery entries for the inbox and the settings page |
| Modify `macos/ship-phone.sh` | Leave a build note unless the cable install worked |
| Modify `~/.claude/skills/install-ios-build/ship-ios.sh` (outside the repo) | Leave a build note on its Tailscale path |

---

### Task 1: The shared notes model

**Files:**
- Create: `macos/LosttyRemote/Sources/LosttyRemote/Notes.swift`
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/NotesTests.swift`

**Interfaces:**
- Consumes: `RemoteSession` (`TmuxRemote.swift`), `ClaudeActivity.waiting`, `SessionLabel.row(for:now:)`, `SessionLabel.cleanTitle(_:)`, `SessionSkin(encoded:)` / `.encoded`.
- Produces:
  - `struct LosttyNote: Codable, Equatable, Sendable, Identifiable` with `id: UUID`, `kind: Kind` (`.waiting`, `.build`; `CaseIterable`), `created: Date`, `updated: Date`, `read: Bool`, `title: String`, `body: String`, `sessionID: String?`, `skin: String?`, `build: NoteBuild?`.
  - `struct NoteBuild: Codable, Equatable, Sendable` with `app, bundleID, build, commit, branch, project, installURL: String`.
  - `struct NoteLog: Codable, Equatable, Sendable`: `notes: [LosttyNote]` (newest first, read-only), `waiting: Set<String>`, `init(notes:waiting:)`, `unreadCount: Int`, `unreadCount(showing: Set<LosttyNote.Kind>) -> Int`, `mutating sync(sessions:now:newID:) -> Bool`, `mutating apply(_:now:newID:) -> Bool`, `mutating prune(now:)`, `json() throws -> Data`, `static decode(_ data: Data) throws -> NoteLog`, constants `keepRead`, `cap`, `waitingBody`.
  - `enum NoteDrop: Equatable, Sendable`: `.read([UUID])`, `.readAll`, `.delete([UUID])`, `.installed(bundleID: String, build: String)`, `.build(NoteBuild, sessionID: String?, terminal: String?, skin: String?)`, `.phone(PhoneNoteSettings)`; `init(json: Data) throws`, `json() throws -> Data`, `fileName(id: UUID) -> String`.
  - `enum NoteDelivery: String, Codable, CaseIterable, Sendable { case off, wave, push }`.
  - `struct NoteSettings: Codable, Equatable, Sendable` with `waiting`, `build: NoteDelivery` (default `.wave`), `subscript(kind:) -> NoteDelivery { get set }`, `shown: Set<LosttyNote.Kind>`.
  - `struct PhoneNoteSettings: Codable, Equatable, Sendable` with `phoneID: String`, `name: String`, `settings: NoteSettings`.

- [ ] **Step 1: Write the failing tests**

Create `macos/LosttyRemote/Tests/LosttyRemoteTests/NotesTests.swift`:

```swift
import Foundation
import Testing
@testable import LosttyRemote

/// Deterministic note ids, in order.
private final class IDs {
    private var n = 0
    func next() -> UUID {
        n += 1
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!
    }
}

struct NotesTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let skin = "1b2a20,,7fd1a0"

    func session(
        _ id: String = "$1", claude: ClaudeActivity? = .waiting, action: String? = "Allow? Run the iOS tests",
        title: String = "✳ Fix the login bug"
    ) -> RemoteSession {
        RemoteSession(
            id: id, name: "lostty", surface: "PANE", owner: 4242, claude: claude, action: action, title: title,
            path: "/Users/me/projectrepos/lostty", command: "2.1.296", activity: now,
            skin: SessionSkin(encoded: skin))
    }

    let lostty = NoteBuild(
        app: "Lostty", bundleID: "com.lawliang.lostty-mobile", build: "202610131331", commit: "cf0a354c9",
        branch: "skins", project: "lostty",
        installURL: "itms-services://?action=download-manifest&url=https://mac.ts.net/manifest-202610131331.plist")

    func build(_ number: String, bundleID: String = "com.lawliang.lostty-mobile") -> NoteBuild {
        var b = lostty
        b.build = number
        b.bundleID = bundleID
        return b
    }

    // MARK: Waiting

    @Test func aWaitingTerminalMakesOneUnreadNote() {
        var log = NoteLog()
        let ids = IDs()
        #expect(log.sync(sessions: [session()], now: now, newID: ids.next))
        #expect(log.notes.count == 1)
        let note = log.notes[0]
        #expect(note.kind == .waiting)
        #expect(note.title == "Fix the login bug")
        #expect(note.body == "Allow? Run the iOS tests")
        #expect(note.sessionID == "$1")
        #expect(note.skin == SessionSkin(encoded: skin)?.encoded)
        #expect(!note.read)
        #expect(log.unreadCount == 1)
    }

    @Test func withoutAQuestionItSaysWaitingOnYou() {
        var log = NoteLog()
        log.sync(sessions: [session(action: nil), session("$2", action: "")], now: now)
        #expect(log.notes.map(\.body) == [NoteLog.waitingBody, NoteLog.waitingBody])
    }

    @Test func aTerminalThatIsNotWaitingMakesNoNote() {
        var log = NoteLog()
        #expect(!log.sync(sessions: [session(claude: .working), session("$2", claude: nil)], now: now))
        #expect(log.notes.isEmpty)
    }

    @Test func answeringItReadsIt() {
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        #expect(log.sync(sessions: [session(claude: .working)], now: now.addingTimeInterval(5)))
        #expect(log.notes.count == 1)
        #expect(log.notes[0].read)
    }

    @Test func aTerminalThatEndsReadsItsNote() {
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        log.sync(sessions: [], now: now.addingTimeInterval(5))
        #expect(log.notes[0].read)
    }

    @Test func aNewEpisodeRevivesTheSameNote() {
        var log = NoteLog()
        let ids = IDs()
        log.sync(sessions: [session()], now: now, newID: ids.next)
        let id = log.notes[0].id
        log.sync(sessions: [session(claude: .working)], now: now.addingTimeInterval(5), newID: ids.next)
        log.sync(sessions: [session(action: "Allow? Push to main")], now: now.addingTimeInterval(60), newID: ids.next)
        #expect(log.notes.count == 1)
        #expect(log.notes[0].id == id)
        #expect(!log.notes[0].read)
        #expect(log.notes[0].body == "Allow? Push to main")
        #expect(log.notes[0].updated == now.addingTimeInterval(60))
        #expect(log.notes[0].created == now)
    }

    @Test func aRelistWhileStillWaitingChangesNothing() {
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        #expect(!log.sync(sessions: [session()], now: now.addingTimeInterval(1)))
    }

    @Test func aNewQuestionWhileStillWaitingRevivesIt() {
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        log.apply(.readAll, now: now)
        log.sync(sessions: [session(action: "Allow? Delete the build folder")], now: now.addingTimeInterval(3))
        #expect(!log.notes[0].read)
        #expect(log.notes[0].body == "Allow? Delete the build folder")
    }

    @Test func aDeletedNoteStaysGoneUntilTheNextEpisode() {
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        log.apply(.delete([log.notes[0].id]), now: now)
        log.sync(sessions: [session()], now: now.addingTimeInterval(1))
        #expect(log.notes.isEmpty)
        log.sync(sessions: [session(claude: .working)], now: now.addingTimeInterval(2))
        log.sync(sessions: [session()], now: now.addingTimeInterval(3))
        #expect(log.notes.count == 1)
    }

    @Test func aRestartDoesNotRepeatNotes() throws {
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        log.apply(.readAll, now: now)
        var again = try NoteLog.decode(try log.json())
        #expect(again == log)
        #expect(!again.sync(sessions: [session()], now: now.addingTimeInterval(30)))
        #expect(again.notes[0].read)
    }

    @Test func newestFirst() {
        var log = NoteLog()
        log.sync(sessions: [session("$1")], now: now)
        log.sync(sessions: [session("$1"), session("$2")], now: now.addingTimeInterval(10))
        #expect(log.notes.map(\.sessionID) == ["$2", "$1"])
    }

    // MARK: Builds

    @Test func aBuildDropAddsANoteInItsTerminalsLook() {
        var log = NoteLog()
        log.apply(.build(lostty, sessionID: "$3", terminal: "✳ Ship the inbox", skin: skin), now: now)
        let note = log.notes[0]
        #expect(note.kind == .build)
        #expect(note.title == "Lostty is ready to install")
        #expect(note.body == "Build 202610131331 · skins · Ship the inbox")
        #expect(note.sessionID == "$3")
        #expect(note.skin == skin)
        #expect(note.build == lostty)
        #expect(!note.read)
    }

    @Test func aBuildFromOutsideLosttyNamesItsProject() {
        var log = NoteLog()
        log.apply(.build(lostty, sessionID: nil, terminal: nil, skin: nil), now: now)
        #expect(log.notes[0].body == "Build 202610131331 · skins · lostty")
        #expect(log.notes[0].skin == nil)
    }

    @Test func installingReadsThatAppsBuildsUpToIt() {
        var log = NoteLog()
        log.apply(.build(build("202610131331"), sessionID: nil, terminal: nil, skin: nil), now: now)
        log.apply(.build(build("202610131400"), sessionID: nil, terminal: nil, skin: nil), now: now.addingTimeInterval(1))
        log.apply(.build(build("1", bundleID: "com.example.other"), sessionID: nil, terminal: nil, skin: nil), now: now.addingTimeInterval(2))
        log.apply(.installed(bundleID: "com.lawliang.lostty-mobile", build: "202610131331"), now: now)
        let read = Dictionary(uniqueKeysWithValues: log.notes.map { ($0.build!.build, $0.read) })
        #expect(read == ["202610131331": true, "202610131400": false, "1": false])
    }

    // MARK: Reading, deleting, keeping

    @Test func readMarksOnlyThose() {
        var log = NoteLog()
        log.sync(sessions: [session("$1"), session("$2")], now: now)
        log.apply(.read([log.notes[0].id]), now: now)
        #expect(log.notes.map(\.read) == [true, false])
        log.apply(.readAll, now: now)
        #expect(log.unreadCount == 0)
    }

    @Test func pruneDropsReadNotesAfterAWeekButKeepsUnread() {
        var log = NoteLog()
        log.sync(sessions: [session("$1"), session("$2")], now: now)
        log.apply(.read([log.notes.first { $0.sessionID == "$1" }!.id]), now: now)
        log.prune(now: now.addingTimeInterval(NoteLog.keepRead + 1))
        #expect(log.notes.map(\.sessionID) == ["$2"])
    }

    @Test func pruneCapsAtAHundredOldestReadFirst() {
        var log = NoteLog()
        for i in 0..<105 {
            log.apply(.build(build(String(i)), sessionID: nil, terminal: nil, skin: nil), now: now.addingTimeInterval(Double(i)))
        }
        log.apply(.read(log.notes.suffix(10).map(\.id)), now: now)
        log.prune(now: now.addingTimeInterval(200))
        #expect(log.notes.count == NoteLog.cap)
        #expect(log.notes.allSatisfy { Int($0.build!.build)! >= 5 })
    }

    @Test func unreadCountCountsOnlyShownKinds() {
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        log.apply(.build(lostty, sessionID: nil, terminal: nil, skin: nil), now: now)
        #expect(log.unreadCount(showing: [.build]) == 1)
        #expect(log.unreadCount(showing: [.waiting, .build]) == 2)
    }

    // MARK: Drop files

    @Test func dropsRoundTripThroughJSON() throws {
        let drops: [NoteDrop] = [
            .read([UUID()]), .readAll, .delete([UUID(), UUID()]),
            .installed(bundleID: "com.lawliang.lostty-mobile", build: "202610131331"),
            .build(lostty, sessionID: "$3", terminal: "it's \"done\"", skin: skin),
            .phone(PhoneNoteSettings(phoneID: "P1", name: "iPhone 13", settings: NoteSettings(waiting: .off, build: .wave))),
        ]
        for drop in drops {
            #expect(try NoteDrop(json: try drop.json()) == drop)
        }
    }

    @Test func readsTheShipScriptsShape() throws {
        // What macos/ship-phone.sh and ship-ios.sh write.
        let json = """
        {"type": "build", "app": "Lostty", "bundleID": "com.lawliang.lostty-mobile", "build": "202610131331",
         "commit": "cf0a354c9", "branch": "skins", "project": "lostty",
         "installURL": "itms-services://?action=download-manifest&url=https://mac.ts.net/manifest-202610131331.plist",
         "sessionID": null, "terminal": null, "skin": null}
        """
        #expect(try NoteDrop(json: Data(json.utf8)) == .build(lostty, sessionID: nil, terminal: nil, skin: nil))
    }

    @Test func anUnknownDropIsAnError() {
        #expect(throws: (any Error).self) { try NoteDrop(json: Data(#"{"type":"launch-rockets"}"#.utf8)) }
        #expect(throws: (any Error).self) { try NoteDrop(json: Data("not json".utf8)) }
    }

    @Test func dropFileNamesSayTheirTypeAndAreUnique() {
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        #expect(NoteDrop.readAll.fileName(id: id) == "readAll-00000000-0000-4000-8000-000000000001.json")
        #expect(NoteDrop.build(lostty, sessionID: nil, terminal: nil, skin: nil).fileName(id: id).hasPrefix("build-"))
    }

    // MARK: Settings

    @Test func settingsDefaultToWaveAndHideWhatIsOff() {
        var settings = NoteSettings()
        #expect(settings[.waiting] == .wave && settings[.build] == .wave)
        settings[.build] = .off
        #expect(settings.shown == [.waiting])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd macos/LosttyRemote && swift test --filter NotesTests`
Expected: build FAILS with "cannot find 'NoteLog' in scope" (and the other new types).

- [ ] **Step 3: Write the implementation**

Create `macos/LosttyRemote/Sources/LosttyRemote/Notes.swift`:

```swift
import Foundation

/// Lostty Mobile's notifications (👋): what the Mac keeps in
/// `notifications/notes.json` and the phone shows in its inbox. A terminal
/// waiting on you, or a new build to install.
public struct LosttyNote: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case waiting
        case build
    }

    public var id: UUID
    public var kind: Kind
    public var created: Date
    /// Last time it said something new: newest first in the inbox.
    public var updated: Date
    public var read: Bool
    public var title: String
    public var body: String
    /// The terminal it came from ("$3"); nil for a build shipped outside Lostty.
    public var sessionID: String?
    /// That terminal's `@lostty_skin`, so the note wears its colors.
    public var skin: String?
    public var build: NoteBuild?

    public init(
        id: UUID, kind: Kind, created: Date, updated: Date, read: Bool = false, title: String, body: String,
        sessionID: String? = nil, skin: String? = nil, build: NoteBuild? = nil
    ) {
        self.id = id
        self.kind = kind
        self.created = created
        self.updated = updated
        self.read = read
        self.title = title
        self.body = body
        self.sessionID = sessionID
        self.skin = skin
        self.build = build
    }
}

/// A phone build published over Tailscale (`ship-phone.sh`, `ship-ios.sh`).
public struct NoteBuild: Codable, Equatable, Sendable {
    public var app: String
    public var bundleID: String
    public var build: String
    public var commit: String
    public var branch: String
    public var project: String
    /// The `itms-services` link that starts the install.
    public var installURL: String

    public init(app: String, bundleID: String, build: String, commit: String, branch: String, project: String, installURL: String) {
        self.app = app
        self.bundleID = bundleID
        self.build = build
        self.commit = commit
        self.branch = branch
        self.project = project
        self.installURL = installURL
    }
}

/// The notes and every rule about them, shared by the Mac (which keeps
/// them) and the phone (which shows them and applies its own changes at
/// once, ahead of the Mac).
public struct NoteLog: Codable, Equatable, Sendable {
    /// Read notes go this long after their last update.
    public static let keepRead: TimeInterval = 7 * 24 * 3600
    public static let cap = 100
    /// A waiting note's text when Claude didn't say what it asks.
    public static let waitingBody = "Waiting on you"

    /// Newest first.
    public private(set) var notes: [LosttyNote]
    /// The sessions waiting at the last `sync`: a waiting episode starts
    /// when a session joins it. Kept with the notes, so a restart doesn't
    /// start them all again.
    public private(set) var waiting: Set<String>

    public init(notes: [LosttyNote] = [], waiting: Set<String> = []) {
        self.notes = notes
        self.waiting = waiting
        sort()
    }

    public var unreadCount: Int { notes.filter { !$0.read }.count }

    public func unreadCount(showing kinds: Set<LosttyNote.Kind>) -> Int {
        notes.filter { !$0.read && kinds.contains($0.kind) }.count
    }

    /// Waiting notes from a session listing: one per terminal. A terminal
    /// that starts waiting, or asks something new, adds its note or revives
    /// it (unread, now); one that stops waiting (answered, or ended) reads
    /// it. True when anything changed.
    @discardableResult
    public mutating func sync(sessions: [RemoteSession], now: Date, newID: () -> UUID = UUID.init) -> Bool {
        let before = self
        let waitingNow = sessions.filter { $0.claude == .waiting }
        for session in waitingNow {
            let title = SessionLabel.row(for: session, now: now).title
            let body = session.action.flatMap { $0.isEmpty ? nil : $0 } ?? Self.waitingBody
            let started = !waiting.contains(session.id)
            if let i = notes.firstIndex(where: { $0.kind == .waiting && $0.sessionID == session.id }) {
                notes[i].title = title
                notes[i].skin = session.skin?.encoded
                if started || notes[i].body != body {
                    notes[i].body = body
                    notes[i].updated = now
                    notes[i].read = false
                }
            } else if started {
                // Deleted while still waiting: back only with the next episode.
                notes.append(LosttyNote(
                    id: newID(), kind: .waiting, created: now, updated: now, title: title, body: body,
                    sessionID: session.id, skin: session.skin?.encoded))
            }
        }
        let ids = Set(waitingNow.map(\.id))
        for i in notes.indices where notes[i].kind == .waiting {
            if let id = notes[i].sessionID, waiting.contains(id), !ids.contains(id) { notes[i].read = true }
        }
        waiting = ids
        sort()
        return self != before
    }

    /// A drop file's change (`NoteDrop`). `.phone` is the keeper's, not the
    /// log's. True when anything changed.
    @discardableResult
    public mutating func apply(_ drop: NoteDrop, now: Date, newID: () -> UUID = UUID.init) -> Bool {
        let before = self
        switch drop {
        case .read(let ids):
            for i in notes.indices where ids.contains(notes[i].id) { notes[i].read = true }
        case .readAll:
            for i in notes.indices { notes[i].read = true }
        case .delete(let ids):
            notes.removeAll { ids.contains($0.id) }
        case .installed(let bundleID, let build):
            for i in notes.indices {
                guard let shipped = notes[i].build, shipped.bundleID == bundleID,
                      Self.isAtMost(shipped.build, build) else { continue }
                notes[i].read = true
            }
        case .build(let info, let sessionID, let terminal, let skin):
            let from = terminal.map(SessionLabel.cleanTitle).flatMap { $0.isEmpty ? nil : $0 } ?? info.project
            let body = ["Build \(info.build)", info.branch, from].filter { !$0.isEmpty }.joined(separator: " · ")
            notes.append(LosttyNote(
                id: newID(), kind: .build, created: now, updated: now, title: "\(info.app) is ready to install",
                body: body, sessionID: sessionID, skin: skin, build: info))
        case .phone:
            break
        }
        sort()
        return self != before
    }

    /// Read notes a week past their last update go; past `cap`, the oldest
    /// read ones go first.
    public mutating func prune(now: Date) {
        notes.removeAll { $0.read && now.timeIntervalSince($0.updated) > Self.keepRead }
        while notes.count > Self.cap {
            if let i = notes.lastIndex(where: \.read) {
                notes.remove(at: i)
            } else {
                notes.removeLast()
            }
        }
    }

    public func json() throws -> Data { try Self.encoder.encode(self) }

    public static func decode(_ data: Data) throws -> NoteLog { try decoder.decode(NoteLog.self, from: data) }

    /// Builds are numbered by time ("202610131331"); anything else matches
    /// only itself.
    static func isAtMost(_ shipped: String, _ installed: String) -> Bool {
        if let a = Int(shipped), let b = Int(installed) { return a <= b }
        return shipped == installed
    }

    private mutating func sort() {
        notes.sort { a, b in
            if a.updated != b.updated { return a.updated > b.updated }
            if a.created != b.created { return a.created > b.created }
            return a.id.uuidString > b.id.uuidString
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

/// One change for the Mac's keeper, left as a file in
/// `notifications/inbox/` by the phone or a ship script.
public enum NoteDrop: Equatable, Sendable {
    case read([UUID])
    case readAll
    case delete([UUID])
    /// A phone runs this build of `bundleID`: that app's build notes up to it are read.
    case installed(bundleID: String, build: String)
    /// A build published for install; `terminal` is the shipping pane's title.
    case build(NoteBuild, sessionID: String?, terminal: String?, skin: String?)
    case phone(PhoneNoteSettings)

    public init(json data: Data) throws {
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        switch wire.type {
        case "read": self = .read(try wire.need(\.ids))
        case "readAll": self = .readAll
        case "delete": self = .delete(try wire.need(\.ids))
        case "installed": self = .installed(bundleID: try wire.need(\.bundleID), build: try wire.need(\.build))
        case "build":
            self = .build(
                NoteBuild(
                    app: try wire.need(\.app), bundleID: try wire.need(\.bundleID), build: try wire.need(\.build),
                    commit: wire.commit ?? "", branch: wire.branch ?? "", project: wire.project ?? "",
                    installURL: try wire.need(\.installURL)),
                sessionID: wire.sessionID, terminal: wire.terminal, skin: wire.skin)
        case "phone": self = .phone(try wire.need(\.phone))
        default: throw DropError.unknownType(wire.type)
        }
    }

    public func json() throws -> Data {
        var wire = Wire(type: type)
        switch self {
        case .read(let ids), .delete(let ids): wire.ids = ids
        case .readAll: break
        case .installed(let bundleID, let build):
            wire.bundleID = bundleID
            wire.build = build
        case .build(let info, let sessionID, let terminal, let skin):
            wire.app = info.app
            wire.bundleID = info.bundleID
            wire.build = info.build
            wire.commit = info.commit
            wire.branch = info.branch
            wire.project = info.project
            wire.installURL = info.installURL
            wire.sessionID = sessionID
            wire.terminal = terminal
            wire.skin = skin
        case .phone(let phone): wire.phone = phone
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(wire)
    }

    /// "<type>-<id>.json". Written as "." + this, then renamed: a name
    /// starting with "." is still being written.
    public func fileName(id: UUID) -> String { "\(type)-\(id.uuidString).json" }

    private var type: String {
        switch self {
        case .read: "read"
        case .readAll: "readAll"
        case .delete: "delete"
        case .installed: "installed"
        case .build: "build"
        case .phone: "phone"
        }
    }

    enum DropError: Error, Equatable {
        case unknownType(String)
        case missing(String)
    }

    /// Flat, with a "type", so the ship scripts can write it by hand.
    private struct Wire: Codable {
        var type: String
        var ids: [UUID]?
        var bundleID: String?
        var build: String?
        var app: String?
        var commit: String?
        var branch: String?
        var project: String?
        var installURL: String?
        var sessionID: String?
        var terminal: String?
        var skin: String?
        var phone: PhoneNoteSettings?

        func need<T>(_ field: KeyPath<Wire, T?>) throws -> T {
            guard let value = self[keyPath: field] else { throw DropError.missing("\(field)") }
            return value
        }
    }
}

/// Where a kind of note goes: nowhere, the app's inbox (👋), or the inbox
/// and a push.
public enum NoteDelivery: String, Codable, CaseIterable, Sendable {
    case off
    case wave
    case push
}

/// One phone's choices, per kind.
public struct NoteSettings: Codable, Equatable, Sendable {
    public var waiting: NoteDelivery
    public var build: NoteDelivery

    public init(waiting: NoteDelivery = .wave, build: NoteDelivery = .wave) {
        self.waiting = waiting
        self.build = build
    }

    public subscript(kind: LosttyNote.Kind) -> NoteDelivery {
        get {
            switch kind {
            case .waiting: waiting
            case .build: build
            }
        }
        set {
            switch kind {
            case .waiting: waiting = newValue
            case .build: build = newValue
            }
        }
    }

    /// The kinds this phone shows.
    public var shown: Set<LosttyNote.Kind> { Set(LosttyNote.Kind.allCases.filter { self[$0] != .off }) }
}

/// A phone's settings as the Mac keeps them (`phones.json`), for pushes.
public struct PhoneNoteSettings: Codable, Equatable, Sendable {
    public var phoneID: String
    /// "iPhone 13", for the Mac's Phone Access window later.
    public var name: String
    public var settings: NoteSettings

    public init(phoneID: String, name: String, settings: NoteSettings) {
        self.phoneID = phoneID
        self.name = name
        self.settings = settings
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd macos/LosttyRemote && swift test --filter NotesTests`
Expected: all `NotesTests` PASS. If `aWaitingTerminalMakesOneUnreadNote` fails on the title, print `SessionLabel.row(for: session(), now: now).title` and check `SessionLabelTests.aClaudeSessionReadsAsItsTask`: the session must look like Claude (`command: "2.1.296"`).

- [ ] **Step 5: Run the whole package's tests**

Run: `cd macos/LosttyRemote && swift test`
Expected: PASS (nothing else changed).

---

### Task 2: Reading and leaving notes over SSH

**Files:**
- Create: `macos/LosttyRemote/Sources/LosttyRemote/NotesRemote.swift`
- Modify: `macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift` (after `sessions()`)
- Test: `macos/LosttyRemote/Tests/LosttyRemoteTests/NotesRemoteTests.swift`

**Interfaces:**
- Consumes: `NoteLog.decode`, `NoteDrop.json()`, `NoteDrop.fileName(id:)` (Task 1), `TmuxRemote.shellQuote(_:)`.
- Produces: `enum NotesRemote` with `static let folder: String`, `static let readCommand: String`, `static func dropCommand(_ drop: NoteDrop, id: UUID = UUID()) throws -> String`, `static func parseNotes(_ text: String) -> NoteLog?`; `RemoteConnection.notes() async throws -> NoteLog`; `RemoteConnection.drop(_ drop: NoteDrop) async throws`.

- [ ] **Step 1: Write the failing tests**

Create `macos/LosttyRemote/Tests/LosttyRemoteTests/NotesRemoteTests.swift`:

```swift
import Foundation
import Testing
@testable import LosttyRemote

struct NotesRemoteTests {
    /// Runs `command` with /bin/sh as the phone's SSH session would, with
    /// HOME in a fresh temporary folder; returns that folder.
    func run(_ command: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return home
    }

    func inbox(_ home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Lostty/notifications/inbox")
    }

    @Test func aDropSurvivesTheShellByteForByte() throws {
        let build = NoteBuild(
            app: "Lostty", bundleID: "com.lawliang.lostty-mobile", build: "1", commit: "abc", branch: "it's",
            project: "$HOME `x`", installURL: "itms-services://?a=1&b=2")
        let drop = NoteDrop.build(build, sessionID: "$3", terminal: "say \"hi\"\nthen 'bye' \\ $(ls)", skin: nil)
        let id = UUID()
        let home = try run(try NotesRemote.dropCommand(drop, id: id))
        let file = inbox(home).appendingPathComponent(drop.fileName(id: id))
        #expect(try NoteDrop(json: Data(contentsOf: file)) == drop)
        // Renamed into place: no unfinished "." file left behind.
        let names = try FileManager.default.contentsOfDirectory(atPath: inbox(home).path)
        #expect(names == [drop.fileName(id: id)])
    }

    @Test func readingWithNoNotesYetSucceedsEmpty() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let process = Process()
        let out = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", NotesRemote.readCommand]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        process.standardOutput = out
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(NotesRemote.parseNotes(text) == NoteLog())
    }

    @Test func parsesTheKeepersFile() throws {
        var log = NoteLog()
        log.apply(.readAll, now: Date())
        log.apply(
            .build(
                NoteBuild(app: "Lostty", bundleID: "b", build: "1", commit: "c", branch: "main", project: "p", installURL: "u"),
                sessionID: nil, terminal: nil, skin: nil),
            now: Date(timeIntervalSince1970: 2_000_000_000))
        let text = String(decoding: try log.json(), as: UTF8.self) + "\n"
        #expect(NotesRemote.parseNotes(text) == log)
    }

    @Test func garbageIsNotNotes() {
        #expect(NotesRemote.parseNotes("cat: permission denied") == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd macos/LosttyRemote && swift test --filter NotesRemoteTests`
Expected: build FAILS with "cannot find 'NotesRemote' in scope".

- [ ] **Step 3: Write the implementation**

Create `macos/LosttyRemote/Sources/LosttyRemote/NotesRemote.swift`:

```swift
import Foundation

/// The phone's side of the Mac's notes (`NoteLog`): commands for its SSH
/// session. It reads `notes.json` but never writes it; a change goes in as
/// a drop file the Mac's Lostty applies.
public enum NotesRemote {
    /// On the Mac, through the login shell (double quotes: `$HOME` expands).
    public static let folder = "\"$HOME/Library/Application Support/Lostty/notifications\""

    /// Prints `notes.json`; nothing, and still success, before the Mac has
    /// kept any.
    public static let readCommand = "cat \(folder)/notes.json 2>/dev/null; true"

    /// Leaves `drop` in the inbox: written under a "." name, then renamed,
    /// so the Mac never reads half a file.
    public static func dropCommand(_ drop: NoteDrop, id: UUID = UUID()) throws -> String {
        let name = drop.fileName(id: id)
        let json = String(decoding: try drop.json(), as: UTF8.self)
        return "d=\(folder)/inbox && mkdir -p \"$d\" && printf '%s' \(TmuxRemote.shellQuote(json)) > \"$d/.\(name)\""
            + " && mv \"$d/.\(name)\" \"$d/\(name)\""
    }

    /// `readCommand`'s output: no notes yet when empty, nil when unreadable.
    public static func parseNotes(_ text: String) -> NoteLog? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return NoteLog() }
        return try? NoteLog.decode(Data(trimmed.utf8))
    }
}
```

In `macos/LosttyRemote/Sources/LosttyRemote/RemoteConnection.swift`, insert right after the closing brace of `public func sessions() async throws -> [RemoteSession] { … }`:

```swift

    /// The Mac's notifications (👋); none before its Lostty keeps any.
    public func notes() async throws -> NoteLog {
        NotesRemote.parseNotes(String(buffer: try await client.executeCommand(NotesRemote.readCommand))) ?? NoteLog()
    }

    /// Leaves `drop` for the Mac's Lostty to apply to its notes.
    public func drop(_ drop: NoteDrop) async throws {
        _ = try await client.executeCommand(try NotesRemote.dropCommand(drop))
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd macos/LosttyRemote && swift test --filter NotesRemoteTests`
Expected: PASS.

- [ ] **Step 5: Run the whole package's tests**

Run: `cd macos/LosttyRemote && swift test`
Expected: PASS.

---

### Task 3: The Mac's notes keeper

**Files:**
- Create: `macos/Sources/Features/PhoneNotes/NotesFolder.swift`
- Create: `macos/Sources/Features/PhoneNotes/NotesKeeper.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (the Lostty Mobile start block)
- Test: `macos/Tests/PhoneNotes/NotesFolderTests.swift`

**Interfaces:**
- Consumes: `NoteLog`, `NoteDrop`, `PhoneNoteSettings` (Task 1); `TmuxClient().sessionListing()`, `TmuxClient().run(_:)`, `TmuxHooks.signalArgs`, `Notification.Name.losttySessionsChanged` (existing Mac code).
- Produces: `struct NotesFolder` with `init(root: URL)`, `static var standard: URL`, `notesURL`, `phonesURL`, `inbox`, `lockURL`, `create() throws`, `loadNotes() -> NoteLog`, `save(_: NoteLog) throws`, `loadPhones() -> [String: PhoneNoteSettings]`, `save(phones:) throws`, `drain() -> [NoteDrop]`, `lock() -> Int32?`; `final class NotesKeeper` with `static let shared`, `start()`.

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/PhoneNotes/NotesFolderTests.swift`:

```swift
#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

struct NotesFolderTests {
    func folder() throws -> NotesFolder {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString)")
        let folder = NotesFolder(root: root)
        try folder.create()
        return folder
    }

    func put(_ folder: NotesFolder, _ name: String, _ text: String) throws {
        try Data(text.utf8).write(to: folder.inbox.appendingPathComponent(name))
    }

    @Test func noFileIsNoNotes() throws {
        #expect(try folder().loadNotes() == NoteLog())
    }

    @Test func savesAndLoadsNotes() throws {
        let folder = try folder()
        var log = NoteLog()
        log.apply(
            .build(
                NoteBuild(app: "Lostty", bundleID: "b", build: "1", commit: "c", branch: "main", project: "p", installURL: "u"),
                sessionID: "$1", terminal: nil, skin: nil),
            now: Date(timeIntervalSince1970: 2_000_000_000))
        try folder.save(log)
        #expect(folder.loadNotes() == log)
    }

    @Test func savesAndLoadsPhones() throws {
        let folder = try folder()
        let phone = PhoneNoteSettings(phoneID: "P1", name: "iPhone 13", settings: NoteSettings(waiting: .off))
        try folder.save(phones: ["P1": phone])
        #expect(folder.loadPhones() == ["P1": phone])
    }

    @Test func drainAppliesFinishedFilesAndDeletesThem() throws {
        let folder = try folder()
        try put(folder, NoteDrop.readAll.fileName(id: UUID()), String(decoding: try NoteDrop.readAll.json(), as: UTF8.self))
        let delete = NoteDrop.delete([UUID()])
        try put(folder, delete.fileName(id: UUID()), String(decoding: try delete.json(), as: UTF8.self))
        let drops = folder.drain()
        #expect(drops.count == 2)
        #expect(drops.contains(.readAll))
        #expect(drops.contains(delete))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.inbox.path).isEmpty)
    }

    @Test func drainSkipsUnfinishedAndDropsMalformed() throws {
        let folder = try folder()
        let unfinished = "." + NoteDrop.readAll.fileName(id: UUID())
        try put(folder, unfinished, #"{"type":"rea"#)
        try put(folder, "read-\(UUID().uuidString).json", "{not json")
        try put(folder, "phone-\(UUID().uuidString).json", #"{"type":"phone"}"#)
        #expect(folder.drain().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.inbox.path) == [unfinished])
    }

    @Test func onlyOneKeeperHoldsTheLock() throws {
        let folder = try folder()
        let first = folder.lock()
        #expect(first != nil)
        #expect(folder.lock() == nil)
        if let first { close(first) }
        let again = folder.lock()
        #expect(again != nil)
        if let again { close(again) }
    }
}
#endif
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `macos/skins-test.sh NotesFolderTests`
Expected: build FAILS with "cannot find 'NotesFolder' in scope".

- [ ] **Step 3: Write `NotesFolder`**

Create `macos/Sources/Features/PhoneNotes/NotesFolder.swift`:

```swift
#if os(macOS)
import Foundation
import LosttyRemote
import os

/// Lostty Mobile's notifications on disk: `notes.json` (only the keeper
/// writes it), `phones.json` (each phone's settings, for pushes) and
/// `inbox/` (drop files from the phone and the ship scripts; see
/// `NoteDrop`).
struct NotesFolder {
    let root: URL

    static var standard: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty/notifications", isDirectory: true)
    }

    var notesURL: URL { root.appendingPathComponent("notes.json") }
    var phonesURL: URL { root.appendingPathComponent("phones.json") }
    var inbox: URL { root.appendingPathComponent("inbox", isDirectory: true) }
    var lockURL: URL { root.appendingPathComponent(".lock") }

    private static let logger = Logger(subsystem: "com.lawliang.lostty", category: "notes")

    func create() throws {
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    func loadNotes() -> NoteLog {
        (try? Data(contentsOf: notesURL)).flatMap { try? NoteLog.decode($0) } ?? NoteLog()
    }

    func save(_ log: NoteLog) throws {
        try log.json().write(to: notesURL, options: .atomic)
    }

    func loadPhones() -> [String: PhoneNoteSettings] {
        (try? Data(contentsOf: phonesURL)).flatMap { try? JSONDecoder().decode([String: PhoneNoteSettings].self, from: $0) } ?? [:]
    }

    func save(phones: [String: PhoneNoteSettings]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(phones).write(to: phonesURL, options: .atomic)
    }

    /// Each finished drop file, oldest first, read and deleted. One that
    /// doesn't read as a drop is logged and deleted, never applied in part;
    /// a name starting with "." is still being written and waits.
    func drain() -> [NoteDrop] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        let finished = files
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "json" }
            .sorted { a, b in
                let (x, y) = (Self.created(a), Self.created(b))
                return x != y ? x < y : a.lastPathComponent < b.lastPathComponent
            }
        var drops: [NoteDrop] = []
        for file in finished {
            if let data = try? Data(contentsOf: file), let drop = try? NoteDrop(json: data) {
                drops.append(drop)
            } else {
                Self.logger.error("dropped an unreadable notes file: \(file.lastPathComponent, privacy: .public)")
            }
            try? fm.removeItem(at: file)
        }
        return drops
    }

    /// The keeper's lock: the open file descriptor while held, nil when
    /// another Lostty (debug and release share the tmux server) holds it.
    func lock() -> Int32? {
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private static func created(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `macos/skins-test.sh NotesFolderTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Write `NotesKeeper`**

Create `macos/Sources/Features/PhoneNotes/NotesKeeper.swift`:

```swift
#if os(macOS)
import Foundation
import LosttyRemote

/// Lostty Mobile: keeps the phone's notifications (👋). Waiting notes come
/// from the same session listing the phone reads, after every tmux change;
/// everything else arrives as drop files in `inbox/`. After a change it
/// saves `notes.json` and wakes tmux's change channel, so a phone that's
/// watching re-lists and reads the notes. Only one Lostty process keeps
/// them: the one holding the folder's lock.
@MainActor
final class NotesKeeper {
    static let shared = NotesKeeper()

    private let folder = NotesFolder(root: NotesFolder.standard)
    private var log = NoteLog()
    private var phones: [String: PhoneNoteSettings] = [:]
    private var lockFD: Int32?
    private var inboxSource: DispatchSourceFileSystemObject?
    private var observer: NSObjectProtocol?
    /// tmux runs here, off the main thread.
    private let tmux = DispatchQueue(label: "Lostty notes", qos: .utility)

    func start() {
        guard lockFD == nil else { return }
        do { try folder.create() } catch { return }
        guard let fd = folder.lock() else { return }
        lockFD = fd
        log = folder.loadNotes()
        phones = folder.loadPhones()
        watchInbox()
        observer = NotificationCenter.default.addObserver(forName: .losttySessionsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relist() }
        }
        drainInbox()
        relist()
    }

    private func watchInbox() {
        let fd = open(folder.inbox.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drainInbox() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        inboxSource = source
    }

    private func drainInbox() {
        var changed = false
        for drop in folder.drain() {
            if case .phone(let phone) = drop {
                phones[phone.phoneID] = phone
                try? folder.save(phones: phones)
            } else if log.apply(drop, now: Date()) {
                changed = true
            }
        }
        if changed { save() }
    }

    private func relist() {
        tmux.async { [weak self] in
            let sessions = TmuxClient().sessionListing()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.log.sync(sessions: sessions, now: Date()) else { return }
                    self.save()
                }
            }
        }
    }

    private func save() {
        log.prune(now: Date())
        do { try folder.save(log) } catch { return }
        // The phone's watch re-lists, and reads the notes with it. Our own
        // listing that follows finds nothing new, so this doesn't loop.
        tmux.async { _ = TmuxClient().run(TmuxHooks.signalArgs) }
    }
}
#endif
```

- [ ] **Step 6: Start it with the other Lostty Mobile services**

In `macos/Sources/App/macOS/AppDelegate.swift`, inside the `if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {` block, right after the line `NewTerminalRequests.shared.start(ghostty)`, add:

```swift
            // Lostty Mobile: the phone's notifications (👋).
            NotesKeeper.shared.start()
```

- [ ] **Step 7: Build the Mac app**

Run: `macos/build.nu`
Expected: build succeeds.

- [ ] **Step 8: Check it end to end on this Mac**

Launch the built Debug app (`open macos/build/Debug/Lostty.app`). If the installed release Lostty is already running, it has no keeper, so the Debug app takes the lock. Then:

```sh
D="$HOME/Library/Application Support/Lostty/notifications"
ls "$D"                      # expect: inbox  notes.json (maybe)  .lock
printf '%s' '{"type":"build","app":"Lostty","bundleID":"com.lawliang.lostty-mobile","build":"1","installURL":"itms-services://x"}' > "$D/inbox/.t.json" && mv "$D/inbox/.t.json" "$D/inbox/build-test.json"
sleep 1; ls "$D/inbox"; python3 -I -m json.tool "$D/notes.json" | head -20
```

Expected: `inbox` is empty again, and `notes.json` has a `"kind": "build"` note titled "Lostty is ready to install". Delete the test note afterwards with `printf '%s' '{"type":"readAll"}' > "$D/inbox/readAll-x.json"`, or leave it; read notes go after 7 days. Quit the Debug app when done.

- [ ] **Step 9: Run the Mac suite again**

Run: `macos/skins-test.sh NotesFolderTests`
Expected: `** TEST SUCCEEDED **`.

---

### Task 4: The phone reads notes and sends changes

**Files:**
- Modify: `macos/Sources/App/iOS/MobileStore.swift`
- Create: `macos/Sources/App/iOS/MobileStore+Notes.swift`

**Interfaces:**
- Consumes: `RemoteConnection.notes()`, `RemoteConnection.drop(_:)` (Task 2); `NoteLog`, `NoteDrop`, `NoteSettings`, `PhoneNoteSettings` (Task 1); `DeviceModel.current`.
- Produces on `MobileStore`: `@Published var notes: NoteLog`, `@Published var noteSettings: NoteSettings`, `shownNotes: [LosttyNote]`, `unreadNotes: Int`, `markNotesRead(_ ids: [UUID])`, `markAllNotesRead()`, `deleteNotes(_ ids: [UUID])`, `setDelivery(_ delivery: NoteDelivery, for kind: LosttyNote.Kind)`, and `gallery(…, notes: NoteLog = NoteLog())`.

The iOS app has no unit-test target; this task is verified by building, and by the simulator in Task 5.

- [ ] **Step 1: Add the stored properties and widen three members**

In `macos/Sources/App/iOS/MobileStore.swift` (re-read it first; another session edits it):

1. After the line `@Published var message: String?`, add:

```swift

    /// The Mac's notifications (👋), as of the last listing.
    @Published var notes = NoteLog()
    /// Which kinds this phone shows (and, in stage 2, pushes).
    @Published var noteSettings: NoteSettings
```

2. Change `private let defaults: UserDefaults` to `let defaults: UserDefaults`.

3. In `init(defaults:)`, after `self.settings = RemoteHostSettings.load(from: defaults)`, add:

```swift
        self.noteSettings = Self.loadNoteSettings(from: defaults)
```

4. Change `private func withConnection<T>(` to `func withConnection<T>(`.

5. In `watch(on:)`'s nested `func relist()`, after `await loadLogoTiles(found, on: connection)`, add:

```swift
            await loadNotes(on: connection)
```

6. In `static func gallery(`, add a parameter `notes: NoteLog = NoteLog()` after `settings: RemoteHostSettings = RemoteHostSettings()`, and before `return store` add `store.notes = notes`.

- [ ] **Step 2: Write the phone-side notes actions**

Create `macos/Sources/App/iOS/MobileStore+Notes.swift`:

```swift
#if os(iOS)
import Foundation
import LosttyRemote

/// Lostty Mobile's notifications on the phone: read with each listing;
/// changed here at once, then by a drop file the Mac's Lostty applies for
/// every phone.
extension MobileStore {
    static let noteSettingsKey = "LosttyNoteSettings"
    static let phoneIDKey = "LosttyPhoneID"
    static let reportedBuildKey = "LosttyReportedBuild"

    /// The notes this phone shows: every kind it hasn't turned off.
    var shownNotes: [LosttyNote] { notes.notes.filter { noteSettings.shown.contains($0.kind) } }

    /// For 👋's badge.
    var unreadNotes: Int { notes.unreadCount(showing: noteSettings.shown) }

    static func loadNoteSettings(from defaults: UserDefaults) -> NoteSettings {
        defaults.data(forKey: noteSettingsKey).flatMap { try? JSONDecoder().decode(NoteSettings.self, from: $0) } ?? NoteSettings()
    }

    /// This phone to the Mac, made the first time it's asked for.
    var phoneID: String {
        if let id = defaults.string(forKey: Self.phoneIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.phoneIDKey)
        return id
    }

    func loadNotes(on connection: RemoteConnection) async {
        guard let log = try? await connection.notes() else { return }
        notes = log
        await reportBuild(on: connection)
    }

    func markNotesRead(_ ids: [UUID]) { send(.read(ids)) }
    func markAllNotesRead() { send(.readAll) }
    func deleteNotes(_ ids: [UUID]) { send(.delete(ids)) }

    func setDelivery(_ delivery: NoteDelivery, for kind: LosttyNote.Kind) {
        noteSettings[kind] = delivery
        if let data = try? JSONEncoder().encode(noteSettings) { defaults.set(data, forKey: Self.noteSettingsKey) }
        send(.phone(PhoneNoteSettings(phoneID: phoneID, name: DeviceModel.current, settings: noteSettings)))
    }

    /// Once per build of this app: the Mac reads its build notes up to it.
    private func reportBuild(on connection: RemoteConnection) async {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              defaults.string(forKey: Self.reportedBuildKey) != build else { return }
        do {
            try await connection.drop(.installed(bundleID: bundleID, build: build))
            defaults.set(build, forKey: Self.reportedBuildKey)
        } catch {
            // Next listing tries again.
        }
    }

    /// Shown at once; the Mac applies it and every phone follows.
    private func send(_ drop: NoteDrop) {
        notes.apply(drop, now: Date())
        #if DEBUG
        if isGallery { return }
        #endif
        guard !settings.remoteHosts.isEmpty else { return }
        Task { try? await withConnection { try await $0.drop(drop) } }
    }
}
#endif
```

If `DeviceModel.current` isn't a `String`, use `String(describing: DeviceModel.current)`.

- [ ] **Step 3: Build the phone app**

Run (XcodeBuildMCP): `build_sim` with the session defaults (project `macos/Lostty.xcodeproj`, scheme `Lostty-iOS`, simulator "Lostty iPhone", Debug).
Expected: build succeeds. (`isGallery` is only read here, so its `private(set)` stays; it lives in `#if DEBUG`, as its use in `send` does.)

---

### Task 5: The inbox and 👋's badge

**Files:**
- Create: `macos/Sources/App/iOS/NotificationsInbox.swift`
- Modify: `macos/Sources/App/iOS/SessionsScreen.swift`
- Modify: `macos/Sources/App/iOS/DesignGallery.swift`

**Interfaces:**
- Consumes: `MobileStore.shownNotes`, `.unreadNotes`, `.markNotesRead(_:)`, `.markAllNotesRead()`, `.deleteNotes(_:)`, `.sessions` (Task 4); `RowColors(skin:)`, `TextureTile.image(for:displayScale:)`, `TerminalLook.textureOpacity(_:)` (existing phone code).
- Produces: `struct NotificationsInbox: View` with `init(openTerminal: @escaping (RemoteSession) -> Void)`; `struct NoteBadge: View` with `count: Int`.

- [ ] **Step 1: Write the inbox**

Create `macos/Sources/App/iOS/NotificationsInbox.swift`:

```swift
#if os(iOS)
import LosttyRemote
import SwiftUI

/// The notes from 👋: newest first, each in its terminal's colors. Tapping
/// one reads it and opens its terminal, or starts its build's install;
/// swiping one away deletes it for every phone.
struct NotificationsInbox: View {
    /// Opens a terminal, as tapping its row in the list does.
    let openTerminal: (RemoteSession) -> Void
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var ended: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.shownNotes.isEmpty {
                    ContentUnavailableView(
                        "No Notifications", systemImage: "hand.wave",
                        description: Text("Terminals waiting on you and new builds show up here."))
                } else {
                    List {
                        ForEach(store.shownNotes) { note in
                            Button { tap(note) } label: { NoteRow(note: note) }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: 5, leading: LosttyTheme.margin, bottom: 5, trailing: LosttyTheme.margin))
                        }
                        .onDelete { offsets in
                            let shown = store.shownNotes
                            store.deleteNotes(offsets.map { shown[$0].id })
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .losttyScreen()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Mark All Read") { store.markAllNotesRead() }
                        .disabled(store.unreadNotes == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .alert(
                "That terminal has ended",
                isPresented: Binding(get: { ended != nil }, set: { if !$0 { ended = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(ended ?? "")
            }
        }
    }

    private func tap(_ note: LosttyNote) {
        store.markNotesRead([note.id])
        switch note.kind {
        case .waiting:
            guard let session = store.sessions.first(where: { $0.id == note.sessionID }) else {
                ended = note.title
                return
            }
            dismiss()
            openTerminal(session)
        case .build:
            if let url = note.build.flatMap({ URL(string: $0.installURL) }) { openURL(url) }
        }
    }
}

/// A note as its terminal's row looks: the skin's colors and texture, a
/// dot while unread, dimmed once read.
private struct NoteRow: View {
    let note: LosttyNote
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let skin = note.skin.flatMap(SessionSkin.init(encoded:))
        let colors = RowColors(skin: skin)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.kind == .waiting ? "hand.raised" : "arrow.down.app")
                .font(.body.weight(.semibold))
                .foregroundStyle(colors.prompt)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.title)
                        .font(LosttyFont.bodyEmphasis)
                        .foregroundStyle(colors.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(note.updated, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(LosttyFont.detail)
                        .foregroundStyle(colors.secondary)
                }
                Text(note.body)
                    .font(LosttyFont.detail)
                    .foregroundStyle(colors.secondary)
                    .lineLimit(2)
            }
            if !note.read {
                Circle().fill(colors.flash).frame(width: 8, height: 8).padding(.top, 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                colors.background
                if let skin, let texture = skin.texture, let tile = TextureTile.image(for: skin, displayScale: displayScale) {
                    Image(decorative: tile, scale: displayScale)
                        .resizable(resizingMode: .tile)
                        .opacity(TerminalLook.textureOpacity(texture))
                }
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(colors.border, lineWidth: 1))
        .opacity(note.read ? 0.6 : 1)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityValue(note.read ? "" : "Unread")
    }
}

/// 👋's unread count.
struct NoteBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(LosttyTheme.accent, in: Capsule())
            .accessibilityHidden(true)
    }
}
#endif
```

`TextureTile.image(for:displayScale:)`, `TerminalLook.textureOpacity(_:)` and `RowColors(skin:)` are the session rows' own helpers. If `TextureTile.image` takes the skin under a different label, match the call in `SessionsScreen.swift` (`TextureTile.image(for: $0, displayScale: displayScale)`).

- [ ] **Step 2: Wire 👋 in the session list**

In `macos/Sources/App/iOS/SessionsScreen.swift` (re-read it first; another session edits it):

1. Change `private struct RowColors {` to `struct RowColors {`.

2. Next to the other `@State` properties near the top of `SessionsScreen`, add:

```swift
    @State private var showNotifications = false
```

3. Replace the 👋 placeholder toolbar item. Find:

```swift
                    // Notifications. Not wired to anything yet.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {} label: {
                            Image(systemName: "hand.wave").foregroundStyle(.white)
                        }
                        .tint(.white)
                        .accessibilityLabel("Notifications")
                    }
```

and replace it with:

```swift
                    // Notifications: the inbox, and how many are unread.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNotifications = true } label: {
                            Image(systemName: "hand.wave").foregroundStyle(.white)
                                .overlay(alignment: .topTrailing) {
                                    if store.unreadNotes > 0 {
                                        NoteBadge(count: store.unreadNotes).offset(x: 11, y: -9)
                                    }
                                }
                        }
                        .tint(.white)
                        .accessibilityLabel("Notifications")
                        .accessibilityValue(store.unreadNotes > 0 ? "\(store.unreadNotes) unread" : "")
                    }
```

4. After the `.sheet(isPresented: $showNewTerminal) { … }` modifier, add:

```swift
            .sheet(isPresented: $showNotifications) {
                NotificationsInbox(openTerminal: openTerminal).environmentObject(store)
            }
```

5. In `row(_:now:)`'s `tap:` closure, replace these three lines:

```swift
                guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else { return }
                open = (session, terminal.view, terminal.io, terminal.link)
                path = ["terminal"]
```

with:

```swift
                openTerminal(session)
```

6. After `private func openMade(_ session: RemoteSession) { … }`, add:

```swift

    /// Opens `session`'s terminal: a row's tap, or a note's.
    private func openTerminal(_ session: RemoteSession) {
        guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else { return }
        open = (session, terminal.view, terminal.io, terminal.link)
        path = ["terminal"]
    }
```

- [ ] **Step 3: Gallery entries with sample notes**

In `macos/Sources/App/iOS/DesignGallery.swift` (re-read it first):

1. Add a sample log next to the other `private static let` samples (for example after `paired`):

```swift
    /// Two waiting terminals (one read) and a new build, in the sample sessions' colors.
    private static let notes: NoteLog = {
        var log = NoteLog()
        log.sync(sessions: sessions, now: Date().addingTimeInterval(-600))
        if let first = log.notes.last { log.apply(.read([first.id]), now: Date()) }
        log.apply(
            .build(
                NoteBuild(
                    app: "Lostty", bundleID: "com.lawliang.lostty-mobile", build: "202610131331", commit: "cf0a354c9",
                    branch: "skins", project: "lostty", installURL: "itms-services://?action=download-manifest&url=https://example.ts.net/manifest.plist"),
                sessionID: sessions.first?.id, terminal: "✳ Ship the inbox", skin: sessions.first?.skin?.encoded),
            now: Date().addingTimeInterval(-60))
        return log
    }()
```

2. In the "Sessions" group, change the `"Sessions"` entry's store to `MobileStore.gallery(sessions: Self.sessions, settings: Self.paired, notes: Self.notes)` so 👋 shows a badge.

3. In the same group, add:

```swift
                entry("Notifications") {
                    NotificationsInbox(openTerminal: { _ in })
                        .environmentObject(MobileStore.gallery(sessions: Self.sessions, settings: Self.paired, notes: Self.notes))
                },
                entry("Notifications — empty") {
                    NotificationsInbox(openTerminal: { _ in })
                        .environmentObject(MobileStore.gallery(sessions: Self.sessions, settings: Self.paired))
                },
```

The sample sessions must include at least one `claude: .waiting` session for a waiting note. They do (`claude: .waiting` on "$1"); if that changes, the sample shows only the build.

- [ ] **Step 4: Build and look**

Run (XcodeBuildMCP): `build_run_sim` with `launchArgs: ["-LosttyDesignGallery", "YES", "-LosttyDesignGalleryEntry", "Sessions"]`, then `screenshot`.
Expected: 👋 at the top right with a badge "2".

Then `launch_app_sim` with `-LosttyDesignGalleryEntry "Notifications"` and `screenshot`.
Expected: three rows. The newest (the build) is in the first sample session's colors and has an unread dot. The read waiting note is dimmed. "Mark All Read" is at the top left. Tap a row with AXe (`axe tap -x … -y … --udid <sim>`), screenshot: its dot is gone. Swipe a row left (`axe swipe`): Delete removes it.

Then `launch_app_sim` with `-LosttyDesignGalleryEntry "Notifications — empty"` and `screenshot`: "No Notifications" with the hand.

Finally `launch_app_sim` with no arguments, so the simulator is back on the app, not the gallery.

---

### Task 6: Settings → Notifications

**Files:**
- Create: `macos/Sources/App/iOS/NotificationSettingsScreen.swift`
- Modify: `macos/Sources/App/iOS/SettingsScreen.swift`
- Modify: `macos/Sources/App/iOS/DesignGallery.swift`

**Interfaces:**
- Consumes: `MobileStore.noteSettings`, `.setDelivery(_:for:)` (Task 4); `LosttyCard`.
- Produces: `struct NotificationSettingsScreen: View`.

- [ ] **Step 1: Write the screen**

Create `macos/Sources/App/iOS/NotificationSettingsScreen.swift`:

```swift
#if os(iOS)
import LosttyRemote
import SwiftUI

/// Settings → Notifications: per kind, Off, Wave (the inbox under 👋), or
/// Wave + Push. Push comes with stage 2; until then it can't be picked.
struct NotificationSettingsScreen: View {
    @EnvironmentObject private var store: MobileStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(LosttyNote.Kind.allCases, id: \.self) { kind in
                    LosttyCard(padding: 0) {
                        NoteKindRow(
                            kind: kind,
                            delivery: Binding(get: { store.noteSettings[kind] }, set: { store.setDelivery($0, for: kind) }))
                    }
                }
                Text("Wave puts it under 👋 in the app. Push isn't set up yet: it needs a push key on your Mac.")
                    .font(LosttyFont.detail)
                    .foregroundStyle(LosttyTheme.textSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(LosttyTheme.margin)
        }
        .losttyScreen()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NoteKindRow: View {
    let kind: LosttyNote.Kind
    @Binding var delivery: NoteDelivery

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.settingsTitle).font(LosttyFont.body).foregroundStyle(LosttyTheme.textPrimary)
                Text(kind.settingsDetail).font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Picker(kind.settingsTitle, selection: $delivery) {
                ForEach(NoteDelivery.allCases, id: \.self) { option in
                    Text(option.title).tag(option).selectionDisabled(option == .push)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(LosttyTheme.textSecondary)
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
    }
}

extension LosttyNote.Kind {
    var settingsTitle: String {
        switch self {
        case .waiting: "Waiting on You"
        case .build: "New Builds"
        }
    }

    var settingsDetail: String {
        switch self {
        case .waiting: "When Claude asks you something in a terminal."
        case .build: "When a build is ready to install over Tailscale."
        }
    }
}

extension NoteDelivery {
    var title: String {
        switch self {
        case .off: "Off"
        case .wave: "Wave"
        case .push: "Wave + Push"
        }
    }
}
#endif
```

- [ ] **Step 2: Add the row to Settings**

In `macos/Sources/App/iOS/SettingsScreen.swift` (re-read it first):

1. Replace:

```swift
        .safeAreaInset(edge: .bottom) {
            TerminalTextSizeRow()
                .padding(.horizontal, LosttyTheme.margin)
                .padding(.bottom, 12)
        }
```

with:

```swift
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if store.settings.paired { NotificationsRow() }
                TerminalTextSizeRow()
            }
            .padding(.horizontal, LosttyTheme.margin)
            .padding(.bottom, 12)
        }
```

2. After the `TerminalTextSizeRow` struct, add:

```swift

/// Opens Settings → Notifications.
private struct NotificationsRow: View {
    var body: some View {
        NavigationLink { NotificationSettingsScreen() } label: {
            LosttyCard(padding: 0) {
                HStack {
                    Text("Notifications")
                        .font(LosttyFont.body)
                        .foregroundStyle(LosttyTheme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LosttyTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Gallery entry**

In `macos/Sources/App/iOS/DesignGallery.swift`, in the "Other" group after the `"Settings"` entry, add:

```swift
                entry("Notification settings") {
                    NavigationStack { NotificationSettingsScreen() }.environmentObject(MobileStore.gallery(settings: Self.paired))
                },
```

- [ ] **Step 4: Build and look**

Run (XcodeBuildMCP): `build_run_sim` with `launchArgs: ["-LosttyDesignGallery", "YES", "-LosttyDesignGalleryEntry", "Settings"]`, then `screenshot`.
Expected: a "Notifications ›" card above Terminal Text Size.

Then `launch_app_sim` with `-LosttyDesignGalleryEntry "Notification settings"`, `screenshot`.
Expected: two cards, "Waiting on You" and "New Builds", each showing "Wave". Tap a picker (AXe): the menu lists Off, Wave, Wave + Push, with Wave + Push greyed out. Pick Off, screenshot: the card says Off.

Finally `launch_app_sim` with no arguments.

---

### Task 7: Ship scripts leave a build note

**Files:**
- Modify: `macos/ship-phone.sh`
- Modify: `~/.claude/skills/install-ios-build/ship-ios.sh` (outside the repo, so it won't show in git)

**Interfaces:**
- Consumes: the drop JSON shape `NoteDrop(json:)` reads (Task 1, `readsTheShipScriptsShape`).
- Produces: a `note_build` shell function in each script: `note_build <app> <bundle id> <build> <commit> <branch> <install link>`.

- [ ] **Step 1: Add `note_build` to `ship-phone.sh`**

In `macos/ship-phone.sh` (re-read it first), right after the line `set -eu`, add:

```sh

# Leaves a build note for Lostty on this Mac to show on the phone (👋): the
# build, its install link, and the terminal that shipped it, in its colors.
# Skipped when this Mac's Lostty keeps no notes.
note_build() { # app bundle-id build commit branch install-link
  inbox="$HOME/Library/Application Support/Lostty/notifications/inbox"
  [ -d "$inbox" ] || return 0
  session=""; title=""; skin=""
  if [ -n "${TMUX_PANE:-}" ]; then
    session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_id}' 2>/dev/null || true)
    title=$(tmux display-message -p -t "$TMUX_PANE" '#{?@lostty_label,#{@lostty_label},#{pane_title}}' 2>/dev/null || true)
    skin=$(tmux display-message -p -t "$TMUX_PANE" '#{@lostty_skin}' 2>/dev/null || true)
  fi
  project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
  python3 -I -c '
import json, os, sys, uuid
inbox, app, bundle, build, commit, branch, link, project, session, title, skin = sys.argv[1:]
drop = {"type": "build", "app": app, "bundleID": bundle, "build": build, "commit": commit,
        "branch": branch, "project": project, "installURL": link,
        "sessionID": session or None, "terminal": title or None, "skin": skin or None}
name = "build-%s.json" % str(uuid.uuid4()).upper()
with open(os.path.join(inbox, "." + name), "w") as f:
    json.dump(drop, f)
os.replace(os.path.join(inbox, "." + name), os.path.join(inbox, name))
' "$inbox" "$1" "$2" "$3" "$4" "$5" "$6" "$project" "$session" "$title" "$skin" || true
}
```

- [ ] **Step 2: Call it unless the cable install worked**

In `macos/ship-phone.sh`, find the block that starts `# A phone the Mac can reach (its cable, or the same network) gets the build`. Add `INSTALLED=0` on its own line just before the `if xcrun devicectl list devices` line. In that block, change:

```sh
      echo "Installed on the phone directly."
```

to:

```sh
      echo "Installed on the phone directly."
      INSTALLED=1
```

At the very end of the script, after that block's closing `fi`, add:

```sh

# Not on the phone yet: a note on it (👋) carries the install link.
[ "$INSTALLED" = 1 ] || note_build Lostty "$BUNDLE" "$BUILD" "$COMMIT" "$BRANCH" \
  "itms-services://?action=download-manifest&url=$URL/manifest-$BUILD.plist"
```

- [ ] **Step 3: Same function in `ship-ios.sh`**

In `~/.claude/skills/install-ios-build/ship-ios.sh`, after `set -eu`, add the same `note_build() { … }` function, word for word, as in Step 1. Then find:

```sh
if curl -fsS -o /dev/null "$URL/manifest-$BUILD.plist"; then
  echo "Published build $BUILD: open $URL/ on the phone and tap Install."
```

and add one line right after the `echo`:

```sh
  note_build "$NAME" "$BUNDLE" "$BUILD" "$COMMIT" "$BRANCH" "itms-services://?action=download-manifest&url=$URL/manifest-$BUILD.plist"
```

Its cable path exits before this, so a cable install leaves no note.

- [ ] **Step 4: Check the scripts parse, and that the note reads**

Run:

```sh
sh -n macos/ship-phone.sh && sh -n ~/.claude/skills/install-ios-build/ship-ios.sh && echo parse ok
T=$(mktemp -d); mkdir -p "$T/Library/Application Support/Lostty/notifications/inbox"
sed -n '/^note_build()/,/^}/p' macos/ship-phone.sh > "$T/fn.sh"
HOME="$T" TMUX_PANE= sh -c ". '$T/fn.sh'; note_build Lostty com.lawliang.lostty-mobile 202610131331 cf0a354c9 skins 'itms-services://?action=download-manifest&url=https://mac.ts.net/manifest-202610131331.plist'"
ls -a "$T/Library/Application Support/Lostty/notifications/inbox"; cat "$T/Library/Application Support/Lostty/notifications/inbox"/build-*.json; echo
```

Expected: `parse ok`; the inbox has exactly one `build-<UUID>.json` and no "." file; the JSON has `"type": "build"`, the six values, `"project"` = `lostty`, and `null` for `sessionID`, `terminal`, `skin`. `NotesTests.readsTheShipScriptsShape` already decodes this shape.

Run the same with `TMUX_PANE="$TMUX_PANE"` from inside a Lostty terminal. Expected: `sessionID` like `"$3"`, `terminal` the tab's title, and `skin` the pane's skin (if it has one).

Then `rm -rf "$T"`.

---

## Stage 2 (separate plan, after this ships)

Push needs your APNs key, so it gets its own plan once stage 1 works on the phone: the push entitlement and explicit App ID, Phone Access "Set Up Push", the APNs sender behind `PhoneNotifier`, the phone's device token in its `.phone` drop, the 5-minute re-push and idle/attached skips (`NoteLog.shouldPush`), and the app icon badge.
