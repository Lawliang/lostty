#if os(iOS)
import Foundation
import GhosttyKit
import LocalAuthentication
import LosttyRemote
import Network
import SwiftUI

/// Lostty Mobile's state: the Mac to reach, the key, the session list, and
/// the open terminal's connection, which it restarts when the app returns
/// to the foreground or the network changes.
@MainActor
final class MobileStore: ObservableObject {
    @Published var settings: RemoteHostSettings
    @Published private(set) var sessions: [RemoteSession] = []
    @Published private(set) var loading = false
    @Published var message: String?

    /// One Face ID approval per foreground period.
    private var context = LAContext()
    private var key: RemoteKey?
    private let defaults: UserDefaults
    private var openIO: RemoteSurfaceIO?
    private let pathMonitor = NWPathMonitor()
    private var sawFirstPath = false
    private var lastStatus: NWPath.Status?
    private var lastInterfaceTypes: Set<NWInterface.InterfaceType> = []
    private var wasBackgrounded = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = RemoteHostSettings.load(from: defaults)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let types = Set([NWInterface.InterfaceType.wifi, .cellular, .wiredEthernet].filter { path.usesInterfaceType($0) })
            let status = path.status
            Task { @MainActor in self?.networkChanged(status, types) }
        }
        pathMonitor.start(queue: .main)
    }

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty", isDirectory: true)
    }

    var knownHosts: KnownHosts { KnownHosts(fileURL: Self.supportDir.appendingPathComponent("known_hosts")) }

    /// What to show for an error: network failures read as "couldn't reach".
    private func describe(_ error: Error) -> String {
        guard let host = settings.remoteHost else { return (error as? RemoteError)?.message ?? error.localizedDescription }
        return RemoteError.describe(error, host: host)
    }

    /// Drops the pinned host key for the Mac in the settings, so the next
    /// connect trusts whatever key it offers.
    func forgetHostKey() {
        #if DEBUG
        if isGallery { return }
        #endif
        // The pins are written under the trimmed addresses, so forget them there.
        let hosts = settings.remoteHosts
        guard !hosts.isEmpty else {
            message = settings.problem
            return
        }
        do {
            for host in hosts { try knownHosts.forget(host: host.host, port: host.port) }
            message = "Forgot the Mac's host key. The next connection will trust the key it offers."
        } catch {
            message = error.localizedDescription
        }
    }

    /// A terminal closed by itself. If the session is still on the Mac, the
    /// attach failed rather than the session ending.
    func terminalClosedItself(_ session: RemoteSession) async {
        await refresh()
        if sessions.contains(where: { $0.id == session.id && $0.name == session.name }) {
            message = "Couldn't open \(session.name). Check that tmux runs on the Mac and that Phone Access shows Terminal definition ✓."
        }
    }

    func saveSettings() {
        settings.save(to: defaults)
    }

    /// The SSH key, loaded once; Face ID is asked through the shared context.
    func remoteKey() throws -> RemoteKey {
        if let key { return key }
        #if targetEnvironment(simulator)
        let loaded = try RemoteKey.software(storedAt: Self.supportDir.appendingPathComponent("simulator-key"))
        #else
        let loaded = try RemoteKey.secureEnclave(storedAt: Self.supportDir.appendingPathComponent("remote-key"), context: context)
        #endif
        key = loaded
        #if !targetEnvironment(simulator)
        // A restored handle on a new phone is a dead end: keep it out of backups.
        var handle = Self.supportDir.appendingPathComponent("remote-key")
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? handle.setResourceValues(values)
        #endif
        return loaded
    }

    func refresh() async {
        #if DEBUG
        if isGallery { return }
        #endif
        let hosts = settings.remoteHosts
        guard !hosts.isEmpty else {
            message = settings.problem
            return
        }
        loading = true
        defer { loading = false }
        do {
            let connection = try await RemoteConnection.connect(toFirstReachable: hosts, key: try remoteKey(), knownHosts: knownHosts)
            defer { Task { await connection.close() } }
            sessions = try await connection.sessions()
            message = sessions.isEmpty ? Self.noSessionsMessage : nil
            needsPairing = false
        } catch {
            message = describe(error)
            noteNeedsPairing(error)
        }
    }

    /// Connects to the first reachable Mac, runs `body`, and closes the
    /// connection whether it succeeded or threw.
    private func withConnection<T>(_ body: (RemoteConnection) async throws -> T) async throws -> T {
        let connection = try await RemoteConnection.connect(toFirstReachable: settings.remoteHosts, key: try remoteKey(), knownHosts: knownHosts)
        let result: T
        do {
            result = try await body(connection)
        } catch {
            await connection.close()
            throw error
        }
        await connection.close()
        return result
    }

    /// Ends the session on the Mac; false (with `message` set) when it failed.
    @discardableResult
    func kill(_ session: RemoteSession) async -> Bool {
        #if DEBUG
        if isGallery { return false }
        #endif
        guard !settings.remoteHosts.isEmpty else { return false }
        do {
            try await withConnection { connection in
                try await connection.killSession(session.id, name: session.name, device: DeviceModel.current)
            }
            sessions.removeAll { $0.id == session.id }
            return true
        } catch {
            message = describe(error)
            noteNeedsPairing(error)
            return false
        }
    }

    static let renameGoneMessage = "Couldn't rename: that session has ended."

    /// Names `session` on the Mac (blank: back to the automatic name); the
    /// Mac tab shows it too. False (with `message` set) when it failed.
    @discardableResult
    func rename(_ session: RemoteSession, to typed: String) async -> Bool {
        #if DEBUG
        if isGallery { return false }
        #endif
        guard !settings.remoteHosts.isEmpty else { return false }
        let label = SessionLabel.cleanLabel(typed)
        do {
            let renamed = try await withConnection { connection in
                try await connection.setLabel(label, sessionID: session.id, name: session.name)
            }
            guard renamed else {
                message = Self.renameGoneMessage
                return false
            }
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index].label = label }
            return true
        } catch {
            message = describe(error)
            noteNeedsPairing(error)
            return false
        }
    }

    /// A terminal view attached to `session`, with its IO; nil (with a message)
    /// when the settings or key aren't ready.
    func terminal(for session: RemoteSession, app: ghostty_app_t) -> (view: Ghostty.SurfaceView, io: RemoteSurfaceIO)? {
        #if DEBUG
        if isGallery { return nil }
        #endif
        let hosts = settings.remoteHosts
        guard !hosts.isEmpty else {
            message = settings.problem
            return nil
        }
        do {
            _ = try remoteKey()  // surface a key problem now, not after the screen opens
            let io = RemoteSurfaceIO(attacher: SSHAttacher(
                hosts: hosts,
                key: { [weak self] in
                    guard let self else { throw CancellationError() }
                    return try await self.remoteKey()
                },
                knownHosts: knownHosts,
                sessionID: session.id,
                sessionName: session.name))
            var config = Ghostty.SurfaceConfiguration()
            config.remoteIO = io
            openIO = io
            return (Ghostty.SurfaceView(app, baseConfig: config), io)
        } catch {
            message = describe(error)
            return nil
        }
    }

    /// Only clears the open IO if it is the one being closed, so a late
    /// disappear of an old screen can't drop a newer terminal.
    func terminalClosed(_ io: RemoteSurfaceIO?) {
        if openIO === io { openIO = nil }
    }

    // MARK: Live list

    /// The list is on screen; with the app active, one connection watches
    /// tmux and re-lists on every change.
    private var listVisible = false
    private var appActive = true
    private var watchTask: Task<Void, Never>?

    func listAppeared() {
        listVisible = true
        updateWatch()
    }

    func listDisappeared() {
        listVisible = false
        updateWatch()
    }

    /// Settings or pairing may have changed the Mac: watch the current one.
    func restartWatch() {
        watchTask?.cancel()
        watchTask = nil
        updateWatch()
    }

    private func updateWatch() {
        #if DEBUG
        if isGallery { return }
        #endif
        let wanted = listVisible && appActive && !settings.remoteHosts.isEmpty
        if wanted, watchTask == nil {
            watchTask = Task { [weak self] in await self?.watchLoop() }
        } else if !wanted, let task = watchTask {
            task.cancel()
            watchTask = nil
        }
    }

    private func watchLoop() async {
        var policy = ReconnectPolicy()
        while !Task.isCancelled {
            let hosts = settings.remoteHosts
            guard !hosts.isEmpty else { break }
            if sessions.isEmpty { loading = true }
            do {
                let connection = try await RemoteConnection.connect(toFirstReachable: hosts, key: try remoteKey(), knownHosts: knownHosts)
                // Leaving the list cancels this task; closing the connection
                // is what ends the watch's channel.
                let delivered = await withTaskCancellationHandler {
                    await watch(on: connection)
                } onCancel: {
                    Task { await connection.close() }
                }
                await connection.close()
                policy.watchEnded(deliveredChange: delivered)
            } catch {
                loading = false
                if Task.isCancelled { break }
                message = describe(error)
                noteNeedsPairing(error)
                // Only pairing again fixes these; don't keep knocking.
                if needsPairing { break }
            }
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(policy.nextDelay()))
        }
        if !Task.isCancelled { watchTask = nil }
    }

    /// Lists, then lists again after each change (at most every 300 ms)
    /// until the watch ends: no tmux server, or the connection dropped.
    /// True when the change stream delivered at least one event.
    private func watch(on connection: RemoteConnection) async -> Bool {
        var lastList = Date.distantPast
        var delivered = false
        func relist() async throws {
            let found = try await connection.sessions()
            lastList = Date()
            show(found)
        }
        do {
            try await relist()
        } catch {
            loading = false
            if !Task.isCancelled { message = describe(error) }
            return false
        }
        do {
            let changes = try await connection.watchChanges()
            for await _ in changes {
                delivered = true
                let wait = ListPacing.delay(sinceLastList: lastList, now: Date())
                if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
                try await relist()
            }
        } catch {
            // The watch ended: cancelled, or the connection dropped.
        }
        // One more look, so a server that went away shows the empty state.
        if !Task.isCancelled { try? await relist() }
        return delivered
    }

    private func show(_ found: [RemoteSession]) {
        sessions = found
        loading = false
        message = found.isEmpty ? Self.noSessionsMessage : nil
        needsPairing = false
    }

    // MARK: Pairing

    enum PairingPhase: Equatable {
        case idle
        case finding
        case waitingForAllow
        case testing
        case failed(String, canRetryTest: Bool)
        case done
    }

    @Published private(set) var pairing: PairingPhase = .idle
    /// The Mac refused this phone or its identity changed: show Pair Again.
    @Published private(set) var needsPairing = false
    /// Kept after the Mac allowed this phone, so a failed test can retry
    /// without scanning again.
    private var allowedPayload: PairingPayload?

    static let noSessionsMessage = "No sessions. Is Lostty open on your Mac?"

    #if DEBUG
    /// Design Gallery only: a store frozen in one state that never connects.
    private(set) var isGallery = false

    static func gallery(
        sessions: [RemoteSession] = [], message: String? = nil, pairing: PairingPhase = .idle,
        needsPairing: Bool = false, settings: RemoteHostSettings = RemoteHostSettings()
    ) -> MobileStore {
        let store = MobileStore(defaults: UserDefaults(suiteName: "lostty-design-gallery")!)
        store.isGallery = true
        store.settings = settings
        store.sessions = sessions
        store.message = message
        store.pairing = pairing
        store.needsPairing = needsPairing
        return store
    }
    #endif

    static let tailscaleHint = "Is Tailscale on and signed into the same account as your Mac?"

    /// Identifies the running pairing attempt; cancelling bumps it so a late
    /// result of an abandoned attempt is dropped.
    private var pairingAttempt = UUID()

    /// A pairing link opened from outside the app (the Camera app), waiting
    /// for the pairing screen to pick it up.
    @Published private(set) var pendingPairingLink: String?

    func openPairingLink(_ url: URL) {
        guard url.scheme == "lostty", url.host == "pair" else { return }
        pendingPairingLink = url.absoluteString
    }

    /// The waiting link, once.
    func takePendingPairingLink() -> String? {
        defer { pendingPairingLink = nil }
        return pendingPairingLink
    }

    func resetPairing() {
        #if DEBUG
        if isGallery { return }
        #endif
        pairingAttempt = UUID()
        pairing = .idle
        allowedPayload = nil
    }

    /// The user backed out: stop acting on whatever the attempt still gets.
    func cancelPairing() {
        #if DEBUG
        if isGallery { return }
        #endif
        resetPairing()
    }

    /// Scan → find the Mac nearby → send this phone's key → wait for Allow
    /// → test over Tailscale. Only a working test saves the pairing.
    func pair(link: String) async {
        #if DEBUG
        if isGallery { return }
        #endif
        switch pairing {
        case .idle, .failed: break
        default: return
        }
        pairingAttempt = UUID()
        let attempt = pairingAttempt
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let payload = try? PairingPayload(url: url)
        else {
            pairing = .failed(PairingError.invalidLink.message, canRetryTest: false)
            return
        }
        do {
            let key = try remoteKey()
            pairing = .finding
            let endpoint = try await PairingClient.find(secret: payload.secret)
            guard attempt == pairingAttempt else { return }
            pairing = .waitingForAllow
            let response = try await PairingClient.send(
                PairingRequest(publicKey: key.publicKeyLine, model: DeviceModel.current),
                to: endpoint, secret: payload.secret)
            guard attempt == pairingAttempt else { return }
            guard response.result == .allowed else {
                pairing = .failed("Your Mac declined. Try again from Phone Access.", canRetryTest: false)
                return
            }
            allowedPayload = payload
        } catch let error as PairingError {
            guard attempt == pairingAttempt else { return }
            pairing = .failed(error.message, canRetryTest: false)
            return
        } catch {
            guard attempt == pairingAttempt else { return }
            // Network and decoding errors say nothing a customer can use.
            pairing = .failed(PairingError.connectionFailed.message, canRetryTest: false)
            return
        }
        await runPairingTest(attempt: attempt)
    }

    /// Pins the Mac's key from the QR and connects over Tailscale.
    func retryPairingTest() async {
        #if DEBUG
        if isGallery { return }
        #endif
        guard case .failed(_, canRetryTest: true) = pairing else { return }
        pairingAttempt = UUID()
        await runPairingTest(attempt: pairingAttempt)
    }

    private func runPairingTest(attempt: UUID) async {
        guard attempt == pairingAttempt, let payload = allowedPayload else { return }
        pairing = .testing
        let candidate = RemoteHostSettings.paired(with: payload, at: Date())
        // Test against scratch pins; the real ones change only on success.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("pairing-known-hosts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let testHosts = KnownHosts(fileURL: scratch)
        do {
            for host in candidate.remoteHosts {
                try testHosts.pin(host: host.host, port: host.port, key: payload.hostKeyLine)
            }
            let connection = try await RemoteConnection.connect(
                toFirstReachable: candidate.remoteHosts, key: try remoteKey(), knownHosts: testHosts)
            let found: [RemoteSession]
            do {
                found = try await connection.sessions()
            } catch {
                await connection.close()
                throw error
            }
            await connection.close()
            guard attempt == pairingAttempt else { return }
            for host in candidate.remoteHosts {
                try knownHosts.pin(host: host.host, port: host.port, key: payload.hostKeyLine)
            }
            settings = candidate
            saveSettings()
            sessions = found
            message = sessions.isEmpty ? Self.noSessionsMessage : nil
            needsPairing = false
            allowedPayload = nil
            pairing = .done
        } catch {
            guard attempt == pairingAttempt else { return }
            let text = RemoteError.isUnreachable(error)
                ? "Your Mac allowed this phone, but Lostty couldn't reach it. \(Self.tailscaleHint)"
                : describe(error)
            pairing = .failed(text, canRetryTest: true)
        }
    }

    /// Errors that only pairing again fixes.
    private func noteNeedsPairing(_ error: Error) {
        switch error as? RemoteError {
        case .keyRejected?, .hostKeyChanged?: needsPairing = true
        default: break
        }
    }

    // MARK: Reconnect triggers

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            appActive = true
            updateWatch()
            // .inactive -> .active also happens for the Face ID sheet and
            // Control Center; only a real trip to the background restarts.
            if wasBackgrounded {
                wasBackgrounded = false
                openIO?.restart()
            }
        case .background:
            wasBackgrounded = true
            appActive = false
            updateWatch()
            // Face ID again after the app has been away.
            context.invalidate()
            context = LAContext()
            key = nil
        default:
            break
        }
    }

    /// Any network update after the first (Wi-Fi ↔ cellular, a new
    /// address) may have killed the connection: attach again.
    private func networkChanged(_ status: NWPath.Status, _ types: Set<NWInterface.InterfaceType>) {
        let previousStatus = lastStatus
        let previousTypes = lastInterfaceTypes
        defer {
            sawFirstPath = true
            lastStatus = status
            lastInterfaceTypes = types
        }
        guard sawFirstPath, status == .satisfied else { return }
        // Only a path that became usable, or moved to other kinds of
        // interface; flags (expensive, constrained) and VPN interfaces
        // (Tailscale) changing don't drop the connection.
        if previousStatus != .satisfied || previousTypes != types {
            openIO?.restart()
        }
    }
}
#endif
