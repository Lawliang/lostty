#if os(macOS)
import SwiftUI

/// Puts the extensions' icon row and the Claude usage bar below the
/// terminal content, and the axolotl in the terminal's bottom-right corner.
/// An open overlay extension (Skins) covers the terminal content; an open
/// window extension (Branches) covers everything here, the icon row and
/// usage bar included, until closed. The terminal never changes size for
/// an app.
struct ExtensionSidebarLayout<Content: View>: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ViewBuilder let content: () -> Content

    /// The terminal's height, for the mascot's bubble (at most half).
    @State private var terminalHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            content()
                // Read behind the terminal, so nothing covers it.
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { terminalHeight = geo.size.height }
                        .onChange(of: geo.size.height) { terminalHeight = $0 }
                })
                // Over the terminal's corner, under any open extension.
                // The overlay is only as big as the axolotl, which takes
                // clicks (its bubble); the rest of the terminal keeps them.
                .overlay(alignment: .bottomTrailing) {
                    if model.showsMascot {
                        SidebarMascot(surfaceID: model.focusedSurfaceID, bubbleMaxHeight: max(160, terminalHeight / 2))
                            .padding(.trailing, 14)
                            .padding(.bottom, 10)
                    }
                }
                .overlay {
                    if let ext = model.active, ext.presentation == .overlay {
                        ExtensionContentView(ext: ext, model: model)
                            .transition(.opacity)
                    }
                }
                // Above an open app, so it never hides a notification.
                .overlay(alignment: .topTrailing) { NotificationStackView() }
            ExtensionSidebarView(model: model)
            ClaudeUsageBar(model: model)
        }
        .overlay {
            if let ext = model.active, ext.presentation == .window {
                ExtensionContentView(ext: ext, model: model)
                    .background(Color(nsColor: model.chromeColor ?? .windowBackgroundColor))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.active)
    }
}
#endif
