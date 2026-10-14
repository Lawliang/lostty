#if os(macOS)
import AppKit

/// Handler for the `restart to update` AppleScript command (`Ghostty.sdef`):
/// for `install-skins.sh --previous` and agents.
@MainActor
@objc(LosttyScriptRestartCommand)
final class ScriptRestartCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard NSApp.validateScript(command: self) else { return nil }
        // After this event's reply: quitting inside it leaves the script waiting.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { LosttyRestart.restart(reason: .script) }
        }
        return nil
    }
}
#endif
