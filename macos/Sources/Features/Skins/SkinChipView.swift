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
                // Unskinned panes show a plain "skins" label, no swatch.
                if let skin {
                    Rectangle()
                        .fill(Color(rgb: skin.background))
                        .overlay(Rectangle().strokeBorder(Color(rgb: skin.accent), lineWidth: 1.5))
                        .frame(width: 9, height: 9)
                        .rotationEffect(.degrees(45))
                        .frame(width: 13, height: 13)
                }
                Text(chipTitle(skin)).font(.system(size: 11, weight: .medium)).lineLimit(1)
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
                // Ghostty Skins: `.id(id)` recreates the picker when the
                // focused pane changes while it is open, so its `@State`
                // (the current pick) never carries over to another pane.
                SkinPopoverView(
                    surfaceID: id, manager: manager, savedColors: SkinsRuntime.shared.savedColors,
                    onClose: { showingPopover = false }
                ).id(id)
            }
        }
        .padding(.trailing, 8)
        // Line the pill up with the window title's baseline area.
        .padding(.top, 7)
    }

    private func chipTitle(_ skin: Skin?) -> String {
        guard let skin else { return "skins" }
        return SkinPresets.title(for: skin)
    }
}
#endif
