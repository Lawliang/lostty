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
            message = "Couldn't open \(session.name). Check that tmux runs on the Mac."
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
            sessions = RemoteSession.forPicking(try await connection.sessions())
            message = sessions.isEmpty ? Self.noSessionsMessage : nil
            needsPairing = false
        } catch {
            message = describe(error)
            noteNeedsPairing(error)
        }
    }

    /// Ends the session on the Mac; false (with `message` set) when it failed.
    @discardableResult
    func kill(_ session: RemoteSession) async -> Bool {
        let hosts = settings.remoteHosts
        guard !hosts.isEmpty else { return false }
        do {
            let connection = try await RemoteConnection.connect(toFirstReachable: hosts, key: try remoteKey(), knownHosts: knownHosts)
            do {
                try await connection.killSession(session.id, name: session.name)
            } catch {
                await connection.close()
                throw error
            }
            await connection.close()
            sessions.removeAll { $0.id == session.id }
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
    static let tailscaleHint = "Is Tailscale on and signed into the same account as your Mac?"

    /// Identifies the running pairing attempt; cancelling bumps it so a late
    /// result of an abandoned attempt is dropped.
    private var pairingAttempt = UUID()

    func resetPairing() {
        pairingAttempt = UUID()
        pairing = .idle
        allowedPayload = nil
    }

    /// The user backed out: stop acting on whatever the attempt still gets.
    func cancelPairing() {
        resetPairing()
    }

    /// Scan → find the Mac nearby → send this phone's key → wait for Allow
    /// → test over Tailscale. Only a working test saves the pairing.
    func pair(link: String) async {
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
            pairing = .failed(describe(error), canRetryTest: false)
            return
        }
        await runPairingTest(attempt: attempt)
    }

    /// Pins the Mac's key from the QR and connects over Tailscale.
    func retryPairingTest() async {
        guard case .failed(_, canRetryTest: true) = pairing else { return }
        pairingAttempt = UUID()
        await runPairingTest(attempt: pairingAttempt)
    }

    private func runPairingTest(attempt: UUID) async {
        guard attempt == pairingAttempt, let payload = allowedPayload else { return }
        pairing = .testing
        let candidate = RemoteHostSettings.paired(with: payload, at: Date())
        do {
            for host in candidate.remoteHosts {
                guard attempt == pairingAttempt else { return }
                try knownHosts.pin(host: host.host, port: host.port, key: payload.hostKeyLine)
            }
            let connection = try await RemoteConnection.connect(
                toFirstReachable: candidate.remoteHosts, key: try remoteKey(), knownHosts: knownHosts)
            let found = try await connection.sessions()
            await connection.close()
            guard attempt == pairingAttempt else { return }
            settings = candidate
            saveSettings()
            sessions = RemoteSession.forPicking(found)
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
            // .inactive -> .active also happens for the Face ID sheet and
            // Control Center; only a real trip to the background restarts.
            if wasBackgrounded {
                wasBackgrounded = false
                openIO?.restart()
            }
        case .background:
            wasBackgrounded = true
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
