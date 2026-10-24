#if os(macOS)
import AppKit
import SwiftUI

/// The tickets panel's card on the canvas, cut like a terminal card: a Mac
/// window's corners, edge and shadow, the red, yellow and green buttons in
/// a title bar that drags it, and resize handles on its edges. Under the
/// title bar, the tickets (TicketBoardContent).
///
/// The card takes the keyboard for the list, so its keys work only while
/// the list has it: never while a terminal or one of the panel's own
/// fields does.
final class TicketBoardView: NSView, CanvasStacked {
    static let newSize = CGSize(width: 900, height: 580)

    let board: TicketBoard
    private weak var canvas: CanvasController?
    private let content = CardContentView()
    private let header: TicketBoardHeaderView
    private let host: TicketBoardHost
    private var handles: [CardEdgeHandle] = []
    var stackIndex = 0

    /// The focused card looks like the active window, as a terminal card does.
    var isFocusedCard = false {
        didSet {
            needsDisplay = true
            header.buttons.isActive = isFocusedCard
        }
    }

    init(board: TicketBoard, canvas: CanvasController) {
        self.board = board
        self.canvas = canvas
        header = TicketBoardHeaderView(board: board, canvas: canvas)
        host = TicketBoardHost(rootView: TicketBoardContent(board: board))
        super.init(frame: .zero)
        CardView.setUpWindowLook(self, content: content)
        content.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        addSubview(content)
        content.addSubview(host)
        content.addSubview(header)
        header.buttons.isActive = false
        for edges in CanvasModel.handleEdges {
            let handle = CardEdgeHandle(edges: edges, id: board.id, canvas: canvas)
            handles.append(handle)
            addSubview(handle)
        }
        board.focusList = { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
        board.popUp = { [weak self] menu, frame in
            guard let self else { return }
            let y = host.isFlipped ? frame.maxY + 4 : host.bounds.height - frame.maxY - 4
            menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: y), in: host)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        board.listFocused = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        board.listFocused = false
        return true
    }

    override func updateLayer() {
        CardView.updateWindowLook(self, content: content, focused: isFocusedCard)
        content.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    override func layout() {
        super.layout()
        content.frame = bounds
        layer?.shadowPath = CGPath(
            roundedRect: bounds, cornerWidth: CardView.cornerRadius, cornerHeight: CardView.cornerRadius, transform: nil)
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: CardView.headerHeight)
        host.frame = NSRect(
            x: 0, y: CardView.headerHeight, width: bounds.width, height: max(0, bounds.height - CardView.headerHeight))
        for handle in handles { handle.frame = CanvasModel.handleFrame(for: handle.edges, in: bounds) }
    }

    /// A click on the panel while the canvas is zoomed (see TicketBoardHost)
    /// zooms to it at 100%, where its rows and fields take clicks.
    override func mouseDown(with event: NSEvent) {
        canvas?.zoom(toCard: board.id)
    }

    /// A scroll its list doesn't take pans the canvas.
    override func scrollWheel(with event: NSEvent) {
        enclosingScrollView?.scrollWheel(with: event)
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if !handle(event) { super.keyDown(with: event) }
    }

    /// The list's keys, as its hints show them. Keys with ⌘, ⌃ or ⌥ are
    /// left to the menus.
    private func handle(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
        // The new ticket's sheet is over the list: keys go to it.
        if board.draft != nil {
            if event.keyCode == 53 {
                board.cancelNew()
            } else {
                board.focusRequest = .newSummary
            }
            return true
        }
        let selected = board.list.selected
        switch event.keyCode {
        case 125: board.move(by: 1)
        case 126: board.move(by: -1)
        case 115: board.list.moveToEnd(last: false)
        case 119: board.list.moveToEnd(last: true)
        case 123:
            guard let status = selected.flatMap(board.list.ticket)?.status else { return false }
            withAnimation(TicketBoard.motion) { board.list.fold(status) }
        case 124: withAnimation(TicketBoard.motion) { board.list.folded = [] }
        case 36, 76:
            guard selected != nil else { return false }
            board.focusRequest = .summary
        case 51, 117:
            guard let selected else { return false }
            board.delete(selected)
        default:
            return handle(character: event.charactersIgnoringModifiers?.lowercased() ?? "", selected: selected)
        }
        return true
    }

    private func handle(character: String, selected: String?) -> Bool {
        switch character {
        case "j": board.move(by: 1)
        case "k": board.move(by: -1)
        case "c": board.newTicket()
        case "1", "2", "3":
            guard let selected, let index = Int(character) else { return false }
            board.setStatus(CanvasTicket.Status.allCases[index - 1], of: selected)
        case "s":
            guard let selected else { return false }
            board.cycleStatus(of: selected)
        case "d":
            guard selected != nil else { return false }
            board.focusRequest = .details
        case "p": board.pick(.priority)
        case "t": board.pick(.kind)
        case "a": board.pick(.assignee)
        default: return false
        }
        return true
    }

    /// ⌘C on the list copies the selected ticket's key.
    @IBAction func copy(_ sender: Any?) {
        board.copyKey()
    }

    /// Edit → Delete deletes the selected ticket, as ⌫ does.
    @IBAction func delete(_ sender: Any?) {
        guard let selected = board.list.selected else { return }
        board.delete(selected)
    }

    /// ⌘W (Close) and ⇧⌘W (Close Window) in the panel close it, as the red
    /// button does, not the canvas.
    @IBAction func close(_ sender: Any?) {
        canvas?.closeTickets()
    }

    @IBAction func closeWindow(_ sender: Any?) {
        canvas?.closeTickets()
    }
}

/// Hosts the panel's content. While the canvas is zoomed SwiftUI misplaces
/// clicks, as on a terminal card (CardTerminalHost), so then every click
/// goes to the panel's card, which zooms to 100%. Scrolling over the
/// focused panel scrolls its list, and over any other pans the canvas, as
/// over a pane; ⌥ swaps the two. A scroll that pans goes to the panel's
/// card, which hands it on up to the canvas.
final class TicketBoardHost: NSHostingView<TicketBoardContent> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        if let event = NSApp.currentEvent, event.type == .scrollWheel, let canvas = enclosingScrollView as? CanvasScrollView {
            // Decided as the scroll starts (CanvasScrollView.scrollingTicket).
            if CanvasScrollView.startsScroll(event) {
                let focused = enclosingBoard?.isFocusedCard ?? false
                canvas.scrollingTicket = focused != event.modifierFlags.contains(.option) ? self : nil
            }
            if canvas.scrollingTicket !== self { return enclosingBoard }
        }
        guard (enclosingScrollView?.magnification ?? 1) != 1 else { return super.hitTest(point) }
        return enclosingBoard
    }

    /// Zoomed, the panel is one element, as SwiftUI's own accessibility
    /// hit test loops until Lostty crashes (CardTerminalHost).
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        (enclosingScrollView?.magnification ?? 1) != 1 ? self : super.accessibilityHitTest(point)
    }

    private var enclosingBoard: TicketBoardView? {
        var view = superview
        while let next = view, !(next is TicketBoardView) { view = next.superview }
        return view as? TicketBoardView
    }
}

/// The panel's title bar, as a terminal card's: close, minimize and zoom
/// buttons, "Tickets" and how many are in each section, and New Ticket at
/// the right. Dragging it moves the panel; double-clicking zooms to it at
/// 100%.
final class TicketBoardHeaderView: NSView {
    private let board: TicketBoard
    private weak var canvas: CanvasController?
    private let title: PassthroughHostingView<TicketBoardTitle>
    private let newButton: TicketNewButtonHost
    let buttons: CardWindowButtons
    private var start: (point: CGPoint, origin: CGPoint)?

    init(board: TicketBoard, canvas: CanvasController) {
        self.board = board
        self.canvas = canvas
        title = PassthroughHostingView(rootView: TicketBoardTitle(board: board))
        newButton = TicketNewButtonHost(rootView: TicketNewButton(board: board))
        buttons = CardWindowButtons { [weak board, weak canvas] button in
            guard let board, let canvas else { return }
            switch button {
            case .close: canvas.closeTickets()
            case .minimize: canvas.zoomToFit()
            case .zoom: canvas.zoom(toCard: board.id)
            }
        }
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(title)
        addSubview(newButton)
        addSubview(buttons)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func layout() {
        super.layout()
        title.frame = bounds
        let size = buttons.intrinsicContentSize
        buttons.frame = NSRect(x: 12, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        let new = newButton.fittingSize
        newButton.frame = NSRect(
            x: bounds.width - new.width - 8, y: (bounds.height - new.height) / 2, width: new.width, height: new.height)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            canvas?.zoom(toCard: board.id)
            return
        }
        guard let point = documentPoint(event), let frame = canvas?.model.card(board.id)?.frame else { return }
        start = (point, frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let start, let point = documentPoint(event),
              var frame = canvas.model.card(board.id)?.frame else { return }
        frame.origin = CGPoint(x: start.origin.x + point.x - start.point.x, y: start.origin.y + point.y - start.point.y)
        canvas.setFrame(frame, of: board.id)
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        canvas?.cardFrameDidSettle()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Ticket", action: #selector(newTicket), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Tickets", action: #selector(closeTickets), keyEquivalent: "").target = self
        return menu
    }

    @objc private func newTicket() {
        board.newTicket()
    }

    @objc private func closeTickets() {
        canvas?.closeTickets()
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint? {
        enclosingScrollView?.documentView?.convert(event.locationInWindow, from: nil)
    }
}

/// The title bar's New Ticket button. Zoomed, its clicks go to the title
/// bar under it (SwiftUI misplaces them), which drags and zooms.
final class TicketNewButtonHost: NSHostingView<TicketNewButton> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        (enclosingScrollView?.magnification ?? 1) != 1 ? nil : super.hitTest(point)
    }
}

/// The title, in the middle of the title bar: "Tickets", then how many
/// are in progress, up next and done.
struct TicketBoardTitle: View {
    @ObservedObject var board: TicketBoard

    var body: some View {
        let list = board.list
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Tickets")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))
            Text("\(list.count(.inProgress)) in progress · \(list.count(.toDo)) up next · \(list.count(.done)) done")
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TicketNewButton: View {
    @ObservedObject var board: TicketBoard
    @State private var hovering = false

    var body: some View {
        Button { board.newTicket() } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("New Ticket")
                    .font(.system(size: 12, weight: .medium))
                TicketKeyCap("C")
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 24)
            .background(Color.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("New Ticket (C)")
    }
}
#endif
