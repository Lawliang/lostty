#if os(macOS)
import AppKit
import LosttyRemote

/// Agents on the canvas: + → New Agent opens one (AgentRecipe), a
/// project's coordinator opens more with `lostty +agent open`, an agent
/// tells the one that opened it something with `lostty +agent report`,
/// and what Lostty has to tell an agent is typed in once its Claude is
/// free.
extension CanvasController {
    /// How many agents one coordinator may have open at once.
    static let agentLimit = 3

    /// + → New Agent → `recipe`: a card where a new terminal goes, its
    /// agent started. One that takes the manager seat becomes its
    /// project's manager there, and its project starts tickets itself.
    func newAgent(_ recipe: AgentRecipe) {
        let frame = model.placement(in: scrollView.documentVisibleRect)
        let zone = model.zone(for: frame)
        let project = zone.flatMap(model.projectZone)
        let context = recipe.takesManagerSeat ? project.map { [notesLine($0)] } ?? [] : []
        guard let pane = startAgent(recipe, name: recipe.name, message: nil, context: context, place: { config in
            newCard(at: frame, zone: zone, baseConfig: config).card
        }) else { return }
        if recipe.takesManagerSeat, let project {
            updateZone(project) { zone in
                zone.manager = pane
                zone.autoStart = true
            }
        }
    }

    func agentRequested(_ request: AgentRequest, from pane: UUID) {
        switch request {
        case .report(let text):
            guard let opener = agentOpeners[pane] ?? manager(of: pane), opener != pane else { return }
            tell(opener, "\(agentTitle(pane) ?? "An agent you opened") reports: \(text)")
        case .open(let name, let message, let feature, let branch):
            openAgent(name, message: message, feature: feature, branch: branch, for: pane)
        }
    }

    /// `lostty +agent open` from `asker`, which must be its project's
    /// manager: agent `name` as a card in `feature`'s zone, or beside the
    /// asker's card without one, on a new worktree for `branch` if given.
    /// What stops it is typed back to the asker.
    private func openAgent(_ name: String, message: String?, feature: String?, branch: String?, for asker: UUID) {
        guard case .manager(let project)? = model.ticketRole(of: asker, panes: membership.panes) else {
            return tell(asker, "Only a project's coordinator (its manager) can open agents.")
        }
        let recipes = AgentRecipe.all()
        guard let recipe = AgentRecipe.named(name, in: recipes) else {
            return tell(asker, "There's no agent named \(name). Agents: \(recipes.map(\.name).joined(separator: ", ")).")
        }
        let open = Set(cards.flatMap { $0.surfaceTree.map(\.id) })
        agentOpeners = agentOpeners.filter { open.contains($0.key) }
        guard agentOpeners.values.filter({ $0 == asker }).count < Self.agentLimit else {
            return tell(asker, "\(Self.agentLimit) agents you opened are still open. "
                + "Ask the owner to close a finished one, then open the next.")
        }
        var domain: UUID?
        if let feature {
            guard let id = model.feature(named: feature, in: project) else {
                let projectName = model.zone(project)?.name ?? "this project"
                return tell(asker, "There's no feature named \(feature) in \(projectName). Ask the owner to draw its zone.")
            }
            domain = id
        }
        let base = domain.flatMap(model.startFolder(ofZone:)) ?? model.startFolder(ofZone: project)
            ?? surfaceView(asker)?.pwd
        let title = ([recipe.name] + (domain.flatMap { model.zone($0)?.name }.map { [$0] } ?? [])).joined(separator: " · ")
        let context = ["Lostty opened you for your project's coordinator. "
            + "Tell it anything it should know with lostty +agent report \"<text>\"."]
            + (domain.flatMap { model.zone($0)?.name }.map { ["Your feature: \($0)."] } ?? [])
        Task { @MainActor [weak self] in
            var folder = base
            if let branch, let base {
                let made = await Task.detached(priority: .userInitiated) { WorktreeMaker.make(branch: branch, in: base) }.value
                switch made {
                case .success(let path): folder = path
                case .failure(let failure):
                    self?.tell(asker, "Couldn't open \(recipe.name): \(failure.message)")
                    return
                }
            }
            guard let self else { return }
            let pane = startAgent(recipe, name: title, message: message, context: context) { config in
                if let domain {
                    return self.newCard(at: self.newCardSpot(in: domain), zone: domain, baseConfig: config, folder: folder).card
                }
                if let card = self.cards.first(where: { $0.surfaceTree.contains { $0.id == asker } }) {
                    return self.newCard(beside: card, baseConfig: config, folder: folder).card
                }
                return self.newCard(at: self.model.placement(in: self.scrollView.documentVisibleRect),
                                    zone: project, baseConfig: config, folder: folder).card
            }
            if let pane { agentOpeners[pane] = asker }
        }
    }

    /// Writes `recipe`'s prompt and the command that starts it to files
    /// of their own and sources the command in the card `place` makes with
    /// the config given: the new card's pane. Typed in itself, a name or
    /// message that isn't ASCII would arrive garbled.
    private func startAgent(
        _ recipe: AgentRecipe, name: String, message: String?, context: [String],
        place: (Ghostty.SurfaceConfiguration) -> CardController
    ) -> UUID? {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty/Agents")
        let id = UUID().uuidString
        let file = folder.appendingPathComponent("\(id).md")
        let script = folder.appendingPathComponent("\(id).sh")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try recipe.fileText(context: context, message: message).write(to: file, atomically: true, encoding: .utf8)
            try (recipe.commandLine(file: file.path, name: name, message: message) + "\n")
                .write(to: script, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        var config = Ghostty.SurfaceConfiguration()
        config.initialInput = "source \(Ghostty.Shell.quote(script.path))\n"
        return place(config).surfaceTree.first { _ in true }?.id
    }

    private func notesLine(_ project: UUID) -> String {
        let name = (model.zone(project)?.name ?? "project").replacingOccurrences(of: "/", with: "-")
        return "Your notes file: ~/.config/lostty/notes/\(name).md. Read it when you start, and keep it current."
    }

    /// The manager of the project pane `pane` is in, where it has one.
    private func manager(of pane: UUID) -> UUID? {
        membership.panes.zones[pane].flatMap(model.projectZone).flatMap { model.zone($0)?.manager }
    }

    private func surfaceView(_ pane: UUID) -> Ghostty.SurfaceView? {
        cards.lazy.compactMap { card in card.surfaceTree.first { $0.id == pane } }.first
    }

    /// `text` for pane `pane`, typed in as "Lostty: <text>" once its
    /// Claude is free.
    func tell(_ pane: UUID, _ text: String) {
        agentInbox[pane, default: []].append(text)
        deliverSoon()
    }

    /// Types each pane's waiting lines into it, where its Claude is off
    /// and its input box empty; a pane that's gone loses its lines. True
    /// while some still wait.
    func deliverInbox() -> Bool {
        var waiting = false
        let pid = ProcessInfo.processInfo.processIdentifier
        for (id, lines) in agentInbox {
            guard let pane = surfaceView(id) else {
                agentInbox[id] = nil
                continue
            }
            let session = TmuxOwnership.showing(id, ownedBy: pid, in: tmuxSessions).first?.id
            guard ClaudeRuntime.shared.phase(id).isOff,
                  TicketDelivery.input(in: TicketDelivery.screen(of: pane, session: session)) == .empty,
                  TicketDelivery.type(lines.map { "Lostty: \($0)" }.joined(separator: "\n"), into: pane) else {
                waiting = true
                continue
            }
            agentInbox[id] = nil
        }
        return waiting
    }
}
#endif
