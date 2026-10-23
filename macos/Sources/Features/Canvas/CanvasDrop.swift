#if os(macOS)
import AppKit
import SwiftUI

/// A terminal window dragged by its title bar and held over the canvas for
/// `holdSeconds` moves onto the canvas. While it's over the canvas, the
/// canvas lights up with a ring counting down and "Merging…" over it, and
/// the dragged window goes see-through; once the ring runs out the window
/// warps in (CanvasAbsorb) and becomes a card, tabs and all. Dragging it
/// off the canvas or letting go first leaves it a window. The window
/// server moves the window, so the drag is followed by watching the
/// pointer and the mouse button.
@MainActor
final class CanvasDrop: NSObject {
    static let shared = CanvasDrop()

    /// How see-through the dragged window is over the canvas.
    static let hoverAlpha: CGFloat = 0.7
    /// How long a window is held over the canvas before it merges in.
    static let holdSeconds: TimeInterval = 2

    private var watching = false
    private weak var dragging: TerminalController?
    private var timer: Timer?
    private var well: NSPanel?
    /// When the dragged window came over the canvas; nil while it isn't.
    private var heldSince: Date?

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

    /// Whether a window held over the canvas since `since` merges in at `now`.
    nonisolated static func merges(heldSince since: Date?, now: Date) -> Bool {
        guard let since else { return false }
        return now.timeIntervalSince(since) >= holdSeconds
    }

    private func dragStarted(_ controller: TerminalController) {
        // Only a drag (the button down), with the canvas showing.
        guard timer == nil, NSEvent.pressedMouseButtons & 1 != 0, LosttyChannel.current.hasCanvas,
              let canvas = CanvasController.shared?.window, canvas.isVisible, !canvas.isMiniaturized,
              controller.window?.styleMask.contains(.fullScreen) == false else { return }
        dragging = controller
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
        let point = NSEvent.mouseLocation
        // Over the canvas, and nothing but the dragged window in front of
        // it there.
        let under = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: window.windowNumber)
        let inside = canvas.frame.contains(point) && under == canvas.windowNumber
        hover(inside, canvas: canvas, dragged: window)
        guard Self.merges(heldSince: heldSince, now: Date()) else { return }
        stop()
        let controllers = (window.tabbedWindows ?? [window]).compactMap { $0.windowController as? TerminalController }
        let ghostty = controller.ghostty
        CanvasAbsorb.run(window, into: point) {
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
        if inside {
            showWell(over: canvas)
        } else {
            hideWell()
        }
    }

    /// Over the dragged window too, so the countdown shows through it.
    private func showWell(over canvas: NSWindow) {
        let well = self.well ?? CanvasAbsorb.overlay(frame: canvas.frame)
        well.setFrame(canvas.frame, display: false)
        well.contentView = NSHostingView(rootView: CanvasMergeOverlay(seconds: Self.holdSeconds))
        well.orderFrontRegardless()
        self.well = well
    }

    private func hideWell() {
        well?.orderOut(nil)
        well = nil
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if heldSince != nil, let window = dragging?.window { window.alphaValue = 1 }
        heldSince = nil
        dragging = nil
        hideWell()
    }
}

/// Over the canvas while a window is held there: the canvas's edge lit,
/// and in its middle the + button's lit glass with a ring running down the
/// seconds until the window merges in.
private struct CanvasMergeOverlay: View {
    let seconds: TimeInterval
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var left = 1.0

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
                Text("Merging…")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .modifier(CanvasAddLitGlass(shape: Capsule(), dark: dark, lit: shown, interactive: false,
                                        reduceMotion: reduceMotion))
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
