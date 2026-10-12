#if os(macOS)
import Foundation

/// Text for the Branches rows. Pure.
enum BranchesFormat {
    static func aheadBehind(_ value: AheadBehind?) -> String? {
        guard let value else { return nil }
        if value.ahead == 0 && value.behind == 0 { return "even" }
        return [value.ahead > 0 ? "↑\(value.ahead)" : nil, value.behind > 0 ? "↓\(value.behind)" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    static func upstream(_ upstream: Upstream) -> String {
        switch upstream {
        case .none:
            return "Not pushed"
        case .gone(let name):
            return "\(name) was deleted"
        case .tracking(let name, 0, 0):
            return "Up to date with \(name)"
        case .tracking(let name, let ahead, 0):
            return "\(ahead) to push to \(name)"
        case .tracking(let name, 0, let behind):
            return "\(behind) to pull from \(name)"
        case .tracking(let name, let ahead, let behind):
            return "\(ahead) to push, \(behind) to pull · \(name)"
        }
    }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// The first letter of a pane title, skipping agent spinners and symbols.
    static func initial(_ title: String) -> String {
        guard let letter = title.first(where: \.isLetter) else { return "•" }
        return String(letter).uppercased()
    }

    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
#endif
