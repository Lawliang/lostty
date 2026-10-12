#if os(iOS)
import SwiftUI
import VisionKit

/// The camera, looking for one QR code; reports its text once.
struct QRScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    /// The hardware can scan. `DataScannerViewController.isAvailable` is
    /// also false until camera access is granted, so the screen asks first.
    static var isSupported: Bool { DataScannerViewController.isSupported }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onFound: (String) -> Void
        private var reported = false

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !reported else { return }
            for item in added {
                if case .barcode(let code) = item, let text = code.payloadStringValue, text.hasPrefix("lostty://pair") {
                    reported = true
                    scanner.stopScanning()
                    onFound(text)
                    return
                }
            }
        }
    }
}
#endif
