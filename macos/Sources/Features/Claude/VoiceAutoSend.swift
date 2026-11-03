#if os(macOS)
import AppKit
import Foundation
import GhosttyKit
import os

/// What a Claude pane shows while it records a dictation in tap mode:
/// the words in its input box so far, which Claude fills in as you talk.
/// Its sound-level bar is left out: room noise keeps it from ever
/// reading quiet.
struct VoiceFrame: Equatable {
    var words: String
    /// Screen rows of the input box's bottom line and of the footer.
    var ruleRow: Int?
    var footerRow: Int?

    static let marker = "REC · tap to send"
    static let bars: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    /// The frame on a pane's screen, or nil when Claude isn't recording.
    static func parse(_ screen: String) -> VoiceFrame? {
        let lines = screen.components(separatedBy: "\n")
        guard let footer = lines.lastIndex(where: { $0.contains(marker) }),
              let start = lines[..<footer].lastIndex(where: { $0.hasPrefix("❯") }) else { return nil }
        var text: [String] = []
        var rule: Int?
        for (index, line) in lines[start..<footer].enumerated() {
            if index > 0 && line.hasPrefix("─") {
                rule = start + index
                break
            }
            text.append(index == 0 ? String(line.dropFirst()) : line)
        }
        let words = text.joined(separator: " ")
            .filter { !bars.contains($0) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return VoiceFrame(words: words, ruleRow: rule, footerRow: footer)
    }
}

/// One pane's dictation, from its voice key on: once words have come in
/// and none has for `quiet` seconds, a `countdown` starts, and when it runs
/// out Lostty sends the message. New words call the countdown off, and so
/// does `hold()` (the voice key pressed during it) until you say more:
/// Claude touching up the words already there (punctuation, a word
/// heard better, the last words landing just after the hold) doesn't
/// count.
struct VoiceWatch: Equatable {
    /// The buffer after your last word: no countdown shows yet, so the
    /// voice key goes to Claude and sends right away.
    static let quiet: TimeInterval = 1
    static let countdown: TimeInterval = 3
    /// How long Claude may take to start recording after the key.
    static let warmup: TimeInterval = 5
    /// How long the recording mark may be missing (a frame mid-redraw)
    /// before the recording counts as over.
    static let gone: TimeInterval = 1
    /// After a hold, how long late words still count as said before it.
    static let settle: TimeInterval = 1.5

    enum Step: Equatable { case wait, send, stop }

    var since: Date
    var words = ""
    var heard: Date?
    var seen: Date?
    var sendsAt: Date?
    var ruleRow: Int?
    var footerRow: Int?
    /// The word count when you held, and when.
    var heldCount: Int?
    var heldAt: Date?

    init(since: Date) { self.since = since }

    mutating func update(_ frame: VoiceFrame?, now: Date) -> Step {
        guard let frame else {
            sendsAt = nil
            let limit = seen == nil ? Self.warmup : Self.gone
            return now.timeIntervalSince(seen ?? since) > limit ? .stop : .wait
        }
        seen = now
        ruleRow = frame.ruleRow
        footerRow = frame.footerRow
        if frame.words != words {
            words = frame.words
            heard = now
            sendsAt = nil
            if let heldCount, let heldAt {
                let count = Self.count(words)
                if now.timeIntervalSince(heldAt) < Self.settle {
                    self.heldCount = max(heldCount, count)
                } else if count > heldCount {
                    self.heldCount = nil
                    self.heldAt = nil
                }
            }
            return .wait
        }
        if let sendsAt { return now >= sendsAt ? .send : .wait }
        if let heard, heldCount == nil, now.timeIntervalSince(heard) >= Self.quiet {
            sendsAt = now.addingTimeInterval(Self.countdown)
        }
        return .wait
    }

    mutating func hold(now: Date = Date()) {
        sendsAt = nil
        heldCount = Self.count(words)
        heldAt = now
    }

    private static func count(_ words: String) -> Int {
        words.split(whereSeparator: \.isWhitespace).count
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

/// A pane's countdown as its badge draws it: when it sends, and where
/// Claude's footer sits in the pane (points from its top left), when
/// Lostty could find it.
struct VoiceCountdown: Equatable {
    var sendsAt: Date
    var footerY: CGFloat?
    var left: CGFloat = 0
    var key = "`"

    func secondsLeft(at date: Date) -> Int {
        max(1, Int(sendsAt.timeIntervalSince(date).rounded(.up)))
    }
}

/// Sends a Claude dictation by itself when you stop talking (VoiceWatch),
/// so you can talk and move on to another terminal. It looks at a pane
/// only after its voice key, and only until the recording ends.
@MainActor
final class VoiceAutoSend: ObservableObject {
    static let shared = VoiceAutoSend()
    static let tick: TimeInterval = 0.25
    private static let log = Logger(subsystem: "com.lawliang.lostty", category: "voice")

    /// Panes counting down.
    @Published private(set) var countdowns: [UUID: VoiceCountdown] = [:]

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
            Self.log.notice("voice key in pane \(view.id.uuidString, privacy: .public): watching")
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
            if step != .wait { Self.log.notice("pane \(pane.uuidString, privacy: .public): \(String(describing: step), privacy: .public)") }
            if step == .send { send(view) }
            publish(pane, view: view)
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

    private func publish(_ pane: UUID, view: Ghostty.SurfaceView? = nil) {
        guard let watch = watches[pane], let sendsAt = watch.sendsAt else {
            if countdowns[pane] != nil { countdowns[pane] = nil }
            return
        }
        guard countdowns[pane]?.sendsAt != sendsAt, let view = view ?? ContextHandoffWiring.surface(pane) else { return }
        let rule = watch.ruleRow.flatMap { Self.rowCentre(view, row: $0) }
        let footer = watch.footerRow.flatMap { Self.rowCentre(view, row: $0) }
        let key = voiceKeys().sorted().first.map { $0 == " " ? "space" : $0 } ?? "`"
        countdowns[pane] = VoiceCountdown(
            sendsAt: sendsAt, footerY: footer?.y, left: rule?.x ?? footer?.x ?? 0, key: key)
    }

    /// The middle of a screen row, and its left edge, in the pane's
    /// points: Ghostty reports a read's baseline, about 0.3 of a row
    /// below the middle.
    private static func rowCentre(_ view: Ghostty.SurfaceView, row: Int) -> CGPoint? {
        guard let surface = view.surface, row >= 0 else { return nil }
        let point = ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: UInt32(row))
        var text = ghostty_text_s()
        let selection = ghostty_selection_s(top_left: point, bottom_right: point, rectangle: false)
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard text.tl_px_y >= 0 else { return nil }
        return CGPoint(x: text.tl_px_x, y: text.tl_px_y - view.cellSize.height * 0.3)
    }
}
#endif
