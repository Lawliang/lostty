#if os(macOS)
import AppKit
import SwiftUI

/// Edits a draft skin that previews live; Apply makes it the pane's override.
struct SkinPopoverView: View {
    let surfaceID: UUID
    @ObservedObject var manager: SkinManager
    @State private var draft: Skin?
    @State private var committed = false

    private static let presets: [RGB] = [
        "#12222b", "#10262b", "#1f2a1c", "#2a2416", "#2b1a10", "#3a0f14", "#2b1f33", "#1c1c1c",
    ].compactMap(RGB.init(hex:))

    private var base: Skin {
        manager.effectiveSkin(surfaceID) ?? Skin.fallback
    }

    private var current: Skin {
        draft ?? base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(manager.sourceLabel(surfaceID)).font(.headline)
            if let error = manager.configError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let textureError = manager.textureError {
                Text(textureError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !manager.config.skins.isEmpty {
                section("Skins") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(manager.config.skins.values.sorted { $0.name < $1.name }, id: \.name) { skin in
                            Button {
                                preview(skin)
                            } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(Color(rgb: skin.background)).frame(width: 10, height: 10)
                                    Text(skin.name).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }

            section("Color") {
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.self) { color in
                        Button {
                            edit { $0.background = color }
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(rgb: color))
                                .frame(width: 20, height: 20)
                                .overlay(RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(current.background == color ? Color.accentColor : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    ColorPicker("", selection: colorBinding, supportsOpacity: false).labelsHidden()
                }
            }

            section("Texture") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                    ForEach(textureOptions, id: \.label) { option in
                        Button {
                            edit { skin in
                                skin.texture = option.texture
                                skin.accent = option.accent ?? Skin.defaultAccent(for: skin.background)
                            }
                        } label: {
                            thumbnail(option)
                        }
                        .buttonStyle(.plain)
                        .help(option.label)
                    }
                }
            }

            section("Texture opacity") {
                Slider(value: opacityBinding, in: 0...0.5)
            }

            HStack {
                Button("Reset to project") {
                    committed = true
                    draft = nil
                    manager.reset(surfaceID)
                }
                Spacer()
                Button("Apply") {
                    committed = true
                    if let draft { manager.setOverride(surfaceID, draft) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft == nil)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onDisappear {
            if !committed { manager.setPreview(surfaceID, nil) }
        }
    }

    // MARK: Draft editing

    private func preview(_ skin: Skin) {
        committed = false
        draft = skin
        manager.setPreview(surfaceID, skin)
    }

    private func edit(_ change: (inout Skin) -> Void) {
        var skin = current
        skin.name = "custom"
        change(&skin)
        preview(skin)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(rgb: current.background) },
            set: { newValue in
                guard let c = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                // Ghostty Skins: some color spaces (e.g. wide-gamut Display
                // P3 swatches) round-trip through sRGB with components
                // slightly outside 0...1, which would otherwise overflow
                // the UInt8 conversion below.
                func clamped255(_ component: CGFloat) -> UInt8 {
                    UInt8((min(max(component, 0), 1) * 255).rounded())
                }
                let rgb = RGB(
                    r: clamped255(c.redComponent),
                    g: clamped255(c.greenComponent),
                    b: clamped255(c.blueComponent))
                edit { skin in
                    skin.background = rgb
                    if case .builtin = skin.texture { skin.accent = Skin.defaultAccent(for: rgb) }
                }
            })
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { current.textureOpacity }, set: { value in edit { $0.textureOpacity = value } })
    }

    // MARK: Textures

    private struct TextureOption {
        let label: String
        let texture: SkinTexture
        let accent: RGB?
    }

    private var textureOptions: [TextureOption] {
        var options = [TextureOption(label: "None", texture: .none, accent: nil)]
        options += BuiltinTexture.allCases.map { TextureOption(label: $0.rawValue, texture: .builtin($0), accent: nil) }
        for skin in manager.config.skins.values.sorted(by: { $0.name < $1.name }) {
            if case .logo = skin.texture {
                options.append(TextureOption(label: "\(skin.name) logo", texture: skin.texture, accent: skin.accent))
            }
        }
        return options
    }

    private func sampleSkin(for option: TextureOption) -> Skin {
        var skin = current
        skin.texture = option.texture
        skin.accent = option.accent ?? Skin.defaultAccent(for: current.background)
        return skin
    }

    @ViewBuilder
    private func thumbnail(_ option: TextureOption) -> some View {
        let selected = current.texture == option.texture
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color(rgb: current.background))
            if option.texture != .none {
                // Ghostty Skins: use the side-effect-free, in-memory lookup
                // here — this runs during a view update (so it must not
                // mutate `@Published textureError`), and re-renders on every
                // color/texture change, so it must not write to disk either.
                if let image = manager.thumbnailImage(for: sampleSkin(for: option)) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill().opacity(0.8)
                }
            } else {
                Image(systemName: "nosign").foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
#endif
