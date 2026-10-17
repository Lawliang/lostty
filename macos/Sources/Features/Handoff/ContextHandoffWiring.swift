#if os(macOS)
import AppKit
import Combine
import Foundation

/// Connects the context handoff to the app (beta only): the usage feed,
/// the hooks' signals, the setting, typing into panes, and keys typed
/// while a handoff is pending.
@MainActor
enum ContextHandoffWiring {
    private static var watchers: Set<AnyCancellable> = []
    private static var keyMonitor: Any?

    static func project(pwd: String?) -> String {
        guard let pwd, !pwd.isEmpty else { return "Terminal" }
        let last = (pwd as NSString).lastPathComponent
        return last.isEmpty || last == "/" ? "Terminal" : last
    }

    static func showsRow(channel: LosttyChannel, isClaude: Bool) -> Bool {
        channel.showsMascot && isClaude
    }

    static func surface(_ pane: UUID) -> Ghostty.SurfaceView? {
        (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: pane)
    }

    /// Types into the pane's terminal; Return as a key press, so Claude's
    /// prompt takes it as Enter rather than pasted text.
    static func type(_ pane: UUID, _ keys: [ContextHandoffKey]) {
        guard let surface = surface(pane)?.surfaceModel else { return }
        for key in keys {
            switch key {
            case .text(let text): surface.sendText(text)
            case .enter:
                surface.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .press, mods: []))
                surface.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .release, mods: []))
            }
        }
    }

    static func start() {
        guard LosttyChannel.current.showsMascot, watchers.isEmpty else { return }
        let coordinator = ContextHandoffCoordinator.shared
        coordinator.restore()
        ClaudeRuntime.shared.handoffSignal = { pane, signal in coordinator.signal(pane, signal) }
        ClaudeUsageRuntime.shared.$contexts
            .sink { contexts in
                for (pane, context) in contexts { coordinator.contextChanged(pane, used: context.used, size: context.size) }
            }
            .store(in: &watchers)
        ContextHandoffPreferences.shared.$enabled
            .dropFirst()
            .sink { coordinator.settingChanged(enabled: $0) }
            .store(in: &watchers)
        // Every key typed in a terminal: one typed since the last prompt
        // means its prompt may hold half a message, so Lostty types nothing
        // there; one during a pending handoff calls it off. The key still
        // reaches the terminal.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if let view = NSApp.keyWindow?.firstResponder as? Ghostty.SurfaceView {
                    coordinator.keyTyped(view.id)
                }
            }
            return event
        }
    }
}
#endif
