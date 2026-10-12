#if os(macOS)
import SwiftUI

/// The window's extensions sidebar: an always-on narrow strip on the right
/// edge, the color of the title bar, with an iOS-style icon per extension.
struct ExtensionSidebarView: View {
    static let width: CGFloat = 64

    @ObservedObject var model: ExtensionSidebarModel
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @State private var showingAddNote = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(LosttyExtension.allCases) { ext in
                ZStack(alignment: .leading) {
                    // Active indicator: only while this extension is open.
                    Capsule()
                        .fill(Color(white: 0.95))
                        .frame(width: 3, height: model.active == ext ? 28 : 8)
                        .opacity(model.active == ext ? 1 : 0)
                        .offset(x: -1.5)

                    Button { model.select(ext) } label: {
                        ExtensionIcon(ext: ext, skin: model.focusedSurfaceID.flatMap { skins.effectiveSkin($0) })
                            .overlay(alignment: .topTrailing) {
                                // skins.toml has an error (the last good config stays active).
                                if ext == .skins, skins.configError != nil {
                                    Circle().fill(Color.yellow)
                                        .frame(width: 10, height: 10)
                                        .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
                                        .offset(x: 3, y: -3)
                                }
                            }
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel(ext.title)
                    .frame(width: Self.width)
                }
                .frame(width: Self.width, height: 44)
            }

            Button { showingAddNote.toggle() } label: {
                AddExtensionIcon()
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Add extension")
            .popover(isPresented: $showingAddNote, arrowEdge: .leading) {
                Text("More extensions are on the way.")
                    .font(.system(size: 12))
                    .padding(12)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: model.chromeColor ?? .windowBackgroundColor))
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: model.active)
    }
}

/// Shared shape for sidebar icons: iOS continuous corners.
private let iconShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

/// Presses scale the icon down a touch, like iOS.
private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Modern iOS icon edge: a faint light along the top, a soft drop shadow.
private struct IOSIconChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(iconShape)
            .overlay(
                iconShape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75))
            .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.28), radius: 6, y: 4)
    }
}

private struct ExtensionIcon: View {
    let ext: LosttyExtension
    /// The focused pane's skin, shown on the Skins icon.
    let skin: Skin?

    var body: some View {
        switch ext {
        case .branches:
            BranchesIcon()
        case .skins:
            SkinsIcon(skin: skin)
                .frame(width: 44, height: 44)
                .modifier(IOSIconChrome())
        }
    }
}

/// A git-branch mark on deep green.
private struct BranchesIcon: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.56, blue: 0.38), Color(red: 0.03, green: 0.22, blue: 0.15)],
                startPoint: .top, endPoint: .bottom)
            BranchGlyph()
                .frame(width: 24, height: 24)
                .shadow(color: Color(red: 0.55, green: 1, blue: 0.75).opacity(0.6), radius: 3)
        }
        .frame(width: 44, height: 44)
        .modifier(IOSIconChrome())
    }
}

/// A trunk with a branch forking off it, three commit dots.
private struct BranchGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let line = Color(red: 0.86, green: 1, blue: 0.92)
            var trunk = Path()
            trunk.move(to: p(7, 4))
            trunk.addLine(to: p(7, 20))
            var fork = Path()
            fork.move(to: p(17, 6.5))
            fork.addCurve(to: p(7, 16), control1: p(17, 12), control2: p(9, 11))
            ctx.stroke(trunk, with: .color(line), lineWidth: 2 * s)
            ctx.stroke(fork, with: .color(line), lineWidth: 2 * s)
            for center in [p(7, 4), p(7, 20), p(17, 6.5)] {
                let r = 2.6 * s
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.white))
            }
        }
    }
}

/// The pane's current skin: its background with the accent diamond.
private struct SkinsIcon: View {
    let skin: Skin?

    var body: some View {
        let background = skin.map { Color(rgb: $0.background) } ?? Color(red: 0.16, green: 0.16, blue: 0.19)
        let accent = skin.map { Color(rgb: $0.accent) } ?? Color(white: 0.85)
        ZStack {
            background
            LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent.opacity(0.25))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(accent, lineWidth: 2))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(45))
                .shadow(color: accent.opacity(0.6), radius: 4)
        }
    }
}

private struct AddExtensionIcon: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.07)
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .frame(width: 44, height: 44)
        .clipShape(iconShape)
        .overlay(iconShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// What an open extension shows in the terminal area.
struct ExtensionContentView: View {
    let ext: LosttyExtension
    @ObservedObject var model: ExtensionSidebarModel

    var body: some View {
        switch ext {
        case .branches:
            BranchesPanel(model: model.branches, onClose: model.close)
        case .skins:
            if let id = model.focusedSurfaceID {
                // `.id(id)` starts the picker fresh if the target pane changes.
                SkinPickerView(
                    surfaceID: id, manager: SkinsRuntime.shared.manager,
                    savedColors: SkinsRuntime.shared.savedColors,
                    onClose: { model.select(.skins) })
                    .id(id)
            } else {
                ZStack {
                    Color(red: 0.05, green: 0.04, blue: 0.04)
                    Text("Click a pane, then open Skins.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

#endif
