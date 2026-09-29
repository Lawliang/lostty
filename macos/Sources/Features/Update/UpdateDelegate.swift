import Sparkle
import Cocoa

extension UpdateDriver: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        // Ghostty Skins: this fork does not publish its own appcast, and
        // must never point at upstream Ghostty's feed — doing so would let
        // "Check for Updates…" offer to replace this fork with official
        // Ghostty. Returning nil here (with no `SUFeedURL` in
        // Ghostty-Info.plist to fall back to) leaves Sparkle with no feed
        // URL at all, so a manual check surfaces a "no update information"
        // error instead of silently reaching for the real ghostty.org feed.
        // See UPGRADING.md.
        return nil
    }

    /// Called when an update is scheduled to install silently,
    /// which occurs when `auto-update = download`.
    ///
    /// When `auto-update = check`, Sparkle will call the corresponding
    /// delegate method on the responsible driver instead.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        viewModel.state = .installing(.init(
            isAutoUpdate: true,
            retryTerminatingApplication: immediateInstallHandler,
            dismiss: { [weak viewModel] in
                viewModel?.state = .idle
            }
        ))
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // When the updater is relaunching the application we want to get macOS
        // to invalidate and re-encode all of our restorable state so that when
        // we relaunch it uses it.
        NSApp.invalidateRestorableState()
        for window in NSApp.windows { window.invalidateRestorableState() }
    }
}
