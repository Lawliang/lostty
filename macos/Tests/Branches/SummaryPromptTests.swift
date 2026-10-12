#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SummaryPromptTests {
    @Test func aSmallBranchSendsTheWholeDiff() {
        let prompt = SummaryPrompt.build(branch: "feat", base: "main", log: "Add X\n", diff: "+x\n", stat: "x | 1 +")
        #expect(prompt.contains("\"feat\""))
        #expect(prompt.contains("\"main\""))
        #expect(prompt.contains("Add X"))
        #expect(prompt.contains("Diff:\n+x\n"))
        #expect(!prompt.contains("truncated"))
    }

    @Test func aLargeDiffIsCappedWithTheStatFirst() {
        let diff = String(repeating: "+ some changed line ✨\n", count: 10_000)
        let prompt = SummaryPrompt.build(branch: "feat", base: "main", log: "Add X\n", diff: diff, stat: "a.swift | 900 +")
        #expect(prompt.utf8.count <= SummaryPrompt.limit + 32)
        #expect(prompt.contains("Files changed:\na.swift | 900 +"))
        #expect(prompt.hasSuffix("[diff truncated]"))
    }

    @Test func aHugeLogIsCappedToo() {
        let log = String(repeating: "commit subject\n", count: 20_000)
        let prompt = SummaryPrompt.build(branch: "feat", base: "main", log: log, diff: "+x\n", stat: "x | 1 +")
        #expect(prompt.utf8.count <= SummaryPrompt.limit + 32)
    }
}
#endif
