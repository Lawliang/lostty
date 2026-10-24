#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct CanvasImportTests {
    @Test func aRememberedAnswerIsUsedWithoutAsking() {
        let name = "CanvasImportTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(CanvasImport.remembered(in: defaults) == nil)
        defaults.set(false, forKey: CanvasImport.key)
        #expect(!CanvasImport.shouldMoveAll(3, opening: true, defaults: defaults))
        defaults.set(true, forKey: CanvasImport.key)
        #expect(CanvasImport.shouldMoveAll(3, opening: false, defaults: defaults))
    }
}
#endif
