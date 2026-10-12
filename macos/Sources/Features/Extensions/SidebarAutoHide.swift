#if os(macOS)
import Foundation

/// When an auto-hiding sidebar shows. Shown while the pointer is on the
/// window's right edge or on the sidebar, or while an app is open; hidden
/// `hideDelay` after none of those holds.
struct SidebarAutoHide: Equatable {
    static let hideDelay: TimeInterval = 0.5

    enum Region: Hashable {
        /// The thin reveal strip at the window's right edge.
        case edge
        /// The sidebar itself, with any open panel.
        case sidebar
    }

    enum State: Equatable {
        case hidden
        case shown
        case hiding(deadline: Date)
    }

    private(set) var state: State = .hidden
    private var appOpen = false
    private var inside: Set<Region> = []

    var isVisible: Bool { state != .hidden }

    var hideDeadline: Date? {
        if case .hiding(let deadline) = state { return deadline }
        return nil
    }

    mutating func pointer(_ region: Region, inside isInside: Bool, now: Date) {
        if isInside {
            inside.insert(region)
            state = .shown
        } else {
            inside.remove(region)
            startHidingIfIdle(now: now)
        }
    }

    mutating func appChanged(open: Bool, now: Date) {
        appOpen = open
        if open {
            state = .shown
        } else {
            startHidingIfIdle(now: now)
        }
    }

    mutating func tick(now: Date) {
        if let deadline = hideDeadline, now >= deadline { state = .hidden }
    }

    private mutating func startHidingIfIdle(now: Date) {
        guard inside.isEmpty, !appOpen, isVisible else { return }
        state = .hiding(deadline: now.addingTimeInterval(Self.hideDelay))
    }
}

/// Runs a window's `SidebarAutoHide` against the clock.
@MainActor
final class SidebarAutoHideDriver: ObservableObject {
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    @Published private(set) var machine = SidebarAutoHide()

    private let now: () -> Date
    private let schedule: Scheduler

    init(
        now: @escaping () -> Date = Date.init,
        schedule: @escaping Scheduler = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { work() }
            }
        }
    ) {
        self.now = now
        self.schedule = schedule
    }

    var isVisible: Bool { machine.isVisible }

    func pointer(_ region: SidebarAutoHide.Region, inside: Bool) {
        machine.pointer(region, inside: inside, now: now())
        armHide()
    }

    func appChanged(open: Bool) {
        machine.appChanged(open: open, now: now())
        armHide()
    }

    /// Auto-hide was just turned on or off.
    func reset(appOpen: Bool) {
        machine = SidebarAutoHide()
        if appOpen { machine.appChanged(open: true, now: now()) }
    }

    private func armHide() {
        guard let deadline = machine.hideDeadline else { return }
        schedule(max(0, deadline.timeIntervalSince(now()))) { [weak self] in
            guard let self else { return }
            self.machine.tick(now: self.now())
        }
    }
}
#endif
