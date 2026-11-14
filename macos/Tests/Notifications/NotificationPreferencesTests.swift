#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct NotificationPreferencesTests {
    let defaults = UserDefaults(suiteName: "NotificationPreferencesTests-\(UUID().uuidString)")!
    let marker = FileManager.default.temporaryDirectory
        .appendingPathComponent("lostty-mute-\(UUID().uuidString)/notifications-muted")

    @Test func mutingSavesWritesTheMarkerAndClearsWhatShows() {
        let preferences = NotificationPreferences(defaults: defaults, marker: marker)
        var cleared = 0
        preferences.onMute = { cleared += 1 }
        #expect(!preferences.muted)
        #expect(!FileManager.default.fileExists(atPath: marker.path))

        preferences.muted = true
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(cleared == 1)
        #expect(NotificationPreferences(defaults: defaults, marker: marker).muted)

        preferences.muted = false
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(cleared == 1)
    }

    @Test func aMutedCenterDropsBubblesAndNotices() {
        var muted = true
        let bubbles = LosttyNotifications(muted: { muted }, schedule: { _, _ in })
        let notices = TerminalNotices(muted: { muted }, schedule: { _, _ in })
        let pane = UUID()
        notices.awaitingChanged([pane])

        bubbles.post(LosttyNotification(kind: .update, title: "Title", detail: "Detail"))
        notices.post(TerminalNotice(pane: pane, title: "Fix the login", project: nil, recap: RequestRecap()))
        #expect(bubbles.items.isEmpty)
        #expect(notices.items.isEmpty)

        muted = false
        bubbles.post(LosttyNotification(kind: .update, title: "Title", detail: "Detail"))
        notices.post(TerminalNotice(pane: pane, title: "Fix the login", project: nil, recap: RequestRecap()))
        #expect(bubbles.items.count == 1)
        #expect(notices.items.count == 1)

        bubbles.clear()
        notices.clear()
        #expect(bubbles.items.isEmpty)
        #expect(notices.items.isEmpty)
    }
}
#endif
