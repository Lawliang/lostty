#if os(macOS)
import Foundation

/// The plan's weekly limits for one model, such as Fable's, which Claude
/// Code shows on its /usage screen but leaves out of what it sends the
/// status line. Read from `claude -p /usage`, a local command that asks
/// no model and costs nothing: every `interval`, and when the Usage app
/// opens (at most once a minute).
@MainActor
final class ClaudeModelLimits: ObservableObject {
    struct Limit: Equatable {
        /// The model, as /usage names it: "Fable".
        let name: String
        let percent: Double
        /// As /usage says it: "resets Nov 12 at 8pm (America/Los_Angeles)".
        let reset: String?
    }

    static let shared = ClaudeModelLimits()
    static let interval: TimeInterval = 15 * 60
    static let soonest: TimeInterval = 60
    /// Where Claude Code's installer and Homebrew put `claude`; the app's
    /// own PATH has neither.
    nonisolated static let places = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    @Published private(set) var limits: [Limit] = []

    private var timer: Timer?
    private var reading = false
    private var lastRead: Date?

    /// The per-model lines of /usage's text: "Current week (Fable): 3% used
    /// · resets …". Not the all-models week, which the status line sends.
    nonisolated static func parse(_ text: String) -> [Limit] {
        text.split(separator: "\n").compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("Current week ("), let close = line.range(of: "): ") else { return nil }
            let name = String(line[line.index(line.startIndex, offsetBy: 14)..<close.lowerBound])
            let rest = line[close.upperBound...]
            guard name != "all models", let percentEnd = rest.range(of: "% used"),
                  let percent = Double(rest[..<percentEnd.lowerBound]) else { return nil }
            let after = rest[percentEnd.upperBound...]
            let reset = after.range(of: "resets ").map { String(after[$0.lowerBound...]) }
            return Limit(name: name.replacingOccurrences(of: " only", with: ""), percent: percent, reset: reset)
        }
    }

    /// `claude -p`'s JSON answer's text.
    nonisolated static func text(ofAnswer data: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["result"] as? String
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { ClaudeModelLimits.shared.refresh() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        if reading || lastRead.map({ Date().timeIntervalSince($0) < Self.soonest }) == true { return }
        reading = true
        lastRead = Date()
        Task {
            let read = await Task.detached(priority: .utility) { Self.read() }.value
            reading = false
            if let read, read != limits { limits = read }
        }
    }

    /// Runs `claude -p /usage`; nil when it can't.
    nonisolated static func read() -> [Limit]? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let claude = places.map({ $0.replacingOccurrences(of: "~", with: home) })
            .first(where: FileManager.default.isExecutableFile(atPath:)) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = ["-p", "/usage", "--output-format", "json", "--no-session-persistence",
                             "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#]
        process.currentDirectoryURL = URL(fileURLWithPath: home)
        // Not a Lostty pane's: its hooks stay quiet.
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("LOSTTY_") { environment[key] = nil }
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: killer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        guard process.terminationStatus == 0, let text = text(ofAnswer: data) else { return nil }
        return parse(text)
    }
}
#endif
