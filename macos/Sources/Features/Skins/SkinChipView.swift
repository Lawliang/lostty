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
    @State private var flash: String?

    var body: some View {
        let id = model.focusedSurfaceID
        let skin = id.flatMap { manager.effectiveSkin($0) }
        Button {
            showingPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                // Unskinned panes show a plain "skins" label, no swatch.
                if let skin {
                    Circle()
                        .fill(Color(rgb: skin.background))
                        .overlay(Circle().strokeBorder(Color(rgb: skin.accent), lineWidth: 1.5))
                        .frame(width: 11, height: 11)
                }
                if let flash {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    Text("Equipped").font(.system(size: 11, weight: .semibold))
                        .help(flash)
                } else {
                    Text(chipTitle(skin)).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
                if let id, manager.isLocked(id) {
                    Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                }
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
                SkinPopoverView(
                    surfaceID: id, manager: manager, savedColors: SkinsRuntime.shared.savedColors,
                    onEquipped: { name in
                        showingPopover = false
                        flash = name
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { flash = nil }
                    }
                ).id(id)
            }
        }
        .padding(.trailing, 8)
        // Line the pill up with the window title's baseline area.
        .padding(.top, 7)
    }

    private func chipTitle(_ skin: Skin?) -> String {
        guard let skin else { return "skins" }
        return SkinPresets.all.contains { $0.skin.name == skin.name } ? SkinPresets.displayName(skin.name) : skin.name
    }
}
#endif
