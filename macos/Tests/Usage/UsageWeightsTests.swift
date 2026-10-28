#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct UsageWeightsTests {
    @Test func tokenKindsWeighDifferently() {
        let tokens = TokenCounts(input: 100, output: 10, cacheWrite: 40, cacheRead: 1000)
        // (100 + 10 × 5 + 40 × 2 + 1000 × 0.05) × 4, on Opus 5.5.
        #expect(abs(UsageWeights.weight(tokens, model: "claude-opus-5-5") - 1120) < 1e-9)
        // Fable 5.1 reads its cache at 0.025 of input: (100 + 50 + 80 + 25) × 10.
        #expect(abs(UsageWeights.weight(tokens, model: "claude-fable-5-1") - 2550) < 1e-9)
    }

    @Test func modelsWeighByTheirInputPrice() {
        let tokens = TokenCounts(input: 10)
        #expect(abs(UsageWeights.weight(tokens, model: "claude-haiku-5-5") - 1) < 1e-9)
        #expect(UsageWeights.weight(tokens, model: "claude-haiku-4-5-20251001") == 10)
        #expect(UsageWeights.weight(tokens, model: "claude-sonnet-5-5") == 20)
        #expect(UsageWeights.weight(tokens, model: "claude-sonnet-4-6") == 30)
        #expect(UsageWeights.weight(tokens, model: "claude-opus-5-5") == 40)
        #expect(UsageWeights.weight(tokens, model: "claude-opus-4-8") == 50)
        #expect(UsageWeights.weight(tokens, model: "claude-fable-5-1") == 100)
        #expect(UsageWeights.weight(tokens, model: "Claude-Fable-5") == 100)
    }

    @Test func anUnknownModelWeighsLikeTheCurrentOpus() {
        #expect(UsageWeights.weight(TokenCounts(input: 10), model: "something-new") == 40)
        #expect(UsageWeights.weight(TokenCounts(input: 10), model: "") == 40)
    }

    @Test func opusInputsCountACurrentOpusInputTokenAsOne() {
        #expect(UsageWeights.opusInputs(TokenCounts(input: 7), model: "claude-opus-5-5") == 7)
        #expect(UsageWeights.opusInputs(TokenCounts(input: 2), model: "claude-fable-5-1") == 5)
    }

    @Test func noTokensWeighNothing() {
        #expect(UsageWeights.weight(TokenCounts(), model: "claude-opus-5-5") == 0)
    }
}
#endif
