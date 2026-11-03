#if os(macOS)
import AppKit
import Foundation

/// What a Claude pane shows while it records a dictation in tap mode:
/// the words in its input box so far and its sound-level bar (1, quiet,
/// to 8, loud; nil when Claude draws no bar).
struct VoiceFrame: Equatable {
    var words: String
    var level: Int?

    static let marker = "REC · tap to send"
    static let bars: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    /// The frame on a pane's screen, or nil when Claude isn't recording.
    static func parse(_ screen: String) -> VoiceFrame? {
        let lines = screen.components(separatedBy: "\n")
        guard let footer = lines.lastIndex(where: { $0.contains(marker) }),
              let start = lines[..<footer].lastIndex(where: { $0.hasPrefix("❯") }) else { return nil }
        var text: [String] = []
        for (index, line) in lines[start..<footer].enumerated() {
            if index > 0 && line.hasPrefix("─") { break }
            text.append(index == 0 ? String(line.dropFirst()) : line)
        }
        let joined = text.joined(separator: " ")
        let level = joined.last { bars.contains($0) }.flatMap { bars.firstIndex(of: $0) }.map { $0 + 1 }
        let words = joined.filter { !bars.contains($0) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return VoiceFrame(words: words, level: level)
    }
}

/// One pane's dictation, from its voice key on: once you've spoken and
/// gone quiet for `quiet` seconds, a `countdown` starts, and when it runs
/// out Lostty sends the message. Speaking again calls the countdown off,
/// and so does `hold()` (the voice key pressed during it) until you speak
/// again.
struct VoiceWatch: Equatable {
    static let quiet: TimeInterval = 1
    static let countdown: TimeInterval = 3
    /// How long Claude may take to start recording after the key.
    static let warmup: TimeInterval = 5
    /// How long the recording mark may be missing (a frame mid-redraw)
    /// before the recording counts as over.
    static let gone: TimeInterval = 1

    enum Step: Equatable { case wait, send, stop }

    var since: Date
    var words = ""
    var heard: Date?
    var seen: Date?
    var sendsAt: Date?
    var held = false

    init(since: Date) { self.since = since }

    mutating func update(_ frame: VoiceFrame?, now: Date) -> Step {
        guard let frame else {
            sendsAt = nil
            let limit = seen == nil ? Self.warmup : Self.gone
            return now.timeIntervalSince(seen ?? since) > limit ? .stop : .wait
        }
        seen = now
        if frame.words != words || (frame.level ?? 1) > 1 {
            words = frame.words
            heard = now
            sendsAt = nil
            held = false
            return .wait
        }
        if let sendsAt { return now >= sendsAt ? .send : .wait }
        if let heard, !held, now.timeIntervalSince(heard) >= Self.quiet {
            sendsAt = now.addingTimeInterval(Self.countdown)
        }
        return .wait
    }

    mutating func hold() {
        sendsAt = nil
        held = true
    }
}

/// The keys bound to Claude Code's voice:pushToTalk in its Chat context:
/// space unless ~/.claude/keybindings.json says otherwise. Only plain keys
/// count; a combo with a modifier is left out.
enum VoiceKeys {
    static let action = "voice:pushToTalk"

    static func parse(_ data: Data?) -> Set<String> {
        var map: [String: String] = ["space": action]
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        for block in json?["bindings"] as? [[String: Any]] ?? [] where block["context"] as? String == "Chat" {
            for (key, value) in block["bindings"] as? [String: Any] ?? [:] {
                map[key.lowercased()] = value as? String
            }
        }
        return Set(map.filter { $0.value == action }.keys.compactMap(character))
    }

    private static func character(_ key: String) -> String? {
        if key == "space" { return " " }
        return key.count == 1 ? key : nil
    }
}

/// Sends a Claude dictation by itself when you stop talking (VoiceWatch),
/// so you can talk and move on to another terminal. It looks at a pane
/// only after its voice key, and only until the recording ends.
@MainActor
final class VoiceAutoSend: ObservableObject {
    static let shared = VoiceAutoSend()
    static let tick: TimeInterval = 0.25

    /// Panes counting down, with when each sends.
    @Published private(set) var countdowns: [UUID: Date] = [:]

    private var watches: [UUID: VoiceWatch] = [:]
    private var timer: Timer?
    private var keyMonitor: Any?
    private var keys: Set<String> = [" "]
    private var keysRead: Date?

    static var keybindingsPath: String { "\(NSHomeDirectory())/.claude/keybindings.json" }

    func start() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let characters = event.characters
            let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let keep = MainActor.assumeIsolated { VoiceAutoSend.shared.keyDown(characters, plain: plain) }
            return keep ? nil : event
        }
    }

    /// You pressed the voice key during a countdown, or clicked Keep
    /// talking: the message waits until you speak and go quiet again.
    func hold(_ pane: UUID) {
        watches[pane]?.hold()
        publish(pane)
    }

    /// True to keep the key from the terminal.
    private func keyDown(_ characters: String?, plain: Bool) -> Bool {
        guard let view = NSApp.keyWindow?.firstResponder as? Ghostty.SurfaceView else { return false }
        let isVoiceKey = plain && characters.map { voiceKeys().contains($0) } == true
        if countdowns[view.id] != nil {
            if isVoiceKey {
                hold(view.id)
                return true
            }
            watches[view.id]?.heard = Date()
            watches[view.id]?.sendsAt = nil
            publish(view.id)
            return false
        }
        if isVoiceKey && watches[view.id] == nil {
            watches[view.id] = VoiceWatch(since: Date())
            startTimer()
        }
        return false
    }

    private func voiceKeys() -> Set<String> {
        let modified = (try? FileManager.default.attributesOfItem(atPath: Self.keybindingsPath))?[.modificationDate] as? Date
        if modified != keysRead {
            keys = VoiceKeys.parse(FileManager.default.contents(atPath: Self.keybindingsPath))
            keysRead = modified
        }
        return keys
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { _ in
            MainActor.assumeIsolated { VoiceAutoSend.shared.tickAll() }
        }
    }

    private func tickAll() {
        let now = Date()
        for pane in Array(watches.keys) {
            guard var watch = watches[pane], let view = ContextHandoffWiring.surface(pane) else {
                watches[pane] = nil
                publish(pane)
                continue
            }
            let step = watch.update(VoiceFrame.parse(TicketDelivery.screen(of: view)), now: now)
            watches[pane] = step == .wait ? watch : nil
            if step == .send { send(view) }
            publish(pane)
        }
        if watches.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Presses the voice key in the pane: in tap mode, Claude stops
    /// recording and sends.
    private func send(_ view: Ghostty.SurfaceView) {
        guard let key = voiceKeys().sorted().first else { return }
        _ = view.surfaceModel?.perform(action: TicketDelivery.textAction(key))
    }

    private func publish(_ pane: UUID) {
        let sendsAt = watches[pane]?.sendsAt
        if countdowns[pane] != sendsAt { countdowns[pane] = sendsAt }
    }
}
#endif
