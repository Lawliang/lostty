#if os(iOS)
import GhosttyKit
import LosttyRemote
import SwiftUI
import UIKit

/// Home: the Mac's Lostty sessions, kept current while on screen; the
/// welcome screen while no Mac is set up.
struct SessionsScreen: View {
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var ghostty: Ghostty.App
    @Environment(\.displayScale) private var displayScale
    /// Shows the Settings tab (the welcome's Settings button).
    var openSettings: () -> Void = {}
    @State private var path: [String] = []
    @State private var open: (session: RemoteSession, view: Ghostty.SurfaceView, io: RemoteSurfaceIO, link: TerminalLink)?
    @State private var showPairing = false
    @State private var showNewTerminal = false
    @State private var showNotifications = false
    /// A terminal asked of the Mac, shown being made until it opens.
    @State private var creating: NewTerminalRequest?
    @State private var confirmKill: RemoteSession?
    /// The Active filter pill tapped, if any.
    @State private var filter: ActiveState?
    /// The project pill tapped, if any: only its terminals show.
    @State private var projectFilter: String?
    /// A row was held: every row jiggles with a delete badge until Done.
    @State private var editing = false
    /// Rows pulled to refresh, by session id, until the Mac has answered.
    @State private var refreshing: Set<String> = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.settings.remoteHost == nil {
                    WelcomeScreen(pair: { showPairing = true }, settings: openSettings)
                } else {
                    sessionList
                }
            }
            // The app's name centered in the top bar, the axolotl peeking out
            // from behind its L; + at the left, the wave at the right. The
            // plain title stays for VoiceOver. Only over the list: the
            // welcome has its own.
            .navigationTitle(store.settings.remoteHost != nil ? "Lostty" : "")
            .toolbarTitleDisplayMode(.inline)
            .losttyScreen()
            .toolbar {
                if store.settings.remoteHost != nil {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 0) {
                            PeekingAxolotl()
                            Text("Lostty")
                                .font(LosttyFont.largeTitle)
                                .foregroundStyle(LosttyTheme.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                                .fixedSize()
                        }
                    }
                }
                if editing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { withAnimation(LosttyTheme.motion) { editing = false } }
                            .fontWeight(.semibold)
                            .tint(.white)
                    }
                } else if store.settings.remoteHost != nil && !showsProblem {
                    // A new terminal, here and on the Mac.
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showNewTerminal = true } label: {
                            Image(systemName: "plus").foregroundStyle(.white)
                        }
                        .tint(.white)
                        .accessibilityLabel("New Terminal")
                    }
                    // Notifications: the inbox, and how many are unread.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNotifications = true } label: {
                            Image(systemName: "bell").foregroundStyle(.white)
                                .overlay(alignment: .topTrailing) {
                                    if store.unreadNotes > 0 {
                                        NoteBadge(count: store.unreadNotes).offset(x: 11, y: -9)
                                    }
                                }
                        }
                        .tint(.white)
                        .accessibilityLabel("Notifications")
                        .accessibilityValue(store.unreadNotes > 0 ? "\(store.unreadNotes) unread" : "")
                    }
                }
            }
            .navigationDestination(for: String.self) { route in
                if route == Self.creatingRoute, open == nil, let creating {
                    CreatingTerminalScreen(request: creating) { openMade($0) }
                } else if let open {
                    TerminalScreen(session: open.session, surfaceView: open.view, io: open.io, link: open.link)
                }
            }
            .sheet(isPresented: $showNewTerminal) {
                NewTerminalSheet { request in
                    creating = request
                    path = [Self.creatingRoute]
                }
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsInbox(openTerminal: openTerminal).environmentObject(store)
            }
            .sheet(isPresented: $showPairing, onDismiss: { store.restartWatch() }) {
                NavigationStack { PairingScreen() }
            }
            .confirmCloseSession($confirmKill) { session in
                Task { await store.kill(session) }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: editing) { _, now in now }
            // Nothing left to edit.
            .onChange(of: store.sessions.isEmpty) { _, empty in if empty { editing = false } }
            .onAppear {
                if path.isEmpty { store.listAppeared() }
                if store.pendingPairingLink != nil { showPairing = true }
            }
            .onChange(of: store.pendingPairingLink) { _, link in if link != nil { showPairing = true } }
            .onChange(of: path) { _, newPath in
                editing = false
                if newPath.isEmpty {
                    // Back from the terminal: drop it (the store may keep it
                    // warm); the list resumes.
                    open = nil
                    store.listAppeared()
                }
                // An open terminal keeps the live list going: its Claude
                // trace follows the session's state from it.
            }
        }
    }

    private var sessionList: some View {
        // Once a minute, so "5m ago" stays true.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let groups = SessionLabel.ordered(store.sessions)
            let labels = Dictionary(uniqueKeysWithValues: (groups.active + groups.inactive).map {
                ($0.id, SessionLabel.row(for: $0, now: context.date))
            })
            let projects = ProjectFilter.projects(groups.active.compactMap { labels[$0.id] })
            // A project whose last open terminal closed shows everything again.
            let project = projectFilter.flatMap { name in projects.contains { $0.name == name } ? name : nil }
            let inProject = { (session: RemoteSession) in project == nil || labels[session.id]?.project == project }
            let active = groups.active.filter(inProject)
            let inactive = groups.inactive.filter(inProject)
            let states = Dictionary(uniqueKeysWithValues: active.map {
                ($0.id, labels[$0.id].map { ActiveState($0.status) } ?? nil)
            })
            let counts = Dictionary(grouping: states.values.compactMap { $0 }) { $0 }.mapValues(\.count)
            // A filter whose last terminal moved on shows everything again.
            let shown = filter.flatMap { counts[$0, default: 0] > 0 ? $0 : nil }
            List {
                // A message beside sessions; with none to show, the centered
                // problem state below says it instead.
                if let message = store.message, !showsEmptyState, !showsProblem {
                    LosttyCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message).font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                            if store.needsPairing {
                                Button("Pair Again") { showPairing = true }.buttonStyle(.lostty(.primary))
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: LosttyTheme.margin, bottom: 6, trailing: LosttyTheme.margin))
                }
                // Headings and pills are rows, not section headers: headers
                // stay pinned over the rows scrolling under them.
                if !active.isEmpty {
                    sectionHeader("Open Terminals", count: active.count, tint: LosttyTheme.success)
                        .listHeading(first: true)
                    statePills(counts: counts, selected: shown).listPills()
                    // Under the states, by project: only with two or more,
                    // when picking one narrows anything.
                    if projects.count >= 2 {
                        projectPills(projects, total: groups.active.count, selected: project).listPills(first: false)
                    }
                    ForEach(active.filter { shown == nil || states[$0.id] == shown }, id: \.id) { session in
                        row(session, now: context.date)
                    }
                }
                if !inactive.isEmpty {
                    sectionHeader("Disconnected", count: inactive.count, tint: LosttyTheme.textSecondary)
                        .listHeading(first: active.isEmpty)
                    // No Mac window shows them: still there to open or
                    // close, but quieter.
                    ForEach(inactive, id: \.id) { session in
                        row(session, now: context.date).opacity(0.55)
                    }
                }
            }
            .listStyle(.plain)
            // Rows as tall as they are: a short heading padded to the
            // default 44pt would sit further from its pills than another.
            .environment(\.defaultMinListRowHeight, 0)
            // Forget a filter once its last terminal moves on, so it doesn't
            // come back by itself later.
            .onChange(of: shown) { _, now in if now == nil { filter = nil } }
            .onChange(of: project) { _, now in if now == nil { projectFilter = nil } }
            .overlay {
                if showsEmptyState {
                    // Let pulls reach the list underneath (pull to refresh).
                    EmptySessions().allowsHitTesting(false)
                } else if showsProblem, let message = store.message {
                    ConnectionProblem(needsPairing: store.needsPairing, message: message, pair: { showPairing = true }) {
                        Task {
                            await store.refresh()
                            store.listAppeared()
                        }
                    }
                } else if store.loading && store.sessions.isEmpty {
                    BufferSpinner(color: LosttyTheme.accent)
                        .frame(width: 22, height: 22)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Loading terminals")
                }
            }
            .refreshable {
                await store.refresh()
                store.listAppeared()  // resumes a watch that stopped on an error
            }
        }
    }

    static let creatingRoute = "creating"

    /// The terminal the Mac made: in place of the screen that waited for
    /// it, on the same stop of the path (replacing the path's last value
    /// pops instead), so no slide: its axolotl carries on into the
    /// terminal's.
    private func openMade(_ session: RemoteSession) {
        guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else {
            path = []
            return
        }
        open = (session, terminal.view, terminal.io, terminal.link)
    }

    /// Opens `session`'s terminal: a row's tap, or a note's.
    private func openTerminal(_ session: RemoteSession) {
        guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else { return }
        open = (session, terminal.view, terminal.io, terminal.link)
        path = ["terminal"]
    }

    private func row(_ session: RemoteSession, now: Date) -> some View {
        let label = SessionLabel.row(for: session, now: now)
        return SessionRowGestures(
            editing: editing,
            refreshing: refreshing.contains(session.id),
            phase: Double(abs(session.id.hashValue) % 100) / 100,
            title: label.title,
            tap: {
                // Editing: a tap on a row ends it, as on the Home Screen.
                if editing {
                    withAnimation(LosttyTheme.motion) { editing = false }
                    return
                }
                openTerminal(session)
            },
            refresh: { refreshRow(session) },
            hold: { withAnimation(LosttyTheme.motion) { editing = true } },
            delete: { confirmKill = session }
        ) {
            SessionRowView(
                row: label,
                texture: session.skin.flatMap { TextureTile.image(for: $0, displayScale: displayScale) })
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // Edge to edge: each terminal is a full-width band.
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }

    /// Pulled to refresh: that terminal connects afresh next time it opens,
    /// and the list is read again. The row stays slid out until then.
    private func refreshRow(_ session: RemoteSession) {
        refreshing.insert(session.id)
        Task {
            await store.refreshTerminal(session)
            withAnimation(SessionRowMotion.settle) { _ = refreshing.remove(session.id) }
        }
    }

    /// One pill per state with terminals in it, in `ActiveState` order. A
    /// tap shows only that state; another tap shows them all.
    private func statePills(counts: [ActiveState: Int], selected: ActiveState?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActiveState.allCases.filter { counts[$0, default: 0] > 0 }, id: \.self) { state in
                    let on = state == selected
                    filterPill(on: on, count: counts[state, default: 0]) {
                        withAnimation(LosttyTheme.motion) { filter = on ? nil : state }
                    } label: {
                        Text(state.title)
                    }
                }
            }
            .padding(.horizontal, LosttyTheme.margin)
        }
    }

    /// All (the default), then one pill per project with open terminals:
    /// "> lostty" as the rows begin their project line, the ">" in its
    /// first terminal's accent. A tap shows only its terminals; All, or
    /// another tap, shows them all again.
    private func projectPills(_ projects: [OpenProject], total: Int, selected: String?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Every project: the default, and the way back from one.
                filterPill(on: selected == nil, count: total) {
                    withAnimation(LosttyTheme.motion) { projectFilter = nil }
                } label: {
                    Text("All")
                }
                ForEach(projects, id: \.name) { project in
                    let on = project.name == selected
                    filterPill(on: on, count: project.count) {
                        withAnimation(LosttyTheme.motion) { projectFilter = on ? nil : project.name }
                    } label: {
                        HStack(spacing: 5) {
                            Text(">")
                                .fontWeight(.heavy)
                                .foregroundStyle(project.skin.map { Color($0.accent) } ?? LosttyTheme.accent)
                                .accessibilityHidden(true)
                            Text(project.name)
                        }
                    }
                }
            }
            .padding(.horizontal, LosttyTheme.margin)
        }
    }

    /// A filter pill: its label, then its count in a circle darker than the
    /// pill (a capsule once it needs two digits); tinted with the accent
    /// while on.
    private func filterPill<Label: View>(
        on: Bool, count: Int, action: @escaping () -> Void, @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                label()
                Text("\(count)")
                    .monospacedDigit()
                    .fontWeight(.heavy)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color.black.opacity(0.4), in: Capsule())
            }
            .font(LosttyFont.detail.weight(.semibold))
            .foregroundStyle(LosttyTheme.textPrimary)
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(on ? LosttyTheme.accent.opacity(0.14) : LosttyTheme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? LosttyTheme.accent.opacity(0.35) : LosttyTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// "Open Terminals (3)": the count in a soft pill tinted `tint`.
    private func sectionHeader(_ title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(LosttyFont.bodyEmphasis)
                .foregroundStyle(LosttyTheme.textSecondary)
            Text("\(count)")
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(minWidth: 10)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// No sessions and nothing else to say: the friendly empty state.
    private var showsEmptyState: Bool {
        store.sessions.isEmpty && !store.loading && store.message == MobileStore.noSessionsMessage
    }

    /// Nothing to list because something's wrong: say so in the middle.
    private var showsProblem: Bool {
        store.sessions.isEmpty && !store.loading && store.message != nil && !showsEmptyState
    }
}

/// A row's gestures. Tap opens it. Drag it left and let go past
/// `RowPull.threshold` to refresh that terminal: the row slides aside over a
/// refresh arrow that fills as it goes, and stays slid out with a spinner
/// until the Mac answers. Hold it to edit: every row jiggles with a delete
/// badge, like the Home Screen.
private struct SessionRowGestures<Content: View>: View {
    /// How far a refreshing row stays slid out: room for the spinner.
    static var held: CGFloat { 56 }
    /// The jiggle: degrees either way, and swings a second.
    static var wobble: Double { 0.7 }
    static var wobbleRate: Double { 3.5 }

    let editing: Bool
    let refreshing: Bool
    /// Where in its swing this row's jiggle starts, 0–1, so rows don't
    /// move in step.
    let phase: Double
    /// The row's title, for VoiceOver.
    let title: String
    let tap: () -> Void
    let refresh: () -> Void
    let hold: () -> Void
    let delete: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The pull under way: its travel, negative to the left.
    @State private var pull: Double = 0

    var body: some View {
        let dx = pull
        let slid = refreshing ? -Self.held : CGFloat(RowPull.offset(dx: dx))
        ZStack(alignment: .trailing) {
            indicator(progress: RowPull.progress(dx: dx))
                .frame(width: max(0, -slid))
                .opacity(-slid > 8 ? 1 : 0)
                // The row's own Refresh action says it for VoiceOver.
                .accessibilityHidden(true)
            jiggling
                .offset(x: slid)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: RowPull.refreshes(dx: dx)) { _, armed in armed }
        .modifier(SidewaysPull(
            changed: { dx in if !editing && !refreshing { pull = min(0, dx) } },
            ended: { dx in
                let refreshes = !editing && !refreshing && RowPull.refreshes(dx: dx)
                withAnimation(SessionRowMotion.settle) {
                    pull = 0
                    if refreshes { refresh() }
                }
            }))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap() }
        .accessibilityAction(named: "Refresh") { refresh() }
        .accessibilityAction(named: "Close") { delete() }
    }

    /// The row, rocking gently while editing, its delete badge riding along.
    private var jiggling: some View {
        let shaking = editing && !reduceMotion
        return TimelineView(.animation(minimumInterval: nil, paused: !shaking)) { context in
            let swing = (context.date.timeIntervalSinceReferenceDate * Self.wobbleRate + phase) * 2 * .pi
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: tap)
                // A finger that moves is dragging or scrolling, not holding.
                .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 6, perform: hold)
                .overlay(alignment: .topLeading) {
                    if editing {
                        deleteBadge.transition(.scale.combined(with: .opacity))
                    }
                }
                .rotationEffect(.degrees(shaking ? sin(swing) * Self.wobble : 0))
        }
    }

    /// What the slid-aside row uncovers: an arrow that turns and fills as
    /// the pull nears the threshold, then the spinner while refreshing.
    @ViewBuilder
    private func indicator(progress: Double) -> some View {
        if refreshing {
            BufferSpinner(color: LosttyTheme.accent).frame(width: 22, height: 22)
        } else {
            let armed = progress >= 1
            ZStack {
                Circle().stroke(LosttyTheme.hairline, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(LosttyTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(armed ? LosttyTheme.accent : LosttyTheme.textSecondary)
                    .rotationEffect(.degrees(progress * 270))
            }
            .frame(width: 26, height: 26)
            .scaleEffect(armed ? 1.12 : 1)
            .animation(.spring(duration: 0.2), value: armed)
        }
    }

    /// The Home Screen's minus badge, on the row's top-left corner.
    private var deleteBadge: some View {
        Button(action: delete) {
            Image(systemName: "minus")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.thinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1))
                // A full-size touch target around the small badge.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: -4, y: -15)
        .accessibilityLabel("Close \(title)")
    }
}

/// A row's sideways pull, as a UIKit pan that only starts when the finger
/// heads left (`RowPull.isSideways`), so a vertical swipe still scrolls the
/// list. (SwiftUI's own drag gesture on a row takes those too.) `ended`
/// also comes for a cancelled pan, so the row always springs home. Before
/// iOS 18 there is no pull; the row's Refresh accessibility action remains.
private struct SidewaysPull: ViewModifier {
    let changed: (Double) -> Void
    let ended: (Double) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.gesture(SidewaysPan(changed: changed, ended: ended))
        } else {
            content
        }
    }
}

@available(iOS 18, *)
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    let changed: (Double) -> Void
    let ended: (Double) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let dx = Double(pan.translation(in: pan.view).x)
        switch pan.state {
        case .began, .changed: changed(dx)
        case .ended: ended(dx)
        case .cancelled, .failed: ended(0)
        default: break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return RowPull.isSideways(dx: Double(velocity.x), dy: Double(velocity.y))
        }

        /// The list's scrolling waits for this to decide, so a pull takes
        /// the touch for itself (a list being scrolled holds back redrawing
        /// its rows), and a vertical swipe, which fails it at once, scrolls.
        func gestureRecognizer(
            _ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool { other.view is UIScrollView }
    }
}

/// How a pulled row springs back, and slides home after refreshing.
private enum SessionRowMotion {
    static let settle: Animation = .spring(duration: 0.35, bounce: 0.2)
}

/// What an Active terminal is doing, for the filter pills.
enum ActiveState: CaseIterable, Hashable {
    case waiting, working, ready, idle

    /// nil for a terminal no Mac window shows.
    init?(_ status: SessionRow.Status) {
        switch status {
        case .waiting: self = .waiting
        case .working: self = .working
        case .ready: self = .ready
        case .idle: self = .idle
        case .lastUsed: return nil
        }
    }

    /// Waiting on you or working: its label takes the skin's accent.
    var isBusy: Bool { self == .waiting || self == .working }

    var title: String {
        switch self {
        case .waiting: "Waiting on You"
        case .working: "Working"
        case .ready: "Ready"
        case .idle: "Idle"
        }
    }
}

/// One session: what it is, its repo and branch, and an axolotl waving
/// while it waits for you or dancing while it works, else when it was last
/// used; in its Mac pane's skin colors when it has one.
private struct SessionRowView: View {
    let row: SessionRow
    /// The skin's texture tile, at the screen's scale.
    let texture: CGImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let colors = RowColors(skin: row.skin)
        HStack(alignment: .rowMascot, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(LosttyFont.bodyEmphasis)
                    .foregroundStyle(colors.primary)
                    .lineLimit(1)
                // A prompt: "> lostty/skins", the ">" in the skin's accent.
                HStack(spacing: 6) {
                    Text(">")
                        .fontWeight(.heavy)
                        .foregroundStyle(colors.prompt)
                        .accessibilityHidden(true)
                    Text(row.detail)
                        .foregroundStyle(colors.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(LosttyFont.mono(.footnote, size: 13))
                // The axolotl and chevron sit level with this line (about the
                // middle of title, branch and state), so a row that grows
                // keeps them up top. Without a state line, they center.
                .modifier(MascotLevel(isOn: ActiveState(row.status) != nil))
                // What its Claude is doing right now, or asks to do.
                if let action = row.action {
                    Text(action)
                        .font(LosttyFont.mono(.footnote, size: 13))
                        .foregroundStyle(colors.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 5)
                }
                // What it's doing, as the filter pills name it; nothing for a
                // terminal no Mac window shows.
                if let state = ActiveState(row.status) {
                    Group {
                        if state == .working {
                            WorkingLine(spinner: row.spinner, color: colors.prompt, detail: colors.secondary)
                        } else {
                            StatusLabel(state: state, color: state.isBusy ? colors.prompt : colors.primary)
                        }
                    }
                    .padding(.top, row.action == nil ? 5 : 1)
                }
            }
            Spacer(minLength: 8)
            switch row.status {
            case .waiting:
                // Waving you over; still, it says the same.
                mascot(.waving)
            case .working where !reduceMotion:
                mascot(.dancing)
                    // Over the axolotl's left side, to save room.
                    .overlay(alignment: .leading) {
                        BufferSpinner(color: colors.prompt)
                            .frame(width: 16, height: 16)
                            .offset(x: -4)
                    }
            case .ready:
                mascot(.ready)
            case .idle(let since):
                sleeper(since: since)
            default:
                if !row.statusText.isEmpty {
                    Text(row.statusText)
                        .font(LosttyFont.detail)
                        .foregroundStyle(colors.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(colors.primary.opacity(0.8))
                // Drawn behind, not laid out: the axolotl keeps its place and
                // the two may overlap.
                .background {
                    Circle()
                        .fill(Color.black.opacity(colors.chevronShade))
                        .frame(width: 28, height: 28)
                }
        }
        // Text lines up with the section headers.
        .padding(.vertical, 14)
        .padding(.horizontal, LosttyTheme.margin + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                // The skin's texture, as the Mac pane shows it.
                if let tile = texture, let skinTexture = row.skin?.texture {
                    Image(decorative: tile, scale: displayScale)
                        .resizable(resizingMode: .tile)
                        .opacity(TerminalLook.textureOpacity(skinTexture))
                }
                // Waiting on you: the band slowly brightens and fades, in time.
                if row.status == .waiting && !reduceMotion { WaitingFlash(color: colors.flash) }
            }
            .clipShape(RoundedRectangle(cornerRadius: RowTrace.cornerRadius, style: .circular))
        }
        .modifier(RowGlass(colors: colors))
        .contentShape(RoundedRectangle(cornerRadius: RowTrace.cornerRadius, style: .circular))
        // Working: a small beam laps the row, as the terminal's laps the screen.
        .overlay {
            if row.status == .working { RowTrace(skin: row.skin) }
        }
        .accessibilityElement(children: .combine)
        // The axolotl is decorative: say what it means.
        .accessibilityValue(spokenStatus)
    }

    /// What VoiceOver says for an axolotl; empty where the text says it.
    private var spokenStatus: String {
        switch row.status {
        case .waiting, .ready: row.statusText
        case .working: reduceMotion ? "" : row.statusText
        case .idle(let since): since.isEmpty ? "Idle" : "Idle, \(since)"
        case .lastUsed: ""
        }
    }

    /// Asleep, with how long it's been idle on a black pill over its feet.
    private func sleeper(since: String) -> some View {
        ZStack(alignment: .bottom) {
            Axolotl(pose: .sleeping).frame(width: 60, height: 60)
                .background(alignment: .bottom) { MascotPlatform() }
            if !since.isEmpty {
                Text(since)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black, in: Capsule())
                    .fixedSize()
            }
        }
        .padding(.vertical, -10)
    }

    private func mascot(_ pose: Axolotl.Pose) -> some View {
        Axolotl(pose: pose).frame(width: 60, height: 60)
            .background(alignment: .bottom) { MascotPlatform() }
            // Fills the card without making it taller.
            .padding(.vertical, -10)
    }
}

extension VerticalAlignment {
    /// A session row's text and its axolotl and chevron meet here.
    private enum RowMascot: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }

    fileprivate static let rowMascot = VerticalAlignment(RowMascot.self)
}

/// Puts a session row's axolotl and chevron level with this view.
private struct MascotLevel: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.alignmentGuide(.rowMascot) { $0[VerticalAlignment.center] }
        } else {
            content
        }
    }
}

/// A row's state under its branch, ending on a still dot ("Ready."). Working
/// has its own line (`WorkingLine`).
private struct StatusLabel: View {
    let state: ActiveState
    let color: Color

    var body: some View {
        Text(state.title + ".")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .tracking(0.3)
            .foregroundStyle(color)
            .accessibilityLabel(state.title)
    }
}

/// Working, drawn as Claude Code draws it under the conversation: its
/// glyph turning, the word with a band of light running through it, then
/// how long and how many tokens, the time running on by itself:
/// `✳ Incubating… (3m 51s · ↓ 23.5k tokens)`. A pane showing no such line
/// (only subagents work, say) reads `✳ Working…`. Short of room, it drops
/// the word "tokens" (`↓ 23.5k`), then the tokens. Under Reduce Motion the
/// glyph and word stay still; the time still runs.
private struct WorkingLine: View {
    /// A glyph this long, as Claude's.
    static let frame: TimeInterval = 0.12
    /// The band of light crosses the word this often.
    static let sweep: TimeInterval = 2.2
    /// Its half-width, in characters.
    static let band: Double = 2.5

    let spinner: ClaudeSpinner?
    let color: Color
    let detail: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : Self.frame)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 0) {
                // Its own box: the glyphs differ in width.
                Text(reduceMotion ? "✳" : ClaudeSpinner.glyph(tick: Int(t / Self.frame)))
                    .foregroundStyle(color)
                    .frame(width: 16, alignment: .leading)
                ViewThatFits(in: .horizontal) {
                    ForEach(Room.allCases, id: \.self) { room in
                        word(at: t) + parentheses(at: context.date, room: room)
                    }
                }
            }
        }
        .font(LosttyFont.mono(.footnote, size: 13))
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(["Working", spinner?.parentheses(now: Date())].compactMap { $0 }.joined(separator: ", "))
    }

    private var text: String { spinner?.word ?? "Working…" }

    /// The word in `color`, each letter lightening as the band passes.
    private func word(at t: TimeInterval) -> Text {
        let letters = Array(text)
        guard !reduceMotion else { return Text(text).foregroundStyle(color) }
        let light = Self.blend(UIColor(color), .white, 0.55)
        // From a band's width before the word to one after it.
        let travel = Double(letters.count) + 2 * Self.band
        let center = (t.truncatingRemainder(dividingBy: Self.sweep) / Self.sweep) * travel - Self.band
        return letters.enumerated().reduce(Text("")) { line, letter in
            let lift = max(0, 1 - abs(Double(letter.offset) - center) / Self.band)
            return line + Text(String(letter.element))
                .foregroundStyle(Color(uiColor: Self.blend(UIColor(color), light, lift)))
        }
    }

    /// How much of the parentheses fits, most first.
    private enum Room: CaseIterable { case all, noTokensWord, timeOnly }

    private func parentheses(at now: Date, room: Room) -> Text {
        guard var text = spinner?.parentheses(now: now, detail: room != .timeOnly) else { return Text("") }
        if room == .noTokensWord { text = text.replacingOccurrences(of: " tokens", with: "") }
        return Text(" " + text).foregroundStyle(detail)
    }

    /// `a` moved `amount` (0…1) of the way to `b`.
    private static func blend(_ a: UIColor, _ b: UIColor, _ amount: Double) -> UIColor {
        var (ar, ag, ab, aa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (br, bg, bb, ba): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let k = CGFloat(amount)
        return UIColor(red: ar + (br - ar) * k, green: ag + (bg - ag) * k, blue: ab + (bb - ab) * k,
                       alpha: aa + (ba - aa) * k)
    }
}

/// A row's surface: iOS's glass, tinted the skin's background and
/// answering a touch as a glass button does; before iOS 26, the background
/// solid with a faint accent edge.
private struct RowGlass: ViewModifier {
    let colors: RowColors

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: RowTrace.cornerRadius, style: .circular)
        if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(colors.background.opacity(0.85)).interactive(), in: shape)
        } else {
            content
                .background(colors.background, in: shape)
                .overlay { shape.strokeBorder(colors.border, lineWidth: 1) }
        }
    }
}

/// A circular buffering spinner: an arc chasing round a faint ring, a turn
/// every `BufferSpinner.turn`.
struct BufferSpinner: View {
    static let turn: TimeInterval = 0.9

    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let turns = context.date.timeIntervalSinceReferenceDate / Self.turn
            ZStack {
                Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(360 * turns.truncatingRemainder(dividingBy: 1)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A slow flash: `color` rises to a soft wash and fades out, every
/// `WaitingFlash.period`.
private struct WaitingFlash: View {
    static let period: TimeInterval = 2.4
    static let peak: Double = 0.22

    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 2 * .pi / Self.period
            color.opacity(Self.peak * (0.5 - 0.5 * cos(phase)))
        }
        .allowsHitTesting(false)
    }
}

/// A row's colors: the skin's background, text and accent (as the pane
/// looks on the Mac), else the plain card's.
struct RowColors {
    var background = LosttyTheme.surface
    var primary = LosttyTheme.textPrimary
    var secondary = LosttyTheme.textSecondary
    /// The row's edge: the skin's accent, faint.
    var border = LosttyTheme.hairline
    /// What a terminal waiting on you flashes.
    var flash = LosttyTheme.accent
    /// The ">" before the repo and branch.
    var prompt = LosttyTheme.accent
    /// How dark the circle behind the chevron is: lighter on a light skin.
    var chevronShade = 0.5

    init(skin: SessionSkin?) {
        guard let skin else { return }
        // A skin without its own text color shows the terminal's default:
        // light text, or dark on a light background.
        let text = skin.foreground.map(Color.init) ?? (skin.isLight ? Color(losttyHex: 0x1C1A1F) : LosttyTheme.textPrimary)
        let accent = Color(skin.accent)
        background = Color(skin.background)
        primary = text
        secondary = text.opacity(0.65)
        border = accent.opacity(0.45)
        flash = accent
        chevronShade = skin.isLight ? 0.2 : 0.5
        // A made-up accent is the background lightened: too faint on a
        // light one, where the text color stands in.
        prompt = skin.isLight && skin.accent.luminance > 0.4 ? text : accent
    }
}

private extension Color {
    init(_ rgb: SessionSkin.RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

/// Rename: one name everywhere (the Mac tab shows it too); blank goes back
/// to the automatic name. A failure goes to `failed`, or the list's message.
struct RenameSessionAlert: ViewModifier {
    @Binding var session: RemoteSession?
    /// The caller is attached to the session (see `MobileStore.rename`).
    var attached: Bool
    var renamed: (RemoteSession) -> Void
    var failed: ((String) -> Void)?
    @EnvironmentObject private var store: MobileStore
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(
                "Rename",
                isPresented: Binding(get: { session != nil }, set: { if !$0 { session = nil } }),
                presenting: session
            ) { target in
                TextField("Name", text: $text)
                Button("Save") {
                    let typed = text
                    Task {
                        switch await store.rename(target, to: typed, attached: attached) {
                        case .renamed(let session): renamed(session)
                        case .failed(let text):
                            if let failed { failed(text) } else { store.message = text }
                        case .skipped: break
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Leave blank to use the automatic name.")
            }
            .onChange(of: session?.id) { _, id in
                if id != nil { text = session?.label ?? "" }
            }
    }
}

extension View {
    /// Asks before closing `session`: closing ends the terminal on the phone
    /// and the Mac alike, so say so, with Cancel to back out.
    func confirmCloseSession(
        _ session: Binding<RemoteSession?>, close: @escaping (RemoteSession) -> Void
    ) -> some View {
        let warning = session.wrappedValue.map(SessionLabel.closeWarning)
        return alert(
            warning?.title ?? "",
            isPresented: Binding(get: { session.wrappedValue != nil }, set: { if !$0 { session.wrappedValue = nil } }),
            presenting: session.wrappedValue
        ) { target in
            Button("Cancel", role: .cancel) {}
            Button("Close", role: .destructive) { close(target) }
        } message: { _ in
            Text(warning?.message ?? "")
        }
    }

    func renameSession(
        _ session: Binding<RemoteSession?>, attached: Bool = false,
        renamed: @escaping (RemoteSession) -> Void = { _ in }, failed: ((String) -> Void)? = nil
    ) -> some View {
        modifier(RenameSessionAlert(session: session, attached: attached, renamed: renamed, failed: failed))
    }
}

/// The axolotl leaning out from behind the title's L: tilted out to the
/// left, everything past the L's edge cut away so the rest of him seems
/// hidden behind the letter. His cursor eye blinks.
private struct PeekingAxolotl: View {
    var body: some View {
        // Gills swaying, eye steady: a logo, not a cursor.
        Axolotl(pose: .waiting, blinks: false)
            .frame(width: 40, height: 40)
            .rotationEffect(.degrees(-16))
            // Head and face only: his right side ends at the L, his body
            // below is hidden behind the title.
            .frame(width: 30, height: 28, alignment: .topLeading)
            .clipped()
            .padding(.trailing, 1)
            .accessibilityHidden(true)
    }
}

/// Can't list the Mac's terminals: what happened and the one thing to do
/// about it, centered. A phone the Mac no longer accepts is sent to pair
/// again; anything else can try again.
private struct ConnectionProblem: View {
    let needsPairing: Bool
    let message: String
    let pair: () -> Void
    let retry: () -> Void

    var body: some View {
        // Not paired says it all; anything else says what went wrong.
        UhOh(headline: needsPairing ? "This phone isn't paired anymore" : "Can't reach your Mac",
             detail: needsPairing ? nil : message) {
            Button(needsPairing ? "Pair Again" : "Try Again", action: needsPairing ? pair : retry)
                .buttonStyle(.lostty(.primary, fullWidth: true))
        }
    }
}

private struct EmptySessions: View {
    var body: some View {
        VStack(spacing: 10) {
            Axolotl(pose: .resting).frame(width: 104, height: 104).losttyGlow(diameter: 260)
                .padding(.bottom, 6)
            Text("Nothing running yet")
                .font(LosttyFont.bodyEmphasis)
                .foregroundStyle(LosttyTheme.textPrimary)
            Text("Open Lostty on your Mac.")
                .font(LosttyFont.detail)
                .foregroundStyle(LosttyTheme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(LosttyTheme.margin)
    }
}

/// The list's headings and pill rows: on the screen's background, no
/// separators, lined up with the rows' text.
private extension View {
    /// A group's heading, 36pt below what's above it: the last group's
    /// pills (their 8 and its 28), or for the `first`, the top bar's
    /// buttons (the list starts 10pt under them).
    func listHeading(first: Bool) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: first ? 26 : 28, leading: LosttyTheme.margin, bottom: 6, trailing: LosttyTheme.margin))
    }

    /// A row of filter pills, scrolling sideways edge to edge; rows of
    /// them stack 8pt apart, 12pt under the heading and 14pt over the
    /// terminals.
    func listPills(first: Bool = true) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: first ? 6 : 0, leading: 0, bottom: 8, trailing: 0))
    }
}
#endif
