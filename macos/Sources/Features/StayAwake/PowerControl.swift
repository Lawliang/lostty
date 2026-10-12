#if os(macOS)
import Foundation

/// The power settings Stay Awake changes, as they were before it did.
struct PowerSettings: Codable, Equatable {
    var disableSleep: Bool
    /// nil on Macs without a battery.
    var lowPowerOnBattery: Bool?
    var lowPowerOnAC: Bool
}

enum PowerSource: String, Codable {
    case battery = "-b"
    case ac = "-c"
}

/// The only `pmset` changes Lostty makes; each is one line of the sudoers
/// rule (`StayAwakeSudoers`).
enum PowerCommand: Equatable {
    case disableSleep(Bool)
    case lowPowerEverywhere
    case lowPower(PowerSource, Bool)

    static let all: [PowerCommand] = [
        .disableSleep(false), .disableSleep(true), .lowPowerEverywhere,
        .lowPower(.battery, false), .lowPower(.battery, true),
        .lowPower(.ac, false), .lowPower(.ac, true),
    ]

    var pmsetArguments: [String] {
        switch self {
        case .disableSleep(let on): ["-a", "disablesleep", on ? "1" : "0"]
        case .lowPowerEverywhere: ["-a", "lowpowermode", "1"]
        case .lowPower(let source, let on): [source.rawValue, "lowpowermode", on ? "1" : "0"]
        }
    }
}

enum PowerParse {
    /// `pmset -g` lists `SleepDisabled 1` under the system-wide settings only
    /// while it is set.
    static func sleepDisabled(pmsetG: String) -> Bool {
        pmsetG.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count == 2 && fields[0] == "SleepDisabled" && fields[1] == "1"
        }
    }

    /// `pmset -g custom`: `lowpowermode` under "Battery Power:" and "AC Power:".
    static func lowPower(pmsetCustom: String) -> (battery: Bool?, ac: Bool?) {
        var section: PowerSource?
        var battery: Bool?
        var ac: Bool?
        for line in pmsetCustom.split(separator: "\n") {
            if line.hasPrefix("Battery Power:") { section = .battery; continue }
            if line.hasPrefix("AC Power:") { section = .ac; continue }
            if !line.hasPrefix(" "), !line.hasPrefix("\t"), line.hasSuffix(":") { section = nil; continue }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[0] == "lowpowermode" else { continue }
            let on = fields[1] == "1"
            switch section {
            case .battery: battery = on
            case .ac: ac = on
            case nil: break
            }
        }
        return (battery, ac)
    }
}

enum PowerControlError: Error, Equatable {
    /// `sudo -n` wants a password: the sudoers rule is missing.
    case permissionMissing
    case failed(String)
    case unreadable
}

protocol PowerControl {
    func read() throws -> PowerSettings
    func run(_ command: PowerCommand) throws
    func hasPermission() -> Bool
}

/// `pmset` through `sudo -n`, which never prompts: without the rule it fails
/// at once instead of waiting for a password nobody can type.
struct SystemPowerControl: PowerControl {
    func read() throws -> PowerSettings {
        guard let g = Command.run("/usr/bin/pmset", ["-g"]), g.status == 0,
              let custom = Command.run("/usr/bin/pmset", ["-g", "custom"]), custom.status == 0
        else { throw PowerControlError.unreadable }
        let lowPower = PowerParse.lowPower(pmsetCustom: custom.output)
        guard let ac = lowPower.ac else { throw PowerControlError.unreadable }
        return PowerSettings(
            disableSleep: PowerParse.sleepDisabled(pmsetG: g.output),
            lowPowerOnBattery: lowPower.battery, lowPowerOnAC: ac)
    }

    func run(_ command: PowerCommand) throws {
        guard let result = Command.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + command.pmsetArguments) else {
            throw PowerControlError.failed("pmset didn't finish.")
        }
        guard result.status != 0 else { return }
        if result.output.contains("password is required") || result.output.contains("terminal is required") {
            throw PowerControlError.permissionMissing
        }
        throw PowerControlError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The rule file is there and sudo lets this user run pmset without a
    /// password. Both: `sudo -n -l` alone also passes on a fresh sudo timestamp.
    func hasPermission() -> Bool {
        FileManager.default.fileExists(atPath: StayAwakeSudoers.path)
            && Command.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"])?.status == 0
    }
}
#endif
