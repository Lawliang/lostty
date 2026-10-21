#if os(macOS)
import AppKit
import SwiftUI

/// The What's New card over a terminal window when it's this window's
/// turn (WhatsNewCenter): it dims the window and takes its keys, Return
/// for the card's button and Escape to close it.
struct WhatsNewOverlay: View {
    @ObservedObject var center: WhatsNewCenter = .shared
    /// The window's sidebar model: one per window.
    let window: ObjectIdentifier

    var body: some View {
        ZStack {
            Color.clear.allowsHitTesting(false)
            if let showing = center.showing, showing.window == window {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .transition(.opacity)
                WhatsNewCardView(card: showing.card, restart: center.restart, dismiss: center.dismiss)
                    .padding(24)
                    .background(WhatsNewKeys(primary: primary(showing.card), cancel: center.dismiss))
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: center.showing?.card)
        .onAppear { center.windowOpened(window) }
        .onDisappear { center.windowClosed(window) }
    }

    private func primary(_ card: WhatsNewCard) -> () -> Void {
        switch card {
        case .restart: center.restart
        case .gotIt: center.dismiss
        }
    }
}

/// The Lostty logo, the headline, what's in the build, and Restart to
/// Update (with Later) or Got it.
struct WhatsNewCardView: View {
    let card: WhatsNewCard
    let restart: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image("LosttyIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(LosttyTheme.accent)
                    Text(card.notes.headline)
                        .font(LosttyFont.title)
                        .foregroundStyle(LosttyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !card.notes.summary.isEmpty {
                Text(card.notes.summary)
                    .font(LosttyFont.body)
                    .foregroundStyle(LosttyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }

            if !card.notes.bullets.isEmpty {
                // A long list scrolls; a short one takes only its height.
                ViewThatFits(in: .vertical) {
                    bullets
                    ScrollView { bullets }
                }
                .frame(maxHeight: 260)
                .padding(.top, 14)
            }

            buttons.padding(.top, 22)
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .background(LosttyTheme.surface, in: RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous)
            .strokeBorder(LosttyTheme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var eyebrow: String {
        switch card {
        case .restart: "UPDATE READY"
        case .gotIt: "WHAT'S NEW"
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(card.notes.bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(LosttyTheme.accent)
                    Text(bullet)
                        .foregroundStyle(LosttyTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(LosttyFont.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var buttons: some View {
        switch card {
        case .restart:
            HStack(spacing: 12) {
                Text("Your terminals stay open.")
                    .font(LosttyFont.detail)
                    .foregroundStyle(LosttyTheme.textSecondary)
                Spacer(minLength: 0)
                Button("Later", action: dismiss)
                    .buttonStyle(LosttyButtonStyle(kind: .quiet))
                    .fixedSize()
                Button("Restart to Update", action: restart)
                    .buttonStyle(LosttyButtonStyle(kind: .primary))
                    .fixedSize()
            }
        case .gotIt:
            HStack {
                Spacer(minLength: 0)
                Button("Got it, thanks!", action: dismiss)
                    .buttonStyle(LosttyButtonStyle(kind: .primary))
                    .fixedSize()
            }
        }
    }
}

/// While the card shows, its window's keys go to it: Return presses its
/// button, Escape closes it, and the terminal behind gets none (⌘ shortcuts
/// still work).
private struct WhatsNewKeys: NSViewRepresentable {
    let primary: () -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> KeyView { KeyView() }

    func updateNSView(_ view: KeyView, context: Context) {
        view.primary = primary
        view.cancel = cancel
    }

    final class KeyView: NSView {
        var primary: () -> Void = {}
        var cancel: () -> Void = {}
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, event.window === self.window,
                          !event.modifierFlags.contains(.command) else { return event }
                    switch event.keyCode {
                    case 36, 76: self.primary()
                    case 53: self.cancel()
                    default: break
                    }
                    return nil
                }
            }
        }
    }
}
#endif
