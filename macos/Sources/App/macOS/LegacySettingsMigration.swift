import Foundation

/// Carries preferences over from before the Lostty rename.
///
/// The Mac app's bundle identifier was `com.lawliang.ghostty-skins` (Debug:
/// `com.lawliang.ghostty-skins.debug`). macOS keys preferences by bundle
/// identifier, so the renamed app starts with an empty domain. Once, before
/// anything reads `UserDefaults`, this copies the old domain's keys into the
/// new one without overwriting keys the new domain already has. The app is
/// not sandboxed, so it can read the old domain.
enum LegacySettingsMigration {
    /// Set in the new domain once the copy has run.
    static let markerKey = "LosttyMigratedFromGhosttySkins"

    /// Keys Ghostty prefixed with its own identifier (such as the Shortcuts
    /// permission) were renamed along with the app.
    static let legacyKeyPrefix = "com.mitchellh.ghostty."
    static let keyPrefix = "com.lawliang.lostty."

    /// The domain the app used before the rename, if `bundleID` had one.
    static func legacyDomain(for bundleID: String) -> String? {
        switch bundleID {
        case "com.lawliang.lostty": "com.lawliang.ghostty-skins"
        case "com.lawliang.lostty.debug": "com.lawliang.ghostty-skins.debug"
        default: nil
        }
    }

    /// Runs the migration for the running app. Skipped in the test host so a
    /// test run never writes the developer's real preferences.
    static func runIfNeeded() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let bundleID = Bundle.main.bundleIdentifier,
              let legacy = legacyDomain(for: bundleID)
        else { return }
        migrate(from: legacy, to: bundleID)
    }

    /// Copies every key in `old` that `new` lacks, then marks `new` as
    /// migrated. Does nothing once the marker is set. Returns the keys it
    /// wrote, marker excluded.
    @discardableResult
    static func migrate(from old: String, to new: String) -> [String] {
        let user = kCFPreferencesCurrentUser
        let host = kCFPreferencesAnyHost
        let newDomain = new as CFString

        if CFPreferencesCopyValue(markerKey as CFString, newDomain, user, host) != nil {
            return []
        }

        let oldValues = (CFPreferencesCopyMultiple(nil, old as CFString, user, host) as NSDictionary)
            as? [String: Any] ?? [:]
        let existing = Set((CFPreferencesCopyKeyList(newDomain, user, host) as NSArray?) as? [String] ?? [])

        var toWrite: [String: Any] = [:]
        for (key, value) in oldValues {
            let newKey = key.hasPrefix(legacyKeyPrefix)
                ? keyPrefix + key.dropFirst(legacyKeyPrefix.count)
                : key
            guard !existing.contains(newKey), toWrite[newKey] == nil else { continue }
            toWrite[newKey] = value
        }
        let written = toWrite.keys.sorted()

        toWrite[markerKey] = true
        CFPreferencesSetMultiple(toWrite as CFDictionary, nil, newDomain, user, host)
        _ = CFPreferencesSynchronize(newDomain, user, host)
        return written
    }
}
