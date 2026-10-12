#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct StayAwakeStoreTests {
    final class FakeControl: PowerControl {
        var settings = PowerSettings(disableSleep: false, lowPowerOnBattery: true, lowPowerOnAC: false)
        var ran: [PowerCommand] = []
        var failOn: PowerCommand?
        var permission = true
        var unreadable = false
        func read() throws -> PowerSettings {
            if unreadable { throw PowerControlError.unreadable }
            return settings
        }
        func run(_ command: PowerCommand) throws {
            if command == failOn { throw PowerControlError.failed("boom") }
            ran.append(command)
        }
        func hasPermission() -> Bool { permission }
    }

    final class Notes { var mac: [String] = [] }

    func make(_ control: FakeControl, power: PowerState, defaults: UserDefaults, notes: Notes = Notes()) -> StayAwakeStore {
        StayAwakeStore(
            control: control, defaults: defaults, phone: NoPhoneNotifier(),
            readPower: { power }, hasPairedPhone: { true },
            notifyMac: { notes.mac.append($0) }, now: { Date(timeIntervalSince1970: 1_000) })
    }

    func freshDefaults() -> UserDefaults {
        let name = "StayAwakeStoreTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    let open = PowerState(lidClosed: false, onBattery: true, batteryPercent: 80, thermal: .nominal)

    @Test func turnOnSavesTheRecordAndDisablesSleep() {
        let control = FakeControl()
        let defaults = freshDefaults()
        let store = make(control, power: open, defaults: defaults)
        store.refreshAvailability()
        store.turnOn(.untilOff)
        #expect(store.isOn)
        #expect(control.ran == [.disableSleep(true)])
        #expect(StayAwakeRecordStore(defaults: defaults).load()?.settings == control.settings)
    }

    @Test func turnOffRestoresAndClearsTheRecord() {
        let control = FakeControl()
        let defaults = freshDefaults()
        let store = make(control, power: open, defaults: defaults)
        store.refreshAvailability()
        store.turnOn(.untilOff)
        store.turnOff()
        #expect(control.ran == [.disableSleep(true), .disableSleep(false)])
        #expect(StayAwakeRecordStore(defaults: defaults).load() == nil)
    }

    @Test func stopsAtTheFirstFailureSoTheRecordSurvives() {
        let control = FakeControl()
        let defaults = freshDefaults()
        let notes = Notes()
        let store = make(control, power: open, defaults: defaults, notes: notes)
        store.refreshAvailability()
        store.turnOn(.untilOff)
        control.failOn = .disableSleep(false)
        store.turnOff()
        #expect(StayAwakeRecordStore(defaults: defaults).load() != nil)
        #expect(notes.mac == [StayAwakeCopy.restoreFailed])
    }

    @Test func startRestoresALeftoverRecord() {
        let control = FakeControl()
        let defaults = freshDefaults()
        StayAwakeRecordStore(defaults: defaults).save(.init(settings: control.settings, lowPowerApplied: false))
        let store = make(control, power: open, defaults: defaults)
        store.start()
        #expect(control.ran == [.disableSleep(false)])
        #expect(StayAwakeRecordStore(defaults: defaults).load() == nil)
    }

    @Test func notAvailableWithoutPermission() {
        let control = FakeControl()
        control.permission = false
        let store = make(control, power: open, defaults: freshDefaults())
        store.refreshAvailability()
        #expect(!store.available)
        store.turnOn(.untilOff)
        #expect(!store.isOn)
        #expect(control.ran.isEmpty)
    }

    @Test func floorDefaultsToFifteenAndPersists() {
        let defaults = freshDefaults()
        let store = make(FakeControl(), power: open, defaults: defaults)
        #expect(store.batteryFloor == 15)
        store.batteryFloor = 30
        #expect(make(FakeControl(), power: open, defaults: defaults).batteryFloor == 30)
    }

    @Test func unreadableSettingsNotifyAndChangeNothing() {
        let control = FakeControl()
        control.unreadable = true
        let defaults = freshDefaults()
        let notes = Notes()
        let store = make(control, power: open, defaults: defaults, notes: notes)
        store.refreshAvailability()
        store.turnOn(.untilOff)
        #expect(!store.isOn)
        #expect(control.ran.isEmpty)
        #expect(StayAwakeRecordStore(defaults: defaults).load() == nil)
        #expect(notes.mac == [StayAwakeCopy.unreadable])
        control.unreadable = false
        store.turnOn(.untilOff)
        #expect(store.isOn)
        #expect(control.ran == [.disableSleep(true)])
    }
}
#endif
