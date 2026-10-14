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

    /// `notes.json` didn't read as notes (a newer Mac, say): not an empty inbox.
    public struct Unreadable: Error {}

    /// `readCommand`'s output: no notes yet when empty.
    public static func notes(_ text: String) throws -> NoteLog {
        guard let log = parseNotes(text) else { throw Unreadable() }
        return log
    }

    /// `readCommand`'s output: no notes yet when empty, nil when unreadable.
    public static func parseNotes(_ text: String) -> NoteLog? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return NoteLog() }
        return try? NoteLog.decode(Data(trimmed.utf8))
    }
}
