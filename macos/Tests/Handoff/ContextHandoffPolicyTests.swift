#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct ContextHandoffPolicyTests {
    @Test func aOneMillionWindowUsesTheSetting() {
        #expect(ContextHandoffPolicy.limit(setting: 300_000, size: 1_000_000) == 300_000)
        #expect(ContextHandoffPolicy.ceiling(setting: 300_000, size: 1_000_000) == 400_000)
    }

    @Test func aSmallWindowCapsTheLimitAt70AndTheCeilingAt90Percent() {
        #expect(ContextHandoffPolicy.limit(setting: 300_000, size: 200_000) == 140_000)
        #expect(ContextHandoffPolicy.ceiling(setting: 300_000, size: 200_000) == 180_000)
    }

    @Test func levels() {
        #expect(ContextHandoffPolicy.level(used: 299_999, size: 1_000_000, setting: 300_000) == nil)
        #expect(ContextHandoffPolicy.level(used: 300_000, size: 1_000_000, setting: 300_000) == .limit)
        #expect(ContextHandoffPolicy.level(used: 400_000, size: 1_000_000, setting: 300_000) == .ceiling)
    }

    @Test func anUnknownWindowNeverArms() {
        #expect(ContextHandoffPolicy.level(used: 900_000, size: 0, setting: 300_000) == nil)
    }

    @Test func preferencesDefaultOffAt300k() {
        let defaults = UserDefaults(suiteName: "handoff-prefs-\(UUID())")!
        let prefs = ContextHandoffPreferences(defaults: defaults)
        #expect(prefs.enabled == false)
        #expect(prefs.limit == 300_000)
        prefs.enabled = true
        prefs.limit = 500_000
        let again = ContextHandoffPreferences(defaults: defaults)
        #expect(again.enabled)
        #expect(again.limit == 500_000)
    }

    @Test func anUnlistedSavedLimitFallsBackTo300k() {
        let defaults = UserDefaults(suiteName: "handoff-prefs-\(UUID())")!
        defaults.set(123, forKey: ContextHandoffPreferences.limitKey)
        #expect(ContextHandoffPreferences(defaults: defaults).limit == 300_000)
    }

    #if DEBUG
    @Test func theDebugOverrideReplacesTheSetting() {
        let defaults = UserDefaults(suiteName: "handoff-prefs-\(UUID())")!
        defaults.set(20_000, forKey: ContextHandoffPreferences.overrideKey)
        #expect(ContextHandoffPreferences(defaults: defaults).setting == 20_000)
    }
    #endif
}
#endif
