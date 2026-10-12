#if os(macOS)
import Foundation
import Testing

/// The app is branded Lostty everywhere a user can see it. These read the
/// sources directly so they hold regardless of how the test host is built.
struct AppNameTests {
    // macos/Tests/App/<this file> → repository root.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func menuBarNameIsLostty() throws {
        // CFBundleName feeds the menu bar's bold app name. Xcode generates it
        // from PRODUCT_NAME (Ghostty), so a build phase rewrites it.
        let pbxproj = try Self.read("macos/Ghostty.xcodeproj/project.pbxproj")
        #expect(pbxproj.contains("Set :CFBundleName Lostty"))
    }

    @Test func hostAppBundleIsNamedLostty() {
        // The unit tests are hosted by the app, so this is the shipped plist.
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == "Lostty")
    }

    @Test func mainMenuTitlesNeverSayGhostty() throws {
        let xib = try Self.read("macos/Sources/App/macOS/MainMenu.xib")
        let offenders = xib.split(separator: "\n").filter {
            $0.range(of: #"title="[^"]*Ghostty[^"]*""#, options: .regularExpression) != nil
        }
        #expect(offenders.isEmpty, "MainMenu.xib still titles: \(offenders)")
    }
}
#endif
