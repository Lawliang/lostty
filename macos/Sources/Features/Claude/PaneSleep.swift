#if os(macOS)
import Foundation

/// What sleep keeps of a pane's Claude while it's gone: enough to resume
/// the same conversation under the same name, and for the hooks
/// (`+claude-state tool`) to know a SendMessage's target sleeps.
struct SleepingAgent: Codable, Equatable {
    let pane: UUID
    /// The conversation's id, a UUID.
    let sessionId: String
    /// The Claude session name its peers message it by.
    let name: String
    /// The tmux session showing the pane, for the hooks' zone check.
    let tmux: String
    let folder: String
    /// The model it was on, as `--model` takes it.
    var model: String?

    /// Typed at the pane's shell prompt to wake it.
    var resumeCommand: String {
        let quote = Ghostty.Shell.quote
        let flag = model.flatMap { PaneConversation.isModel($0) ? " --model \(quote($0))" : nil } ?? ""
        return "cd \(quote(folder)) && claude --resume \(quote(sessionId)) --name \(quote(name))" + flag
    }
}

/// A pane's place in the sleep cycle. A pane with none is awake.
enum SleepPhase: Equatable {
    /// `/exit` typed; waiting for Claude to go.
    case fallingAsleep(SleepingAgent)
    /// Claude gone, the veil up.
    case asleep(SleepingAgent)
    /// The resume typed; waiting for Claude to start.
    case waking(SleepingAgent)

    var agent: SleepingAgent {
        switch self {
        case .fallingAsleep(let agent), .asleep(let agent), .waking(let agent): agent
        }
    }

    var veiled: Bool {
        if case .waking = self { return false }
        return true
    }
}

/// What the app knows of an awake pane when it asks whether it may sleep.
/// Claude's input box is read separately, last: that reads tmux.
struct SleepCandidate: Equatable {
    var agent: HookAgent?
    /// Claude works, or its subagents do.
    var working = false
    /// A tool call under way or a permission question open.
    var asking = false
    /// Subagents or background shells listed for the pane.
    var tasks = false
    /// A guard request waits on the owner.
    var guardWaiting = false
    var focused = false
    var onPhone = false
    /// A ticket or an inbox line waits to be typed into it.
    var deliveryWaiting = false
    var idleSince: Date?
    /// Claude's last reply asks the owner something (`SleepSignals`).
    var asksOwner = false
    /// When another agent's message last woke the pane.
    var wokenByWork: Date?
    /// When the Mac last woke: its own sleep isn't the pane's idle time.
    var macWokeAt: Date?

    /// A Claude idle for `minutes` with nothing under way or waiting;
    /// 0 minutes is never. An unread reply doesn't keep it awake: the
    /// conversation is all there when it wakes. One that asks the owner
    /// something waits longer for the answer, one another agent just woke
    /// stays up for the next message, and only time the Mac was awake
    /// counts.
    func qualifies(now: Date, minutes: Int) -> Bool {
        guard minutes > 0, agent == .claude, let idleSince,
              !working, !asking, !tasks, !guardWaiting, !focused, !onPhone, !deliveryWaiting else { return false }
        if let wokenByWork, now.timeIntervalSince(wokenByWork) < SleepSignals.afterWork { return false }
        let wait = asksOwner ? max(minutes, SleepSignals.askingMinutes) : minutes
        let since = macWokeAt.map { max($0, idleSince) } ?? idleSince
        return now.timeIntervalSince(since) >= TimeInterval(wait * 60)
    }
}

/// Idle Claude cards put to sleep: Claude quits, freeing its processes and
/// servers, and the card waits under a light veil until something wakes it,
/// when the same conversation resumes in the same pane under the same name.
/// Keyed by pane: card ids are new every launch. Mirrored to
/// `handoff/sleeping.json` for the hooks and the next launch.
@MainActor
final class PaneSleep: ObservableObject {
    /// What sleep does to a pane, so tests can stand in for the terminals.
    struct Hands {
        /// Types `/exit` into the pane's idle Claude; false when it can't.
        var exit: @MainActor (UUID) -> Bool
        /// Types the resume at the pane's shell prompt; false when the pane
        /// isn't at its shell (Claude still runs there, or it's gone).
        var resume: @MainActor (SleepingAgent) -> Bool
        /// Runs `work` after `delay` seconds.
        var schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
    }

    static let shared = PaneSleep()
    static let standardURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lostty/handoff/sleeping.json")
    /// How long a pane waits for Claude to go after `/exit` before it
    /// counts as awake again.
    static let exitTimeout: TimeInterval = 30
    /// How long a waking pane waits for its Claude to start before it
    /// counts as awake, free to sleep again.
    static let wakeTimeout: TimeInterval = 60

    @Published private(set) var phases: [UUID: SleepPhase] = [:]

    private let url: URL
    private let hands: Hands

    init(url: URL = PaneSleep.standardURL, hands: Hands? = nil) {
        self.url = url
        self.hands = hands ?? .app
        let data = try? Data(contentsOf: url)
        let saved = data.flatMap { try? JSONDecoder().decode([SleepingAgent].self, from: $0) } ?? []
        for agent in saved { phases[agent.pane] = .asleep(agent) }
    }

    func phase(_ pane: UUID) -> SleepPhase? { phases[pane] }

    func isVeiled(_ pane: UUID) -> Bool { phases[pane]?.veiled ?? false }

    /// Puts an awake pane's Claude to sleep.
    func fallAsleep(_ agent: SleepingAgent) {
        let pane = agent.pane
        guard phases[pane] == nil, hands.exit(pane) else { return }
        set(.fallingAsleep(agent), for: pane)
        hands.schedule(Self.exitTimeout) { [weak self] in
            guard let self, phases[pane] == .fallingAsleep(agent) else { return }
            set(nil, for: pane)
        }
    }

    /// Wakes a sleeping pane; anything else is left as it is.
    func wake(_ pane: UUID) {
        guard case .asleep(let agent) = phases[pane] else { return }
        guard hands.resume(agent) else { return set(nil, for: pane) }
        set(.waking(agent), for: pane)
        hands.schedule(Self.wakeTimeout) { [weak self] in
            guard let self, phases[pane] == .waking(agent) else { return }
            set(nil, for: pane)
        }
    }

    /// A Claude started in the pane: it's awake.
    func started(_ pane: UUID) {
        set(nil, for: pane)
    }

    /// Claude exited in the pane. True when that was sleep, so the pane
    /// keeps its conversation, claims and recap; false for a real exit,
    /// a resume's Claude quitting included.
    func exited(_ pane: UUID) -> Bool {
        switch phases[pane] {
        case .fallingAsleep(let agent):
            set(.asleep(agent), for: pane)
            return true
        case .asleep:
            return true
        case .waking:
            set(nil, for: pane)
            return false
        case nil:
            return false
        }
    }

    /// The pane closed.
    func closed(_ pane: UUID) {
        set(nil, for: pane)
    }

    /// Only the panes still open keep their sleep.
    func keep(_ open: Set<UUID>) {
        for pane in phases.keys where !open.contains(pane) { set(nil, for: pane) }
    }

    private func set(_ phase: SleepPhase?, for pane: UUID) {
        guard phases[pane] != phase else { return }
        phases[pane] = phase
        save()
    }

    /// The panes asleep or falling asleep, for the hooks and the next
    /// launch. A waking one is left out: its Claude is about to answer for
    /// itself.
    private func save() {
        let sleeping = phases.values.filter(\.veiled).map(\.agent).sorted { $0.pane.uuidString < $1.pane.uuidString }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(sleeping).write(to: url, options: .atomic)
        } catch {
            Ghostty.logger.warning("sleep: couldn't save (\(error.localizedDescription))")
        }
    }
}

@MainActor
extension PaneSleep.Hands {
    static var app: PaneSleep.Hands { PaneSleep.Hands(
        exit: { pane in
            guard let view = PaneTyping.surface(pane) else { return false }
            return TicketDelivery.type("/exit", into: view)
        },
        resume: { agent in
            guard let view = PaneTyping.surface(agent.pane), ClaudeRuntime.shared.phase(agent.pane).isOff,
                  !view.needsConfirmQuit else { return false }
            PaneTyping.type(agent.pane, [.text(agent.resumeCommand), .enter])
            return true
        },
        schedule: { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { work() }
            }
        })
    }
}

/// Lostty Settings → Sleep: how long a Claude card sits idle before it
/// sleeps; 0 is never.
@MainActor
final class SleepPreferences: ObservableObject {
    static let shared = SleepPreferences()
    static let minutesKey = "LosttySleepAfterMinutes"
    static let defaultMinutes = 20
    static let choices = [0, 10, 20, 30, 60, 120]

    private let defaults: UserDefaults

    @Published var minutes: Int {
        didSet { defaults.set(minutes, forKey: Self.minutesKey) }
    }

    init(defaults: UserDefaults = .ghostty) {
        self.defaults = defaults
        minutes = defaults.object(forKey: Self.minutesKey) as? Int ?? Self.defaultMinutes
    }
}
#endif
