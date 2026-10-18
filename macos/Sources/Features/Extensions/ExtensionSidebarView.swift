#if os(macOS)
import SwiftUI

/// The window's extensions, as a slim row of small iOS-style icons along
/// the bottom, right above the usage bar and the color of the title bar.
/// Clicking an icon opens its app; clicking it again closes it.
struct ExtensionSidebarView: View {
    static let height: CGFloat = 34
    static let iconSize: CGFloat = 24

    @ObservedObject var model: ExtensionSidebarModel
    @ObservedObject private var skins = SkinsRuntime.shared.manager

    var body: some View {
        HStack(spacing: 10) {
            ForEach(model.available) { ext in
                Button { model.select(ext) } label: {
                    ExtensionIcon(ext: ext, skin: model.focusedSurfaceID.flatMap { skins.effectiveSkin($0) },
                                  size: Self.iconSize)
                        .overlay(alignment: .topTrailing) {
                            // skins.toml has an error (the last good config stays active).
                            if ext == .skins, skins.configError != nil {
                                Circle().fill(Color.yellow)
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
                                    .offset(x: 2, y: -2)
                            }
                        }
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(ext.title)
                .help(ext.title)
                // Active indicator: only while this extension is open.
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(Color(white: 0.95))
                        .frame(width: model.active == ext ? 14 : 4, height: 2)
                        .opacity(model.active == ext ? 1 : 0)
                        .offset(y: 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: model.chromeColor ?? .windowBackgroundColor))
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: model.active)
    }
}

/// Shared shape for the icons: iOS continuous corners, in proportion to
/// `size` (10pt on a 44pt icon).
private func iconShape(_ size: CGFloat) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: size * 10 / 44, style: .continuous)
}

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
    let size: CGFloat

    func body(content: Content) -> some View {
        let k = size / 44
        content
            .clipShape(iconShape(size))
            .overlay(
                iconShape(size).strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75))
            .shadow(color: .black.opacity(0.45), radius: 1 * k, y: 1 * k)
            .shadow(color: .black.opacity(0.28), radius: 6 * k, y: 4 * k)
    }
}

private struct ExtensionIcon: View {
    let ext: LosttyExtension
    /// The focused pane's skin, shown on the Skins icon.
    let skin: Skin?
    let size: CGFloat

    var body: some View {
        switch ext {
        case .branches:
            BranchesIcon(size: size)
        case .skins:
            SkinsIcon(skin: skin, size: size)
                .frame(width: size, height: size)
                .modifier(IOSIconChrome(size: size))
        }
    }
}

/// A git-branch mark on deep green.
private struct BranchesIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.56, blue: 0.38), Color(red: 0.03, green: 0.22, blue: 0.15)],
                startPoint: .top, endPoint: .bottom)
            BranchGlyph()
                .frame(width: size * 24 / 44, height: size * 24 / 44)
                .shadow(color: Color(red: 0.55, green: 1, blue: 0.75).opacity(0.6), radius: size * 3 / 44)
        }
        .frame(width: size, height: size)
        .modifier(IOSIconChrome(size: size))
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
    let size: CGFloat

    var body: some View {
        let background = skin.map { Color(rgb: $0.background) } ?? Color(red: 0.16, green: 0.16, blue: 0.19)
        let accent = skin.map { Color(rgb: $0.accent) } ?? Color(white: 0.85)
        let k = size / 44
        ZStack {
            background
            LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 3 * k, style: .continuous)
                .fill(accent.opacity(0.25))
                .overlay(RoundedRectangle(cornerRadius: 3 * k, style: .continuous).strokeBorder(accent, lineWidth: max(1.5, 2 * k)))
                .frame(width: 16 * k, height: 16 * k)
                .rotationEffect(.degrees(45))
                .shadow(color: accent.opacity(0.6), radius: 4 * k)
        }
    }
}

/// What an open extension shows: over the terminal (Skins) or the whole
/// window below the title bar (Branches).
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
