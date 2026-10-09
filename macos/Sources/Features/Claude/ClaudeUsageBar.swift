#if os(macOS)
import AppKit
import SwiftUI

/// The strip along the bottom of the window, as tall as the title bar and
/// the same color as it and the sidebar: the focused pane's Claude context
/// on the left, the tracked usage (a bar and a percentage) on the right.
/// Clicking it lists every usage; picking one tracks it here. Without a
/// Claude session in the focused pane the strip is empty.
struct ClaudeUsageBar: View {
    /// A standard title bar's height.
    static let height: CGFloat = NSWindow.frameRect(forContentRect: .zero, styleMask: [.titled]).height

    @ObservedObject var model: ExtensionSidebarModel
    @ObservedObject private var usage = ClaudeUsageRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager
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
        Button { showingDetails.toggle() } label: {
            // Ticks so a limit that resets while nothing reports drops to 0%.
            TimelineView(.everyMinute) { _ in
                HStack(spacing: 10) {
                    if hasSession {
                        contextLabel
                        Spacer(minLength: 12)
                        trackedLabel
                    } else {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(ink.opacity(hovering || showingDetails ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasSession)
        .onHover { hovering = $0 && hasSession }
        .help("Claude usage: click to choose what this bar tracks")
        .popover(isPresented: $showingDetails, arrowEdge: .top) {
            TimelineView(.everyMinute) { _ in
                ClaudeUsageDetails(usage: usage, pane: pane, accent: accent) { showingDetails = false }
            }
        }
        .background(Color(nsColor: chrome))
    }

    /// The model, then the context once Claude has replied.
    private var contextLabel: some View {
        HStack(spacing: 6) {
            Text("✳").foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
            if let name = pane.flatMap({ usage.models[$0] }) {
                Text(name).foregroundStyle(ink.opacity(0.55))
            }
            if let context = pane.flatMap({ usage.contexts[$0] }) {
                Text("\(ClaudeUsageFormat.tokens(context.used)) / \(ClaudeUsageFormat.tokens(context.size))")
                    .foregroundStyle(ink.opacity(0.85))
                    .monospacedDigit()
                Text("context").foregroundStyle(ink.opacity(0.45))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }

    private var trackedLabel: some View {
        let metric = usage.tracked
        let percent = usage.percent(metric, pane: pane)
        return HStack(spacing: 7) {
            Text(metric.shortTitle)
                .foregroundStyle(ink.opacity(0.55))
            ClaudeUsageMeter(percent: percent, accent: accent, track: ink.opacity(0.14))
                .frame(width: 84, height: 5)
            Text(percent.map(ClaudeUsageFormat.percent) ?? "—")
                .foregroundStyle(ink.opacity(0.9))
                .monospacedDigit()
                .frame(minWidth: 30, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }
}

/// A thin capsule meter. The fill turns amber past 70% and red past 90%.
struct ClaudeUsageMeter: View {
    let percent: Double?
    let accent: Color
    let track: Color

    static func fill(for percent: Double, accent: Color) -> Color {
        if percent >= 90 { return Color(red: 0.95, green: 0.33, blue: 0.30) }
        if percent >= 70 { return Color(red: 0.96, green: 0.68, blue: 0.25) }
        return accent
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if let percent {
                    Capsule()
                        .fill(Self.fill(for: percent, accent: accent))
                        .frame(width: max(geo.size.height, geo.size.width * min(percent, 100) / 100))
                        .opacity(percent > 0 ? 1 : 0)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: percent)
    }
}

/// Every usage, each tappable to make it the one the bar tracks.
private struct ClaudeUsageDetails: View {
    @ObservedObject var usage: ClaudeUsageRuntime
    let pane: UUID?
    let accent: Color
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude usage")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(ClaudeUsageMetric.allCases) { metric in
                row(metric)
            }
            Text("Click one to show it in the bar.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(width: 300)
    }

    private func row(_ metric: ClaudeUsageMetric) -> some View {
        let percent = usage.percent(metric, pane: pane)
        let available = metric != .weeklyFable
        return Button {
            usage.tracked = metric
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(metric.title).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(percent.map(ClaudeUsageFormat.percent) ?? "—")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }
                    ClaudeUsageMeter(percent: percent, accent: accent, track: Color.primary.opacity(0.1))
                        .frame(height: 5)
                    Text(subtitle(metric))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .opacity(usage.tracked == metric ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(usage.tracked == metric ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.5)
    }

    private func subtitle(_ metric: ClaudeUsageMetric) -> String {
        let now = usage.now()
        switch metric {
        case .context:
            guard let context = pane.flatMap({ usage.contexts[$0] }) else { return "Shows after Claude's first reply" }
            return "\(ClaudeUsageFormat.tokens(context.used)) of \(ClaudeUsageFormat.tokens(context.size)) tokens"
        case .session:
            return limitSubtitle(usage.fiveHour, now: now, window: "5-hour limit")
        case .weekly:
            return limitSubtitle(usage.sevenDay, now: now, window: "7-day limit")
        case .weeklyFable:
            return "Claude Code doesn't share this one yet"
        }
    }

    private func limitSubtitle(_ limit: ClaudeUsageReport.Limit?, now: Date, window: String) -> String {
        guard let limit else { return "Shows after Claude's next reply (Pro and Max plans)" }
        guard let reset = limit.resetsAt else { return window }
        return "\(window) · \(ClaudeUsageFormat.reset(reset, now: now))"
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
