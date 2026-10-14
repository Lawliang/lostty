#if os(macOS)
import Combine
import LosttyRemote
import SwiftUI

/// The axolotl at the foot of the window's sidebar, doing what the focused
/// pane's terminal is doing, as the phone's rows show it: waving while
/// Claude waits on you, dancing while it works, wagging its tail when
/// ready, asleep when idle. What it means, in words, above it.
struct SidebarMascot: View {
    let surfaceID: UUID?
    @ObservedObject private var claude = ClaudeRuntime.shared
    @ObservedObject private var activity = PaneActivity.shared

    var body: some View {
        // Each half minute, so ready turns idle on time.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let state = state(now: context.date) {
                VStack(spacing: 4) {
                    Text(state.title)
                        .font(.system(size: 10, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(state == .waiting || state == .working
                            ? LosttyTheme.accent : Color.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Axolotl(pose: Self.pose(state)).frame(width: 52, height: 52)
                }
                .frame(width: ExtensionSidebarView.width - 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.title)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: surfaceID.flatMap { state(id: $0, now: Date()) })
        .onAppear { activity.start() }
    }

    /// nil for a pane tmux doesn't know (no session yet) and Claude isn't in.
    private func state(now: Date) -> PaneState? {
        surfaceID.flatMap { state(id: $0, now: now) }
    }

    private func state(id: UUID, now: Date) -> PaneState? {
        let waiting = claude.awaiting.contains(id)
        let working = claude.phases[id] != nil
        let last = activity.lastActivity[id]
        guard waiting || working || activity.known.contains(id) else { return nil }
        return PaneState(waiting: waiting, working: working, lastActivity: last, now: now)
    }

    static func pose(_ state: PaneState) -> Axolotl.Pose {
        switch state {
        case .waiting: .waving
        case .working: .dancing
        case .ready: .ready
        case .idle: .sleeping
        }
    }
}

/// When each pane's tmux session was last typed into, read from tmux every
/// half minute and whenever the sessions change. App-wide: every window's
/// mascot reads it.
@MainActor
final class PaneActivity: ObservableObject {
    static let shared = PaneActivity()

    /// Panes with a session, by their surface id.
    @Published private(set) var known: Set<UUID> = []
    /// Their sessions' last input; missing when tmux didn't say.
    @Published private(set) var lastActivity: [UUID: Date] = [:]

    private var timer: Timer?
    private var changes: AnyCancellable?
    private var reading = false

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { PaneActivity.shared.refresh() }
        }
        changes = NotificationCenter.default.publisher(for: .losttySessionsChanged)
            .sink { _ in MainActor.assumeIsolated { PaneActivity.shared.refresh() } }
        refresh()
    }

    func refresh() {
        guard !reading else { return }
        reading = true
        Task.detached(priority: .utility) {
            let sessions = TmuxClient().sessionListing()
            await MainActor.run { PaneActivity.shared.update(sessions) }
        }
    }

    private func update(_ sessions: [RemoteSession]) {
        reading = false
        var known: Set<UUID> = []
        var last: [UUID: Date] = [:]
        for session in sessions {
            guard let id = session.surface.flatMap(UUID.init(uuidString:)) else { continue }
            known.insert(id)
            last[id] = session.activity
        }
        if known != self.known { self.known = known }
        if last != lastActivity { lastActivity = last }
    }
}
#endif
