#if os(macOS)
import Foundation

/// What hears a finished agent turn: the usage breakdown in every build,
/// the turn observer only while it's on (`LosttyChannel.observesTurns`).
enum TurnEnd {
    static func handler(
        observes: Bool,
        observe: @escaping @MainActor (UUID, String) -> Void,
        report: @escaping @MainActor (String) -> Void
    ) -> @MainActor (UUID, String) -> Void {
        { pane, path in
            if observes { observe(pane, path) }
            // The usage breakdown counts this conversation as Claude Code in Lostty.
            report(path)
        }
    }
}
#endif
