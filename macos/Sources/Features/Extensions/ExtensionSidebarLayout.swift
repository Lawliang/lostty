#if os(macOS)
import SwiftUI

/// Puts the extensions sidebar beside the terminal content, so it narrows
/// the terminal rather than covering it, and the Claude usage bar below
/// both. An open extension covers the terminal content only; the sidebar
/// and the bar stay put.
struct ExtensionSidebarLayout<Content: View>: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
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
            ClaudeUsageBar(model: model)
        }
        .animation(.easeOut(duration: 0.18), value: model.active)
    }
}
#endif
