#if os(macOS)
import AppKit
import CoreText
import LosttyRemote
import SwiftUI

/// The strip along the bottom of the window, as tall as the title bar and
/// the same color as it and the sidebar, in the terminal's font. At the
/// left, `Context ▓▓░░░░░░░░ 50K   CPU 12%  Mem 340M`: the focused pane's
/// context and what the pane's processes use (`PaneResourceMonitor`). The
/// plan's weekly limit is the canvas dock's Usage app. Context is hidden without
/// a Claude session in the focused pane; CPU and memory show for any pane
/// on Lostty's tmux. At the right, `✳ Opus 5.5`, then the apps button;
/// while it's on, the window's apps (`ExtensionAppsRow`) take the bar's
/// place of the meters and model. A narrow window drops the model first,
/// then shortens the meters (`ClaudeUsageFit`), so every window still
/// shows how it's doing.
struct ClaudeUsageBar: View {
    /// A standard title bar's height, or the Mockup window style's 28pt.
    static var height: CGFloat { LosttyWindowStyle.barHeight }

    @ObservedObject var model: ExtensionSidebarModel
    @ObservedObject private var usage = ClaudeUsageRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @ObservedObject private var monitor = PaneResourceMonitor.shared
    @ObservedObject private var style = WindowStylePreferences.shared
    @State private var width: CGFloat = 0

    private var pane: UUID? { model.focusedSurfaceID }
    private var chrome: NSColor { model.chromeColor ?? .windowBackgroundColor }
    private var ink: Color { chrome.isLight ? .black : .white }
    private var accent: Color {
        pane.flatMap { skins.effectiveSkin($0) }.map { Color(rgb: $0.accent) } ?? ink.opacity(0.8)
    }
    private var hasSession: Bool { pane.map { usage.sessions.contains($0) } ?? false }
    private var resources: PaneResources? { pane.flatMap { monitor.resources[$0] } }

    var body: some View {
        let fit = self.fit
        return ZStack {
            if model.showsApps {
                ExtensionAppsRow(model: model, ink: ink)
                    // Clear of the apps button.
                    .padding(.leading, 12)
                    .padding(.trailing, 44)
                    .transition(.opacity)
            }
            HStack(spacing: 0) {
                if !model.showsApps { meters(fit.style).transition(.opacity) }
                Spacer(minLength: 0)
                if hasSession, !model.showsApps, fit.showsModel {
                    modelLabel
                        .padding(.trailing, ClaudeUsageFit.gap)
                        .transition(.opacity)
                }
                appsButton
            }
            .padding(.leading, ClaudeUsageFit.leading)
            .padding(.trailing, 8)
        }
        .animation(.easeOut(duration: 0.15), value: model.showsApps)
        // Sampled while the bar shows this pane.
        .task(id: pane) {
            guard let pane else { return }
            monitor.watch(pane)
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 3_600_000_000_000) }
            monitor.unwatch(pane)
        }
        .font(ClaudeUsageFont.font(size: 12))
        .lineLimit(1)
        // Never wider than the window: a narrow one truncates the text.
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: Self.height)
        .clipped()
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { width = $0 }
        })
        .background(Color(nsColor: chrome))
    }

    private var modelName: String { pane.flatMap { usage.models[$0] } ?? "" }

    /// The meters' style at the bar's width, and whether the model fits.
    private var fit: (style: ClaudeUsageFit.Style, showsModel: Bool) {
        ClaudeUsageFit.fit(
            width: width, model: modelName.isEmpty ? nil : ClaudeUsageFont.width("✳ " + modelName),
            meters: ClaudeUsageFit.styles.map(metersWidth))
    }

    /// The chips in a style: their text, padding and the space between.
    private func metersWidth(_ style: ClaudeUsageFit.Style) -> CGFloat {
        var texts: [String] = []
        if hasSession { texts.append(contextText(style)) }
        if let resources { texts.append(resourcesText(resources, style)) }
        guard !texts.isEmpty else { return 0 }
        return texts.map { ClaudeUsageFont.width($0) }.reduce(0, +)
            + CGFloat(texts.count) * 16 + CGFloat(texts.count - 1) * 6
    }

    private func meters(_ style: ClaudeUsageFit.Style) -> some View {
        HStack(spacing: 6) {
            if hasSession { chip(contextLine(style)) }
            if let resources { chip(resourcesLine(resources, style)) }
        }
    }

    private func chip(_ content: some View) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }

    /// A 2x2 grid; lit while the bar shows the apps.
    private var appsButton: some View {
        Button { model.toggleApps() } label: {
            Image(systemName: model.showsApps ? "square.grid.2x2.fill" : "square.grid.2x2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink.opacity(model.showsApps ? 0.9 : 0.5))
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(ink.opacity(model.showsApps ? 0.12 : 0)))
                .frame(width: 28, height: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.showsApps ? "Hide apps" : "Show apps")
        .help("Apps")
    }

    /// Picks the pane's model (`ClaudeModelSwitch`); a beep when Claude
    /// is busy or something is typed in its box.
    private var modelLabel: some View {
        Menu {
            ForEach(ClaudeModelSwitch.models(), id: \.id) { choice in
                Button {
                    guard let pane, ClaudeModelSwitch.switchTo(choice, in: pane) else { return NSSound.beep() }
                } label: {
                    if choice.name == modelName { Label(choice.name, systemImage: "checkmark") } else { Text(choice.name) }
                }
            }
        } label: {
            Text("✳ ").foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
                + Text(modelName).foregroundColor(ink.opacity(0.6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch model")
    }

    /// `Context ▓▓░░░░░░░░ 50K`, as `contextLine` draws it in `style`.
    private func contextText(_ style: ClaudeUsageFit.Style) -> String {
        let context = pane.flatMap { usage.contexts[$0] }
        return (style.labels ? "Context " : "") + ClaudeUsageBlocks.string(context?.percent ?? 0, cells: style.cells)
            + (style.cells > 0 ? " " : "") + ClaudeUsageFormat.thousands(context?.used ?? 0)
    }

    /// `CPU 12%  Mem 340M`, as `resourcesLine` draws it in `style`.
    private func resourcesText(_ resources: PaneResources, _ style: ClaudeUsageFit.Style) -> String {
        let cpu = ClaudeUsageFormat.percent(resources.cpu), memory = PaneResourceMath.memory(resources.memory)
        return style.labels ? "CPU \(cpu)  Mem \(memory)" : "\(cpu) \(memory)"
    }

    private func resourcesLine(_ resources: PaneResources, _ style: ClaudeUsageFit.Style) -> some View {
        let cpu = ClaudeUsageFormat.percent(resources.cpu), memory = PaneResourceMath.memory(resources.memory)
        let label = ink.opacity(0.6), value = ink.opacity(0.9)
        return Group {
            if style.labels {
                Text("CPU ").foregroundColor(label) + Text(cpu).foregroundColor(value)
                    + Text("  Mem ").foregroundColor(label) + Text(memory).foregroundColor(value)
            } else {
                Text(cpu + " " + memory).foregroundColor(value)
            }
        }
        .help("CPU and memory used by what runs in this pane")
    }

    /// The number alone takes the meter's color, so it still shows how full.
    private func number(_ percent: Double, _ style: ClaudeUsageFit.Style) -> Color {
        style.cells > 0 ? ink.opacity(0.9) : ClaudeUsageBlocks.fill(for: percent, accent: accent)
    }

    private func contextLine(_ style: ClaudeUsageFit.Style) -> some View {
        let context = pane.flatMap { usage.contexts[$0] }
        let percent = context?.percent ?? 0

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            if style.labels { Text("Context ").foregroundColor(ink.opacity(0.6)) }
            if style.cells > 0 {
                ClaudeUsageBlocks.text(percent, accent: accent, empty: ink.opacity(0.28), cells: style.cells)
            }
            Text((style.cells > 0 ? " " : "") + ClaudeUsageFormat.thousands(context?.used ?? 0))
                .foregroundColor(number(percent, style))
        }
        .help(style.labels ? "" : "Context")
    }
}

/// How the bar fits its width. The meters sit at the left and take the
/// roomiest style that fits clear of the apps button; the model, the least
/// needed, shows between them only beside the roomiest. The narrowest
/// window keeps the meters as `▓▓░░░ 50K  ▓░░░░ 2%  12% 340M`, or just the
/// numbers in the meters' colors.
enum ClaudeUsageFit {
    struct Style: Equatable {
        let labels: Bool
        let cells: Int
    }

    /// Roomiest first.
    static let styles = [
        Style(labels: true, cells: ClaudeUsageBlocks.cells),
        Style(labels: true, cells: 5),
        Style(labels: false, cells: 5),
        Style(labels: false, cells: 0),
    ]
    /// Space kept between the meters and what's beside them.
    static let gap: CGFloat = 12
    /// The meters' inset from the left edge; their chips pad the text to 12.
    static let leading: CGFloat = 4
    /// The apps button and its inset from the right edge.
    static let trailing: CGFloat = 36

    /// The style for a bar `width` wide, given the model's width (nil with
    /// none) and the meters' in each of `styles`, and whether the model shows.
    static func fit(width: CGFloat, model: CGFloat?, meters: [CGFloat]) -> (style: Style, showsModel: Bool) {
        // The meters, a gap, the model and its gap when shown, the apps button.
        func fits(_ meters: CGFloat, beside model: CGFloat) -> Bool {
            leading + meters + gap + model + trailing <= width
        }
        if let model, let roomiest = meters.first, fits(roomiest, beside: model + gap) {
            return (styles[0], true)
        }
        let index = meters.firstIndex { fits($0, beside: 0) } ?? styles.count - 1
        return (styles[index], false)
    }
}

/// A text meter of block characters: `▓` used, `░` free. The used part
/// turns amber past 70% and red past 90% (`UsageMeter`, which the phone
/// draws too).
enum ClaudeUsageBlocks {
    static let cells = UsageMeter.cells

    /// Used cells for `percent`: any use shows at least one.
    static func filled(_ percent: Double, cells: Int = cells) -> Int {
        UsageMeter.filled(percent, cells: cells)
    }

    static func fill(for percent: Double, accent: Color) -> Color {
        switch UsageMeter.level(percent) {
        case .critical: Color(red: 0.95, green: 0.33, blue: 0.30)
        case .high: Color(red: 0.96, green: 0.68, blue: 0.25)
        case .normal: accent
        }
    }

    static func text(_ percent: Double, accent: Color, empty: Color, cells: Int = cells) -> Text {
        let used = filled(percent, cells: cells)
        return Text(String(repeating: "▓", count: used)).foregroundColor(fill(for: percent, accent: accent))
            + Text(String(repeating: "░", count: cells - used)).foregroundColor(empty)
    }

    /// The meter's characters, uncolored.
    static func string(_ percent: Double, cells: Int = cells) -> String {
        let used = filled(percent, cells: cells)
        return String(repeating: "▓", count: used) + String(repeating: "░", count: cells - used)
    }
}

/// The terminal's default font (JetBrains Mono, bundled from Ghostty's
/// embedded copy), registered for the app on first use; SF Mono if that
/// fails.
enum ClaudeUsageFont {
    private static let name: String? = {
        guard let url = Bundle.main.url(forResource: "JetBrainsMonoNoNF-Regular", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else { return nil }
        if NSFont(name: name, size: 12) == nil {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: name, size: 12) == nil ? nil : name
    }()

    static func font(size: CGFloat) -> Font {
        name.map { .custom($0, size: size) } ?? .system(size: size, design: .monospaced)
    }

    /// Widths measured so far: the bar measures every style's text each
    /// time any pane's usage changes, and the texts mostly repeat.
    private static let widths: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 512
        return cache
    }()

    /// How wide `text` is in the font, for fitting the bar.
    static func width(_ text: String, size: CGFloat = 12) -> CGFloat {
        let key = "\(size) \(text)" as NSString
        if let width = widths.object(forKey: key) { return CGFloat(width.doubleValue) }
        let font = name.flatMap { NSFont(name: $0, size: size) } ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        widths.setObject(NSNumber(value: Double(width)), forKey: key)
        return width
    }
}

/// The Usage app's popover: the weekly limit, when it resets, and how much
/// of it Claude Code and Lostty used.
struct ClaudeUsageDetails: View {
    @ObservedObject var usage: ClaudeUsageRuntime
    let accent: Color
    @ObservedObject var breakdown: UsageBreakdownRuntime = .shared

    var body: some View {
        let percent = usage.percent(.weekly) ?? 0
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(ClaudeUsageMetric.weekly.title)
                Spacer(minLength: 10)
                (ClaudeUsageBlocks.text(percent, accent: accent, empty: Color.primary.opacity(0.25))
                    + Text(" " + ClaudeUsageFormat.percent(percent)))
                    .fixedSize()
            }
            Text(usage.sevenDay?.resetsAt.map { ClaudeUsageFormat.reset($0, now: usage.now()) } ?? " ")
                .font(ClaudeUsageFont.font(size: 10))
                .foregroundStyle(.secondary)
            if let line = breakdown.line(.weekly, usage: usage) {
                Text(line)
                    .font(ClaudeUsageFont.font(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .font(ClaudeUsageFont.font(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(width: 320)
        .onAppear { breakdown.refresh() }
    }
}

extension NSColor {
    /// Relative luminance above the midpoint: dark ink reads better on it.
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent > 0.6
    }
}
#endif
