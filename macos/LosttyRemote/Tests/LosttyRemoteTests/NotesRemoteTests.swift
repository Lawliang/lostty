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

    @Test func unreadableNotesAreAnErrorNotAnEmptyInbox() throws {
        #expect(throws: NotesRemote.Unreadable.self) { try NotesRemote.notes("{\"notes\": 7}") }
        #expect(try NotesRemote.notes("") == NoteLog())
    }

    @Test func garbageIsNotNotes() {
        #expect(NotesRemote.parseNotes("cat: permission denied") == nil)
    }
}
