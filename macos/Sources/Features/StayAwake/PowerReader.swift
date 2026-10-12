#if os(macOS)
import Foundation
import IOKit
import IOKit.ps

enum PowerReader {
    static func read() -> PowerState {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? ?? kIOPSACPowerValue
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as Array
        let descriptions = list.compactMap {
            IOPSGetPowerSourceDescription(info, $0 as CFTypeRef)?.takeUnretainedValue() as? [String: Any]
        }
        let battery = battery(providing: providing, descriptions: descriptions)
        return PowerState(
            lidClosed: lidClosed(), onBattery: battery.onBattery, batteryPercent: battery.percent,
            thermal: Thermal(ProcessInfo.processInfo.thermalState))
    }

    static func battery(providing: String, descriptions: [[String: Any]]) -> (onBattery: Bool, percent: Int?) {
        let internalBattery = descriptions.first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
        let percent: Int? = internalBattery.flatMap { d in
            guard let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { return nil }
            return current * 100 / max
        }
        return (providing == kIOPSBatteryPowerValue, percent)
    }

    /// `AppleClamshellState` on the power-management root.
    private static func lidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }
}
#endif
