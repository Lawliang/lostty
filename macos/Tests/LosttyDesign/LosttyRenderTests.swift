#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Lostty

/// Writes PNGs of the axolotl when LOSTTY_RENDER_DIR is set (for review and
/// for the iPhone launch image); does nothing otherwise.
@MainActor
struct LosttyRenderTests {
    @Test func renderAxolotl() throws {
        guard let dir = ProcessInfo.processInfo.environment["LOSTTY_RENDER_DIR"] else { return }
        let poses = HStack(spacing: 40) {
            Axolotl(pose: .resting).frame(width: 200, height: 200)
            Axolotl(pose: .waiting).frame(width: 200, height: 200)
            Axolotl(pose: .happy).frame(width: 200, height: 200)
        }
        .padding(40)
        .background(LosttyTheme.background)
        try write(poses, scale: 2, to: "\(dir)/axolotl-poses.png")
        for scale in [1, 2, 3] {
            try write(Axolotl(pose: .resting).frame(width: 120, height: 120), scale: CGFloat(scale),
                      to: "\(dir)/LaunchAxolotl@\(scale)x.png")
        }
    }

    #if DEBUG
    /// The Phone Access gallery's states as the window draws them (and the
    /// pairing sheet), for review.
    @Test func renderPhoneAccess() async throws {
        guard let dir = ProcessInfo.processInfo.environment["LOSTTY_RENDER_DIR"] else { return }
        for (title, store) in PhoneAccessGallery.variants() {
            let name = title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            let window = NSWindow(contentViewController: NSHostingController(rootView: PhoneAccessView().environmentObject(store)))
            window.styleMask = [.titled, .closable, .resizable]
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(LosttyTheme.background)
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 560, height: 900))
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .seconds(1.5))
            try snapshot(window.contentView!, to: "\(dir)/mac-\(String(name)).png")
            if let sheet = window.attachedSheet {
                try snapshot(sheet.contentView!, to: "\(dir)/mac-\(String(name))-sheet.png")
            }
            window.close()
        }
    }

    private func snapshot(_ view: NSView, to path: String) throws {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
    #endif

    private func write(_ view: some View, scale: CGFloat, to path: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.nsImage)
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
#endif
