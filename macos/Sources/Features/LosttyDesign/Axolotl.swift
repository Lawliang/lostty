import SwiftUI

/// Lostty's mascot. `.waiting` blinks its cursor eye and sways its gills;
/// `.happy` perks its gills up and holds a check. Decorative: hidden from
/// VoiceOver.
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
            let side = min(geometry.size.width, geometry.size.height)
            let line = side / 100 * AxolotlMotion.lineWidth(forSide: side)
            let stroke = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            ZStack {
                AxolotlBody().stroke(LosttyTheme.textPrimary, style: stroke)
                ForEach([AxolotlSide.left, .right], id: \.self) { side in
                    ZStack {
                        AxolotlStalks(side: side).stroke(LosttyTheme.textPrimary, style: stroke)
                        AxolotlFronds(side: side)
                            .stroke(LosttyTheme.accent, style: StrokeStyle(lineWidth: line * 0.7, lineCap: .round))
                    }
                    // Left gills turn one way, right the other: a mirrored sway.
                    .rotationEffect(.degrees(side == .left ? gills : -gills),
                                    anchor: AxolotlGeometry.gillAnchor(side))
                }
                AxolotlEyes(cursorVisible: cursor)
                    .stroke(LosttyTheme.textPrimary,
                            style: StrokeStyle(lineWidth: line * 1.15, lineCap: .round, lineJoin: .round))
                if pose == .happy {
                    AxolotlCheck().stroke(LosttyTheme.accent, style: stroke)
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

    /// Thicker lines when small, as approved: 2.2 large, 2.8 medium, 3.6 small
    /// (in drawing units).
    static func lineWidth(forSide side: CGFloat) -> CGFloat {
        side >= 200 ? 2.2 : side >= 80 ? 2.8 : 3.6
    }
}
