#if os(macOS)
import Foundation

/// One critical call the guard stopped, and what became of it.
struct GuardRequest: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case pending, approved, used, denied, expired }

    let id: Int
    let check: GuardCheck
    let created: Date
    var state: State
    /// When you approved or denied it, or when it lapsed.
    var decided: Date?
}

/// The guard's requests and approvals (spec §7.4–7.5). An approval covers
/// exactly one call, in one pane, once, for 10 minutes; a request nobody
/// answers lapses after an hour. Only `approve` grants, and only Lostty's
/// own UI calls it: nothing the guard sends can.
struct ApprovalBook: Codable, Equatable, Sendable {
    static let approvalLifetime: TimeInterval = 10 * 60
    static let requestLifetime: TimeInterval = 60 * 60
    static let historyLimit = 100

    private(set) var requests: [GuardRequest] = []
    private(set) var nextID = 1

    init() {}

    var pending: [GuardRequest] { requests.filter { $0.state == .pending } }

    func request(_ id: Int) -> GuardRequest? { requests.first { $0.id == id } }

    mutating func check(_ c: GuardCheck, now: Date) -> (reply: GuardReply, isNew: Bool) {
        _ = expire(now: now)
        if let i = requests.firstIndex(where: { $0.state == .approved && $0.check.key == c.key }) {
            requests[i].state = .used
            requests[i].decided = now
            return (.allow, false)
        }
        if let open = requests.first(where: { $0.state == .pending && $0.check.key == c.key }) {
            return (.deny(open.id), false)
        }
        let id = nextID
        nextID += 1
        requests.append(GuardRequest(id: id, check: c, created: now, state: .pending, decided: nil))
        trim()
        return (.deny(id), true)
    }

    mutating func approve(_ id: Int, now: Date) -> Bool { decide(id, .approved, now: now) }
    mutating func deny(_ id: Int, now: Date) -> Bool { decide(id, .denied, now: now) }

    private mutating func decide(_ id: Int, _ state: GuardRequest.State, now: Date) -> Bool {
        _ = expire(now: now)
        guard let i = requests.firstIndex(where: { $0.id == id }), requests[i].state == .pending else { return false }
        requests[i].state = state
        requests[i].decided = now
        return true
    }

    mutating func expire(now: Date) -> [Int] {
        var lapsed: [Int] = []
        for i in requests.indices {
            switch requests[i].state {
            case .pending where now.timeIntervalSince(requests[i].created) > Self.requestLifetime:
                lapsed.append(requests[i].id)
                requests[i].state = .expired
                requests[i].decided = now
            case .approved where now.timeIntervalSince(requests[i].decided ?? now) > Self.approvalLifetime:
                requests[i].state = .expired
                requests[i].decided = now
            default:
                break
            }
        }
        return lapsed
    }

    func persisted() -> ApprovalBook {
        var copy = self
        for i in copy.requests.indices where copy.requests[i].state == .approved {
            copy.requests[i].state = .pending
            copy.requests[i].decided = nil
        }
        return copy
    }

    /// Keeps every open request and the most recent decided ones.
    private mutating func trim() {
        let decided = requests.filter { $0.state != .pending && $0.state != .approved }
        let excess = requests.count - Self.historyLimit
        guard excess > 0 else { return }
        let drop = Set(decided.prefix(excess).map(\.id))
        requests.removeAll { drop.contains($0.id) }
    }
}
#endif
