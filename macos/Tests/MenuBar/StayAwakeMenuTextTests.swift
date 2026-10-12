#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Ghostty

struct StayAwakeMenuTextTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let battery = PowerState(lidClosed: false, onBattery: true, batteryPercent: 64, thermal: .nominal)
    let record = StayAwakeRecord(settings: .init(disableSleep: false, lowPowerOnBattery: nil, lowPowerOnAC: false), lowPowerApplied: false)

    @Test func onWithTimeLeftBatteryAndHeat() {
        let s = StayAwakeMenuText.status(.on(until: now.addingTimeInterval(2 * 3600 + 40 * 60), record: record),
                                         power: battery, permissionInstalled: true, now: now)
        #expect(s == "2h 40m left · 64% on battery · normal")
    }

    @Test func onUntilTurnedOffOnPowerHot() {
        let s = StayAwakeMenuText.status(.on(until: nil, record: record),
                                         power: .init(lidClosed: true, onBattery: false, batteryPercent: 90, thermal: .serious),
                                         permissionInstalled: true, now: now)
        #expect(s == "On until you turn it off · on power · hot")
    }

    @Test func lessThanAnHourAndRoundsUp() {
        let s = StayAwakeMenuText.status(.on(until: now.addingTimeInterval(61), record: record), power: nil, permissionInstalled: true, now: now)
        #expect(s == "2m left")
    }

    @Test func offReasons() {
        #expect(StayAwakeMenuText.status(.off(reason: .battery(15), at: now), power: nil, permissionInstalled: true, now: now)?.hasPrefix("Turned off at 15% battery · ") == true)
        #expect(StayAwakeMenuText.status(.off(reason: .heat, at: now), power: nil, permissionInstalled: true, now: now)?.hasPrefix("Turned off: the Mac got too hot · ") == true)
        #expect(StayAwakeMenuText.status(.off(reason: .timer, at: now), power: nil, permissionInstalled: true, now: now)?.hasPrefix("Time ran out · ") == true)
        #expect(StayAwakeMenuText.status(.off(reason: .restoreFailed, at: now), power: nil, permissionInstalled: true, now: now) == StayAwakeCopy.restoreFailed)
        #expect(StayAwakeMenuText.status(.off(reason: .turnedOff, at: now), power: nil, permissionInstalled: true, now: now) == nil)
        #expect(StayAwakeMenuText.status(.off(reason: nil, at: nil), power: nil, permissionInstalled: false, now: now) == "Needs the stay-awake permission")
    }

    @Test func permissionMissingClearsOnceInstalled() {
        #expect(StayAwakeMenuText.status(.off(reason: .permissionMissing, at: now), power: nil, permissionInstalled: false, now: now) == "Needs the stay-awake permission")
        #expect(StayAwakeMenuText.status(.off(reason: .permissionMissing, at: now), power: nil, permissionInstalled: true, now: now) == nil)
    }

    @Test func attachedLineNamesNoPhone() {
        #expect(StayAwakeMenuText.attached("api-server") == "A phone or SSH client is attached to api-server")
    }

    @Test func sessionLinesMarkWaitingAndWorking() {
        let waiting = SessionLabel.row(for: RemoteSession(
            id: "$1", name: "lostty", surface: "A", owner: 1, claude: .waiting,
            title: "✳ Fix login", command: "2.1.296"), now: now)
        #expect(StayAwakeMenuText.sessionLine(waiting) == "   ● Fix login — Waiting")
        let working = SessionLabel.row(for: RemoteSession(
            id: "$1", name: "lostty", surface: "A", owner: 1, claude: .working,
            title: "◐ Fix login", command: "2.1.296"), now: now)
        #expect(StayAwakeMenuText.sessionLine(working) == "   ○ Fix login — Working")
    }

    @Test func otherSessionsSayWhenTheyWereUsed() {
        let used = SessionLabel.row(for: RemoteSession(
            id: "$2", name: "notes-2", surface: nil, owner: nil, command: "zsh",
            activity: now.addingTimeInterval(-300)), now: now)
        #expect(StayAwakeMenuText.sessionLine(used) == "   notes — 5m ago")
        let unknown = SessionLabel.row(for: RemoteSession(id: "$3", name: "notes", surface: nil, owner: nil), now: now)
        #expect(StayAwakeMenuText.sessionLine(unknown) == "   notes")
    }
}
#endif
