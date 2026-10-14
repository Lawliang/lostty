#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct ObserverPreferencesTests {
    @Test func backgroundSummariesAreOnByDefaultAndRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "ObserverPreferencesTests-\(UUID().uuidString)"))
        let preferences = ObserverPreferences(defaults: defaults)
        #expect(preferences.background)
        preferences.background = false
        #expect(defaults.object(forKey: ObserverPreferences.backgroundKey) as? Bool == false)
        #expect(!ObserverPreferences(defaults: defaults).background)
        #expect(ObserverPreferences.backgroundKey == "LosttyObserverBackground")
    }
}
#endif
