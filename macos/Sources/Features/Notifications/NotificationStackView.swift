#if os(macOS)
import AppKit
import SwiftUI

/// One stack in the notification column: a canvas zone's notifications,
/// newest first, or one notification on its own.
struct NotificationGroup: Identifiable {
    enum Entry: Identifiable {
        case bubble(LosttyNotification)
        case terminal(TerminalNotice)

        var id: UUID {
            switch self {
            case .bubble(let item): item.id
            case .terminal(let item): item.id
            }
        }

        var zone: UUID? {
            switch self {
            case .bubble(let item): item.zone
            case .terminal(let item): item.zone
            }
        }

        var posted: Date {
            switch self {
            case .bubble(let item): item.posted
            case .terminal(let item): item.posted
            }
        }
    }

    let zone: UUID?
    var entries: [Entry]

    var id: UUID { zone ?? entries[0].id }

    /// A stack for each zone and every other notification on its own, in
    /// the order of their newest.
    static func make(_ bubbles: [LosttyNotification], _ notices: [TerminalNotice]) -> [NotificationGroup] {
        let entries = (bubbles.map(Entry.bubble) + notices.map(Entry.terminal)).sorted { $0.posted > $1.posted }
        var groups: [NotificationGroup] = []
        for entry in entries {
            if let zone = entry.zone, let index = groups.firstIndex(where: { $0.zone == zone }) {
                groups[index].entries.append(entry)
            } else {
                groups.append(NotificationGroup(zone: entry.zone, entries: [entry]))
            }
        }
        return groups
    }
}

/// The top-right column of notifications over the terminal area, in the
/// frontmost window only. A zone's notifications stack: the newest shows,
/// the rest fold behind it until a click opens the stack. The others
/// show on their own.
struct NotificationStackView: View {
    @ObservedObject var center: LosttyNotifications = .shared
    @ObservedObject var notices: TerminalNotices = .shared
    @State private var window: NSWindow?
    /// The zones whose stack is open.
    @State private var open: Set<UUID> = []

    var body: some View {
        let groups = NotificationGroup.make(center.items, notices.items)
        VStack(alignment: .trailing, spacing: 8) {
            if isFront {
                ForEach(groups) { stack($0) }
            }
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
        .background(WindowReader { found in
            window = found
            if found.isKeyWindow || center.front == nil { center.show(in: ObjectIdentifier(found)) }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let window, note.object as? NSWindow === window { center.show(in: ObjectIdentifier(window)) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if let window, note.object as? NSWindow === window { center.windowClosed(ObjectIdentifier(window)) }
        }
        // A stack down to one closes, so the next to come starts folded.
        .onChange(of: groups.map(\.entries.count)) { _, _ in
            open = open.filter { zone in groups.contains { $0.zone == zone && $0.entries.count > 1 } }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: groups.flatMap { $0.entries.map(\.id) })
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: open)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: notices.collapsed)
    }

    private var isFront: Bool { window.map { center.front == ObjectIdentifier($0) } ?? false }

    @ViewBuilder
    private func stack(_ group: NotificationGroup) -> some View {
        if let zone = group.zone, group.entries.count > 1 {
            if open.contains(zone) {
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 6) {
                        zoneName(zone)
                        Spacer(minLength: 0)
                        pill("Show Less") { open.remove(zone) }
                        pill("Clear") { clear(group) }
                    }
                    .frame(width: 320)
                    ForEach(group.entries) { entry($0) }
                }
            } else {
                deck(group, zone)
            }
        } else {
            ForEach(group.entries) { entry($0) }
        }
    }

    @ViewBuilder
    private func entry(_ entry: NotificationGroup.Entry) -> some View {
        switch entry {
        case .bubble(let item):
            NotificationBubble(item: item, center: center)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)))
        case .terminal(let item):
            TerminalNoticeCard(item: item, compact: notices.collapsed.contains(item.id))
                .onTapGesture { notices.open(item) }
                .onHover { notices.setHovering(item.id, $0) }
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    /// The newest, with the folded ones' edges under it (copies of it, so
    /// they take its width and look as it shrinks), and how many.
    private func deck(_ group: NotificationGroup, _ zone: UUID) -> some View {
        let more = group.entries.count - 1
        return VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .top) {
                ForEach([2, 1].filter { $0 <= more }, id: \.self) { depth in
                    let scale = 1 - CGFloat(depth) * 0.05
                    look(group.entries[0])
                        .allowsHitTesting(false)
                        // Only the strip that shows past the one above: the cards
                        // are see-through, and would show its text.
                        .mask(alignment: .bottom) { Rectangle().frame(height: 7 / scale) }
                        .scaleEffect(scale, anchor: .bottom)
                        .offset(y: CGFloat(depth) * 7)
                        .opacity(depth == 1 ? 0.6 : 0.3)
                        .overlay { Color.clear.contentShape(Rectangle()).onTapGesture { open.insert(zone) } }
                        .accessibilityHidden(true)
                }
                entry(group.entries[0])
            }
            .padding(.bottom, CGFloat(min(more, 2)) * 7)
            Button { open.insert(zone) } label: {
                HStack(spacing: 4) {
                    Text("\(more) more from")
                    zoneName(zone)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show \(more) more notifications")
        }
    }

    /// A notification as it looks, for the deck's edges.
    @ViewBuilder
    private func look(_ entry: NotificationGroup.Entry) -> some View {
        switch entry {
        case .bubble(let item): NotificationBubble(item: item, center: center)
        case .terminal(let item): TerminalNoticeCard(item: item, compact: notices.collapsed.contains(item.id))
        }
    }

    /// The zone's name in its color, as its caption on the canvas.
    @ViewBuilder
    private func zoneName(_ id: UUID) -> some View {
        if let zone = CanvasController.shared?.model.zone(id) {
            HStack(spacing: 4) {
                Circle().fill(Color(nsColor: zone.color.tint)).frame(width: 7, height: 7)
                Text(zone.name.isEmpty ? "Zone" : zone.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
        } else {
            Text("Zone").font(.system(size: 11, weight: .semibold))
        }
    }

    private func clear(_ group: NotificationGroup) {
        for entry in group.entries {
            switch entry {
            case .bubble(let item): center.dismiss(item.id)
            case .terminal(let item): notices.dismiss(item.id)
            }
        }
        if let zone = group.zone { open.remove(zone) }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glass(in: Capsule())
    }
}

/// An iOS-style banner: icon, title with its age, two lines of detail
/// (all of it on hover) and up to two buttons. Clicking it goes to what
/// it's about; a swipe to the right, or ✕ on hover, dismisses it.
private struct NotificationBubble: View {
    let item: LosttyNotification
    let center: LosttyNotifications
    @State private var hovering = false
    @State private var offset: CGFloat = 0
    @State private var scrollMonitor: Any?

    private static let dismissDistance: CGFloat = 80
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(hovering ? nil : 1)
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(LosttyNotification.age(of: item.posted, now: context.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(hovering ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if item.actionTitle != nil || item.secondaryTitle != nil {
                    HStack(spacing: 6) {
                        if let actionTitle = item.actionTitle, let action = item.action {
                            Button(actionTitle) { action() }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor))
                        }
                        if let title = item.secondaryTitle, let action = item.secondaryAction {
                            Button(title) { action() }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.12)))
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .contentShape(shape)
        .onTapGesture { open() }
        .glass(in: shape)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        // macOS Notification Center's close button: on hover, at the corner.
        .overlay(alignment: .topLeading) {
            if hovering {
                Button { center.dismiss(item.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .glass(in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: -7, y: -7)
                .help("Dismiss")
                .transition(.opacity)
            }
        }
        .offset(x: offset)
        .opacity(1 - min(Double(offset) / 240, 0.6))
        .gesture(DragGesture(minimumDistance: 6)
            .onChanged { offset = max(0, $0.translation.width) }
            .onEnded { _ in finishSwipe() })
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.15)) { hovering = isHovering }
            center.setHovering(item.id, isHovering)
            watchScroll(isHovering)
        }
        .onAppear { center.markShown(item.id) }
        .onDisappear { watchScroll(false) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Dismiss") { center.dismiss(item.id) }
    }

    private func open() {
        guard let open = item.open else { return }
        open()
        if !item.stays { center.dismiss(item.id) }
    }

    /// A two-finger swipe to the right, over the bubble, slides it away.
    private func watchScroll(_ on: Bool) {
        if on, scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return event }
                if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                    if offset > 0 { finishSwipe() }
                    return event
                }
                // The fingers' direction, whatever the scrolling setting.
                let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
                guard offset > 0 || (fingers > 0 && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)) else {
                    return event
                }
                offset = max(0, offset + fingers)
                return nil
            }
        } else if !on, let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
            if offset > 0 { finishSwipe() }
        }
    }

    private func finishSwipe() {
        if offset > Self.dismissDistance {
            center.dismiss(item.id)
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
        }
    }

    private var symbol: String {
        if item.style == .failure { return "exclamationmark" }
        return switch item.kind {
        case .hooksMissing: "link"
        case .hooks: "checkmark"
        case .handoff: "exclamationmark"
        case .update: "arrow.up"
        case .zoneLeft: "square.dashed"
        case .keptInside: "hand.raised.fill"
        }
    }

    private var tint: Color {
        switch item.style {
        case .attention: Color(red: 0.36, green: 0.36, blue: 0.95)
        case .success: Color(red: 0.2, green: 0.7, blue: 0.4)
        case .failure: Color(red: 0.9, green: 0.36, blue: 0.3)
        case .update: LosttyTheme.accent
        }
    }
}

private extension View {
    /// Liquid Glass on macOS 26, frosted material before it.
    @ViewBuilder
    func glass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(shape.fill(.regularMaterial))
        }
    }
}

/// Hands over the window the view is in, once it has one.
private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Reader(found: found) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Reader: NSView {
        let found: (NSWindow) -> Void

        init(found: @escaping (NSWindow) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
        }
    }
}
#endif
