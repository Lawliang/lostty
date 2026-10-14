#if os(iOS)
import Combine
import CoreText
import GhosttyKit
import LosttyRemote
import SwiftUI

/// The open terminal's connection events, from its `RemoteSurfaceIO`
/// (delivered on the main thread). The last one is replayed to a late
/// subscriber: the attach can end before the screen starts listening.
@MainActor
final class TerminalLink {
    private let latest = CurrentValueSubject<RemoteLinkStatus?, Never>(nil)
    /// Made once, so the screen's `onReceive` sees the same publisher.
    let events: AnyPublisher<RemoteLinkStatus, Never>

    private let shown = CurrentValueSubject<Bool, Never>(false)
    /// Whether the terminal has drawn anything yet; stays true from then
    /// on, so a warm terminal reopens drawn.
    let drawn: AnyPublisher<Bool, Never>

    init() {
        events = latest.compactMap { $0 }.eraseToAnyPublisher()
        drawn = shown.removeDuplicates().eraseToAnyPublisher()
    }

    func send(_ status: RemoteLinkStatus) {
        latest.send(status)
    }

    func markDrawn() {
        shown.send(true)
    }
}

/// One remote session. Back closes only the connection; "Close Session"
/// ends the session (and its Mac window) after asking. When the session
/// ends from elsewhere, or the connection drops, an overlay over the dimmed
/// last screen says so.
struct TerminalScreen: View {
    let surfaceView: Ghostty.SurfaceView
    let io: RemoteSurfaceIO
    let link: TerminalLink
    @State private var session: RemoteSession
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The session Close Session is asking about.
    @State private var confirmClose: RemoteSession?
    @State private var closeError: String?
    @State private var overlay: TerminalOverlay = .none
    /// Close Session from this screen is under way: its end is ours.
    @State private var closingHere = false
    /// The attach ended while the app was away: explain it on return.
    /// The value is whether input had just been sent.
    @State private var endWhileAway: Bool?
    @State private var renaming: RemoteSession?
    @State private var renameError: String?
    /// The attach's end is being (or was) explained: a replayed `.exited`
    /// must not ask the Mac again.
    @State private var endHandled = false
    /// tmux has drawn the terminal: until then, the axolotl waits over it.
    @State private var drawn = false

    init(session: RemoteSession, surfaceView: Ghostty.SurfaceView, io: RemoteSurfaceIO, link: TerminalLink) {
        _session = State(initialValue: session)
        self.surfaceView = surfaceView
        self.io = io
        self.link = link
    }

    /// This session as last listed: the Mac renames a session when its
    /// shell changes project, so the name it opened with can be stale.
    private var current: RemoteSession {
        RemoteSession.current(of: session, in: store.sessions) ?? session
    }

    private var row: SessionRow { SessionLabel.row(for: current, now: Date()) }
    private var title: String { row.title }

    var body: some View {
        GeometryReader { geo in
            Ghostty.SurfaceRepresentable(view: surfaceView, size: geo.size)
        }
        .opacity(overlay == .none ? 1 : 0.35)
        .allowsHitTesting(overlay == .none)
        .overlay {
            if overlay != .none {
                TerminalOverlayCard(overlay: overlay, title: title) { dismiss() }
                    .transition(.opacity)
            }
        }
        .animation(LosttyTheme.motion, value: overlay)
        .overlay {
            if !drawn && overlay == .none {
                TerminalLoading(skin: current.skin).transition(.opacity)
            }
        }
        .animation(LosttyTheme.motion, value: drawn)
        // Claude's trace round the whole screen while it works.
        .overlay { PhoneTrace(activity: current.claude, skin: current.skin) }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // The whole screen for the terminal and its keyboard.
        .toolbar(.hidden, for: .tabBar)
        // The terminal's own color up to the top edge, under the bar: the
        // bar's buttons float over the terminal, as the list's do once it
        // scrolls. Its text starts below them, so none is hidden.
        .background(TerminalLook.background(skin: current.skin).ignoresSafeArea())
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TerminalTitle(
                    name: title, detail: row.detail,
                    color: TerminalLook.text(skin: current.skin), prompt: TerminalLook.prompt(skin: current.skin),
                    context: current.context)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename") { renaming = current }
                    Button("Close Session", role: .destructive) { confirmClose = current }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.white)
                }
                .tint(.white)
                // Under an overlay the attach is down or the session gone:
                // the id may no longer name this session.
                .disabled(overlay != .none)
            }
        }
        .confirmCloseSession($confirmClose) { target in
            closingHere = true
            Task {
                if await store.kill(target, attached: true) {
                    dismiss()
                } else {
                    closingHere = false
                    closeError = store.message ?? "Couldn't close the session."
                }
            }
        }
        .alert("Couldn't Close Session", isPresented: Binding(get: { closeError != nil }, set: { if !$0 { closeError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(closeError ?? "")
        }
        .renameSession($renaming, attached: true, renamed: { session = $0 }, failed: { renameError = $0 })
        .alert("Couldn't Rename", isPresented: Binding(get: { renameError != nil }, set: { if !$0 { renameError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(renameError ?? "")
        }
        .onAppear {
            // A warm terminal may predate a Text Size (Settings) or skin change.
            applyLook()
            surfaceView.showKeyboardWhenSettled()
        }
        // Back keeps it warm for a quick return; not once it ended or is
        // being closed.
        .onDisappear {
            store.terminalLeft(session, (surfaceView, io, link), keepWarm: !closingHere && !endHandled)
        }
        .onReceive(link.events) { handle($0) }
        .onReceive(link.drawn) { drawn = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let typed = endWhileAway {
                endWhileAway = nil
                explainEnd(typedRecently: typed)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .losttySurfaceClosed)) { note in
            if (note.object as AnyObject?) === surfaceView {
                endHandled = true
                dismiss()
                Task { await store.terminalClosedItself(session) }
            }
        }
    }

    private func applyLook() {
        guard let surface = surfaceView.surface else { return }
        TerminalLook.apply(skin: current.skin, to: surface, overlayDir: TerminalLook.overlayDir)
    }

    private func handle(_ status: RemoteLinkStatus) {
        if case .exited = status {
            guard !closingHere, !endHandled else { return }
            endHandled = true
            let typed = io.wroteRecently(within: SessionEnd.typedWindow)
            if scenePhase == .active {
                explainEnd(typedRecently: typed)
            } else {
                endWhileAway = typed
            }
            return
        }
        let next = overlay.after(status, now: Date())
        guard next != overlay else { return }
        let wasShowing = overlay != .none
        overlay = next
        if next == .none, wasShowing {
            // Only when attached again; after `.stopped` the terminal shows
            // why it gave up, and there is nothing to type into.
            if status == .attached { surfaceView.showKeyboard() }
        } else if next != .none {
            _ = surfaceView.resignFirstResponder()
        }
    }

    /// Asks the Mac why the session ended, then goes back to the list or
    /// says why over the dimmed screen.
    private func explainEnd(typedRecently: Bool) {
        Task {
            let probe = await store.endProbe(session)
            switch SessionEnd.decide(probe: probe, endedHere: closingHere, typedRecently: typedRecently) {
            case .backToList:
                dismiss()
            case .stillRunning:
                dismiss()
                await store.terminalClosedItself(session)
            case .closed(let reason):
                overlay = .closed(reason)
                _ = surfaceView.resignFirstResponder()
            }
        }
    }
}

/// The card over a dimmed terminal: why, which session, and (when closed,
/// or after 30 s of reconnecting) Back to Sessions.
/// A terminal opening, before tmux has drawn it (or being made on the Mac):
/// the axolotl waiting, in the terminal's colors, so the empty screen never
/// shows.
struct TerminalLoading: View {
    let skin: SessionSkin?
    /// For VoiceOver: the screen shows only the axolotl and the spinner.
    var label = "Opening the terminal"

    var body: some View {
        ZStack {
            TerminalLook.background(skin: skin).ignoresSafeArea()
            VStack(spacing: 14) {
                Axolotl(pose: .waiting).frame(width: 120, height: 120)
                // The terminal rows' spinner, in the skin's accent.
                BufferSpinner(color: TerminalLook.prompt(skin: skin))
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

private struct TerminalOverlayCard: View {
    let overlay: TerminalOverlay
    let title: String
    let back: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            LosttyCard(padding: 20) {
                VStack(spacing: 12) {
                    if overlay.isReconnecting {
                        ProgressView().tint(LosttyTheme.accent)
                    }
                    Text(overlay.message ?? "")
                        .font(LosttyFont.bodyEmphasis)
                        .foregroundStyle(LosttyTheme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(title)
                        .font(LosttyFont.mono(.footnote, size: 13))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if overlay.offersBack(now: context.date) {
                        Button("Back to Sessions", action: back)
                            .buttonStyle(.lostty(.primary, fullWidth: true))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 340)
            .padding(LosttyTheme.margin)
        }
    }
}

/// The terminal's top bar: its title, and "> repo/branch" under it, as
/// its row in the list says them, small enough to fit between the buttons.
/// While Claude runs there, it takes turns with the Mac's Context bar
/// (`Context ▓▓░░░░░░░░ 50K`), every five seconds.
struct TerminalTitle: View {
    var name: String
    var detail: String?
    var color: Color = LosttyTheme.textPrimary
    var prompt: Color = LosttyTheme.accent
    var context: SessionContext?

    static let turn: Duration = .seconds(5)

    @State private var showingContext = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if showingContext, let context {
                TerminalContextBar(context: context, color: color, accent: prompt)
                    .transition(turnTransition)
            } else {
                title.transition(turnTransition)
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        // Restarts when Claude starts or stops there: no context, no turns.
        .task(id: context != nil) {
            guard context != nil else {
                showingContext = false
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.turn)
                guard !Task.isCancelled else { return }
                withAnimation(LosttyTheme.motion) { showingContext.toggle() }
            }
        }
    }

    private var title: some View {
        VStack(spacing: 1) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            if let detail {
                HStack(spacing: 4) {
                    Text(">").fontWeight(.heavy).foregroundStyle(prompt)
                    Text(detail).foregroundStyle(color.opacity(0.65))
                }
                .font(LosttyFont.mono(.caption2, size: 11))
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
    }

    /// The next one comes up from below as the last goes up and away.
    private var turnTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity))
    }

    private var accessibilityText: String {
        var parts = [name]
        if let detail { parts.append(detail) }
        if let context { parts.append("context \(Int(context.percent.rounded())) percent full") }
        return parts.joined(separator: ", ")
    }
}

/// The Mac's Context bar, as its usage bar draws it: in the terminal's
/// font, the label dimmed, the meter in the skin's accent (amber past 70%,
/// red past 90%), then the tokens used.
struct TerminalContextBar: View {
    let context: SessionContext
    var color: Color = LosttyTheme.textPrimary
    var accent: Color = LosttyTheme.accent

    var body: some View {
        let percent = context.percent
        let used = UsageMeter.filled(percent)
        return (Text("Context ").foregroundColor(color.opacity(0.6))
            + Text(String(repeating: "▓", count: used)).foregroundColor(fill(percent))
            + Text(String(repeating: "░", count: UsageMeter.cells - used)).foregroundColor(color.opacity(0.28))
            + Text(" " + UsageMeter.thousands(context.used)).foregroundColor(color.opacity(0.9)))
            .font(TerminalFont.font(size: 12))
            .lineLimit(1)
    }

    private func fill(_ percent: Double) -> Color {
        switch UsageMeter.level(percent) {
        case .critical: Color(red: 0.95, green: 0.33, blue: 0.30)
        case .high: Color(red: 0.96, green: 0.68, blue: 0.25)
        case .normal: accent
        }
    }
}

/// The terminal's font (JetBrains Mono, bundled), registered on first use;
/// the system's monospaced font if that fails.
enum TerminalFont {
    private static let name: String? = {
        guard let url = Bundle.main.url(forResource: "JetBrainsMonoNoNF-Regular", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else { return nil }
        if UIFont(name: name, size: 12) == nil {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return UIFont(name: name, size: 12) == nil ? nil : name
    }()

    static func font(size: CGFloat) -> Font {
        name.map { .custom($0, size: size) } ?? .system(size: size, design: .monospaced)
    }
}
#endif
