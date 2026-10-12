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
            message = sessions.isEmpty ? "No Lostty sessions are running on the Mac." : nil
        } catch {
            message = describe(error)
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
