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

    /// `text` plus a line for `key`; nil when the key's base64 is already on
    /// some line (allowed before, by Lostty or by hand).
    public static func adding(key: String, id: String, to text: String) -> String? {
        let fields = key.split(separator: " ")
        guard fields.count == 2 else { return nil }
        let present = lines(text).contains { line in
            line.split(whereSeparator: \.isWhitespace).contains(fields[1])
        }
        guard !present else { return nil }
        let base = text.isEmpty || text.unicodeScalars.last == "\n" ? text : text + "\n"
        return base + line(key: key, id: id) + "\n"
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
    private static func phone(in line: String) -> Phone? {
        let fields = line.split(separator: " ")
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
