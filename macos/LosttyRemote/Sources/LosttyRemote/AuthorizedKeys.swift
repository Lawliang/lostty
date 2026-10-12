import Foundation

/// The phone keys Lostty adds to ~/.ssh/authorized_keys, one line each:
/// "restrict,pty <type> <base64> lostty-phone:<id>". `restrict` turns off
/// port, agent and X11 forwarding; `pty` gives the terminal back. Lines
/// Lostty didn't write are never changed, byte for byte.
public enum AuthorizedKeys {
    public static let tag = "lostty-phone:"

    public struct Phone: Equatable, Sendable {
        public var id: String
        /// "<type> <base64>"
        public var key: String

        public init(id: String, key: String) {
            self.id = id
            self.key = key
        }
    }

    public static func line(key: String, id: String) -> String {
        "restrict,pty \(key) \(tag)\(id)"
    }

    /// The phones Lostty added, in file order.
    public static func phones(in text: String) -> [Phone] {
        lines(text).compactMap(phone(in:))
    }

    /// Where a phone key stands in an authorized_keys file.
    public enum Status: Equatable, Sendable {
        /// No line mentions the key.
        case absent
        /// An active line Lostty wrote (its id).
        case lostty(String)
        /// Only lines Lostty didn't write mention it: hand-added, commented
        /// out, or with options like `from=`.
        case foreign
    }

    public static func status(of key: String, in text: String) -> Status {
        let fields = key.split(separator: " ")
        guard fields.count == 2 else { return .absent }
        let all = lines(text)
        if let phone = all.compactMap(phone(in:)).first(where: { $0.key == key }) {
            return .lostty(phone.id)
        }
        return all.contains { mentions($0, base64: fields[1]) } ? .foreign : .absent
    }

    /// `text` plus a line for `key`; nil when the key's base64 is already on
    /// some line (see `status(of:in:)`).
    public static func adding(key: String, id: String, to text: String) -> String? {
        guard status(of: key, in: text) == .absent else { return nil }
        return appending(key: key, id: id, to: text)
    }

    /// `text` without every line Lostty didn't write that mentions `key`,
    /// plus a Lostty line for it. sshd uses the first matching line, so a
    /// hand line would otherwise keep `restrict` from applying.
    public static func replacingForeign(key: String, id: String, in text: String) -> String {
        let fields = key.split(separator: " ")
        guard fields.count == 2 else { return text }
        let kept = lines(text).filter { phone(in: $0) != nil || !mentions($0, base64: fields[1]) }
        return appending(key: key, id: id, to: kept.joined(separator: "\n"))
    }

    private static func appending(key: String, id: String, to text: String) -> String {
        let base = text.isEmpty || text.unicodeScalars.last == "\n" ? text : text + "\n"
        return base + line(key: key, id: id) + "\n"
    }

    private static func mentions(_ line: String, base64: Substring) -> Bool {
        line.split(whereSeparator: \.isWhitespace).contains(base64)
    }

    /// `text` without the line for phone `id`.
    public static func removing(id: String, from text: String) -> String {
        lines(text).filter { phone(in: $0)?.id != id }.joined(separator: "\n")
    }

    /// `text` without any line Lostty added.
    public static func removingAll(from text: String) -> String {
        lines(text).filter { phone(in: $0) == nil }.joined(separator: "\n")
    }

    /// A line exactly as `line(key:id:)` writes it, else nil.
    /// Trailing spaces, tabs and a CR (a file edited on Windows) are ignored.
    private static func phone(in line: String) -> Phone? {
        var end = line.unicodeScalars.endIndex
        let blanks: Set<Unicode.Scalar> = [" ", "\t", "\r"]
        while end > line.unicodeScalars.startIndex {
            let before = line.unicodeScalars.index(before: end)
            guard blanks.contains(line.unicodeScalars[before]) else { break }
            end = before
        }
        let trimmed = String(line.unicodeScalars[..<end])
        let fields = trimmed.split(separator: " ")
        guard fields.count == 4, fields[0] == "restrict,pty", fields[3].hasPrefix(tag) else { return nil }
        let id = fields[3].dropFirst(tag.count)
        guard !id.isEmpty, !id.contains("\r") else { return nil }
        return Phone(id: String(id), key: "\(fields[1]) \(fields[2])")
    }

    /// Split on unicode scalars: a Character split would not break at "\r\n",
    /// merging a CRLF line with the next one.
    private static func lines(_ text: String) -> [String] {
        text.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String(String.UnicodeScalarView($0)) }
    }
}

/// Reads and atomically rewrites an authorized_keys file: a temp file in the
/// same directory, 0600, renamed over the original. A symlink (a dotfiles
/// repo) is followed, so the link itself is kept.
public struct AuthorizedKeysFile: Sendable {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    #if os(macOS)
    public static var standard: AuthorizedKeysFile {
        AuthorizedKeysFile(url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/authorized_keys"))
    }
    #endif

    public func read() throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func write(_ text: String) throws {
        let target = url.resolvingSymlinksInPath()
        let dir = target.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let temp = dir.appendingPathComponent(".authorized_keys.lostty-\(UUID().uuidString)")
        guard FileManager.default.createFile(
            atPath: temp.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        guard rename(temp.path, target.path) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            try? FileManager.default.removeItem(at: temp)
            throw POSIXError(code)
        }
    }
}
