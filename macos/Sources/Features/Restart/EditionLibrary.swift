#if os(macOS)
import Foundation

/// The built editions this Mac can switch between (AGENTS.md → Editions).
/// install.sh keeps a copy of every edition it installs, Core included, in
/// `Application Support/Lostty/Editions/<name>.app`. Switching swaps one
/// into /Applications/Lostty.app the way install.sh does, then restarts
/// into it keeping every terminal, so going back to Core never needs a build.
enum EditionLibrary {
    struct Entry: Equatable {
        let edition: LosttyEdition
        let url: URL
        /// "0.4 beta 3", or the plain version.
        let version: String?
        let commit: String?
    }

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty/Editions", isDirectory: true)
    }

    /// Every built edition in `folder`, Core first, then by name. A copy
    /// whose Info.plist names another edition than its file is skipped: the
    /// name in the build is the truth, and a misfiled copy isn't offered.
    static func entries(in folder: URL = folder) -> [Entry] {
        let apps = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let found: [Entry] = apps.compactMap { url in
            guard url.pathExtension == "app",
                  let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
            else { return nil }
            let edition = LosttyEdition(info: info)
            guard edition.name == url.deletingPathExtension().lastPathComponent else { return nil }
            return Entry(edition: edition, url: url,
                         version: LosttyChannel.displayVersion(info: info),
                         commit: info["LosttyBuildCommit"] as? String)
        }
        return ordered(found)
    }

    static func ordered(_ entries: [Entry]) -> [Entry] {
        entries.sorted { a, b in
            if a.edition.isCore != b.edition.isCore { return a.edition.isCore }
            return a.edition.name < b.edition.name
        }
    }

    /// The menu lists editions only when there's somewhere to go: this is
    /// the installed Lostty, no other build is waiting to restart into, and
    /// the library holds an edition other than the one running.
    @MainActor static var available: Bool {
        LosttyRestart.bundlePath == PreviousBuild.installedURL.path && !BundleWatch.shared.updateReady
            && offersSwitch(entries(), current: .current)
    }

    static func offersSwitch(_ entries: [Entry], current: LosttyEdition) -> Bool {
        entries.contains { $0.edition != current }
    }

    /// The menu line for one edition: "Orca  0.4 beta 3 (abc1234)".
    static func title(_ entry: Entry) -> String {
        let build = [entry.version, entry.commit.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        return build.isEmpty ? entry.edition.title : "\(entry.edition.title)  \(build)"
    }

    /// Puts `entry` in /Applications/Lostty.app and keeps the build it
    /// replaces as "Lostty (previous).app", as install.sh does, so Go Back to
    /// Previous Build still works. The copy goes in under a temporary name
    /// and is renamed into place, so nothing ever sees half a build.
    static func install(_ entry: Entry,
                        installed: URL = PreviousBuild.installedURL,
                        previous: URL = PreviousBuild.previousURL) throws {
        let fm = FileManager.default
        let installing = installed.deletingLastPathComponent().appendingPathComponent("Lostty (installing).app")
        try? fm.removeItem(at: installing)
        try fm.copyItem(at: entry.url, to: installing)
        if fm.fileExists(atPath: installed.path) {
            try? fm.removeItem(at: previous)
            try fm.moveItem(at: installed, to: previous)
        }
        try fm.moveItem(at: installing, to: installed)
    }
}
#endif
