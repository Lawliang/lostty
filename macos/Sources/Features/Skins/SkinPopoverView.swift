#if os(macOS)
import AppKit
import SwiftUI

/// Lostty's skin picker (spec §7), styled as a boon offering: Boons /
/// Custom, live preview, Equip.
struct SkinPopoverView: View {
    let surfaceID: UUID
    @ObservedObject var manager: SkinManager
    @ObservedObject var savedColors: SavedColorsStore
    var onEquipped: (String) -> Void
    var onClose: () -> Void

    private enum Tab: Hashable { case presets, custom }

    @State private var tab: Tab = .presets
    @State private var draft: Skin?
    @State private var committed = false
    @State private var hex = ""

    private static let card = Color(red: 30 / 255, green: 23 / 255, blue: 17 / 255).opacity(0.9)
    /// Solid card and field fills, warmed to sit on the boon panel.
    private static let solidCard = Color(red: 26 / 255, green: 20 / 255, blue: 15 / 255)
    private static let field = Color(red: 14 / 255, green: 11 / 255, blue: 9 / 255)
    private static let ink = Boon.ink

    private var base: Skin { manager.effectiveSkin(surfaceID) ?? Skin.fallback }
    private var current: Skin { draft ?? base }
    private var accent: Color { Color(rgb: current.accent) }
    private var presetBackgrounds: Set<RGB> { Set(SkinPresets.all.map(\.skin.background)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            tabSwitcher
            if tab == .presets { presetGrid } else { customPanel }
            problems
            footer
        }
        .padding(20)
        .frame(width: 440)
        .background(panelBackground)
        .environment(\.colorScheme, .dark)
        .onAppear { hex = current.background.hex }
        .onDisappear { if !committed { manager.setPreview(surfaceID, nil) } }
    }

    // MARK: Sections

    /// Dark ground lit from the top by the previewed skin's accent, the way
    /// a patron's color fills the screen when they offer a boon.
    private var panelBackground: some View {
        ZStack {
            Boon.ground
            RadialGradient(colors: [accent.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 320)
                .animation(.easeOut(duration: 0.35), value: current.accent)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CHOOSE A BOON")
                    .font(Boon.display(20, .black)).kerning(3)
                    .foregroundStyle(Boon.goldFill)
                Text(subtitle).font(.system(size: 12, design: .serif)).italic()
                    .foregroundStyle(Boon.faded).lineLimit(1)
            }
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Boon.gold)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Boon.rowFill))
                    .overlay(Circle().strokeBorder(Boon.bronze, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close")
        }
    }

    private var subtitle: String {
        let pwd = manager.panes[surfaceID]?.pwd ?? ""
        if pwd.isEmpty { return "A patron offers a skin for this pane" }
        let home = NSHomeDirectory()
        return (pwd == home || pwd.hasPrefix(home + "/"))
            ? "A patron offers a skin for ~" + pwd.dropFirst(home.count) : "A patron offers a skin for \(pwd)"
    }

    private var presetGrid: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(manager.library, id: \.skin.name) { entry in
                    boonRow(entry)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .frame(maxHeight: 400)
    }

    private func boonRow(_ entry: SkinLibrary.Entry) -> some View {
        let skin = entry.skin
        let selected = current.name == skin.name && current.palette == skin.palette
        let equipped = manager.equippedName(surfaceID) == skin.name
        let glow = Color(rgb: skin.accent)
        return Button { preview(skin) } label: {
            HStack(spacing: 14) {
                BoonEmblem(skin: skin, rarity: entry.rarity, glyph: entry.glyph,
                           texture: manager.thumbnailImage(for: skin))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(SkinPresets.title(for: skin).uppercased())
                            .font(Boon.display(14)).kerning(1.2).lineLimit(1)
                            .foregroundStyle(selected ? Boon.goldLight : Color(red: 217 / 255, green: 199 / 255, blue: 156 / 255))
                        if let patron = entry.patron {
                            Text(patron.uppercased()).font(Boon.display(9, .semibold)).kerning(1)
                                .foregroundStyle(Boon.faded).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        rarityTag(entry.rarity)
                    }
                    Text(entry.blurb)
                        .font(.system(size: 11.5, design: .serif))
                        .foregroundStyle(Boon.parchment.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        ForEach(Array(gems(skin).enumerated()), id: \.offset) { _, color in
                            Rectangle().fill(Color(rgb: color)).frame(width: 6, height: 6)
                                .rotationEffect(.degrees(45))
                        }
                        Spacer()
                        if equipped {
                            Text("EQUIPPED").font(Boon.display(8.5, .heavy)).kerning(1.2)
                                .foregroundStyle(Boon.gold)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.leading, 16).padding(.trailing, 22).padding(.vertical, 10)
            .background(
                HexBar().fill(selected
                    ? AnyShapeStyle(LinearGradient(colors: [glow.opacity(0.2), Boon.rowFill], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Boon.rowFill)))
            .overlay(HexBar().strokeBorder(selected ? Boon.goldRim : Boon.bronzeRim, lineWidth: selected ? 1.5 : 1))
            .shadow(color: selected ? glow.opacity(0.4) : .clear, radius: 10)
            .contentShape(HexBar())
        }
        .buttonStyle(.plain)
        .help("skins set \(skin.name)")
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    /// The eight normal ANSI colors, or just the ground and accent for a
    /// skin without a palette.
    private func gems(_ skin: Skin) -> [RGB] {
        guard let palette = skin.palette, palette.count >= 8 else { return [skin.background, skin.accent] }
        return Array(palette[1...7]) + [skin.foreground ?? palette[15]]
    }

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            tabButton("Boons", .presets)
            tabButton("Custom", .custom)
        }
        .padding(3)
        .background(HexBar(notch: 12).fill(Boon.rowFill))
        .overlay(HexBar(notch: 12).strokeBorder(Boon.bronze, lineWidth: 1))
    }

    private func tabButton(_ title: String, _ value: Tab) -> some View {
        let on = tab == value
        return Button { tab = value } label: {
            Text(title.uppercased()).font(Boon.display(12)).kerning(2)
                .foregroundStyle(on ? AnyShapeStyle(Self.ink) : AnyShapeStyle(Boon.faded))
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(HexBar(notch: 11).fill(on ? AnyShapeStyle(Boon.goldFill) : AnyShapeStyle(Color.clear)))
                .contentShape(HexBar(notch: 11))
        }
        .buttonStyle(.plain)
    }

    private var customPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("BACKGROUND")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 10), count: 8), alignment: .leading, spacing: 10) {
                    ForEach(SkinPresets.all.map(\.skin.background), id: \.self) { color in swatch(color, removable: false) }
                    ForEach(savedColors.colors.filter { !presetBackgrounds.contains($0) }, id: \.self) { color in swatch(color, removable: true) }
                }
                anyColorRow
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("TEXTURE")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    textureTile(.none, label: "None")
                    ForEach(BuiltinTexture.allCases, id: \.self) { texture in
                        textureTile(.builtin(texture), label: texture.rawValue.capitalized)
                    }
                }
            }
        }
    }

    private var anyColorRow: some View {
        HStack(spacing: 12) {
            // The rainbow circle is the design's; the (nearly invisible) system
            // well laid over it still opens the standard color panel.
            ZStack {
                Circle().fill(AngularGradient(colors: [
                    Color(rgb: RGB(r: 0xff, g: 0x3d, b: 0xf2)), Color(rgb: RGB(r: 0xff, g: 0x7a, b: 0x3d)),
                    Color(rgb: RGB(r: 0xff, g: 0xd8, b: 0x4d)), Color(rgb: RGB(r: 0x2c, g: 0xff, b: 0x9a)),
                    Color(rgb: RGB(r: 0x25, g: 0xc4, b: 0xff)), Color(rgb: RGB(r: 0x9b, g: 0x87, b: 0xff)),
                    Color(rgb: RGB(r: 0xff, g: 0x3d, b: 0xf2)),
                ], center: .center, angle: .degrees(-90)))
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36, height: 36)
                    .scaleEffect(1.6)
                    .opacity(0.011)
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .help("Pick any background color")
            .accessibilityLabel("Pick any background color")

            VStack(alignment: .leading, spacing: 2) {
                Text("Any color").font(.system(size: 13, weight: .semibold))
                Text("Open the full color picker").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Hex").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.55))
            TextField("#rrggbb", text: $hex)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(width: 84, height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(Self.field))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .onChange(of: hex) { new in
                    if let rgb = RGB(hex: new.trimmingCharacters(in: .whitespaces).lowercased()), rgb != current.background {
                        setBackground(rgb)
                    }
                }
                .onSubmit {
                    if let rgb = RGB(hex: hex.trimmingCharacters(in: .whitespaces).lowercased()), rgb != current.background {
                        setBackground(rgb)
                    }
                }

            let saved = savedColors.contains(current.background)
                || SkinPresets.all.contains { $0.skin.background == current.background }
            Button { savedColors.add(current.background) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    Text(saved ? "Saved" : "Save").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(saved ? Color.white.opacity(0.6) : onAccent)
                .padding(.horizontal, 12).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(saved ? Color.white.opacity(0.1) : accent))
            }
            .buttonStyle(.plain)
            .disabled(saved)
            .help("Save this color to the swatches")
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Rectangle().fill(Self.solidCard))
        .overlay(Rectangle().strokeBorder(Boon.bronze, lineWidth: 1))
    }

    private var problems: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = manager.configError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let error = manager.textureError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { reset() } label: {
                Text("RESET TO PROJECT").font(Boon.display(12)).kerning(1.5)
                    .foregroundStyle(Color(red: 205 / 255, green: 187 / 255, blue: 148 / 255))
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(HexBar(notch: 12).fill(Boon.rowFill))
                    .overlay(HexBar(notch: 12).strokeBorder(Boon.bronze, lineWidth: 1))
                    .contentShape(HexBar(notch: 12))
            }
            .buttonStyle(.plain)
            Button { equip() } label: {
                Text("EQUIP").font(Boon.display(14, .black)).kerning(3)
                    .foregroundStyle(Self.ink)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(HexBar(notch: 12).fill(Boon.goldFill))
                    .shadow(color: Boon.gold.opacity(draft == nil ? 0 : 0.45), radius: 10)
                    .contentShape(HexBar(notch: 12))
            }
            .buttonStyle(.plain)
            .disabled(draft == nil)
            .opacity(draft == nil ? 0.5 : 1)
        }
    }

    // MARK: Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(Boon.display(11)).foregroundStyle(Boon.gold).kerning(2)
    }

    private func rarityTag(_ rarity: SkinRarity) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(rarity.color).frame(width: 5, height: 5).rotationEffect(.degrees(45))
            Text(rarity.label).font(Boon.display(9, .heavy)).kerning(1.6).foregroundStyle(rarity.color)
        }
        .fixedSize()
    }

    private func swatch(_ color: RGB, removable: Bool) -> some View {
        Button { setBackground(color) } label: {
            Circle().fill(Color(rgb: color))
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(current.background == color ? accent : .clear, lineWidth: 3))
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(color.hex)
        .overlay(alignment: .topTrailing) {
            if removable {
                Button { savedColors.remove(color) } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(Self.ink)
                        .frame(width: 16, height: 16).background(Circle().fill(.white))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .help("Remove \(color.hex)")
            }
        }
    }

    private func textureTile(_ texture: SkinTexture, label: String) -> some View {
        var sample = current
        sample.texture = texture
        let selected = current.texture == texture
        return Button { edit { skin in
            skin.texture = texture
            skin.recomputeAccentIfNeeded()
        } } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color(rgb: current.background))
                    if texture != .none, let image = manager.thumbnailImage(for: sample) {
                        Image(decorative: image, scale: 2).resizable(resizingMode: .tile).opacity(0.8)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(height: 38)
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            .padding(.top, 6).padding(.horizontal, 4).padding(.bottom, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Self.solidCard))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private var onAccent: Color {
        let a = current.accent
        let luminance = 0.2126 * Double(a.r) + 0.7152 * Double(a.g) + 0.0722 * Double(a.b)
        return luminance > 140 ? Color(red: 0.04, green: 0.04, blue: 0.07) : .white
    }

    private func preview(_ skin: Skin) {
        committed = false
        draft = skin
        hex = skin.background.hex
        manager.setPreview(surfaceID, skin)
    }

    private func edit(_ change: (inout Skin) -> Void) {
        var skin = current
        skin.name = "custom"
        change(&skin)
        preview(skin)
    }

    private func setBackground(_ color: RGB) {
        edit { skin in
            skin.background = color
            skin.recomputeAccentIfNeeded()
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(rgb: current.background) },
            set: { newValue in
                guard let c = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                func byte(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
                setBackground(RGB(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent)))
            })
    }

    private func equip() {
        guard let draft else { return }
        committed = true
        manager.setOverride(surfaceID, draft)
        onEquipped(SkinPresets.title(for: draft))
    }

    private func reset() {
        committed = true
        draft = nil
        manager.reset(surfaceID)
        hex = base.background.hex
    }
}
#endif
