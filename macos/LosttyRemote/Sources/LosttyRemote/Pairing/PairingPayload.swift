import Foundation
import Network
import NIOSSH

/// What the Mac's QR code carries: the Mac's Tailscale name and address, who
/// to sign in as, the Mac's SSH host key (pinned, so the phone never trusts
/// on first use), and the one-time secret for the pairing link.
public struct PairingPayload: Equatable, Sendable {
    /// MagicDNS name, without the trailing dot.
    public var name: String
    /// Tailscale IPv4 address, for when the name doesn't resolve.
    public var ip: String
    public var user: String
    /// The Mac's ed25519 host key, standard base64 (the second field of
    /// /etc/ssh/ssh_host_ed25519_key.pub).
    public var hostKey: String
    /// 32 random bytes.
    public var secret: Data

    public init(name: String, ip: String, user: String, hostKey: String, secret: Data) throws {
        self.name = name
        self.ip = ip
        self.user = user
        self.hostKey = hostKey
        self.secret = secret
        guard isValid else { throw PairingError.invalidLink }
    }

    /// "ssh-ed25519 AAAA…", the form KnownHosts stores.
    public var hostKeyLine: String { "ssh-ed25519 \(hostKey)" }

    public static func newSecret() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "lostty"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "ip", value: ip),
            URLQueryItem(name: "user", value: user),
            URLQueryItem(name: "hostkey", value: Base64URL.encode(Data(base64Encoded: hostKey) ?? Data())),
            URLQueryItem(name: "secret", value: Base64URL.encode(secret)),
        ]
        return components.url!
    }

    public init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "lostty", components.host == "pair"
        else { throw PairingError.invalidLink }
        var items: [String: String] = [:]
        for item in components.queryItems ?? [] { items[item.name] = item.value }
        guard items["v"] == "1",
              let name = items["name"], let ip = items["ip"], let user = items["user"],
              let hostKey = items["hostkey"].flatMap(Base64URL.decode),
              let secret = items["secret"].flatMap(Base64URL.decode)
        else { throw PairingError.invalidLink }
        try self.init(name: name, ip: ip, user: user, hostKey: hostKey.base64EncodedString(), secret: secret)
    }

    private var isValid: Bool {
        !name.isEmpty && name.count <= 253 && !name.contains(where: \.isWhitespace)
            && IPv4Address(ip) != nil
            && !user.isEmpty && !user.contains(where: \.isWhitespace)
            && secret.count == 32
            && (try? NIOSSHPublicKey(openSSHPublicKey: hostKeyLine)) != nil
    }
}

/// base64url without padding, so the QR's URL needs no percent-escapes.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
