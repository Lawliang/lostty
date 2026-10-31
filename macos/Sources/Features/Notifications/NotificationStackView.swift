#if os(macOS)
import AppKit
import SwiftUI

/// The top-right stack of notification bubbles over the terminal area, in
/// the frontmost window only. Newest on top; past `shown` bubbles the rest
/// fold into a deck that opens on a click.
struct NotificationStackView: View {
    @ObservedObject var center: LosttyNotifications = .shared
    @State private var window: NSWindow?

    static let shown = 3

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if isFront {
                if center.expanded { header }
                ForEach(visible) { item in
                    NotificationBubble(item: item, center: center)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
                if folded > 0 { deck }
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
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.items.map(\.id))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.expanded)
    }

    private var isFront: Bool { window.map { center.front == ObjectIdentifier($0) } ?? false }

    private var visible: [LosttyNotification] {
        center.expanded ? center.items : Array(center.items.prefix(Self.shown))
    }

    private var folded: Int { center.expanded ? 0 : max(0, center.items.count - Self.shown) }

    /// Over the open deck, as iOS has it.
    private var header: some View {
        HStack(spacing: 6) {
            pill("Show Less") { center.expanded = false }
            pill("Clear All") { center.clearAll() }
        }
    }

    /// The folded bubbles' edges under the last one showing, and how many.
    private var deck: some View {
        Button { center.expanded = true } label: {
            VStack(spacing: 4) {
                VStack(spacing: 0) {
                    edge(width: 300, opacity: 1)
                    edge(width: 280, opacity: 0.7)
                }
                Text("\(folded) more")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 320)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, -8)
        .accessibilityLabel("Show \(folded) more notifications")
    }

    private func edge(width: CGFloat, opacity: Double) -> some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
        return Color.clear
            .frame(width: width, height: 8)
            .background(shape.fill(.regularMaterial))
            .opacity(opacity)
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
