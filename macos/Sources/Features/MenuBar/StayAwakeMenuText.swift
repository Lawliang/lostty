#if os(macOS)
import Foundation
import LosttyRemote

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
            case .permissionMissing: return permissionInstalled ? nil : "Needs the stay-awake permission"
            case .turnedOff, nil: return permissionInstalled ? nil : "Needs the stay-awake permission"
            }
        }
    }

    static func attached(_ session: String) -> String { "A phone or SSH client is attached to \(session)" }

    /// A Sessions row: "● task — Waiting", "○ task — Working", "project — 5m ago".
    static func sessionLine(_ row: SessionRow) -> String {
        let marker: String
        switch row.status {
        case .waiting: marker = "● "
        case .working: marker = "○ "
        case .lastUsed: marker = ""
        }
        let right = row.statusText.isEmpty ? "" : " — \(row.statusText)"
        return "   \(marker)\(row.title)\(right)"
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
