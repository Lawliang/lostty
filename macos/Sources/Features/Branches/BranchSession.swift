#if os(macOS)
import Foundation

/// What an agent in a pane is doing, as Lostty's Claude wiring knows it.
/// Lostty can't tell Claude from Codex, and only knows "idle" for Claude.
enum AgentState: Equatable, Sendable {
    case working
    case idle
    /// Finished or asking while you were looking elsewhere.
    case waiting
}

/// A Lostty session: a pane on the Mac, or a tmux session only the phone shows.
struct BranchSession: Identifiable, Equatable, Sendable {
    enum Origin: Hashable, Sendable {
        case pane(UUID)
        case phone(sessionID: String)
    }

    var origin: Origin
    var title: String
    var pwd: String
    var agent: AgentState?

    var id: Origin { origin }
    var isPhone: Bool {
        if case .phone = origin { return true }
        return false
    }
}
#endif
