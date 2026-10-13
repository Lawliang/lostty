#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct StayAwakeModelTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let before = PowerSettings(disableSleep: false, lowPowerOnBattery: true, lowPowerOnAC: false)
    let open = PowerState(lidClosed: false, onBattery: true, batteryPercent: 80, thermal: .nominal)
    var closed: PowerState { PowerState(lidClosed: true, onBattery: true, batteryPercent: 80, thermal: .nominal) }

    func onModel(lid: PowerState? = nil, until: Date? = nil) -> StayAwakeModel {
        var m = StayAwakeModel()
        _ = m.handle(.power(lid ?? open), now: t0)
        _ = m.handle(.turnOn(until: until, current: before), now: t0)
        return m
    }

    @Test func turningOnSavesTheRecordBeforeDisablingSleep() {
        var m = StayAwakeModel()
        _ = m.handle(.power(open), now: t0)
        let actions = m.handle(.turnOn(until: nil, current: before), now: t0)
        #expect(actions == [.saveRecord(.init(settings: before, lowPowerApplied: false)), .run(.disableSleep(true))])
        #expect(m.isOn)
    }

    @Test func turningOnWithTheLidClosedAppliesLowPowerToo() {
        var m = StayAwakeModel()
        _ = m.handle(.power(closed), now: t0)
        let actions = m.handle(.turnOn(until: nil, current: before), now: t0)
        #expect(actions == [
            .saveRecord(.init(settings: before, lowPowerApplied: false)), .run(.disableSleep(true)),
            .saveRecord(.init(settings: before, lowPowerApplied: true)), .run(.lowPowerEverywhere),
        ])
    }

    @Test func lowPowerOnlyWhileTheLidIsClosed() {
        var m = onModel()
        #expect(m.handle(.power(closed), now: t0) == [
            .saveRecord(.init(settings: before, lowPowerApplied: true)), .run(.lowPowerEverywhere),
        ])
        #expect(m.handle(.power(closed), now: t0) == [])
        #expect(m.handle(.power(open), now: t0) == [
            .run(.lowPower(.battery, true)), .run(.lowPower(.ac, false)),
            .saveRecord(.init(settings: before, lowPowerApplied: false)),
        ])
    }

    @Test func restoresLowPowerPerSource() {
        var m = onModel(lid: closed)
        let actions = m.handle(.turnOff, now: t0)
        #expect(actions == [
            .run(.disableSleep(false)),
            .run(.lowPower(.battery, true)), .run(.lowPower(.ac, false)), .clearRecord,
        ])
        #expect(m.state == .off(reason: .turnedOff, at: t0))
    }

    @Test func aHandSetDisableSleepStaysSet() {
        var m = StayAwakeModel()
        _ = m.handle(.power(open), now: t0)
        let mine = PowerSettings(disableSleep: true, lowPowerOnBattery: nil, lowPowerOnAC: false)
        _ = m.handle(.turnOn(until: nil, current: mine), now: t0)
        _ = m.handle(.power(closed), now: t0)
        #expect(m.handle(.turnOff, now: t0) == [
            .run(.disableSleep(true)), .run(.lowPower(.ac, false)), .clearRecord,
        ])
    }

    @Test func batteryFloorCutsOffOnlyOnBattery() {
        var m = onModel()
        m.batteryFloor = 15
        #expect(m.handle(.power(.init(lidClosed: false, onBattery: false, batteryPercent: 10, thermal: .nominal)), now: t0) == [])
        #expect(m.isOn)
        let actions = m.handle(.power(.init(lidClosed: false, onBattery: true, batteryPercent: 15, thermal: .nominal)), now: t0)
        #expect(actions == [
            .notifyMac("Mac is going to sleep — battery at 15%."), .notifyPhone("Mac is going to sleep — battery at 15%."),
            .run(.disableSleep(false)), .clearRecord,
        ])
        #expect(m.state == .off(reason: .battery(15), at: t0))
    }

    @Test func criticalHeatCutsOff() {
        var m = onModel()
        _ = m.handle(.power(.init(lidClosed: false, onBattery: true, batteryPercent: 80, thermal: .serious)), now: t0)
        #expect(m.isOn)
        let actions = m.handle(.power(.init(lidClosed: false, onBattery: true, batteryPercent: 80, thermal: .critical)), now: t0)
        #expect(actions.first == .notifyMac("Mac is going to sleep — it's too hot."))
        #expect(m.state == .off(reason: .heat, at: t0))
    }

    @Test func timerEndsIt() {
        var m = onModel(until: t0.addingTimeInterval(3600))
        #expect(m.handle(.tick, now: t0.addingTimeInterval(3599)) == [])
        let actions = m.handle(.tick, now: t0.addingTimeInterval(3600))
        #expect(actions.first == .notifyMac("Mac is going to sleep — Stay Awake time is up."))
        #expect(m.state == .off(reason: .timer, at: t0.addingTimeInterval(3600)))
    }

    @Test func noRearmingAfterACutOff() {
        var m = onModel()
        m.batteryFloor = 15
        _ = m.handle(.power(.init(lidClosed: false, onBattery: true, batteryPercent: 10, thermal: .nominal)), now: t0)
        #expect(m.handle(.power(.init(lidClosed: false, onBattery: false, batteryPercent: 90, thermal: .nominal)), now: t0) == [])
        #expect(!m.isOn)
    }

    @Test func refusesToTurnOnBelowTheFloorOrHot() {
        var m = StayAwakeModel()
        m.batteryFloor = 15
        _ = m.handle(.power(.init(lidClosed: false, onBattery: true, batteryPercent: 12, thermal: .nominal)), now: t0)
        #expect(m.handle(.turnOn(until: nil, current: before), now: t0) == [])
        #expect(m.state == .off(reason: .battery(12), at: t0))

        var hot = StayAwakeModel()
        _ = hot.handle(.power(.init(lidClosed: false, onBattery: false, batteryPercent: nil, thermal: .critical)), now: t0)
        #expect(hot.handle(.turnOn(until: nil, current: before), now: t0) == [])
        #expect(hot.state == .off(reason: .heat, at: t0))
    }

    @Test func quitRestoresWithoutNotifying() {
        var m = onModel(lid: closed)
        let actions = m.handle(.quit, now: t0)
        #expect(!actions.contains { if case .notifyMac = $0 { true } else { false } })
        #expect(actions.last == .clearRecord)
        #expect(!m.isOn)
    }

    @Test func launchRestoresALeftoverRecord() {
        var m = StayAwakeModel()
        let record = StayAwakeRecord(settings: before, lowPowerApplied: true)
        #expect(m.handle(.launch(record), now: t0) == [
            .run(.disableSleep(false)),
            .run(.lowPower(.battery, true)), .run(.lowPower(.ac, false)), .clearRecord,
        ])
        #expect(m.handle(.launch(nil), now: t0) == [])
    }

    @Test func permissionMissingWhileTurningOnLeavesNothingChanged() {
        var m = onModel()
        let actions = m.handle(.controlFailed(.permissionMissing, command: .disableSleep(true)), now: t0)
        #expect(actions == [.clearRecord])
        #expect(m.state == .off(reason: .permissionMissing, at: t0))
    }

    @Test func failedRestoreKeepsTheRecordAndSaysHowToUndo() {
        var m = onModel()
        _ = m.handle(.turnOff, now: t0)
        let actions = m.handle(.controlFailed(.failed("nope"), command: .disableSleep(false)), now: t0)
        #expect(actions == [.notifyMac(StayAwakeCopy.restoreFailed)])
        #expect(!actions.contains(.clearRecord))
        #expect(m.state == .off(reason: .restoreFailed, at: t0))
        #expect(StayAwakeCopy.restoreFailed == "Lostty couldn't let your Mac sleep again. Run: sudo pmset -a disablesleep 0")
    }

    @Test func lowPowerFailureWhileOnOnlyNotifies() {
        var m = onModel()
        _ = m.handle(.power(closed), now: t0)
        let actions = m.handle(.controlFailed(.failed("x"), command: .lowPowerEverywhere), now: t0)
        #expect(actions == [
            .saveRecord(.init(settings: before, lowPowerApplied: true)),
            .notifyMac("Lostty couldn't change Low Power Mode."),
        ])
        #expect(m.isOn)
    }

    @Test func noTurnOnAfterAFailedRestore() {
        var m = onModel()
        _ = m.handle(.turnOff, now: t0)
        _ = m.handle(.controlFailed(.failed("nope"), command: .disableSleep(false)), now: t0)
        let stuck = PowerSettings(disableSleep: true, lowPowerOnBattery: true, lowPowerOnAC: true)
        #expect(m.handle(.turnOn(until: nil, current: stuck), now: t0) == [])
        #expect(m.state == .off(reason: .restoreFailed, at: t0))
    }

    @Test func failedLidOpenRestoreIsRetriedAtTurnOff() {
        var m = onModel()
        _ = m.handle(.power(closed), now: t0)
        _ = m.handle(.power(open), now: t0)
        #expect(m.handle(.controlFailed(.failed("x"), command: .lowPower(.battery, true)), now: t0) == [
            .saveRecord(.init(settings: before, lowPowerApplied: true)),
            .notifyMac("Lostty couldn't change Low Power Mode."),
        ])
        #expect(m.handle(.turnOff, now: t0) == [
            .run(.disableSleep(false)),
            .run(.lowPower(.battery, true)), .run(.lowPower(.ac, false)), .clearRecord,
        ])
    }

    @Test func failedLidOpenRestoreIsNotRetriedEveryPoll() {
        var m = onModel()
        _ = m.handle(.power(closed), now: t0)
        _ = m.handle(.power(open), now: t0)
        _ = m.handle(.controlFailed(.failed("x"), command: .lowPower(.battery, true)), now: t0)
        #expect(m.handle(.power(open), now: t0) == [])
        #expect(m.handle(.turnOff, now: t0) == [
            .run(.disableSleep(false)),
            .run(.lowPower(.battery, true)), .run(.lowPower(.ac, false)), .clearRecord,
        ])
    }

    @Test func durations() {
        #expect(StayAwakeDuration.allCases.map(\.title) == ["Until I Turn It Off", "1 Hour", "4 Hours", "8 Hours"])
        #expect(StayAwakeDuration.untilOff.seconds == nil)
        #expect(StayAwakeDuration.fourHours.seconds == TimeInterval(4 * 3600))
    }
}
#endif
