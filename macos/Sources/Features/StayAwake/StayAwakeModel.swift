#if os(macOS)
import Foundation

enum Thermal: Equatable {
    case nominal, fair, serious, critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }
}

struct PowerState: Equatable {
    var lidClosed: Bool
    var onBattery: Bool
    /// nil on Macs without a battery.
    var batteryPercent: Int?
    var thermal: Thermal
}

/// What to put back, saved before anything changes.
struct StayAwakeRecord: Codable, Equatable {
    var settings: PowerSettings
    var lowPowerApplied: Bool
}

enum StayAwakeReason: Equatable {
    case turnedOff, timer, battery(Int), heat, permissionMissing, failed(String), restoreFailed
}

enum StayAwakeDuration: String, CaseIterable {
    case untilOff, oneHour, fourHours, eightHours

    var title: String {
        switch self {
        case .untilOff: "Until I Turn It Off"
        case .oneHour: "1 Hour"
        case .fourHours: "4 Hours"
        case .eightHours: "8 Hours"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .untilOff: nil
        case .oneHour: 3600
        case .fourHours: 4 * 3600
        case .eightHours: 8 * 3600
        }
    }
}

enum StayAwakeAction: Equatable {
    case saveRecord(StayAwakeRecord)
    case clearRecord
    case run(PowerCommand)
    case notifyMac(String)
    case notifyPhone(String)
}

enum StayAwakeCopy {
    static let restoreFailed = "Lostty couldn't let your Mac sleep again. Run: sudo pmset -a disablesleep 0"
    static let lowPowerFailed = "Lostty couldn't change Low Power Mode."
    static let unreadable = "Lostty couldn't read your power settings, so Stay Awake didn't turn on."

    static func goingToSleep(_ reason: StayAwakeReason) -> String? {
        switch reason {
        case .battery(let percent): "Mac is going to sleep — battery at \(percent)%."
        case .heat: "Mac is going to sleep — it's too hot."
        case .timer: "Mac is going to sleep — Stay Awake time is up."
        default: nil
        }
    }
}

/// Stay Awake for Phone's rules, with no system calls: events in, actions
/// out. The store performs the actions in order and stops at the first
/// failure, reporting it back as `controlFailed`; `clearRecord` always comes
/// last, so a failed restore leaves the record for the next launch.
struct StayAwakeModel {
    enum State: Equatable {
        case off(reason: StayAwakeReason?, at: Date?)
        case on(until: Date?, record: StayAwakeRecord)
    }

    enum Event: Equatable {
        case turnOn(until: Date?, current: PowerSettings)
        case turnOff
        case power(PowerState)
        case tick
        case quit
        case launch(StayAwakeRecord?)
        /// Restart to Update: the Lostty before had it on, with this record.
        case resume(StayAwakeRecord?, until: Date?)
        case controlFailed(PowerControlError, command: PowerCommand)
    }

    private(set) var state: State = .off(reason: nil, at: nil)
    private(set) var power: PowerState?
    var batteryFloor = 15
    /// Not persisted: stops the 5 s power poll from retrying a failed lid-open restore.
    private var lidOpenRestoreFailed = false

    var isOn: Bool { if case .on = state { true } else { false } }

    mutating func handle(_ event: Event, now: Date) -> [StayAwakeAction] {
        switch event {
        case .turnOn(let until, let current):
            guard !isOn else { return [] }
            // A failed restore left the record for the next launch; a new
            // baseline taken now would overwrite it with the stuck settings.
            if case .off(.restoreFailed?, _) = state { return [] }
            if let power, let reason = cutOff(power) {
                state = .off(reason: reason, at: now)
                return []
            }
            var record = StayAwakeRecord(settings: current, lowPowerApplied: false)
            var actions: [StayAwakeAction] = [.saveRecord(record), .run(.disableSleep(true))]
            if power?.lidClosed == true {
                record.lowPowerApplied = true
                actions += [.saveRecord(record), .run(.lowPowerEverywhere)]
            }
            lidOpenRestoreFailed = false
            state = .on(until: until, record: record)
            return actions

        case .turnOff:
            return finish(.turnedOff, now: now)

        case .quit:
            return finish(.turnedOff, now: now)

        case .power(let next):
            power = next
            guard case .on(let until, var record) = state else { return [] }
            if let reason = cutOff(next) { return finish(reason, now: now) }
            if next.lidClosed { lidOpenRestoreFailed = false }
            if next.lidClosed && !record.lowPowerApplied {
                record.lowPowerApplied = true
                state = .on(until: until, record: record)
                return [.saveRecord(record), .run(.lowPowerEverywhere)]
            }
            if !next.lidClosed && record.lowPowerApplied && !lidOpenRestoreFailed {
                record.lowPowerApplied = false
                state = .on(until: until, record: record)
                return restoreLowPower(record.settings) + [.saveRecord(record)]
            }
            return []

        case .tick:
            guard case .on(let until?, _) = state, now >= until else { return [] }
            return finish(.timer, now: now)

        case .resume(let record, let until):
            // Still applied from before the restart: adopt it, run nothing.
            guard let record, !isOn else { return [] }
            state = .on(until: until, record: record)
            return []

        case .launch(let record):
            guard let record else { return [] }
            state = .off(reason: nil, at: nil)
            return restore(record) + [.clearRecord]

        case .controlFailed(let error, let command):
            if isOn {
                if command == .disableSleep(true) {
                    state = .off(reason: error == .permissionMissing ? .permissionMissing : .failed(Self.text(error)), at: now)
                    return [.clearRecord]
                }
                // A half-done change: keep remembering it so turn off retries the restore.
                guard case .on(let until, var record) = state else { return [] }
                record.lowPowerApplied = true
                if power?.lidClosed == false { lidOpenRestoreFailed = true }
                state = .on(until: until, record: record)
                return [.saveRecord(record), .notifyMac(StayAwakeCopy.lowPowerFailed)]
            }
            state = .off(reason: .restoreFailed, at: now)
            return [.notifyMac(StayAwakeCopy.restoreFailed)]
        }
    }

    private func cutOff(_ power: PowerState) -> StayAwakeReason? {
        if power.thermal == .critical { return .heat }
        if power.onBattery, let percent = power.batteryPercent, percent <= batteryFloor { return .battery(percent) }
        return nil
    }

    private mutating func finish(_ reason: StayAwakeReason, now: Date) -> [StayAwakeAction] {
        guard case .on(_, let record) = state else { return [] }
        lidOpenRestoreFailed = false
        state = .off(reason: reason, at: now)
        let notices = StayAwakeCopy.goingToSleep(reason).map { [StayAwakeAction.notifyMac($0), .notifyPhone($0)] } ?? []
        return notices + restore(record) + [.clearRecord]
    }

    private func restore(_ record: StayAwakeRecord) -> [StayAwakeAction] {
        // Sleep first: a failed Low Power Mode restore must not leave the Mac awake.
        [.run(.disableSleep(record.settings.disableSleep))]
            + (record.lowPowerApplied ? restoreLowPower(record.settings) : [])
    }

    private func restoreLowPower(_ settings: PowerSettings) -> [StayAwakeAction] {
        var actions: [StayAwakeAction] = []
        if let battery = settings.lowPowerOnBattery { actions.append(.run(.lowPower(.battery, battery))) }
        actions.append(.run(.lowPower(.ac, settings.lowPowerOnAC)))
        return actions
    }

    private static func text(_ error: PowerControlError) -> String {
        switch error {
        case .permissionMissing: "needs the stay-awake permission"
        case .failed(let message): message
        case .unreadable: "couldn't read the power settings"
        }
    }
}
#endif
