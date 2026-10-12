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
        VStack(spacing: 20) {
            switch store.pairing {
            case .idle:
                Text("On your Mac, open Lostty → Phone Access → Pair a Phone, then point the camera at the code.")
                    .multilineTextAlignment(.center)
                if QRScannerView.isSupported && cameraAllowed == true {
                    QRScannerView { link in Task { await store.pair(link: link) } }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxHeight: 360)
                } else if cameraAllowed == false {
                    Text("Lostty can't use the camera. Allow it in Settings → Lostty, or on the Mac click Copy Pairing Link and paste it here.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else if !QRScannerView.isSupported {
                    Text("This device can't scan codes. On the Mac, click Copy Pairing Link, then paste it here.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button("Paste Pairing Link") {
                    let link = UIPasteboard.general.string ?? ""
                    Task { await store.pair(link: link) }
                }
            case .finding:
                ProgressView("Looking for your Mac nearby…")
            case .waitingForAllow:
                ProgressView("Click Allow on your Mac.")
            case .testing:
                ProgressView("Connecting over Tailscale…")
            case .failed(let text, let canRetryTest):
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(text).multilineTextAlignment(.center)
                if canRetryTest {
                    Button("Try Again") { Task { await store.retryPairingTest() } }
                } else {
                    Button("Scan Again") { store.resetPairing() }
                }
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("Paired. Your Mac's sessions are ready.")
                Button("Done") { dismiss() }
            }
        }
        .padding()
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

    /// Pairs with a link the Camera app opened Lostty with.
    private func startPendingLink() {
        guard let link = store.takePendingPairingLink() else { return }
        Task { await store.pair(link: link) }
    }
}
#endif
