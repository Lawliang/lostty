#if os(macOS) && DEBUG
import AppKit
import LosttyRemote

/// Lostty Mobile, debug builds only: opens one of this Mac's tmux sessions
/// over SSH to localhost through the remote backend, proving the core and
/// LosttyRemote before the iPhone app exists. Needs Remote Login on and the
/// key from "Copy Remote Key" in ~/.ssh/authorized_keys.
@MainActor
enum RemoteDebugUI {
    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty", isDirectory: true)
    }
    static var keyURL: URL { supportDir.appendingPathComponent("remote-key") }
    static var knownHostsURL: URL { supportDir.appendingPathComponent("known_hosts") }
    static var host: RemoteHost {
        RemoteHost.localhost(terminfoDir: Bundle.main.resourceURL!.appendingPathComponent("terminfo").path)
    }

    static func installMenuItems(after anchor: NSMenuItem) {
        guard let menu = anchor.menu else { return }
        let open = NSMenuItem(title: "Open Remote Session…", action: #selector(Actions.open(_:)), keyEquivalent: "")
        let copy = NSMenuItem(title: "Copy Remote Key", action: #selector(Actions.copyKey(_:)), keyEquivalent: "")
        for item in [open, copy] {
            item.target = Actions.shared
        }
        let index = menu.index(of: anchor) + 1
        menu.insertItem(copy, at: index)
        menu.insertItem(open, at: index)
    }

    @MainActor
    final class Actions: NSObject {
        static let shared = Actions()

        @objc func copyKey(_ sender: Any?) {
            do {
                let key = try RemoteKey.secureEnclave(storedAt: RemoteDebugUI.keyURL)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key.publicKeyLine + "\n", forType: .string)
            } catch {
                RemoteDebugUI.show(error)
            }
        }

        @objc func open(_ sender: Any?) {
            guard #available(macOS 15, *) else {
                RemoteDebugUI.show(message: "Remote sessions need macOS 15 or later.")
                return
            }
            Task { @MainActor in await RemoteDebugUI.open() }
        }
    }

    @available(macOS 15, *)
    static func open() async {
        guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }
        do {
            let key = try RemoteKey.secureEnclave(storedAt: keyURL)
            let knownHosts = KnownHosts(fileURL: knownHostsURL)
            let connection = try await RemoteConnection.connect(to: host, key: key, knownHosts: knownHosts)
            let sessions = try await connection.sessions()
            await connection.close()
            guard let session = pick(sessions) else { return }

            var config = Ghostty.SurfaceConfiguration()
            config.remoteIO = RemoteSurfaceIO(attacher: SSHAttacher(
                host: host, key: key, knownHosts: knownHosts, sessionID: session.id))
            _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
        } catch {
            show(error)
        }
    }

    /// Asks which session to open; nil when there are none or on Cancel.
    static func pick(_ sessions: [RemoteSession]) -> RemoteSession? {
        guard !sessions.isEmpty else {
            show(message: "No Lostty tmux sessions are running on this Mac.")
            return nil
        }
        let alert = NSAlert()
        alert.messageText = "Open Remote Session"
        alert.informativeText = "Opens the session over SSH to localhost, as the phone will."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        popup.addItems(withTitles: sessions.map { "\($0.name) (\($0.id))" })
        alert.accessoryView = popup
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return sessions[popup.indexOfSelectedItem]
    }

    static func show(_ error: Error) {
        show(message: (error as? RemoteError)?.message ?? error.localizedDescription)
    }

    static func show(message: String) {
        let alert = NSAlert()
        alert.messageText = "Lostty Remote"
        alert.informativeText = message
        alert.runModal()
    }
}
#endif
