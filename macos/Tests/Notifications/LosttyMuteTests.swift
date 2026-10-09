#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct LosttyMuteTests {
    @Test func muteIsRememberedAndReadableOffTheMainActor() {
        let name = "LosttyMuteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let mute = LosttyMute(defaults: defaults)
        #expect(!mute.isMuted)
        #expect(!LosttyMute.isMuted(in: defaults))
        mute.isMuted = true
        #expect(LosttyMute.isMuted(in: defaults))
        #expect(LosttyMute(defaults: defaults).isMuted)
    }
}
#endif
