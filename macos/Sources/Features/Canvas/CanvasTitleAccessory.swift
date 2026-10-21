#if os(macOS)
import SwiftUI

/// At the right of the canvas's title bar: Jump to What Needs You, and the
/// focused card's project pill.
struct CanvasTitleAccessory: View {
    @ObservedObject var sidebar: ExtensionSidebarModel
    let jump: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: jump) {
                Image(systemName: "arrow.down.forward.circle")
            }
            .buttonStyle(.borderless)
            .help("Jump to What Needs You (⌃⌘J)")
            .accessibilityLabel("Jump to What Needs You")
            ProjectPill(model: sidebar)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }
}
#endif
