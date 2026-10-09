#if os(macOS)
import Foundation
import Combine

/// What Claude Code's status line feed reports through `+claude-usage`
/// (the LOSTTY_USAGE user var): `{"v":1,"ctx":{"used":…,"size":…},
/// "five":{"pct":…,"reset":…},"week":{…},"model":"…"}`. Every piece but
/// `v` is optional.
struct ClaudeUsageReport: Equatable {
    struct Context: Equatable {
        var used: Int
        var size: Int

        var percent: Double { size > 0 ? Double(used) / Double(size) * 100 : 0 }
    }

    struct Limit: Equatable, Codable {
        var percent: Double
        var resetsAt: Date?

        /// A window that has reset since the report counts as empty.
        func percent(at now: Date) -> Double {
            if let resetsAt, resetsAt <= now { return 0 }
            return percent
        }
    }

    static let userVarName = "LOSTTY_USAGE"

    var context: Context?
    var fiveHour: Limit?
    var sevenDay: Limit?
    var model: String?

    /// Nil for other versions and malformed input.
    static func decode(_ value: String) -> ClaudeUsageReport? {
        guard let data = value.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (object["v"] as? Int) == 1 else { return nil }
        var report = ClaudeUsageReport()
        if let ctx = object["ctx"] as? [String: Any],
           let used = (ctx["used"] as? NSNumber)?.intValue,
           let size = (ctx["size"] as? NSNumber)?.intValue, size > 0 {
            report.context = Context(used: max(0, used), size: size)
        }
        report.fiveHour = limit(object["five"])
        report.sevenDay = limit(object["week"])
        report.model = object["model"] as? String
        return report
    }

    private static func limit(_ value: Any?) -> Limit? {
        guard let obj = value as? [String: Any],
              let pct = (obj["pct"] as? NSNumber)?.doubleValue, pct.isFinite else { return nil }
        let reset = (obj["reset"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return Limit(percent: min(max(pct, 0), 100), resetsAt: reset)
    }
}

/// The plan limit the bar at the bottom of the window tracks (the context
/// has a meter of its own).
enum ClaudeUsageMetric: String, CaseIterable, Identifiable {
    case session, weekly, weeklyFable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: "Current session"
        case .weekly: "Weekly · all models"
        case .weeklyFable: "Weekly · Fable"
        }
    }

    /// Short form for the bar.
    var shortTitle: String {
        switch self {
        case .session: "Session"
        case .weekly: "Weekly"
        case .weeklyFable: "Fable"
        }
    }
}

/// App-wide usage: each pane's Claude context window, and the plan's
/// limits (account-wide, so the latest report from any pane wins).
@MainActor
final class ClaudeUsageRuntime: ObservableObject {
    static let shared = ClaudeUsageRuntime()

    /// Panes running a Claude session: they have reported at least once.
    @Published private(set) var sessions: Set<UUID> = []
    @Published private(set) var contexts: [UUID: ClaudeUsageReport.Context] = [:]
    @Published private(set) var models: [UUID: String] = [:]
    @Published private(set) var fiveHour: ClaudeUsageReport.Limit?
    @Published private(set) var sevenDay: ClaudeUsageReport.Limit?
    /// What the bar shows; tapped in the bar's popover, remembered.
    @Published var tracked: ClaudeUsageMetric {
        didSet { defaults.set(tracked.rawValue, forKey: Keys.tracked) }
    }

    private let defaults: UserDefaults
    let now: () -> Date

    private enum Keys {
        static let tracked = "LosttyUsageTracked"
        static let fiveHour = "LosttyUsageFiveHour"
        static let sevenDay = "LosttyUsageSevenDay"
    }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        tracked = defaults.string(forKey: Keys.tracked).flatMap(ClaudeUsageMetric.init(rawValue:)) ?? .session
        // The limits from the last run, so the bar has numbers before Claude replies.
        fiveHour = Self.load(defaults, Keys.fiveHour)
        sevenDay = Self.load(defaults, Keys.sevenDay)
    }

    func userVarChanged(_ id: UUID, name: String, value: String) {
        guard name == ClaudeUsageReport.userVarName else { return }
        guard let report = ClaudeUsageReport.decode(value) else {
            Ghostty.logger.debug("claude: rejected malformed \(ClaudeUsageReport.userVarName) payload")
            return
        }
        // Claude reports at session start, before it has any context numbers.
        if !sessions.contains(id) { sessions.insert(id) }
        if let context = report.context, contexts[id] != context { contexts[id] = context }
        if let model = report.model, models[id] != model { models[id] = model }
        if let limit = report.fiveHour, fiveHour != limit {
            fiveHour = limit
            Self.save(defaults, Keys.fiveHour, limit)
        }
        if let limit = report.sevenDay, sevenDay != limit {
            sevenDay = limit
            Self.save(defaults, Keys.sevenDay, limit)
        }
    }

    /// Whatever ran in the pane (claude included) finished: its context is gone.
    func commandFinished(_ id: UUID) {
        forget(id)
    }

    func surfaceClosed(_ id: UUID) {
        forget(id)
    }

    /// Percent of `metric` used, or nil before any report of it.
    func percent(_ metric: ClaudeUsageMetric) -> Double? {
        switch metric {
        case .session: fiveHour?.percent(at: now())
        case .weekly: sevenDay?.percent(at: now())
        case .weeklyFable: nil
        }
    }

    private func forget(_ id: UUID) {
        if sessions.contains(id) { sessions.remove(id) }
        if contexts[id] != nil { contexts[id] = nil }
        if models[id] != nil { models[id] = nil }
    }

    private static func load(_ defaults: UserDefaults, _ key: String) -> ClaudeUsageReport.Limit? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ClaudeUsageReport.Limit.self, from: $0) }
    }

    private static func save(_ defaults: UserDefaults, _ key: String, _ limit: ClaudeUsageReport.Limit) {
        if let data = try? JSONEncoder().encode(limit) { defaults.set(data, forKey: key) }
    }
}

enum ClaudeUsageFormat {
    /// Tokens to the nearest thousand: 49_600 → "50K", 1_234_000 → "1,234K".
    static func thousands(_ n: Int) -> String {
        let k = Int((Double(n) / 1_000).rounded())
        return k.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US"))) + "K"
    }

    static func percent(_ p: Double) -> String {
        "\(Int(p.rounded()))%"
    }

    /// "Resets in 2h 14m" within a day, otherwise "Resets Fri, 9 AM".
    static func reset(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "Reset" }
        if seconds < 24 * 3600 {
            let minutes = Int((seconds / 60).rounded(.up))
            let h = minutes / 60, m = minutes % 60
            return h > 0 ? "Resets in \(h)h \(m)m" : "Resets in \(m)m"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE j")
        return "Resets " + formatter.string(from: date)
    }
}
#endif
