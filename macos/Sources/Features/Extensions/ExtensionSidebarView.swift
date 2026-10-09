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
        case .skins:
            SkinsIcon(skin: skin)
                .frame(width: 44, height: 44)
                .modifier(IOSIconChrome())
        case .codebaseVisualizer:
            ZStack {
                RadialGradient(
                    colors: [
                        Color(red: 0.23, green: 0.18, blue: 0.61),
                        Color(red: 0.10, green: 0.10, blue: 0.35),
                        Color(red: 0.04, green: 0.04, blue: 0.15),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 30)
                NodeGlyph()
                    .frame(width: 26, height: 26)
                    .shadow(color: Color(red: 0.59, green: 0.67, blue: 1).opacity(0.85), radius: 3)
            }
            .frame(width: 44, height: 44)
            .modifier(IOSIconChrome())
        }
    }
}

/// A small neural cluster: a bright core joined to three colored nodes.
private struct NodeGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 26
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let core = p(13, 13)
            let lineColor = Color(red: 0.56, green: 0.65, blue: 1)
            for end in [p(5, 7), p(21, 8), p(11, 22)] {
                var line = Path()
                line.move(to: core)
                line.addLine(to: end)
                ctx.stroke(line, with: .color(lineColor), lineWidth: 1.2 * s)
            }
            var spur = Path()
            spur.move(to: p(21, 8))
            spur.addLine(to: p(22, 17))
            ctx.stroke(spur, with: .color(lineColor), lineWidth: 1 * s)

            func dot(_ c: CGPoint, _ r: CGFloat, _ color: Color) {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * s, y: c.y - r * s, width: 2 * r * s, height: 2 * r * s)),
                         with: .color(color))
            }
            dot(core, 3.4, Color(red: 0.95, green: 0.95, blue: 1))
            dot(p(5, 7), 2.2, Color(red: 0.66, green: 0.55, blue: 1))
            dot(p(21, 8), 2.2, Color(red: 0.44, green: 0.82, blue: 1))
            dot(p(11, 22), 2.2, Color(red: 1, green: 0.54, blue: 0.85))
            dot(p(22, 17), 1.6, Color(red: 0.44, green: 0.82, blue: 1))
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
        case .codebaseVisualizer:
            // MindControl (the `mindcontrol` branch) replaces this with its panel.
            ZStack {
                RadialGradient(
                    colors: [
                        Color(red: 0.05, green: 0.06, blue: 0.19),
                        Color(red: 0.03, green: 0.03, blue: 0.09),
                        Color(red: 0.01, green: 0.01, blue: 0.035),
                    ],
                    center: .center, startRadius: 0, endRadius: 700)
                VStack(spacing: 8) {
                    NodeGlyph().frame(width: 40, height: 40)
                    Text("Codebase visualizer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("The 3D map arrives with MindControl.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }
}

#endif
