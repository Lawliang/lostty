#if os(macOS)
import Foundation
import Combine

/// A coding agent whose hooks Lostty installs.
enum HookAgent: String, CaseIterable {
    case claude, codex

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// The agent's config folder in the home directory; it exists when the
    /// agent is installed.
    var configDirectory: String {
        switch self {
        case .claude: ".claude"
        case .codex: ".codex"
        }
    }
}

/// One bubble in the top-right notification stack.
struct LosttyNotification: Identifiable {
    enum Kind: Hashable {
        /// The agent is installed but Lostty's hooks are not set up.
        case hooksMissing(HookAgent)
        /// The outcome of connecting the agent's hooks.
        case hooks(HookAgent)
        /// Context handoffs that didn't reach their fresh windows, in one bubble.
        case handoff
        /// A new Lostty is ready for Restart to Update.
        case update
        /// Canvas cards that left the zone with this title, in one bubble.
        case zoneLeft(String)
        /// A pane's agent messaged one outside its zone, and was stopped.
        case keptInside(pane: UUID)

        /// Bubbles in the same slot replace each other (a connect result
        /// takes the place of its agent's "not connected" bubble).
        var slot: String {
            switch self {
            case .hooksMissing(let agent), .hooks(let agent): "hooks-\(agent.rawValue)"
            case .handoff: "handoff"
            case .update: "update"
            case .zoneLeft(let zone): "zone-left-\(zone)"
            case .keptInside(let pane): "kept-inside-\(pane.uuidString)"
            }
        }
    }

    /// Sets the bubble's icon color.
    enum Style { case attention, success, failure, update }

    let id = UUID()
    let kind: Kind
    var style: Style = .attention
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (@MainActor () -> Void)?
    /// A second, quieter button beside the action.
    var secondaryTitle: String?
    var secondaryAction: (@MainActor () -> Void)?
    /// Clicking the bubble itself: goes to what it's about.
    var open: (@MainActor () -> Void)?
    /// What a bubble for several events stands for, oldest first: the
    /// cards that left a zone, or the handoffs that didn't finish.
    var group: [String] = []
    /// The canvas project zone it's about: it stacks with the zone's others.
    var zone: UUID?
    var posted = Date()

    /// A bubble with a button waits for it; the rest fade.
    var stays: Bool { actionTitle != nil || secondaryTitle != nil }

    /// The time in the bubble's corner: "now", "4m ago", "2h ago".
    static func age(of posted: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(posted))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

/// App-wide notification bubbles, newest first, shown at the top right of
/// the frontmost window, stacked by zone (`NotificationGroup`). A bubble without a button fades `lifetime`
/// seconds after it's first shown; hovering keeps it, and leaving restarts
/// the countdown.
@MainActor
final class LosttyNotifications: ObservableObject {
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    static let shared = LosttyNotifications()
    static let lifetime: TimeInterval = 6

    @Published private(set) var items: [LosttyNotification] = []
    /// The window showing the bubbles: the last one with a stack to be key.
    @Published private(set) var front: ObjectIdentifier?

    private let schedule: Scheduler
    private var shown: Set<UUID> = []
    private var hovering: Set<UUID> = []
    private var generation: [UUID: Int] = [:]

    init(schedule: @escaping Scheduler = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
    }) {
        self.schedule = schedule
    }

    /// On top, in place of the bubble in its slot.
    func post(_ notification: LosttyNotification) {
        if let index = items.firstIndex(where: { $0.kind.slot == notification.kind.slot }) {
            forget(items[index].id)
            items.remove(at: index)
        }
        items.insert(notification, at: 0)
    }

    /// The bubble up in `kind`'s slot, to add to.
    func current(_ kind: LosttyNotification.Kind) -> LosttyNotification? {
        items.first { $0.kind.slot == kind.slot }
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        forget(id)
    }

    /// The bubble in `kind`'s slot, if one is up.
    func dismiss(kind: LosttyNotification.Kind) {
        for item in items where item.kind.slot == kind.slot { dismiss(item.id) }
    }

    /// A window displayed the bubble: start its countdown (once).
    func markShown(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), !item.stays, !shown.contains(id) else { return }
        shown.insert(id)
        countdown(id)
    }

    func setHovering(_ id: UUID, _ isHovering: Bool) {
        if isHovering {
            hovering.insert(id)
        } else {
            hovering.remove(id)
            if shown.contains(id) { countdown(id) }
        }
    }

    /// A window with a stack became key: the bubbles move to it.
    func show(in window: ObjectIdentifier) { front = window }

    func windowClosed(_ window: ObjectIdentifier) {
        if front == window { front = nil }
    }

    private func countdown(_ id: UUID) {
        let token = (generation[id] ?? 0) + 1
        generation[id] = token
        schedule(Self.lifetime) { [weak self] in
            guard let self, self.generation[id] == token, !self.hovering.contains(id) else { return }
            self.dismiss(id)
        }
    }

    private func forget(_ id: UUID) {
        shown.remove(id)
        hovering.remove(id)
        generation[id] = nil
    }
}
#endif
