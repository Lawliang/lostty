#if os(macOS)
import AppKit
import Foundation
import GhosttyKit

/// The terminal's font as Lostty Settings shows it. `nil` means "not in the
/// config file", i.e. Ghostty's default.
struct TerminalFontSettings: Equatable {
    var family: String?
    var size: Double?
    /// `adjust-cell-height` as written, e.g. "10%".
    var cellHeight: String?

    static let defaultFamily = "JetBrains Mono"
    static let defaultSize: Double = 13
}

/// Reads and rewrites the font lines of a Ghostty config file, leaving every
/// other line as it was.
enum TerminalFontConfig {
    static let familyKey = "font-family"
    static let sizeKey = "font-size"
    static let cellHeightKey = "adjust-cell-height"
    static let header = "# Terminal font (Lostty Settings)"

    static func read(_ text: String) -> TerminalFontSettings {
        var settings = TerminalFontSettings()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let item = entry(line) else { continue }
            let value = item.value
            switch item.key {
            case familyKey:
                // `font-family = ""` resets the list; the first family after
                // the last reset is the one Ghostty uses first.
                if value.isEmpty {
                    settings.family = nil
                } else if settings.family == nil {
                    settings.family = value
                }
            case sizeKey:
                settings.size = Double(value)
            case cellHeightKey:
                settings.cellHeight = value.isEmpty ? nil : value
            default:
                break
            }
        }
        return settings
    }

    /// Each key's first line is replaced in place and its other lines are
    /// dropped. A key with no line yet is appended under `header`; a `nil`
    /// value removes the key.
    static func write(_ settings: TerminalFontSettings, into text: String) -> String {
        let values: [(String, String?)] = [
            (familyKey, settings.family.map { "\"\($0)\"" }),
            (sizeKey, settings.size.map(format)),
            (cellHeightKey, settings.cellHeight),
        ]
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }

        var placed: Set<String> = []
        lines = lines.compactMap { line in
            guard let key = entry(Substring(line))?.key,
                  let new = values.first(where: { $0.0 == key }) else { return line }
            guard let value = new.1, placed.insert(key).inserted else { return nil }
            return "\(key) = \(value)"
        }

        let missing = values.compactMap { key, value in
            value.flatMap { placed.contains(key) ? nil : "\(key) = \($0)" }
        }
        if !missing.isEmpty {
            if !lines.contains(header) {
                if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append("")
                }
                lines.append(header)
                lines += missing
            } else {
                // Keep the font lines together under our header.
                let index = lines.firstIndex(of: header)! + 1
                lines.insert(contentsOf: missing, at: index)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `key = value` with the value unquoted, or nil for comments and blanks.
    private static func entry(_ line: Substring) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { return nil }
        let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
        var value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        return (key, value)
    }

    private static func format(_ size: Double) -> String {
        size.rounded() == size ? String(Int(size)) : String(size)
    }
}

/// Monospaced font families installed on this Mac.
enum TerminalFontCatalog {
    /// Families picked for legibility (clear 0/O, 1/l/I, open shapes), shown
    /// first when installed.
    static let readable = [
        BundledTerminalFonts.atkinson, BundledTerminalFonts.geist, "SF Mono", "IBM Plex Mono", "Menlo",
        "Source Code Pro", "Fira Code", "Cascadia Code", "Iosevka", "Hack",
    ]

    /// Includes the fonts Lostty ships (`BundledTerminalFonts`).
    static func installedFamilies() -> [String] {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName })
            .union(BundledTerminalFonts.families)
        return families.filter { !$0.hasPrefix(".") }.sorted()
    }
}

/// Lostty Settings → Terminal font. Writes the font lines into the config
/// file (the one ⌘, opens) and reloads it, so every open terminal, and
/// Claude Code or any other agent running in one, redraws in the new font.
@MainActor
final class TerminalFontPreferences: ObservableObject {
    static let shared = TerminalFontPreferences()

    @Published private(set) var settings = TerminalFontSettings()
    @Published private(set) var error: String?

    private let configURL: () -> URL?
    private let reloadConfig: @MainActor () -> Void
    private var pendingWrite: DispatchWorkItem?

    /// Lets a stepper's quick clicks land as one write and one reload.
    private static let debounce: TimeInterval = 0.25

    init(
        configURL: @escaping () -> URL? = TerminalFontPreferences.ghosttyConfigURL,
        reloadConfig: @escaping @MainActor () -> Void = { (NSApp.delegate as? AppDelegate)?.ghostty.reloadConfig() }
    ) {
        self.configURL = configURL
        self.reloadConfig = reloadConfig
    }

    /// Re-reads the config file, which may have been edited by hand.
    func refresh() {
        guard pendingWrite == nil, let url = configURL() else { return }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        settings = TerminalFontConfig.read(text)
    }

    func set(_ new: TerminalFontSettings) {
        guard new != settings else { return }
        settings = new
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.write() }
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
    }

    private func write() {
        pendingWrite = nil
        guard let url = configURL() else { return }
        do {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let updated = TerminalFontConfig.write(settings, into: text)
            guard updated != text else { return }
            // Not atomic: an atomic write would replace a symlinked config
            // (e.g. from a dotfiles repo) with a plain file.
            try updated.write(to: url, atomically: false, encoding: .utf8)
            error = nil
            reloadConfig()
        } catch {
            self.error = "Couldn't save \(url.path): \(error.localizedDescription)"
        }
    }

    /// The config file that wins on this Mac (creating it if there is none).
    private static func ghosttyConfigURL() -> URL? {
        let path = Ghostty.AllocatedString(ghostty_config_open_path()).string
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }
}
#endif
