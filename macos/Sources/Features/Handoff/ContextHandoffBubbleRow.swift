#if os(macOS)
import SwiftUI

/// Under the mascot's bubble in a Claude pane (spec §2, §3): what the
/// context handoff is doing, and the button to arm or call it off.
struct ContextHandoffBubbleRow: View {
    let pane: UUID
    @ObservedObject private var coordinator = ContextHandoffCoordinator.shared
    @ObservedObject private var usage = ClaudeUsageRuntime.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = coordinator.line(pane) {
                Text(line)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if coordinator.isArmed(pane) {
                    Button("Don't hand off this conversation") { coordinator.decline(pane) }
                } else {
                    Button("Hand off at next break") {
                        let context = usage.contexts[pane]
                        coordinator.armByButton(pane, used: context?.used ?? 0, size: context?.size ?? 0)
                    }
                }
                Spacer()
                Button("Handoffs Folder") {
                    let url = ContextHandoffStore.standard.handoffs
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: MascotBubble.width, alignment: .leading)
    }
}
#endif
