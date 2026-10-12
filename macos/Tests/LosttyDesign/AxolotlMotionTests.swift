import Testing
@testable import Ghostty

struct AxolotlMotionTests {
    @Test func cursorBlinksOnSixTenthsOffFourTenths() {
        #expect(AxolotlMotion.cursorVisible(at: 0.0))
        #expect(AxolotlMotion.cursorVisible(at: 0.59))
        #expect(!AxolotlMotion.cursorVisible(at: 0.61))
        #expect(!AxolotlMotion.cursorVisible(at: 0.99))
        #expect(AxolotlMotion.cursorVisible(at: 1.1))
    }

    @Test func gillsSwayGentlyAroundRest() {
        let angles = stride(from: 0.0, through: 4.8, by: 0.1).map(AxolotlMotion.gillSway(at:))
        #expect(angles.allSatisfy { abs($0) <= 4.0001 })
        #expect(angles.contains { $0 > 3.5 })
        #expect(angles.contains { $0 < -3.5 })
    }

    @Test func posesFrame() {
        #expect(AxolotlMotion.frame(pose: .resting, reduceMotion: false, time: 0.7) == (true, 0))
        #expect(AxolotlMotion.frame(pose: .happy, reduceMotion: false, time: 0.7) == (true, AxolotlMotion.happyLift))
        #expect(AxolotlMotion.frame(pose: .waiting, reduceMotion: false, time: 0.7).cursor == false)
    }

    @Test func reduceMotionIsStill() {
        for time in [0.0, 0.7, 1.3, 2.9] {
            #expect(AxolotlMotion.frame(pose: .waiting, reduceMotion: true, time: time) == (true, 0))
        }
    }
}
