#if os(iOS)
import LosttyRemote
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// In place of the app while it rests (`MobileStore.resting`): the axolotl
/// asleep and held still, so nothing draws. A tap anywhere wakes it.
struct RestingScreen: View {
    @EnvironmentObject private var store: MobileStore

    var body: some View {
        VStack(spacing: 12) {
            Axolotl(pose: .sleeping, moves: false)
                .frame(width: 104, height: 104)
                .padding(.bottom, 8)
            Text("Resting")
                .font(LosttyFont.largeTitle)
                .foregroundStyle(LosttyTheme.textPrimary)
            Text("Unused for \(Int(AwayClock.limit / 60)) minutes, so Lostty let its connections go.")
                .font(LosttyFont.body)
                .foregroundStyle(LosttyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tap to wake it.")
                .font(LosttyFont.bodyEmphasis)
                .foregroundStyle(LosttyTheme.accent)
                .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 320)
        .padding(LosttyTheme.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LosttyTheme.background.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { store.wake() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Calls `onTouch` for every touch in the window it's placed in, without
/// taking any from the views underneath: how the app knows it's in use.
struct TouchWatcher: UIViewRepresentable {
    var onTouch: @MainActor () -> Void

    func makeUIView(context: Context) -> WatcherView {
        WatcherView(onTouch: onTouch)
    }

    func updateUIView(_ view: WatcherView, context: Context) {
        view.recognizer.onTouch = onTouch
    }

    final class WatcherView: UIView {
        let recognizer = Recognizer()

        init(onTouch: @escaping @MainActor () -> Void) {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            recognizer.onTouch = onTouch
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }
    }

    /// Notes the touch and fails at once, so it never holds up or cancels
    /// another gesture.
    final class Recognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
        var onTouch: @MainActor () -> Void = {}

        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouch()
            state = .failed
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
#endif
