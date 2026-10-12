#if os(macOS)
import IOKit.ps
import Testing
@testable import Ghostty

struct PowerReaderTests {
    @Test func percentFromTheInternalBattery() {
        let internalBattery: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 64, kIOPSMaxCapacityKey: 100,
        ]
        let ups: [String: Any] = [kIOPSTypeKey: kIOPSUPSType, kIOPSCurrentCapacityKey: 10, kIOPSMaxCapacityKey: 100]
        let r = PowerReader.battery(providing: kIOPSBatteryPowerValue, descriptions: [ups, internalBattery])
        #expect(r.onBattery)
        #expect(r.percent == 64)
    }

    @Test func onPowerAndNoBattery() {
        let r = PowerReader.battery(providing: kIOPSACPowerValue, descriptions: [])
        #expect(!r.onBattery)
        #expect(r.percent == nil)
    }

    @Test func scalesWhenMaxIsNotHundred() {
        let b: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 2500, kIOPSMaxCapacityKey: 5000]
        #expect(PowerReader.battery(providing: kIOPSACPowerValue, descriptions: [b]).percent == 50)
    }
}
#endif
