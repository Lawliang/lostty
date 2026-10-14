#if os(macOS)
import AppKit
import Combine

/// Restart to Update in Lostty's app menu, shown once a new build is
/// installed (BundleWatch).
@MainActor
enum RestartUI {
    private static var watcher: AnyCancellable?

    static func installMenuItem(after anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Restart to Update (Keeps Terminals)", action: #selector(Target.restart), keyEquivalent: "")
        item.target = Target.shared
        item.isHidden = true
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
        watcher = BundleWatch.shared.$updateReady.sink { item.isHidden = !$0 }
    }

    final class Target: NSObject {
        static let shared = Target()

        @objc func restart() {
            MainActor.assumeIsolated { LosttyRestart.restart(reason: .menu) }
        }
    }
}
#endif
