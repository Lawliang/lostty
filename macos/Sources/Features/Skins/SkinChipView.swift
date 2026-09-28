#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Which surface the window's chip describes.
@MainActor
final class SkinChipModel: ObservableObject {
    @Published var focusedSurfaceID: UUID?
}

extension Color {
    init(rgb: RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

/// Title-bar pill showing the focused pane's skin; click to override it.
struct SkinChipView: View {
    @ObservedObject var model: SkinChipModel
    @ObservedObject var manager: SkinManager
    @State private var showingPopover = false

    var body: some View {
        let id = model.focusedSurfaceID
        let skin = id.flatMap { manager.effectiveSkin($0) }
        Button {
            showingPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(skin.map { Color(rgb: $0.background) } ?? Color.secondary.opacity(0.3))
                    .overlay(Circle().strokeBorder(skin.map { Color(rgb: $0.accent) } ?? Color.secondary, lineWidth: 1.5))
                    .frame(width: 11, height: 11)
                Text(skin?.name ?? "default")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let id, manager.panes[id]?.override != nil {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                }
                if manager.configError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(id == nil)
        .help("Pane skin")
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            if let id {
                // Ghostty Skins: `.id(id)` forces SwiftUI to tear down and
                // recreate this view when the focused pane changes while the
                // popover is open (e.g. the pane's process exits, or focus
                // moves via AppleScript). Without it, SkinPopoverView's
                // `@State` (draft, committed) would stick around across the
                // pane change: the old pane's preview would never be
                // cancelled (its `onDisappear` wouldn't fire), and Apply
                // would write the old pane's draft as the new pane's
                // override. Recreating the view makes the old one disappear
                // (cancelling its preview) and starts the new one fresh.
                SkinPopoverView(surfaceID: id, manager: manager).id(id)
            }
        }
        .padding(.leading, 6)
    }
}
#endif
