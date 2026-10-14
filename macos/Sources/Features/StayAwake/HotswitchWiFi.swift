#if os(macOS)
import CoreGraphics
import CoreWLAN
import Foundation
import LosttyRemote
import Security

/// Hotswitch's hands on the Mac's Wi-Fi, through CoreWLAN. Network names
/// need Location. Joining is slow (a scan first), so callers stay off the
/// main thread for `join` and `sightings`.
struct HotswitchWiFi: Sendable {
    private var interface: CWInterface? { CWWiFiClient.shared().interface() }

    /// The Wi-Fi network now; nil when on none.
    func network() -> String? { interface?.ssid() }

    /// Networks this Mac has joined before, most preferred first.
    func knownNetworks() -> [String] {
        let profiles = interface?.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
        return profiles.compactMap(\.ssid)
    }

    /// Joins `name` with `password`. Nil when joined, else why not. A
    /// failed join leaves the Mac on no network.
    func join(_ name: String, password: String) -> String? {
        guard let interface else { return "no Wi-Fi interface" }
        let found: Set<CWNetwork>
        do {
            found = try interface.scanForNetworks(withName: name)
        } catch {
            return "scan failed: \(Self.describe(error))"
        }
        guard let network = found.max(by: { $0.rssiValue < $1.rssiValue }) else {
            return "\(name) isn't visible (is Allow Others to Join on?)"
        }
        do {
            try interface.associate(to: network, password: password)
            return nil
        } catch {
            return "\(Self.describe(error)), screen \(Self.screenLocked() ? "locked" : "unlocked")"
        }
    }

    /// Leaves the current network; macOS rejoins known Wi-Fi by itself.
    func leave() { interface?.disassociate() }

    /// Known networks in range, except `hotspot`.
    func sightings(excluding hotspot: String) -> [HotswitchModel.Sighting] {
        let known = Set(knownNetworks())
        guard let found = try? interface?.scanForNetworks(withName: nil) else { return [] }
        return found.compactMap { network in
            guard let name = network.ssid, name != hotspot, known.contains(name) else { return nil }
            return HotswitchModel.Sighting(name: name, rssi: network.rssiValue)
        }
    }

    /// One fetch of Apple's captive check: true when the internet works.
    static func probe(_ session: URLSession) async -> Bool {
        var request = URLRequest(url: URL(string: "https://captive.apple.com/hotspot-detect.html")!)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        guard let (data, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
            && String(decoding: data, as: UTF8.self).contains("Success")
    }

    static func screenLocked() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private static func describe(_ error: Error) -> String {
        "\(error.localizedDescription) (\((error as NSError).code))"
    }
}

/// The hotspot's password, kept by Lostty: CoreWLAN can't use the one
/// macOS saved.
enum HotspotPassword {
    private static let service = "Lostty hotspot"

    static func read(_ network: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: network,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func exists(_ network: String) -> Bool { read(network) != nil }

    @discardableResult
    static func save(_ password: String, for network: String) -> Bool {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: network,
        ]
        SecItemDelete(match as CFDictionary)
        var item = match
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrLabel as String] = "Lostty: \(network) hotspot"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
#endif
