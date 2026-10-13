#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

/// Scan the Mac's code, then follow pairing to the end.
struct PairingScreen: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed: Bool?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    switch store.pairing {
                    case .idle:
                        if let problem = cameraProblem {
                            // No way to scan: say why, and pair by link.
                            UhOh(headline: problem,
                                 detail: "On your Mac, open Lostty → Phone Access → Pair a Phone and click Copy Pairing Link. Then paste it here.") {
                                pasteButton(.primary)
                                if cameraAllowed == false {
                                    Button("Open Settings") {
                                        if let url = URL(string: UIApplication.openSettingsURLString) {
                                            UIApplication.shared.open(url)
                                        }
                                    }
                                    .buttonStyle(.lostty(.secondary, fullWidth: true))
                                }
                            }
                            .containerRelativeFrame(.vertical)
                        } else {
                            viewfinder
                            Text("On your Mac, open Lostty → Phone Access → Pair a Phone, then point the camera at the code.")
                                .font(LosttyFont.body)
                                .foregroundStyle(LosttyTheme.textSecondary)
                                .multilineTextAlignment(.center)
                            pasteButton(.secondary)
                        }
                    case .finding, .waitingForAllow, .testing:
                        Axolotl(pose: .waiting).frame(width: 120, height: 120).losttyGlow(diameter: 290).padding(.top, 24)
                        Text(waitingTitle)
                            .font(LosttyFont.title)
                            .foregroundStyle(LosttyTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        LosttyCard(padding: 0) { StepIndicator(progress: progress) }
                    case .failed(let text, let canRetryTest):
                        UhOh(headline: "Pairing didn't finish", detail: text) {
                            if canRetryTest {
                                Button("Try Again") { Task { await store.retryPairingTest() } }
                                    .buttonStyle(.lostty(.primary, fullWidth: true))
                            } else {
                                // "Scan" only where there's a camera to scan with.
                                Button(cameraProblem == nil ? "Scan Again" : "Start Over") { store.resetPairing() }
                                    .buttonStyle(.lostty(.primary, fullWidth: true))
                            }
                        }
                        .containerRelativeFrame(.vertical)
                    case .done:
                        // In the middle of the screen, the axolotl waving hello.
                        VStack(spacing: 20) {
                            Axolotl(pose: .waving).frame(width: 140, height: 140).losttyGlow(diameter: 330)
                            Text("Paired.").font(LosttyFont.largeTitle).foregroundStyle(LosttyTheme.textPrimary)
                            Text("Your Mac's sessions are ready.")
                                .font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                        }
                        .containerRelativeFrame(.vertical)
                    }
                }
                // Full width, so a glow wider than the text isn't cut off at
                // the text's edges.
                .frame(maxWidth: .infinity)
                .padding(LosttyTheme.margin)
            }
            .safeAreaInset(edge: .bottom) {
                if store.pairing == .done {
                    Button("Done") { dismiss() }
                        .buttonStyle(.lostty(.primary, fullWidth: true))
                        .padding(LosttyTheme.margin)
                }
            }
        }
        .sensoryFeedback(.success, trigger: store.pairing == .done) { _, done in done }
        .losttyScreen()
        .navigationTitle("Pair with Mac")
        .toolbar {
            // Once paired there's nothing to cancel: Done closes it.
            if store.pairing != .done {
                Button("Cancel") {
                    store.cancelPairing()
                    dismiss()
                }
            }
        }
        .onAppear {
            store.resetPairing()
            startPendingLink()
        }
        .onChange(of: store.pendingPairingLink) { _, _ in startPendingLink() }
        .task {
            guard QRScannerView.isSupported else { return }
            cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
        }
        .onDisappear {
            if store.pairing == .done { store.resetPairing() } else { store.cancelPairing() }
        }
    }

    /// Why the camera can't scan, in a line; nil when it can (or is still
    /// being asked for).
    private var cameraProblem: String? {
        if !QRScannerView.isSupported {
            // No camera at all (the simulator), or one too old to read
            // codes (before the A12).
            return AVCaptureDevice.default(for: .video) == nil
                ? "This device has no camera" : "This iPhone can't scan codes"
        }
        return cameraAllowed == false ? "Lostty can't use the camera" : nil
    }

    private func pasteButton(_ kind: LosttyButtonStyle.Kind) -> some View {
        Button("Paste Pairing Link") {
            let link = UIPasteboard.general.string ?? ""
            Task { await store.pair(link: link) }
        }
        .buttonStyle(.lostty(kind, fullWidth: kind == .primary))
    }

    /// The scanner in a rounded frame with magenta corner brackets; empty
    /// until the camera may be used.
    @ViewBuilder private var viewfinder: some View {
        if QRScannerView.isSupported && cameraAllowed == true {
            QRScannerView { link in Task { await store.pair(link: link) } }
                .clipShape(RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous))
                .overlay(ViewfinderBrackets().stroke(LosttyTheme.accent,
                                                     style: StrokeStyle(lineWidth: 4, lineCap: .round)))
                .frame(height: 320)
        }
    }

    private var progress: PairingProgress {
        switch store.pairing {
        case .finding: .finding
        case .waitingForAllow: .waitingForAllow
        case .testing: .testing
        case .done: .finished
        case .idle, .failed: .notStarted
        }
    }

    private var waitingTitle: String {
        switch store.pairing {
        case .finding: "Looking for your Mac nearby…"
        case .waitingForAllow: "Waiting for your Mac to say yes…"
        default: "Connecting over Tailscale…"
        }
    }

    /// Pairs with a link the Camera app opened Lostty with.
    private func startPendingLink() {
        guard let link = store.takePendingPairingLink() else { return }
        Task { await store.pair(link: link) }
    }
}

/// Four corner brackets, inset from the viewfinder's edge.
private struct ViewfinderBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 18, arm: CGFloat = 28
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                 (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        return path
    }
}
#endif
