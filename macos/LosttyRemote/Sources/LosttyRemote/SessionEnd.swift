import Foundation

/// What the Mac says about a session whose attach just ended.
public struct EndProbe: Equatable, Sendable {
    /// Still there: this client was detached, or the attach failed.
    public var exists: Bool
    /// `@lostty_end_<n>`: who ended it. nil: it ended by itself.
    public var tag: String?

    public init(exists: Bool, tag: String?) {
        self.exists = exists
        self.tag = tag
    }
}

/// What the phone's terminal does when its attach ends.
public enum SessionEnd: Equatable, Sendable {
    /// You ended it here (Close Session, or typing `exit`): back to the list.
    case backToList
    /// It is still on the Mac: back to the list, which says if the attach failed.
    case stillRunning
    /// Ended elsewhere: the overlay says why until Back to Sessions.
    case closed(String)

    /// Input this recent means the person typed `exit` (or Ctrl-D).
    public static let typedWindow: TimeInterval = 3
    public static let unreadable = "This terminal was closed"

    /// `probe` nil: the Mac couldn't be asked. A tag always wins over recent
    /// typing; "this phone closed it" comes only from `endedHere`, never from
    /// the tag (two phones can be the same model).
    public static func decide(probe: EndProbe?, endedHere: Bool, typedRecently: Bool) -> SessionEnd {
        if endedHere { return .backToList }
        guard let probe else { return .closed(unreadable) }
        if probe.exists { return .stillRunning }
        guard let tag = probe.tag else {
            return typedRecently ? .backToList : .closed("The shell exited")
        }
        if tag == TmuxRemote.EndTag.macClose { return .closed("Closed on your Mac") }
        if tag == TmuxRemote.EndTag.macQuit { return .closed("Lostty quit on your Mac") }
        if tag.hasPrefix(TmuxRemote.EndTag.phonePrefix) {
            let device = tag.dropFirst(TmuxRemote.EndTag.phonePrefix.count).trimmingCharacters(in: .whitespaces)
            if !device.isEmpty { return .closed("Closed from \(device)") }
        }
        return .closed(unreadable)
    }
}
