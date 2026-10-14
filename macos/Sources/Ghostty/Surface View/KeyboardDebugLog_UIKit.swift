#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

extension Ghostty {
    /// Lostty Mobile, while we chase dropped taps and a keyboard that closes
    /// mid-typing: a line for every touch on Lostty's keyboard, every key
    /// press, and every time the keyboard shows or hides (with what hid it).
    /// Read it off the phone with:
    ///
    ///     xcrun devicectl device copy from --device <id> \
    ///       --domain-type appDataContainer --domain-identifier com.lawliang.lostty-mobile \
    ///       --source Library/Caches/keyboard-debug.log --destination keyboard-debug.log
    @MainActor
    enum KeyboardDebugLog {
        static let enabled = true
        /// Past this, the log starts over at the next launch.
        static let maxBytes = 4_000_000

        private static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keyboard-debug.log")
        private static let clock: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f
        }()
        private static var file: FileHandle? = {
            guard enabled else { return nil }
            let fm = FileManager.default
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if size > maxBytes || !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
            handle.seekToEndOfFile()
            handle.write(Data("=== launch \(Date()) ===\n".utf8))
            return handle
        }()

        static func log(_ line: @autoclosure () -> String) {
            guard enabled, let file else { return }
            file.write(Data("\(clock.string(from: Date())) \(line())\n".utf8))
        }

        /// The app's own frames that led here, without UIKit's and Swift's,
        /// so a log line says who asked.
        static func caller() -> String {
            Thread.callStackSymbols.dropFirst(2).compactMap { frame -> String? in
                guard frame.contains("Lostty") else { return nil }
                // "3  Lostty  0x... $s6Lostty...name + 123": the symbol.
                let parts = frame.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 4 else { return nil }
                return parts[3...].joined(separator: " ")
            }
            .prefix(6)
            .joined(separator: " <- ")
        }
    }

    /// Watches every touch on a view without taking part: it never
    /// recognizes, cancels or delays anything, so the keys behave exactly as
    /// without it.
    final class TouchLogRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
        /// What is under a point in the view: a key, a gap, the grabber.
        var describe: ((CGPoint) -> String)?
        private var ids: [ObjectIdentifier: (id: Int, start: CGPoint, time: TimeInterval)] = [:]
        private var next = 1

        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            for touch in touches {
                let point = touch.location(in: view)
                ids[ObjectIdentifier(touch)] = (next, point, touch.timestamp)
                MainActor.assumeIsolated {
                    KeyboardDebugLog.log(String(
                        format: "touch#%d down (%.0f,%.0f) r=%.0f on %@ [fingers %d]",
                        next, point.x, point.y, touch.majorRadius, describe?(point) ?? "?",
                        event.allTouches?.count ?? 1))
                }
                next += 1
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            finish(touches, event, "up")
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            finish(touches, event, "CANCELLED")
        }

        private func finish(_ touches: Set<UITouch>, _ event: UIEvent, _ how: String) {
            for touch in touches {
                guard let begun = ids.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
                let point = touch.location(in: view)
                MainActor.assumeIsolated {
                    KeyboardDebugLog.log(String(
                        format: "touch#%d %@ (%.0f,%.0f) moved %.0fpt after %.0fms on %@",
                        begun.id, how, point.x, point.y,
                        hypot(point.x - begun.start.x, point.y - begun.start.y),
                        (touch.timestamp - begun.time) * 1000, describe?(point) ?? "?"))
                }
            }
            // Never recognizes; failing once every finger is up resets it.
            if ids.isEmpty { state = .failed }
        }

        override func reset() {
            super.reset()
            ids.removeAll()
        }
    }
}

/// A gesture's state, as the log says it.
extension UIGestureRecognizer.State {
    var debugName: String {
        switch self {
        case .possible: "possible"
        case .began: "BEGAN"
        case .changed: "changed"
        case .ended: "ended"
        case .cancelled: "cancelled"
        case .failed: "failed"
        @unknown default: "?"
        }
    }
}
#endif
