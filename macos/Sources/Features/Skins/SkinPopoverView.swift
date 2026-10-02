#if os(macOS)
import AppKit
import SwiftUI

/// Lostty's skin picker (spec §7): Presets / Custom, live preview, Equip.
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

    private static let panel = Color(red: 0.09, green: 0.09, blue: 0.14)
    private static let card = Color.white.opacity(0.06)
    /// Solid card and field fills from the "Lostty Skin Picker" design.
    private static let solidCard = Color(red: 31 / 255, green: 31 / 255, blue: 46 / 255)
    private static let field = Color(red: 20 / 255, green: 20 / 255, blue: 32 / 255)
    private static let ink = Color(red: 11 / 255, green: 11 / 255, blue: 18 / 255)

    private var base: Skin { manager.effectiveSkin(surfaceID) ?? Skin.fallback }
    private var current: Skin { draft ?? base }
    private var accent: Color { Color(rgb: current.accent) }
    private var presetBackgrounds: Set<RGB> { Set(SkinPresets.all.map(\.skin.background)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let locked = manager.lockedSkinName(surfaceID) {
                lockedCard(locked)
            } else {
                tabSwitcher
                if tab == .presets { presetGrid } else { customPanel }
                problems
                footer
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Self.panel)
        .environment(\.colorScheme, .dark)
        .onAppear { hex = current.background.hex }
        .onDisappear { if !committed { manager.setPreview(surfaceID, nil) } }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Skins").font(.system(size: 20, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close")
        }
    }

    private var subtitle: String {
        if let locked = manager.lockedSkinName(surfaceID) { return "Locked · \(locked) from skins.toml" }
        let pwd = manager.panes[surfaceID]?.pwd ?? ""
        if pwd.isEmpty { return "This pane" }
        let home = NSHomeDirectory()
        return (pwd == home || pwd.hasPrefix(home + "/"))
            ? "This pane · ~" + pwd.dropFirst(home.count) : "This pane · \(pwd)"
    }

    private func lockedCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(accent)
                Text("Locked to \(name)").font(.system(size: 14, weight: .semibold))
            }
            Text("This folder is mapped in skins.toml, so it always shows its own skin. Edit the [[match]] entry to change it; your picks still apply in other folders.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Reveal skins.toml in Finder") {
                let file = SkinsRuntime.configDir.appendingPathComponent("skins.toml")
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Self.card))
    }

    private var presetGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(manager.library, id: \.skin.name) { entry in
                    presetCard(entry)
                }
            }
        }
        .frame(maxHeight: 360)
    }

    private func presetCard(_ entry: SkinLibrary.Entry) -> some View {
        let skin = entry.skin
        let selected = current.name == skin.name && current.palette == skin.palette
        let equipped = manager.equippedName(surfaceID) == skin.name
        let ring = Color(rgb: skin.accent)
        return Button { preview(skin) } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(Color(rgb: skin.background))
                    if let image = manager.thumbnailImage(for: skin) {
                        Image(decorative: image, scale: 2)
                            .resizable(resizingMode: .tile)
                            .opacity(min(1, skin.textureOpacity * 3))
                    }
                    Text("❯ _")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(ring)
                        .padding(10)
                    if equipped {
                        Text("EQUIPPED")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(8)
                    }
                }
                .frame(height: 64)
                .clipped()
                HStack(spacing: 6) {
                    Text(SkinPresets.title(for: skin)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    rarityPill(entry.rarity)
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
            }
            .background(Self.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? ring : .clear, lineWidth: 2))
            .shadow(color: selected ? ring.opacity(0.45) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .help("skins set \(skin.name)")
    }

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            tabButton("Presets", .presets)
            tabButton("Custom", .custom)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }

    private func tabButton(_ title: String, _ value: Tab) -> some View {
        let on = tab == value
        return Button { tab = value } label: {
            Text(title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Self.ink : Color.white.opacity(0.7))
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(on ? Color.white : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 9))
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
        .background(RoundedRectangle(cornerRadius: 14).fill(Self.solidCard))
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
                Text("Reset to project").font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            Button { equip() } label: {
                Text("Equip").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(onAccent)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(accent))
                    .shadow(color: accent.opacity(0.45), radius: 10)
            }
            .buttonStyle(.plain)
            .disabled(draft == nil)
            .opacity(draft == nil ? 0.5 : 1)
        }
    }

    // MARK: Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6)).kerning(0.5)
    }

    private func rarityPill(_ rarity: SkinRarity) -> some View {
        let style: (String, Color, Color) = switch rarity {
        case .legendary: ("LEGENDARY", Color(red: 1, green: 0.85, blue: 0.3), Color(red: 0.16, green: 0.1, blue: 0))
        case .epic: ("EPIC", Color(red: 0.7, green: 0.42, blue: 1), .white)
        case .rare: ("RARE", Color(red: 0.18, green: 0.7, blue: 1), Color(red: 0, green: 0.07, blue: 0.12))
        case .common: ("COMMON", Color.white.opacity(0.16), .white)
        case .project: ("PROJECT", .white, Color(red: 0.07, green: 0.13, blue: 0.17))
        }
        return Text(style.0)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(style.2)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(style.1))
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
