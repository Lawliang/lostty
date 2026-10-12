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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = RemoteHostSettings.load(from: defaults)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.networkChanged(path.status) }
        }
        pathMonitor.start(queue: .main)
    }

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty", isDirectory: true)
    }

    var knownHosts: KnownHosts { KnownHosts(fileURL: Self.supportDir.appendingPathComponent("known_hosts")) }

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
        return loaded
    }

    func refresh() async {
        guard let host = settings.remoteHost else {
            message = settings.problem
            return
        }
        loading = true
        defer { loading = false }
        do {
            let connection = try await RemoteConnection.connect(to: host, key: try remoteKey(), knownHosts: knownHosts)
            defer { Task { await connection.close() } }
            sessions = RemoteSession.forPicking(try await connection.sessions())
            message = sessions.isEmpty ? "No Lostty sessions are running on the Mac." : nil
        } catch {
            message = (error as? RemoteError)?.message ?? error.localizedDescription
        }
    }

    func kill(_ session: RemoteSession) async {
        guard let host = settings.remoteHost else { return }
        do {
            let connection = try await RemoteConnection.connect(to: host, key: try remoteKey(), knownHosts: knownHosts)
            try await connection.killSession(session.id)
            await connection.close()
            sessions.removeAll { $0.id == session.id }
        } catch {
            message = (error as? RemoteError)?.message ?? error.localizedDescription
        }
    }

    /// A terminal view attached to `session`; nil (with a message) when the
    /// settings or key aren't ready.
    func terminal(for session: RemoteSession, app: ghostty_app_t) -> Ghostty.SurfaceView? {
        guard let host = settings.remoteHost else {
            message = settings.problem
            return nil
        }
        do {
            _ = try remoteKey()  // surface a key problem now, not after the screen opens
            let io = RemoteSurfaceIO(attacher: SSHAttacher(
                host: host,
                key: { [weak self] in
                    guard let self else { throw CancellationError() }
                    return try await self.remoteKey()
                },
                knownHosts: knownHosts,
                sessionID: session.id))
            var config = Ghostty.SurfaceConfiguration()
            config.remoteIO = io
            openIO = io
            return Ghostty.SurfaceView(app, baseConfig: config)
        } catch {
            message = (error as? RemoteError)?.message ?? error.localizedDescription
            return nil
        }
    }

    func terminalClosed() {
        openIO = nil
    }

    // MARK: Reconnect triggers

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            openIO?.restart()
        case .background:
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
    private func networkChanged(_ status: NWPath.Status) {
        defer { sawFirstPath = true }
        guard sawFirstPath, status == .satisfied else { return }
        openIO?.restart()
    }
}
#endif
