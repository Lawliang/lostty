#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SkinConfigStoreTests {
    private func makeStore() throws -> (SkinConfigStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skins-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("skins.toml")
        return (SkinConfigStore(fileURL: file, home: "/h"), file)
    }

    @Test func missingFileIsEmptyConfig() throws {
        let (store, _) = try makeStore()
        store.reload()
        #expect(store.config == .empty)
        #expect(store.error == nil)
    }

    @Test func keepsLastGoodConfigOnError() throws {
        let (store, file) = try makeStore()
        var changes = 0
        store.onChange = { changes += 1 }

        try "[skins.a]\nbackground = \"#000000\"\n".write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.config.skins["a"] != nil)
        #expect(store.error == nil)

        try "[skins.a]\nbackground = \"#0000".write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.config.skins["a"] != nil)
        #expect(store.error?.contains("line 2") == true)

        try "[skins.b]\nbackground = \"#ffffff\"\n".write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.config.skins["b"] != nil)
        #expect(store.error == nil)
        #expect(changes == 3)
    }
}
#endif
