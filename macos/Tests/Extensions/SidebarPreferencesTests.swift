#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SidebarPreferencesTests {
    @Test func autoHideIsOffByDefaultAndRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "SidebarPreferencesTests-\(UUID().uuidString)"))
        let preferences = SidebarPreferences(defaults: defaults)
        #expect(preferences.autoHide == false)
        preferences.autoHide = true
        #expect(defaults.bool(forKey: SidebarPreferences.autoHideKey))
        #expect(SidebarPreferences(defaults: defaults).autoHide)
        #expect(SidebarPreferences.autoHideKey == "LosttySidebarAutoHide")
    }
}
#endif
