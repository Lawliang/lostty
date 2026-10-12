import Foundation

/// The Mac the phone connects to: filled in by pairing, or typed under
/// Advanced. Stored in UserDefaults as JSON under `defaultsKey`; a JSON
/// string is accepted too, so a launch argument (`-LosttyRemoteHost
/// '{"host":…}'`) can set it. Settings saved by older builds (with a
/// terminfoDir) still load.
public struct RemoteHostSettings: Codable, Equatable, Sendable {
    public static let defaultsKey = "LosttyRemoteHost"

    public var host: String
    public var port: Int
    public var user: String
    /// The Mac's Tailscale address, tried when `host` (its name) can't be reached.
    public var fallbackHost: String?
    /// When this phone was paired with the Mac; nil for typed settings.
    public var pairedAt: Date?

    public init(host: String = "", port: Int = 22, user: String = "", fallbackHost: String? = nil, pairedAt: Date? = nil) {
        self.host = host
        self.port = port
        self.user = user
        self.fallbackHost = fallbackHost
        self.pairedAt = pairedAt
    }

    /// The settings pairing with `payload` produces.
    public static func paired(with payload: PairingPayload, at date: Date) -> RemoteHostSettings {
        RemoteHostSettings(host: payload.name, port: 22, user: payload.user, fallbackHost: payload.ip, pairedAt: date)
    }

    public var paired: Bool { pairedAt != nil }

    /// What to fix before connecting, or nil.
    public var problem: String? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty { return "Enter the Mac's address." }
        if host.contains(where: \.isWhitespace) { return "The Mac's address can't contain spaces." }
        if user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter your user name on the Mac." }
        if !(1...65535).contains(port) { return "The port must be between 1 and 65535." }
        return nil
    }

    /// The Mac's name, then its address; empty while `problem` is set.
    public var remoteHosts: [RemoteHost] {
        guard problem == nil else { return [] }
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var hosts = [RemoteHost(host: primary, port: port, user: user)]
        if let fallback = fallbackHost?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty, fallback != primary, !fallback.contains(where: \.isWhitespace) {
            hosts.append(RemoteHost(host: fallback, port: port, user: user))
        }
        return hosts
    }

    public var remoteHost: RemoteHost? { remoteHosts.first }

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
