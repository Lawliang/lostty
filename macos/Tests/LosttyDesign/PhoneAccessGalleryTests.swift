#if os(macOS) && DEBUG
import Testing
@testable import Ghostty

/// A Design Gallery store is frozen: it never probes the Mac.
@MainActor
struct PhoneAccessGalleryTests {
    @Test func galleryStoreIgnoresRefresh() {
        let status = PhoneAccessStatus(
            tailscale: nil, tmuxPath: nil, remoteLogin: false, authMethods: nil,
            lockdownFileExists: false, blockAllIncoming: false, terminfoInstalled: false)
        let phones = [PairedPhone(id: "a", name: "iPhone 13", paired: nil)]
        let store = PhoneAccessStore.gallery(status: status, lockdownSkipped: true, phones: phones)
        store.refresh()
        #expect(!store.checking)
        #expect(store.status == status)
        #expect(store.phones == phones)
        #expect(store.lockdownSkipped)
    }
}
#endif
