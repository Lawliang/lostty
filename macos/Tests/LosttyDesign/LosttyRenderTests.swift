#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Ghostty

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

    private func write(_ view: some View, scale: CGFloat, to path: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.nsImage)
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
#endif
