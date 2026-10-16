#if os(macOS)
import SwiftUI

/// A pane's guard badges, top right: amber while one of its calls waits
/// for you (click to open it), red when its agent's guard hook is missing.
struct GuardBadgeOverlay: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = GuardRuntime.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let r = runtime.pending(for: surfaceID) {
                Button { GuardRequestWindow.show(r.id) } label: {
                    Label("Needs your approval · #\(r.id)", systemImage: "hand.raised.fill")
                }
                .buttonStyle(.plain)
                .badgeStyle(.orange)
            }
            if GuardHealth.showsDisconnected(agent: runtime.agentPanes[surfaceID], disconnected: runtime.disconnected) {
                Label("Guard disconnected", systemImage: "exclamationmark.shield.fill").badgeStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

private extension View {
    func badgeStyle(_ color: Color) -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.9)))
    }
}
#endif
