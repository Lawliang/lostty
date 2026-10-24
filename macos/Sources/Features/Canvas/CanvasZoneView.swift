#if os(macOS)
import AppKit
import SwiftUI

/// The canvas's zones, behind every card: the document's first subview,
/// as big as it. Takes clicks only on a zone's label and edges, so the
/// marquee, card clicks and panning work in a zone as anywhere else.
final class CanvasZoneLayer: NSView {
    weak var canvas: CanvasController?
    private var views: [UUID: CanvasZoneView] = [:]

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Draws `zones`, projects under their domains, keeping the view of a
    /// zone that's still there (a drag on it goes on).
    func show(_ zones: [CanvasZone]) {
        guard let canvas else { return }
        let ordered = zones.filter { $0.parent == nil } + zones.filter { $0.parent != nil }
        let kept = Set(zones.map(\.id))
        for (id, view) in views where !kept.contains(id) {
            view.removeFromSuperview()
            views[id] = nil
        }
        let shown = ordered.map { zone in
            let view = views[zone.id] ?? CanvasZoneView(id: zone.id, canvas: canvas)
            views[zone.id] = view
            view.show(zone, zoom: zoom)
            return view
        }
        if subviews != shown { subviews = shown }
    }

    /// The edges as thick on screen as the zoom has changed.
    func updateEdges() {
        for view in views.values { view.updateEdge(zoom: zoom) }
    }

    private var zoom: CGFloat { enclosingScrollView?.magnification ?? 1 }
}

/// One zone: a rounded area with a faint fill of its color and a solid
/// edge, its label inside the top edge, and handles along its edges that
/// resize it.
final class CanvasZoneView: NSView {
    private let label: CanvasZoneLabel
    private var handles: [CardEdgeHandle] = []
    private var isDomain = false

    init(id: UUID, canvas: CanvasController) {
        label = CanvasZoneLabel(id: id, canvas: canvas)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        addSubview(label)
        for edges in CanvasModel.handleEdges {
            let handle = CardEdgeHandle(
                edges: edges,
                frame: { [weak canvas] in canvas?.model.zone(id)?.frame },
                resize: { [weak canvas] frame in canvas?.setZoneFrame(frame, of: id) })
            handles.append(handle)
            addSubview(handle)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    func show(_ zone: CanvasZone, zoom: CGFloat) {
        isDomain = zone.parent != nil
        frame = zone.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = isDomain ? 16 : 22
        layer?.backgroundColor = zone.color.tint.withAlphaComponent(0.06).cgColor
        layer?.borderColor = zone.color.tint.withAlphaComponent(0.5).cgColor
        CATransaction.commit()
        updateEdge(zoom: zoom)
        label.show(zone.name, color: zone.color, isDomain: isDomain)
        needsLayout = true
    }

    /// 2pt on screen for a project, 1.5pt for a domain, at every zoom.
    func updateEdge(zoom: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.borderWidth = (isDomain ? 1.5 : 2) / max(zoom, CanvasZoom.minimum)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let inset = isDomain ? CGPoint(x: 12, y: 10) : CGPoint(x: 14, y: 12)
        let size = label.pillSize
        label.frame = CGRect(
            x: inset.x, y: inset.y, width: min(size.width, max(0, bounds.width - 2 * inset.x)), height: size.height)
        for handle in handles { handle.frame = CanvasModel.handleFrame(for: handle.edges, in: bounds) }
    }
}

/// A zone's name on a pill of its color. Dragging it moves the zone and
/// everything in it; a click opens its settings, a right-click its menu.
final class CanvasZoneLabel: NSView {
    private let id: UUID
    private weak var canvas: CanvasController?
    private var text = NSAttributedString()
    private var padding: CGFloat = 10
    private var height: CGFloat = 26
    /// Where a drag started on the document, and how far the zone has
    /// been allowed to follow it.
    private var drag: (start: CGPoint, allowed: CGSize, moved: Bool)?
    private var settings: NSPopover?

    init(id: UUID, canvas: CanvasController) {
        self.id = id
        self.canvas = canvas
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func show(_ name: String, color: CanvasZone.Color, isDomain: Bool) {
        padding = isDomain ? 8 : 10
        height = isDomain ? 22 : 26
        text = NSAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: isDomain ? 12 : 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        layer?.backgroundColor = color.pill.cgColor
        layer?.cornerRadius = isDomain ? 7 : 8
        needsDisplay = true
        superview?.needsLayout = true
    }

    var pillSize: NSSize {
        NSSize(width: (text.size().width + 2 * padding).rounded(.up), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = text.size()
        text.draw(with: CGRect(
            x: padding, y: (bounds.height - size.height) / 2, width: bounds.width - 2 * padding, height: size.height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let point = documentPoint(event) else { return }
        drag = (point, .zero, false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, var drag, let point = documentPoint(event) else { return }
        let delta = CGSize(width: point.x - drag.start.x, height: point.y - drag.start.y)
        // A click that wobbles isn't a drag.
        let zoom = enclosingScrollView?.magnification ?? 1
        guard drag.moved || hypot(delta.width, delta.height) * zoom >= 3 else { return }
        drag.moved = true
        NSCursor.closedHand.set()
        if canvas.previewZoneMove(id, by: delta) { drag.allowed = delta }
        self.drag = drag
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil
        guard drag.moved else {
            showSettings()
            return
        }
        canvas?.moveZone(id, by: drag.allowed)
        window?.invalidateCursorRects(for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        zoneMenu()
    }

    private func zoneMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [
            ("Zone Settings…", #selector(showSettings)),
            ("Zoom to Zone", #selector(zoomToZone)),
            ("Remove Zone", #selector(removeZone)),
        ] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        return menu
    }

    @objc private func showSettings() {
        guard let canvas, let zone = canvas.model.zone(id) else { return }
        if let settings, settings.isShown {
            settings.close()
            return
        }
        let id = id
        let popover = NSPopover()
        // Not transient: a folder picker opened from it mustn't close it.
        popover.behavior = .semitransient
        let host = NSHostingController(rootView: CanvasZoneSettings(
            zone: zone,
            project: zone.parent.flatMap { canvas.model.zone($0) },
            members: canvas.memberTitles(of: id),
            update: { [weak canvas] change in canvas?.updateZone(id, change) },
            zoomToZone: { [weak self] in self?.zoomToZone() },
            remove: { [weak self] in self?.removeZone() }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        settings = popover
    }

    @objc private func zoomToZone() {
        settings?.close()
        canvas?.zoomToZone(id)
    }

    @objc private func removeZone() {
        settings?.close()
        canvas?.removeZone(id)
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint? {
        enclosingScrollView?.documentView?.convert(event.locationInWindow, from: nil)
    }
}

extension CanvasZone.Color {
    /// The zone's fill and edge, faded.
    var tint: NSColor {
        switch self {
        case .blue: Self.rgb(90, 150, 250)
        case .green: Self.rgb(70, 190, 120)
        case .orange: Self.rgb(232, 150, 70)
        case .purple: Self.rgb(150, 125, 255)
        case .pink: Self.rgb(235, 110, 175)
        case .teal: Self.rgb(45, 190, 192)
        case .yellow: Self.rgb(235, 190, 60)
        case .red: Self.rgb(235, 95, 90)
        }
    }

    /// The label's pill: a shade dark enough for white text.
    var pill: NSColor {
        switch self {
        case .blue: Self.rgb(0x2F, 0x63, 0xC4)
        case .green: Self.rgb(0x23, 0x78, 0x4A)
        case .orange: Self.rgb(0xA6, 0x5A, 0x17)
        case .purple: Self.rgb(0x6B, 0x4F, 0xD8)
        case .pink: Self.rgb(0xA8, 0x36, 0x7A)
        case .teal: Self.rgb(0x1D, 0x7F, 0x81)
        case .yellow: Self.rgb(0x8C, 0x6A, 0x0C)
        case .red: Self.rgb(0xB0, 0x36, 0x32)
        }
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }
}
#endif
