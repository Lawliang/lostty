import Foundation

/// A friendly name for the phone in the Mac's Allow prompt. iOS only gives
/// apps the user's own device name with a special entitlement, so Lostty
/// sends the model instead.
public enum DeviceModel {
    static let names: [String: String] = [
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e",
    ]

    /// "iPhone" for models not in the table.
    public static func name(forIdentifier identifier: String) -> String {
        names[identifier] ?? "iPhone"
    }

    #if os(iOS)
    /// This phone's name; the simulator reports the model it simulates.
    public static var current: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return name(forIdentifier: simulated)
        }
        var info = utsname()
        uname(&info)
        let identifier = withUnsafeBytes(of: info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return name(forIdentifier: identifier)
    }
    #endif
}
