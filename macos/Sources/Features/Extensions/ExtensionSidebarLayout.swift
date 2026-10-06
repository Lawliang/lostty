#if os(macOS)
import SwiftUI

/// Puts the extensions sidebar beside the terminal content, so showing it
/// narrows the terminal rather than covering it. An open extension covers
/// the terminal content only; the sidebar stays put.
struct ExtensionSidebarLayout<Content: View>: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
                .overlay {
                    if let ext = model.active {
                        ExtensionContentView(ext: ext)
                            .transition(.opacity)
                    }
                }
            if model.isShown {
                ExtensionSidebarView(model: model)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: model.isShown)
        .animation(.easeOut(duration: 0.18), value: model.active)
    }
}
#endif
