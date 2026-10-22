#if os(macOS)
import AppKit
import SwiftUI

/// A ticket on the canvas: what it says, and the copy being edited.
@MainActor
final class TicketCard: ObservableObject {
    let id: UUID
    @Published var ticket: CanvasTicket
    /// The copy being edited; nil while the ticket is only shown.
    @Published var draft: CanvasTicket?
    private weak var canvas: CanvasController?

    init(id: UUID, ticket: CanvasTicket, canvas: CanvasController) {
        self.id = id
        self.ticket = ticket
        self.canvas = canvas
    }

    func edit() {
        draft = ticket
    }

    /// Create or Save: a new ticket gets the next key.
    func save() {
        guard var edited = draft, edited.canSave else { return }
        if !edited.isCreated { edited.key = canvas?.nextTicketKey() }
        ticket = edited
        draft = nil
        canvas?.saveSoon()
    }

    /// Cancel throws a draft away, and a new ticket with it.
    func cancel() {
        guard ticket.isCreated else {
            close()
            return
        }
        draft = nil
    }

    func setStatus(_ status: CanvasTicket.Status) {
        ticket.status = status
        canvas?.saveSoon()
    }

    func close() {
        canvas?.closeTicket(id)
    }
}

/// A ticket's card on the canvas, cut like a terminal card: a Mac window's
/// corners, edge and shadow, the red, yellow and green buttons in a title
/// bar that drags it, and resize handles on its edges. The ticket shows
/// under the title bar, or its form while it's edited.
final class TicketCardView: NSView, CanvasStacked {
    static let newSize = CGSize(width: 380, height: 360)

    let ticket: TicketCard
    private weak var canvas: CanvasController?
    private let content = CardContentView()
    private let header: TicketHeaderView
    private let details: TicketDetailsHost
    private var handles: [CardEdgeHandle] = []
    var stackIndex = 0

    /// The focused card looks like the active window, as a terminal card does.
    var isFocusedCard = false {
        didSet {
            needsDisplay = true
            header.buttons.isActive = isFocusedCard
        }
    }

    init(ticket: TicketCard, canvas: CanvasController) {
        self.ticket = ticket
        self.canvas = canvas
        header = TicketHeaderView(ticket: ticket, canvas: canvas)
        details = TicketDetailsHost(rootView: TicketCardContent(ticket: ticket))
        super.init(frame: .zero)
        CardView.setUpWindowLook(self, content: content)
        content.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        addSubview(content)
        content.addSubview(details)
        content.addSubview(header)
        header.buttons.isActive = false
        for edges in CanvasModel.handleEdges {
            let handle = CardEdgeHandle(edges: edges, id: ticket.id, canvas: canvas)
            handles.append(handle)
            addSubview(handle)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    /// Takes the keyboard from a terminal when clicked between its fields.
    override var acceptsFirstResponder: Bool { true }

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
        details.frame = NSRect(
            x: 0, y: CardView.headerHeight, width: bounds.width, height: max(0, bounds.height - CardView.headerHeight))
        for handle in handles { handle.frame = CanvasModel.handleFrame(for: handle.edges, in: bounds) }
    }

    /// A click on the ticket while the canvas is zoomed (see
    /// TicketDetailsHost) zooms to it at 100%, where its fields take clicks.
    override func mouseDown(with event: NSEvent) {
        canvas?.zoom(toCard: ticket.id)
    }
}

/// Hosts a ticket's details or form. While the canvas is zoomed SwiftUI
/// misplaces clicks, as on a terminal card (CardTerminalHost), so then
/// every click goes to the ticket's card, which zooms to 100%.
final class TicketDetailsHost: NSHostingView<TicketCardContent> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard (enclosingScrollView?.magnification ?? 1) != 1 else { return super.hitTest(point) }
        guard frame.contains(point) else { return nil }
        var view = superview
        while let next = view, !(next is TicketCardView) { view = next.superview }
        return view
    }
}

/// A ticket's title bar, as a terminal card's: close, minimize and zoom
/// buttons, then the ticket's type and key. Dragging it moves the ticket;
/// double-clicking zooms to it at 100%.
final class TicketHeaderView: NSView {
    private let ticket: TicketCard
    private weak var canvas: CanvasController?
    private let content: PassthroughHostingView<TicketHeaderContent>
    let buttons: CardWindowButtons
    private var start: (point: CGPoint, origin: CGPoint)?

    init(ticket: TicketCard, canvas: CanvasController) {
        self.ticket = ticket
        self.canvas = canvas
        content = PassthroughHostingView(rootView: TicketHeaderContent(ticket: ticket))
        buttons = CardWindowButtons { [weak ticket, weak canvas] button in
            guard let ticket, let canvas else { return }
            switch button {
            case .close: ticket.close()
            case .minimize: canvas.zoomToFit()
            case .zoom: canvas.zoom(toCard: ticket.id)
            }
        }
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(content)
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
        content.frame = bounds
        let size = buttons.intrinsicContentSize
        buttons.frame = NSRect(x: 12, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            canvas?.zoom(toCard: ticket.id)
            return
        }
        guard let point = documentPoint(event), let frame = canvas?.model.card(ticket.id)?.frame else { return }
        start = (point, frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let start, let point = documentPoint(event),
              var frame = canvas.model.card(ticket.id)?.frame else { return }
        frame.origin = CGPoint(x: start.origin.x + point.x - start.point.x, y: start.origin.y + point.y - start.point.y)
        canvas.setFrame(frame, of: ticket.id)
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        canvas?.cardFrameDidSettle()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        if ticket.draft == nil {
            menu.addItem(withTitle: "Edit Ticket", action: #selector(editTicket), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Close Ticket", action: #selector(closeTicket), keyEquivalent: "").target = self
        return menu
    }

    @objc private func editTicket() {
        ticket.edit()
    }

    @objc private func closeTicket() {
        ticket.close()
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint? {
        enclosingScrollView?.documentView?.convert(event.locationInWindow, from: nil)
    }
}

/// What a ticket's title bar shows after the buttons: its type and key.
struct TicketHeaderContent: View {
    @ObservedObject var ticket: TicketCard

    var body: some View {
        HStack(spacing: 6) {
            TicketKindIcon(kind: (ticket.draft ?? ticket.ticket).kind)
            Text(ticket.ticket.key ?? "New Ticket")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.leading, CardHeaderContent.titleInset)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Under a ticket's title bar: the ticket, or its form while it's edited.
struct TicketCardContent: View {
    @ObservedObject var ticket: TicketCard

    var body: some View {
        if ticket.draft != nil {
            TicketForm(ticket: ticket)
        } else {
            TicketDetails(ticket: ticket)
        }
    }
}

/// A ticket as Jira shows one on a board: its summary and status, what
/// it's about, and its priority and assignee. Double-click to edit it.
private struct TicketDetails: View {
    @ObservedObject var ticket: TicketCard

    var body: some View {
        let shown = ticket.ticket
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(shown.summary)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TicketStatusMenu(status: shown.status) { ticket.setStatus($0) }
            }
            if shown.details.isEmpty {
                Text("No description")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    Text(shown.details)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                TicketPriorityLabel(priority: shown.priority)
                TicketAssigneeLabel(assignee: shown.assignee)
                Spacer(minLength: 0)
                Button("Edit") { ticket.edit() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { ticket.edit() }
    }
}

/// A new ticket's form, or an existing one's while it's edited. ⌘↩ saves,
/// Escape cancels.
private struct TicketForm: View {
    @ObservedObject var ticket: TicketCard
    @FocusState private var summaryFocused: Bool

    private var draft: Binding<CanvasTicket> {
        Binding(get: { ticket.draft ?? ticket.ticket }, set: { ticket.draft = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Summary", text: draft.summary)
                .textFieldStyle(.roundedBorder)
                .focused($summaryFocused)
                .onSubmit { ticket.save() }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Picker("Type", selection: draft.kind) {
                        ForEach(CanvasTicket.Kind.allCases, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    Picker("Priority", selection: draft.priority) {
                        ForEach(CanvasTicket.Priority.allCases, id: \.self) { priority in
                            Label(priority.title, systemImage: priority.symbol).tag(priority)
                        }
                    }
                }
                GridRow {
                    Picker("Status", selection: draft.status) {
                        ForEach(CanvasTicket.Status.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Assignee", text: draft.assignee)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 12))
            TextEditor(text: draft.details)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .overlay(alignment: .topLeading) {
                    if draft.wrappedValue.details.isEmpty {
                        Text("Description")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Spacer()
                Button("Cancel") { ticket.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(ticket.ticket.isCreated ? "Save" : "Create") { ticket.save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.wrappedValue.canSave)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Once it's in the window: before then the field can't take the keyboard.
        .onAppear { DispatchQueue.main.async { summaryFocused = true } }
    }
}

/// A ticket's status, Jira's colored lozenge, and the menu that changes it.
private struct TicketStatusMenu: View {
    let status: CanvasTicket.Status
    let change: (CanvasTicket.Status) -> Void

    var body: some View {
        Menu {
            ForEach(CanvasTicket.Status.allCases, id: \.self) { status in
                Button(status.title) { change(status) }
            }
        } label: {
            Text(status.title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(status.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(status.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change status")
    }
}

private struct TicketKindIcon: View {
    let kind: CanvasTicket.Kind

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(kind.color)
            .help(kind.title)
    }
}

private struct TicketPriorityLabel: View {
    let priority: CanvasTicket.Priority

    var body: some View {
        Label {
            Text(priority.title)
        } icon: {
            Image(systemName: priority.symbol).foregroundStyle(priority.color)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

/// The assignee's initial in a circle, and their name; "Unassigned" when
/// there's none.
private struct TicketAssigneeLabel: View {
    let assignee: String

    var body: some View {
        let name = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
        HStack(spacing: 5) {
            if let initial = name.first {
                Text(String(initial).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.accentColor, in: Circle())
                Text(name).lineLimit(1)
            } else {
                Image(systemName: "person.crop.circle")
                Text("Unassigned")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

/// Jira's icons and colors for each, in SF Symbols.
extension CanvasTicket.Kind {
    var symbol: String {
        switch self {
        case .task: "checkmark.square.fill"
        case .bug: "ladybug.fill"
        case .story: "bookmark.fill"
        }
    }

    var color: Color {
        switch self {
        case .task: .blue
        case .bug: .red
        case .story: .green
        }
    }
}

extension CanvasTicket.Priority {
    var symbol: String {
        switch self {
        case .highest: "chevron.up.2"
        case .high: "chevron.up"
        case .medium: "equal"
        case .low: "chevron.down"
        case .lowest: "chevron.down.2"
        }
    }

    var color: Color {
        switch self {
        case .highest, .high: .red
        case .medium: .orange
        case .low, .lowest: .blue
        }
    }
}

extension CanvasTicket.Status {
    var color: Color {
        switch self {
        case .toDo: .secondary
        case .inProgress: .blue
        case .done: .green
        }
    }
}
#endif
