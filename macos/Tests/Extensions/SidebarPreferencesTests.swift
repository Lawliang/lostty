#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct SidebarPreferencesTests {
    @Test func hidingIsOnByDefaultAndRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "SidebarPreferencesTests-\(UUID().uuidString)"))
        let preferences = SidebarPreferences(defaults: defaults)
        #expect(preferences.autoHide)
        preferences.autoHide = false
        #expect(defaults.object(forKey: SidebarPreferences.autoHideKey) as? Bool == false)
        #expect(SidebarPreferences(defaults: defaults).autoHide == false)
        #expect(SidebarPreferences.autoHideKey == "LosttySidebarAutoHide")
    }
}
#endif
