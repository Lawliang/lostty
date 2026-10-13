#if os(macOS) && DEBUG
import AppKit
import LosttyRemote
import SwiftUI

/// Debug only: the Phone Access window in each state, for review.
@MainActor
enum PhoneAccessGallery {
    private static var window: NSWindow?

    static func show() {
        let all = variants()
        let content = TabView {
            ForEach(all.indices, id: \.self) { index in
                PhoneAccessView().environmentObject(all[index].1)
                    .tabItem { Text(all[index].0) }
            }
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "Phone Access Design Gallery"
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 600, height: 760))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    /// Each state, titled; also rendered to PNGs by `LosttyRenderTests`.
    static func variants() -> [(String, PhoneAccessStore)] {
        let ready = PhoneAccessStatus(
            tailscale: .init(running: true, name: "studio-mac.example.ts.net", ipv4: "100.64.0.10"),
            tmuxPath: "/opt/homebrew/bin/tmux", remoteLogin: true, authMethods: ["publickey"],
            lockdownFileExists: true, blockAllIncoming: false, terminfoInstalled: true,
            folders: ["Desktop": true, "Documents": true, "Downloads": true], dropsLostConnections: true)
        var mixed = ready
        mixed.dropsLostConnections = false
        mixed.authMethods = ["publickey", "password"]
        mixed.lockdownFileExists = false
        mixed.terminfoInstalled = false
        mixed.folders = nil
        let phones = [
            PairedPhone(id: "a", name: "iPhone 13", paired: Date(timeIntervalSince1970: 1_791_000_000)),
            PairedPhone(id: "b", name: "Alex's other iPhone", paired: nil),
        ]
        let payload = try? PairingPayload(
            name: "studio-mac.example.ts.net", ip: "100.64.0.10", user: "alex",
            hostKey: "AAAAC3NzaC1lZDI1NTE5AAAAIO2ib6szt8DC6VJejVmS+ZXbDzWg/68qdlqbp2uhPYfl",
            secret: Data(repeating: 7, count: 32))
        return [
            ("All ready, two phones", .gallery(status: ready, phones: phones)),
            ("Mixed checklist, no phones", .gallery(status: mixed)),
            ("Password logins skipped", .gallery(status: mixed, lockdownSkipped: true)),
            ("Pairing sheet", .gallery(status: ready, pairing: payload.map { .showing($0, expires: Date().addingTimeInterval(75)) })),
            ("Expired code", .gallery(status: ready, pairing: .expired)),
        ]
    }
}
#endif
