import Foundation

/// A pane's recent lines, read in one go so the phone can scroll them itself:
/// the wheel sends tmux one event per line and waits for its redraw, a round
/// trip each, so the text trails the finger and moves a whole line at a time.
public struct PaneHistory: Equatable, Sendable {
    /// The pane's size in cells.
    public var cols: Int
    public var rows: Int
    /// Oldest first, ending with the screen; each with tmux's colour codes.
    public var lines: [Data]
    /// The pane scrolls itself: a full-screen program (vim, less), one that
    /// takes the mouse, or tmux's copy mode already scrolled. The wheel
    /// belongs to it.
    public var takesWheel: Bool

    public init(cols: Int, rows: Int, lines: [Data], takesWheel: Bool) {
        self.cols = cols
        self.rows = rows
        self.lines = lines
        self.takesWheel = takesWheel
    }

    /// Lines above the screen.
    public var scrollback: Int { max(0, lines.count - rows) }

    /// How far back to read. A thousand lines is a long way to scroll on a
    /// phone, and stays small enough to arrive while the finger moves.
    public static let defaultLines = 1000

    static let marker = "lostty-history"

    /// The pane's size and whether it takes the wheel, then its last
    /// `lines` lines above the screen and the screen. Copy mode the wheel
    /// started (tmux.conf colours its cursor #010203) ends first: the phone
    /// scrolls instead, and left on it would send every scroll after to
    /// the wheel. Copy mode someone chose stays.
    public static func command(sessionID: String, lines: Int) throws -> String {
        guard TmuxRemote.isSessionID(sessionID) else { throw TmuxRemoteError.badSessionID(sessionID) }
        let target = TmuxRemote.shellQuote(sessionID)
        let wheelCopyMode = "#{&&:#{pane_in_mode},#{==:#{cursor-colour},#010203}}"
        // The same test as tmux.conf's WheelUpPane binding.
        let format = "\(marker) #{pane_width} #{pane_height} #{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}"
        return "\(TmuxRemote.tmux) if-shell -F -t \(target) \(TmuxRemote.shellQuote(wheelCopyMode))"
            // tmux takes a block only in its own command strings: one, quoted.
            + " " + TmuxRemote.shellQuote("send-keys -X -t '\(sessionID)' cancel")
            + " \\; display-message -p -t \(target) \(TmuxRemote.shellQuote(format))"
            + " \\; capture-pane -p -e -S -\(lines) -t \(target)"
    }

    public static func parse(_ output: Data) -> PaneHistory? {
        guard let newline = output.firstIndex(of: 0x0A) else { return nil }
        let header = String(decoding: output[output.startIndex..<newline], as: UTF8.self).split(separator: " ")
        guard header.count == 4, header[0] == marker,
              let cols = Int(header[1]), let rows = Int(header[2]), cols > 0, rows > 0 else { return nil }
        var body = output[output.index(after: newline)...]
        if body.last == 0x0A { body = body.dropLast() }
        let lines = body.split(separator: 0x0A, omittingEmptySubsequences: false).map { Data($0) }
        return PaneHistory(cols: cols, rows: rows, lines: lines, takesWheel: header[3] == "1")
    }

    /// The bytes that draw it on a fresh terminal of the pane's width, the
    /// newest line at the bottom, with no cursor.
    public var feed: Data {
        var out = Data("\u{1B}[?25l".utf8)
        for (index, line) in lines.enumerated() {
            if index > 0 { out.append(Self.lineBreak) }
            out.append(line)
        }
        return out
    }

    /// tmux carries colours over from one line to the next, but a line that
    /// scrolls in takes the current background, all the way across. So:
    /// save the colours with the cursor, break the line with none, then
    /// take them back and step down to the new line's start.
    static let lineBreak = Data("\u{1B}7\u{1B}[0m\r\n\u{1B}8\u{1B}[B\r".utf8)
}

/// A `PaneHistory` drawn in blocks of `chunkRows` lines each, stacked in
/// order and only ever moved: a terminal scrolling its own lines redraws a
/// frame behind a move, so text drawn once and moved can't snap. Offsets
/// are points scrolled back from the newest line; positions are in the
/// terminal view's points.
public struct HistoryLayout: Equatable, Sendable {
    /// One line, in points.
    public var lineHeight: Double
    /// All of the history's lines, and how many of them the screen shows.
    public var lines: Int
    public var rows: Int
    /// Lines per block.
    public var chunkRows: Int
    /// The screen's padding above its first line, and its height.
    public var top: Double
    public var height: Double

    public init(lineHeight: Double, lines: Int, rows: Int, chunkRows: Int, top: Double, height: Double) {
        self.lineHeight = lineHeight
        self.lines = lines
        self.rows = rows
        self.chunkRows = chunkRows
        self.top = top
        self.height = height
    }

    /// Back as far as the oldest line, at the top of the screen.
    public var maxOffset: Double { Double(max(0, lines - rows)) * lineHeight }

    public func clamped(_ offset: Double) -> Double {
        min(max(offset, 0), maxOffset)
    }

    public var chunkCount: Int { (lines + chunkRows - 1) / chunkRows }

    /// Where block `chunk`'s first line sits: at the bottom (offset 0) the
    /// screen's lines are where the live terminal draws them.
    public func chunkTop(_ chunk: Int, offset: Double) -> Double {
        top + Double(chunk * chunkRows - (lines - rows)) * lineHeight + offset
    }

    /// The blocks any of the screen shows.
    public func visibleChunks(offset: Double) -> ClosedRange<Int> {
        let first = (-top - offset) / lineHeight + Double(lines - rows)
        let last = (height - top - offset) / lineHeight + Double(lines - rows)
        let firstLine = min(max(Int(first.rounded(.down)), 0), lines - 1)
        let lastLine = min(max(Int(last.rounded(.down)), firstLine), lines - 1)
        return (firstLine / chunkRows)...(lastLine / chunkRows)
    }
}

extension PaneHistory {
    /// The bytes that draw block `chunk` (lines `chunk * rows` on) on a
    /// fresh terminal `rows` lines tall: the colours in effect where it
    /// starts, then its lines, with no cursor.
    public func chunkFeed(_ chunk: Int, rows: Int) -> Data {
        let start = min(chunk * rows, lines.count)
        let end = min(start + rows, lines.count)
        var out = Data("\u{1B}[?25l".utf8)
        out.append(carriedStyle(at: start))
        for index in start..<end {
            if index > start { out.append(Self.lineBreak) }
            out.append(lines[index])
        }
        return out
    }

    /// The colour codes (SGR) still in effect at the start of line `index`:
    /// tmux writes one only when it changes, so a block starting partway
    /// replays them. Everything since the last full reset, in order.
    func carriedStyle(at index: Int) -> Data {
        var since = Data()
        for line in lines[0..<min(index, lines.count)] {
            let bytes = [UInt8](line)
            var i = 0
            while i + 1 < bytes.count {
                guard bytes[i] == 0x1B, bytes[i + 1] == UInt8(ascii: "[") else { i += 1; continue }
                var j = i + 2
                while j < bytes.count, !(0x40...0x7E).contains(bytes[j]) { j += 1 }
                guard j < bytes.count else { break }
                if bytes[j] == UInt8(ascii: "m") {
                    let params = String(decoding: bytes[(i + 2)..<j], as: UTF8.self)
                    let sequence = Data(bytes[i...j])
                    if params.isEmpty || params == "0" {
                        since = Data()
                    } else if params.hasPrefix("0;") {
                        since = sequence
                    } else {
                        since.append(sequence)
                    }
                }
                i = j + 1
            }
        }
        return since
    }
}
