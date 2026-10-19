#if os(macOS)
import SwiftUI

/// Puts the extensions' icon row and the Claude usage bar below the
/// terminal content, and the axolotl in the terminal's bottom-right corner.
/// The icon row starts tucked away: a handle peeks above the usage bar, and
/// dragging it up (or clicking it) brings the row out. While the handle is
/// dragged the row slides over the terminal; let go, it snaps shown or
/// tucked away, and only then does the terminal give it room (one resize,
/// not one per step). An open overlay extension (Skins) covers the terminal
/// content; an open window extension (Branches) covers everything here, the
/// icon row and usage bar included, until closed. The terminal never
/// changes size for an app.
struct ExtensionSidebarLayout<Content: View>: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ViewBuilder let content: () -> Content

    /// The terminal's height, for the mascot's bubble (at most half).
    @State private var terminalHeight: CGFloat = 0
    /// How far the handle is dragged (negative upward), while it is.
    @State private var dragged: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                content()
                    // Read behind the terminal, so nothing covers it.
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { terminalHeight = geo.size.height }
                            .onChange(of: geo.size.height) { terminalHeight = $0 }
                    })
                    // Over the terminal's corner, under any open extension.
                    // The overlay is only as big as the axolotl, which takes
                    // clicks (its bubble); the rest of the terminal keeps them.
                    .overlay(alignment: .bottomTrailing) {
                        if model.showsMascot {
                            SidebarMascot(surfaceID: model.focusedSurfaceID, bubbleMaxHeight: max(160, terminalHeight / 2))
                                .padding(.trailing, 14)
                                .padding(.bottom, 10)
                        }
                    }
                    .overlay {
                        if let ext = model.active, ext.presentation == .overlay {
                            ExtensionContentView(ext: ext, model: model)
                                .transition(.opacity)
                        }
                    }
                    // Above an open app, so it never hides a notification.
                    .overlay(alignment: .topTrailing) { NotificationStackView() }
                if model.iconRowShown {
                    // Room for the row, which the drawer draws.
                    Color(nsColor: model.chromeColor ?? .windowBackgroundColor)
                        .frame(height: ExtensionSidebarView.height)
                }
            }
            .overlay(alignment: .bottom) { drawer }
            IconRowHandle(model: model, dragged: $dragged)
            ClaudeUsageBar(model: model)
        }
        .overlay {
            if let ext = model.active, ext.presentation == .window {
                ExtensionContentView(ext: ext, model: model)
                    .background(Color(nsColor: model.chromeColor ?? .windowBackgroundColor))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.active)
    }

    /// The icon row, as much of it as shows: sliding up out of the handle
    /// while dragged, all of it once shown. It takes clicks only when all
    /// of it shows.
    private var drawer: some View {
        let height = ExtensionSidebarView.height
        let reveal = IconRowDrawer.reveal(shown: model.iconRowShown, dragged: dragged)
        return ExtensionSidebarView(model: model)
            .offset(y: height - reveal)
            .frame(height: height, alignment: .top)
            .clipped()
            .opacity(reveal > 0 ? 1 : 0)
            .allowsHitTesting(reveal == height)
    }
}

/// The strip above the usage bar with the icon row's handle: drag it up to
/// bring the row out, down to tuck it away, or click it. AppKit, so it
/// takes drags on a zoomed canvas too.
struct IconRowHandle: NSViewRepresentable {
    static let height: CGFloat = 10

    @ObservedObject var model: ExtensionSidebarModel
    @Binding var dragged: CGFloat

    func makeNSView(context: Context) -> IconRowHandleView {
        let view = IconRowHandleView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        return view
    }

    func updateNSView(_ view: IconRowHandleView, context: Context) {
        view.chrome = model.chromeColor ?? .windowBackgroundColor
        let label = model.iconRowShown ? "Hide Apps" : "Show Apps"
        view.toolTip = label
        view.setAccessibilityLabel(label)
        view.onDrag = { dragged = $0 }
        view.onRelease = { dragged, predicted in
            settle(to: dragged.map {
                IconRowDrawer.settle(shown: model.iconRowShown, dragged: $0, predicted: predicted)
            } ?? !model.iconRowShown)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: IconRowHandleView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: Self.height)
    }

    /// Slides the row the rest of the way over the terminal, then gives it
    /// room (or takes it back) in one step, so the terminal resizes once.
    private func settle(to shown: Bool) {
        let duration = 0.18
        let height = ExtensionSidebarView.height
        let target: CGFloat = shown == model.iconRowShown ? 0 : (shown ? -height : height)
        withAnimation(.easeOut(duration: duration)) { dragged = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [model] in
            var plain = Transaction()
            plain.disablesAnimations = true
            withTransaction(plain) {
                model.iconRowShown = shown
                dragged = 0
            }
        }
    }
}

final class IconRowHandleView: NSView {
    var chrome: NSColor = .windowBackgroundColor {
        didSet { needsDisplay = true }
    }
    /// The drag's height so far, negative upward.
    var onDrag: (CGFloat) -> Void = { _ in }
    /// Let go: the drag's height and where a flick would carry it, or nil
    /// for a click.
    var onRelease: (CGFloat?, CGFloat) -> Void = { _, _ in }

    private var start: NSPoint?
    private var last: (y: CGFloat, time: TimeInterval)?
    private var velocity: CGFloat = 0
    private var hovering = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        chrome.setFill()
        bounds.fill()
        let ink = chrome.isLightColor ? NSColor.black : NSColor.white
        ink.withAlphaComponent(hovering || start != nil ? 0.45 : 0.25).setFill()
        let grip = NSRect(x: bounds.midX - 18, y: bounds.midY - 2, width: 36, height: 4)
        NSBezierPath(roundedRect: grip, xRadius: 2, yRadius: 2).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeUpDown.set() }

    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow
        last = (event.locationInWindow.y, event.timestamp)
        velocity = 0
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        // Window points run upward; the drawer's run downward.
        onDrag(start.y - event.locationInWindow.y)
        // Events closer together than a display frame make no speed worth trusting.
        if let last, event.timestamp - last.time > 0.004 {
            velocity = (last.y - event.locationInWindow.y) / CGFloat(event.timestamp - last.time)
        }
        last = (event.locationInWindow.y, event.timestamp)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        needsDisplay = true
        let dragged = start.y - event.locationInWindow.y
        // Barely moved: a click.
        if abs(dragged) < 3 {
            onRelease(nil, 0)
        } else {
            onRelease(dragged, dragged + velocity * 0.15)
        }
    }
}

#endif
