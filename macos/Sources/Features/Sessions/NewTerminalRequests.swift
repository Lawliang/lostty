#if os(macOS)
import AppKit
import Combine
import LosttyRemote

/// Lostty Mobile: terminals the phone asks for (`NewTerminalRequest`). On
/// each change in tmux, claims the requests waiting, makes a request's
/// branch if it wants one, opens a window in its folder (typing its
/// agent's command, if it has one), and answers with the new session's id, or why it couldn't.
/// The window's shell is a Lostty one, so Claude's hooks work in it.
@MainActor
final class NewTerminalRequests {
    static let shared = NewTerminalRequests()
    /// How long the new window's session has to show up in tmux.
    nonisolated static let sessionWait: TimeInterval = 10

    private var watcher: AnyCancellable?
    private weak var ghostty: Ghostty.App?
    private var checking = false
    private var checkAgain = false

    func start(_ ghostty: Ghostty.App) {
        guard watcher == nil else { return }
        self.ghostty = ghostty
        watcher = NotificationCenter.default.publisher(for: .losttySessionsChanged)
            .sink { _ in MainActor.assumeIsolated { NewTerminalRequests.shared.check() } }
        check()
    }

    /// One look at a time; a change during one looks again after it.
    private func check() {
        guard !checking else {
            checkAgain = true
            return
        }
        checking = true
        Task {
            let claimed = await Task.detached(priority: .userInitiated) { Self.claim(TmuxClient()) }.value
            for request in claimed {
                let answer = await make(request)
                await Task.detached(priority: .userInitiated) { Self.answer(request, with: answer, TmuxClient()) }.value
            }
            checking = false
            if checkAgain {
                checkAgain = false
                check()
            }
        }
    }

    /// Takes every request waiting in tmux: reads it, then unsets it, so no
    /// later look takes it again.
    nonisolated static func claim(_ client: TmuxClient) -> [NewTerminalRequest] {
        guard let options = client.run(["show-options", "-g"]) else { return [] }
        var claimed: [NewTerminalRequest] = []
        for line in options.split(separator: "\n") {
            let name = String(line.prefix { $0 != " " })
            guard let id = NewTerminalRequest.id(ofRequestOption: name),
                  let value = client.run(["show-options", "-gqv", name]) else { continue }
            client.run(["set-option", "-gu", name])
            if let request = NewTerminalRequest(encoded: value.trimmingCharacters(in: .whitespacesAndNewlines)),
               request.id == id {
                claimed.append(request)
            }
        }
        return claimed
    }

    private func make(_ request: NewTerminalRequest) async -> NewTerminalAnswer {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.folder, isDirectory: &isFolder), isFolder.boolValue else {
            return .failed("That folder isn't on your Mac anymore.")
        }
        var folder = request.folder
        if let branch = request.branch {
            let made = await Task.detached(priority: .userInitiated) {
                WorktreeMaker.make(branch: branch, in: request.folder)
            }.value
            switch made {
            case .success(let path): folder = path
            case .failure(let failure): return .failed(failure.message)
            }
        }
        guard let ghostty else { return .failed("Lostty on your Mac isn't ready yet.") }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = folder
        if let start = request.startCommand { config.initialInput = start + "\n" }
        let controller = TerminalController.newWindow(ghostty, withBaseConfig: config)
        guard let pane = controller.surfaceTree.first(where: { _ in true })?.id else {
            return .failed("Couldn't open a window on your Mac.")
        }
        let session = await Task.detached(priority: .userInitiated) { Self.session(showing: pane) }.value
        return session.map { .made(sessionID: $0) } ?? .failed("The new terminal didn't start on your Mac.")
    }

    /// The session pane `pane` shows, once its launcher has made it and
    /// its shell has named it: the phone attaches by id and name, and
    /// refuses a session whose name changed since (as the launcher's
    /// temporary one does). Still unnamed at the deadline: as it is.
    nonisolated static func session(showing pane: UUID) -> String? {
        let client = TmuxClient()
        let deadline = Date().addingTimeInterval(sessionWait)
        var found: String?
        while Date() < deadline {
            if let session = client.remoteSessions().first(where: { $0.surface == pane.uuidString }) {
                found = session.id
                if !isTemporaryName(session.name, of: pane) { return session.id }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return found
    }

    /// The launcher's name for a session until its shell renames it:
    /// "lostty-", the pane UUID's first 8 characters (lowercased), "-" and
    /// a pid (`tempName` in src/cli/tmux/session.zig).
    nonisolated static func isTemporaryName(_ name: String, of pane: UUID) -> Bool {
        name.hasPrefix("lostty-\(pane.uuidString.prefix(8).lowercased())-")
    }

    nonisolated static func answer(_ request: NewTerminalRequest, with answer: NewTerminalAnswer, _ client: TmuxClient) {
        client.run(["set-option", "-g", request.answerOption, answer.encoded, ";"] + TmuxHooks.signalCommand)
    }
}
#endif
