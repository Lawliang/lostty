import SwiftUI

/// Lostty's mascot, a chibi axolotl. `.waiting` blinks its cursor eye and
/// sways its gills; `.happy` lifts its gills and holds a check. Decorative:
/// hidden from VoiceOver.
struct Axolotl: View {
    enum Pose: Equatable { case resting, waiting, happy }

    var pose: Pose = .resting
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if pose == .waiting && !reduceMotion {
                TimelineView(.animation) { context in
                    let frame = AxolotlMotion.frame(pose: pose, reduceMotion: false,
                                                    time: context.date.timeIntervalSinceReferenceDate)
                    drawing(cursor: frame.cursor, gills: frame.gills)
                }
            } else {
                let frame = AxolotlMotion.frame(pose: pose, reduceMotion: reduceMotion, time: 0)
                drawing(cursor: frame.cursor, gills: frame.gills)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func drawing(cursor: Bool, gills: Double) -> some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width, geometry.size.height) / 100
            ZStack {
                AxolotlPart(kind: .tail).fill(AxolotlGeometry.shade)
                AxolotlPart(kind: .body).fill(AxolotlGeometry.shade)
                AxolotlPart(kind: .belly).fill(AxolotlGeometry.skin)
                AxolotlPart(kind: .limbs).fill(AxolotlGeometry.skin)
                ForEach([AxolotlSide.left, .right], id: \.self) { side in
                    AxolotlPart(kind: .gills(side)).fill(LosttyTheme.accent)
                        // Left gills turn one way, right the other: a mirrored sway.
                        .rotationEffect(.degrees(side == .left ? gills : -gills),
                                        anchor: AxolotlGeometry.gillAnchor(side))
                }
                AxolotlPart(kind: .head).fill(AxolotlGeometry.skin)
                AxolotlPart(kind: .highlight).fill(Color.white.opacity(0.35))
                AxolotlPart(kind: .blush).fill(LosttyTheme.accent.opacity(0.45))
                AxolotlEyes(cursorVisible: cursor)
                    .stroke(AxolotlGeometry.ink,
                            style: StrokeStyle(lineWidth: 4.4 * unit, lineCap: .round, lineJoin: .round))
                AxolotlMouth()
                    .stroke(AxolotlGeometry.ink,
                            style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round, lineJoin: .round))
                if pose == .happy {
                    AxolotlCheck()
                        .stroke(LosttyTheme.accent,
                                style: StrokeStyle(lineWidth: 4 * unit, lineCap: .round, lineJoin: .round))
                }
            }
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

    static func frame(pose: Axolotl.Pose, reduceMotion: Bool, time: TimeInterval) -> (cursor: Bool, gills: Double) {
        switch pose {
        case .resting: (true, 0)
        case .happy: (true, happyLift)
        case .waiting: reduceMotion ? (true, 0) : (cursorVisible(at: time), gillSway(at: time))
        }
    }
}
