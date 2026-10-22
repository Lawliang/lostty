#if os(macOS)
import Foundation

/// Which Lostty this is: stable, the finished build people download, or
/// the beta, the same main with unfinished features on (CONTRIBUTING.md →
/// Stable and beta). Read from the signed Info.plist, so a stable copy
/// can't be switched to the beta.
enum LosttyChannel: String, Equatable {
    case stable
    case beta

    static let infoKey = "LosttyChannel"
    static let betaNumberKey = "LosttyBetaNumber"

    /// Only "beta" is the beta: an empty, unknown or unexpanded value is
    /// stable, so a build that forgets the setting ships the finished one.
    init(info: [String: Any]?) {
        self = (info?[Self.infoKey] as? String) == Self.beta.rawValue ? .beta : .stable
    }

    static let current = LosttyChannel(info: Bundle.main.infoDictionary)

    var isBeta: Bool { self == .beta }
    /// What the app calls itself where the build shows: the About window.
    var appName: String { isBeta ? "Lostty Beta" : "Lostty" }
    /// The context handoff: a long conversation hands off to a fresh one.
    var handsOff: Bool { isBeta }
    /// The turn observer, which summarizes each agent turn. Off in every
    /// build since its one view, the axolotl's bubble, went; on again once
    /// it has a new home.
    var observesTurns: Bool { false }
    /// Branches in the sidebar.
    var hasBranches: Bool { isBeta }
    /// The canvas: an infinite whiteboard window of terminal cards.
    var hasCanvas: Bool { isBeta }

    /// The version as the About window shows it: "0.4", or "0.4 beta 2"
    /// for a released beta (`LOSTTY_BETA_NUMBER`).
    static func displayVersion(info: [String: Any]?) -> String? {
        guard let version = info?["CFBundleShortVersionString"] as? String else { return nil }
        guard LosttyChannel(info: info).isBeta,
              let number = info?[betaNumberKey] as? String, Int(number) != nil else { return version }
        return "\(version) beta \(number)"
    }
}
#endif
