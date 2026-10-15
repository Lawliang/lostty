#if os(macOS)
import Foundation

/// The build install.sh replaced, kept as "Lostty (previous).app":
/// Go Back to Previous Build swaps the two and restarts.
enum PreviousBuild {
    static let installedURL = URL(fileURLWithPath: "/Applications/Lostty.app")
    static let previousURL = URL(fileURLWithPath: "/Applications/Lostty (previous).app")

    /// This is the installed Lostty, not about to be replaced, and an older
    /// one is there to go back to (after going back, the newer one sits
    /// there instead: going "back" would go forward).
    @MainActor static var available: Bool {
        LosttyRestart.bundlePath == installedURL.path && !BundleWatch.shared.updateReady
            && goesBack(previous: previousURL, installed: installedURL)
    }

    /// `previous` is an older build than `installed` (by their executables).
    static func goesBack(previous: URL, installed: URL) -> Bool {
        func modified(_ app: URL) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: app.appendingPathComponent("Contents/MacOS/lostty").path))?[.modificationDate] as? Date
        }
        guard let old = modified(previous), let new = modified(installed) else { return false }
        return old < new
    }

    static func swap(installed: URL = installedURL, previous: URL = previousURL) throws {
        let fm = FileManager.default
        let aside = installed.deletingLastPathComponent().appendingPathComponent("Lostty (swap).app")
        try? fm.removeItem(at: aside)
        try fm.moveItem(at: installed, to: aside)
        try fm.moveItem(at: previous, to: installed)
        try fm.moveItem(at: aside, to: previous)
    }
}
#endif
