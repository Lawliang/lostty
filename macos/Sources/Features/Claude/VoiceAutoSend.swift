#if os(macOS)
import AppKit
import Foundation
import os

/// What a Claude pane shows while it records a dictation in tap mode:
/// the words in its input box so far, which Claude fills in as you talk,
/// and its sound-level bar (1, quiet, to 8, loud; nil when Claude draws
/// no bar).
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
        let words = joined
            .filter { !bars.contains($0) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return VoiceFrame(words: words, level: level)
    }
}

/// One pane's dictation, from its voice key on: once words have come in
/// and none has for `quiet` seconds, an unseen `countdown` starts, and
/// when it runs out Lostty sends the message. New words call it off. A
/// sound bar `maybeSpeech` levels over the quietest it has read (the
/// room's) may be you talking again before Claude writes the words, so
/// the send waits `listen` seconds past it.
struct VoiceWatch: Equatable {
    /// The pause after your last word before the countdown starts.
    static let quiet: TimeInterval = 1
    static let countdown: TimeInterval = 3
    /// How far over the room's level counts as maybe speech.
    static let maybeSpeech = 2
    /// How long the send waits after maybe speech, for its words.
    static let listen: TimeInterval = 2
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
    /// The quietest bar so far: the room.
    var room: Int?

    init(since: Date) { self.since = since }

    mutating func update(_ frame: VoiceFrame?, now: Date) -> Step {
        guard let frame else {
            sendsAt = nil
            let limit = seen == nil ? Self.warmup : Self.gone
            return now.timeIntervalSince(seen ?? since) > limit ? .stop : .wait
        }
        seen = now
        var loud = false
        if let level = frame.level {
            let room = min(self.room ?? level, level)
            self.room = room
            loud = level >= room + Self.maybeSpeech
        }
        if frame.words != words {
            words = frame.words
            heard = now
            sendsAt = nil
            return .wait
        }
        if let sendsAt {
            let waits = loud ? max(sendsAt, now.addingTimeInterval(Self.listen)) : sendsAt
            self.sendsAt = waits
            return now >= waits ? .send : .wait
        }
        if let heard, now.timeIntervalSince(heard) >= Self.quiet {
            sendsAt = now.addingTimeInterval(Self.countdown)
        }
        return .wait
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
/// so you can talk and move on to another terminal. Nothing shows while
/// it waits. It looks at a pane only after its voice key, and only until
/// the recording ends; typing in the pane puts the send off.
@MainActor
final class VoiceAutoSend {
    static let shared = VoiceAutoSend()
    static let tick: TimeInterval = 0.25
    private static let log = Logger(subsystem: "com.lawliang.lostty", category: "voice")

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
            let plain = event.modifierFlags.isDisjoint(with: [.command, .control, .option])
            MainActor.assumeIsolated { VoiceAutoSend.shared.keyDown(characters, plain: plain) }
            return event
        }
    }

    private func keyDown(_ characters: String?, plain: Bool) {
        guard let view = NSApp.keyWindow?.firstResponder as? Ghostty.SurfaceView else { return }
        let isVoiceKey = plain && characters.map { voiceKeys().contains($0) } == true
        if watches[view.id] != nil {
            // The voice key goes to Claude, which stops and sends; any other
            // key is you editing, so the send waits.
            if !isVoiceKey {
                watches[view.id]?.heard = Date()
                watches[view.id]?.sendsAt = nil
            }
            return
        }
        if isVoiceKey {
            watches[view.id] = VoiceWatch(since: Date())
            Self.log.notice("voice key in pane \(view.id.uuidString, privacy: .public): watching")
            startTimer()
        }
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
                continue
            }
            let step = watch.update(VoiceFrame.parse(TicketDelivery.screen(of: view)), now: now)
            watches[pane] = step == .wait ? watch : nil
            if step != .wait { Self.log.notice("pane \(pane.uuidString, privacy: .public): \(String(describing: step), privacy: .public)") }
            if step == .send { send(view) }
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
}
#endif
