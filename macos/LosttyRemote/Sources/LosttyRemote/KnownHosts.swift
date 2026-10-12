import Foundation

/// Host keys pinned on first connect ("trust on first use"). One line per
/// host: "<host>:<port> <key in OpenSSH form>". A key that differs from the
/// pin is reported, never re-pinned: the user forgets the pin (`forget`) if
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
        try save(pins)
    }

    /// Pins `key` for the host, replacing any earlier pin: pairing hands the
    /// phone the Mac's key, so there is nothing to trust on first use.
    public func pin(host: String, port: Int, key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var pins = load()
        pins[Self.label(host, port)] = key
        try save(pins)
    }

    private func save(_ pins: [String: String]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = pins.keys.sorted().map { "\($0) \(pins[$0]!)" }.joined(separator: "\n") + (pins.isEmpty ? "" : "\n")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Removes the pin for the host, so the next connect pins whatever key it
    /// offers. For when the Mac's host key really changed.
    public func forget(host: String, port: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        var pins = load()
        guard pins.removeValue(forKey: Self.label(host, port)) != nil else { return }
        try save(pins)
    }

    /// "host:port", with IPv6 hosts bracketed ("[fd7a::1]:22") so the port
    /// can't be read as part of the address.
    private static func label(_ host: String, _ port: Int) -> String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

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
