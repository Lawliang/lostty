#if os(macOS)
import AppKit
import SwiftUI

/// What the canvas's selection draws over the cards, in window points so
/// it's as thin at every zoom: the marquee while it's dragged, and round
/// two or more selected cards a dashed outline with "N selected" on it.
/// Takes no clicks.
final class CanvasSelectionView: NSView {
    weak var document: NSView?
    /// The marquee, in document points.
    var marquee: CGRect? { didSet { needsDisplay = true } }
    /// The selected cards' frames, in document points.
    var selected: [CGRect] = [] {
        didSet {
            needsDisplay = true
            // The bar sits under them.
            superview?.needsLayout = true
        }
    }

    /// Room between the outline and the cards in it.
    nonisolated static let outlineRoom: CGFloat = 8
    /// The selection's color, in both appearances: the light blue of a
    /// browser's focus ring (#99C8FF), as in the drag-select mockup.
    static let color = NSColor(srgbRed: 0.6, green: 0.784, blue: 1, alpha: 1)
    /// The label's text on it (#0B1A33).
    static let ink = NSColor(srgbRed: 0.043, green: 0.102, blue: 0.2, alpha: 1)

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let document else { return }
        let color = Self.color
        if selected.count > 1 {
            let box = convert(selected.reduce(CGRect.null) { $0.union($1) }, from: document)
                .insetBy(dx: -Self.outlineRoom, dy: -Self.outlineRoom)
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
            outline.lineWidth = 1
            outline.setLineDash([4, 3], count: 2, phase: 0)
            color.setStroke()
            outline.stroke()
            drawLabel("\(selected.count) selected", above: box)
        }
        if let marquee {
            let box = convert(marquee, from: document)
            let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            color.withAlphaComponent(0.14).setFill()
            path.fill()
            path.lineWidth = 1
            color.setStroke()
            path.stroke()
        }
    }

    /// The outline's label, a pill in the selection's color over its top left.
    private func drawLabel(_ text: String, above box: CGRect) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: Self.ink,
        ])
        let size = string.size()
        let pill = CGRect(x: box.minX - 1, y: box.minY - 24, width: size.width + 16, height: size.height + 4)
        Self.color.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        string.draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 2))
    }
}

/// The ring round a selected card, just outside its edge, in the
/// selection's color, 1pt on screen at every zoom. A layer of the card's own, so cards in front of
/// it cover it.
final class CanvasSelectionRing {
    static let width: CGFloat = 1
    private let ring = CALayer()

    init(on view: NSView) {
        ring.isHidden = true
        ring.zPosition = 1_000
        ring.cornerCurve = .continuous
        view.layer?.addSublayer(ring)
    }

    func update(selected: Bool, in bounds: CGRect, zoom: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.isHidden = !selected
        let width = Self.width / max(zoom, CanvasZoom.minimum)
        ring.frame = bounds.insetBy(dx: -width, dy: -width)
        ring.borderWidth = width
        ring.cornerRadius = CardView.cornerRadius + width
        ring.borderColor = CanvasSelectionView.color.cgColor
        CATransaction.commit()
    }
}

/// The bar under the selected cards' outline while cards are selected: how
/// many, Zoom to Selection, Re-organize with the layout it uses, Deselect,
/// and the trash.
final class CanvasSelectionBarView: NSHostingView<CanvasSelectionBar> {
    /// Room round the bar for its shadow.
    nonisolated static let shadowRoom: CGFloat = 16
    /// From the selection's outline to the bar, and the least from the
    /// canvas's edges.
    nonisolated static let margin: CGFloat = 12

    /// The bar's frame of `size` (with the room for its shadow) in `bounds`
    /// (y up): centered under `selection`, the selected cards' outline,
    /// kept inside `bounds`.
    nonisolated static func frame(size: CGSize, under selection: CGRect, in bounds: CGRect) -> CGRect {
        let room = shadowRoom
        let top = selection.minY - CanvasSelectionView.outlineRoom - margin
        let x = min(max(selection.midX - size.width / 2, bounds.minX + margin - room), bounds.maxX - margin + room - size.width)
        let y = min(max(top + room - size.height, bounds.minY + margin - room), bounds.maxY - margin + room - size.height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// The bar itself, without the room for its shadow.
    private var live: CGRect {
        bounds.insetBy(dx: Self.shadowRoom, dy: Self.shadowRoom)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        live.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    /// Whether a click at `point` (in the window) is the bar's.
    func covers(_ point: NSPoint) -> Bool {
        !isHiddenOrHasHiddenAncestor && live.contains(convert(point, from: nil))
    }
}

struct CanvasSelectionBar: View {
    var count = 0
    var layout = CanvasModel.Tidy.row
    var zoom: () -> Void = {}
    /// Re-organize.
    var tidy: () -> Void = {}
    /// The layout button: the next layout.
    var nextLayout: () -> Void = {}
    /// Zone from Selection; nil when no zone fits round the cards.
    var makeZone: (() -> Void)?
    var deselect: () -> Void = {}
    /// The trash: closes the selected terminals; nil when none are selected
    /// (only the tickets panel).
    var close: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        HStack(spacing: 4) {
            Text(count == 1 ? "1 window" : "\(count) windows")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .padding(.leading, 10)
                .padding(.trailing, 8)
            separator
            CanvasSelectionButton(action: zoom) { Text("Zoom to Selection") }
            // Re-organize and its layout, as one button.
            HStack(spacing: 0) {
                CanvasSelectionButton(corner: 0, action: tidy) { Text("Re-organize") }
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 26)
                CanvasSelectionButton(corner: 0, action: nextLayout) { CanvasTidyIcon(layout: layout) }
                    .help(layout.help)
                    .accessibilityLabel(layout.help)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            if let makeZone {
                separator
                CanvasSelectionButton(action: makeZone) { Text("Zone from Selection") }
            }
            separator
            CanvasSelectionButton(action: deselect) { Text("Deselect") }
            if let close {
                separator
                CanvasSelectionButton(tint: .red, action: close) { Image(systemName: "trash") }
                    .help("Close Selected Terminals")
                    .accessibilityLabel("Close Selected Terminals")
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: dark ? NSColor(srgbRed: 0.137, green: 0.125, blue: 0.157, alpha: 1) : .white))
                .shadow(color: .black.opacity(dark ? 0.6 : 0.2), radius: 12, y: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(dark ? Color.white.opacity(0.1) : Color.black.opacity(0.16), lineWidth: 0.5))
        .padding(CanvasSelectionBarView.shadowRoom)
        .fixedSize()
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 16)
    }
}

private struct CanvasSelectionButton<Label: View>: View {
    /// The hover highlight's corners; 0 inside a joined button, which
    /// rounds its own.
    var corner: CGFloat = 7
    /// The label and highlight on hover.
    var tint = Color.accentColor
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 12))
                .foregroundStyle(hovering ? tint : Color.primary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(tint.opacity(hovering ? 0.12 : 0), in: RoundedRectangle(cornerRadius: corner))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Re-organize's layout as blocks: three in a row, two by two, or three in a
/// column.
private struct CanvasTidyIcon: View {
    let layout: CanvasModel.Tidy

    var body: some View {
        let block = RoundedRectangle(cornerRadius: 1.5)
        Group {
            switch layout {
            case .row:
                HStack(spacing: 1.5) { ForEach(0..<3, id: \.self) { _ in block.frame(width: 4, height: 12) } }
            case .column:
                VStack(spacing: 1.5) { ForEach(0..<3, id: \.self) { _ in block.frame(width: 12, height: 4) } }
            case .grid:
                VStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: 2) { ForEach(0..<2, id: \.self) { _ in block.frame(width: 6, height: 6) } }
                    }
                }
            }
        }
        .frame(width: 14, height: 14)
    }
}

extension CanvasModel.Tidy {
    /// The layout button's tooltip.
    var help: String {
        switch self {
        case .row: "Re-organize into a row"
        case .grid: "Re-organize into a grid"
        case .column: "Re-organize into a column"
        }
    }
}

// MARK: - Selecting

extension CanvasController {
    /// A drag on the canvas between the cards starts a marquee: it selects
    /// every card it touches, with ⇧ as well as those already selected.
    func marqueeBegan(adding: Bool) {
        guard !drawsZone else { return }
        marqueeBase = adding ? selection : []
        if !adding { selection = [] }
    }

    /// The marquee, in document points, as dragged so far.
    func marqueeMoved(to rect: CGRect) {
        if !drawsZone { selection = (marqueeBase ?? selection).union(model.cards(touching: rect)) }
        surface.selection.marquee = rect
    }

    /// Drawing a zone, the marquee is its frame, in the project that
    /// wholly holds it if one does.
    func marqueeEnded() {
        if drawsZone, let rect = surface.selection.marquee {
            addZone(rect, parent: model.project(holding: rect))
        }
        drawsZone = false
        marqueeBase = nil
        surface.selection.marquee = nil
    }

    /// ⇧-click on a card's title bar: in the selection or out of it.
    func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// ⌘A on the canvas itself.
    func selectAllCards() {
        selection = Set(model.cards.map(\.id))
    }

    /// The selection's look follows it: the cards' rings, the outline and
    /// the bar.
    func selectionDidChange() {
        for entry in model.cards { view(entry.id)?.isSelectedCard = selection.contains(entry.id) }
        updateSelectionOutline()
        updateSelectionBar()
        if let window { updateGroupHover(at: window.mouseLocationOutsideOfEventStream) }
    }

    func updateSelectionBar() {
        surface.selectionBar.rootView = CanvasSelectionBar(
            count: selection.count,
            layout: tidyLayout,
            zoom: { [weak self] in self?.zoomToSelection() },
            tidy: { [weak self] in self?.tidySelection() },
            nextLayout: { [weak self] in
                guard let self else { return }
                tidyLayout = tidyLayout.next
                updateSelectionBar()
            },
            makeZone: model.zoneAround(selection) == nil ? nil : { [weak self] in self?.zoneFromSelection() },
            deselect: { [weak self] in self?.selection = [] },
            close: selectedTerminals.isEmpty ? nil : { [weak self] in self?.closeSelection() })
        surface.selectionBar.isHidden = selection.isEmpty
        surface.needsLayout = true
    }

    /// The outline round the selection, where its cards are now (in
    /// `shown`, while a zone's drag shows them elsewhere).
    func updateSelectionOutline(in shown: CanvasModel? = nil) {
        surface.selection.selected = (shown ?? model).cards.filter { selection.contains($0.id) }.map(\.frame)
    }

    /// A title bar drag on card `id` starts: where it, and the rest of the
    /// selection if it's selected, started out.
    func beginMove(_ id: UUID) -> [UUID: CGPoint] {
        let moving = selection.contains(id) ? selection : [id]
        return Dictionary(uniqueKeysWithValues: model.cards.filter { moving.contains($0.id) }.map { ($0.id, $0.frame.origin) })
    }

    /// The cards that began a move at `origins`, dragged by `delta` since.
    func move(_ origins: [UUID: CGPoint], by delta: CGSize) {
        for (id, origin) in origins {
            guard var frame = model.card(id)?.frame else { continue }
            frame.origin = CGPoint(x: origin.x + delta.width, y: origin.y + delta.height)
            setFrame(frame, of: id)
        }
    }

    /// Every selected card in view.
    func zoomToSelection() {
        guard let rect = model.fitRect(of: selection) else { return }
        zoomToFit(rect)
    }

    /// The selected cards in a row, a grid or a column, as the bar's
    /// layout button shows.
    func tidySelection() {
        for (id, frame) in model.tidied(selection, into: tidyLayout) { setFrame(frame, of: id) }
        cardFrameDidSettle()
    }

    // MARK: - Closing

    /// The selected terminal cards: not the tickets panel.
    var selectedTerminals: [CardController] {
        selection.compactMap { views[$0]?.card }
    }

    /// The trash: asks whether to check the selected terminals' work first.
    /// Yes will ask each one's agent (for now it closes them all, as No
    /// does); No closes them all now, with no more asking; Cancel keeps
    /// them.
    func closeSelection() {
        let cards = selectedTerminals
        guard let window, !cards.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "You are attempting to close \(cards.count == 1 ? "1 terminal" : "\(cards.count) terminals")"
        alert.informativeText = "Would you like to check if the work is completed on all of them?"
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: CanvasCloseCheck.shared.run(cards, window: window)
            case .alertSecondButtonReturn: for card in cards { card.closeCard(confirm: false) }
            default: break
            }
        }
    }
}
#endif
