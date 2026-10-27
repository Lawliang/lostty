#if os(macOS)
import Foundation

/// One reply's or one run's tokens, by kind.
struct TokenCounts: Codable, Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
}

/// How fast tokens use up a plan limit, relative to each other (usage
/// breakdown spec §1). A stand-in for API price, which Anthropic's limits
/// track; only the ratios matter. Fable counts like Opus until better known.
enum UsageWeights {
    static let input = 1.0
    static let output = 5.0
    static let cacheWrite = 1.25
    static let cacheRead = 0.1

    /// By the model id's family ("claude-haiku-5-5" → Haiku).
    static let families: [(name: String, weight: Double)] = [
        ("haiku", 1), ("sonnet", 3), ("opus", 5), ("fable", 5),
    ]
    static let otherModel = 5.0

    static func model(_ id: String) -> Double {
        let id = id.lowercased()
        return families.first { id.contains($0.name) }?.weight ?? otherModel
    }

    static func weight(_ tokens: TokenCounts, model id: String) -> Double {
        let raw = Double(tokens.input) * input + Double(tokens.output) * output
            + Double(tokens.cacheWrite) * cacheWrite + Double(tokens.cacheRead) * cacheRead
        return raw * model(id)
    }

    /// The same weight in Opus input tokens, each of which weighs 1.
    static func opusInputs(_ tokens: TokenCounts, model id: String) -> Double {
        weight(tokens, model: id) / model("opus")
    }
}
#endif
