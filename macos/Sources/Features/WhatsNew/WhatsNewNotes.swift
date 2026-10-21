#if os(macOS)
import Foundation

/// What a build brings, for the What's New card and the update banner: the
/// first entry of WhatsNew.md, the build's commits (BuildNotes.md, from
/// install.sh), or an update's release notes.
struct WhatsNewNotes: Equatable {
    var headline: String
    var summary = ""
    var bullets: [String] = []

    /// The first entry of WhatsNew.md: a `# ` headline, a paragraph, then
    /// `- ` bullets (an indented line carries on the bullet above). HTML
    /// comments are left out.
    static func firstEntry(of text: String) -> WhatsNewNotes? {
        var notes: WhatsNewNotes?
        var summary: [String] = []
        var inComment = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if inComment {
                if line.contains("-->") { inComment = false }
                continue
            }
            if line.hasPrefix("<!--") {
                inComment = !line.contains("-->")
                continue
            }
            if line.hasPrefix("# ") {
                if notes != nil { break }
                notes = WhatsNewNotes(headline: String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if notes == nil || line.isEmpty {
                continue
            } else if let bullet = bullet(line) {
                notes?.bullets.append(bullet)
            } else if raw.first?.isWhitespace == true, var bullets = notes?.bullets, let last = bullets.popLast() {
                notes?.bullets = bullets + [last + " " + line]
            } else if notes?.bullets.isEmpty == true {
                summary.append(line)
            }
        }
        notes?.summary = summary.joined(separator: " ")
        return notes
    }

    /// The `- ` lines of BuildNotes.md.
    static func bullets(ofList text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .compactMap { bullet($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// The `<li>` items of an update's release notes (release.sh's feed).
    static func bullets(ofHTML html: String) -> [String] {
        guard let items = try? NSRegularExpression(pattern: "<li>(.*?)</li>", options: [.dotMatchesLineSeparators])
        else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return items.matches(in: html, range: range).compactMap { match in
            Range(match.range(at: 1), in: html).map { unescape(String(html[$0])) }
        }.filter { !$0.isEmpty }
    }

    private static func bullet(_ line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        let text = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A build as the What's New card sees it: what identifies it across
/// launches, and what it brings.
struct WhatsNewBuild: Equatable {
    /// Its commit (install.sh and release.sh stamp it) and, for a release,
    /// its build number (what an update's feed names). None for a Debug
    /// build, which never shows a card.
    var ids: [String]
    /// The first entry of its WhatsNew.md.
    var entry: WhatsNewNotes?
    /// Its commits since the build before it, or an update's release notes.
    var changes: [String] = []
    /// A headline for `changes`: an update's title ("Lostty 0.5").
    var title: String?

    static let commitKey = "LosttyBuildCommit"
    static let notesFile = "WhatsNew"
    static let changesFile = "BuildNotes"

    static func ids(info: [String: Any]?) -> [String] {
        var ids: [String] = []
        if let commit = info?[commitKey] as? String, !commit.isEmpty, !commit.hasPrefix("$(") {
            ids.append("commit:\(commit)")
        }
        if UpdateFeed.url(info: info) != nil, let build = info?["CFBundleVersion"] as? String, !build.isEmpty {
            ids.append("version:\(build)")
        }
        return ids
    }

    /// The build in the app bundle at `path`, read from its files (Bundle
    /// caches a path's bundle, so the one installed over this Lostty would
    /// read as this one).
    static func installed(atPath path: String) -> WhatsNewBuild {
        let contents = URL(fileURLWithPath: path).appendingPathComponent("Contents")
        let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) as? [String: Any]
        let resources = contents.appendingPathComponent("Resources")
        return WhatsNewBuild(
            ids: ids(info: info),
            entry: (try? String(contentsOf: resources.appendingPathComponent("\(notesFile).md"), encoding: .utf8))
                .flatMap(WhatsNewNotes.firstEntry(of:)),
            changes: (try? String(contentsOf: resources.appendingPathComponent("\(changesFile).md"), encoding: .utf8))
                .map(WhatsNewNotes.bullets(ofList:)) ?? [])
    }

    /// An update Sparkle found: its build number and release notes.
    static func update(version: String, title: String?, description: String?) -> WhatsNewBuild {
        WhatsNewBuild(ids: ["version:\(version)"], entry: nil,
                      changes: description.map(WhatsNewNotes.bullets(ofHTML:)) ?? [], title: title)
    }
}

/// The builds a card has been shown for, and the WhatsNew.md entry it last
/// showed.
struct WhatsNewSeen: Equatable {
    var builds: [String] = []
    var headline: String?

    static let keep = 20

    func hasSeen(_ build: WhatsNewBuild) -> Bool {
        build.ids.contains(where: builds.contains)
    }

    mutating func record(_ build: WhatsNewBuild) {
        builds = Array((build.ids + builds.filter { !build.ids.contains($0) }).prefix(Self.keep))
        if let entry = build.entry { headline = entry.headline }
    }
}

/// The centered card a new window shows.
enum WhatsNewCard: Equatable {
    /// A new build is installed (or downloaded) but this Lostty isn't it yet.
    case restart(WhatsNewNotes)
    /// The first window on a new build.
    case gotIt(WhatsNewNotes)

    var notes: WhatsNewNotes {
        switch self {
        case .restart(let notes), .gotIt(let notes): notes
        }
    }

    /// Restart's, when the new build says nothing about itself.
    static let readyNotes = WhatsNewNotes(
        headline: "A new Lostty is ready",
        summary: "Restart to switch to it. Your terminals stay open.")

    /// What `build` tells: its WhatsNew.md entry if it's one not shown
    /// before, else its commits or release notes.
    static func notes(for build: WhatsNewBuild, seenHeadline: String?) -> WhatsNewNotes? {
        if let entry = build.entry, entry.headline != seenHeadline { return entry }
        guard !build.changes.isEmpty else { return nil }
        return WhatsNewNotes(headline: build.title ?? "What's new in this build", bullets: build.changes)
    }

    /// The card for a new window, and the builds it answers for (record
    /// them, so each build shows a card once): Restart for a new build not
    /// offered yet, else What's New on a build not seen yet. A card for the
    /// waiting build covers this one too, and tells what's in the next.
    static func next(running: WhatsNewBuild, pending: WhatsNewBuild?,
                     seen: WhatsNewSeen) -> (card: WhatsNewCard?, record: [WhatsNewBuild]) {
        if let pending, !pending.ids.isEmpty, !seen.hasSeen(pending) {
            let notes = notes(for: pending, seenHeadline: seen.headline) ?? readyNotes
            return (.restart(notes), [running, pending])
        }
        guard !running.ids.isEmpty, !seen.hasSeen(running) else { return (nil, []) }
        return (notes(for: running, seenHeadline: seen.headline).map(WhatsNewCard.gotIt), [running])
    }
}
#endif
