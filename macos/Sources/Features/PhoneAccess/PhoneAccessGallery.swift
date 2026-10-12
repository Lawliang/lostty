#if os(macOS) && DEBUG
import AppKit
import LosttyRemote
import SwiftUI

/// Debug only: the Phone Access window in each state, for review.
@MainActor
enum PhoneAccessGallery {
    private static var window: NSWindow?

    static func show() {
        let ready = PhoneAccessStatus(
            tailscale: .init(running: true, name: "laws-macbook-pro.tail278d1f.ts.net", ipv4: "100.126.63.10"),
            tmuxPath: "/opt/homebrew/bin/tmux", remoteLogin: true, authMethods: ["publickey"],
            lockdownFileExists: true, blockAllIncoming: false, terminfoInstalled: true,
            folders: ["Desktop": true, "Documents": true, "Downloads": true])
        var mixed = ready
        mixed.authMethods = ["publickey", "password"]
        mixed.lockdownFileExists = false
        mixed.terminfoInstalled = false
        mixed.folders = nil
        let phones = [
            PairedPhone(id: "a", name: "iPhone 13", paired: Date(timeIntervalSince1970: 1_791_000_000)),
            PairedPhone(id: "b", name: "Law's other iPhone", paired: nil),
        ]
        let payload = try? PairingPayload(
            name: "laws-macbook-pro.tail278d1f.ts.net", ip: "100.126.63.10", user: "lawliang",
            hostKey: "AAAAC3NzaC1lZDI1NTE5AAAAIO2ib6szt8DC6VJejVmS+ZXbDzWg/68qdlqbp2uhPYfl",
            secret: Data(repeating: 7, count: 32))
        let variants: [(String, PhoneAccessStore)] = [
            ("All ready, two phones", .gallery(status: ready, phones: phones)),
            ("Mixed checklist, no phones", .gallery(status: mixed)),
            ("Password logins skipped", .gallery(status: mixed, lockdownSkipped: true)),
            ("Pairing sheet", .gallery(status: ready, pairing: payload.map { .showing($0, expires: Date().addingTimeInterval(75)) })),
            ("Expired code", .gallery(status: ready, pairing: .expired)),
        ]
        let content = TabView {
            ForEach(variants.indices, id: \.self) { index in
                PhoneAccessView().environmentObject(variants[index].1)
                    .tabItem { Text(variants[index].0) }
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
}
#endif
