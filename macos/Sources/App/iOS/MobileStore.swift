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
    @Published var settings: RemoteHostSettings {
        // Another Mac or user: warm terminals belong to the old one.
        didSet { if oldValue.remoteHosts != settings.remoteHosts { close(warm.removeAll()) } }
    }
    @Published private(set) var sessions: [RemoteSession] = [] {
        // A warm terminal whose session is gone has nothing left to show.
        didSet { close(warm.remove { key in !sessions.contains { $0.id == key.id } }) }
    }
    @Published private(set) var loading = false
    @Published var message: String?

    /// The Mac's notifications (🔔), as of the last listing.
    @Published var notes = NoteLog()
    /// Which kinds this phone shows (and, in stage 2, pushes).
    @Published var noteSettings: NoteSettings
    /// This phone's note changes the Mac may not have applied yet.
    var pendingNotes = PendingDrops()

    /// One Face ID approval per foreground period.
    private var context = LAContext()
    private var key: RemoteKey?
    let defaults: UserDefaults
    private var openIO: RemoteSurfaceIO?
    /// Terminals kept open after going back to the list, so opening one
    /// again is instant (see `WarmTerminals`).
    private var warm = WarmTerminals<OpenTerminal>()
    private var warmCheck: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var sawFirstPath = false
    private var lastStatus: NWPath.Status?
    private var lastInterfaceTypes: Set<NWInterface.InterfaceType> = []
    private var wasBackgrounded = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = RemoteHostSettings.load(from: defaults)
        self.noteSettings = Self.loadNoteSettings(from: defaults)
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

    /// A terminal closed by itself. If the session is still on the Mac, the
    /// attach failed rather than the session ending.
    func terminalClosedItself(_ session: RemoteSession) async {
        await refresh()
        if sessions.contains(where: { $0.id == session.id && $0.name == session.name }) {
            message = "Couldn't open \(SessionLabel.row(for: session, now: Date()).title). Check that tmux runs on the Mac and that Phone Access shows Terminal definition ✓."
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
    func withConnection<T>(_ body: (RemoteConnection) async throws -> T) async throws -> T {
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
    /// `attached`: the caller is attached to this very session (the
    /// terminal screen), so its current name is read by id first; the name
    /// the screen opened with goes stale when the Mac renames the session.
    @discardableResult
    func kill(_ session: RemoteSession, attached: Bool = false) async -> Bool {
        #if DEBUG
        if isGallery { return false }
        #endif
        guard !settings.remoteHosts.isEmpty else { return false }
        do {
            let listed: [RemoteSession]? = try await withConnection { connection in
                guard attached else {
                    try await connection.killSession(session.id, name: session.name, device: DeviceModel.current)
                    return nil
                }
                let listed = try await connection.sessions()
                // Not listed: it already ended.
                if let current = RemoteSession.current(of: session, in: listed) {
                    try await connection.killSession(current.id, name: current.name, device: DeviceModel.current)
                }
                return listed
            }
            if let listed { sessions = listed }
            sessions.removeAll { $0.id == session.id }
            return true
        } catch {
            message = describe(error)
            noteNeedsPairing(error)
            return false
        }
    }

    enum RenameResult: Equatable {
        /// The session as renamed, under its current name.
        case renamed(RemoteSession)
        /// Why not, for the user.
        case failed(String)
        /// Nothing to talk to (no Mac set up, or the Design Gallery).
        case skipped
    }

    /// Names `session` on the Mac (blank: back to the automatic name); the
    /// Mac tab shows it too. `attached`: as for `kill`, the current name is
    /// read by id first. The caller shows a failure.
    func rename(_ session: RemoteSession, to typed: String, attached: Bool = false) async -> RenameResult {
        #if DEBUG
        if isGallery { return .skipped }
        #endif
        guard !settings.remoteHosts.isEmpty else { return .skipped }
        let label = SessionLabel.cleanLabel(typed)
        do {
            let (result, listed) = try await withConnection { connection -> (RenameResult, [RemoteSession]?) in
                var target = session
                var listed: [RemoteSession]?
                if attached {
                    let found = try await connection.sessions()
                    listed = found
                    guard let current = RemoteSession.current(of: session, in: found) else {
                        return (.failed(RenameFailure.ended.message), found)
                    }
                    target = current
                }
                if try await connection.setLabel(label, sessionID: target.id, name: target.name) {
                    target.label = label
                    return (.renamed(target), listed)
                }
                // Refused: gone, or renamed on the Mac since it was listed.
                let after = try await connection.sessions()
                return (.failed(RenameFailure.after(sessionID: session.id, listed: after).message), after)
            }
            if let listed { sessions = listed }
            if case .renamed(let renamed) = result, let index = sessions.firstIndex(where: { $0.id == renamed.id }) {
                sessions[index] = renamed
            }
            return result
        } catch {
            noteNeedsPairing(error)
            return .failed(describe(error))
        }
    }

    /// A terminal view attached to `session`, with its IO and its link
    /// events; nil (with a message) when the settings or key aren't ready.
    typealias OpenTerminal = (view: Ghostty.SurfaceView, io: RemoteSurfaceIO, link: TerminalLink)


    func terminal(for session: RemoteSession, app: ghostty_app_t) -> OpenTerminal? {
        #if DEBUG
        if isGallery { return nil }
        #endif
        // Still warm from last time: its screen and connection as they are.
        // By id: it has stayed attached, which proves the id still names it.
        var kept = warm.remove { $0.id == session.id }
        if let terminal = kept.popLast() {
            close(kept)
            scheduleWarmCheck()
            openIO = terminal.io
            return terminal
        }
        let hosts = settings.remoteHosts
        guard !hosts.isEmpty else {
            message = settings.problem
            return nil
        }
        do {
            _ = try remoteKey()  // surface a key problem now, not after the screen opens
            let link = TerminalLink()
            let io = RemoteSurfaceIO(
                attacher: SSHAttacher(
                    hosts: hosts,
                    key: { [weak self] in
                        guard let self else { throw CancellationError() }
                        return try await self.remoteKey()
                    },
                    knownHosts: knownHosts,
                    sessionID: session.id,
                    sessionName: session.name),
                surfaceCalls: .overlaid(
                    status: { status in MainActor.assumeIsolated { link.send(status) } },
                    drawn: { MainActor.assumeIsolated { link.markDrawn() } }))
            var config = Ghostty.SurfaceConfiguration()
            config.remoteIO = io
            config.fontSize = TerminalLook.fontSize
            openIO = io
            let view = Ghostty.SurfaceView(app, baseConfig: config)
            // Its row's colors and the branch line's size.
            if let surface = view.surface {
                TerminalLook.apply(skin: session.skin, to: surface, overlayDir: TerminalLook.overlayDir)
            }
            // Scrolling back reads the history and scrolls it here.
            let skin = session.skin
            view.scrollback = .init(
                fetch: { [weak io] in await io?.paneHistory() },
                makeView: { Self.historyCopy(app: app, skin: skin) })
            return (view, io, link)
        } catch {
            message = describe(error)
            return nil
        }
    }

    /// A terminal that looks like a session's, for a block of its history:
    /// no padding above or below, so blocks stack with no gaps.
    private static func historyCopy(app: ghostty_app_t, skin: SessionSkin?) -> Ghostty.SurfaceView {
        var config = Ghostty.SurfaceConfiguration()
        config.remoteIO = Ghostty.StillIO()
        config.fontSize = TerminalLook.fontSize
        let view = Ghostty.SurfaceView(app, baseConfig: config)
        if let surface = view.surface {
            TerminalLook.apply(skin: skin, to: surface, overlayDir: TerminalLook.overlayDir,
                               extra: ["window-padding-y = 0"])
            // Ghostty takes padding from new settings only when the screen
            // scale changes: this one changes back when the view goes on
            // screen, so the blocks really have none.
            ghostty_surface_set_content_scale(surface, 1, 1)
        }
        return view
    }

    /// Why `session` ended, read from the Mac: its end tag and whether it
    /// is still there. nil when that can't be read.
    func endProbe(_ session: RemoteSession) async -> EndProbe? {
        #if DEBUG
        if isGallery { return nil }
        #endif
        guard !settings.remoteHosts.isEmpty else { return nil }
        return try? await withConnection { connection in
            try await connection.endProbe(session.id)
        }
    }

    /// The terminal's screen went away. Back keeps it warm; one that ended
    /// or was closed (`keepWarm` false) goes with its view. Only clears the
    /// open IO if it is this one, so a late disappear of an old screen
    /// can't drop a newer terminal.
    func terminalLeft(_ session: RemoteSession, _ terminal: OpenTerminal, keepWarm: Bool) {
        if openIO === terminal.io { openIO = nil }
        guard keepWarm else { return }
        close(warm.put(.init(id: session.id, name: session.name), terminal, now: Date()))
        scheduleWarmCheck()
    }

    /// A row pulled to refresh: drops its warm terminal, so opening it
    /// connects afresh (one that gave up, say, when Face ID couldn't show),
    /// then reads the list again.
    func refreshTerminal(_ session: RemoteSession) async {
        close(warm.remove { $0.id == session.id })
        scheduleWarmCheck()
        await refresh()
        listAppeared()  // resumes a watch that stopped on an error
    }

    /// Ends warm terminals' connections now, not whenever their views go.
    private func close(_ terminals: [OpenTerminal]) {
        for terminal in terminals { terminal.io.detach() }
    }

    /// Closes warm terminals as their time runs out.
    private func scheduleWarmCheck() {
        warmCheck?.cancel()
        guard let next = warm.nextExpiry else { return }
        warmCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            self.close(self.warm.expired(now: Date()))
            self.scheduleWarmCheck()
        }
    }

    // MARK: Live list

    /// The list is on screen; with the app active, one connection watches
    /// tmux and re-lists on every change. A watch stopped on an error the
    /// user must resolve stays stopped until they ask (`ListWatchGate`).
    private var gate = ListWatchGate()
    private var watchTask: Task<Void, Never>?

    /// The list came on screen, or pull to refresh: also resumes a watch
    /// that stopped on an error.
    func listAppeared() {
        gate.listVisible = true
        gate.userAsked()
        updateWatch()
    }

    /// Settings or pairing may have changed the Mac: watch the current one.
    /// `userAsked`: false for a network change, which must not re-prompt
    /// for a Face ID the user cancelled.
    func restartWatch(userAsked: Bool = true) {
        if userAsked { gate.userAsked() }
        watchTask?.cancel()
        watchTask = nil
        updateWatch()
    }

    private func updateWatch() {
        #if DEBUG
        if isGallery { return }
        #endif
        let wanted = gate.wanted(hasHosts: !settings.remoteHosts.isEmpty)
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
                let heartbeat = Task { await connection.heartbeat() }
                let delivered = await withTaskCancellationHandler {
                    await watch(on: connection)
                } onCancel: {
                    Task { await connection.close() }
                }
                heartbeat.cancel()
                await connection.close()
                policy.watchEnded(deliveredChange: delivered)
            } catch {
                loading = false
                if Task.isCancelled { break }
                message = describe(error)
                noteNeedsPairing(error)
                // Pairing again, or the user, resolves these; don't keep
                // knocking (or re-prompting for Face ID). Pull to refresh,
                // coming back to the list or from the background starts it
                // again; the Face ID sheet's own inactive → active doesn't.
                if gate.watchFailed(error) { break }
            }
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(policy.nextDelay()))
        }
        // A cancelled task was already replaced or cleared by updateWatch.
        if !Task.isCancelled { watchTask = nil }
    }

    /// Lists, then lists again after each change (at most every 300 ms),
    /// and every few seconds while a Claude works, until the watch ends: no
    /// tmux server, or the connection dropped. True when the change stream
    /// delivered at least one event.
    private func watch(on connection: RemoteConnection) async -> Bool {
        var lastList = Date.distantPast
        var delivered = false
        func relist() async throws {
            let found = try await connection.sessions()
            // Cancelled while listing (unpaired, or another Mac): the list
            // belongs to the old one.
            try Task.checkCancellation()
            lastList = Date()
            show(found)
            await loadLogoTiles(found, on: connection)
            await loadNotes(on: connection)
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
            for await wake in Self.wakes(changes, every: ListPacing.whileWorking) {
                if wake == .change {
                    delivered = true
                } else if !sessions.contains(where: { $0.claude?.isWorking == true }) {
                    continue
                }
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

    private enum Wake { case change, tick }

    /// `changes`, with a tick every `interval` between them; ends with them.
    private nonisolated static func wakes(_ changes: AsyncStream<Void>, every interval: TimeInterval) -> AsyncStream<Wake> {
        AsyncStream { continuation in
            let forward = Task {
                for await _ in changes { continuation.yield(.change) }
                continuation.finish()
            }
            let ticker = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    continuation.yield(.tick)
                }
            }
            continuation.onTermination = { _ in
                forward.cancel()
                ticker.cancel()
            }
        }
    }

    // MARK: New terminals

    /// Why a new terminal couldn't be made, to show.
    struct CreateFailure: Error, Equatable {
        var message: String
    }

    /// How long the Mac has to make a terminal: fetching for a new branch
    /// can take a while.
    static let createWait: TimeInterval = 75
    private static let recentProjectsKey = "LosttyRecentProjects"
    static let recentProjectsLimit = 5

    /// Project folders picked here before, most recent first.
    @Published private(set) var recentProjects: [String] =
        UserDefaults.standard.stringArray(forKey: MobileStore.recentProjectsKey) ?? []

    /// What browsing to a folder on the Mac found.
    enum FolderLook: Equatable {
        case found(MacFolder)
        /// Not there, or not one that can be opened.
        case missing
        case failed(String)
    }

    /// What a search below a folder on the Mac found.
    enum SearchLook: Equatable {
        case found(FolderSearch)
        case missing
        case failed(String)
    }

    /// One connection for a whole browse (`endBrowsing`), so each folder
    /// opens without connecting again.
    private var browsing: Task<RemoteConnection, Error>?

    /// Folder `path` on the Mac, the home folder when nil (or "~"), for
    /// the new terminal's browser.
    func folder(at path: String?) async -> FolderLook {
        #if DEBUG
        if isGallery {
            let at = path ?? "/Users/alex"
            return .found(MacFolder(path: at, isRepo: at.hasSuffix("lostty"), folders: at.hasSuffix("lostty") ? [] : [
                .init(name: "api-server", isRepo: true), .init(name: "lostty", isRepo: true), .init(name: "notes", isRepo: false),
            ]))
        }
        #endif
        switch await onBrowsingConnection({ try await $0.folder(at: path) }) {
        case .success(let folder): return folder.map(FolderLook.found) ?? .missing
        case .failure(let failure): return .failed(failure.message)
        }
    }

    /// The models `agent` can start with (and its default), nil when the
    /// Mac couldn't say.
    func agentModels(_ agent: TerminalAgent) async -> AgentModelList? {
        #if DEBUG
        if isGallery {
            let model = AgentModel(id: "gpt-model", name: "GPT-Model")
            return AgentModelList(models: [model], defaultModel: model)
        }
        #endif
        return try? await onBrowsingConnection { try await $0.agentModels(agent) }.get()
    }

    /// Folders below `path` (as `folder(at:)` takes it) named like `keyword`.
    func searchFolders(in path: String?, matching keyword: String) async -> SearchLook {
        #if DEBUG
        if isGallery { return .found(FolderSearch(path: path ?? "/Users/alex", hits: [])) }
        #endif
        switch await onBrowsingConnection({ try await $0.searchFolders(in: path, matching: keyword) }) {
        case .success(let found): return found.map(SearchLook.found) ?? .missing
        case .failure(let failure): return .failed(failure.message)
        }
    }

    /// Runs `body` on the browsing connection: once more on a new one if
    /// the connection dropped since the last call.
    private func onBrowsingConnection<T>(_ body: (RemoteConnection) async throws -> T) async -> Result<T, CreateFailure> {
        guard !settings.remoteHosts.isEmpty else {
            return .failure(CreateFailure(message: settings.problem ?? "Pair with your Mac first."))
        }
        for attempt in 0..<2 {
            do {
                return .success(try await body(try await browsingConnection()))
            } catch {
                await endBrowsing()
                if attempt == 1 || error is CancellationError { return .failure(CreateFailure(message: describe(error))) }
            }
        }
        return .failure(CreateFailure(message: "Couldn't reach your Mac."))
    }

    private func browsingConnection() async throws -> RemoteConnection {
        if let browsing { return try await browsing.value }
        let hosts = settings.remoteHosts
        let key = try remoteKey()
        let knownHosts = knownHosts
        let connecting = Task { try await RemoteConnection.connect(toFirstReachable: hosts, key: key, knownHosts: knownHosts) }
        browsing = connecting
        return try await connecting.value
    }

    /// Closes the browser's connection.
    func endBrowsing() async {
        guard let browsing else { return }
        self.browsing = nil
        if let connection = try? await browsing.value { await connection.close() }
    }

    /// Asks the Mac's Lostty for a new terminal (`NewTerminalRequest`) and
    /// waits for it: the new session, or why not. A request the Mac never
    /// took is withdrawn, so it can't open a window later.
    func createTerminal(_ request: NewTerminalRequest) async -> Result<RemoteSession, CreateFailure> {
        #if DEBUG
        if isGallery { return .failure(CreateFailure(message: "The gallery can't make terminals.")) }
        #endif
        remember(project: request.folder)
        do {
            return try await withConnection { connection in
                try await connection.requestNewTerminal(request)
                let deadline = Date().addingTimeInterval(Self.createWait)
                while Date() < deadline {
                    do {
                        try await Task.sleep(for: .milliseconds(400))
                    } catch {
                        await connection.clearNewTerminal(id: request.id)
                        throw error
                    }
                    guard let answer = try await connection.newTerminalAnswer(id: request.id) else { continue }
                    await connection.clearNewTerminal(id: request.id)
                    switch answer {
                    case .failed(let why):
                        return .failure(CreateFailure(message: why))
                    case .made(let id):
                        let listed = try await connection.sessions()
                        show(listed)
                        guard let session = listed.first(where: { $0.id == id }) else {
                            return .failure(CreateFailure(message: "The new terminal closed before it opened."))
                        }
                        return .success(session)
                    }
                }
                await connection.clearNewTerminal(id: request.id)
                return .failure(CreateFailure(
                    message: "Your Mac didn't answer. Make sure Lostty is open there and up to date."))
            }
        } catch {
            return .failure(CreateFailure(message: describe(error)))
        }
    }

    private func remember(project folder: String) {
        recentProjects = Array(([folder] + recentProjects.filter { $0 != folder }).prefix(Self.recentProjectsLimit))
        UserDefaults.standard.set(recentProjects, forKey: Self.recentProjectsKey)
    }

    /// Logo tiles the Mac couldn't give: not asked for again this run.
    private var unreadableTiles: Set<String> = []
    /// Bumped when a logo tile arrives, so rows that name it redraw.
    @Published private(set) var texturesLoaded = 0

    /// Fetches, over `connection`, the logo tiles the listed skins name
    /// and the phone doesn't have yet.
    private func loadLogoTiles(_ found: [RemoteSession], on connection: RemoteConnection) async {
        let scale = TerminalLook.surfaceScale
        let tiles = Set(found.compactMap { session -> String? in
            if case .logo(let tile) = session.skin?.texture?.look { return tile }
            return nil
        })
        for tile in tiles where TextureTile.needsLogo(tile, displayScale: scale) && !unreadableTiles.contains(tile) {
            guard let png = try? await connection.textureTile(at: tile),
                  TextureTile.storeLogo(png, tile: tile, displayScale: scale) else {
                unreadableTiles.insert(tile)
                continue
            }
            texturesLoaded += 1
        }
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
        needsPairing: Bool = false, settings: RemoteHostSettings = RemoteHostSettings(), notes: NoteLog = NoteLog()
    ) -> MobileStore {
        let store = MobileStore(defaults: UserDefaults(suiteName: "lostty-design-gallery")!)
        store.isGallery = true
        store.settings = settings
        store.sessions = sessions
        store.message = message
        store.pairing = pairing
        store.needsPairing = needsPairing
        store.notes = notes
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

    /// Forgets the Mac: its address and its pinned host key. The phone's own
    /// key stays, so pairing again (with this Mac or another) reuses it; the
    /// Mac still lists this phone under Phone Access until removed there.
    func unpair() {
        #if DEBUG
        if isGallery { return }
        #endif
        for host in settings.remoteHosts {
            try? knownHosts.forget(host: host.host, port: host.port)
        }
        settings = RemoteHostSettings()
        defaults.removeObject(forKey: RemoteHostSettings.defaultsKey)
        sessions = []
        message = nil
        needsPairing = false
        restartWatch(userAsked: false)
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
            // .inactive -> .active also happens for the Face ID sheet and
            // Control Center; only a real trip to the background restarts.
            let returning = wasBackgrounded
            wasBackgrounded = false
            gate.becameActive(afterBackground: returning)
            updateWatch()
            if returning { openIO?.restart() }
        case .background:
            wasBackgrounded = true
            // iOS suspends their connections anyway; don't keep them.
            close(warm.removeAll())
            warmCheck?.cancel()
            gate.wentToBackground()
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
            for terminal in warm.values { terminal.io.restart() }
            restartWatch(userAsked: false)
        }
    }
}
#endif
