#if os(macOS)
import AppKit

/// The canvas trash button's Yes: each selected terminal's idle agent runs
/// the lostty-close-check skill, which answers with `lostty +close-check
/// done` or `pending` (the LOSTTY_CLOSE_CHECK user var). A card closes when
/// every pane in it would: no agent, or an agent that answered done. A busy
/// agent, a permission prompt or a half-typed prompt keeps it open unasked,
/// and so does no answer within two minutes.
@MainActor
final class CanvasCloseCheck {
    static let shared = CanvasCloseCheck()
    static let userVarName = "LOSTTY_CLOSE_CHECK"
    static let timeout: TimeInterval = 120

    enum Pane: Equatable {
        case closes, keeps, ask(HookAgent)
    }

    /// Panes asked that haven't answered, each with its card.
    private var asked: [UUID: CardController] = [:]

    static func pane(_ id: UUID) -> Pane {
        guard let agent = LastSessionStore.shared.agent(in: id) else { return .closes }
        let runtime = ClaudeRuntime.shared
        if !runtime.phase(id).isOff || runtime.actions[id] != nil || ContextHandoffCoordinator.shared.hasTyped(id) {
            return .keeps
        }
        return .ask(agent)
    }

    /// What's typed into an agent's prompt to run the skill.
    static func prompt(for agent: HookAgent) -> String {
        switch agent {
        case .claude: "/lostty-close-check"
        case .codex: "Use the lostty-close-check skill."
        }
    }

    static func skillInstalled(for agent: HookAgent) -> Bool {
        let folder = agent == .claude ? ".claude" : ".codex"
        let path = "\(NSHomeDirectory())/\(folder)/skills/lostty-close-check/SKILL.md"
        return FileManager.default.fileExists(atPath: path)
    }

    /// `offered`: Lostty's skills were offered already, so a missing one
    /// leaves its agent unanswered rather than asking again.
    func run(_ cards: [CardController], window: NSWindow, offered: Bool = false) {
        let plans = cards.map { card in (card, card.surfaceTree.map { ($0.id, Self.pane($0.id)) }) }
        let agents = Set(plans.flatMap { $0.1 }.compactMap { if case .ask(let agent) = $0.1 { agent } else { nil } })
        let missing = agents.filter { !Self.skillInstalled(for: $0) }
        guard missing.isEmpty || offered else {
            offerSkills(window: window) { [weak self] in self?.run(cards, window: window, offered: true) }
            return
        }
        for (card, panes) in plans {
            if panes.contains(where: { $0.1 == .keeps }) { continue }
            let ask = panes.compactMap { id, pane in if case .ask(let agent) = pane { (id, agent) } else { nil } }
            guard !ask.isEmpty else {
                card.closeCard(confirm: false)
                continue
            }
            card.checkingClose = true
            for (id, agent) in ask {
                asked[id] = card
                ContextHandoffWiring.type(id, [.text(Self.prompt(for: agent)), .enter])
            }
            let ids = ask.map(\.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self, weak card] in
                MainActor.assumeIsolated {
                    guard let self, let card, ids.contains(where: { self.asked[$0] === card }) else { return }
                    self.stop(card)
                }
            }
        }
    }

    func userVarChanged(_ id: UUID, name: String, value: String) {
        guard name == Self.userVarName, let card = asked.removeValue(forKey: id) else { return }
        guard value == "done" else {
            stop(card)
            return
        }
        guard !asked.values.contains(where: { $0 === card }) else { return }
        card.checkingClose = false
        card.closeCard(confirm: false)
    }

    /// The card stays open: forget its other panes' answers.
    private func stop(_ card: CardController) {
        asked = asked.filter { $0.value !== card }
        card.checkingClose = false
    }

    /// The skill isn't installed: offer Lostty's skills (they go in with its
    /// hooks), then `retry`. Cancel calls the check off.
    private func offerSkills(window: NSWindow, retry: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Install Lostty's skills?"
        alert.informativeText = "The check asks each agent with Lostty's lostty-close-check skill. Lostty installs its "
            + "skills with its hooks, in ~/.claude/skills and ~/.codex/skills."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let result = ClaudeHooksCLI().run("install")
            guard result.exitCode == 0 else {
                let failed = NSAlert()
                failed.alertStyle = .warning
                failed.messageText = "Lostty could not install its skills"
                failed.informativeText = result.stderr.isEmpty ? "Unknown error." : result.stderr
                failed.beginSheetModal(for: window)
                return
            }
            retry()
        }
    }
}
#endif
