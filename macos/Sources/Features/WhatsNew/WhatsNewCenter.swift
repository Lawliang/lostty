#if os(macOS)
import AppKit
import Combine
import Sparkle

/// Tells you about a new Lostty. A ready one (installed over this one, or
/// downloaded by the updater) posts a banner with Restart to Update on
/// every window; the next window you open shows a card with what's in it.
/// The first window on a new build shows what's new in it, once.
@MainActor
final class WhatsNewCenter: ObservableObject {
    static let shared = WhatsNewCenter()

    /// The card showing, and the window it shows in (its sidebar model).
    struct Showing {
        let card: WhatsNewCard
        let window: ObjectIdentifier
    }

    @Published private(set) var showing: Showing?

    static let seenBuildsKey = "LosttyWhatsNewSeenBuilds"
    static let seenHeadlineKey = "LosttyWhatsNewSeenHeadline"

    private let defaults: UserDefaults
    private var running: WhatsNewBuild
    /// The build Restart to Update would switch to.
    private var pending: WhatsNewBuild?
    private var watchers: Set<AnyCancellable> = []
    /// The ready build the banner was posted for, so it's posted once.
    private var bannered: [String]?

    init(defaults: UserDefaults = .ghostty, running: WhatsNewBuild = .installed(atPath: Bundle.main.bundlePath)) {
        self.defaults = defaults
        self.running = running
    }

    private var seen: WhatsNewSeen {
        get {
            WhatsNewSeen(builds: defaults.stringArray(forKey: Self.seenBuildsKey) ?? [],
                         headline: defaults.string(forKey: Self.seenHeadlineKey))
        }
        set {
            defaults.set(newValue.builds, forKey: Self.seenBuildsKey)
            defaults.set(newValue.headline, forKey: Self.seenHeadlineKey)
        }
    }

    /// Watches for a ready build: one installed over this Lostty
    /// (BundleWatch), or an update the updater found or downloaded.
    func start(updates: UpdateViewModel) {
        BundleWatch.shared.$updateReady
            .combineLatest(updates.$state)
            .sink { [weak self] ready, state in self?.refresh(ready: ready, state: state) }
            .store(in: &watchers)
    }

    private func refresh(ready: Bool, state: UpdateState) {
        if ready {
            pending = .installed(atPath: LosttyRestart.bundlePath)
        } else {
            switch state {
            // The update the updater offers, or has downloaded and waits to
            // put in.
            case .updateAvailable(let available): pending = .update(available.appcastItem)
            case .installing(let installing): pending = installing.appcastItem.map(WhatsNewBuild.update) ?? pending
            // Still the update it found, on its way.
            case .downloading, .extracting: break
            default: pending = nil
            }
        }
        postBanner()
    }

    /// The banner, once for each ready build; gone when none is.
    private func postBanner() {
        guard let pending else {
            if bannered != nil { LosttyNotifications.shared.dismiss(kind: .update) }
            bannered = nil
            return
        }
        guard bannered != pending.ids else { return }
        bannered = pending.ids
        let headline = WhatsNewCard.notes(for: pending, seenHeadline: seen.headline)?.headline
        LosttyNotifications.shared.post(LosttyNotification(
            kind: .update, style: .update,
            title: "A new Lostty is ready",
            detail: headline.map { "\($0). Your terminals stay open." } ?? "Restart to switch to it. Your terminals stay open.",
            actionTitle: "Restart to Update",
            action: { WhatsNewCenter.shared.restart() },
            persistent: true))
    }

    /// A window opened: it shows the card due, if no other window is.
    func windowOpened(_ window: ObjectIdentifier) {
        guard showing == nil else { return }
        let next = WhatsNewCard.next(running: running, pending: pending, seen: seen)
        var seen = seen
        for build in next.record { seen.record(build) }
        self.seen = seen
        if let card = next.card { showing = Showing(card: card, window: window) }
    }

    /// Its window closed; the card isn't shown again.
    func windowClosed(_ window: ObjectIdentifier) {
        if showing?.window == window { showing = nil }
    }

    func dismiss() {
        showing = nil
    }

    /// Into the ready build, keeping every terminal: Restart to Update for
    /// one installed over this Lostty; the updater's install and relaunch
    /// for one it found.
    func restart() {
        showing = nil
        if BundleWatch.shared.updateReady {
            LosttyRestart.restart(reason: .menu)
            return
        }
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        if case .installing(let installing) = delegate.updateViewModel.state {
            installing.retryTerminatingApplication()
        } else {
            delegate.updateController.installUpdate()
        }
    }
}

extension WhatsNewBuild {
    static func update(_ item: SUAppcastItem) -> WhatsNewBuild {
        update(version: item.versionString, title: item.title, description: item.itemDescription)
    }
}
#endif
