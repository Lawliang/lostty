import SwiftUI

/// Lostty's mascot, a chibi axolotl. `.waiting` blinks its cursor eye and
/// sways its gills; `.happy` lifts its gills and holds a check; `.dancing`
/// dances on the spot: hops to the beat rocking on its feet, turns all the
/// way round every fourth beat, gills wiggling; `.waving` leans to its own
/// left and waves its right hand high above, to get your attention;
/// `.ready` stands still but for a wagging tail; `.sleeping` sleeps, eyes
/// shut and gills drooping, breathing slowly under rising z's.
/// Decorative: hidden from VoiceOver.
struct Axolotl: View {
    enum Pose: Equatable { case resting, waiting, happy, dancing, waving, ready, sleeping }

    var pose: Pose = .resting
    /// Whether `.waiting`'s cursor eye blinks; off, it stays lit.
    var blinks = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if pose != .resting && pose != .happy && !reduceMotion {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let frame = AxolotlMotion.frame(pose: pose, reduceMotion: false, time: time)
                    drawing(cursor: frame.cursor || !blinks, gills: frame.gills,
                            step: pose == .dancing ? AxolotlMotion.dance(at: time) : nil,
                            wave: pose == .waving ? AxolotlMotion.wave(at: time) : nil,
                            tail: pose == .ready ? AxolotlMotion.wag(at: time) : 0,
                            sleep: pose == .sleeping ? AxolotlMotion.sleep(at: time) : nil)
                }
            } else {
                let frame = AxolotlMotion.frame(pose: pose, reduceMotion: reduceMotion, time: 0)
                drawing(cursor: frame.cursor, gills: frame.gills,
                        wave: pose == .waving ? AxolotlMotion.stillWave : nil,
                        sleep: pose == .sleeping ? AxolotlMotion.stillSleep : nil)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// `step`: where the dance has it; nil stands still, full size.
    /// `wave`: the raised arm and lean of the waving pose. `tail`: its
    /// wag, degrees. `sleep`: eyes shut, breathing and z's.
    private func drawing(
        cursor: Bool, gills: Double, step: AxolotlStep? = nil, wave: AxolotlWave? = nil,
        tail: Double = 0, sleep: AxolotlSleep? = nil
    ) -> some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width, geometry.size.height) / 100
            ZStack {
                AxolotlPart(kind: .tail).fill(AxolotlGeometry.shade)
                    .rotationEffect(.degrees(tail), anchor: AxolotlGeometry.tailAnchor)
                AxolotlPart(kind: .body).fill(AxolotlGeometry.shade)
                AxolotlPart(kind: .belly).fill(AxolotlGeometry.skin)
                AxolotlPart(kind: wave == nil ? .limbs : .limbsWaving).fill(AxolotlGeometry.skin)
                ForEach([AxolotlSide.left, .right], id: \.self) { side in
                    AxolotlPart(kind: .gills(side)).fill(LosttyTheme.accent)
                        // Left gills turn one way, right the other: a mirrored sway.
                        .rotationEffect(.degrees(side == .left ? gills : -gills),
                                        anchor: AxolotlGeometry.gillAnchor(side))
                }
                AxolotlPart(kind: .head).fill(AxolotlGeometry.skin)
                AxolotlPart(kind: .highlight).fill(Color.white.opacity(0.35))
                AxolotlPart(kind: .blush).fill(LosttyTheme.accent.opacity(0.45))
                if let wave {
                    // In front of the head; outlined in the body's shade so
                    // it doesn't melt into the cheek.
                    raisedArm(unit: unit)
                        .rotationEffect(.degrees(wave.arm), anchor: AxolotlGeometry.shoulderAnchor)
                }
                if sleep != nil {
                    AxolotlSleepingEyes()
                        .stroke(AxolotlGeometry.ink,
                                style: StrokeStyle(lineWidth: 3.6 * unit, lineCap: .round, lineJoin: .round))
                } else {
                    AxolotlEyes(cursorVisible: cursor)
                        .stroke(AxolotlGeometry.ink,
                                style: StrokeStyle(lineWidth: 4.4 * unit, lineCap: .round, lineJoin: .round))
                }
                AxolotlMouth()
                    .stroke(AxolotlGeometry.ink,
                            style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round, lineJoin: .round))
                if pose == .happy {
                    AxolotlCheck()
                        .stroke(LosttyTheme.accent,
                                style: StrokeStyle(lineWidth: 4 * unit, lineCap: .round, lineJoin: .round))
                }
            }
            // Breathing: a slow rise and fall from the feet.
            .scaleEffect(x: 1, y: 1 + (sleep?.breath ?? 0), anchor: AxolotlMotion.feet)
            .modifier(AxolotlStepEffect(step: step, unit: unit))
            .modifier(AxolotlLeanEffect(lean: wave?.lean))
            if let sleep {
                ForEach(Array(sleep.zs.enumerated()), id: \.offset) { _, rise in
                    sleepingZ(rise: rise, unit: unit)
                }
            }
        }
    }

    /// One z, `rise` (0...1) of the way from just above the head to the
    /// top right corner: growing, fading in and then out.
    private func sleepingZ(rise: Double, unit: CGFloat) -> some View {
        Text("z")
            .font(.system(size: (8 + 7 * rise) * unit, weight: .heavy, design: .rounded))
            .foregroundStyle(LosttyTheme.accent)
            .opacity(sin(rise * .pi))
            .position(x: (66 + 22 * rise) * unit, y: (16 - 14 * rise) * unit)
    }

    private func raisedArm(unit: CGFloat) -> some View {
        let outline = StrokeStyle(lineWidth: 1.6 * unit)
        return ZStack {
            AxolotlRaisedArm(part: .arm).fill(AxolotlGeometry.skin)
            AxolotlRaisedArm(part: .arm).stroke(AxolotlGeometry.shade, style: outline)
            AxolotlRaisedArm(part: .hand).fill(AxolotlGeometry.skin)
            AxolotlRaisedArm(part: .hand).stroke(AxolotlGeometry.shade, style: outline)
            // Skin, not accent: they sit by the gills, which are accent.
            AxolotlRaisedArm(part: .marks)
                .stroke(AxolotlGeometry.skin, style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round))
        }
    }
}

/// The sleeping axolotl at one moment.
struct AxolotlSleep: Equatable {
    /// How far it's breathed in: a fraction of its height, ±.
    var breath: Double
    /// Each z's rise, 0...1.
    var zs: [Double]
}

/// The waving axolotl at one moment.
struct AxolotlWave: Equatable {
    /// The raised arm's swing from where it's drawn, degrees clockwise.
    var arm: Double
    /// Leaning to its own left (the viewer's right), degrees clockwise.
    var lean: Double
}

/// Leans the waving axolotl over from its feet, a little smaller so its
/// head and gills stay inside the frame.
private struct AxolotlLeanEffect: ViewModifier {
    let lean: Double?

    func body(content: Content) -> some View {
        if let lean {
            content
                .scaleEffect(AxolotlMotion.waveScale, anchor: AxolotlMotion.feet)
                .rotationEffect(.degrees(lean), anchor: AxolotlMotion.feet)
        } else {
            content
        }
    }
}

/// The dancing axolotl's pose at one moment, on the spot.
struct AxolotlStep: Equatable {
    /// How high it is off the ground, in drawing units (the frame is 100).
    var hop: Double
    /// Rocking on its feet, degrees clockwise.
    var sway: Double
    /// Turning around where it stands, degrees about the vertical.
    var spin: Double
}

/// Rocks it on its feet, lifts it off them, turns it round where it
/// stands; a little smaller so the hop stays inside the frame.
private struct AxolotlStepEffect: ViewModifier {
    let step: AxolotlStep?
    let unit: CGFloat

    func body(content: Content) -> some View {
        if let step {
            content
                .scaleEffect(AxolotlMotion.danceScale, anchor: AxolotlMotion.feet)
                .rotationEffect(.degrees(step.sway), anchor: AxolotlMotion.feet)
                .rotation3DEffect(.degrees(step.spin), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .offset(y: -step.hop * unit)
        } else {
            content
        }
    }
}

/// The axolotl's timing, kept pure so it can be tested.
enum AxolotlMotion {
    /// Positive lifts the gills up (left gills turn clockwise).
    static let happyLift: Double = 10

    /// The cursor eye: on for 0.6 s, off for 0.4 s.
    static func cursorVisible(at time: TimeInterval) -> Bool {
        time.truncatingRemainder(dividingBy: 1.0) < 0.6
    }

    /// ±4° over 2.4 s.
    static func gillSway(at time: TimeInterval) -> Double {
        4 * sin(time * 2 * .pi / 2.4)
    }

    /// One beat: a hop.
    static let danceBeat: TimeInterval = 0.5
    /// Rocks left, then right, over two beats.
    static let danceSway: Double = 12
    /// How high a hop goes, in drawing units.
    static let danceHop: Double = 6
    /// Every fourth beat it turns all the way round, easing in and out.
    static let danceSpinEvery = 4
    /// Room for the hop: the drawing's feet sit near its bottom edge.
    static let danceScale: Double = 0.92
    /// Where it stands: it rocks and shrinks around here.
    static let feet = UnitPoint(x: 0.5, y: 0.9)

    static func dance(at time: TimeInterval) -> AxolotlStep {
        let beats = time / danceBeat
        let hop = danceHop * abs(sin(beats * .pi))
        let sway = danceSway * sin(beats * .pi)
        // The last beat of each bar: one full turn.
        let bar = beats.truncatingRemainder(dividingBy: Double(danceSpinEvery))
        let turn = max(0, bar - Double(danceSpinEvery - 1))
        let eased = turn * turn * (3 - 2 * turn)
        return AxolotlStep(hop: hop, sway: turn > 0 ? 0 : sway, spin: 360 * eased)
    }

    /// ±8°, a wiggle a beat.
    static func danceGills(at time: TimeInterval) -> Double {
        8 * sin(time * 2 * .pi / danceBeat)
    }

    /// One wave of the hand, there and back.
    static let wavePeriod: TimeInterval = 0.6
    /// How far the arm swings each way.
    static let waveSwing: Double = 14
    /// How far it leans over, and how much it bobs in time with the wave.
    static let waveLean: Double = 10
    static let waveBob: Double = 3
    static let waveScale: Double = 0.94

    /// Arm raised, leaning over, not moving.
    static let stillWave = AxolotlWave(arm: 0, lean: waveLean)

    /// The hand swings to and fro; the lean bobs once every two waves.
    static func wave(at time: TimeInterval) -> AxolotlWave {
        let phase = time * 2 * .pi / wavePeriod
        return AxolotlWave(arm: waveSwing * sin(phase), lean: waveLean + waveBob * sin(phase / 2))
    }

    /// One wag, side to side and back.
    static let wagPeriod: TimeInterval = 0.9
    static let wagSwing: Double = 14

    static func wag(at time: TimeInterval) -> Double {
        wagSwing * sin(time * 2 * .pi / wagPeriod)
    }

    /// One slow breath, in and out.
    static let breathPeriod: TimeInterval = 3.6
    static let breathDepth: Double = 0.025
    /// How long one z takes to rise, and how many are up at once.
    static let zRise: TimeInterval = 3.6
    static let zCount = 3
    /// Sleeping gills hang down.
    static let sleepDroop: Double = -8

    /// Asleep, still: one z, halfway up.
    static let stillSleep = AxolotlSleep(breath: 0, zs: [0.5])

    static func sleep(at time: TimeInterval) -> AxolotlSleep {
        let rises = (0..<zCount).map { i in
            (time / zRise + Double(i) / Double(zCount)).truncatingRemainder(dividingBy: 1)
        }
        return AxolotlSleep(breath: breathDepth * sin(time * 2 * .pi / breathPeriod), zs: rises)
    }

    static func frame(pose: Axolotl.Pose, reduceMotion: Bool, time: TimeInterval) -> (cursor: Bool, gills: Double) {
        switch pose {
        case .resting: (true, 0)
        case .happy: (true, happyLift)
        case .waiting: reduceMotion ? (true, 0) : (cursorVisible(at: time), gillSway(at: time))
        case .dancing: reduceMotion ? (true, happyLift) : (true, danceGills(at: time))
        case .waving: reduceMotion ? (true, happyLift) : (true, happyLift + gillSway(at: time))
        // Still, all but the tail.
        case .ready: (true, 0)
        case .sleeping: (true, sleepDroop)
        }
    }
}

/// The shadow an axolotl stands on: a soft dark oval under its feet.
struct MascotPlatform: View {
    var body: some View {
        Ellipse()
            .fill(RadialGradient(
                colors: [.black.opacity(0.45), .black.opacity(0)], center: .center, startRadius: 0, endRadius: 22))
            .frame(width: 46, height: 11)
            .offset(y: -1)
            .accessibilityHidden(true)
    }
}
