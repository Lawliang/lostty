#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// The canvas's + button, at the bottom right over the cards and the same
/// size at every zoom. Clicking it opens a pill of what it can add above
/// it; choosing one, clicking anywhere else or Escape closes it.
final class CanvasAddMenuView: NSView {
    enum Item: CaseIterable {
        case terminal, ticket

        var title: String {
            switch self {
            case .terminal: "New Terminal"
            case .ticket: "New Ticket"
            }
        }

        var symbol: String {
            switch self {
            case .terminal: "terminal"
            case .ticket: "ticket"
            }
        }
    }

    /// The button's diameter; the pill is as wide.
    static let diameter: CGFloat = 44
    /// From the canvas's bottom and right edges to the button's.
    static let margin: CGFloat = 20
    /// Room round the button and pill for their shadows.
    static let shadowRoom: CGFloat = 16
    static let itemSize: CGFloat = 36
    static let pillPadding: CGFloat = 4
    static let pillGap: CGFloat = 10

    static var pillHeight: CGFloat {
        let count = CGFloat(Item.allCases.count)
        return count * itemSize + (count - 1) * pillPadding + 2 * pillPadding
    }

    /// Big enough for the pill open above the button.
    static var size: CGSize {
        CGSize(width: diameter + 2 * shadowRoom, height: pillHeight + pillGap + diameter + 2 * shadowRoom)
    }

    var chose: ((Item) -> Void)?
    private let state = CanvasAddMenuState()
    private lazy var host = NSHostingView(rootView: CanvasAddButton(state: state) { [weak self] item in
        self?.close()
        self?.chose?(item)
    })
    private var monitor: Any?
    private var opened: AnyCancellable?

    init() {
        super.init(frame: .zero)
        addSubview(host)
        opened = state.$isOpen.dropFirst().sink { [weak self] isOpen in self?.watchOutside(isOpen) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        host.frame = bounds
    }

    /// The button, and the pill while it's open (y up): clicks anywhere else
    /// in the view go on to the cards under it.
    private var live: CGRect {
        let inset = bounds.insetBy(dx: Self.shadowRoom, dy: Self.shadowRoom)
        guard !state.isOpen else { return inset }
        return CGRect(x: inset.minX, y: inset.minY, width: Self.diameter, height: Self.diameter)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        live.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    /// Whether a click at `point` (in the window) is the menu's.
    func covers(_ point: NSPoint) -> Bool {
        !isHiddenOrHasHiddenAncestor && live.contains(convert(point, from: nil))
    }

    /// While the pill is open, a click anywhere else or Escape closes it
    /// (the click still lands; Escape goes no further).
    private func watchOutside(_ isOpen: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isOpen else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, event.window === window else { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53 else { return event }
                close()
                return nil
            }
            if !covers(event.locationInWindow) { close() }
            return event
        }
    }

    private func close() {
        withAnimation(CanvasAddButton.spring) { state.isOpen = false }
    }
}

final class CanvasAddMenuState: ObservableObject {
    @Published var isOpen = false
}

/// The + button in the website's magenta, turning to × while the pill of
/// what it adds is open above it.
struct CanvasAddButton: View {
    @ObservedObject var state: CanvasAddMenuState
    let choose: (CanvasAddMenuView.Item) -> Void

    /// The website's `--btn-bg` (website/custom.html).
    private static let magenta = Color(nsColor: NSColor(name: "LosttyCanvasAdd") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0xE5 / 255, green: 0x19 / 255, blue: 0x9C / 255, alpha: 1)
            : NSColor(srgbRed: 0xB3 / 255, green: 0x0F / 255, blue: 0x77 / 255, alpha: 1)
    })

    static let spring = Animation.spring(response: 0.28, dampingFraction: 0.8)

    var body: some View {
        VStack(spacing: CanvasAddMenuView.pillGap) {
            if state.isOpen {
                pill.transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
            Button {
                withAnimation(Self.spring) { state.isOpen.toggle() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(state.isOpen ? 45 : 0))
                    .frame(width: CanvasAddMenuView.diameter, height: CanvasAddMenuView.diameter)
                    .background(Self.magenta, in: Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(state.isOpen ? "Close" : "Add to Canvas")
            .accessibilityLabel(state.isOpen ? "Close" : "Add to Canvas")
        }
        .padding(CanvasAddMenuView.shadowRoom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var pill: some View {
        VStack(spacing: CanvasAddMenuView.pillPadding) {
            ForEach(CanvasAddMenuView.Item.allCases, id: \.self) { item in
                CanvasAddItem(item: item) { choose(item) }
            }
        }
        .padding(CanvasAddMenuView.pillPadding)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

/// One of the pill's icons, lit while the pointer is over it.
private struct CanvasAddItem: View {
    let item: CanvasAddMenuView.Item
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: CanvasAddMenuView.itemSize, height: CanvasAddMenuView.itemSize)
                .background(Color.primary.opacity(hovering ? 0.1 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.title)
        .accessibilityLabel(item.title)
    }
}
#endif
