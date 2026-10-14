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

    /// The kept notes; none when there's no file yet. One that doesn't read
    /// (a newer Lostty wrote it, say) is moved aside, not overwritten by the
    /// next save, and the notes start over.
    func loadNotes() -> NoteLog {
        guard let data = try? Data(contentsOf: notesURL) else { return NoteLog() }
        if let log = try? NoteLog.decode(data) { return log }
        let aside = root.appendingPathComponent("notes.json.unreadable-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: notesURL, to: aside)
        Self.logger.error("moved unreadable notes aside: \(aside.lastPathComponent, privacy: .public)")
        return NoteLog()
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
    /// Close-on-exec: a terminal started meanwhile (its tmux server, which
    /// outlives Lostty) must not inherit it and hold it after Lostty quits.
    func lock() -> Int32? {
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
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
