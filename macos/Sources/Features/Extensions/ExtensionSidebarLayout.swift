#if os(macOS)
import SwiftUI

/// Puts the bottom bar (Claude's usage, or the apps) below the terminal
/// content, and under it, while the focused pane's Claude has subagents or
/// shells, their strip (the window grows for it). An open one covers the
/// terminal content, as an open overlay extension (Skins) does;
/// an open window extension (Branches) covers everything here, the bottom
/// bar included, until closed. The terminal never changes size for an app.
struct ExtensionSidebarLayout<Content: View>: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .overlay { PaneTaskOverlay(model: model) }
                .overlay {
                    if let ext = model.active, ext.presentation == .overlay {
                        ExtensionContentView(ext: ext, model: model)
                            .transition(.opacity)
                    }
                }
                // Above an open app, so it never hides a notification.
                .overlay(alignment: .topTrailing) {
                    if model.showsNotifications { NotificationStackView() }
                }
            ClaudeUsageBar(model: model)
            if model.showsTasks { PaneTaskStrip(model: model) }
        }
        .overlay {
            if let ext = model.active, ext.presentation == .window {
                ExtensionContentView(ext: ext, model: model)
                    .background(Color(nsColor: model.chromeColor ?? .windowBackgroundColor))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.active)
        .animation(.easeOut(duration: 0.15), value: model.openTaskID)
    }
}
#endif
