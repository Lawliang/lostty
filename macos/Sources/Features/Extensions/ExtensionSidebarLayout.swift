#if os(macOS)
import SwiftUI

/// Puts the extensions sidebar beside the terminal content, so it narrows
/// the terminal rather than covering it, and the Claude usage bar below
/// both. An open overlay extension covers the terminal content; an open
/// sidebar extension grows out of the strip over the terminal's edge. The
/// terminal never changes size.
struct ExtensionSidebarLayout<Content: View>: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                content()
                    .overlay {
                        if let ext = model.active, ext.presentation == .overlay {
                            ExtensionContentView(ext: ext, model: model)
                                .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .topTrailing) { NotificationStackView() }
                    .overlay(alignment: .trailing) { sidebarPanel }
                ExtensionSidebarView(model: model)
            }
            ClaudeUsageBar(model: model)
        }
        .animation(.easeOut(duration: 0.18), value: model.active)
    }

    /// The open sidebar extension, flush against the strip.
    @ViewBuilder private var sidebarPanel: some View {
        if let ext = model.active, case .sidebar(let width) = ext.presentation {
            ExtensionContentView(ext: ext, model: model)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: model.chromeColor ?? .windowBackgroundColor))
                .shadow(color: .black.opacity(0.35), radius: 12, x: -4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}
#endif
