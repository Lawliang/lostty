#if os(macOS)
import SwiftUI

/// Puts the extensions sidebar beside the terminal content, so it narrows
/// the terminal rather than covering it, and the Claude usage bar below
/// both. An open overlay extension covers the terminal content; an open
/// sidebar extension grows out of the strip over the terminal's edge. With
/// auto-hide on, the terminal takes the full width and the strip slides in
/// over it from the right edge. The terminal never changes size for an
/// app or for the strip showing and hiding.
struct ExtensionSidebarLayout<Content: View>: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ViewBuilder let content: () -> Content
    @ObservedObject private var preferences = SidebarPreferences.shared
    @StateObject private var autoHide = SidebarAutoHideDriver()

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
                    .overlay(alignment: .trailing) { trailingChrome }
                if !preferences.autoHide {
                    ExtensionSidebarView(model: model)
                }
            }
            ClaudeUsageBar(model: model)
        }
        .animation(.easeOut(duration: 0.18), value: model.active)
        .animation(.easeOut(duration: 0.18), value: autoHide.isVisible)
        .onChange(of: model.active) { active in autoHide.appChanged(open: active != nil) }
        .onChange(of: preferences.autoHide) { _ in autoHide.reset(appOpen: model.active != nil) }
    }

    /// Over the terminal's right edge: the open sidebar extension, and with
    /// auto-hide the strip itself plus the hover edge that reveals it.
    @ViewBuilder private var trailingChrome: some View {
        if preferences.autoHide {
            ZStack(alignment: .trailing) {
                HoverEdge { autoHide.pointer(.edge, inside: $0) }
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                HStack(spacing: 0) {
                    sidebarPanel
                    ExtensionSidebarView(model: model)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: -2)
                }
                .onHover { autoHide.pointer(.sidebar, inside: $0) }
                .offset(x: autoHide.isVisible ? 0 : ExtensionSidebarView.width + 16)
            }
        } else {
            sidebarPanel
        }
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
