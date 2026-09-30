#if os(macOS)
import Combine
import Foundation

/// Background colors the user saved from the picker's "Any color" row
/// (spec §6). Stored in state/saved-colors.json, never in skins.toml.
@MainActor
final class SavedColorsStore: ObservableObject {
    static let maxColors = 24

    @Published private(set) var colors: [RGB] = []
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    func contains(_ color: RGB) -> Bool { colors.contains(color) }

    func add(_ color: RGB) {
        guard !colors.contains(color) else { return }
        colors.append(color)
        if colors.count > Self.maxColors { colors.removeFirst(colors.count - Self.maxColors) }
        save()
    }

    func remove(_ color: RGB) {
        colors.removeAll { $0 == color }
        save()
    }

    private struct File: Codable {
        var version: Int
        var colors: [String]
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            colors = []
            return
        }
        var unique: [RGB] = []
        for color in file.colors.compactMap(RGB.init(hex:)) where !unique.contains(color) {
            unique.append(color)
        }
        colors = Array(unique.suffix(Self.maxColors))
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(File(version: 1, colors: colors.map(\.hex)))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Ghostty.logger.warning("skins: failed to save colors: \(String(describing: error))")
        }
    }
}
#endif
