#if os(macOS)
import AppKit
import SwiftUI

/// A card's header: its project pill and agent state, and a close button.
/// Dragging it moves the card; double-clicking zooms to the card at 100%;
/// its menu moves the card to a window or closes it.
final class CardHeaderView: NSView {
    private let card: CardController
    private weak var canvas: CanvasController?
    private let content: PassthroughHostingView<CardHeaderContent>
    private let close = NSButton()
    private var start: (point: CGPoint, origin: CGPoint)?

    init(card: CardController, canvas: CanvasController) {
        self.card = card
        self.canvas = canvas
        content = PassthroughHostingView(rootView: CardHeaderContent(card: card))
        super.init(frame: .zero)
        wantsLayer = true
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Card")
        close.isBordered = false
        close.imageScaling = .scaleProportionallyDown
        close.target = self
        close.action = #selector(closeCard)
        close.toolTip = "Close Card"
        addSubview(content)
        addSubview(close)
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
        close.frame = NSRect(x: bounds.width - 24, y: 4, width: 16, height: 16)
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

/// What a card's header shows: the focused pane's project pill and the
/// card's agent state, dimmed with the card while a pane waits on you.
struct CardHeaderContent: View {
    @ObservedObject var card: CardController
    @ObservedObject private var claude = ClaudeRuntime.shared
    @ObservedObject private var activity = PaneActivity.shared

    var body: some View {
        // Ready fades after a while without use; look again now and then.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let panes = card.surfaceTree.map(\.id)
            HStack(spacing: 8) {
                ProjectPill(model: card.header)
                if let status = CardStatus.of(
                    panes: panes, awaiting: claude.awaiting, phases: claude.phases,
                    known: activity.known, lastActivity: activity.lastActivity, now: timeline.date) {
                    CardStatusLabel(status: status)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                // The same dim as the panes' Ready for Response below it.
                if ClaudeReadyOverlay.waiting(in: panes, awaiting: claude.awaiting) != nil {
                    Color.black.opacity(0.45)
                }
            }
        }
    }
}

struct CardStatusLabel: View {
    let status: CardStatus
    var size: CGFloat = 11

    var body: some View {
        Text(status.title)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .waiting: .orange
        case .working: .pink
        case .ready: .green
        }
    }
}
#endif
