#if os(macOS)
import AppKit
import CoreText
import LosttyRemote
import SwiftUI

/// The strip along the bottom of the window, as tall as the title bar and
/// the same color as it and the sidebar, in the terminal's font. At the
/// left, `Context ▓▓░░░░░░░░ 50K   Session ▓░░░░░░░░░ 2%   CPU 12%  Mem 340M`:
/// the focused pane's context, the tracked plan limit, and what the pane's
/// processes use (`PaneResourceMonitor`). Clicking the limit lists every
/// limit, and picking one tracks it here. In the beta, a line on the
/// context meter marks where the conversation hands off, and clicking the
/// context shows and sets that limit. Context and limit are hidden without
/// a Claude session in the focused pane; CPU and memory show for any pane
/// on Lostty's tmux. At the right, `✳ Opus 5.5`, then the apps button;
/// while it's on, the window's apps (`ExtensionAppsRow`) take the bar's
/// place of the meters and model. A narrow window drops the model first,
/// then shortens the meters (`ClaudeUsageFit`), so every window still
/// shows how it's doing.
struct ClaudeUsageBar: View {
    /// A standard title bar's height.
    static let height: CGFloat = NSWindow.frameRect(forContentRect: .zero, styleMask: [.titled]).height

    @ObservedObject var model: ExtensionSidebarModel
    @ObservedObject private var usage = ClaudeUsageRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @ObservedObject private var handoff = ContextHandoffCoordinator.shared
    @ObservedObject private var handoffSettings = ContextHandoffPreferences.shared
    @ObservedObject private var monitor = PaneResourceMonitor.shared
    @State private var showingDetails = false
    @State private var showingHandoff = false
    @State private var hovered: Part?
    @State private var width: CGFloat = 0

    private enum Part { case context, limit }

    /// The context handoff is the beta's, like the mascot.
    private let handsOff = LosttyChannel.current.showsMascot

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
        let armed = pane.map { handoff.isArmed($0) } ?? false
        var texts: [String] = []
        if hasSession { texts += [contextText(style) + (armed ? "  " : ""), limitText(style)] }
        if let resources { texts.append(resourcesText(resources, style)) }
        guard !texts.isEmpty else { return 0 }
        return texts.map { ClaudeUsageFont.width($0) }.reduce(0, +)
            + CGFloat(texts.count) * 16 + CGFloat(texts.count - 1) * 6
    }

    private func meters(_ style: ClaudeUsageFit.Style) -> some View {
        HStack(spacing: 6) {
            if hasSession { usageChips(style) }
            if let resources { chip(resourcesLine(resources, style), lit: false) }
        }
    }

    @ViewBuilder
    private func usageChips(_ style: ClaudeUsageFit.Style) -> some View {
        if handsOff {
            Button { showingHandoff.toggle() } label: {
                chip(contextLine(style), lit: hovered == .context || showingHandoff)
            }
            .buttonStyle(.plain)
            .onHover { hover(.context, $0) }
            .popover(isPresented: $showingHandoff, arrowEdge: .top) {
                ContextHandoffDetails(settings: handoffSettings, context: pane.flatMap { usage.contexts[$0] },
                                      armed: pane.flatMap { handoff.line($0) })
            }
        } else {
            chip(contextLine(style), lit: false)
        }
        Button { showingDetails.toggle() } label: {
            // Ticks so a limit that resets while nothing reports drops to 0%.
            chip(TimelineView(.everyMinute) { _ in limitLine(style) }, lit: hovered == .limit || showingDetails)
        }
        .buttonStyle(.plain)
        .onHover { hover(.limit, $0) }
        .popover(isPresented: $showingDetails, arrowEdge: .top) {
            TimelineView(.everyMinute) { _ in
                ClaudeUsageDetails(usage: usage, accent: accent) { showingDetails = false }
            }
        }
    }

    /// Moving straight from one part to the other may report the new one
    /// before the old one's exit, so an exit clears only its own part.
    private func hover(_ part: Part, _ inside: Bool) {
        if inside {
            hovered = part
        } else if hovered == part {
            hovered = nil
        }
    }

    private func chip(_ content: some View, lit: Bool) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ink.opacity(lit ? 0.07 : 0)))
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

    private var modelLabel: some View {
        Text("✳ ").foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
            + Text(modelName).foregroundColor(ink.opacity(0.6))
    }

    /// `Context ▓▓░░░░░░░░ 50K`, as `contextLine` draws it in `style`.
    private func contextText(_ style: ClaudeUsageFit.Style) -> String {
        let context = pane.flatMap { usage.contexts[$0] }
        return (style.labels ? "Context " : "") + ClaudeUsageBlocks.string(context?.percent ?? 0, cells: style.cells)
            + (style.cells > 0 ? " " : "") + ClaudeUsageFormat.thousands(context?.used ?? 0)
    }

    /// `Session ▓░░░░░░░░░ 2%`, as `limitLine` draws it in `style`.
    private func limitText(_ style: ClaudeUsageFit.Style) -> String {
        let limit = usage.percent(usage.tracked) ?? 0
        return (style.labels ? usage.tracked.shortTitle + " " : "")
            + ClaudeUsageBlocks.string(limit, cells: style.cells)
            + (style.cells > 0 ? " " : "") + ClaudeUsageFormat.percent(limit)
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
        let armed = pane.map { handoff.isArmed($0) } ?? false

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            if style.labels { Text("Context ").foregroundColor(ink.opacity(0.6)) }
            if style.cells > 0 {
                ClaudeUsageBlocks.text(percent, accent: accent, empty: ink.opacity(0.28), cells: style.cells)
                    .overlay(alignment: .leading) {
                        if let mark = handoffMark(context) {
                            // A line across the meter where the handoff limit falls.
                            GeometryReader { meter in
                                Rectangle()
                                    .fill(ink.opacity(0.85))
                                    .frame(width: 1.5, height: meter.size.height + 4)
                                    .offset(x: meter.size.width * mark - 0.75, y: -2)
                            }
                        }
                    }
            }
            (Text((style.cells > 0 ? " " : "") + ClaudeUsageFormat.thousands(context?.used ?? 0))
                .foregroundColor(number(percent, style))
                + (armed ? Text(" ") + Text(Image(systemName: "arrow.triangle.2.circlepath")).foregroundColor(accent)
                    : Text("")))
        }
        .help(armed ? "Will hand off at the next clean break" : style.labels ? "" : "Context")
    }

    /// Where the handoff limit falls on the context meter, 0...1, while
    /// handoffs are on and the window's size is known.
    private func handoffMark(_ context: ClaudeUsageReport.Context?) -> Double? {
        guard handsOff, handoffSettings.enabled, let context, context.size > 0 else { return nil }
        let limit = ContextHandoffPolicy.limit(setting: handoffSettings.setting, size: context.size)
        return min(1, Double(limit) / Double(context.size))
    }

    private func limitLine(_ style: ClaudeUsageFit.Style) -> some View {
        let metric = usage.tracked
        let limit = usage.percent(metric) ?? 0

        return (Text(style.labels ? metric.shortTitle + " " : "").foregroundColor(ink.opacity(0.6))
            + ClaudeUsageBlocks.text(limit, accent: accent, empty: ink.opacity(0.28), cells: style.cells)
            + Text((style.cells > 0 ? " " : "") + ClaudeUsageFormat.percent(limit)).foregroundColor(number(limit, style)))
            .help(style.labels ? "" : metric.title)
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

    /// How wide `text` is in the font, for fitting the bar.
    static func width(_ text: String, size: CGFloat = 12) -> CGFloat {
        let font = name.flatMap { NSFont(name: $0, size: size) } ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// Every plan limit, each tappable to make it the one the bar tracks.
private struct ClaudeUsageDetails: View {
    @ObservedObject var usage: ClaudeUsageRuntime
    let accent: Color
    @ObservedObject var breakdown: UsageBreakdownRuntime = .shared
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ClaudeUsageMetric.allCases) { metric in
                row(metric)
            }
            if ClaudeUsageMetric.allCases.contains(where: { breakdown.line($0, usage: usage) != nil }) {
                Text(UsageBreakdownRuntime.footnote)
                    .font(ClaudeUsageFont.font(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }
        }
        .font(ClaudeUsageFont.font(size: 12))
        .padding(6)
        .frame(width: 320)
        .onAppear { breakdown.refresh() }
    }

    private func row(_ metric: ClaudeUsageMetric) -> some View {
        let available = metric != .weeklyFable
        let percent = usage.percent(metric) ?? 0
        return Button {
            usage.tracked = metric
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text(metric.title)
                    Spacer(minLength: 10)
                    if available {
                        (ClaudeUsageBlocks.text(percent, accent: accent, empty: Color.primary.opacity(0.25))
                            + Text(" " + ClaudeUsageFormat.percent(percent)))
                            .fixedSize()
                    }
                }
                Text(subtitle(metric))
                    .font(ClaudeUsageFont.font(size: 10))
                    .foregroundStyle(.secondary)
                if let line = breakdown.line(metric, usage: usage) {
                    Text(line)
                        .font(ClaudeUsageFont.font(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(usage.tracked == metric ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.5)
    }

    /// When the limit resets.
    private func subtitle(_ metric: ClaudeUsageMetric) -> String {
        let limit: ClaudeUsageReport.Limit?
        switch metric {
        case .session: limit = usage.fiveHour
        case .weekly: limit = usage.sevenDay
        case .weeklyFable: return "Not available"
        }
        guard let reset = limit?.resetsAt else { return " " }
        return ClaudeUsageFormat.reset(reset, now: usage.now())
    }
}

/// The focused window's context handoff: where it hands off, each limit
/// to pick from (the same setting as Settings → Mascot), and the switch.
private struct ContextHandoffDetails: View {
    @ObservedObject var settings: ContextHandoffPreferences
    let context: ClaudeUsageReport.Context?
    /// What an armed handoff waits for (ContextHandoffCoordinator.line).
    let armed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $settings.enabled) { Text("Hand off long conversations") }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .padding(.horizontal, 10)
                .padding(.top, 7)
            Text(summary)
                .font(ClaudeUsageFont.font(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(ContextHandoffPreferences.limits, id: \.self) { limit in
                row(limit)
            }
        }
        .font(ClaudeUsageFont.font(size: 12))
        .padding(6)
        .frame(width: 320)
    }

    private var summary: String {
        guard settings.enabled else { return "Off: Lostty doesn't hand off long conversations." }
        if let armed { return armed }
        let k = ContextHandoffDirective.k
        guard let context, context.size > 0 else { return "Hands off past \(k(settings.setting))." }
        let limit = ContextHandoffPolicy.limit(setting: settings.setting, size: context.size)
        let ceiling = ContextHandoffPolicy.ceiling(setting: settings.setting, size: context.size)
        return "This window: \(k(context.used)) of \(k(context.size)). Hands off at the next clean break "
            + "past \(k(limit)), at the end of the turn past \(k(ceiling))."
    }

    private func row(_ limit: Int) -> some View {
        let k = ContextHandoffDirective.k
        // Capped at 70% of a smaller window.
        let here = context.map { ContextHandoffPolicy.limit(setting: limit, size: $0.size) }
        return Button { settings.limit = limit } label: {
            HStack(spacing: 0) {
                Text("Hand off after " + k(limit))
                Spacer(minLength: 10)
                if let here, here != limit {
                    Text(k(here) + " here").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(settings.limit == limit ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!settings.enabled)
        .opacity(settings.enabled ? 1 : 0.5)
    }
}

private extension NSColor {
    /// Relative luminance above the midpoint: dark ink reads better on it.
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent > 0.6
    }
}
#endif
