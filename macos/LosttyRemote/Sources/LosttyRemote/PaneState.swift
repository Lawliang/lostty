import Foundation

/// What a Mac pane's terminal is doing, by the phone's rows' rules: Claude
/// waiting on you (finished or asking, and you haven't looked), working,
/// else ready if typed into lately, else idle. For the mascot at the foot
/// of the Mac window's sidebar.
public enum PaneState: Equatable, Sendable {
    case waiting, working, ready, idle

    public init(waiting: Bool, working: Bool, lastActivity: Date?, now: Date) {
        if waiting {
            self = .waiting
        } else if working {
            self = .working
        } else if let lastActivity, now.timeIntervalSince(lastActivity) < SessionLabel.idleAfter {
            self = .ready
        } else {
            self = .idle
        }
    }

    public var title: String {
        switch self {
        case .waiting: "Waiting on you"
        case .working: "Working\u{2026}"
        case .ready: "Ready"
        case .idle: "Idle"
        }
    }
}
