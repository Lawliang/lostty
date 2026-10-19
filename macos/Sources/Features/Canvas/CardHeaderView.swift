#if os(macOS)
import AppKit
import SwiftUI

/// A card's title bar, drawn as a Mac window's: close, minimize and zoom
/// buttons, the title, and the project pill and agent state. Dragging it
/// moves the card; double-clicking zooms to the card at 100%; its menu
/// moves the card to a window or closes it.
final class CardHeaderView: NSView {
    private let card: CardController
    private weak var canvas: CanvasController?
    private let content: PassthroughHostingView<CardHeaderContent>
    let buttons: CardWindowButtons
    private var start: (point: CGPoint, origin: CGPoint)?

    init(card: CardController, canvas: CanvasController) {
        self.card = card
        self.canvas = canvas
        content = PassthroughHostingView(rootView: CardHeaderContent(card: card))
        buttons = CardWindowButtons { [weak card, weak canvas] button in
            guard let card, let canvas else { return }
            switch button {
            case .close: card.closeCard()
            case .minimize: canvas.zoomToFit()
            case .zoom: canvas.zoom(to: card)
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
        layer?.backgroundColor = (card.sidebar.chromeColor ?? .windowBackgroundColor).cgColor
    }

    override func layout() {
        super.layout()
        content.frame = bounds
        let size = buttons.intrinsicContentSize
        buttons.frame = NSRect(x: 12, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func mouseDown(with event: NSEvent) {
        canvas?.focus(card)
        if event.clickCount == 2 {
            canvas?.zoom(to: card)
            return
        }
        guard let point = documentPoint(event), let frame = canvas?.model.card(card.id)?.frame else { return }
        start = (point, frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let start, let point = documentPoint(event),
              var frame = canvas.model.card(card.id)?.frame else { return }
        frame.origin = CGPoint(x: start.origin.x + point.x - start.point.x, y: start.origin.y + point.y - start.point.y)
        canvas.setFrame(frame, of: card)
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        canvas?.cardFrameDidSettle()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Move to Window", action: #selector(moveToWindow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Card", action: #selector(closeCard), keyEquivalent: "").target = self
        return menu
    }

    @objc private func closeCard() {
        card.closeCard()
    }

    @objc private func moveToWindow() {
        canvas?.moveToWindow(card)
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint? {
        enclosingScrollView?.documentView?.convert(event.locationInWindow, from: nil)
    }
}

/// A Mac window's red, yellow and green buttons, for a card: colored on the
/// focused card and gray on the others, as on inactive windows, with their
/// symbols while the pointer is over them. Red closes the card, yellow
/// zooms out to every card, green zooms to the card at 100%. AppKit, so
/// they take clicks however far the canvas is zoomed.
final class CardWindowButtons: NSView {
    enum Button: CaseIterable {
        case close, minimize, zoom
    }

    static let diameter: CGFloat = 12
    static let spacing: CGFloat = 8
    static var width: CGFloat {
        let count = CGFloat(Button.allCases.count)
        return count * diameter + (count - 1) * spacing
    }

    var isActive = true {
        didSet { if isActive != oldValue { needsDisplay = true } }
    }
    private var hovering = false {
        didSet { if hovering != oldValue { needsDisplay = true } }
    }
    private let action: (Button) -> Void
    private var pressed: Button?

    init(action: @escaping (Button) -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: Self.diameter)
    }

    private func rect(_ button: Button) -> NSRect {
        let index = CGFloat(Button.allCases.firstIndex(of: button) ?? 0)
        return NSRect(x: index * (Self.diameter + Self.spacing), y: 0, width: Self.diameter, height: Self.diameter)
    }

    private func button(at point: NSPoint) -> Button? {
        Button.allCases.first { rect($0).insetBy(dx: -Self.spacing / 2, dy: -4).contains(point) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        for button in Button.allCases {
            let circle = NSBezierPath(ovalIn: rect(button).insetBy(dx: 0.25, dy: 0.25))
            let (fill, stroke) = colors(button, dark: dark)
            fill.setFill()
            circle.fill()
            stroke.setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            if hovering, isActive { drawSymbol(button) }
        }
    }

    private func colors(_ button: Button, dark: Bool) -> (NSColor, NSColor) {
        guard isActive || hovering else {
            return dark
                ? (NSColor(white: 0.36, alpha: 1), NSColor(white: 0.30, alpha: 1))
                : (NSColor(white: 0.86, alpha: 1), NSColor(white: 0.78, alpha: 1))
        }
        switch button {
        case .close: return (NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1), NSColor(srgbRed: 0.878, green: 0.267, blue: 0.243, alpha: 1))
        case .minimize: return (NSColor(srgbRed: 0.996, green: 0.737, blue: 0.180, alpha: 1), NSColor(srgbRed: 0.871, green: 0.631, blue: 0.137, alpha: 1))
        case .zoom: return (NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1), NSColor(srgbRed: 0.102, green: 0.671, blue: 0.161, alpha: 1))
        }
    }

    private func drawSymbol(_ button: Button) {
        let name = switch button {
        case .close: "xmark"
        case .minimize: "minus"
        case .zoom: "plus"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
            .applying(.init(paletteColors: [NSColor(white: 0, alpha: 0.55)]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let r = rect(button)
        image.draw(in: NSRect(x: r.midX - image.size.width / 2, y: r.midY - image.size.height / 2,
                              width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds.insetBy(dx: -4, dy: -4),
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return button(at: local) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        pressed = button(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let pressed, button(at: convert(event.locationInWindow, from: nil)) == pressed else { return }
        action(pressed)
    }
}

/// What a card's title bar shows, laid out as a Lostty window's: after the
/// buttons, the focused pane's folder icon and the card's title; at the
/// right, the focused pane's project pill (its repo and branch, hidden
/// outside a repo). Dimmed with the card while a pane waits on you.
struct CardHeaderContent: View {
    /// Clear of the close, minimize and zoom buttons.
    static let titleInset: CGFloat = 12 + CardWindowButtons.width + 14

    @ObservedObject var card: CardController
    @ObservedObject private var sidebar: ExtensionSidebarModel
    @ObservedObject private var claude = ClaudeRuntime.shared

    init(card: CardController) {
        self.card = card
        sidebar = card.sidebar
    }

    private var focusedPane: Ghostty.SurfaceView? {
        sidebar.focusedSurfaceID.flatMap { id in card.surfaceTree.first { $0.id == id } }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let pane = focusedPane { CardFolderIcon(pane: pane) }
            Text(card.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            ProjectPill(model: card.sidebar)
        }
        .padding(.leading, Self.titleInset)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            // The same dim as the panes' Ready for Response below it.
            if ClaudeReadyOverlay.waiting(in: card.surfaceTree.map(\.id), awaiting: claude.awaiting) != nil {
                Color.black.opacity(0.45)
            }
        }
    }
}

/// The folder a pane is in, as a window's title bar shows it (its proxy
/// icon): the folder's own Finder icon.
private struct CardFolderIcon: View {
    @ObservedObject var pane: Ghostty.SurfaceView

    var body: some View {
        if let pwd = pane.pwd, !pwd.isEmpty {
            Image(nsImage: NSWorkspace.shared.icon(forFile: pwd))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .help(pwd)
        }
    }
}
#endif
