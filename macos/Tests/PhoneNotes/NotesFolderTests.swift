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

    @Test func anUnreadableNotesFileIsMovedAsideNotOverwritten() throws {
        let folder = try folder()
        try Data("{\"notes\": 7}".utf8).write(to: folder.notesURL)
        #expect(folder.loadNotes() == NoteLog())
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.root.path)
        #expect(names.contains { $0.hasPrefix("notes.json.unreadable-") })
        #expect(!names.contains("notes.json"))
    }

    /// A terminal started while Lostty holds the lock (its tmux server, say)
    /// must not keep holding it after Lostty quits.
    @Test func theLockDoesNotLeakIntoChildProcesses() throws {
        let folder = try folder()
        let fd = try #require(folder.lock())
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sleep"), strdup("5"), nil]
        defer { argv.forEach { free($0) } }
        #expect(posix_spawn(&pid, "/bin/sleep", nil, nil, argv, environ) == 0)
        defer {
            kill(pid, SIGKILL)
            var status: Int32 = 0
            waitpid(pid, &status, 0)
        }
        close(fd)
        let again = folder.lock()
        #expect(again != nil)
        if let again { close(again) }
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
