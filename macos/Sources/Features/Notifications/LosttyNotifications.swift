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

        /// Bubbles in the same slot replace each other (a connect result
        /// takes the place of its agent's "not connected" bubble).
        var slot: String {
            switch self {
            case .hooksMissing(let agent), .hooks(let agent): "hooks-\(agent.rawValue)"
            }
        }
    }

    /// Sets the bubble's icon and color.
    enum Style { case attention, success, failure }

    let id = UUID()
    let kind: Kind
    var style: Style = .attention
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (@MainActor () -> Void)?
}

/// App-wide notification bubbles, shown in the top-right of each terminal
/// window. A bubble fades `lifetime` seconds after a window first shows it;
/// hovering keeps it, and leaving restarts the countdown.
@MainActor
final class LosttyNotifications: ObservableObject {
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    static let shared = LosttyNotifications()
    static let lifetime: TimeInterval = 8

    @Published private(set) var items: [LosttyNotification] = []

    private let schedule: Scheduler
    private var shown: Set<UUID> = []
    private var hovering: Set<UUID> = []
    private var generation: [UUID: Int] = [:]

    init(schedule: @escaping Scheduler = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
    }) {
        self.schedule = schedule
    }

    func post(_ notification: LosttyNotification) {
        if let index = items.firstIndex(where: { $0.kind.slot == notification.kind.slot }) {
            forget(items[index].id)
            items[index] = notification
        } else {
            items.append(notification)
        }
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        forget(id)
    }

    /// A window displayed the bubble: start its countdown (once).
    func markShown(_ id: UUID) {
        guard items.contains(where: { $0.id == id }), !shown.contains(id) else { return }
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
