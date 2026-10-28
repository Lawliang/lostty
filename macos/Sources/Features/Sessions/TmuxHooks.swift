#if os(macOS)
import LosttyRemote

/// The tmux hooks that signal `lostty-changed`, so the phone's list and the
/// Mac's watcher hear about sessions coming, going, being renamed, and
/// clients attaching or leaving, and the settings a running server must
/// pick up. tmux.conf has the same lines; the Mac sets them again for a
/// server started without them.
enum TmuxHooks {
    static let events = ["session-created", "session-closed", "session-renamed", "client-attached", "client-detached"]
    static let command = "wait-for -S \(TmuxRemote.changedChannel)"

    /// The server stays up when its last session ends: it keeps
    /// `@lostty_end_<n>`, which the phone reads after the session is gone.
    /// Lostty stops an empty one at launch (`TmuxClient.stopServerIfEmpty`).
    static let keepServer = "set -s exit-empty off"

    /// A prompt redrawn on a pane's first line ("erase from here down" from
    /// the top-left) counts to tmux as clearing the screen, and
    /// scroll-on-clear saved a copy of the prompt to the history each time:
    /// Powerlevel10k's redraws at startup and after every resize.
    static let noScrollOnClear = "set -g scroll-on-clear off"

    /// A click without a drag leaves copy mode. Without it a stray wheel tick
    /// left the pane in copy mode, cursor hidden, and clicks did nothing.
    static let copyModeTables = ["copy-mode", "copy-mode-vi"]

    /// As written in tmux.conf.
    static var confLines: [String] {
        events.map { "set-hook -g \($0) '\(command)'" } + [keepServer, noScrollOnClear]
            + copyModeTables.map { "bind-key -T \($0) MouseUp1Pane send-keys -X cancel" }
    }

    /// One `tmux` call setting all of them.
    static var setArgs: [String] {
        let hooks = events.enumerated().flatMap { index, event in
            (index == 0 ? [] : [";"]) + ["set-hook", "-g", event, command]
        }
        return hooks + [";", "set-option", "-s", "exit-empty", "off", ";", "set-option", "-g", "scroll-on-clear", "off"]
            + copyModeTables.flatMap { [";", "bind-key", "-T", $0, "MouseUp1Pane", "send-keys", "-X", "cancel"] }
    }

    /// Wakes everything waiting on the channel. `-f /dev/null`: signalling
    /// must never start a server that reads the user's ~/.tmux.conf.
    static let signalArgs = ["-f", "/dev/null"] + signalCommand

    /// The signal as a command, to chain after others with `;`.
    static let signalCommand = ["wait-for", "-S", TmuxRemote.changedChannel]
}
#endif
