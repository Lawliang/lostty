#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct TurnObserverTests {
    /// Conversations by path (an offset is an entry count) and a summarizer
    /// that answers only when told to.
    final class Fake: @unchecked Sendable {
        private let lock = NSLock()
        private var conversations: [String: [ConversationEntry]] = [:]
        private var waiting: [CheckedContinuation<Result<String, SummaryError>, Never>] = []
        private(set) var prompts: [String] = []
        private(set) var handles: [RunHandle] = []

        func set(_ path: String, _ entries: [ConversationEntry]) {
            lock.withLock { conversations[path] = entries }
        }

        func read(_ path: String, _ offset: UInt64) -> ConversationChunk? {
            lock.withLock {
                guard let all = conversations[path] else { return nil }
                let start = Int(offset) <= all.count ? Int(offset) : 0
                return ConversationChunk(entries: Array(all[start...]), offset: UInt64(all.count),
                                         restarted: Int(offset) > all.count)
            }
        }

        func summarize(_ prompt: String, _ handle: RunHandle) async -> Result<String, SummaryError> {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    prompts.append(prompt)
                    handles.append(handle)
                    waiting.append(continuation)
                }
            }
        }

        var started: Int { lock.withLock { prompts.count } }

        /// Answers the oldest run still waiting.
        func answer(_ result: Result<String, SummaryError>) {
            let continuation = lock.withLock { waiting.removeFirst() }
            continuation.resume(returning: result)
        }
    }

    final class Switch: @unchecked Sendable {
        var on = true
    }

    let fake = Fake()
    let toggle = Switch()
    let pane = UUID()
    let you = ConversationEntry(speaker: .you, text: "Fix the login bug")
    let agent = ConversationEntry(speaker: .agent, text: "Fixed it.")

    func makeObserver(kind: SummarizerKind = .claude("/fake/claude"), maxRunning: Int = 2) -> TurnObserver {
        let fake = self.fake
        let toggle = self.toggle
        return TurnObserver(deps: TurnObserver.Dependencies(
            enabled: { toggle.on },
            locate: { $0.hasPrefix("/ok/") ? TranscriptLocation(url: URL(fileURLWithPath: $0), agent: .claude) : nil },
            read: { fake.read($0.url.path, $1) },
            detect: { kind },
            summarize: { _, prompt, handle in await fake.summarize(prompt, handle) },
            maxRunning: maxRunning))
    }

    func reply(_ built: [String], _ justNow: String) -> Result<String, SummaryError> {
        let data = try? JSONSerialization.data(withJSONObject: ["built": built, "just_now": justNow])
        return .success(String(decoding: data ?? Data(), as: UTF8.self))
    }

    /// Waits (up to 2 s) for the observer's tasks to catch up.
    func eventually(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test func aTurnsEndUpdatesTheNotes() async {
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 1 }
        #expect(observer.content(pane: pane, working: false) == .waiting)
        #expect(fake.prompts.first?.contains("You: Fix the login bug") == true)
        #expect(fake.prompts.first?.contains("The agent's last reply:\nFixed it.") == true)
        fake.answer(reply(["Fixed login"], "It works now."))
        let notes = ObserverNotes(built: ["Fixed login"], justNow: "It works now.")
        await eventually { observer.content(pane: pane, working: false) == .notes(notes) }
        #expect(observer.content(pane: pane, working: false) == .notes(notes))
        // The agent working again: wait for its new reply.
        #expect(observer.content(pane: pane, working: true) == .waiting)
    }

    @Test func laterRunsSendOnlyWhatsNew() async {
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 1 }
        fake.answer(reply(["Fixed login"], "It works now."))
        await eventually { observer.content(pane: pane, working: false) != .waiting }

        fake.set("/ok/a", [you, agent, ConversationEntry(speaker: .you, text: "Now add tests"),
                           ConversationEntry(speaker: .agent, text: "Added two tests.")])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 2 }
        let second = fake.prompts[1]
        #expect(second.contains(#""built":["Fixed login"]"#))
        #expect(second.contains("You: Now add tests"))
        #expect(!second.contains("Fix the login bug"))
        #expect(second.contains("The agent's last reply:\nAdded two tests."))
        fake.answer(reply(["Fixed login", "Added tests"], "Tests pass."))
    }

    @Test func turnsDuringARunQueueJustOneMore() async {
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 1 }
        // Two more turns while it runs (a run with nothing new asks nobody).
        fake.set("/ok/a", [you, agent, ConversationEntry(speaker: .you, text: "more"),
                           ConversationEntry(speaker: .agent, text: "ok")])
        observer.turnEnded(pane: pane, path: "/ok/a")
        observer.turnEnded(pane: pane, path: "/ok/a")
        fake.answer(reply(["a"], "b"))
        await eventually { fake.started == 2 }
        #expect(observer.content(pane: pane, working: false) == .waiting)
        fake.answer(reply(["a"], "c"))
        await eventually { observer.content(pane: pane, working: false) == .notes(ObserverNotes(built: ["a"], justNow: "c")) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.started == 2)
    }

    @Test func atMostTwoRunAtOnce() async {
        let observer = makeObserver()
        for name in ["a", "b", "c"] {
            fake.set("/ok/\(name)", [you, agent])
            observer.turnEnded(pane: UUID(), path: "/ok/\(name)")
        }
        await eventually { fake.started == 2 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.started == 2)
        fake.answer(reply([], "done"))
        await eventually { fake.started == 3 }
        #expect(fake.started == 3)
        fake.answer(reply([], "done"))
        fake.answer(reply([], "done"))
    }

    @Test func withTheSwitchOffOnlyATapRuns() async {
        toggle.on = false
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.started == 0)
        observer.open(pane: pane, working: false)
        await eventually { fake.started == 1 }
        #expect(fake.started == 1)
        fake.answer(reply([], "hi"))
    }

    @Test func aTapMidTurnWaitsForTheTurnToEnd() async {
        toggle.on = false
        let observer = makeObserver()
        observer.open(pane: pane, working: true)
        #expect(observer.content(pane: pane, working: true) == .waiting)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.started == 0)
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 1 }
        #expect(fake.started == 1)
        fake.answer(reply([], "hi"))
    }

    @Test func closingCancelsOnlyATapsRun() async {
        toggle.on = false
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        observer.open(pane: pane, working: false)
        await eventually { fake.started == 1 }
        observer.close(pane: pane)
        #expect(fake.handles[0].isCancelled)
        fake.answer(.failure(.cancelled))

        toggle.on = true
        let other = UUID()
        fake.set("/ok/b", [you, agent])
        observer.turnEnded(pane: other, path: "/ok/b")
        await eventually { fake.started == 2 }
        observer.open(pane: other, working: false)
        observer.close(pane: other)
        #expect(!fake.handles[1].isCancelled)
        fake.answer(reply([], "kept"))
    }

    @Test func aPathOutsideTheAllowedFoldersIsIgnored() async {
        let observer = makeObserver()
        observer.turnEnded(pane: pane, path: "/Users/me/.ssh/id_ed25519")
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.started == 0)
        #expect(observer.content(pane: pane, working: false) == .message(TurnObserver.nothingYet))
    }

    @Test func aGarbledReplyKeepsTheLastNotes() async {
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 1 }
        fake.answer(reply(["Fixed login"], "It works now."))
        await eventually { observer.content(pane: pane, working: false) != .waiting }
        fake.set("/ok/a", [you, agent, ConversationEntry(speaker: .you, text: "more"),
                           ConversationEntry(speaker: .agent, text: "ok")])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { fake.started == 2 }
        fake.answer(.success("not json"))
        let notes = ObserverNotes(built: ["Fixed login"], justNow: "It works now.")
        await eventually { observer.content(pane: pane, working: false) != .waiting }
        #expect(observer.content(pane: pane, working: false) == .failed(TurnObserver.garbled, notes))
    }

    @Test func anEmptyConversationHasNothingToSumUp() async {
        let observer = makeObserver()
        fake.set("/ok/a", [])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { observer.content(pane: pane, working: false) != .waiting }
        #expect(observer.content(pane: pane, working: false) == .message(TurnObserver.nothingYet))
        #expect(fake.started == 0)
    }

    @Test func noSummarizerSaysHowToGetOne() async {
        let observer = makeObserver(kind: .none)
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        await eventually { observer.content(pane: pane, working: false) == .message(Summarizer.noSummarizer) }
        #expect(observer.content(pane: pane, working: false) == .message(Summarizer.noSummarizer))
        #expect(fake.started == 0)
    }

    @Test func aRestartCarriesEachPanesConversation() async {
        toggle.on = false
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        observer.turnEnded(pane: pane, path: "/ok/a")
        #expect(observer.carry() == [pane: "/ok/a"])

        let next = makeObserver()
        next.restore([pane: "/ok/a", UUID(): "/etc/passwd"])
        #expect(next.carry() == [pane: "/ok/a"])
        next.open(pane: pane, working: false)
        await eventually { fake.started == 1 }
        #expect(fake.started == 1)
        fake.answer(reply([], "hi"))
    }

    @Test func aClosedPaneIsForgotten() {
        let observer = makeObserver()
        fake.set("/ok/a", [you, agent])
        toggle.on = false
        observer.turnEnded(pane: pane, path: "/ok/a")
        observer.surfaceClosed(pane)
        #expect(observer.carry().isEmpty)
    }
}
#endif
