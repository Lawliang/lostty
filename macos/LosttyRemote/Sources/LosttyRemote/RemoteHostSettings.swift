import Foundation

/// The Mac the phone connects to, as typed in Settings. Stored in
/// UserDefaults as JSON under `defaultsKey`; a JSON string is accepted too,
/// so a launch argument (`-LosttyRemoteHost '{"host":…}'`) can set it.
public struct RemoteHostSettings: Codable, Equatable, Sendable {
    public static let defaultsKey = "LosttyRemoteHost"
    public static let defaultTerminfoDir = "/Applications/Lostty.app/Contents/Resources/terminfo"

    public var host: String
    public var port: Int
    public var user: String
    /// Lostty.app's terminfo directory on the Mac (xterm-ghostty).
    public var terminfoDir: String

    public init(host: String = "", port: Int = 22, user: String = "", terminfoDir: String = RemoteHostSettings.defaultTerminfoDir) {
        self.host = host
        self.port = port
        self.user = user
        self.terminfoDir = terminfoDir
    }

    /// What to fix before connecting, or nil.
    public var problem: String? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty { return "Enter the Mac's address." }
        if host.contains(where: \.isWhitespace) { return "The Mac's address can't contain spaces." }
        if user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter your user name on the Mac." }
        if !(1...65535).contains(port) { return "The port must be between 1 and 65535." }
        return nil
    }

    public var remoteHost: RemoteHost? {
        guard problem == nil else { return nil }
        let dir = terminfoDir.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteHost(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            user: user.trimmingCharacters(in: .whitespacesAndNewlines),
            terminfoDir: dir.isEmpty ? Self.defaultTerminfoDir : dir)
    }

    public static func load(from defaults: UserDefaults) -> RemoteHostSettings {
        let data = defaults.data(forKey: defaultsKey) ?? defaults.string(forKey: defaultsKey).map { Data($0.utf8) }
        guard let data, let settings = try? JSONDecoder().decode(RemoteHostSettings.self, from: data) else {
            return RemoteHostSettings()
        }
        return settings
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
