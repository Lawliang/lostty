#if os(macOS)
import Foundation
import LosttyRemote

/// At most one signal per `interval`: a change fires at once; changes in
/// the window after it fire once, at its end.
struct SignalThrottle {
    enum Decision: Equatable {
        case fireNow
        case fireAfter(TimeInterval)
        case alreadyPending
    }

    let interval: TimeInterval
    private(set) var lastFired: Date?
    private(set) var pending = false

    init(interval: TimeInterval) {
        self.interval = interval
    }

    mutating func request(now: Date) -> Decision {
        if pending { return .alreadyPending }
        if let last = lastFired, now.timeIntervalSince(last) < interval {
            pending = true
            return .fireAfter(interval - now.timeIntervalSince(last))
        }
        lastFired = now
        return .fireNow
    }

    mutating func firedPending(now: Date) {
        pending = false
        lastFired = now
    }
}

/// Lostty Mobile: wakes the phone's list when a Claude pane's task title
/// changes; tmux has no hook for title changes. Spinner frames are not
/// changes: only the title without its leading glyph counts, at most once
/// a second.
@MainActor
final class SessionTitleSignal {
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    static let shared = SessionTitleSignal()

    private let now: () -> Date
    private let schedule: Scheduler
    private let signal: () -> Void
    private var throttle = SignalThrottle(interval: 1)
    /// The cleaned title of each pane whose title is a Claude task.
    private var tasks: [UUID: String] = [:]

    init(
        now: @escaping () -> Date = Date.init,
        schedule: @escaping Scheduler = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { work() }
            }
        },
        signal: @escaping () -> Void = {
            // Not in the test host: it would write to the user's live server.
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            Task.detached(priority: .utility) { TmuxClient().signalChanged() }
        }
    ) {
        self.now = now
        self.schedule = schedule
        self.signal = signal
    }

    func titleChanged(_ id: UUID, title: String) {
        let task: String? = SessionLabel.hasClaudeGlyph(title) ? SessionLabel.cleanTitle(title) : nil
        guard tasks[id] != task else { return }
        tasks[id] = task
        switch throttle.request(now: now()) {
        case .fireNow:
            signal()
        case .fireAfter(let delay):
            schedule(delay) { [weak self] in
                guard let self else { return }
                throttle.firedPending(now: now())
                signal()
            }
        case .alreadyPending:
            break
        }
    }

    func surfaceClosed(_ id: UUID) {
        tasks[id] = nil
    }
}
#endif
