import Foundation

/// Host keys pinned on first connect ("trust on first use"). One line per
/// host: "<host>:<port> <key in OpenSSH form>". A key that differs from the
/// pin is reported, never re-pinned: the user removes the line by hand if
/// the Mac's key really changed.
public final class KnownHosts: @unchecked Sendable {
    public enum Verdict: Equatable {
        case trusted
        case unknown
        case changed(pinned: String)
    }

    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func verdict(host: String, port: Int, key: String) -> Verdict {
        lock.lock()
        defer { lock.unlock() }
        guard let pinned = load()[Self.label(host, port)] else { return .unknown }
        return pinned == key ? .trusted : .changed(pinned: pinned)
    }

    /// Pins `key` for the host unless a key is already pinned.
    public func trust(host: String, port: Int, key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var pins = load()
        let label = Self.label(host, port)
        guard pins[label] == nil else { return }
        pins[label] = key
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = pins.keys.sorted().map { "\($0) \(pins[$0]!)" }.joined(separator: "\n") + "\n"
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func label(_ host: String, _ port: Int) -> String { "\(host):\(port)" }

    private func load() -> [String: String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [:] }
        var pins: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let space = line.firstIndex(of: " ") else { continue }
            pins[String(line[..<space])] = String(line[line.index(after: space)...])
        }
        return pins
    }
}
