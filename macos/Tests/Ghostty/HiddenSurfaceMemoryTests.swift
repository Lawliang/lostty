#if os(macOS)
import AppKit
import GhosttyKit
import Testing
@testable import Lostty

/// A terminal that isn't shown gives back its spare frame buffers, and
/// draws again when shown. Real surfaces in a real window: the buffers
/// are the GPU's, so only the process's footprint shows them.
@MainActor
struct HiddenSurfaceMemoryTests {
    static let count = 4
    static let size = NSSize(width: 800, height: 600)

    /// The process's memory as Activity Monitor counts it.
    static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// Waits until `footprint` holds still, and returns it.
    static func settled() async throws -> Int {
        var last = footprint()
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(250))
            let now = footprint()
            if abs(now - last) < 512 * 1024 { return now }
            last = now
        }
        return last
    }

    @Test func hiddenTerminalsGiveBackTheirSpareFrameBuffers() async throws {
        let app = try #require((NSApp.delegate as? AppDelegate)?.ghostty.app)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: Self.size.width * 2, height: Self.size.height * 2)),
            styleMask: [.titled], backing: .buffered, defer: false)
        let views = (0..<Self.count).map { index in
            let view = Ghostty.SurfaceView(app)
            view.frame = NSRect(
                origin: NSPoint(x: CGFloat(index % 2) * Self.size.width, y: CGFloat(index / 2) * Self.size.height),
                size: Self.size)
            window.contentView?.addSubview(view)
            return view
        }
        window.orderFrontRegardless()
        defer { window.close() }
        let scale = window.backingScaleFactor
        for view in views { view.sizeDidChange(view.frame.size) }

        // Enough output that every frame of each swap chain has been drawn.
        func draw() async throws {
            for round in 0..<6 {
                for view in views {
                    guard let surface = view.surface else { continue }
                    ghostty_surface_set_occlusion(surface, true)
                    ghostty_surface_refresh(surface)
                }
                try await Task.sleep(for: .milliseconds(150 + round))
            }
        }
        try await draw()
        let shown = try await Self.settled()

        for view in views { view.surface.map { ghostty_surface_set_occlusion($0, false) } }
        let hidden = try await Self.settled()

        // Each terminal holds three buffers of width x height x 4 bytes and
        // gives back two. Half of that is asked for: the footprint also
        // moves for reasons of its own.
        let buffer = Int(Self.size.width * scale * Self.size.height * scale * 4)
        let expected = Self.count * 2 * buffer
        #expect(shown - hidden >= expected / 2, "shown \(shown >> 20) MB, hidden \(hidden >> 20) MB, expected a drop near \(expected >> 20) MB")

        // Shown again, they draw and take the buffers back.
        try await draw()
        let again = try await Self.settled()
        #expect(again - hidden >= expected / 2, "hidden \(hidden >> 20) MB, shown again \(again >> 20) MB")
    }
}
#endif
