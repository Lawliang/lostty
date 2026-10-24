#if os(macOS)
import AppKit
import SwiftUI

/// The tickets panel under its title bar: the list in sections on the
/// left with the keys it takes along the bottom, the selected ticket on
/// the right (when there's room), and the new ticket's sheet over both.
struct TicketBoardContent: View {
    @ObservedObject var board: TicketBoard
    @FocusState private var focus: TicketBoard.Field?

    /// Narrower than this, the inspector is left out.
    static let inspectorRoom: CGFloat = 600

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    TicketListView(board: board)
                    TicketHints(focused: board.listFocused)
                }
                if geometry.size.width >= Self.inspectorRoom {
                    Divider()
                    TicketInspector(board: board, focus: $focus)
                        .frame(width: 320)
                }
            }
            .overlay {
                if board.draft != nil {
                    TicketComposer(board: board, focus: $focus)
                        .transition(.opacity)
                }
            }
        }
        .coordinateSpace(name: TicketBoard.space)
        .onPreferenceChange(TicketAnchorKey.self) { board.anchors = $0 }
        .onChange(of: board.focusRequest) { _, field in
            guard let field else { return }
            // Once it's in the window: before then a field can't take the keyboard.
            DispatchQueue.main.async {
                focus = field
                board.focusRequest = nil
            }
        }
    }
}

/// Where a menu's row or chip is, for the menu to open under it.
struct TicketAnchorKey: PreferenceKey {
    static let defaultValue: [TicketBoard.Anchor: CGRect] = [:]

    static func reduce(value: inout [TicketBoard.Anchor: CGRect], nextValue: () -> [TicketBoard.Anchor: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func ticketAnchor(_ anchor: TicketBoard.Anchor) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: TicketAnchorKey.self, value: [anchor: geometry.frame(in: .named(TicketBoard.space))])
        })
    }
}

// MARK: The list

/// The tickets in their sections, In Progress, Up Next and Completed, one
/// flat stack so a ticket changing section slides to its new place.
private struct TicketListView: View {
    @ObservedObject var board: TicketBoard

    private enum Item: Identifiable {
        case header(CanvasTicket.Status)
        case row(CanvasTicket)
        case empty(CanvasTicket.Status)

        var id: String {
            switch self {
            case .header(let status): "header-\(status.rawValue)"
            case .row(let ticket): ticket.key ?? ""
            case .empty(let status): "empty-\(status.rawValue)"
            }
        }
    }

    private var items: [Item] {
        TicketList.sections.flatMap { status -> [Item] in
            guard !board.list.folded.contains(status) else { return [.header(status)] }
            let tickets = board.list.tickets(in: status)
            return [.header(status)] + (tickets.isEmpty ? [.empty(status)] : tickets.map(Item.row))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .header(let status):
                            TicketSectionHeader(board: board, status: status)
                                .padding(.top, status == TicketList.sections.first ? 0 : 2)
                        case .row(let ticket):
                            TicketRow(board: board, ticket: ticket)
                        case .empty(let status):
                            Text(Self.emptyText(status))
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 40)
                                .padding(.vertical, 7)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: board.list.selected) { _, key in
                guard let key else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(key) }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private static func emptyText(_ status: CanvasTicket.Status) -> String {
        switch status {
        case .inProgress: "Nothing in progress. Press 2 on a ticket to start it."
        case .toDo: "Nothing up next. Press C to add a ticket."
        case .done: "Nothing completed yet."
        }
    }
}

/// A section's header: fold it, see how many, or add a ticket to it.
private struct TicketSectionHeader: View {
    @ObservedObject var board: TicketBoard
    let status: CanvasTicket.Status
    @State private var hovering = false
    @State private var hoveringToggle = false

    var body: some View {
        let folded = board.list.folded.contains(status)
        HStack(spacing: 4) {
            Button { board.toggleFold(status) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(folded ? 0 : 90))
                        .frame(width: 10)
                    TicketStatusIcon(status: status)
                    Text(status.sectionTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(board.list.count(status))")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 26)
                .background(Color.primary.opacity(hoveringToggle ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringToggle = $0 }
            .accessibilityLabel("\(status.sectionTitle), \(board.list.count(status)) tickets, \(folded ? "folded" : "unfolded")")
            Button { board.newTicket(in: status) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("New Ticket in \(status.sectionTitle)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: 32)
        .onHover { hovering = $0 }
    }
}

/// A ticket in the list: its type, key, status (click for the next one),
/// summary, priority and assignee. Click to select it, double-click to
/// edit its summary.
private struct TicketRow: View {
    @ObservedObject var board: TicketBoard
    let ticket: CanvasTicket
    @State private var hovering = false

    var body: some View {
        let key = ticket.key ?? ""
        HStack(spacing: 10) {
            TicketKindBadge(kind: ticket.kind)
            Text(key)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 44, alignment: .leading)
            Button { board.cycleStatus(of: key) } label: {
                TicketStatusIcon(status: ticket.status)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("\(ticket.status.title): click for \(ticket.status.next.title) (S)")
            Text(ticket.summary)
                .font(.system(size: 13))
                .foregroundStyle(ticket.status == .done ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            TicketPriorityIcon(priority: ticket.priority)
                .help("\(ticket.priority.title) priority")
            TicketAvatar(name: ticket.assignee)
                .help(ticket.assignee.isEmpty ? "Unassigned" : ticket.assignee)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 32)
        .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            board.select(key)
            // A double-click edits; read off the click, so a single click
            // isn't held back waiting to see if another follows.
            if NSApp.currentEvent?.clickCount == 2 { board.focusRequest = .summary }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            ForEach(CanvasTicket.Status.allCases, id: \.self) { status in
                Button("Move to \(status.sectionTitle)") { board.setStatus(status, of: key) }
                    .disabled(ticket.status == status)
            }
            Divider()
            Button("Copy Key") {
                board.list.selected = key
                board.copyKey()
            }
            Button("Delete Ticket") { board.delete(key) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selected: Bool { board.list.selected == ticket.key }

    private var fill: Color {
        if board.landed == ticket.key { return Color.accentColor.opacity(0.16) }
        if selected { return board.listFocused ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07) }
        return Color.primary.opacity(hovering ? 0.04 : 0)
    }
}

/// The keys the list takes, along its bottom; brighter while it has the keyboard.
private struct TicketHints: View {
    let focused: Bool

    var body: some View {
        HStack(spacing: 14) {
            hint(["↑", "↓"], "Move")
            hint(["1", "2", "3"], "Set status")
            hint(["S"], "Cycle")
            hint(["↵"], "Edit")
            hint(["C"], "New")
            hint(["⌫"], "Delete")
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        .opacity(focused ? 1 : 0.7)
        .accessibilityHidden(true)
    }

    private func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { TicketKeyCap($0) }
            Text(label).padding(.leading, 1)
        }
        .fixedSize()
    }
}

// MARK: The inspector

/// The selected ticket, to read and change: its summary, properties (each
/// a menu) and description.
private struct TicketInspector: View {
    @ObservedObject var board: TicketBoard
    var focus: FocusState<TicketBoard.Field?>.Binding

    var body: some View {
        Group {
            if let ticket = board.selectedTicket, let key = ticket.key {
                TicketInspectorBody(board: board, ticket: ticket, focus: focus)
                    // Fresh fields for each ticket.
                    .id(key)
            } else {
                VStack(spacing: 6) {
                    Text("No ticket selected.")
                    HStack(spacing: 4) {
                        Text("Press")
                        TicketKeyCap("C")
                        Text("to create one.")
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TicketInspectorBody: View {
    @ObservedObject var board: TicketBoard
    let ticket: CanvasTicket
    var focus: FocusState<TicketBoard.Field?>.Binding
    /// The summary as typed: a blank one isn't kept.
    @State private var summary: String
    @State private var assignee: String

    init(board: TicketBoard, ticket: CanvasTicket, focus: FocusState<TicketBoard.Field?>.Binding) {
        self.board = board
        self.ticket = ticket
        self.focus = focus
        _summary = State(initialValue: ticket.summary)
        _assignee = State(initialValue: ticket.assignee)
    }

    private var key: String { ticket.key ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                TicketKindBadge(kind: ticket.kind)
                Text(key).font(.system(size: 11.5, design: .monospaced))
                Text("·")
                Text(ticket.kind.title)
                Spacer(minLength: 0)
                Button { board.copyKey() } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy Key (⌘C)")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            TextField("Summary", text: $summary, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .focused(focus, equals: .summary)
                .onSubmit { board.focusList?() }
                .onExitCommand { board.focusList?() }
                .onChange(of: summary) { _, typed in
                    let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    board.edit(key) { $0.summary = typed.replacingOccurrences(of: "\n", with: " ") }
                }
                .onChange(of: focus.wrappedValue) { old, _ in
                    // Left blank, it goes back to what it was.
                    if old == .summary { summary = ticket.summary }
                    if old == .assignee { assignee = ticket.assignee }
                }
                // Changed from a menu or by Undo.
                .onChange(of: ticket.summary) { _, new in if focus.wrappedValue != .summary { summary = new } }
                .onChange(of: ticket.assignee) { _, new in if focus.wrappedValue != .assignee { assignee = new } }

            VStack(spacing: 1) {
                propertyRow(.status, "Status", "S") {
                    TicketStatusIcon(status: ticket.status)
                    Text(ticket.status.title)
                }
                propertyRow(.priority, "Priority", "P") {
                    TicketPriorityIcon(priority: ticket.priority)
                    Text(ticket.priority.title)
                }
                propertyRow(.kind, "Type", "T") {
                    TicketKindBadge(kind: ticket.kind)
                    Text(ticket.kind.title)
                }
                assigneeRow
            }
            .padding(.horizontal, -6)

            HStack {
                Text("DESCRIPTION")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(.tertiary)
                Spacer()
                TicketKeyCap("D")
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { Divider() }

            TextEditor(text: Binding(
                get: { board.list.ticket(key)?.details ?? "" },
                set: { details in board.edit(key) { $0.details = details } }))
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused(focus, equals: .details)
                .onExitCommand { board.focusList?() }
                .frame(minHeight: 80)
                .padding(.horizontal, -5)
                .overlay(alignment: .topLeading) {
                    if ticket.details.isEmpty {
                        Text("Add details…")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                }

            Text(focus.wrappedValue == nil ? "↵ edit · double-click a row to rename" : "esc back to the list")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A property's row: click it, or press its key, for its menu.
    private func propertyRow(
        _ property: TicketBoard.Property, _ label: String, _ shortcut: String, @ViewBuilder value: () -> some View
    ) -> some View {
        Button { board.pick(property) } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 78, alignment: .leading)
                HStack(spacing: 7) { value() }
                    .font(.system(size: 12.5))
                Spacer(minLength: 0)
                TicketKeyCap(shortcut).opacity(board.listFocused ? 0.85 : 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(TicketRowButtonStyle())
        .ticketAnchor(.init(property: property))
    }

    /// Type a name, or pick one from the menu.
    private var assigneeRow: some View {
        HStack(spacing: 8) {
            Text("Assignee")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            TicketAvatar(name: assignee, size: 18)
            TextField("Unassigned", text: $assignee)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(focus, equals: .assignee)
                .onSubmit { board.focusList?() }
                .onExitCommand { board.focusList?() }
                .onChange(of: assignee) { _, name in board.edit(key) { $0.assignee = name } }
            Button { board.pick(.assignee) } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Assign to…")
            TicketKeyCap("A").opacity(board.listFocused ? 0.85 : 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 30)
        .ticketAnchor(.init(property: .assignee))
    }
}

/// A row that tints under the pointer and while pressed.
private struct TicketRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TicketRowButtonBody(configuration: configuration)
    }
}

private struct TicketRowButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.08 : hovering ? 0.04 : 0),
                in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
    }
}

// MARK: The new ticket

/// The new ticket's sheet, over the panel: a big summary, details, and a
/// chip for each property. Return in the summary creates it, Escape
/// cancels.
private struct TicketComposer: View {
    @ObservedObject var board: TicketBoard
    var focus: FocusState<TicketBoard.Field?>.Binding

    private var draft: Binding<CanvasTicket> {
        Binding(get: { board.draft ?? CanvasTicket() }, set: { board.draft = $0 })
    }

    private var focused: Bool {
        [.newSummary, .newDetails, .newAssignee].contains(focus.wrappedValue)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.14)
                .contentShape(Rectangle())
                .onTapGesture { board.cancelNew() }
            sheet
                .padding(.top, 24)
                .padding(.horizontal, 16)
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Tickets")
                Text("›").foregroundStyle(.tertiary)
                Text("New Ticket")
                Text("\(board.nextKey) · draft")
                    .font(.system(size: 11.5, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                Spacer(minLength: 0)
                Button { board.cancelNew() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Discard (esc)")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.top, 12)

            TextField("Ticket summary", text: draft.summary)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .semibold))
                .focused(focus, equals: .newSummary)
                .onSubmit { board.create() }
                .onExitCommand { board.cancelNew() }
                .padding(.horizontal, 18)
                .padding(.top, 10)

            TextEditor(text: draft.details)
                .font(.system(size: 13.5))
                .scrollContentBackground(.hidden)
                .focused(focus, equals: .newDetails)
                .onExitCommand { board.cancelNew() }
                .frame(minHeight: 56, maxHeight: 120)
                .overlay(alignment: .topLeading) {
                    if draft.wrappedValue.details.isEmpty {
                        Text("Add details…")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, 4)

            if board.needsSummary {
                Text("Add a summary to create the ticket.")
                    .font(.system(size: 12))
                    .foregroundStyle(CanvasTicket.Kind.bug.color)
                    .padding(.horizontal, 18)
            }

            HStack(spacing: 6) {
                chip(.kind) {
                    TicketKindBadge(kind: draft.wrappedValue.kind, size: 14)
                    Text(draft.wrappedValue.kind.title)
                }
                chip(.priority) {
                    TicketPriorityIcon(priority: draft.wrappedValue.priority)
                    Text(draft.wrappedValue.priority.title)
                }
                chip(.status) {
                    TicketStatusIcon(status: draft.wrappedValue.status, size: 13)
                    Text(draft.wrappedValue.status.title)
                }
                assigneeChip
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)

            HStack(spacing: 12) {
                Toggle("Create more", isOn: $board.createMore)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Spacer(minLength: 0)
                Button { board.create() } label: {
                    HStack(spacing: 6) {
                        Text("Create Ticket")
                        Text("⌘↵").opacity(0.7)
                    }
                }
                .buttonStyle(.borderedProminent)
                // Only while the sheet has the keyboard, so ⌘↵ in a terminal stays the terminal's.
                .keyboardShortcut(focused ? KeyboardShortcut(.return, modifiers: .command) : nil)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .top) { Divider() }
        }
        .frame(maxWidth: 560)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
    }

    private func chip(_ property: TicketBoard.Property, @ViewBuilder label: () -> some View) -> some View {
        Button { board.pick(property, new: true) } label: {
            HStack(spacing: 6) { label() }
                .font(.system(size: 12, weight: .medium))
                .padding(.leading, 7)
                .padding(.trailing, 9)
                .frame(height: 26)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(TicketRowButtonStyle())
        .ticketAnchor(.init(property: property, new: true))
    }

    /// Type a name, or pick one from the menu.
    private var assigneeChip: some View {
        HStack(spacing: 6) {
            TicketAvatar(name: draft.wrappedValue.assignee, size: 16)
            TextField("Assignee", text: draft.assignee)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .focused(focus, equals: .newAssignee)
                .onSubmit { board.create() }
                .onExitCommand { board.cancelNew() }
                .frame(width: 96)
            Button { board.pick(.assignee, new: true) } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Assign to…")
        }
        .padding(.leading, 7)
        .padding(.trailing, 9)
        .frame(height: 26)
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
        .ticketAnchor(.init(property: .assignee, new: true))
    }
}
#endif
