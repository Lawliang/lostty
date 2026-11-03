#if os(macOS)
import AppKit
import SwiftUI

/// The canvas's zoom while it changes: shown at once, put away a moment
/// after the zoom stops.
@MainActor
final class CanvasZoomMeterState: ObservableObject {
    static let linger: TimeInterval = 1.2

    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var shown = false
    private var hide: DispatchWorkItem?
    /// The first zoom is the canvas opening at its saved view, not you.
    private var primed = false

    func zoomed(to zoom: CGFloat) {
        guard abs(zoom - self.zoom) > 0.0005 else { return }
        self.zoom = zoom
        guard primed else {
            primed = true
            return
        }
        if !shown { withAnimation(.easeOut(duration: 0.15)) { shown = true } }
        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeIn(duration: 0.3)) { self?.shown = false }
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.linger, execute: work)
    }

    /// 0 at the farthest out, 1 at the closest in.
    static func fraction(_ zoom: CGFloat) -> CGFloat {
        (CanvasZoom.clamped(zoom) - CanvasZoom.minimum) / (CanvasZoom.maximum - CanvasZoom.minimum)
    }

    static func label(_ zoom: CGFloat) -> String {
        "\(Int((zoom * 100).rounded()))%"
    }
}

/// At the canvas's top right while you zoom: a glass capsule with a bar
/// that fills from 25% to 200%, a mark at 100%, and the zoom in percent.
/// At 100% the cards are drawn point for point, as the reskin mockup is.
struct CanvasZoomMeter: View {
    static let barWidth: CGFloat = 120
    @ObservedObject var state: CanvasZoomMeterState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            bar
            Text(CanvasZoomMeterState.label(state.zoom))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: LosttyWindowStyle.nsColor(LosttyWindowStyle.mockupText)))
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .modifier(CanvasAddLitGlass(shape: Capsule(), dark: true, lit: false,
                                    interactive: false, reduceMotion: reduceMotion, prism: false))
        .padding(16)
        .opacity(state.shown ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zoom \(CanvasZoomMeterState.label(state.zoom))")
    }

    private var bar: some View {
        let width = Self.barWidth
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.14))
            Capsule()
                .fill(LinearGradient(colors: [Self.pink, Self.cyan], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(4, width * CanvasZoomMeterState.fraction(state.zoom)))
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 1.5, height: 10)
                .offset(x: width * CanvasZoomMeterState.fraction(1) - 0.75)
        }
        .frame(width: width, height: 4)
    }

    private static let pink = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0xD9 / 255)
    private static let cyan = Color(red: 0x7A / 255, green: 0xF0 / 255, blue: 0xFF / 255)
}
#endif
