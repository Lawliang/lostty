#if os(macOS)
import Testing
@testable import Lostty

@MainActor
struct GoldDropTests {
    @Test(arguments: [
        (0, "0"), (999, "999"), (1_000, "1k"), (1_049, "1k"), (1_050, "1.1k"), (4_000, "4k"), (4_200, "4.2k"),
        (9_949, "9.9k"), (9_950, "10k"), (10_000, "10k"), (222_000, "222k"), (999_499, "999k"),
        (999_600, "1M"), (1_000_000, "1M"), (1_234_567, "1.2M"), (12_960_000, "13M"),
    ])
    func label(_ tokens: Int, _ text: String) {
        #expect(GoldDropRuntime.label(tokens) == text)
    }

    @Test func theCoinsEndOnTheStackAndEverythingFadesOut() {
        let landed = GoldDropAnimation.frame(at: 1.1, reduceMotion: false)
        #expect(landed.coins.count == GoldDropAnimation.coins)
        #expect(landed.coins.allSatisfy { $0.lift == 0 && $0.spin == 1 && $0.opacity == 1 })
        #expect(landed.label == 1)
        #expect(GoldDropAnimation.frame(at: GoldDropAnimation.duration, reduceMotion: false).opacity == 0)
        #expect(GoldDropAnimation.frame(at: 0, reduceMotion: false).label == 0)
    }

    @Test func reduceMotionDropsNothing() {
        for t in stride(from: 0.0, through: GoldDropAnimation.duration, by: 0.1) {
            #expect(GoldDropAnimation.frame(at: t, reduceMotion: true).coins.allSatisfy { $0.lift == 0 })
        }
    }
}
#endif
