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
        _ id: String = "$1", claude: ClaudeActivity? = .waiting, action: String? = "Run the iOS tests",
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
        let changed = log.sync(sessions: [session()], now: now, newID: ids.next)
        #expect(changed)
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
        let changed = log.sync(sessions: [session(claude: .working), session("$2", claude: nil)], now: now)
        #expect(!changed)
        #expect(log.notes.isEmpty)
    }

    @Test func answeringItReadsIt() {
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        let changed = log.sync(sessions: [session(claude: .working)], now: now.addingTimeInterval(5))
        #expect(changed)
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
        log.sync(sessions: [session(action: "Push to main")], now: now.addingTimeInterval(60), newID: ids.next)
        #expect(log.notes.count == 1)
        #expect(log.notes[0].id == id)
        #expect(!log.notes[0].read)
        #expect(log.notes[0].body == "Allow? Push to main")
        #expect(log.notes[0].updated == now.addingTimeInterval(60))
        #expect(log.notes[0].created == now)
    }

    @Test func theQuestionClearingAsTheWaitEndsKeepsTheNote() {
        // The Mac clears the question and the waiting state separately: a
        // listing can land between them.
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        log.apply(.readAll, now: now)
        let changed = log.sync(sessions: [session(action: nil)], now: now.addingTimeInterval(1))
        #expect(!changed)
        #expect(log.notes[0].body == "Allow? Run the iOS tests")
        #expect(log.notes[0].read)
        #expect(log.notes[0].updated == now)
    }

    @Test func aRelistWhileStillWaitingChangesNothing() {
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        let changed = log.sync(sessions: [session()], now: now.addingTimeInterval(1))
        #expect(!changed)
    }

    @Test func aNewQuestionWhileStillWaitingRevivesIt() {
        var log = NoteLog()
        log.sync(sessions: [session()], now: now)
        log.apply(.readAll, now: now)
        log.sync(sessions: [session(action: "Delete the build folder")], now: now.addingTimeInterval(3))
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
        let changed = again.sync(sessions: [session()], now: now.addingTimeInterval(30))
        #expect(!changed)
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
