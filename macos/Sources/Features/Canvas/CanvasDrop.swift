#if os(macOS)
import AppKit
import SwiftUI

/// A terminal window dragged by its title bar and held overlapping the
/// canvas for `holdSeconds` moves onto the canvas; a window whose drag
/// starts overlapping it must come onto it first (Arrival), so nudging one
/// there leaves it be. While it overlaps the canvas, the canvas lights up with a ring
/// counting down and "Merging…" over it, and the dragged window goes
/// see-through, the same ring over it too; once the ring runs out the window warps in (CanvasAbsorb)
/// and becomes a card, tabs and all. Dragging it off the canvas or letting
/// go first leaves it a window. The window server moves the window, so the
/// drag is followed by watching the window and the mouse button.
@MainActor
final class CanvasDrop: NSObject {
    static let shared = CanvasDrop()

    /// How see-through the dragged window is over the canvas.
    static let hoverAlpha: CGFloat = 0.7
    /// How long a window is held overlapping the canvas before it merges in.
    static let holdSeconds: TimeInterval = 3

    private var watching = false
    private weak var dragging: TerminalController?
    private var timer: Timer?
    /// The countdown over the canvas and over the dragged window.
    private var wells: [NSPanel] = []
    /// When the dragged window came to overlap the canvas; nil while it doesn't.
    private var heldSince: Date?
    /// Whether the drag has come onto the canvas, so overlapping it counts.
    private var arrival = Arrival()

    /// Whether a window's drag has brought it onto the canvas from outside:
    /// the window has been clear of the canvas, or the pointer, on its title
    /// bar, has come onto the canvas from off it. The second is for a window
    /// that can't easily get clear, as one just dragged off as a card
    /// (CanvasUnmerge), which opens half over the canvas.
    struct Arrival {
        private(set) var arrived = false
        private var pointerWasOff = false

        mutating func update(overlapping: Bool, pointerOn: Bool) {
            if !overlapping || (pointerOn && pointerWasOff) { arrived = true }
            if !pointerOn { pointerWasOff = true }
        }
    }

    /// Starts noticing terminal windows being dragged. Once, with the canvas.
    func start() {
        guard !watching else { return }
        watching = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillMove(_:)), name: NSWindow.willMoveNotification, object: nil)
    }

    @objc private func windowWillMove(_ notification: Notification) {
        guard let controller = (notification.object as? NSWindow)?.windowController as? TerminalController else { return }
        dragStarted(controller)
    }

    /// Where the dragged window `window` overlaps the canvas `canvas`, in
    /// screen coordinates; nil where it doesn't.
    nonisolated static func overlap(_ window: CGRect, _ canvas: CGRect) -> CGRect? {
        let overlap = window.intersection(canvas)
        return overlap.isEmpty ? nil : overlap
    }

    /// How many of the label's three dots show `elapsed` seconds into a
    /// countdown: one more every `dotSeconds`, then none again.
    nonisolated static func dots(after elapsed: TimeInterval) -> Int {
        Int(max(0, elapsed) / dotSeconds) % 4
    }

    static let dotSeconds: TimeInterval = 0.3

    /// Whether a hold since `since` (a window overlapping the canvas, or a
    /// card dragged off it) has lasted `holdSeconds` at `now`.
    nonisolated static func held(since: Date?, now: Date) -> Bool {
        guard let since else { return false }
        return now.timeIntervalSince(since) >= holdSeconds
    }

    private func dragStarted(_ controller: TerminalController) {
        // Only a drag (the button down), with the canvas showing.
        guard timer == nil, NSEvent.pressedMouseButtons & 1 != 0, LosttyChannel.current.hasCanvas,
              let canvas = CanvasController.shared?.window, canvas.isVisible, !canvas.isMiniaturized,
              controller.window?.styleMask.contains(.fullScreen) == false else { return }
        dragging = controller
        arrival = Arrival()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { CanvasDrop.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let controller = dragging, let window = controller.window,
              let canvasController = CanvasController.shared, let canvas = canvasController.window else {
            return stop()
        }
        // Let go: it stays a window.
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return stop() }
        let overlap = Self.overlap(window.frame, canvas.frame)
        arrival.update(overlapping: overlap != nil, pointerOn: canvas.frame.contains(NSEvent.mouseLocation))
        hover(overlap != nil && arrival.arrived, canvas: canvas, dragged: window)
        guard let overlap, Self.held(since: heldSince, now: Date()) else { return }
        stop()
        let controllers = (window.tabbedWindows ?? [window]).compactMap { $0.windowController as? TerminalController }
        let ghostty = controller.ghostty
        // Into the pointer if it's over the canvas, else the overlap's middle.
        let point = NSEvent.mouseLocation
        let target = canvas.frame.contains(point) ? point : NSPoint(x: overlap.midX, y: overlap.midY)
        CanvasAbsorb.run(window, into: target) {
            CanvasImport.move(ghostty, controllers, focus: controller) { cards in
                for card in cards {
                    if let view = canvasController.views[card.id] { CanvasAbsorb.emerge(view) }
                }
            }
        }
    }

    private func hover(_ inside: Bool, canvas: NSWindow, dragged: NSWindow) {
        guard inside != (heldSince != nil) else { return }
        heldSince = inside ? Date() : nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            dragged.animator().alphaValue = inside ? Self.hoverAlpha : 1
        }
        hideWells()
        if inside { wells = [canvas, dragged].map { Self.countdown(over: $0.frame, on: $0, label: "Merging") } }
    }

    private func hideWells() {
        Self.hide(wells)
        wells = []
    }

    /// The countdown to a merge or an unmerge over `frame` (in screen
    /// coordinates) on `window`, moving with it.
    static func countdown(over frame: CGRect, on window: NSWindow, label: String) -> NSPanel {
        let well = CanvasAbsorb.overlay(frame: frame)
        well.level = window.level
        well.contentView = NSHostingView(rootView: CanvasMergeOverlay(seconds: holdSeconds, label: label))
        window.addChildWindow(well, ordered: .above)
        return well
    }

    static func hide(_ wells: [NSPanel]) {
        for well in wells {
            well.parent?.removeChildWindow(well)
            well.orderOut(nil)
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if heldSince != nil, let window = dragging?.window { window.alphaValue = 1 }
        heldSince = nil
        dragging = nil
        hideWells()
    }
}

/// Over the canvas, and over the dragged window or card, while a merge or
/// an unmerge counts down: the edge lit, and in the middle the + button's
/// lit glass with a ring running down the seconds, and `label` with its
/// dots coming in one by one, over and over.
private struct CanvasMergeOverlay: View {
    let seconds: TimeInterval
    let label: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var left = 1.0
    @State private var start = Date()

    var body: some View {
        let dark = scheme == .dark
        let ink = dark ? Color.white : Color.black
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.cyan.opacity(dark ? 0.08 : 0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.cyan.opacity(0.7), lineWidth: 2)
                        .shadow(color: .cyan.opacity(0.6), radius: 8)
                }
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(ink.opacity(0.18), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: left)
                        .stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
                TimelineView(.periodic(from: start, by: CanvasDrop.dotSeconds)) { timeline in
                    let dots = reduceMotion ? 3 : CanvasDrop.dots(after: timeline.date.timeIntervalSince(start))
                    // Every dot keeps its place, so the label never shifts.
                    HStack(spacing: 0) {
                        Text(label)
                        ForEach(0..<3, id: \.self) { dot in
                            Text(".").opacity(dot < dots ? 1 : 0)
                        }
                    }
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .modifier(CanvasAddLitGlass(shape: Capsule(), dark: dark, lit: shown, interactive: false,
                                        reduceMotion: reduceMotion, prism: false))
            .scaleEffect(shown || reduceMotion ? 1 : 0.94)
        }
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(CanvasAddButton.light) { shown = true }
            withAnimation(.linear(duration: seconds)) { left = 0 }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
