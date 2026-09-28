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
                SkinPopoverView(surfaceID: id, manager: manager)
            }
        }
        .padding(.leading, 6)
    }
}
#endif
