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
/// track; only the ratios matter. Prices from the claude-api skill's model
/// table (cached 2026-10-06).
enum UsageWeights {
    struct Model {
        /// Input price, dollars per million tokens.
        var input: Double
        /// A cache read's price, as a share of input.
        var cacheRead: Double
    }

    static let output = 5.0
    /// Claude Code caches for an hour, and a 1-hour cache write costs 2×.
    static let cacheWrite = 2.0

    /// By the first prefix of the model id that matches.
    static let models: [(prefix: String, model: Model)] = [
        ("claude-fable-5-1", Model(input: 10, cacheRead: 0.025)),
        ("claude-mythos-5-1", Model(input: 10, cacheRead: 0.025)),
        ("claude-fable-5", Model(input: 10, cacheRead: 0.1)),
        ("claude-mythos-5", Model(input: 10, cacheRead: 0.1)),
        ("claude-opus-5-5", Model(input: 4, cacheRead: 0.05)),
        ("claude-opus", Model(input: 5, cacheRead: 0.1)),
        ("claude-sonnet-5", Model(input: 2, cacheRead: 0.1)),
        ("claude-sonnet", Model(input: 3, cacheRead: 0.1)),
        ("claude-haiku-5-5", Model(input: 0.1, cacheRead: 0.1)),
        ("claude-haiku", Model(input: 1, cacheRead: 0.1)),
    ]
    /// An unknown model costs like the current Opus.
    static let otherModel = Model(input: 4, cacheRead: 0.05)

    static func model(_ id: String) -> Model {
        let id = id.lowercased()
        return models.first { id.hasPrefix($0.prefix) }?.model ?? otherModel
    }

    static func weight(_ tokens: TokenCounts, model id: String) -> Double {
        let model = model(id)
        let raw = Double(tokens.input) + Double(tokens.output) * output
            + Double(tokens.cacheWrite) * cacheWrite + Double(tokens.cacheRead) * model.cacheRead
        return raw * model.input
    }

    /// The same weight in current Opus input tokens, each of which weighs 1.
    static func opusInputs(_ tokens: TokenCounts, model id: String) -> Double {
        weight(tokens, model: id) / model("claude-opus-5-5").input
    }
}
#endif
