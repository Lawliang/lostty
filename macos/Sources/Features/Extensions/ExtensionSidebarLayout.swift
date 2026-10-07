#if os(macOS)
import SwiftUI

/// Puts the extensions sidebar beside the terminal content, so it narrows
/// the terminal rather than covering it. An open extension covers the
/// terminal content only; the sidebar stays put.
struct ExtensionSidebarLayout<Content: View>: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
                .overlay {
                    if let ext = model.active {
                        ExtensionContentView(ext: ext, model: model)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .topTrailing) { NotificationStackView() }
            ExtensionSidebarView(model: model)
        }
        .animation(.easeOut(duration: 0.18), value: model.active)
    }
}
#endif
