#if os(macOS)
import AppKit
import CoreText
import SwiftUI

/// The strip along the bottom of the window, as tall as the title bar and
/// the same color as it and the sidebar, in the terminal's font. At the
/// left, `✳ Opus 5.5`; centered, `Context ▓▓░░░░░░░░ 50K   Session ▓░░░░░░░░░ 2%`,
/// the focused pane's context and the tracked plan limit (clicking it lists
/// every limit, and picking one tracks it here). Both are hidden without a
/// Claude session in the focused pane. At the far right, the mute button.
struct ClaudeUsageBar: View {
    /// A standard title bar's height.
    static let height: CGFloat = NSWindow.frameRect(forContentRect: .zero, styleMask: [.titled]).height

    @ObservedObject var model: ExtensionSidebarModel
    @ObservedObject private var usage = ClaudeUsageRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @ObservedObject private var mute = LosttyMute.shared
    @State private var showingDetails = false
    @State private var hovering = false

    private var pane: UUID? { model.focusedSurfaceID }
    private var chrome: NSColor { model.chromeColor ?? .windowBackgroundColor }
    private var ink: Color { chrome.isLight ? .black : .white }
    private var accent: Color {
        pane.flatMap { skins.effectiveSkin($0) }.map { Color(rgb: $0.accent) } ?? ink.opacity(0.8)
    }
    private var hasSession: Bool { pane.map { usage.sessions.contains($0) } ?? false }

    var body: some View {
        ZStack {
            if hasSession {
                usageButton
                    // Equal on both sides so it stays centered, clear of
                    // the model on the left and mute on the right.
                    .padding(.horizontal, 110)
            }
            HStack(spacing: 0) {
                if hasSession { modelLabel }
                Spacer(minLength: 0)
                muteButton
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
        }
        .font(ClaudeUsageFont.font(size: 12))
        .lineLimit(1)
        // Never wider than the window: a narrow one truncates the text.
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: Self.height)
        .clipped()
        .background(Color(nsColor: chrome))
    }

    private var usageButton: some View {
        Button { showingDetails.toggle() } label: {
            // Ticks so a limit that resets while nothing reports drops to 0%.
            TimelineView(.everyMinute) { _ in line }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ink.opacity(hovering || showingDetails ? 0.07 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $showingDetails, arrowEdge: .top) {
            TimelineView(.everyMinute) { _ in
                ClaudeUsageDetails(usage: usage, accent: accent) { showingDetails = false }
            }
        }
    }

    private var muteButton: some View {
        Button { mute.isMuted.toggle() } label: {
            Image(systemName: mute.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ink.opacity(mute.isMuted ? 0.85 : 0.5))
                .frame(width: 28, height: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mute.isMuted ? "Unmute terminal sounds" : "Mute terminal sounds")
    }

    private var modelLabel: some View {
        Text("✳ ").foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
            + Text(pane.flatMap { usage.models[$0] } ?? "").foregroundColor(ink.opacity(0.6))
    }

    private var line: some View {
        let context = pane.flatMap { usage.contexts[$0] }
        let metric = usage.tracked
        let limit = usage.percent(metric) ?? 0

        return (Text("Context ").foregroundColor(ink.opacity(0.6))
            + ClaudeUsageBlocks.text(context?.percent ?? 0, accent: accent, empty: ink.opacity(0.28))
            + Text(" " + ClaudeUsageFormat.thousands(context?.used ?? 0)).foregroundColor(ink.opacity(0.9))
            + Text("   " + metric.shortTitle + " ").foregroundColor(ink.opacity(0.6))
            + ClaudeUsageBlocks.text(limit, accent: accent, empty: ink.opacity(0.28))
            + Text(" " + ClaudeUsageFormat.percent(limit)).foregroundColor(ink.opacity(0.9)))
    }
}

/// A text meter of block characters: `▓` used, `░` free. The used part
/// turns amber past 70% and red past 90%.
enum ClaudeUsageBlocks {
    static let cells = 10

    /// Used cells for `percent`: any use shows at least one.
    static func filled(_ percent: Double, cells: Int = cells) -> Int {
        let p = min(max(percent, 0), 100)
        guard p > 0 else { return 0 }
        return min(cells, max(1, Int((p / 100 * Double(cells)).rounded())))
    }

    static func fill(for percent: Double, accent: Color) -> Color {
        if percent >= 90 { return Color(red: 0.95, green: 0.33, blue: 0.30) }
        if percent >= 70 { return Color(red: 0.96, green: 0.68, blue: 0.25) }
        return accent
    }

    static func text(_ percent: Double, accent: Color, empty: Color) -> Text {
        let used = filled(percent)
        return Text(String(repeating: "▓", count: used)).foregroundColor(fill(for: percent, accent: accent))
            + Text(String(repeating: "░", count: cells - used)).foregroundColor(empty)
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
}

/// Every plan limit, each tappable to make it the one the bar tracks.
private struct ClaudeUsageDetails: View {
    @ObservedObject var usage: ClaudeUsageRuntime
    let accent: Color
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ClaudeUsageMetric.allCases) { metric in
                row(metric)
            }
        }
        .font(ClaudeUsageFont.font(size: 12))
        .padding(6)
        .frame(width: 320)
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

private extension NSColor {
    /// Relative luminance above the midpoint: dark ink reads better on it.
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent > 0.6
    }
}
#endif
