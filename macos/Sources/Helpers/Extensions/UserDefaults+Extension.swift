import Foundation

extension UserDefaults {
    static var ghosttySuite: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["GHOSTTY_USER_DEFAULTS_SUITE"]
        #else
        nil
        #endif
    }

    static let ghostty: UserDefaults = ghosttySuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
}
