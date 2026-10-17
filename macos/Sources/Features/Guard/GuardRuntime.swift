#if os(macOS)
import AppKit
import Foundation
import UserNotifications

/// The guard in the app (spec §7.4): answers the guard socket from the
/// approval book, shows each new request (a notification with Deny only,
/// the pane's badge, the Branches panel), and when you decide, tells the
/// agent by typing one line into its pane, only while that pane's agent
/// still runs. Your click does the typing, so it speaks for you.
@MainActor
final class GuardRuntime: ObservableObject {
    static let shared = GuardRuntime()
    static let category = "com.lawliang.lostty.guard"
    static let denyAction = "com.lawliang.lostty.guard.deny"

    @Published private(set) var book: ApprovalBook
    @Published private(set) var agentPanes: [UUID: String] = [:]
    @Published var disconnected: Set<HookAgent> = []

    struct Effects {
        var post: @MainActor (GuardRequest) -> Void
        var withdraw: @MainActor (Int) -> Void
        var type: @MainActor (UUID, String) -> Bool
        var save: @MainActor (ApprovalBook) -> Void
        var now: () -> Date

        static let live = Effects(
            post: { GuardRuntime.postNotification($0) },
            withdraw: { id in
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [GuardRuntime.notificationID(id)])
            },
            type: { pane, text in GuardRuntime.typeIntoPane(pane, text) },
            save: { GuardRuntime.save($0) },
            now: Date.init
        )
    }

    private let effects: Effects
    private var server: GuardServer?
    private var expiryTimer: Timer?
    private var hookWatch: GuardHookWatch?
    private var checkGeneration = 0
    private var lastStatus: [HookAgent: ClaudeHooksStatus] = [:]

    init(book: ApprovalBook = .init(), effects: Effects = .live) {
        self.book = book
        self.effects = effects
    }

    // MARK: Lifecycle

    /// One store per app build, like the socket.
    nonisolated static func storeURL(bundleID: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty/guard-requests-\(bundleID).json")
    }

    static var storeURL: URL { storeURL(bundleID: Bundle.main.bundleIdentifier ?? "lostty") }

    func start() {
        if let data = try? Data(contentsOf: Self.storeURL), let saved = Self.load(data) {
            book = saved
        }
        let server = GuardServer(path: GuardServer.appPath) { check in
            GuardRuntime.shared.handle(check)
        }
        do {
            try server.start()
            self.server = server
        } catch {
            Ghostty.logger.error("guard: socket failed to start: \(String(describing: error))")
        }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { GuardRuntime.shared.tick() }
        }
        checkHooks(announce: false)
        let watch = GuardHookWatch { GuardRuntime.shared.checkHooks(announce: true) }
        watch.start()
        hookWatch = watch
    }

    /// The saved book, restored: approvals come back pending.
    nonisolated static func load(_ data: Data) -> ApprovalBook? {
        (try? JSONDecoder().decode(ApprovalBook.self, from: data))?.restored()
    }

    /// Checks each installed agent's hooks off the main thread, then flags
    /// the panes of any agent not fully connected. Only a change made while
    /// the app runs announces; checkAtLaunch already offers Connect at launch.
    private func checkHooks(announce: Bool) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let agents = HookAgent.allCases.filter {
            FileManager.default.fileExists(atPath: home.appendingPathComponent($0.configDirectory).path)
        }
        checkGeneration += 1
        let generation = checkGeneration
        Task.detached {
            var fresh: [HookAgent: ClaudeHooksStatus?] = [:]
            for agent in agents { fresh[agent] = ClaudeHooksCLI().status(agent: agent) }
            await MainActor.run {
                let rt = GuardRuntime.shared
                guard generation == rt.checkGeneration else { return }
                let current = GuardHealth.merge(previous: rt.lastStatus, fresh: fresh)
                let lost = GuardHealth.newlyDisconnected(previous: rt.lastStatus, current: current)
                rt.lastStatus = current
                rt.disconnected = GuardHealth.disconnected(current)
                if announce { for agent in lost { HookNotifications.announceMissing(agent) } }
            }
        }
    }

    func tick() {
        let lapsed = book.expire(now: effects.now())
        guard !lapsed.isEmpty else { return }
        for id in lapsed { effects.withdraw(id) }
        effects.save(book.persisted())
    }

    // MARK: Requests

    func handle(_ c: GuardCheck) -> GuardReply {
        if let pane = UUID(uuidString: c.pane) { agentPanes[pane] = c.agent }
        let (reply, isNew) = book.check(c, now: effects.now())
        if isNew, let id = reply.request, let request = book.request(id) { effects.post(request) }
        effects.save(book.persisted())
        return reply
    }

    func approve(_ id: Int) { decide(id, approved: true) }
    func deny(_ id: Int) { decide(id, approved: false) }

    private func decide(_ id: Int, approved: Bool) {
        let now = effects.now()
        let ok = approved ? book.approve(id, now: now) : book.deny(id, now: now)
        guard ok, let request = book.request(id) else { return }
        effects.withdraw(id)
        effects.save(book.persisted())
        guard let pane = UUID(uuidString: request.check.pane), agentPanes[pane] != nil else { return }
        _ = effects.type(pane, Self.outcomeText(id, approved: approved))
    }

    func agentGone(_ pane: UUID) {
        agentPanes[pane] = nil
    }

    /// A pane's agent reported its state: remember the pane runs one, of
    /// this kind when known. A known kind is never forgotten for unknown.
    func agentSeen(_ pane: UUID, kind: HookAgent?) {
        if let kind {
            if agentPanes[pane] != kind.rawValue { agentPanes[pane] = kind.rawValue }
        } else if agentPanes[pane] == nil {
            agentPanes[pane] = GuardHealth.unknownAgent
        }
    }

    func pending(for pane: UUID) -> GuardRequest? {
        book.pending.first { $0.check.pane == pane.uuidString }
    }

    static func outcomeText(_ id: Int, approved: Bool) -> String {
        approved
            ? "Approved #\(id) in Lostty. Run it now, exactly as before."
            : "Denied #\(id) in Lostty. Don't run it, and don't work around it."
    }

    // MARK: Notifications

    static func notificationID(_ id: Int) -> String { "lostty-guard-\(id)" }

    static func postNotification(_ request: GuardRequest) {
        let content = UNMutableNotificationContent()
        content.title = "\(request.check.agentName) needs your approval · #\(request.id)"
        content.subtitle = request.check.groupLabel
        content.body = request.check.input
        content.categoryIdentifier = category
        content.sound = .default
        content.userInfo = ["lostty": "guard", "request": request.id, "surface": request.check.pane]
        let note = UNNotificationRequest(identifier: notificationID(request.id), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(note)
    }

    /// Deny straight from the banner; anything else opens the request,
    /// since approving means seeing the whole command (spec §7.4).
    func handle(_ response: UNNotificationResponse) -> Bool {
        let info = response.notification.request.content.userInfo
        guard info["lostty"] as? String == "guard", let id = info["request"] as? Int else { return false }
        switch response.actionIdentifier {
        case Self.denyAction: deny(id)
        case UNNotificationDismissActionIdentifier: break
        default: GuardRequestWindow.show(id)
        }
        return true
    }

    // MARK: Typing and saving

    static func typeIntoPane(_ pane: UUID, _ text: String) -> Bool {
        guard let surface = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: pane),
              let model = surface.surfaceModel else { return false }
        model.sendText(text)
        model.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .press, mods: []))
        return true
    }

    static func save(_ book: ApprovalBook) {
        let url = storeURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(book) { try? data.write(to: url, options: .atomic) }
    }
}
#endif
