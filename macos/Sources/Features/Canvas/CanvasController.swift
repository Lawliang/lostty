#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Lostty Beta's canvas: one window that is an infinite whiteboard of
/// terminal cards. Owns the window, the cards' layout (CanvasModel) and
/// the cards (CardController, one per split group). Closing the window
/// hides it; its terminals keep running.
@MainActor
final class CanvasController: NSWindowController, NSWindowDelegate {
    /// The app's one canvas, made the first time it's opened or restored.
    /// Set only by `show(_:freshCard:)` and `restore(_:state:)`.
    static var shared: CanvasController?

    /// The canvas while it's the key window: where ⌘N makes a card.
    static var key: CanvasController? {
        shared.flatMap { $0.window?.isKeyWindow == true ? $0 : nil }
    }

    /// Every card's controller, for the app's pane lookups.
    nonisolated static var allCards: [CardController] {
        onMain { shared?.cards ?? [] }
    }

    /// Closed cards kept so Undo can bring one back.
    static let retiredLimit = 10

    let ghostty: Ghostty.App
    private(set) var model = CanvasModel()
    /// In the order they were added; `model.cards` has them back to front.
    private(set) var cards: [CardController] = []
    /// The card holding keyboard focus, or that last held it.
    private(set) weak var focusedCard: CardController?
    /// The canvas's tickets, kept while no panel is open. Every panel lists
    /// them.
    private(set) var tickets: [CanvasTicket] = []
    /// The open tickets panels' cards. They share `model` with the terminal
    /// cards, so they stack, block clicks and fit to view alike.
    private(set) var ticketPanels: [UUID: TicketBoardView] = [:]
    /// A new ticket's sheet left open in a panel since closed: the next
    /// panel opened takes it.
    var parkedDraft: CanvasTicket? {
        didSet { if parkedDraft != oldValue { saveSoon() } }
    }
    /// The title bar's pill follows the focused card's pane. (Each card has
    /// its own bottom bar.)
    let sidebar = ExtensionSidebarModel()

    let surface = CanvasSurfaceView()
    var scrollView: CanvasScrollView { surface.scrollView }
    private(set) var views: [UUID: CardView] = [:]
    /// Closed cards with where they were, newest last, for Undo.
    private var retired: [(card: CardController, frame: CGRect)] = []
    /// The selected cards, of either kind: a marquee's, ⇧-clicks' or ⌘A's.
    var selection: Set<UUID> = [] {
        didSet { if selection != oldValue { selectionDidChange() } }
    }
    /// What a marquee under way adds to: the selection it started with
    /// under ⇧, else nothing.
    var marqueeBase: Set<UUID>?
    /// New Zone was chosen: the next marquee draws a zone instead.
    var drawsZone = false
    /// The layout Tidy Up uses, chosen on the selection's bar.
    var tidyLayout = CanvasModel.Tidy.row
    /// A press on a group of selected cards under way: where it started,
    /// the card under it, where the cards were, and whether it has moved.
    var groupDrag: (point: CGPoint, id: UUID, origins: [UUID: CGPoint], moved: Bool)?
    /// The pointer is over a group of selected cards: an open hand, the
    /// panes' own cursors off.
    var overGroup = false
    /// Cards whose panes are moving to a window: gone for good, not for Undo.
    private var moving: Set<UUID> = []
    /// Each pane's zone and the zones as they were, when last worked out.
    private var membership = (panes: CanvasPaneZones(), model: CanvasModel())
    /// The zone file last written for each pane in a zone.
    private var zoneFiles: [UUID: CanvasZoneFile] = [:]
    let zoneStore = CanvasZoneStore.standard
    /// Lostty's tmux sessions as last listed: which pane each one shows,
    /// for the zone files' members.
    private var tmuxSessions: [TmuxSession] = []
    /// The zoom the terminals last rendered at.
    var settledZoom: CGFloat = 1
    var settleWork: DispatchWorkItem?
    /// The glide to a card under way (CanvasController+Glide).
    var glide: CanvasGlide?
    var waits = CanvasWaits()
    /// The panes whose Claude is working, its subagents included.
    private var working: Set<UUID> = []
    /// The view to show when the window first opens (a restored canvas's).
    var pendingView: (center: CGPoint, zoom: CGFloat)?
    /// No cards of either kind, and no zones.
    var isEmpty: Bool { model.cards.isEmpty && model.zones.isEmpty }
    /// Whether the view was set the first time the window showed.
    private(set) var placed = false
    private var eventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    /// Opens the canvas, making it the first time; an empty canvas gets a
    /// fresh card unless panes are about to move in.
    @discardableResult
    static func show(_ ghostty: Ghostty.App, freshCard: Bool = true) -> CanvasController {
        let canvas = shared ?? CanvasController(ghostty)
        shared = canvas
        canvas.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if freshCard, canvas.isEmpty { canvas.newCard() }
        return canvas
    }

    init(_ ghostty: Ghostty.App) {
        self.ghostty = ghostty
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Canvas"
        window.tabbingMode = .disallowed
        // Saved with the app's own state (CanvasRestorableState): window
        // restoration skips hidden windows, and a hidden canvas still holds
        // running terminals.
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 320)
        super.init(window: window)
        window.delegate = self
        // Plain AppKit, not in an NSHostingView: AppKit then hit tests the
        // cards for an accessibility app, and each answers as it's zoomed.
        window.contentView = surface
        if !window.setFrameUsingName("LosttyCanvas") { window.center() }
        window.setFrameAutosaveName("LosttyCanvas")
        installTitleAccessory()
        observe()
        // A window dragged onto the title bar moves onto the canvas.
        CanvasDrop.shared.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// A key nothing on the canvas takes is dropped, not beeped at.
    override func noResponder(for eventSelector: Selector) {
        guard eventSelector != #selector(NSResponder.keyDown(with:)) else { return }
        super.noResponder(for: eventSelector)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        placeIfNeeded()
        updateVisibility()
    }

    /// The first time the window shows (by ⌃⌘K, or a pane brought forward):
    /// lay out, then show the restored view or the middle.
    private func placeIfNeeded() {
        guard !placed, window?.isVisible == true else { return }
        placed = true
        window?.contentView?.layoutSubtreeIfNeeded()
        let view = pendingView ?? (CanvasModel.middle, 1)
        pendingView = nil
        scrollView.magnification = CanvasZoom.clamped(view.zoom)
        center(on: view.center)
        settleZoom()
    }

    private func installTitleAccessory() {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        let host = NSHostingView(rootView: CanvasTitleAccessory(sidebar: sidebar) { [weak self] in self?.jump() })
        host.frame.size = NSSize(width: 340, height: 28)
        accessory.view = host
        window?.addTitlebarAccessoryViewController(accessory)
    }

    private func observe() {
        let document = scrollView.document
        document.clicked = { [weak self] adding in
            self?.canvasClicked()
            self?.marqueeBegan(adding: adding)
        }
        document.dragged = { [weak self] rect in self?.marqueeMoved(to: rect) }
        document.dragEnded = { [weak self] in self?.marqueeEnded() }
        document.selectedAll = { [weak self] in self?.selectAllCards() }
        document.deselected = { [weak self] in
            self?.selection = []
            self?.drawsZone = false
        }
        surface.zones.canvas = self
        surface.addMenu.chose = { [weak self] item in
            switch item {
            case .terminal: self?.newCard()
            case .ticket: self?.showTickets()
            case .zone: self?.startDrawingZone()
            }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(canvasMoved), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        // Focus follows the window's first responder: whichever card holds
        // it is the focused card.
        window?.publisher(for: \.firstResponder)
            .sink { [weak self] responder in self?.firstResponderChanged(responder) }
            .store(in: &cancellables)
        ClaudeRuntime.shared.$awaiting
            .sink { [weak self] awaiting in
                self?.waits.update(awaiting: awaiting, now: Date())
                self?.updateZoneCaptions()
            }
            .store(in: &cancellables)
        ClaudeRuntime.shared.$phases
            .map { Set($0.keys) }
            .removeDuplicates()
            .sink { [weak self] working in
                self?.working = working
                self?.updateZoneCaptions()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .losttySessionsChanged)
            .sink { [weak self] _ in self?.tmuxSessionsDidChange() }
            .store(in: &cancellables)
        // A terminal has no use for pinches, so pinching anywhere zooms the
        // canvas. (Scrolling over a pane, which pans the canvas, is the
        // pane's to pass on: a scroll-wheel monitor would turn off AppKit's
        // smooth, off-main-thread scrolling.)
        // A click on the tickets panel focuses it first, wherever it lands
        // (its rows and fields take the click themselves). A click on a card
        // changes the selection first, and a press on a group of selected
        // cards drags them all.
        let events: NSEvent.EventTypeMask = [.magnify, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            guard let self, event.window === window else { return event }
            switch event.type {
            case .magnify:
                stopGlide()
                scrollView.magnify(with: event)
                return nil
            case .leftMouseDown:
                if groupPressed(event) || selectionClicked(event) { return nil }
                ticketClicked(event)
                return event
            case .rightMouseDown:
                ticketClicked(event)
                return event
            case .leftMouseDragged, .leftMouseUp:
                return groupDragged(event) ? nil : event
            default:
                updateGroupHover(at: event.locationInWindow)
                return event
            }
        }
    }

    // MARK: Cards

    /// A new card with one fresh terminal, in the middle of the view; in a
    /// zone, starting in its folder. `config` is what it started with.
    @discardableResult
    func newCard(baseConfig: Ghostty.SurfaceConfiguration? = nil)
        -> (card: CardController, config: Ghostty.SurfaceConfiguration?) {
        let frame = model.placement(in: scrollView.documentVisibleRect)
        return newCard(at: frame, zone: model.zone(for: frame), baseConfig: baseConfig)
    }

    /// ⌘T on a card: a new card beside it, as big, starting where its
    /// focused pane is (`baseConfig`), or in its zone's folder, or in
    /// the folder of `other`'s zone when it lands outside every zone.
    @discardableResult
    func newCard(beside other: CardController, baseConfig: Ghostty.SurfaceConfiguration?)
        -> (card: CardController, config: Ghostty.SurfaceConfiguration?) {
        let frame = model.placement(beside: other.id) ?? model.placement(in: scrollView.documentVisibleRect)
        return newCard(at: frame, zone: model.startZone(beside: other.id, at: frame), baseConfig: baseConfig)
    }

    private func newCard(at frame: CGRect, zone: UUID?, baseConfig: Ghostty.SurfaceConfiguration?)
        -> (card: CardController, config: Ghostty.SurfaceConfiguration?) {
        var config = baseConfig
        if let zone, let folder = model.startFolder(ofZone: zone), Self.isFolder(folder) {
            config = config ?? Ghostty.SurfaceConfiguration()
            config?.workingDirectory = folder
        }
        let card = CardController(ghostty, canvas: self, baseConfig: config)
        add(card, frame: frame)
        focus(card)
        return (card, config)
    }

    private static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// A card holding `tree`: panes moved in from a window, or restored.
    @discardableResult
    func addCard(
        tree: SplitTree<Ghostty.SurfaceView>, frame: CGRect? = nil, focused: Ghostty.SurfaceView? = nil
    ) -> CardController {
        let card = CardController(ghostty, canvas: self, tree: tree)
        if let focused, tree.contains(focused) {
            card.focusedSurface = focused
            card.sidebar.focusedSurfaceID = focused.id
        }
        add(card, frame: frame ?? model.placement(size: Self.cardSize(for: tree), in: scrollView.documentVisibleRect))
        return card
    }

    /// Big enough for `tree`'s panes as they were last laid out, plus a header.
    static func cardSize(for tree: SplitTree<Ghostty.SurfaceView>) -> CGSize {
        let panes = tree.viewBounds()
        guard panes.width > 0, panes.height > 0 else { return CanvasModel.newCardSize }
        return CGSize(width: panes.width, height: panes.height + CardView.chromeHeight)
    }

    private func add(_ card: CardController, frame: CGRect) {
        cards.append(card)
        model.add(card.id, frame: frame)
        let view = CardView(card: card, canvas: self)
        view.stackIndex = model.cards.count - 1
        views[card.id] = view
        scrollView.document.addSubview(view)
        if let placed = model.card(card.id)?.frame { view.frame = placed }
        updateVisibility()
        saveSoon()
        for surface in card.surfaceTree { surface.canvasZoomDidSettle(settledZoom) }
        zoneMembershipDidChange()
    }

    /// Whether a click at `point` (in the window) is on the + menu or a
    /// notification, over the cards.
    func floats(at point: NSPoint) -> Bool {
        surface.floats(at: point)
    }

    func card(holding surface: Ghostty.SurfaceView) -> CardController? {
        cards.first { $0.surfaceTree.contains(surface) }
    }

    /// Keyboard focus to `card`'s focused pane.
    func focus(_ card: CardController) {
        guard let surface = card.focusedSurface ?? card.surfaceTree.first else { return }
        card.focusSurface(surface)
    }

    private func firstResponderChanged(_ responder: NSResponder?) {
        guard let surface = responder as? Ghostty.SurfaceView, let card = card(holding: surface) else { return }
        card.focusedSurfaceDidChange(to: surface)
    }

    /// A click on the canvas itself, between the cards, lets go of the
    /// focused card: no pane has the keyboard, and scrolling pans the canvas
    /// over every pane.
    private func canvasClicked() {
        for panel in ticketPanels.values { panel.isFocusedCard = false }
        guard let previous = focusedCard else {
            // Out of a ticket's field, too.
            window?.makeFirstResponder(scrollView.document)
            return
        }
        focusedCard = nil
        window?.makeFirstResponder(scrollView.document)
        letGo(of: previous)
    }

    /// `previous` is no longer the focused card: its panes, the title bar's
    /// pill and its look follow.
    private func letGo(of previous: CardController) {
        previous.syncFocusToSurfaceTree()
        sidebar.focusedSurfaceID = nil
        for view in views.values { view.isFocusedCard = false }
    }

    /// A card's pane is taking keyboard focus: the card is the focused one
    /// from now on (before its pane is, so the pane never blinks unfocused),
    /// in front.
    func cardWillFocus(_ card: CardController) {
        let previous = focusedCard
        focusedCard = card
        guard previous !== card else { return }
        previous?.syncFocusToSurfaceTree()
        bringToFront(card.id)
    }

    /// A card's pane took keyboard focus: the window's title, pill and the
    /// cards' shadows follow it.
    func cardDidFocus(_ card: CardController) {
        card.syncFocusToSurfaceTree()
        card.applyTitleToWindow()
        sidebar.focusedSurfaceID = card.focusedSurface?.id
        for (id, view) in views { view.isFocusedCard = id == card.id }
        for panel in ticketPanels.values { panel.isFocusedCard = false }
    }

    func bringToFront(_ id: UUID) {
        model.bringToFront(id)
        restack()
    }

    /// The cards' views in `model`'s order, over the zones. Reorders
    /// without taking views out of the window, so the focused pane keeps
    /// keyboard focus.
    private func restack() {
        for (index, entry) in model.cards.enumerated() { view(entry.id)?.stackIndex = index }
        scrollView.document.sortSubviews({ a, b, _ in
            let left = (a as? CanvasStacked)?.stackIndex ?? Int.min, right = (b as? CanvasStacked)?.stackIndex ?? Int.min
            return left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
        }, context: nil)
    }

    /// The view of card `id`, of either kind.
    func view(_ id: UUID) -> (NSView & CanvasStacked)? {
        if let card = views[id] { return card }
        return ticketPanels[id]
    }

    /// The front-most terminal card.
    var frontCard: CardController? {
        model.cards.reversed().lazy.compactMap { entry in self.cards.first { $0.id == entry.id } }.first
    }

    /// Moving or resizing, live.
    func setFrame(_ frame: CGRect, of id: UUID) {
        model.setFrame(frame, of: id)
        if let frame = model.card(id)?.frame { view(id)?.frame = frame }
        if selection.contains(id) { updateSelectionOutline() }
    }

    /// A drag or resize ended, of a card or a zone.
    func cardFrameDidSettle() {
        relistTickets()
        updateVisibility()
        saveSoon()
        zoneMembershipDidChange()
    }

    // MARK: Zones

    /// The zones' views follow `model.zones`, and Zone from Selection
    /// whether it can make one. Membership waits for a resize to settle.
    func zonesDidChange(settled: Bool = true) {
        surface.zones.show(model.zones)
        relistTickets()
        updateSelectionBar()
        saveSoon()
        if settled { zoneMembershipDidChange() }
    }

    /// Adds a zone at `frame`, a domain of `parent` or a project, unless
    /// it breaks the rules.
    func addZone(_ frame: CGRect, parent: UUID?) {
        guard model.addZone(model.newZone(frame, parent: parent)) else { return }
        zonesDidChange()
    }

    /// Saved zones back on the canvas.
    func addZones(_ saved: [CanvasZone]) {
        model.addZones(saved)
        zonesDidChange()
    }

    /// A zone round the selected cards.
    func zoneFromSelection() {
        guard let around = model.zoneAround(selection) else { return }
        addZone(around.frame, parent: around.parent)
    }

    /// New Zone: the next drag on the canvas between the cards draws one;
    /// Escape cancels.
    func startDrawingZone() {
        canvasClicked()
        selection = []
        drawsZone = true
    }

    /// Zone `id` and everything in it drawn `delta` from where they are,
    /// while its label is dragged, when the move keeps the rules; true then.
    /// The model moves only once the drag ends (`moveZone`).
    func previewZoneMove(_ id: UUID, by delta: CGSize) -> Bool {
        var moved = model
        guard let cards = moved.moveZone(id, by: delta) else { return false }
        surface.zones.show(moved.zones)
        for card in cards { if let frame = moved.card(card)?.frame { view(card)?.frame = frame } }
        updateSelectionOutline(in: moved)
        return true
    }

    /// Moves zone `id` by `delta` with everything in it, or puts it back
    /// where it was when the move breaks the rules.
    func moveZone(_ id: UUID, by delta: CGSize) {
        let held = model.members(of: id)
        model.moveZone(id, by: delta)
        for card in held { if let frame = model.card(card)?.frame { view(card)?.frame = frame } }
        zonesDidChange()
        updateSelectionOutline()
        cardFrameDidSettle()
    }

    /// Resizing, live: a frame that breaks the rules leaves it as it was.
    func setZoneFrame(_ frame: CGRect, of id: UUID) {
        guard model.setZoneFrame(frame, of: id) else { return }
        zonesDidChange(settled: false)
    }

    /// Removes zone `id` and its domains; the cards stay, and the tickets
    /// made in them are in no zone, keeping their keys.
    func removeZone(_ id: UUID) {
        let gone = model.removeZone(id)
        setTickets(tickets.map { $0.leaving(gone) })
        zonesDidChange()
    }

    /// Zone `id`'s name, color, folder, brief or key prefix, from its
    /// settings.
    func updateZone(_ id: UUID, _ change: (inout CanvasZone) -> Void) {
        guard model.updateZone(id, change) else { return }
        zonesDidChange()
    }

    /// Zoom to Zone: zone `id` in view, with a margin.
    func zoomToZone(_ id: UUID) {
        guard let frame = model.zone(id)?.frame else { return }
        zoomToFit(frame.insetBy(dx: -CanvasModel.fitMargin, dy: -CanvasModel.fitMargin))
    }

    /// What's in zone `id`, back to front: each terminal card's title as its
    /// header shows it, and "Tickets" for the tickets panel.
    func memberTitles(of id: UUID) -> [String] {
        let members = model.members(of: id)
        return model.cards.filter { members.contains($0.id) }.compactMap { entry in
            ticketPanels[entry.id] != nil ? "Tickets" : cards.first { $0.id == entry.id }?.title
        }
    }

    /// A card's panes changed. With none left the card goes, kept a while
    /// for Undo; when Undo gives it its panes back, it returns where it was.
    func cardTreeDidChange(_ card: CardController, from old: SplitTree<Ghostty.SurfaceView>, to new: SplitTree<Ghostty.SurfaceView>) {
        if new.isEmpty {
            retire(card)
        } else if old.isEmpty, let index = retired.firstIndex(where: { $0.card === card }) {
            let frame = retired.remove(at: index).frame
            add(card, frame: frame)
            focus(card)
        }
        updateVisibility()
        saveSoon()
        for surface in card.surfaceTree { surface.canvasZoomDidSettle(settledZoom) }
        zoneMembershipDidChange()
    }

    /// Works out each pane's zone again (zones spec §5, §9). A pane in a
    /// zone has its zone file, kept current. A pane that moved in or out
    /// is told with its next prompt, and a card that left a zone still on
    /// the canvas shows a notice. A pane new to the canvas didn't move.
    func zoneMembershipDidChange() {
        let now = model.paneZones(cards.map { ($0.id, $0.surfaceTree.map(\.id)) })
        let before = membership
        membership = (now, model)

        for pane in zoneFiles.keys where now.zones[pane] == nil {
            zoneStore.removeZone(pane)
            zoneFiles[pane] = nil
        }
        for pane in before.panes.panes.subtracting(now.panes) { zoneStore.removeSay(pane) }
        let pid = ProcessInfo.processInfo.processIdentifier
        let sessions = now.zones.keys.reduce(into: [UUID: String]()) { names, pane in
            names[pane] = TmuxOwnership.showing(pane, ownedBy: pid, in: tmuxSessions).first?.name
        }
        for (pane, zone) in now.zones {
            guard let file = model.zoneFile(zone, panes: now, sessions: sessions), zoneFiles[pane] != file else { continue }
            zoneStore.writeZone(pane, file)
            zoneFiles[pane] = file
        }

        var noticed: Set<UUID> = []
        for move in before.panes.moves(to: now) {
            let left = move.from.flatMap { before.model.zoneTitle($0) }
            if let note = move.to.flatMap(model.zoneMovedIn) ?? left.map(CanvasModel.zoneMovedOut) {
                zoneStore.writeSay(move.pane, note)
            }
            guard let from = move.from, let left, model.zone(from) != nil,
                  let card = cards.first(where: { $0.surfaceTree.contains { $0.id == move.pane } }),
                  noticed.insert(card.id).inserted else { continue }
            LosttyNotifications.shared.post(LosttyNotification(
                kind: .zone(card: card.id),
                title: "\(card.title) left \(left)",
                detail: move.to.flatMap(model.zoneTitle).map { "Now in \($0)." } ?? "It's in no zone now."))
        }
        updateZoneCaptions()
    }

    /// Each zone's label says what's in it now (zones spec §3).
    private func updateZoneCaptions() {
        let waiting = Set(waits.since.keys)
        let captions = model.zones.map { zone in
            let held = zone.parent == nil ? model.members(of: zone.id) : []
            let members = held.compactMap { id -> CanvasZoneCaption.Member? in
                if ticketPanels[id] != nil { return .tickets }
                return cards.first { $0.id == id }.map { .terminal(panes: $0.surfaceTree.map(\.id)) }
            }
            return (zone.id, CanvasZoneCaption(
                zone, folder: model.startFolder(ofZone: zone.id), members: members, working: working, waiting: waiting))
        }
        surface.zones.showCaptions(Dictionary(uniqueKeysWithValues: captions))
    }

    /// Lists Lostty's tmux sessions again, off the main thread, and brings
    /// the zone files' members up to date.
    private func tmuxSessionsDidChange() {
        Task { @MainActor [weak self] in
            let sessions = await Task.detached(priority: .utility) { TmuxClient().sessions() }.value
            guard let self else { return }
            tmuxSessions = sessions
            zoneMembershipDidChange()
        }
    }

    /// Pane `pane`'s agent tried to message `target`, outside its zone, and
    /// the hook kept the message inside (zones spec §3, §7): a notice with
    /// Allow Once and the zone's settings, until dismissed.
    func messageKeptInside(pane: UUID, target: String) {
        guard let zone = membership.panes.zones[pane], let project = model.projectZone(zone),
              let name = model.zone(project)?.name,
              let card = cards.first(where: { $0.surfaceTree.contains { $0.id == pane } }) else { return }
        let kind = LosttyNotification.Kind.keptInside(pane: pane)
        LosttyNotifications.shared.post(LosttyNotification(
            kind: kind,
            title: "Kept inside \(name)",
            detail: "\(card.title) tried to message \(target), which is outside the zone.",
            actionTitle: "Allow Once",
            action: { [weak self] in
                self?.zoneStore.writeAllow(pane, target: target)
                self?.zoneStore.writeSay(pane, "You may retry your message to \(target) once.")
                LosttyNotifications.shared.dismiss(kind: kind)
            },
            secondaryTitle: "Zone Settings",
            secondaryAction: { [weak self] in self?.showZoneSettings(project) },
            persistent: true))
    }

    /// Zone `id` in view in the front window, its settings open.
    private func showZoneSettings(_ id: UUID) {
        window?.makeKeyAndOrderFront(nil)
        zoomToZone(id)
        surface.zones.showSettings(id)
    }

    private func retire(_ card: CardController) {
        guard let frame = model.card(card.id)?.frame else { return }
        model.remove(card.id)
        selection.remove(card.id)
        cards.removeAll { $0 === card }
        views.removeValue(forKey: card.id)?.removeFromSuperview()
        if !moving.contains(card.id) {
            retired.append((card, frame))
            if retired.count > Self.retiredLimit { retired.removeFirst() }
        }
        guard focusedCard === card else { return }
        focusedCard = nil
        guard let next = frontCard else { return }
        // A card closing while you work elsewhere never pulls the canvas forward.
        if window?.isKeyWindow == true {
            focus(next)
        } else {
            cardWillFocus(next)
            cardDidFocus(next)
        }
    }

    /// Shows the canvas and pans just enough to bring `card` into view.
    func reveal(_ card: CardController) {
        if window?.isVisible != true { showWindow(nil) }
        guard let view = views[card.id] else { return }
        view.scrollToVisible(view.bounds)
    }

    /// Move to Window: the card's panes become a normal window; nothing restarts.
    /// The card's undo history goes with it: undoing a split it made would
    /// pull the window's panes back into a second card. Dragged off the
    /// canvas (CanvasUnmerge), the window's title bar comes under `point`.
    func moveToWindow(_ card: CardController, under point: NSPoint? = nil) {
        let tree = card.surfaceTree
        guard !tree.isEmpty else { return }
        let width = tree.root?.viewBounds().width ?? 0
        let position = point.map { NSPoint(x: $0.x - width / 2, y: $0.y + 14) }
        let undo = (NSApp.delegate as? AppDelegate)?.undoManager
        undo?.removeAllActions(withTarget: card)
        moving.insert(card.id)
        card.surfaceTree = .init()
        moving.remove(card.id)
        // No "Undo New Window" either: undoing it would close the moved panes.
        if let undo {
            undo.disableUndoRegistration { _ = TerminalController.newWindow(ghostty, tree: tree, position: position) }
        } else {
            _ = TerminalController.newWindow(ghostty, tree: tree, position: position)
        }
    }

    // MARK: Tickets

    /// + → Tickets: a panel opens in the middle of the view, or the one in
    /// the zone there (or outside every zone, as there) comes forward where
    /// it is, at 100% (where its rows take clicks), its list taking the
    /// keyboard.
    func showTickets() {
        let spot = model.placement(size: TicketBoardView.newSize, in: scrollView.documentVisibleRect)
        let zone = model.zone(for: spot)
        let there = model.cards.last { ticketPanels[$0.id] != nil && model.zone(for: $0.frame) == zone }
        let id = there?.id ?? openTickets(frame: spot, draft: parkedDraft).board.id
        if there == nil { parkedDraft = nil }
        ticketWillFocus(id)
        window?.makeFirstResponder(ticketPanels[id])
        guard let frame = model.card(id)?.frame else { return }
        if scrollView.magnification != 1 || !scrollView.documentVisibleRect.contains(frame) { zoom(toCard: id) }
    }

    /// A panel's card at `frame`: in front, or back at `stack` when
    /// restored.
    @discardableResult
    func openTickets(frame: CGRect, stack: Int? = nil, draft: CanvasTicket? = nil) -> TicketBoardView {
        let board = TicketBoard(canvas: self, draft: draft)
        if let stack {
            model.insert(board.id, frame: frame, at: stack)
        } else {
            model.add(board.id, frame: frame)
        }
        board.list.moveToEnd(last: false)
        let view = TicketBoardView(board: board, canvas: self)
        ticketPanels[board.id] = view
        scrollView.document.addSubview(view)
        if let placed = model.card(board.id)?.frame { view.frame = placed }
        restack()
        saveSoon()
        updateZoneCaptions()
        return view
    }

    /// The red button, ⌘W or Close Tickets: panel `id` goes, the tickets
    /// stay, and its sheet waits for the next panel opened. Its Undo goes
    /// with it.
    func closeTickets(_ id: UUID) {
        guard let view = ticketPanels.removeValue(forKey: id) else { return }
        if (window?.firstResponder as? NSView)?.isDescendant(of: view) ?? false {
            window?.makeFirstResponder(scrollView.document)
        }
        if let draft = view.board.draft { parkedDraft = draft }
        (NSApp.delegate as? AppDelegate)?.undoManager.removeAllActions(withTarget: view.board)
        model.remove(id)
        selection.remove(id)
        view.removeFromSuperview()
        saveSoon()
        updateZoneCaptions()
    }

    /// The canvas's tickets are now `new`: every panel lists them.
    func setTickets(_ new: [CanvasTicket]) {
        guard new != tickets else { return }
        relistTickets()
        tickets = new
        saveSoon()
    }

    /// Every panel lists its tickets again: they, the zone it's in, or
    /// that zone's domains changed.
    private func relistTickets() {
        for panel in ticketPanels.values { panel.board.objectWillChange.send() }
    }

    /// A panel was clicked or took the keyboard: it comes to the front,
    /// looks focused, and no other card is. Keys go to its list, unless one
    /// of its fields has them.
    func ticketWillFocus(_ id: UUID) {
        guard let view = ticketPanels[id] else { return }
        bringToFront(id)
        for (other, panel) in ticketPanels { panel.isFocusedCard = other == id }
        let previous = focusedCard
        focusedCard = nil
        // Otherwise a pane keeps the keyboard, and keys type into it.
        if !((window?.firstResponder as? NSView)?.isDescendant(of: view) ?? false) { window?.makeFirstResponder(view) }
        if let previous { letGo(of: previous) }
    }

    /// The selected card under a click at `point` (in the window) while two
    /// or more are selected, on its panes or title bar, not its resize
    /// handles, window buttons or rename pencil, nor anything over the
    /// cards, nor a card being renamed.
    func groupCard(at point: NSPoint) -> UUID? {
        guard selection.count > 1, !surface.floats(at: point) else { return nil }
        let inDocument = scrollView.document.convert(point, from: nil)
        guard scrollView.documentVisibleRect.contains(inDocument), let id = model.card(at: inDocument),
              selection.contains(id), views[id]?.isRenaming != true else { return nil }
        let hit = surface.hitTest(point)
        return hit is CardEdgeHandle || hit is CardWindowButtons || hit is CardRenameButton ? nil : id
    }

    /// A press on a group of selected cards: a drag moves them all; let go
    /// without moving, the selection goes and the card pressed takes focus.
    private func groupPressed(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.shift), let id = groupCard(at: event.locationInWindow) else { return false }
        let point = scrollView.document.convert(event.locationInWindow, from: nil)
        groupDrag = (point, id, beginMove(id), false)
        return true
    }

    private func groupDragged(_ event: NSEvent) -> Bool {
        guard var drag = groupDrag else { return false }
        if event.type == .leftMouseUp {
            groupDrag = nil
            if drag.moved {
                cardFrameDidSettle()
            } else {
                selection = []
                if ticketPanels[drag.id] != nil {
                    ticketWillFocus(drag.id)
                } else if let card = cards.first(where: { $0.id == drag.id }) {
                    focus(card)
                }
            }
            updateGroupHover(at: event.locationInWindow)
            return true
        }
        let point = scrollView.document.convert(event.locationInWindow, from: nil)
        let delta = CGSize(width: point.x - drag.point.x, height: point.y - drag.point.y)
        // A click that wobbles isn't a drag.
        guard drag.moved || hypot(delta.width, delta.height) * scrollView.magnification >= 3 else { return true }
        drag.moved = true
        groupDrag = drag
        NSCursor.closedHand.set()
        move(drag.origins, by: delta)
        return true
    }

    /// An open hand over a group of selected cards, which drags them; the
    /// panes' own cursors everywhere else.
    func updateGroupHover(at point: NSPoint) {
        let over = groupCard(at: point) != nil
        if over != overGroup {
            overGroup = over
            if over {
                window?.disableCursorRects()
            } else {
                window?.enableCursorRects()
                window?.resetCursorRects()
                NSCursor.arrow.set()
            }
        }
        if over, groupDrag == nil { NSCursor.openHand.set() }
    }

    /// A click on a card: with ⇧ on its title bar it goes in or out of the
    /// selection, and the click goes no further; otherwise a click on a card
    /// not selected lets go of the selection.
    private func selectionClicked(_ event: NSEvent) -> Bool {
        let adding = event.modifierFlags.contains(.shift)
        guard adding || !selection.isEmpty, !surface.floats(at: event.locationInWindow) else { return false }
        let point = scrollView.document.convert(event.locationInWindow, from: nil)
        guard scrollView.documentVisibleRect.contains(point), let id = model.card(at: point),
              let frame = model.card(id)?.frame else { return false }
        guard adding else {
            if !selection.contains(id) { selection = [] }
            return false
        }
        guard point.y < frame.minY + CardView.headerHeight else { return false }
        toggleSelection(id)
        return true
    }

    /// A click in the canvas's view on a panel, not on what floats over it.
    private func ticketClicked(_ event: NSEvent) {
        guard !surface.floats(at: event.locationInWindow) else { return }
        let point = scrollView.document.convert(event.locationInWindow, from: nil)
        guard scrollView.documentVisibleRect.contains(point), let id = model.card(at: point), ticketPanels[id] != nil else { return }
        ticketWillFocus(id)
    }

    /// The zone ticket panel `id` is in, where it is now.
    func ticketZone(of id: UUID) -> UUID? {
        model.card(id).flatMap { model.zone(for: $0.frame) }
    }

    /// The key the next ticket made in `zone` gets, with its project's
    /// prefix; `take` hands it out.
    func nextTicketKey(in zone: UUID?, take: Bool = false) -> String {
        CanvasTicket.nextKey(
            prefix: model.ticketPrefix(ofZone: zone), after: tickets.compactMap(\.key), defaults: .standard, take: take)
    }

    // MARK: View

    @objc private func canvasMoved() {
        updateVisibility()
        saveSoon()
        guard scrollView.magnification != settledZoom else { return }
        // As thick on screen as the zoom changes.
        for id in selection { view(id)?.updateRing() }
        surface.zones.updateEdges()
        // While the zoom moves the panes keep their pixels (the compositor
        // scales them) and their grid; they re-render once it settles.
        for card in cards {
            for surface in card.surfaceTree where !surface.canvasZoomInFlight { surface.canvasZoomInFlight = true }
        }
        scheduleSettle()
    }

    func center(on point: CGPoint) {
        let size = scrollView.contentView.bounds.size
        scrollView.contentView.scroll(to: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// ⌃⌘0: every card in view, zoomed no closer than `atMost`.
    func zoomToFit(atMost cap: CGFloat = CanvasZoom.maximum) {
        guard let rect = model.fitRect else { return }
        zoomToFit(rect, atMost: cap)
    }

    /// `rect` in view, zoomed no closer than `atMost`.
    func zoomToFit(_ rect: CGRect, atMost cap: CGFloat = CanvasZoom.maximum) {
        scrollView.magnify(toFit: rect)
        if scrollView.magnification > cap {
            scrollView.magnification = cap
            center(on: CGPoint(x: rect.midX, y: rect.midY))
        }
        settleZoom()
    }

    /// ⌃⌘1, double-clicking a header, the green button: glides to `card`
    /// centered at `zoom` (100%).
    func zoom(to card: CardController, zoom: CGFloat = 1) {
        self.zoom(toCard: card.id, zoom: zoom)
    }

    /// The same for card `id`, of either kind.
    func zoom(toCard id: UUID, zoom: CGFloat = 1) {
        guard let frame = model.card(id)?.frame else { return }
        glide(to: CanvasView(center: CGPoint(x: frame.midX, y: frame.midY), zoom: zoom))
    }

    /// The zoom stopped changing: the terminals re-render at it.
    func settleZoom() {
        settleWork?.cancel()
        settledZoom = scrollView.magnification
        for card in cards {
            for surface in card.surfaceTree { surface.canvasZoomDidSettle(settledZoom) }
        }
        updateVisibility()
        saveSoon()
    }

    /// Which cards draw: only those near the view, and none while the
    /// canvas is hidden or covered.
    func updateVisibility() {
        let shown = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        let inView = model.cardsInView(scrollView.documentVisibleRect)
        for card in cards {
            views[card.id]?.mode = shown && inView.contains(card.id) ? .live : .hidden
        }
    }

    /// The app saves its restorable state (and the canvas with it) soon.
    func saveSoon() {
        NSApp.invalidateRestorableState()
        LastSessionStore.shared.noteChange()
    }

    // MARK: NSWindowDelegate

    /// Closing the canvas hides it; its terminals keep running.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        updateVisibility()
        saveSoon()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        placeIfNeeded()
        // Only the focused card restores keyboard focus to its pane.
        focusedCard?.windowDidBecomeKey(notification)
        for card in cards where card !== focusedCard { card.syncFocusToSurfaceTree() }
    }

    func windowDidResignKey(_ notification: Notification) {
        for card in cards { card.windowDidResignKey(notification) }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        placeIfNeeded()
        updateVisibility()
    }

    func windowDidResize(_ notification: Notification) {
        updateVisibility()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (NSApp.delegate as? AppDelegate)?.undoManager
    }
}
#endif
