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
    /// A terminal asked of the Mac, shown being made until it opens.
    @State private var creating: NewTerminalRequest?
    @State private var confirmKill: RemoteSession?
    @State private var renaming: RemoteSession?
    /// The Active filter pill tapped, if any.
    @State private var filter: ActiveState?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.settings.remoteHost == nil {
                    WelcomeScreen(pair: { showPairing = true }, settings: openSettings)
                } else {
                    sessionList
                }
            }
            // A big title in the top bar, rather than a large title under it:
            // the app's name, the axolotl peeking out from behind its L.
            // In iOS's own large-title place, not the leading one, which
            // would morph into the terminal's back button as an empty glass
            // capsule. The plain title stays for VoiceOver and older iOS.
            // Only over the list: the welcome has its own.
            .navigationTitle(store.settings.remoteHost != nil ? "Lostty" : "")
            .toolbarTitleDisplayMode(.inlineLarge)
            .losttyScreen()
            .toolbar {
                if #available(iOS 26, *), store.settings.remoteHost != nil {
                    ToolbarItem(placement: .largeTitle) {
                        HStack(spacing: 0) {
                            PeekingAxolotl()
                            Text("Lostty")
                                .font(LosttyFont.largeTitle)
                                .foregroundStyle(LosttyTheme.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                                .fixedSize()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Level with the + (its own toolbar item, so no
                        // shared alignment): the large title sits lower.
                        .offset(y: Self.titleLift)
                    }
                }
                // A new terminal, here and on the Mac.
                if store.settings.remoteHost != nil && !showsProblem {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewTerminal = true } label: {
                            Image(systemName: "plus").foregroundStyle(.white)
                        }
                        .tint(.white)
                        .accessibilityLabel("New Terminal")
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
            .sheet(isPresented: $showPairing, onDismiss: { store.restartWatch() }) {
                NavigationStack { PairingScreen() }
            }
            .confirmCloseSession($confirmKill) { session in
                Task { await store.kill(session) }
            }
            .renameSession($renaming)
            .onAppear {
                if path.isEmpty { store.listAppeared() }
                if store.pendingPairingLink != nil { showPairing = true }
            }
            .onChange(of: store.pendingPairingLink) { _, link in if link != nil { showPairing = true } }
            .onChange(of: path) { _, newPath in
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
            let states = Dictionary(uniqueKeysWithValues: groups.active.map {
                ($0.id, ActiveState(SessionLabel.row(for: $0, now: context.date).status))
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
                if !groups.active.isEmpty {
                    Section {
                        ForEach(groups.active.filter { shown == nil || states[$0.id] == shown }, id: \.id) { session in
                            row(session, now: context.date)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader("Connected", count: groups.active.count, tint: LosttyTheme.success)
                            statePills(counts: counts, selected: shown)
                        }
                    }
                }
                if !groups.inactive.isEmpty {
                    Section {
                        // No Mac window shows them: still there to open or
                        // close, but quieter.
                        ForEach(groups.inactive, id: \.id) { session in
                            row(session, now: context.date).opacity(0.55)
                        }
                    } header: {
                        sectionHeader("Disconnected", count: groups.inactive.count, tint: LosttyTheme.textSecondary)
                    }
                }
            }
            .listStyle(.plain)
            // Forget a filter once its last terminal moves on, so it doesn't
            // come back by itself later.
            .onChange(of: shown) { _, now in if now == nil { filter = nil } }
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
    /// Measured: the title's capitals and the axolotl centered 8.5pt
    /// below the + button's center.
    static let titleLift: CGFloat = -8.5

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

    private func row(_ session: RemoteSession, now: Date) -> some View {
        Button {
            guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else { return }
            open = (session, terminal.view, terminal.io, terminal.link)
            path = ["terminal"]
        } label: {
            SessionRowView(
                row: SessionLabel.row(for: session, now: now),
                texture: session.skin.flatMap { TextureTile.image(for: $0, displayScale: displayScale) })
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // Edge to edge: each terminal is a full-width band.
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        .swipeActions {
            Button("Close", role: .destructive) { confirmKill = session }.tint(LosttyTheme.danger)
            Button("Rename") { renaming = session }.tint(LosttyTheme.accent)
        }
    }

    /// One pill per state with terminals in it, in `ActiveState` order. A
    /// tap shows only that state; another tap shows them all.
    private func statePills(counts: [ActiveState: Int], selected: ActiveState?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActiveState.allCases.filter { counts[$0, default: 0] > 0 }, id: \.self) { state in
                    let on = state == selected
                    Button {
                        withAnimation(LosttyTheme.motion) { filter = on ? nil : state }
                    } label: {
                        HStack(spacing: 6) {
                            Text(state.title)
                            // The count in a circle darker than the pill (a
                            // capsule once it needs two digits).
                            Text("\(counts[state, default: 0])")
                                .monospacedDigit()
                                .fontWeight(.heavy)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Color.black.opacity(on ? 0.12 : 0.4), in: Capsule())
                        }
                        .font(LosttyFont.detail.weight(.semibold))
                        .foregroundStyle(on ? Color.black : LosttyTheme.textPrimary)
                        .padding(.leading, 12)
                        .padding(.trailing, 4)
                        .padding(.vertical, 4)
                        .background(on ? Color.white : LosttyTheme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color.clear : LosttyTheme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.leading, 2)
        }
    }

    /// "Connected (3)": the count in a soft pill tinted `tint`.
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
        .padding(.leading, 2)
        .accessibilityElement(children: .combine)
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
                if let tile = texture, let opacity = row.skin?.texture?.opacity {
                    Image(decorative: tile, scale: displayScale)
                        .resizable(resizingMode: .tile)
                        .opacity(opacity)
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

/// The shadow an axolotl stands on: a soft dark oval under its feet.
private struct MascotPlatform: View {
    var body: some View {
        Ellipse()
            .fill(RadialGradient(
                colors: [.black.opacity(0.45), .black.opacity(0)], center: .center, startRadius: 0, endRadius: 22))
            .frame(width: 46, height: 11)
            .offset(y: -1)
            .accessibilityHidden(true)
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
private struct RowColors {
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
#endif
