#if os(macOS)
import SwiftUI

/// "Ready for response": shown over a pane whose Claude finished (or asks
/// for permission) while you were elsewhere. Clicks pass through, so
/// clicking the pane focuses it, which dismisses the overlay.
struct ClaudeReadyOverlay: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = ClaudeRuntime.shared

    var body: some View {
        if runtime.awaiting.contains(surfaceID) {
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.55)
                    Text("Ready\nfor\nresponse")
                        .font(.system(size: Self.fontSize(for: geo.size), weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 8)
                        .minimumScaleFactor(0.3)
                        .padding(24)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Big, but always fits: about a sixth of the shorter side.
    static func fontSize(for size: CGSize) -> CGFloat {
        min(96, max(18, min(size.width, size.height) / 6))
    }
}
#endif
