#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct UsageWeightsTests {
    @Test func tokenKindsWeighDifferently() {
        let tokens = TokenCounts(input: 100, output: 10, cacheWrite: 40, cacheRead: 1000)
        // 100 × 1 + 10 × 5 + 40 × 1.25 + 1000 × 0.1, on Haiku (× 1).
        #expect(abs(UsageWeights.weight(tokens, model: "claude-haiku-5-5") - 300) < 1e-9)
    }

    @Test func modelsWeighByFamily() {
        let tokens = TokenCounts(input: 10)
        #expect(UsageWeights.weight(tokens, model: "claude-haiku-5-5") == 10)
        #expect(UsageWeights.weight(tokens, model: "claude-sonnet-5-5") == 30)
        #expect(UsageWeights.weight(tokens, model: "claude-opus-5-5") == 50)
        #expect(UsageWeights.weight(tokens, model: "claude-fable-5-1") == 50)
        #expect(UsageWeights.weight(tokens, model: "Claude-HAIKU-6") == 10)
    }

    @Test func anUnknownModelWeighsLikeOpus() {
        #expect(UsageWeights.weight(TokenCounts(input: 10), model: "something-new") == 50)
        #expect(UsageWeights.weight(TokenCounts(input: 10), model: "") == 50)
    }

    @Test func noTokensWeighNothing() {
        #expect(UsageWeights.weight(TokenCounts(), model: "claude-opus-5-5") == 0)
    }
}
#endif
