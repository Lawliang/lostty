#if os(macOS)
import Foundation
import Testing
@testable import Lostty

/// Under memory pressure or heat, idle Claude cards sleep sooner.
struct MacStrainTests {
    @Test func theWorseOfMemoryAndHeatDecides() {
        #expect(MacStrain(memory: .normal, thermal: .nominal) == .none)
        #expect(MacStrain(memory: .normal, thermal: .fair) == .none)
        #expect(MacStrain(memory: .warning, thermal: .nominal) == .high)
        #expect(MacStrain(memory: .normal, thermal: .serious) == .high)
        #expect(MacStrain(memory: .critical, thermal: .nominal) == .critical)
        #expect(MacStrain(memory: .warning, thermal: .critical) == .critical)
    }

    @Test func aStrainedMacSleepsIdleCardsAfterFiveMinutes() {
        #expect(MacStrain.high.sleepMinutes(setting: 20) == 5)
        #expect(MacStrain.critical.sleepMinutes(setting: 120) == 5)
    }

    @Test func theOwnersSettingHoldsOtherwise() {
        #expect(MacStrain.none.sleepMinutes(setting: 20) == 20)
        // Never later than they asked, and never when sleep is off.
        #expect(MacStrain.high.sleepMinutes(setting: 3) == 3)
        #expect(MacStrain.critical.sleepMinutes(setting: 0) == 0)
    }

    @Test func aLidClosedOverAMacKeptAwakeCountsAsStrain() {
        #expect(MacStrain(memory: .normal, thermal: .nominal, lidShut: true) == .high)
        #expect(MacStrain(memory: .critical, thermal: .nominal, lidShut: true) == .critical)
    }

    @Test func aClosedLidHidesTheWindowsUnlessAnotherDisplayIsAttached() {
        #expect(MacStrainWatch.lidShut(closed: true, displays: [true]))
        #expect(MacStrainWatch.lidShut(closed: true, displays: []))
        #expect(!MacStrainWatch.lidShut(closed: true, displays: [true, false]))
        #expect(!MacStrainWatch.lidShut(closed: false, displays: [true]))
    }
}
#endif
