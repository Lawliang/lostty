import Foundation

/// Where this copy of Lostty looks for updates. `release.sh` builds the
/// feed into a release (`LosttyUpdateFeed`); a build made on a Mac
/// (install.sh, Debug) has none, so a release never replaces it. Only
/// Lostty's own GitHub feed counts: never Ghostty's.
enum UpdateFeed {
    static let infoKey = "LosttyUpdateFeed"
    static let prefix = "https://github.com/Lawliang/lostty/"

    static func url(info: [String: Any]?) -> String? {
        guard let feed = info?[infoKey] as? String, feed.hasPrefix(prefix),
              URL(string: feed) != nil else { return nil }
        return feed
    }

    static var current: String? { url(info: Bundle.main.infoDictionary) }

    /// Shown by Check for Updates… in a copy with no feed.
    static let localBuildMessage = "This copy of Lostty was built on this Mac; it updates with install.sh."

    struct Schedule: Equatable {
        var checks: Bool
        var downloads: Bool
    }

    /// No feed: never check. A feed: check daily and ask first, unless the
    /// `auto-update` config says otherwise.
    static func schedule(hasFeed: Bool, autoUpdate: Ghostty.Config.AutoUpdate?) -> Schedule {
        guard hasFeed else { return Schedule(checks: false, downloads: false) }
        switch autoUpdate {
        case .off: return Schedule(checks: false, downloads: false)
        case .download: return Schedule(checks: true, downloads: true)
        case .check, nil: return Schedule(checks: true, downloads: false)
        }
    }

    enum CheckAction: Equatable {
        case sparkle
        case explainLocalBuild
    }

    static func checkAction(feed: String?) -> CheckAction {
        feed == nil ? .explainLocalBuild : .sparkle
    }
}
