#if os(macOS)
import AppKit
import SwiftUI

/// A card's title bar, drawn as a Mac window's: close, minimize and zoom
/// buttons, the title and a pencil that renames the card, and the project
/// pill and agent state. Dragging it moves the card (and the rest of the
/// selection with a selected card), and a lone card off the canvas makes it
/// a window again (CanvasUnmerge); double-clicking zooms to the card at
/// 100%; its menu moves the card to a window or closes it.
final class CardHeaderView: NSView {
    private let card: CardController
    private weak var canvas: CanvasController?
    private let content: PassthroughHostingView<CardHeaderContent>
    let buttons: CardWindowButtons
    private let rename: CardRenameButton
    /// The Mockup window style's line along the bottom.
    private let hairline = NSView()
    /// Where a drag started, and where the cards it moves were then.
    private var start: (point: CGPoint, origins: [UUID: CGPoint])?

    init(card: CardController, canvas: CanvasController) {
        self.card = card
        self.canvas = canvas
        let rename = CardRenameButton { [weak card] in card?.promptTabTitle() }
        self.rename = rename
        content = PassthroughHostingView(rootView: CardHeaderContent(card: card) { rename.frame = $0 })
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
        hairline.wantsLayer = true
        addSubview(content)
        addSubview(buttons)
        addSubview(rename)
        addSubview(hairline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let chrome = card.sidebar.chromeColor ?? .windowBackgroundColor
        layer?.backgroundColor = chrome.cgColor
        hairline.isHidden = !LosttyWindowStyle.isMockup
        hairline.layer?.backgroundColor = LosttyWindowStyle.hairline(on: chrome).cgColor
    }

    override func layout() {
        super.layout()
        content.frame = bounds
        hairline.frame = NSRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)
        let size = buttons.intrinsicContentSize
        buttons.frame = NSRect(
            x: CardWindowButtons.inset, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func mouseDown(with event: NSEvent) {
        canvas?.focus(card)
        if event.clickCount == 2 {
            canvas?.zoom(to: card)
            return
        }
        guard let canvas, let point = documentPoint(event) else { return }
        start = (point, canvas.beginMove(card.id))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let start else { return }
        // Off the canvas, a lone card holds still while it counts down.
        guard start.origins.count > 1 || !CanvasUnmerge.shared.dragged(card, on: canvas) else { return }
        guard let point = documentPoint(event) else { return }
        canvas.move(start.origins, by: CGSize(width: point.x - start.point.x, height: point.y - start.point.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        CanvasUnmerge.shared.cancel()
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
/// focused card while the canvas is the active window, and gray otherwise,
/// as on inactive windows, with their symbols while the pointer is over
/// them. Red closes the card, yellow
/// zooms out to every card, green zooms to the card at 100%. AppKit, so
/// they take clicks however far the canvas is zoomed.
final class CardWindowButtons: NSView {
    enum Button: CaseIterable {
        case close, minimize, zoom
    }

    static let diameter: CGFloat = 12
    static let spacing: CGFloat = 8
    /// From the title bar's leading edge: the mockup's 10pt, or 12.
    static var inset: CGFloat { LosttyWindowStyle.isMockup ? 10 : 12 }
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

    /// Gray while the canvas isn't the active window.
    private var lit: Bool { isActive && window?.isKeyWindow == true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyChanged), name: name, object: window)
        }
    }

    @objc private func keyChanged() {
        needsDisplay = true
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
            // The mockup's buttons are flat.
            if !LosttyWindowStyle.isMockup {
                stroke.setStroke()
                circle.lineWidth = 0.5
                circle.stroke()
            }
            if hovering, lit { drawSymbol(button) }
        }
    }

    private func colors(_ button: Button, dark: Bool) -> (NSColor, NSColor) {
        guard lit || hovering else {
            // The mockup's dimmed buttons (#4A4552, #D6D3DC).
            let gray = dark
                ? NSColor(srgbRed: 0.290, green: 0.271, blue: 0.322, alpha: 1)
                : NSColor(srgbRed: 0.839, green: 0.827, blue: 0.863, alpha: 1)
            return (gray, gray)
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
/// buttons, the focused pane's folder icon, the card's title and room for
/// its rename pencil (`pencilMoved` places it); at the
/// right, the focused pane's project pill (its repo and branch, hidden
/// outside a repo). The Mockup window style centers the title.
struct CardHeaderContent: View {
    /// Clear of the close, minimize and zoom buttons.
    static var titleInset: CGFloat { CardWindowButtons.inset + CardWindowButtons.width + 14 }

    @ObservedObject var card: CardController
    @ObservedObject private var sidebar: ExtensionSidebarModel
    @ObservedObject private var style = WindowStylePreferences.shared
    @State private var pillWidth: CGFloat = 0
    let pencilMoved: (CGRect) -> Void

    init(card: CardController, pencilMoved: @escaping (CGRect) -> Void) {
        self.card = card
        sidebar = card.sidebar
        self.pencilMoved = pencilMoved
    }

    private var focusedPane: Ghostty.SurfaceView? {
        sidebar.focusedSurfaceID.flatMap { id in card.surfaceTree.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if style.isMockup {
                // The title centered on the card, clear of the buttons and pill.
                ZStack {
                    title(size: 12, color: mockupTitleColor)
                        .padding(.horizontal, max(Self.titleInset, pillWidth + 16))
                    HStack {
                        Spacer(minLength: 0)
                        ProjectPill(model: card.sidebar)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pillWidth = $0 }
                    }
                    .padding(.trailing, 8)
                }
            } else {
                HStack(spacing: 6) {
                    title(size: 13, color: .primary.opacity(0.8))
                    Spacer(minLength: 8)
                    ProjectPill(model: card.sidebar)
                }
                .padding(.leading, Self.titleInset)
                .padding(.trailing, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.space)
    }

    private var mockupTitleColor: Color {
        let skin = sidebar.focusedSurfaceID.flatMap { SkinsRuntime.shared.manager.effectiveSkin($0) }
        return Color(nsColor: LosttyWindowStyle.titleColor(skin: skin, bar: sidebar.chromeColor ?? .windowBackgroundColor))
    }

    private func title(size: CGFloat, color: Color) -> some View {
        HStack(spacing: 6) {
            if let pane = focusedPane { CardFolderIcon(pane: pane) }
            Text(card.title)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.middle)
            Color.clear
                .frame(width: CardRenameButton.size, height: CardRenameButton.size)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { pencilMoved($0) }
        }
    }

    private static let space = "CardHeaderContent"
}

/// The pencil after a card's title: asks for a new title for the card.
/// AppKit, as the window buttons are, so it takes clicks at any zoom.
final class CardRenameButton: NSView {
    static let size: CGFloat = 18

    private let action: () -> Void
    private var hovering = false {
        didSet { if hovering != oldValue { needsDisplay = true } }
    }

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        toolTip = "Rename"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            .applying(.init(paletteColors: [NSColor.labelColor.withAlphaComponent(hovering ? 1 : 0.65)]))
        guard let image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Rename")?
            .withSymbolConfiguration(config) else { return }
        image.draw(in: NSRect(x: bounds.midX - image.size.width / 2, y: bounds.midY - image.size.height / 2,
                              width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
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
