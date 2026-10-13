#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct LegacySettingsMigrationTests {
    @Test func mapsTheRenamedBundleIdentifiers() {
        #expect(LegacySettingsMigration.legacyDomain(for: "com.lawliang.lostty") == "com.lawliang.ghostty-skins")
        #expect(LegacySettingsMigration.legacyDomain(for: "com.lawliang.lostty.debug")
            == "com.lawliang.ghostty-skins.debug")
        #expect(LegacySettingsMigration.legacyDomain(for: "com.lawliang.lostty.tests") == nil)
    }

    @Test func copiesMissingKeysOnce() {
        let id = UUID().uuidString
        let old = "com.lawliang.lostty.tests.migration-old-\(id)"
        let new = "com.lawliang.lostty.tests.migration-new-\(id)"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: old)
            UserDefaults.standard.removePersistentDomain(forName: new)
        }
        UserDefaults.standard.setPersistentDomain([
            "theme": "dark",
            "count": 42,
            "com.mitchellh.ghostty.shortcutsPermission": Data([1]),
        ], forName: old)
        UserDefaults.standard.setPersistentDomain(["theme": "light"], forName: new)

        let written = LegacySettingsMigration.migrate(from: old, to: new)
        #expect(written == ["com.lawliang.lostty.shortcutsPermission", "count"])

        let migrated = UserDefaults.standard.persistentDomain(forName: new) ?? [:]
        #expect(migrated["theme"] as? String == "light")
        #expect(migrated["count"] as? Int == 42)
        #expect(migrated["com.lawliang.lostty.shortcutsPermission"] as? Data == Data([1]))
        #expect(migrated[LegacySettingsMigration.markerKey] as? Bool == true)

        // The marker stops a second pass from copying keys added later.
        UserDefaults.standard.setPersistentDomain(["later": 7], forName: old)
        #expect(LegacySettingsMigration.migrate(from: old, to: new).isEmpty)
    }
}
#endif
