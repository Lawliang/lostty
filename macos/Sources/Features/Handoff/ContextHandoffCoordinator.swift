#if os(macOS)
import Combine
import Foundation

/// What a pane's Claude hooks say that the handoff cares about.
enum ContextHandoffSignal: Equatable {
    /// A turn ended waiting for the user (not a permission prompt).
    case stopped(transcript: String)
    /// A prompt was submitted.
    case prompted
    /// The fresh window's start hook took the handoff after /clear.
    case fresh
    /// The window was cleared with no handoff waiting (your own /clear).
    case cleared
    /// The pane's command finished or the pane closed.
    case gone
}

/// What Lostty types into a pane.
enum ContextHandoffKey: Equatable {
    case text(String)
    case enter
}

/// Each pane's context handoff (spec §4): arms past the limit or on the
/// bubble's button, queues the directive for the hooks, takes the agent's
/// handoff at a turn's end, and after a grace clears the window and starts
/// the fresh one from it.
@MainActor
final class ContextHandoffCoordinator: ObservableObject {
    static let shared = ContextHandoffCoordinator(deps: .live)
    static let grace: TimeInterval = 3
    static let freshTimeout: TimeInterval = 15
    /// After the start hook, before typing: the fresh window settles.
    static let continueDelay: TimeInterval = 1

    struct Dependencies {
        var enabled: @MainActor () -> Bool
        var setting: @MainActor () -> Int
        var store: ContextHandoffStore
        /// The agent's last reply in a conversation file, handed back on
        /// the main actor.
        var readReply: @MainActor (String, @escaping @MainActor (String?) -> Void) -> Void
        var type: @MainActor (UUID, [ContextHandoffKey]) -> Void
        /// The pane's working directory's last component.
        var project: @MainActor (UUID) -> String
        /// The usage feed's model name for the pane.
        var model: @MainActor (UUID) -> String?
        var notify: @MainActor (String) -> Void
        /// The observer: this pane's conversation file changes on purpose.
        var conversationChanging: @MainActor (UUID) -> Void
        var schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
        var now: () -> Date = Date.init
    }

    @Published private(set) var panes: [UUID: ContextHandoffPane] = [:]
    /// The bubble's last word on a pane: done, or failed.
    @Published private(set) var notes: [UUID: String] = [:]

    private let deps: Dependencies
    /// Each pane's latest conversation file, from its turn ends.
    private var conversations: [UUID: String] = [:]
    /// Panes not to arm until their conversation changes ("" = the one
    /// under way, not yet named).
    private var declined: [UUID: String] = [:]
    /// Bumped to drop scheduled work for a pane.
    private var generation: [UUID: Int] = [:]
    /// Panes whose agent works: a prompt since its last turn end.
    private var working: Set<UUID> = []
    /// Panes with the ceiling nudge waiting out its grace.
    private var nudgeWaiting: Set<UUID> = []
    /// Panes with keys typed since their last prompt: their prompt may
    /// hold half a message, which Lostty's typing would add to and send.
    private var typed: Set<UUID> = []

    private struct Reading: Equatable {
        var used: Int
        var size: Int
    }

    /// Each pane's latest context report.
    private var readings: [UUID: Reading] = [:]
    /// A cleared window's last reading: the usage feed sends nothing new
    /// until the fresh window's first reply, so this one keeps coming back.
    private var stale: [UUID: Reading] = [:]

    static let typingNote = "Didn't hand off: you were typing in this terminal. Lostty hands off at the next "
        + "clean break."

    init(deps: Dependencies) {
        self.deps = deps
    }

    func isArmed(_ pane: UUID) -> Bool { panes[pane] != nil }

    /// The bubble's line for a pane: its last word (done, failed, held),
    /// else what an armed pane waits for.
    func line(_ pane: UUID) -> String? {
        if let note = notes[pane] { return note }
        if let state = panes[pane] {
            if state.byButton { return "Will hand off at the next clean break." }
            let limit = ContextHandoffPolicy.limit(setting: deps.setting(), size: state.size)
            return "Will hand off at the next clean break (\(ContextHandoffDirective.k(state.used)) of "
                + "\(ContextHandoffDirective.k(limit)))."
        }
        return nil
    }

    // MARK: - Arming

    func contextChanged(_ pane: UUID, used: Int, size: Int) {
        let reading = Reading(used: used, size: size)
        if let old = stale[pane] {
            guard old != reading else { return }
            stale[pane] = nil
        }
        readings[pane] = reading
        if var state = panes[pane] {
            state.used = used
            state.size = size
            panes[pane] = state
            guard state.phase == .armed, !state.byButton else { return persist(pane) }
            let level = ContextHandoffPolicy.level(used: used, size: size, setting: deps.setting())
            guard deps.enabled(), let level else { return disarm(pane) }
            if level == .ceiling, state.level == .limit {
                state.level = .ceiling
                state.saidAt = used
                panes[pane] = state
                say(pane, problem: nil)
            } else if used >= state.saidAt + ContextHandoffPolicy.reminderStep {
                state.saidAt = used
                panes[pane] = state
                say(pane, problem: nil)
            }
            return persist(pane)
        }
        guard declined[pane] == nil, deps.enabled(),
              let level = ContextHandoffPolicy.level(used: used, size: size, setting: deps.setting()) else { return }
        arm(pane, level: level, used: used, size: size, byButton: false)
    }

    func armByButton(_ pane: UUID, used: Int, size: Int) {
        declined[pane] = nil
        guard panes[pane] == nil else { return }
        arm(pane, level: .limit, used: used, size: size, byButton: true)
    }

    func decline(_ pane: UUID) {
        disarm(pane)
        declined[pane] = conversations[pane] ?? ""
    }

    func settingChanged(enabled: Bool) {
        guard !enabled else { return }
        for pane in Array(panes.keys) { disarm(pane) }
    }

    /// After a restart: panes armed before it are armed again; one caught
    /// mid-handoff goes back to armed (its saved handoff stays saved).
    func restore() {
        for (pane, var state) in deps.store.loadStates() {
            state.phase = .armed
            state.handoff = nil
            state.next = nil
            state.summary = nil
            panes[pane] = state
            persist(pane)
        }
    }

    private func arm(_ pane: UUID, level: ContextHandoffLevel, used: Int, size: Int, byButton: Bool) {
        notes[pane] = nil
        panes[pane] = ContextHandoffPane(phase: .armed, level: level, byButton: byButton, saidAt: used,
                                         used: used, size: size)
        say(pane, problem: nil)
        persist(pane)
    }

    private func say(_ pane: UUID, problem: String?) {
        guard let state = panes[pane] else { return }
        let setting = deps.setting()
        deps.store.writeSay(pane, ContextHandoffDirective.text(
            level: state.level, used: state.used,
            limit: ContextHandoffPolicy.limit(setting: setting, size: state.size),
            ceiling: ContextHandoffPolicy.ceiling(setting: setting, size: state.size),
            byButton: state.byButton, problem: problem))
    }

    private func disarm(_ pane: UUID) {
        bump(pane)
        nudgeWaiting.remove(pane)
        panes[pane] = nil
        deps.store.removeAll(pane)
    }

    private func persist(_ pane: UUID) {
        if let state = panes[pane] { deps.store.saveState(pane, state) }
    }

    @discardableResult
    private func bump(_ pane: UUID) -> Int {
        let next = (generation[pane] ?? 0) + 1
        generation[pane] = next
        return next
    }

    // MARK: - Signals

    func signal(_ pane: UUID, _ signal: ContextHandoffSignal) {
        switch signal {
        case .stopped(let path): stopped(pane, path)
        case .prompted:
            typed.remove(pane)
            working.insert(pane)
            interrupted(pane)
        case .fresh: fresh(pane)
        case .cleared:
            // Lostty's own /clear waits for `fresh` (or times out).
            guard panes[pane]?.phase != .clearing else { return }
            disarm(pane)
            stale[pane] = readings[pane]
        case .gone:
            disarm(pane)
            conversations[pane] = nil
            declined[pane] = nil
            notes[pane] = nil
            working.remove(pane)
            typed.remove(pane)
            readings[pane] = nil
            stale[pane] = nil
        }
    }

    /// A key typed in a pane (the app forwards every terminal's).
    func keyTyped(_ pane: UUID) {
        typed.insert(pane)
        interrupted(pane)
    }

    /// You typed or prompted: a pending clear or a waiting nudge is off.
    /// While you've typed since your last prompt, Lostty types nothing
    /// (`typed`). Not while clearing: /clear and Lostty's own lines
    /// prompt too.
    private func interrupted(_ pane: UUID) {
        guard var state = panes[pane], state.phase != .clearing else { return }
        nudgeWaiting.remove(pane)
        guard state.phase == .pending else { return }
        bump(pane)
        state.phase = .armed
        state.handoff = nil
        state.saidAt = state.used
        panes[pane] = state
        persist(pane)
    }

    private func stopped(_ pane: UUID, _ path: String) {
        if let declinedPath = declined[pane] {
            if declinedPath.isEmpty { declined[pane] = path } else if declinedPath != path { declined[pane] = nil }
        }
        conversations[pane] = path
        working.remove(pane)
        guard panes[pane]?.phase == .armed else { return }
        let gen = bump(pane)
        deps.readReply(path) { [weak self] reply in
            guard let self, self.generation[pane] == gen else { return }
            self.replied(pane, reply ?? "")
        }
    }

    private func replied(_ pane: UUID, _ reply: String) {
        // A prompt came in while the reply was read: the agent works again.
        guard var state = panes[pane], state.phase == .armed, !working.contains(pane) else { return }
        switch ContextHandoffExtract.find(in: reply) {
        case .success where typed.contains(pane):
            // Your prompt may hold half a message: ask again at the next break.
            notes[pane] = Self.typingNote
            say(pane, problem: nil)
        case .success(let handoff):
            do {
                let url = try deps.store.saveHandoff(handoff.text, project: deps.project(pane), at: deps.now())
                state.phase = .pending
                state.handoff = url.path
                state.next = handoff.next
                state.summary = handoff.summary
                panes[pane] = state
                notes[pane] = nil
                persist(pane)
                let gen = bump(pane)
                deps.schedule(Self.grace) { [weak self] in self?.clear(pane, gen) }
            } catch {
                notes[pane] = "Couldn't save the handoff: \(error.localizedDescription)"
            }
        case .failure(.missing(let section)):
            say(pane, problem: "Your handoff had no '\(section)'.")
        case .failure(.none):
            guard state.level == .ceiling, !state.nudged, !state.byButton, !typed.contains(pane) else { return }
            state.nudged = true
            panes[pane] = state
            persist(pane)
            nudgeWaiting.insert(pane)
            deps.schedule(Self.grace) { [weak self] in
                guard let self, self.nudgeWaiting.remove(pane) != nil, self.panes[pane]?.phase == .armed,
                      !self.working.contains(pane), !self.typed.contains(pane) else { return }
                self.deps.type(pane, [.text(ContextHandoffDirective.nudge), .enter])
            }
        }
    }

    private func clear(_ pane: UUID, _ gen: Int) {
        guard generation[pane] == gen, var state = panes[pane], state.phase == .pending, !typed.contains(pane),
              let path = state.handoff, let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        deps.store.removeSay(pane)
        deps.store.writeStart(pane, ContextHandoffDirective.freshStart(handoff: text, path: path, used: state.used))
        state.phase = .clearing
        panes[pane] = state
        persist(pane)
        deps.type(pane, [.text("/clear"), .enter])
        let wait = bump(pane)
        deps.schedule(Self.freshTimeout) { [weak self] in self?.freshTimedOut(pane, wait) }
    }

    private func fresh(_ pane: UUID) {
        guard let state = panes[pane], state.phase == .clearing else { return }
        deps.conversationChanging(pane)
        let lines = ContextHandoffAgent.restoreLines(model: deps.model(pane))
            + [ContextHandoffDirective.continueLine(state.next ?? .wait)]
        let keys = lines.flatMap { [ContextHandoffKey.text($0), .enter] }
        deps.schedule(Self.continueDelay) { [weak self] in self?.deps.type(pane, keys) }
        disarm(pane)
        // The old window's figure stays in the usage feed until the fresh
        // window's first reply: it mustn't arm the fresh one.
        stale[pane] = readings[pane] ?? Reading(used: state.used, size: state.size)
        notes[pane] = "Fresh window: handed off at \(ContextHandoffDirective.k(state.used)) after "
            + "'\(state.summary ?? "")'"
    }

    private func freshTimedOut(_ pane: UUID, _ gen: Int) {
        guard generation[pane] == gen, let state = panes[pane], state.phase == .clearing else { return }
        disarm(pane)
        declined[pane] = conversations[pane] ?? ""
        let message = "Handoff saved, but the fresh window didn't start. It's at \(state.handoff ?? "")."
        notes[pane] = message
        deps.notify(message)
    }
}

extension ContextHandoffCoordinator.Dependencies {
    /// The app's: files under Application Support, typing into the pane's
    /// terminal, the observer and notification bubbles.
    static var live: Self {
        Self(
            enabled: { ContextHandoffPreferences.shared.enabled },
            setting: { ContextHandoffPreferences.shared.setting },
            store: .standard,
            readReply: { path, done in
                Task.detached(priority: .utility) {
                    let reply = ContextHandoffReply.last(path)
                    await MainActor.run { done(reply) }
                }
            },
            type: { ContextHandoffWiring.type($0, $1) },
            project: { ContextHandoffWiring.project(pwd: ContextHandoffWiring.surface($0)?.pwd) },
            model: { ClaudeUsageRuntime.shared.models[$0] },
            notify: { message in
                LosttyNotifications.shared.post(LosttyNotification(
                    kind: .handoff(UUID()), style: .failure, title: "Handoff didn't finish", detail: message))
            },
            conversationChanging: { TurnObserver.shared.conversationChanging($0) },
            schedule: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
            })
    }
}
#endif
