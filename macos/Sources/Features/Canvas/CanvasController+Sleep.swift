#if os(macOS)
import AppKit
import Combine

/// Sleep on the canvas (`PaneSleep`): once a minute, each Claude card idle
/// long enough, with nothing under way or waiting for it and an empty input
/// box, falls asleep.
extension CanvasController {
    static let sleepCheckInterval: TimeInterval = 60

    func watchForSleep() {
        guard sleepTimer == nil else { return }
        let timer = Timer(timeInterval: Self.sleepCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleepIdleCards() }
        }
        timer.tolerance = Self.sleepCheckInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
        // The Mac runs short of memory or hot: idle cards sleep sooner
        // (`MacStrain.sleepMinutes`), starting now.
        MacStrainWatch.shared.start()
        strainWatch = MacStrainWatch.shared.$strain
            .removeDuplicates()
            .filter { $0 >= .high }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.sleepIdleCards() }
    }

    func sleepIdleCards() {
        let sleep = PaneSleep.shared
        sleep.keep(Set(LastSessionStore.openPanes()))
        let minutes = MacStrainWatch.shared.strain.sleepMinutes(setting: SleepPreferences.shared.minutes)
        guard minutes > 0 else { return }
        let runtime = ClaudeRuntime.shared
        let now = Date()
        var focused = Set(focusedCard.map { $0.surfaceTree.map(\.id) } ?? [])
        if let view = NSApp.keyWindow?.firstResponder as? Ghostty.SurfaceView { focused.insert(view.id) }
        let ready = cards.flatMap { Array($0.surfaceTree) }.filter { view in
            let id = view.id
            guard sleep.phase(id) == nil else { return false }
            runtime.foundIdle(id)
            return SleepCandidate(
                agent: LastSessionStore.shared.agent(in: id),
                working: !runtime.phase(id).isOff,
                asking: runtime.actions[id] != nil,
                tasks: PaneTasks.shared.lists[id] != nil,
                guardWaiting: GuardRuntime.shared.pending(for: id) != nil,
                focused: focused.contains(id),
                onPhone: SessionSync.shared.phonePanes.contains(id),
                deliveryWaiting: deliveryWaits(for: id),
                idleSince: runtime.idleSince(id)
            ).qualifies(now: now, minutes: minutes)
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        for view in ready {
            guard let session = TmuxOwnership.showing(view.id, ownedBy: pid, in: tmuxSessions).first,
                  let name = agentName(of: view.id),
                  let conversation = LastSessionStore.shared.conversation(in: view.id),
                  let folder = view.pwd,
                  inputBox(of: view) == .empty else { continue }
            sleep.fallAsleep(SleepingAgent(
                pane: view.id, sessionId: conversation.id, name: name, tmux: session.name, folder: folder,
                model: conversation.model))
        }
    }

    /// What the pane's screen shows of Claude's input box, read from its
    /// tmux session where it has one.
    func inputBox(of view: Ghostty.SurfaceView) -> TicketDelivery.Input {
        let pid = ProcessInfo.processInfo.processIdentifier
        let session = TmuxOwnership.showing(view.id, ownedBy: pid, in: tmuxSessions).first?.id
        return TicketDelivery.input(in: TicketDelivery.screen(of: view, session: session))
    }

    /// An agent messaged a sleeping one, and the hook held the message:
    /// it wakes, and the message goes in once its Claude is back. Only a
    /// pane that sleeps here: anything in a pane can print the user var.
    func messageForSleeper(_ wake: ClaudeMessage.SleepWake) {
        guard PaneSleep.shared.phase(wake.pane) != nil else { return }
        PaneSleep.shared.wake(wake.pane)
        guard let message = wake.message else { return }
        tell(wake.pane, "Message from \(wake.from ?? "another agent"): \(message)")
    }

    /// A click on a sleeping card wakes it; the click goes on as ever.
    func wakeClicked(_ event: NSEvent) {
        guard !surface.floats(at: event.locationInWindow) else { return }
        let point = scrollView.document.convert(event.locationInWindow, from: nil)
        guard scrollView.documentVisibleRect.contains(point), let id = model.card(at: point),
              let card = cards.first(where: { $0.id == id }) else { return }
        for pane in card.surfaceTree { PaneSleep.shared.wake(pane.id) }
    }

    /// Whether a ticket or an inbox line waits to be typed into `pane`: an
    /// inbox line for it, or a ticket that may start in its feature, which
    /// isn't its project's manager.
    func deliveryWaits(for pane: UUID) -> Bool {
        if agentInbox[pane]?.isEmpty == false { return true }
        guard let domain = membership.panes.zones[pane], let parent = model.zone(domain)?.parent,
              let project = model.zone(parent), project.manager != pane else { return false }
        return TicketQueue.next(
            in: domain, of: tickets, autoStart: project.autoStart == true, startedByHand: startedByHand) != nil
    }
}
#endif
