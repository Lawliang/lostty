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
                        viewfinder
                        Text("On your Mac, open Lostty → Phone Access → Pair a Phone, then point the camera at the code.")
                            .font(LosttyFont.body)
                            .foregroundStyle(LosttyTheme.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Paste Pairing Link") {
                            let link = UIPasteboard.general.string ?? ""
                            Task { await store.pair(link: link) }
                        }
                        .buttonStyle(.lostty(.secondary))
                    case .finding, .waitingForAllow, .testing:
                        Axolotl(pose: .waiting).frame(width: 120, height: 120).losttyGlow(diameter: 290).padding(.top, 24)
                        Text(waitingTitle)
                            .font(LosttyFont.title)
                            .foregroundStyle(LosttyTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        LosttyCard(padding: 0) { StepIndicator(progress: progress) }
                    case .failed(let text, let canRetryTest):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(LosttyTheme.warning)
                            .padding(.top, 24)
                        Text(text)
                            .font(LosttyFont.body)
                            .foregroundStyle(LosttyTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        if canRetryTest {
                            Button("Try Again") { Task { await store.retryPairingTest() } }
                                .buttonStyle(.lostty(.primary, fullWidth: true))
                        } else {
                            Button("Scan Again") { store.resetPairing() }
                                .buttonStyle(.lostty(.primary, fullWidth: true))
                        }
                    case .done:
                        Axolotl(pose: .happy).frame(width: 140, height: 140).losttyGlow(diameter: 330).padding(.top, 24)
                        Text("Paired.").font(LosttyFont.largeTitle).foregroundStyle(LosttyTheme.textPrimary)
                        Text("Your Mac's sessions are ready.")
                            .font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                    }
                }
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
            Button("Cancel") {
                store.cancelPairing()
                dismiss()
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

    /// The scanner in a rounded frame with magenta corner brackets, or why
    /// there is none.
    @ViewBuilder private var viewfinder: some View {
        if QRScannerView.isSupported && cameraAllowed == true {
            QRScannerView { link in Task { await store.pair(link: link) } }
                .clipShape(RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous))
                .overlay(ViewfinderBrackets().stroke(LosttyTheme.accent,
                                                     style: StrokeStyle(lineWidth: 4, lineCap: .round)))
                .frame(height: 320)
        } else if cameraAllowed == false {
            LosttyCard {
                Text("Lostty can't use the camera. Allow it in Settings → Lostty, or on the Mac click Copy Pairing Link and paste it here.")
                    .font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
            }
        } else if !QRScannerView.isSupported {
            LosttyCard {
                Text("This device can't scan codes. On the Mac, click Copy Pairing Link, then paste it here.")
                    .font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
            }
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
