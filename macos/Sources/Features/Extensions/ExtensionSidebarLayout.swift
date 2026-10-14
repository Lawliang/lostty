#if os(macOS)
import SwiftUI

/// Where the notification stack sits beside the sidebar chrome.
enum NotificationPlacement {
    /// How far notifications sit from the terminal's right edge: clear of an
    /// open sidebar app, and of the strip while it slides over the terminal.
    static func trailingInset(active: LosttyExtension?, autoHide: Bool, stripVisible: Bool) -> CGFloat {
        var inset: CGFloat = 0
        if let active, case .sidebar(let width) = active.presentation { inset += width }
        if autoHide, stripVisible { inset += ExtensionSidebarView.width }
        return inset
    }
}

/// Puts the extensions sidebar beside the terminal content, so it narrows
/// the terminal rather than covering it, the axolotl in the terminal's
/// bottom-right corner, and the Claude usage bar below both. An open overlay extension covers the terminal content; an open
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
                    // Over the terminal's corner, under any open extension;
                    // clicks and selection pass through to the terminal.
                    .overlay(alignment: .bottomTrailing) {
                        SidebarMascot(surfaceID: model.focusedSurfaceID)
                            .padding(.trailing, 14)
                            .padding(.bottom, 10)
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        if let ext = model.active, ext.presentation == .overlay {
                            ExtensionContentView(ext: ext, model: model)
                                .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .trailing) { trailingChrome }
                    // Above the chrome and just left of it, so an open panel
                    // never hides a notification.
                    .overlay(alignment: .topTrailing) {
                        NotificationStackView()
                            .padding(.trailing, NotificationPlacement.trailingInset(
                                active: model.active, autoHide: preferences.autoHide,
                                stripVisible: autoHide.isVisible))
                    }
                if !preferences.autoHide {
                    ExtensionSidebarView(model: model)
                }
            }
            ClaudeUsageBar(model: model)
        }
        .animation(.easeOut(duration: 0.18), value: model.active)
        .animation(.easeOut(duration: 0.18), value: autoHide.isVisible)
        .onAppear { autoHide.appChanged(open: model.active != nil) }
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
