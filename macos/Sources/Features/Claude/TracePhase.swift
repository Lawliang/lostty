#if os(macOS)
import Foundation

/// One pane's trace: racing while Claude works, gone the moment it stops.
/// `subagents`: Claude finished its turn but its subagents or background
/// shells are still working, so the head keeps to the bottom edge.
enum TracePhase: Equatable {
    case off
    case racing(since: Date, subagents: Bool = false)

    var isOff: Bool { self == .off }

    /// Claude finished its turn; only its subagents or shells still work.
    var subagentsOnly: Bool {
        if case .racing(_, true) = self { true } else { false }
    }

    func applying(_ state: ClaudeState, now: Date) -> TracePhase {
        switch (state, self) {
        case (.busy, .off): .racing(since: now)
        case (.busy, .racing(let since, _)): .racing(since: since)
        case (.agents, .off): .racing(since: now, subagents: true)
        case (.agents, .racing(let since, _)): .racing(since: since, subagents: true)
        case (.resumed, .racing(let since, _)): .racing(since: since)
        case (.resumed, .off): .off
        case (.idle, _), (.exit, _): .off
        }
    }
}

#endif
