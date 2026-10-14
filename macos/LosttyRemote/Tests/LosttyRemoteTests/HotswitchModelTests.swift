import Foundation
import Testing
@testable import LosttyRemote

struct HotswitchModelTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func active() -> HotswitchModel {
        var model = HotswitchModel(hotspot: "Law")
        _ = model.setActive(true)
        return model
    }

    /// Wi-Fi gone, joined, internet through the hotspot: on it at `seconds`.
    private func onHotspot(at seconds: TimeInterval = 30) -> HotswitchModel {
        var model = active()
        _ = model.tick(now: at(0), network: nil, internet: nil)
        _ = model.tick(now: at(20), network: nil, internet: nil)
        _ = model.joined(error: nil, now: at(21))
        _ = model.tick(now: at(seconds), network: "Law", internet: true)
        return model
    }

    @Test func wifiGoneTwentySecondsJoins() {
        var model = active()
        #expect(model.tick(now: at(0), network: nil, internet: nil).isEmpty)
        #expect(model.tick(now: at(15), network: nil, internet: nil).isEmpty)
        #expect(model.tick(now: at(20), network: nil, internet: nil).contains(.join))
        #expect(model.phase == .joining)
    }

    @Test func offWifiButOnlineStaysPut() {
        var model = active()
        _ = model.tick(now: at(0), network: nil, internet: nil)
        _ = model.tick(now: at(15), network: nil, internet: true)
        #expect(model.tick(now: at(30), network: nil, internet: nil).isEmpty)
        #expect(model.tick(now: at(49), network: nil, internet: nil).isEmpty)
        #expect(model.tick(now: at(50), network: nil, internet: nil).contains(.join))
    }

    @Test func nothingWhileStayAwakeIsOff() {
        var model = HotswitchModel(hotspot: "Law")
        _ = model.tick(now: at(0), network: nil, internet: nil)
        #expect(model.tick(now: at(60), network: nil, internet: nil).isEmpty)
    }

    @Test func aMinuteOfFailedProbesJoins() {
        var model = active()
        #expect(model.tick(now: at(0), network: "Home", internet: false).isEmpty)
        #expect(model.tick(now: at(30), network: "Home", internet: nil).isEmpty)
        #expect(model.tick(now: at(45), network: "Home", internet: false).isEmpty)
        #expect(model.tick(now: at(60), network: "Home", internet: false).contains(.join))
    }

    @Test func oneGoodProbeStartsTheMinuteOver() {
        var model = active()
        _ = model.tick(now: at(0), network: "Home", internet: false)
        _ = model.tick(now: at(45), network: "Home", internet: true)
        #expect(model.tick(now: at(60), network: "Home", internet: false).isEmpty)
        #expect(model.tick(now: at(119), network: "Home", internet: false).isEmpty)
        #expect(model.tick(now: at(120), network: "Home", internet: false).contains(.join))
    }

    @Test func notWhenAlreadyOnTheHotspot() {
        var model = active()
        _ = model.tick(now: at(0), network: "Law", internet: false)
        #expect(model.tick(now: at(120), network: "Law", internet: false).isEmpty)
    }

    @Test func joiningAndReachingTheInternetTellsThePhone() {
        let model = onHotspot()
        #expect(model.phase == .onHotspot(lastScan: at(30), strongScans: 0))
        #expect(model.status == .onHotspot(since: at(30)))
    }

    @Test func theMoveNoticeGoesToThePhone() {
        var model = active()
        _ = model.tick(now: at(0), network: nil, internet: nil)
        _ = model.tick(now: at(20), network: nil, internet: nil)
        _ = model.joined(error: nil, now: at(21))
        #expect(model.tick(now: at(25), network: "Law", internet: nil).isEmpty)
        #expect(model.tick(now: at(30), network: "Law", internet: true).contains(.notifyPhone(HotswitchModel.moved)))
    }

    @Test func aRefusedJoinTellsThePhoneOnceAndRetriesEveryTwoMinutes() {
        var model = active()
        _ = model.tick(now: at(0), network: nil, internet: nil)
        _ = model.tick(now: at(20), network: nil, internet: nil)
        #expect(model.joined(error: "tmpErr", now: at(21)).contains(.notifyPhone(HotswitchModel.couldNotMove)))
        #expect(model.status == .failed(at: at(21)))
        #expect(model.tick(now: at(100), network: nil, internet: nil).isEmpty)
        #expect(model.tick(now: at(140), network: nil, internet: nil).contains(.join))
        let again = model.joined(error: "tmpErr", now: at(141))
        #expect(!again.contains(.notifyPhone(HotswitchModel.couldNotMove)))
    }

    @Test func workingWifiEndsTheOutage() {
        var model = active()
        _ = model.tick(now: at(0), network: nil, internet: nil)
        _ = model.tick(now: at(20), network: nil, internet: nil)
        _ = model.joined(error: "tmpErr", now: at(21))
        _ = model.tick(now: at(60), network: "Home", internet: true)
        #expect(model.status == nil)
        _ = model.tick(now: at(200), network: nil, internet: nil)
        _ = model.tick(now: at(220), network: nil, internet: nil)
        #expect(model.joined(error: "tmpErr", now: at(221)).contains(.notifyPhone(HotswitchModel.couldNotMove)))
    }

    @Test func noMoveWithinTenMinutesOfTheLast() {
        var model = onHotspot(at: 30)
        // macOS took the Mac back to Wi-Fi, which died again.
        _ = model.tick(now: at(100), network: "Home", internet: true)
        _ = model.tick(now: at(200), network: nil, internet: nil)
        #expect(model.tick(now: at(400), network: nil, internet: nil).isEmpty)
        #expect(model.tick(now: at(630), network: nil, internet: nil).contains(.join))
    }

    @Test func scansEveryTwoMinutesOnTheHotspot() {
        var model = onHotspot(at: 30)
        #expect(model.tick(now: at(100), network: "Law", internet: true).isEmpty)
        #expect(model.tick(now: at(150), network: "Law", internet: true) == [.scan])
        #expect(model.tick(now: at(155), network: "Law", internet: true).isEmpty)
    }

    @Test func leavesAfterTwoStrongScansInARow() {
        var model = onHotspot(at: 30)
        let home = HotswitchModel.Sighting(name: "Home", rssi: -55)
        #expect(model.scanned([home], now: at(150)).isEmpty)
        #expect(model.scanned([home], now: at(270)).contains(.leave))
        #expect(model.phase == .returning(to: "Home", since: at(270)))
    }

    @Test func aWeakScanStartsTheCountOver() {
        var model = onHotspot(at: 30)
        _ = model.scanned([.init(name: "Home", rssi: -55)], now: at(150))
        _ = model.scanned([.init(name: "Home", rssi: -80)], now: at(270))
        #expect(model.scanned([.init(name: "Home", rssi: -55)], now: at(390)).isEmpty)
    }

    @Test func backOnWifiWithInternetIsAQuietNote() {
        var model = onHotspot(at: 30)
        _ = model.scanned([.init(name: "Home", rssi: -55)], now: at(150))
        _ = model.scanned([.init(name: "Home", rssi: -55)], now: at(270))
        #expect(model.tick(now: at(290), network: "Home", internet: true).contains(.note(HotswitchModel.back(on: "Home"))))
        #expect(model.phase == .watching)
        #expect(model.status == nil)
    }

    @Test func wifiWithoutInternetSendsItBackAndIgnoresThatNetwork() {
        var model = onHotspot(at: 30)
        _ = model.scanned([.init(name: "Home", rssi: -55)], now: at(150))
        _ = model.scanned([.init(name: "Home", rssi: -55)], now: at(270))
        #expect(model.tick(now: at(300), network: "Home", internet: false).isEmpty)
        #expect(model.tick(now: at(330), network: "Home", internet: false).contains(.join))
        _ = model.joined(error: nil, now: at(331))
        _ = model.tick(now: at(335), network: "Law", internet: true)
        // Ignored for 15 minutes, even when strong.
        _ = model.scanned([.init(name: "Home", rssi: -40)], now: at(460))
        #expect(model.scanned([.init(name: "Home", rssi: -40)], now: at(580)).isEmpty)
        _ = model.scanned([.init(name: "Home", rssi: -40)], now: at(1_240))
        #expect(model.scanned([.init(name: "Home", rssi: -40)], now: at(1_360)).contains(.leave))
    }

    @Test func stayAwakeOffLeavesTheHotspot() {
        var model = onHotspot(at: 30)
        #expect(model.setActive(false).contains(.leave))
        #expect(model.phase == .watching)
    }

    @Test func stayAwakeOffDoesntLeaveAHotspotJoinedByHand() {
        var model = active()
        _ = model.tick(now: at(0), network: "Law", internet: true)
        #expect(model.setActive(false).isEmpty)
    }

    @Test func aJoinThatLandsAfterStayAwakeTurnedOffLeaves() {
        var model = active()
        _ = model.tick(now: at(0), network: nil, internet: nil)
        _ = model.tick(now: at(20), network: nil, internet: nil)
        _ = model.setActive(false)
        #expect(model.joined(error: nil, now: at(21)).contains(.leave))
        #expect(model.phase == .watching)
    }

    @Test func theHotspotDroppingDoesNothing() {
        var model = onHotspot(at: 30)
        #expect(model.tick(now: at(60), network: nil, internet: nil) == [.log("Dropped off Law")])
        #expect(model.phase == .watching)
    }

    @Test func resumedOnTheHotspotAfterARestart() {
        var model = active()
        model.resumeOnHotspot(now: at(0))
        #expect(model.holdsHotspot)
        #expect(model.tick(now: at(120), network: "Law", internet: true) == [.scan])
    }
}
