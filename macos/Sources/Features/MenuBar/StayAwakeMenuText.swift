#if os(macOS)
import Foundation

enum StayAwakeMenuText {
    static func status(_ state: StayAwakeModel.State, power: PowerState?, permissionInstalled: Bool, now: Date) -> String? {
        switch state {
        case .on(let until, _):
            var parts = [until.map { timeLeft($0.timeIntervalSince(now)) } ?? "On until you turn it off"]
            if let power {
                if power.onBattery, let percent = power.batteryPercent {
                    parts.append("\(percent)% on battery")
                } else {
                    parts.append("on power")
                }
                parts.append(heat(power.thermal))
            }
            return parts.joined(separator: " · ")
        case .off(let reason, let at):
            let time = at.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
            switch reason {
            case .battery(let percent): return "Turned off at \(percent)% battery" + time
            case .heat: return "Turned off: the Mac got too hot" + time
            case .timer: return "Time ran out" + time
            case .restoreFailed: return StayAwakeCopy.restoreFailed
            case .failed(let message): return "Couldn't turn on: \(message)"
            case .permissionMissing: return "Needs the stay-awake permission"
            case .turnedOff, nil: return permissionInstalled ? nil : "Needs the stay-awake permission"
            }
        }
    }

    static func attached(_ session: String) -> String { "A phone or SSH client is attached to \(session)" }

    struct ClaudeRow: Equatable {
        var id: UUID
        var title: String
        var waiting: Bool
    }

    /// Waiting panes first, then working ones, each by title.
    static func claudeRows(phases: Set<UUID>, awaiting: Set<UUID>, title: (UUID) -> String?) -> [ClaudeRow] {
        phases.union(awaiting).map { id in
            let t = title(id)?.trimmingCharacters(in: .whitespaces) ?? ""
            return ClaudeRow(id: id, title: t.isEmpty ? "Claude" : t, waiting: awaiting.contains(id))
        }
        .sorted { ($0.waiting ? 0 : 1, $0.title) < ($1.waiting ? 0 : 1, $1.title) }
    }

    private static func timeLeft(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.up))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left"
    }

    private static func heat(_ thermal: Thermal) -> String {
        switch thermal {
        case .nominal: "normal"
        case .fair: "warm"
        case .serious, .critical: "hot"
        }
    }
}
#endif
