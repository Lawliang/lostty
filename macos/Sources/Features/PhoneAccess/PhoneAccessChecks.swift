#if os(macOS)
import Foundation

/// What Phone Access needs from this Mac, all read without admin rights.
struct PhoneAccessStatus: Equatable {
    struct Tailscale: Equatable {
        var running: Bool
        /// MagicDNS name, without the trailing dot.
        var name: String?
        var ipv4: String?
    }

    /// nil: Tailscale isn't installed.
    var tailscale: Tailscale?
    var tmuxPath: String?
    var remoteLogin: Bool
    /// The login methods sshd offers before any are tried; nil when sshd
    /// didn't answer.
    var authMethods: [String]?
    var lockdownFileExists: Bool
    var blockAllIncoming: Bool
    var terminfoInstalled: Bool
    /// Which of `PhoneAccessFolders.names` Lostty can read; nil until the
    /// customer has clicked Grant Now (checking earlier would make macOS ask).
    var folders: [String: Bool]? = nil
    /// The sudoers rule Stay Awake for Phone needs. Optional: never blocks
    /// pairing.
    var stayAwakePermission: Bool = false
    /// Lostty's sshd setting that drops silent clients is in place, as
    /// Lostty writes it. Optional: never blocks pairing.
    var dropsLostConnections: Bool = false

    var tailscaleReady: Bool {
        tailscale?.running == true && tailscale?.name != nil && tailscale?.ipv4 != nil
    }

    /// Only keys can sign in. Read from what sshd offers, so a customer
    /// setting that overrides Lostty's file shows up here.
    var passwordsOff: Bool { authMethods.map(Set.init) == ["publickey"] }

    func readyToPair(lockdownSkipped: Bool) -> Bool {
        tailscaleReady && tmuxPath != nil && remoteLogin && (passwordsOff || lockdownSkipped)
            && !blockAllIncoming && terminfoInstalled
    }
}

enum PhoneAccessParse {
    /// `tailscale status --json`; nil when it isn't JSON.
    static func tailscale(statusJSON: Data) -> PhoneAccessStatus.Tailscale? {
        guard let root = try? JSONSerialization.jsonObject(with: statusJSON) as? [String: Any] else { return nil }
        let me = root["Self"] as? [String: Any]
        let dns = (me?["DNSName"] as? String).map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
        let ips = me?["TailscaleIPs"] as? [String] ?? []
        return .init(
            running: root["BackendState"] as? String == "Running",
            name: dns?.isEmpty == false ? dns : nil,
            ipv4: ips.first { !$0.contains(":") })
    }

    /// `launchctl print-disabled system` lists sshd as enabled.
    static func sshdEnabled(printDisabled: String) -> Bool {
        printDisabled.split(separator: "\n").contains { line in
            line.contains("\"com.openssh.sshd\"") && line.contains("=> enabled")
        }
    }

    /// The list in "Permission denied (publickey,password)."; nil when ssh
    /// never got that far.
    static func authMethods(sshOutput: String) -> [String]? {
        guard let open = sshOutput.range(of: "Permission denied ("),
              let close = sshOutput[open.upperBound...].firstIndex(of: ")")
        else { return nil }
        return sshOutput[open.upperBound..<close].split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// `socketfilterfw --getblockall` says block-all is on.
    static func blockAll(firewallOutput: String) -> Bool {
        let text = firewallOutput.lowercased()
        return !text.contains("disabled") && text.range(of: #"\benabled\b"#, options: .regularExpression) != nil
    }
}

/// Runs a program; its exit status and combined stdout and stderr. nil when
/// it couldn't start, or ran past `timeout` (then it is killed).
enum Command {
    struct Result: Equatable {
        var status: Int32
        var output: String
    }

    private final class Collected: @unchecked Sendable {
        var data = Data()
    }

    /// `environment` is added to Lostty's own.
    static func run(
        _ path: String, _ arguments: [String], environment: [String: String] = [:], timeout: TimeInterval = 5
    ) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, added in added }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        // Read while it runs: a full pipe would block the child. A private
        // queue, not the global one, which can starve while callers block
        // every cooperative thread (see ProcessRunner).
        let collected = Collected()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue(label: "lostty.command.read", qos: .utility).async {
            collected.data = pipe.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = drained.wait(timeout: .now() + 1)
            return nil
        }
        // A grandchild can keep the pipe open after the child exits; don't
        // wait on it forever.
        if drained.wait(timeout: .now() + 1) == .timedOut { return nil }
        return Result(status: process.terminationStatus, output: String(decoding: collected.data, as: UTF8.self))
    }
}

/// xterm-ghostty in ~/.terminfo, where ncurses looks by default, so the
/// phone's attach doesn't depend on where Lostty.app is.
enum PhoneAccessTerminfo {
    static let entries = ["78/xterm-ghostty", "67/ghostty"]

    /// The bundle ships 67/ghostty as a symlink, and contentsEqual calls a
    /// symlink and a plain file different whatever they hold: resolve it.
    static func installed(bundle: URL, home: URL) -> Bool {
        entries.allSatisfy { entry in
            FileManager.default.contentsEqual(
                atPath: bundle.appendingPathComponent(entry).resolvingSymlinksInPath().path,
                andPath: home.appendingPathComponent(entry).path)
        }
    }

    static func install(bundle: URL, home: URL) throws {
        for entry in entries {
            let target = home.appendingPathComponent(entry)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: bundle.appendingPathComponent(entry)).write(to: target, options: .atomic)
        }
    }

    static var bundleDirectory: URL { Bundle.main.resourceURL!.appendingPathComponent("terminfo") }
    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".terminfo")
    }
}

/// macOS asks before an app reads Desktop, Documents or Downloads, and asks
/// on the Mac's screen: a phone session that touches one first just hangs.
/// Reading them once at the Mac gets the questions answered there.
enum PhoneAccessFolders {
    static let names = ["Desktop", "Documents", "Downloads"]
    static let requestedDefaultsKey = "LosttyPhoneAccessFoldersRequested"

    /// Whether each folder can be listed. The first time, macOS asks and
    /// this waits for the answer; after that it answers without asking.
    static func check(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: names.map { name in
            (name, (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(name).path)) != nil)
        })
    }
}

enum PhoneAccessProbe {
    static let tailscaleCLI = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    static let lockdownPath = "/etc/ssh/sshd_config.d/000-lostty.conf"
    /// Before macOS's own 100-macos.conf: sshd keeps the first value it reads.
    static let alivePath = "/etc/ssh/sshd_config.d/001-lostty-alive.conf"

    /// The file holds exactly what Lostty writes: an older or edited one
    /// is offered again.
    static func dropsLostConnections(fileContents: String?) -> Bool {
        fileContents == PhoneAccessAdmin.aliveConfig
    }

    /// Runs every check. Takes up to a few seconds: call it off the main thread.
    /// Folders are checked only once the customer has asked for access
    /// (`foldersRequested`), so opening the window never makes macOS ask.
    static func run(foldersRequested: Bool) -> PhoneAccessStatus {
        var tailscale: PhoneAccessStatus.Tailscale?
        if FileManager.default.isExecutableFile(atPath: tailscaleCLI) {
            // The App Store Tailscale is its app binary; without a terminal
            // it tries to open its GUI instead, unless told to be the CLI.
            let out = Command.run(tailscaleCLI, ["status", "--json"], environment: ["TAILSCALE_BE_CLI": "1"])?.output ?? ""
            tailscale = PhoneAccessParse.tailscale(statusJSON: Data(out.utf8))
                ?? .init(running: false, name: nil, ipv4: nil)
        }
        let enabled = PhoneAccessParse.sshdEnabled(
            printDisabled: Command.run("/bin/launchctl", ["print-disabled", "system"])?.output ?? "")
        // "none" never authenticates, so sshd answers with the methods it
        // offers. -F /dev/null ignores the user's ssh config.
        let ssh = Command.run("/usr/bin/ssh", [
            "-F", "/dev/null", "-o", "BatchMode=yes", "-o", "PreferredAuthentications=none",
            "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=3", "-o", "LogLevel=ERROR", "\(NSUserName())@127.0.0.1", "true",
        ])
        let methods = PhoneAccessParse.authMethods(sshOutput: ssh?.output ?? "")
        let firewall = Command.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getblockall"])?.output ?? ""
        return PhoneAccessStatus(
            tailscale: tailscale,
            tmuxPath: TmuxClient.locate(),
            remoteLogin: enabled && methods != nil,
            authMethods: methods,
            lockdownFileExists: FileManager.default.fileExists(atPath: lockdownPath),
            blockAllIncoming: PhoneAccessParse.blockAll(firewallOutput: firewall),
            terminfoInstalled: PhoneAccessTerminfo.installed(
                bundle: PhoneAccessTerminfo.bundleDirectory, home: PhoneAccessTerminfo.homeDirectory),
            folders: foldersRequested ? PhoneAccessFolders.check() : nil,
            stayAwakePermission: SystemPowerControl().hasPermission(),
            dropsLostConnections: dropsLostConnections(fileContents: try? String(contentsOfFile: alivePath, encoding: .utf8)))
    }
}
#endif
