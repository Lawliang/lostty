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
            #expect(AxolotlMotion.frame(pose: .dancing, reduceMotion: true, time: time) == (true, AxolotlMotion.happyLift))
            #expect(AxolotlMotion.frame(pose: .waving, reduceMotion: true, time: time) == (true, AxolotlMotion.happyLift))
        }
    }

    @Test func itDancesOnTheSpotLandingEachBeat() {
        let beat = AxolotlMotion.danceBeat
        for n in 0...8 {
            let step = AxolotlMotion.dance(at: Double(n) * beat)
            #expect(abs(step.hop) < 0.001 && abs(step.sway) < 0.001, "beat \(n)")
        }
        let mid = AxolotlMotion.dance(at: beat / 2)
        #expect(abs(mid.hop - AxolotlMotion.danceHop) < 0.001)
        // Rocks one way on the first beat, the other on the second.
        #expect(mid.sway > 0 && AxolotlMotion.dance(at: 1.5 * beat).sway < 0)
    }

    @Test func itTurnsAllTheWayRoundEveryFourthBeat() {
        let beat = AxolotlMotion.danceBeat
        for time in stride(from: 0.0, to: 3 * beat, by: 0.05) {
            #expect(AxolotlMotion.dance(at: time).spin == 0)
        }
        let halfway = AxolotlMotion.dance(at: 3.5 * beat)
        #expect(abs(halfway.spin - 180) < 0.001 && halfway.sway == 0)
        #expect(abs(AxolotlMotion.dance(at: 4 * beat - 0.0001).spin - 360) < 0.1)
        #expect(AxolotlMotion.dance(at: 4.2 * beat).spin == 0)
    }

    @Test func theHopStaysInsideTheFrame() {
        // Shrunk around its feet (90 down), the top of the drawing sits
        // this far down; a hop must not lift it past the frame's top.
        let top = 90 * (1 - AxolotlMotion.danceScale)
        #expect(AxolotlMotion.danceHop <= top)
    }

    @Test func gillsWiggleToTheBeat() {
        let angles = stride(from: 0.0, through: 1.0, by: 0.025).map(AxolotlMotion.danceGills(at:))
        #expect(angles.allSatisfy { abs($0) <= 8.0001 })
        #expect(angles.contains { $0 > 7 } && angles.contains { $0 < -7 })
    }

    @Test func itWavesToAndFroLeaningLeft() {
        let waves = stride(from: 0.0, through: 1.2, by: 0.025).map(AxolotlMotion.wave(at:))
        let swing = AxolotlMotion.waveSwing
        #expect(waves.allSatisfy { abs($0.arm) <= swing + 0.0001 })
        #expect(waves.contains { $0.arm > swing - 1 } && waves.contains { $0.arm < -swing + 1 })
        // Always leaning over to its left (clockwise), bobbing a little.
        #expect(waves.allSatisfy { $0.lean >= AxolotlMotion.waveLean - AxolotlMotion.waveBob - 0.0001 && $0.lean > 0 })
        #expect(AxolotlMotion.stillWave.lean == AxolotlMotion.waveLean)
    }

    @Test func readyStandsStillButWagsItsTail() {
        #expect(AxolotlMotion.frame(pose: .ready, reduceMotion: false, time: 0.7) == (true, 0))
        let wags = stride(from: 0.0, through: 1.8, by: 0.025).map(AxolotlMotion.wag(at:))
        #expect(wags.allSatisfy { abs($0) <= AxolotlMotion.wagSwing + 0.0001 })
        #expect(wags.contains { $0 > AxolotlMotion.wagSwing - 1 } && wags.contains { $0 < -AxolotlMotion.wagSwing + 1 })
    }

    @Test func sleepingBreathesUnderRisingZs() {
        #expect(AxolotlMotion.frame(pose: .sleeping, reduceMotion: false, time: 0.7).gills < 0)
        for time in stride(from: 0.0, through: 7.2, by: 0.1) {
            let sleep = AxolotlMotion.sleep(at: time)
            #expect(abs(sleep.breath) <= AxolotlMotion.breathDepth + 0.0001)
            #expect(sleep.zs.count == AxolotlMotion.zCount)
            #expect(sleep.zs.allSatisfy { $0 >= 0 && $0 < 1 })
        }
        // The z's are spread out, not rising together.
        let zs = AxolotlMotion.sleep(at: 1).zs
        #expect(Set(zs.map { ($0 * 100).rounded() }).count == AxolotlMotion.zCount)
    }
}
