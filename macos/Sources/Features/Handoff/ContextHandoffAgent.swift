#if os(macOS)
import Foundation

/// What a fresh Claude window needs typed back after /clear (spec §4
/// step 6). The desk check (Task 8) settles what /clear keeps.
@MainActor
enum ContextHandoffAgent {
    /// Whether /clear keeps the model; false types `/model <alias>`.
    static var keepsModel = true

    /// `/model`'s alias for the usage feed's display name ("Opus 4.7" → "opus").
    nonisolated static func modelAlias(_ display: String?) -> String? {
        guard let first = display?.split(separator: " ").first?.lowercased() else { return nil }
        return ["opus", "sonnet", "haiku", "fable"].contains(first) ? first : nil
    }

    static func restoreLines(model: String?) -> [String] {
        guard !keepsModel, let alias = modelAlias(model) else { return [] }
        return ["/model \(alias)"]
    }
}
#endif
