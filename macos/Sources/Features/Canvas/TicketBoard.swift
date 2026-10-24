#if os(macOS)
import AppKit
import SwiftUI

/// The tickets panel's state: the list, the new ticket being written, and
/// where the keyboard is. Every change saves the canvas. Moving, changing,
/// making and deleting a ticket can be undone; typing undoes in its field.
@MainActor
final class TicketBoard: ObservableObject {
    /// The fields the keyboard can be sent to.
    enum Field: Hashable { case summary, details, assignee, newSummary, newDetails, newAssignee }

    /// What a menu picks.
    enum Property: Hashable { case status, priority, kind, assignee }

    /// A property's row in the inspector, or its chip on the new ticket.
    struct Anchor: Hashable {
        var property: Property
        var new = false
    }

    /// The SwiftUI coordinate space anchors are measured in: the panel's
    /// content, y down.
    static let space = "TicketBoard"
    static let motion = Animation.spring(response: 0.38, dampingFraction: 0.86)

    /// The panel's card on the canvas.
    let id = UUID()
    @Published var list = TicketList() {
        didSet { if list != oldValue { canvas?.saveSoon() } }
    }

    /// The new ticket's sheet while it's open, with what's typed in it.
    @Published var draft: CanvasTicket? {
        didSet { if draft != oldValue { canvas?.saveSoon() } }
    }

    /// Keep the sheet open after Create, for the next ticket.
    @Published var createMore = false
    /// The list has the keyboard: its selection shows in the accent color.
    @Published var listFocused = false
    /// Where the keyboard goes next. The panel's SwiftUI focus follows,
    /// then clears it.
    @Published var focusRequest: Field?
    /// A ticket just moved or made: its row flashes.
    @Published var landed: String?
    /// Create was asked for with no summary.
    @Published var needsSummary = false

    /// Where each anchor is, for its menu (not published: it changes with
    /// every layout).
    var anchors: [Anchor: CGRect] = [:]
    weak var canvas: CanvasController?
    /// The panel's view: shows a menu under a frame in the content, and
    /// gives the list the keyboard.
    var popUp: ((NSMenu, CGRect) -> Void)?
    var focusList: (() -> Void)?

    var selectedTicket: CanvasTicket? {
        list.selected.flatMap(list.ticket)
    }

    /// The names tickets are assigned to, for the assignee menus.
    var people: [String] {
        let names = list.tickets.map { $0.assignee.trimmingCharacters(in: .whitespaces) } + [draft?.assignee ?? ""]
        return Set(names.filter { !$0.isEmpty }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The key the new ticket will get.
    var nextKey: String {
        canvas?.peekNextTicketKey() ?? CanvasTicket.nextKey(after: list.tickets.compactMap(\.key))
    }

    // MARK: The list

    /// A click on a row: it's selected and the list takes the keyboard.
    func select(_ key: String) {
        list.selected = key
        focusList?()
    }

    func move(by delta: Int) {
        list.move(by: delta)
    }

    func toggleFold(_ status: CanvasTicket.Status) {
        withAnimation(Self.motion) { list.fold(status, !list.folded.contains(status)) }
    }

    func setStatus(_ status: CanvasTicket.Status, of key: String) {
        guard var ticket = list.ticket(key) else { return }
        ticket.status = status
        change(ticket, "Move Ticket")
    }

    func cycleStatus(of key: String) {
        guard let ticket = list.ticket(key) else { return }
        setStatus(ticket.status.next, of: key)
    }

    /// A change from a menu or the list, which Undo takes back.
    func change(_ ticket: CanvasTicket, _ action: String) {
        guard let key = ticket.key, let old = list.ticket(key), old != ticket else { return }
        withAnimation(Self.motion) { list.update(ticket) }
        if old.status != ticket.status { flash(key) }
        // Only what this changed goes back, not typing since.
        registerUndo(action) { board in
            guard let now = board.list.ticket(key) else { return }
            board.change(now.reverting(ticket, to: old), action)
        }
    }

    /// Typing in the inspector: its field undoes its own typing.
    func edit(_ key: String, _ apply: (inout CanvasTicket) -> Void) {
        guard var ticket = list.ticket(key) else { return }
        apply(&ticket)
        list.update(ticket)
    }

    func delete(_ key: String, _ action: String = "Delete Ticket") {
        guard let removed = withAnimation(Self.motion, { list.remove(key) }) else { return }
        registerUndo(action) { $0.restore(removed.ticket, at: removed.index, action) }
    }

    private func restore(_ ticket: CanvasTicket, at index: Int, _ action: String) {
        guard let key = ticket.key else { return }
        withAnimation(Self.motion) { list.add(ticket, at: index) }
        flash(key)
        registerUndo(action) { $0.delete(key, action) }
    }

    func copyKey() {
        guard let key = list.selected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
    }

    /// The row flashes, then fades back.
    private func flash(_ key: String) {
        landed = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, landed == key else { return }
            withAnimation(.easeOut(duration: 0.7)) { self.landed = nil }
        }
    }

    // MARK: The new ticket

    /// C, the + in a section's header, or New Ticket: the sheet opens (with
    /// what was typed before, if it was left open), its summary taking the
    /// keyboard.
    func newTicket(in status: CanvasTicket.Status = .toDo) {
        if draft == nil {
            withAnimation(.easeOut(duration: 0.18)) { draft = CanvasTicket(status: status) }
        }
        needsSummary = false
        focusRequest = .newSummary
    }

    func cancelNew() {
        withAnimation(.easeOut(duration: 0.15)) { draft = nil }
        needsSummary = false
        focusList?()
    }

    /// The new ticket gets the next key and joins the list, selected. With
    /// Create More on the sheet stays, for another of the same kind.
    func create() {
        guard var ticket = draft else { return }
        guard ticket.canSave else {
            needsSummary = true
            focusRequest = .newSummary
            return
        }
        let key = canvas?.nextTicketKey() ?? nextKey
        ticket.key = key
        ticket.summary = ticket.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        ticket.assignee = ticket.assignee.trimmingCharacters(in: .whitespaces)
        withAnimation(Self.motion) { list.add(ticket) }
        flash(key)
        registerUndo("New Ticket") { $0.delete(key, "New Ticket") }
        needsSummary = false
        if createMore {
            draft = CanvasTicket(kind: ticket.kind, priority: ticket.priority, status: ticket.status, assignee: ticket.assignee)
            focusRequest = .newSummary
        } else {
            withAnimation(.easeOut(duration: 0.15)) { draft = nil }
            focusList?()
        }
    }

    // MARK: Menus

    /// The menu for a property of the selected ticket, or the new one,
    /// under its row or chip.
    func pick(_ property: Property, new: Bool = false) {
        guard let ticket = new ? draft : selectedTicket,
              let frame = anchors[Anchor(property: property, new: new)] else { return }
        popUp?(menu(property, for: ticket, new: new), frame)
    }

    private func menu(_ property: Property, for ticket: CanvasTicket, new: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ image: NSImage?, on: Bool, key: String = "", _ set: @escaping (inout CanvasTicket) -> Void) {
            let item = TicketMenuItem(title: title, keyEquivalent: key) { [weak self] in self?.apply(set, new: new, property) }
            item.image = image
            item.state = on ? .on : .off
            item.keyEquivalentModifierMask = []
            menu.addItem(item)
        }
        switch property {
        case .status:
            for (index, status) in CanvasTicket.Status.allCases.enumerated() {
                add(status.title, status.menuImage, on: ticket.status == status, key: "\(index + 1)") { $0.status = status }
            }
        case .priority:
            for (index, priority) in CanvasTicket.Priority.allCases.enumerated() {
                add(priority.title, priority.menuImage, on: ticket.priority == priority, key: "\(index + 1)") { $0.priority = priority }
            }
        case .kind:
            for (index, kind) in CanvasTicket.Kind.allCases.enumerated() {
                add(kind.title, kind.menuImage, on: ticket.kind == kind, key: "\(index + 1)") { $0.kind = kind }
            }
        case .assignee:
            let person = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)
            add("Unassigned", person, on: ticket.assignee.isEmpty) { $0.assignee = "" }
            if !people.isEmpty { menu.addItem(.separator()) }
            for name in people {
                add(name, nil, on: ticket.assignee == name) { $0.assignee = name }
            }
            menu.addItem(.separator())
            let other = TicketMenuItem(title: "Someone Else…", keyEquivalent: "") { [weak self] in
                self?.focusRequest = new ? .newAssignee : .assignee
            }
            menu.addItem(other)
        }
        return menu
    }

    private func apply(_ set: (inout CanvasTicket) -> Void, new: Bool, _ property: Property) {
        if new {
            guard var ticket = draft else { return }
            set(&ticket)
            draft = ticket
            focusRequest = .newSummary
            return
        }
        guard var ticket = selectedTicket else { return }
        set(&ticket)
        change(ticket, property == .status ? "Move Ticket" : "Change Ticket")
    }

    private func registerUndo(_ action: String, _ undo: @escaping (TicketBoard) -> Void) {
        guard let canvas, let manager = (NSApp.delegate as? AppDelegate)?.undoManager else { return }
        manager.setActionName(action)
        manager.registerUndo(withTarget: self, expiresAfter: canvas.ghostty.config.undoTimeout, handler: undo)
    }
}

/// A menu item that runs a closure.
private final class TicketMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, keyEquivalent: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(chosen), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func chosen() {
        run()
    }
}
#endif
