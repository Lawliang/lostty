#if os(macOS)
import Foundation

/// Which edition of Lostty Beta this is: Core, the owner's own Lostty, or
/// Core with one harness integrated on an `edition/<name>` branch
/// (AGENTS.md → Editions). Read from the signed Info.plist.
struct LosttyEdition: Equatable, Hashable {
    static let infoKey = "LosttyEdition"
    static let core = LosttyEdition(name: "core")

    /// Lowercase letters, digits and dashes, as in the branch name.
    let name: String

    /// A missing, empty, unexpanded or malformed value is Core, so a build
    /// that forgets the setting is the owner's own Lostty.
    init(name: String?) {
        self.name = name.flatMap(Self.normalized) ?? "core"
    }

    init(info: [String: Any]?) {
        self.init(name: info?[Self.infoKey] as? String)
    }

    static let current = LosttyEdition(info: Bundle.main.infoDictionary)

    var isCore: Bool { name == "core" }

    /// "orca" → "Orca", "agent-teams" → "Agent Teams".
    var title: String {
        name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// What follows the app's name where the build shows: nothing for Core.
    var suffix: String { isCore ? "" : " · \(title)" }

    static func normalized(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !name.isEmpty, name.first != "-", name.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return name
    }
}
#endif
