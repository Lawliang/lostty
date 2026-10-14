import Foundation

/// A Claude session's context window, as the Mac's usage bar shows it:
/// written by the Mac into tmux (`@lostty_context`, "used,size" in
/// tokens), read by the phone for its top bar.
public struct SessionContext: Equatable, Sendable {
    public var used: Int
    public var size: Int

    public init(used: Int, size: Int) {
        self.used = used
        self.size = size
    }

    /// "84000,200000"; nil when it isn't one.
    public init?(encoded: String) {
        let parts = encoded.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let used = Int(parts[0]), let size = Int(parts[1]), used >= 0, size > 0 else {
            return nil
        }
        self.init(used: used, size: size)
    }

    public var encoded: String { "\(used),\(size)" }

    public var percent: Double { size > 0 ? Double(used) / Double(size) * 100 : 0 }
}

/// The usage bar's text meter, the same on the Mac and the phone: ten
/// cells, `▓` used and `░` free, turning amber past 70% and red past 90%.
public enum UsageMeter {
    public static let cells = 10

    public enum Level: Equatable, Sendable { case normal, high, critical }

    /// Used cells for `percent`: any use shows at least one.
    public static func filled(_ percent: Double, cells: Int = cells) -> Int {
        let p = min(max(percent, 0), 100)
        guard p > 0 else { return 0 }
        return min(cells, max(1, Int((p / 100 * Double(cells)).rounded())))
    }

    public static func level(_ percent: Double) -> Level {
        if percent >= 90 { return .critical }
        if percent >= 70 { return .high }
        return .normal
    }

    /// Tokens to the nearest thousand: 49_600 → "50K", 1_234_000 → "1,234K".
    public static func thousands(_ n: Int) -> String {
        let k = Int((Double(n) / 1_000).rounded())
        return k.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US"))) + "K"
    }
}
