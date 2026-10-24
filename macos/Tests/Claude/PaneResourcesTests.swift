#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct PaneResourcesTests {
    let pane = UUID()

    @Test func readsTheShellsOfThisLosttysPanes() {
        let other = UUID()
        let output = """
            \(pane.uuidString)\t42\t1001
            \(pane.uuidString)\t42\t1002
            \(other.uuidString)\t7\t2001
            \t\t3001
            not-a-uuid\t42\t4001
            """
        #expect(PaneResourceSampler.shells(output, owner: 42) == [pane: [1001, 1002]])
    }

    @Test func cpuIsTheTimeUsedOverTheTimePassed() {
        // 1 s of one process and 0.5 s of another over 2 s: 75% of a core.
        let percent = PaneResourceMath.cpuPercent(
            previous: [1: 1_000_000_000, 2: 0],
            current: [1: 2_000_000_000, 2: 500_000_000],
            elapsed: 2_000_000_000)
        #expect(percent == 75)
    }

    @Test func aNewProcessCountsAllItsTimeAndAnEndedOneNone() {
        let percent = PaneResourceMath.cpuPercent(
            previous: [1: 5_000_000_000],
            current: [2: 1_000_000_000],
            elapsed: 1_000_000_000)
        #expect(percent == 100)
        #expect(PaneResourceMath.cpuPercent(previous: [:], current: [1: 5], elapsed: 0) == 0)
    }

    @Test func memoryReadsInMegabytesThenGigabytes() {
        #expect(PaneResourceMath.memory(0) == "0M")
        #expect(PaneResourceMath.memory(340 * 1_048_576) == "340M")
        #expect(PaneResourceMath.memory(999 * 1_048_576) == "999M")
        #expect(PaneResourceMath.memory(1_288_490_189) == "1.2G")
    }

    @Test func readsThisProcesssUsage() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let usage = try #require(PaneResourceSampler.usage(pid))
        #expect(usage.cpu > 0)
        #expect(usage.memory > 1_048_576)
        #expect(PaneResourceSampler.tree([pid]).first == pid)
    }
}
#endif
