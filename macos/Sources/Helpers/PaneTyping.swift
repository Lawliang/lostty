#if os(macOS)
import AppKit

/// Finds a pane's terminal and types into it.
@MainActor
enum PaneTyping {
    enum Key: Equatable {
        case text(String)
        case enter
    }

    static func surface(_ pane: UUID) -> Ghostty.SurfaceView? {
        (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: pane)
    }

    /// Types into the pane's terminal; Return as a key press, so an agent's
    /// prompt takes it as Enter rather than pasted text.
    static func type(_ pane: UUID, _ keys: [Key]) {
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

    /// Tells `ClaudeRuntime` of every key typed in a terminal. The key
    /// still reaches the terminal, but for one typed into a sleeping pane:
    /// that wakes it, and its shell must get the resume alone. Shortcuts
    /// with ⌘ go on to the menus and don't wake it.
    static func watchKeys() {
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                guard let view = NSApp.keyWindow?.firstResponder as? Ghostty.SurfaceView else { return event }
                if PaneSleep.shared.isVeiled(view.id) {
                    guard !event.modifierFlags.contains(.command) else { return event }
                    PaneSleep.shared.wake(view.id)
                    return nil
                }
                ClaudeRuntime.shared.keyTyped(view.id)
                return event
            }
        }
    }
}
#endif
