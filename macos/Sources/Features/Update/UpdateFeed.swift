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
}
