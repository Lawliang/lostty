#if os(macOS)
import Foundation

/// What hears a finished agent turn: the usage breakdown in every build,
/// the mascot's turn observer only where the mascot is.
enum TurnEnd {
    static func handler(
        channel: LosttyChannel,
        observe: @escaping @MainActor (UUID, String) -> Void,
        report: @escaping @MainActor (String) -> Void
    ) -> @MainActor (UUID, String) -> Void {
        let observes = channel.showsMascot
        return { pane, path in
            if observes { observe(pane, path) }
            // The usage breakdown counts this conversation as Claude Code in Lostty.
            report(path)
        }
    }
}
#endif
