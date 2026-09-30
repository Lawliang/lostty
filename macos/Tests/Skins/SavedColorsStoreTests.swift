#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SavedColorsStoreTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("skins-saved-\(UUID().uuidString)/saved-colors.json")
    }

    @Test func addPersistsAndDedupes() {
        let url = tempFile()
        let store = SavedColorsStore(fileURL: url)
        store.add(RGB(hex: "#2a0f3d")!)
        store.add(RGB(hex: "#2a0f3d")!)
        store.add(RGB(hex: "#101010")!)
        #expect(store.colors.map(\.hex) == ["#2a0f3d", "#101010"])
        #expect(SavedColorsStore(fileURL: url).colors.map(\.hex) == ["#2a0f3d", "#101010"])
    }

    @Test func removePersists() {
        let url = tempFile()
        let store = SavedColorsStore(fileURL: url)
        store.add(RGB(hex: "#2a0f3d")!)
        store.remove(RGB(hex: "#2a0f3d")!)
        #expect(SavedColorsStore(fileURL: url).colors.isEmpty)
    }

    @Test func capsAtMaxKeepingNewest() {
        let store = SavedColorsStore(fileURL: tempFile())
        for i in 0..<30 { store.add(RGB(r: UInt8(i), g: 0, b: 0)) }
        #expect(store.colors.count == SavedColorsStore.maxColors)
        #expect(store.colors.first == RGB(r: 6, g: 0, b: 0))
        #expect(store.colors.last == RGB(r: 29, g: 0, b: 0))
    }

    @Test func malformedFileLoadsValidEntries() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let jsonString = "{\"version\":1,\"colors\":[\"#ff0000\",\"nope\",\"#FF0000\",\"#00ff00\"]}"
        try jsonString.write(to: url, atomically: true, encoding: .utf8)
        #expect(SavedColorsStore(fileURL: url).colors.map(\.hex) == ["#ff0000", "#00ff00"])
        try "garbage".write(to: url, atomically: true, encoding: .utf8)
        #expect(SavedColorsStore(fileURL: url).colors.isEmpty)
    }
}
#endif
