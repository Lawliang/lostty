#if os(macOS)
import AppKit
import Combine
import LosttyRemote
import SwiftUI

/// The axolotl standing in the terminal's bottom-right corner, doing what
/// the focused pane's terminal is doing, as the phone's rows show it:
/// waving while Claude waits on you, dancing while it works, wagging its
/// tail when ready, asleep when idle. Tap it for its bubble: what's been
/// done in this conversation and the last reply in plain words.
struct SidebarMascot: View {
    let surfaceID: UUID?
    /// The tallest the bubble gets before it scrolls: half the terminal.
    var bubbleMaxHeight: CGFloat = 400
    @ObservedObject private var claude = ClaudeRuntime.shared
    @ObservedObject private var activity = PaneActivity.shared
    @ObservedObject private var observer = TurnObserver.shared
    /// The pane whose bubble is open.
    @State private var openPane: UUID?
    /// When the bubble last closed: the click on the mascot that closes a
    /// transient popover must not open it again on mouse-up.
    @State private var closedAt = Date.distantPast
    @State private var escape = EscapeKeyMonitor()

    var body: some View {
        // Each half minute, so ready turns idle on time.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let state = state(now: context.date)
            if Self.isShown(state: state, bubbleOpen: openPane != nil) {
                Button(action: toggle) {
                    Axolotl(pose: openPane != nil ? .happy : state.map(Self.pose) ?? .resting).frame(width: 56, height: 56)
                        .background(alignment: .bottom) { MascotPlatform() }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state?.title ?? "Lostty")
                .accessibilityHint("Shows what's been done in this terminal")
                .popover(isPresented: bubbleShown, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        MascotBubble(content: bubbleContent, maxHeight: bubbleMaxHeight)
                        if let id = openPane, ContextHandoffWiring.showsRow(
                            channel: .current, isClaude: ClaudeUsageRuntime.shared.sessions.contains(id)) {
                            ContextHandoffBubbleRow(pane: id)
                        }
                    }
                }
                .transition(.opacity)
                // Belt and braces: the bubble's anchor gone means it's closed.
                .onDisappear { close() }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: surfaceID.flatMap { state(id: $0, now: Date()) })
        .onAppear { activity.start() }
        // Focus moving to another pane closes the bubble.
        .onChange(of: surfaceID) { _ in close() }
        .onDisappear { close() }
    }

    private var bubbleShown: Binding<Bool> {
        Binding(get: { openPane != nil }, set: { shown in if !shown { close() } })
    }

    private var bubbleContent: BubbleContent {
        guard let id = openPane else { return .message(TurnObserver.nothingYet) }
        return observer.content(pane: id, working: claude.phases[id] != nil)
    }

    private func toggle() {
        if openPane != nil {
            close()
            return
        }
        guard Date().timeIntervalSince(closedAt) > 0.3, let id = surfaceID else { return }
        observer.open(pane: id, working: claude.phases[id] != nil)
        openPane = id
        escape.start { close() }
    }

    private func close() {
        escape.stop()
        guard let id = openPane else { return }
        openPane = nil
        closedAt = Date()
        observer.close(pane: id)
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

    /// Whether the mascot stands in the corner.
    static func isShown(state: PaneState?, bubbleOpen: Bool) -> Bool {
        state != nil || bubbleOpen
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

/// While the bubble is open, Esc closes it instead of reaching the
/// terminal, where it would interrupt Claude.
@MainActor
private final class EscapeKeyMonitor {
    private var monitor: Any?

    func start(_ onEscape: @escaping @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { onEscape() }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
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
