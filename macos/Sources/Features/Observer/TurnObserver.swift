#if os(macOS)
import Combine
import Foundation

/// What the mascot's bubble shows (spec §6).
enum BubbleContent: Equatable {
    /// "…": a summary is on its way (or the agent is still working).
    case waiting
    case notes(ObserverNotes)
    case message(String)
    /// A run failed: why, and the last good notes.
    case failed(String, ObserverNotes?)
}

/// App-wide: when an agent finishes a turn in a pane, reads that
/// conversation's new prompts and replies and has a summarizer update its
/// notes (spec §4). In memory only. The mascot's bubble is its first use;
/// later ones (recall, observing how you work) build on the same notes and
/// turn ends.
@MainActor
final class TurnObserver: ObservableObject {
    static let shared = TurnObserver()
    static let nothingYet = "Nothing to sum up yet."
    /// How soon a pane may move on to another conversation file.
    static let switchInterval: TimeInterval = 30
    /// Read by the nonisolated run, so not main-actor bound.
    nonisolated static let garbled = "The summary came back garbled. Tap again to retry."

    struct Dependencies {
        var enabled: @MainActor () -> Bool
        var locate: @Sendable (String) -> TranscriptLocation?
        var read: @Sendable (TranscriptLocation, UInt64) -> ConversationChunk?
        var detect: @Sendable () async -> SummarizerKind
        var summarize: @Sendable (SummarizerKind, String, RunHandle) async -> Result<String, SummaryError>
        var maxRunning = 2
        var now: @Sendable () -> Date = Date.init

        static var live: Dependencies {
            Dependencies(
                enabled: { ObserverPreferences.shared.background },
                locate: { TranscriptLocation.allowed($0) },
                read: { ConversationReader.read($0, from: $1) },
                detect: { await Task.detached(priority: .utility) { Summarizer.detect() }.value },
                summarize: { await Summarizer.run($0, prompt: $1, handle: $2) })
        }
    }

    /// One conversation file's notes and where reading it got to.
    struct Conversation: Equatable, Sendable {
        var notes: ObserverNotes?
        var offset: UInt64 = 0
        /// Your latest prompt and the reply since (ConversationReader.tail).
        var tail: [ConversationEntry] = []
        /// A turn ended since the notes were written.
        var stale = true
        var queued = false
        var running = false
        /// A turn ended during the run: run once more after it.
        var again = false
        /// The last run's failure; cleared by the next success.
        var error: String?
    }

    enum RunResult: Sendable {
        case notes(ObserverNotes, offset: UInt64, tail: [ConversationEntry])
        /// Nothing new since the notes.
        case nothingNew(offset: UInt64)
        /// The conversation has nothing to sum up.
        case empty(offset: UInt64)
        case failed(SummaryError)
    }

    /// Each pane's current conversation file (allowed paths only).
    @Published private(set) var panes: [UUID: String] = [:]
    /// By conversation file.
    @Published private(set) var conversations: [String: Conversation] = [:]
    /// nil until found (and again after a failed run, to look again).
    @Published private(set) var summarizer: SummarizerKind?

    private let deps: Dependencies
    private var queue: [String] = []
    private var running = 0
    private var handles: [String: RunHandle] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    /// Runs a tap started with the switch off: closing the bubble cancels them.
    private var tapRuns: Set<String> = []
    /// Panes whose bubble opened mid-turn: their turn's end runs even with
    /// the switch off.
    private var waitingPanes: Set<UUID> = []
    private var detecting: Task<SummarizerKind, Never>?
    /// When each pane last took a conversation file.
    private var switchedAt: [UUID: Date] = [:]

    init(deps: Dependencies = .live) {
        self.deps = deps
    }

    /// At launch: find out which summarizer to use, so the first tap knows.
    func start() {
        Task { _ = await summarizerKind() }
    }

    // MARK: - Turn ends

    func turnEnded(pane: UUID, path: String) {
        guard deps.locate(path) != nil else { return }
        if panes[pane] != path {
            // A pane moves to another conversation at most every
            // `switchInterval`, so text printed in it can't queue runs for
            // every conversation on disk.
            let now = deps.now()
            if panes[pane] != nil, let last = switchedAt[pane], now.timeIntervalSince(last) < Self.switchInterval { return }
            panes[pane] = path
            switchedAt[pane] = now
        }
        // A tap's run under way wants this turn too, or it would show the
        // reply before it as current.
        let wanted = waitingPanes.remove(pane) != nil || tapRuns.contains(path)
        var conversation = conversations[path] ?? Conversation()
        conversation.stale = true
        conversations[path] = conversation
        let enabled = deps.enabled()
        guard enabled || wanted else { return }
        request(path, byTap: !enabled)
    }

    // MARK: - The bubble

    /// The bubble opened for `pane`: start a run if its notes are out of
    /// date, or wait for the turn's end if the agent is working.
    func open(pane: UUID, working: Bool) {
        // Look again: the user may have signed in since.
        if summarizer == SummarizerKind.none { summarizer = nil }
        if working {
            waitingPanes.insert(pane)
            return
        }
        guard let path = panes[pane] else { return }
        let conversation = conversations[path] ?? Conversation()
        guard !conversation.queued, !conversation.running, conversation.stale else { return }
        request(path, byTap: !deps.enabled())
    }

    /// The bubble closed: stop waiting, and cancel a run only it wanted.
    func close(pane: UUID) {
        waitingPanes.remove(pane)
        guard let path = panes[pane], tapRuns.remove(path) != nil else { return }
        if var conversation = conversations[path], conversation.queued {
            conversation.queued = false
            conversations[path] = conversation
            queue.removeAll { $0 == path }
        } else {
            handles[path]?.cancel()
            tasks[path]?.cancel()
        }
    }

    func content(pane: UUID, working: Bool) -> BubbleContent {
        if summarizer == SummarizerKind.none { return .message(Summarizer.noSummarizer) }
        if working { return .waiting }
        guard let path = panes[pane] else { return .message(Self.nothingYet) }
        let conversation = conversations[path] ?? Conversation()
        if conversation.queued || conversation.running { return .waiting }
        if let error = conversation.error { return .failed(error, conversation.notes) }
        if let notes = conversation.notes { return conversation.stale ? .waiting : .notes(notes) }
        return conversation.stale ? .waiting : .message(Self.nothingYet)
    }

    // MARK: - Panes

    func surfaceClosed(_ pane: UUID) {
        panes[pane] = nil
        switchedAt[pane] = nil
        waitingPanes.remove(pane)
    }

    /// Each pane's conversation file, for Restart to Update to hand on.
    func carry() -> [UUID: String] { panes }

    func restore(_ carried: [UUID: String]) {
        for (pane, path) in carried where deps.locate(path) != nil {
            panes[pane] = path
        }
    }

    // MARK: - Runs

    private func request(_ path: String, byTap: Bool = false) {
        var conversation = conversations[path] ?? Conversation()
        if conversation.running {
            conversation.again = true
            conversations[path] = conversation
            return
        }
        guard !conversation.queued else { return }
        conversation.queued = true
        conversations[path] = conversation
        if byTap { tapRuns.insert(path) }
        queue.append(path)
        pump()
    }

    private func pump() {
        while running < deps.maxRunning, !queue.isEmpty {
            begin(queue.removeFirst())
        }
    }

    private func begin(_ path: String) {
        var conversation = conversations[path] ?? Conversation()
        conversation.queued = false
        conversation.running = true
        conversation.again = false
        conversations[path] = conversation
        running += 1
        let handle = RunHandle()
        handles[path] = handle
        let snapshot = conversation
        let locate = deps.locate, read = deps.read, summarize = deps.summarize
        tasks[path] = Task {
            let kind = await self.summarizerKind()
            let result = await Self.run(
                path: path, conversation: snapshot, kind: kind,
                locate: locate, read: read, summarize: summarize, handle: handle)
            self.finish(path, result, kind: kind)
        }
    }

    private func finish(_ path: String, _ result: RunResult, kind: SummarizerKind) {
        running -= 1
        handles[path] = nil
        tasks[path] = nil
        tapRuns.remove(path)
        var conversation = conversations[path] ?? Conversation()
        conversation.running = false
        switch result {
        case .notes(let notes, let offset, let tail):
            conversation.notes = notes
            conversation.offset = offset
            conversation.tail = tail
            conversation.error = nil
            conversation.stale = conversation.again
        case .nothingNew(let offset):
            conversation.offset = offset
            conversation.error = nil
            conversation.stale = conversation.again
        case .empty(let offset):
            conversation.notes = nil
            conversation.tail = []
            conversation.offset = offset
            conversation.error = nil
            conversation.stale = conversation.again
        case .failed(.cancelled):
            break
        case .failed(let error):
            conversation.error = error.message
            // A lapsed sign-in shows up as a failure: look again next time.
            if kind != .none { summarizer = nil }
        }
        let again = conversation.again
        conversation.again = false
        conversations[path] = conversation
        if again { request(path) }
        pump()
    }

    private func summarizerKind() async -> SummarizerKind {
        if let summarizer { return summarizer }
        let task: Task<SummarizerKind, Never>
        if let detecting {
            task = detecting
        } else {
            let detect = deps.detect
            task = Task { await detect() }
            detecting = task
        }
        let kind = await task.value
        detecting = nil
        summarizer = kind
        return kind
    }

    /// Reads what's new and asks for updated notes. Off the main actor: a
    /// first read can be a large file.
    nonisolated private static func run(
        path: String,
        conversation: Conversation,
        kind: SummarizerKind,
        locate: @Sendable (String) -> TranscriptLocation?,
        read: @Sendable (TranscriptLocation, UInt64) -> ConversationChunk?,
        summarize: @Sendable (SummarizerKind, String, RunHandle) async -> Result<String, SummaryError>,
        handle: RunHandle
    ) async -> RunResult {
        guard kind != .none else { return .failed(.failed(Summarizer.noSummarizer)) }
        guard let location = locate(path), let chunk = read(location, conversation.offset) else {
            return .failed(.failed("Couldn't read this conversation."))
        }
        let previous = chunk.restarted ? nil : conversation.notes
        let oldTail = chunk.restarted ? [] : conversation.tail
        if chunk.entries.isEmpty {
            return chunk.restarted || conversation.notes == nil ? .empty(offset: chunk.offset) : .nothingNew(offset: chunk.offset)
        }
        let tail = ConversationReader.tail(oldTail, adding: chunk.entries)
        let earlier = chunk.entries.lastIndex { $0.speaker == .you }.map { Array(chunk.entries[...$0]) } ?? []
        let prompt = ObserverPrompt.build(
            previous: previous, earlier: earlier, lastReply: ConversationReader.lastReply(tail), words: kind.words)
        guard !handle.isCancelled, !Task.isCancelled else { return .failed(.cancelled) }
        switch await summarize(kind, prompt, handle) {
        case .success(let text):
            guard let notes = ObserverPrompt.parse(text) else { return .failed(.failed(garbled)) }
            return .notes(notes, offset: chunk.offset, tail: tail)
        case .failure(let error):
            return .failed(error)
        }
    }
}
#endif
