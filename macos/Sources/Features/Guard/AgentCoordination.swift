#if os(macOS)
import Foundation

/// Lostty's agent coordination (the guard, and what's built on it) is off
/// unless `~/.config/lostty/guard.json` says `"enabled": true`, read the
/// way the CLI reads it (src/cli/guard/config.zig). Off, the app behaves as
/// if it were never built: nothing starts, nothing shows, and the hook
/// wording is what it was before. Read once at launch: a change takes
/// effect when Lostty restarts.
enum AgentCoordination {
    static let isOn: Bool = isOn(home: FileManager.default.homeDirectoryForCurrentUser)

    static func isOn(home: URL) -> Bool {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".config/lostty/guard.json")) else { return false }
        return isOn(json: data)
    }

    /// Only an exact top-level boolean `true`; a number or a string is off.
    static func isOn(json data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["enabled"] as? NSNumber else { return false }
        return CFGetTypeID(value) == CFBooleanGetTypeID() && value.boolValue
    }
}
#endif
