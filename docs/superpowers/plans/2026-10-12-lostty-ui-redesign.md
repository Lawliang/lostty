# Lostty UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the iPhone app and the Mac Phone Access window one dark, calm, magenta-accented look with an axolotl mascot, without changing any behavior.

**Architecture:** A `LosttyDesign` folder under `macos/Sources/Features/` (compiled by both app targets) holds the tokens, the axolotl, the blueprint background and five small components. Each screen is restyled to use them; logic stays where it is. A Debug-only Design Gallery in each app shows every state with fake data for review.

**Tech Stack:** Swift 5 mode; SwiftUI (iOS 17, macOS 14), UIKit for the key row, AppKit for the window; Swift Testing (`GhosttyTests`, macOS host).

**Spec:** `docs/superpowers/specs/2026-10-12-lostty-ui-redesign-design.md`

## Global Constraints

- No behavior changes: same flows, same buttons, same store and pairing logic. Allowed additions: a success haptic when pairing finishes, a light haptic when Ctrl latches, Debug-only gallery hooks.
- Colors (exact): background `#0C0B0E`, surface `#17151B`, surfaceRaised `#211E26`, hairline `#2C2833`, textPrimary `#F4F1F6`, textSecondary `#A39CAA`, accent `#E5199C`, accentSoft = accent at 16%, success `#3FB27F`, warning `#E0A23A`, danger `#E5484D`.
- Type: SF Pro for UI, SF Mono (`.monospaced`) for session names, the Mac's address, keys and key-row labels. iPhone uses Dynamic Type text styles (title 28 → `.title`, 20 → `.title3`, 16 → `.callout`, 13 → `.footnote`, buttons → `.headline`); the Mac uses the same sizes fixed.
- Shape: 16 pt corner radius (continuous), 1 pt hairline borders, no shadows; 16 pt margins, 12 pt gaps. Motion: 0.2 s ease; nothing bounces; animations stop under Reduce Motion.
- Accent only behind semibold labels of 17 pt and up, on icons, dots and strokes — never small body text on accent.
- Blueprint background only on: iPhone welcome, pairing, sessions empty state; Mac pairing sheet.
- The axolotl is the approved drawing in Task 1, verbatim. No axolotl on error or security screens or alerts.
- Copy: every existing error, security and alert string stays exactly as it is. New copy, verbatim: "Nothing running yet. Open Lostty on your Mac." (empty sessions), "Waiting for your Mac to say yes…" (waiting for Allow), "Paired." (success title), "Set Up by Hand" (welcome secondary button), "Find your Mac" / "Allow on Mac" / "Connect" (pairing steps), "<ready> of <total> ready" (Mac header).
- The Mac app's icon must not change. The iPhone gets its own icon set.
- New files go under `macos/Sources/Features/LosttyDesign/` and are wrapped in `#if os(iOS)` / `#if os(macOS)` only where UIKit/AppKit differ; Debug-only code is in `#if DEBUG`.
- Tests: `macos/skins-test.sh <Suite>` (app suites); builds: iOS `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SYMROOT="$PWD/macos/build" CODE_SIGNING_ALLOWED=NO build`, Mac `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build`. Both must print `** BUILD SUCCEEDED **`. Package tests (`cd macos/LosttyRemote && swift test`) must still pass.
- If a stray `default.profraw` appears under `macos/Sources` or `macos/Tests`, delete it (it breaks the build with "Multiple commands produce"). Never stage any `default.profraw`.
- Commits: stage by path; end each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never create a PR or issue. swiftlint is not installed.

## Review Focus

1. **Large Dynamic Type on iPhone** (the largest non-accessibility size): no clipped or overlapping text on welcome, session cards, pairing steps; buttons grow. Pinned by the gallery's "Large text" variants (Task 8) and the review screenshots.
2. **Long session names** (a 40-character project name): one line, truncated in the middle, the live dot and chevron still visible. Pinned by the gallery's long-name session (Task 8).
3. **Reduce Motion on**: the waiting axolotl is still (eye shown, gills at rest). Pinned by `AxolotlMotionTests.reduceMotionIsStill` (Task 1).
4. **The Mac window's checklist with long details and three fix buttons** (Password logins: "Turn Off Password Logins…" + "Skip"): buttons don't push the text off the card; text wraps. Pinned by the gallery's mixed-status variant (Task 8).
5. **The pairing countdown near expiry and after it**: the ring never draws past full or below empty, and the sheet switches to the expired state. Pinned by `PairingCountdownTests` (Task 2).

---

## File Structure

| File | Responsibility |
|---|---|
| `macos/Sources/Features/LosttyDesign/LosttyTheme.swift` (new) | Color, type, spacing, motion tokens; `Color(losttyHex:)`; iOS `UIColor` tokens. |
| `macos/Sources/Features/LosttyDesign/AxolotlShapes.swift` (new) | The approved drawing as shapes: body, gills, fronds, eyes, check. |
| `macos/Sources/Features/LosttyDesign/Axolotl.swift` (new) | The axolotl view with poses; `AxolotlMotion` timing. |
| `macos/Sources/Features/LosttyDesign/BlueprintBackground.swift` (new) | The grid motif. |
| `macos/Sources/Features/LosttyDesign/LosttyButton.swift` (new) | Primary / secondary / quiet / quiet-danger button style. |
| `macos/Sources/Features/LosttyDesign/LosttyCard.swift` (new) | Card container; `StatusRow`. |
| `macos/Sources/Features/LosttyDesign/PairingProgress.swift` (new) | Steps, progress state, `StepIndicator`, `PairingCountdown`. |
| `macos/Sources/Features/LosttyDesign/LosttyScreen.swift` (new, iOS) | Screen background + navigation bar styling modifier. |
| `macos/Tests/LosttyDesign/*` (new) | Tests for motion, progress, countdown, readiness. |
| `macos/Assets.xcassets/LosttyPhoneIcon.appiconset`, `LaunchBackground.colorset`, `LaunchAxolotl.imageset` (new) | iPhone icon and launch screen. |
| `macos/Lostty-iOS-Info.plist`, `macos/Ghostty.xcodeproj/project.pbxproj` | iPhone launch screen, icon name, drop the shared Ghostty icon from the iPhone target. |
| `macos/Sources/App/iOS/*.swift` | Restyled screens; gallery hooks in `MobileStore`. |
| `macos/Sources/Ghostty/Surface View/KeyRow_UIKit.swift` | Restyled key row, Ctrl haptic. |
| `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift`, `PhoneAccessUI.swift`, `PhoneAccessModel.swift`, `PhoneAccessStore.swift` | Restyled window, readiness count, gallery hooks. |
| `macos/Sources/App/iOS/DesignGallery.swift`, `macos/Sources/Features/PhoneAccess/PhoneAccessGallery.swift` (new, Debug) | The galleries. |

---

### Task 1: Tokens and the axolotl

**Files:**
- Create: `macos/Sources/Features/LosttyDesign/LosttyTheme.swift`
- Create: `macos/Sources/Features/LosttyDesign/AxolotlShapes.swift`
- Create: `macos/Sources/Features/LosttyDesign/Axolotl.swift`
- Create: `macos/Sources/Features/LosttyDesign/BlueprintBackground.swift`
- Test: `macos/Tests/LosttyDesign/AxolotlMotionTests.swift`
- Test: `macos/Tests/LosttyDesign/LosttyRenderTests.swift`

**Interfaces:**
- Produces:
  - `LosttyTheme.background/surface/surfaceRaised/hairline/textPrimary/textSecondary/accent/accentSoft/success/warning/danger: Color`; `LosttyTheme.radius = 16`, `.margin = 16`, `.gap = 12`, `.motion: Animation`.
  - `LosttyFont.largeTitle/title/body/bodyEmphasis/detail/button: Font`; `LosttyFont.mono(_ style: Font.TextStyle = .callout, size: CGFloat = 16, weight: Font.Weight = .regular) -> Font`.
  - `Color(losttyHex: UInt32)`; iOS: `LosttyUIColor.background/surfaceRaised/textPrimary/accent: UIColor`.
  - `Axolotl(pose: Axolotl.Pose = .resting)` with `Pose` `.resting/.waiting/.happy`; `AxolotlMotion.cursorVisible(at: TimeInterval) -> Bool`, `.gillSway(at: TimeInterval) -> Double` (degrees), `.happyLift: Double`, `.frame(pose:reduceMotion:time:) -> (cursor: Bool, gills: Double)`.
  - `BlueprintBackground()`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/LosttyDesign/AxolotlMotionTests.swift`:

```swift
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
```

`macos/Tests/LosttyDesign/LosttyRenderTests.swift` (renders review and asset images only when asked):

```swift
#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// Writes PNGs of the axolotl when LOSTTY_RENDER_DIR is set (for review and
/// for the iPhone launch image); does nothing otherwise.
@MainActor
struct LosttyRenderTests {
    @Test func renderAxolotl() throws {
        guard let dir = ProcessInfo.processInfo.environment["LOSTTY_RENDER_DIR"] else { return }
        let poses = HStack(spacing: 40) {
            Axolotl(pose: .resting).frame(width: 200, height: 200)
            Axolotl(pose: .waiting).frame(width: 200, height: 200)
            Axolotl(pose: .happy).frame(width: 200, height: 200)
        }
        .padding(40)
        .background(LosttyTheme.background)
        try write(poses, scale: 2, to: "\(dir)/axolotl-poses.png")
        for scale in [1, 2, 3] {
            try write(Axolotl(pose: .resting).frame(width: 120, height: 120), scale: CGFloat(scale),
                      to: "\(dir)/LaunchAxolotl@\(scale)x.png")
        }
    }

    private func write(_ view: some View, scale: CGFloat, to path: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.nsImage)
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
#endif
```

- [ ] **Step 2: Run them to see them fail**

Run: `macos/skins-test.sh AxolotlMotionTests`
Expected: build fails (`AxolotlMotion` not found).

- [ ] **Step 3: Write `LosttyTheme.swift`**

```swift
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Lostty's look: dark and calm, magenta as the one accent. Shared by the
/// iPhone app and the Mac's Phone Access window.
enum LosttyTheme {
    static let background = Color(losttyHex: 0x0C0B0E)
    static let surface = Color(losttyHex: 0x17151B)
    static let surfaceRaised = Color(losttyHex: 0x211E26)
    static let hairline = Color(losttyHex: 0x2C2833)
    static let textPrimary = Color(losttyHex: 0xF4F1F6)
    static let textSecondary = Color(losttyHex: 0xA39CAA)
    /// Sampled from the app icon's face.
    static let accent = Color(losttyHex: 0xE5199C)
    static let accentSoft = accent.opacity(0.16)
    static let success = Color(losttyHex: 0x3FB27F)
    static let warning = Color(losttyHex: 0xE0A23A)
    static let danger = Color(losttyHex: 0xE5484D)

    static let radius: CGFloat = 16
    static let margin: CGFloat = 16
    static let gap: CGFloat = 12
    static let motion = Animation.easeInOut(duration: 0.2)
}

/// Text styles: Dynamic Type on iPhone, the same sizes fixed on the Mac.
enum LosttyFont {
    #if os(iOS)
    static let largeTitle = Font.system(.title, weight: .semibold)
    static let title = Font.system(.title3, weight: .semibold)
    static let body = Font.system(.callout)
    static let bodyEmphasis = Font.system(.callout, weight: .semibold)
    static let detail = Font.system(.footnote)
    static let button = Font.system(.headline)
    static func mono(_ style: Font.TextStyle = .callout, size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
    #else
    static let largeTitle = Font.system(size: 28, weight: .semibold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 16)
    static let bodyEmphasis = Font.system(size: 16, weight: .semibold)
    static let detail = Font.system(size: 13)
    static let button = Font.system(size: 17, weight: .semibold)
    static func mono(_ style: Font.TextStyle = .callout, size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    #endif
}

extension Color {
    /// 0xRRGGBB in sRGB.
    init(losttyHex hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

#if os(iOS)
/// The tokens UIKit views need (the key row).
enum LosttyUIColor {
    static let background = UIColor(LosttyTheme.background)
    static let surfaceRaised = UIColor(LosttyTheme.surfaceRaised)
    static let textPrimary = UIColor(LosttyTheme.textPrimary)
    static let accent = UIColor(LosttyTheme.accent)
}
#endif
```

- [ ] **Step 4: Write `AxolotlShapes.swift`** (the approved drawing, split so the gills can move)

```swift
import SwiftUI

/// The approved axolotl, drawn in a 100×100 box with y down. White
/// line-art; the gill feathers are the only magenta.
enum AxolotlGeometry {
    /// Gill stalks on the left side: (start, control, end). The right side
    /// mirrors them.
    static let leftStalks: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 24, y: 38), CGPoint(x: 16, y: 30), CGPoint(x: 9, y: 26)),
        (CGPoint(x: 19, y: 47), CGPoint(x: 11, y: 45), CGPoint(x: 4, y: 46)),
        (CGPoint(x: 21, y: 57), CGPoint(x: 13, y: 61), CGPoint(x: 8, y: 66)),
    ]

    static func stalks(_ side: AxolotlSide) -> [(CGPoint, CGPoint, CGPoint)] {
        switch side {
        case .left: leftStalks
        case .right: leftStalks.map { a, b, c in
            (CGPoint(x: 100 - a.x, y: a.y), CGPoint(x: 100 - b.x, y: b.y), CGPoint(x: 100 - c.x, y: c.y))
        }
        }
    }

    /// Where each side's gills meet the head, as a unit point for rotating them.
    static func gillAnchor(_ side: AxolotlSide) -> UnitPoint {
        side == .left ? UnitPoint(x: 0.21, y: 0.48) : UnitPoint(x: 0.79, y: 0.48)
    }
}

enum AxolotlSide { case left, right }

/// Maps the 100×100 drawing box into `rect`.
private struct Box {
    let rect: CGRect
    var scale: CGFloat { min(rect.width, rect.height) / 100 }
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
}

/// Head, body, legs, tail and mouth.
struct AxolotlBody: Shape {
    func path(in rect: CGRect) -> Path {
        let b = Box(rect: rect)
        var path = Path()
        // Head: wide, soft, slightly flat on top.
        path.move(to: b.p(50, 27))
        path.addCurve(to: b.p(82, 50), control1: b.p(70, 27), control2: b.p(82, 36))
        path.addCurve(to: b.p(50, 71), control1: b.p(82, 64), control2: b.p(68, 71))
        path.addCurve(to: b.p(18, 50), control1: b.p(32, 71), control2: b.p(18, 64))
        path.addCurve(to: b.p(50, 27), control1: b.p(18, 36), control2: b.p(30, 27))
        // Body: a soft bean under the head, with stubby front legs.
        path.move(to: b.p(39, 69))
        path.addCurve(to: b.p(50, 88), control1: b.p(34, 78), control2: b.p(40, 88))
        path.addCurve(to: b.p(61, 69), control1: b.p(60, 88), control2: b.p(66, 78))
        path.move(to: b.p(41, 82)); path.addQuadCurve(to: b.p(35, 89), control: b.p(37, 84))
        path.move(to: b.p(59, 82)); path.addQuadCurve(to: b.p(65, 89), control: b.p(63, 84))
        // Tail curling right.
        path.move(to: b.p(60, 82))
        path.addCurve(to: b.p(84, 84), control1: b.p(68, 90), control2: b.p(80, 90))
        path.addCurve(to: b.p(80, 74), control1: b.p(87, 80), control2: b.p(85, 74))
        // Mouth: a wide, small smile.
        path.move(to: b.p(43, 60))
        path.addQuadCurve(to: b.p(57, 60), control: b.p(50, 64))
        return path
    }
}

/// One side's three gill stalks (white).
struct AxolotlStalks: Shape {
    var side: AxolotlSide
    func path(in rect: CGRect) -> Path {
        let b = Box(rect: rect)
        var path = Path()
        for (a, c1, c) in AxolotlGeometry.stalks(side) {
            path.move(to: b.p(a.x, a.y))
            path.addQuadCurve(to: b.p(c.x, c.y), control: b.p(c1.x, c1.y))
        }
        return path
    }
}

/// One side's gill feathers: short strokes angled back toward the head,
/// like fletching (magenta).
struct AxolotlFronds: Shape {
    var side: AxolotlSide
    func path(in rect: CGRect) -> Path {
        let b = Box(rect: rect)
        var path = Path()
        for (a, c1, c) in AxolotlGeometry.stalks(side) {
            for t in [0.38, 0.62, 0.86] as [CGFloat] {
                let x = (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * c1.x + t * t * c.x
                let y = (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * c1.y + t * t * c.y
                let dx = 2 * (1 - t) * (c1.x - a.x) + 2 * t * (c.x - c1.x)
                let dy = 2 * (1 - t) * (c1.y - a.y) + 2 * t * (c.y - c1.y)
                let length = max(0.001, (dx * dx + dy * dy).squareRoot())
                let tx = dx / length, ty = dy / length, nx = -ty, ny = tx
                for sign in [1.0, -1.0] as [CGFloat] {
                    path.move(to: b.p(x, y))
                    path.addLine(to: b.p(x + (-tx * 0.45 + nx * sign * 0.9) * 4.2,
                                         y + (-ty * 0.45 + ny * sign * 0.9) * 4.2))
                }
            }
        }
        return path
    }
}

/// The icon's prompt eyes: ">" and a "—" that blinks like a cursor.
struct AxolotlEyes: Shape {
    var cursorVisible = true
    func path(in rect: CGRect) -> Path {
        let b = Box(rect: rect)
        var path = Path()
        path.move(to: b.p(33, 43)); path.addLine(to: b.p(40, 48)); path.addLine(to: b.p(33, 53))
        if cursorVisible {
            path.move(to: b.p(58, 48)); path.addLine(to: b.p(67, 48))
        }
        return path
    }
}

/// The small check the happy pose holds up, top right.
struct AxolotlCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let b = Box(rect: rect)
        var path = Path()
        path.move(to: b.p(80, 14)); path.addLine(to: b.p(85, 19)); path.addLine(to: b.p(95, 7))
        return path
    }
}
```

- [ ] **Step 5: Write `Axolotl.swift`**

```swift
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
```

The tuple comparisons in the tests need `(Bool, Double)` equality, which Swift provides for tuples of `Equatable` values.

- [ ] **Step 6: Write `BlueprintBackground.swift`**

```swift
import SwiftUI

/// The icon's blueprint: a faint grid with its circles and diagonals. Only
/// behind hero screens (welcome, pairing, empty states).
struct BlueprintBackground: View {
    var body: some View {
        Canvas { context, size in
            let ink = GraphicsContext.Shading.color(.white.opacity(0.06))
            let step: CGFloat = 32
            var grid = Path()
            var x: CGFloat = 0
            while x <= size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            context.stroke(grid, with: ink, lineWidth: 1)

            let side = min(size.width, size.height) * 0.8
            let outer = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            var guides = Path()
            guides.addEllipse(in: outer)
            guides.addEllipse(in: outer.insetBy(dx: side * 0.22, dy: side * 0.22))
            guides.move(to: .zero); guides.addLine(to: CGPoint(x: size.width, y: size.height))
            guides.move(to: CGPoint(x: size.width, y: 0)); guides.addLine(to: CGPoint(x: 0, y: size.height))
            context.stroke(guides, with: ink, lineWidth: 1)
        }
        .background(LosttyTheme.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 7: Run the tests**

Run: `macos/skins-test.sh AxolotlMotionTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Render the poses and the launch image**

Run: `mkdir -p /tmp/lostty-render && LOSTTY_RENDER_DIR=/tmp/lostty-render macos/skins-test.sh LosttyRenderTests` — if the environment variable doesn't reach the test host through `skins-test.sh` (it runs `env -i`), run instead: `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin TEST_RUNNER_LOSTTY_RENDER_DIR=/tmp/lostty-render xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" -skip-testing GhosttyUITests -only-testing:GhosttyTests/LosttyRenderTests test` (xcodebuild passes `TEST_RUNNER_`-prefixed variables to the test process without the prefix).
Expected: `/tmp/lostty-render/axolotl-poses.png` and `LaunchAxolotl@1x/2x/3x.png` exist. Include `axolotl-poses.png`'s path in your report: the controller shows it to the human for a look before later tasks build on it.

- [ ] **Step 9: Commit**

```bash
git add macos/Sources/Features/LosttyDesign macos/Tests/LosttyDesign
git commit -m "lostty: design tokens, the axolotl and the blueprint background

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Components

**Files:**
- Create: `macos/Sources/Features/LosttyDesign/LosttyButton.swift`
- Create: `macos/Sources/Features/LosttyDesign/LosttyCard.swift`
- Create: `macos/Sources/Features/LosttyDesign/PairingProgress.swift`
- Create (iOS): `macos/Sources/Features/LosttyDesign/LosttyScreen.swift`
- Test: `macos/Tests/LosttyDesign/PairingProgressTests.swift`

**Interfaces:**
- Consumes: Task 1 tokens.
- Produces:
  - `LosttyButtonStyle(kind: .primary | .secondary | .quiet | .quietDanger, fullWidth: Bool)`; `.buttonStyle(.lostty(_ kind:, fullWidth: Bool = false))`.
  - `LosttyCard(padding: CGFloat = 16) { … }`.
  - `StatusRowStatus` (`.ok/.warning/.missing`); `StatusRow(status: StatusRowStatus, title: String, detail: String) { trailing }`.
  - `PairingStep` (`.find/.allow/.connect`, `title`), `PairingProgress` (`.notStarted/.finding/.waitingForAllow/.testing/.finished`; `state(of:) -> PairingStepState`), `PairingStepState` (`.done/.current/.pending`), `StepIndicator(progress:)`.
  - `PairingCountdown.fraction(now: Date, expires: Date, total: TimeInterval = 120) -> Double`.
  - iOS: `View.losttyScreen() -> some View`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/LosttyDesign/PairingProgressTests.swift`:

```swift
import Foundation
import Testing
@testable import Ghostty

struct PairingProgressTests {
    @Test func eachPhaseHasOneCurrentStepAndEarlierStepsDone() {
        #expect(PairingStep.allCases.map { PairingProgress.notStarted.state(of: $0) } == [.pending, .pending, .pending])
        #expect(PairingStep.allCases.map { PairingProgress.finding.state(of: $0) } == [.current, .pending, .pending])
        #expect(PairingStep.allCases.map { PairingProgress.waitingForAllow.state(of: $0) } == [.done, .current, .pending])
        #expect(PairingStep.allCases.map { PairingProgress.testing.state(of: $0) } == [.done, .done, .current])
        #expect(PairingStep.allCases.map { PairingProgress.finished.state(of: $0) } == [.done, .done, .done])
    }

    @Test func stepTitles() {
        #expect(PairingStep.allCases.map(\.title) == ["Find your Mac", "Allow on Mac", "Connect"])
    }
}

struct PairingCountdownTests {
    let expires = Date(timeIntervalSince1970: 1_000)

    @Test func fullAtTheStartEmptyAtTheEnd() {
        #expect(PairingCountdown.fraction(now: expires.addingTimeInterval(-120), expires: expires) == 1)
        #expect(PairingCountdown.fraction(now: expires.addingTimeInterval(-60), expires: expires) == 0.5)
        #expect(PairingCountdown.fraction(now: expires, expires: expires) == 0)
    }

    @Test func neverOutsideZeroToOne() {
        #expect(PairingCountdown.fraction(now: expires.addingTimeInterval(-500), expires: expires) == 1)
        #expect(PairingCountdown.fraction(now: expires.addingTimeInterval(30), expires: expires) == 0)
        #expect(PairingCountdown.fraction(now: expires, expires: expires, total: 0) == 0)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `macos/skins-test.sh PairingProgressTests`
Expected: build fails (`PairingProgress` not found).

- [ ] **Step 3: Write `PairingProgress.swift`**

```swift
import SwiftUI

/// The three waits of pairing a phone.
enum PairingStep: Int, CaseIterable, Identifiable {
    case find, allow, connect

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .find: "Find your Mac"
        case .allow: "Allow on Mac"
        case .connect: "Connect"
        }
    }
}

enum PairingStepState: Equatable { case done, current, pending }

/// Where pairing is: the step under way, or finished.
struct PairingProgress: Equatable {
    var current: PairingStep?
    var finished = false

    static let notStarted = PairingProgress(current: nil)
    static let finding = PairingProgress(current: .find)
    static let waitingForAllow = PairingProgress(current: .allow)
    static let testing = PairingProgress(current: .connect)
    static let finished = PairingProgress(current: nil, finished: true)

    func state(of step: PairingStep) -> PairingStepState {
        if finished { return .done }
        guard let current else { return .pending }
        if step == current { return .current }
        return step.rawValue < current.rawValue ? .done : .pending
    }
}

/// Numbered steps: done ✓, the current one pulsing, the rest dim.
struct StepIndicator: View {
    var progress: PairingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(PairingStep.allCases) { step in
                let state = progress.state(of: step)
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(state == .pending ? LosttyTheme.surfaceRaised : LosttyTheme.accentSoft)
                        switch state {
                        case .done:
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(LosttyTheme.accent)
                        case .current:
                            Circle().fill(LosttyTheme.accent).frame(width: 8, height: 8)
                                .symbolEffect(.pulse, options: .repeating)
                        case .pending:
                            Text("\(step.rawValue + 1)").font(LosttyFont.mono(.footnote, size: 13, weight: .semibold))
                                .foregroundStyle(LosttyTheme.textSecondary)
                        }
                    }
                    .frame(width: 24, height: 24)
                    Text(step.title)
                        .font(state == .current ? LosttyFont.bodyEmphasis : LosttyFont.body)
                        .foregroundStyle(state == .pending ? LosttyTheme.textSecondary : LosttyTheme.textPrimary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.title), \(state == .done ? "done" : state == .current ? "in progress" : "not started")")
            }
        }
    }
}

/// How much of a pairing code's life is left, 1 (new) … 0 (expired).
enum PairingCountdown {
    static func fraction(now: Date, expires: Date, total: TimeInterval = 120) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, expires.timeIntervalSince(now) / total))
    }
}
```

`.symbolEffect` on a non-symbol view has no effect on some OS versions; if the pulse doesn't show in the gallery, replace that line's modifier with `.opacity(…)` driven by a `TimelineView(.animation)` (`0.5 + 0.5 * sin(t * 2π / 1.2)`), skipped under Reduce Motion. Record the change in your report.

- [ ] **Step 4: Write `LosttyButton.swift`**

```swift
import SwiftUI

/// Lostty's buttons: primary (magenta), secondary (card), quiet (text),
/// quiet danger (red text).
struct LosttyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, quietDanger }

    var kind: Kind
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        LosttyButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }
}

private struct LosttyButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: LosttyButtonStyle.Kind
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var quiet: Bool { kind == .quiet || kind == .quietDanger }

    var body: some View {
        configuration.label
            .font(kind == .primary ? LosttyFont.button : LosttyFont.bodyEmphasis)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, quiet ? 6 : 12)
            .padding(.horizontal, quiet ? 4 : 18)
            .background {
                switch kind {
                case .primary:
                    RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous)
                        .fill(LosttyTheme.accent.opacity(configuration.isPressed ? 0.8 : 1))
                case .secondary:
                    RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous)
                        .fill(configuration.isPressed ? LosttyTheme.surfaceRaised : LosttyTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous)
                            .strokeBorder(LosttyTheme.hairline, lineWidth: 1))
                case .quiet, .quietDanger:
                    Color.clear
                }
            }
            .opacity(isEnabled ? (quiet && configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Rectangle())
            .animation(LosttyTheme.motion, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: LosttyTheme.textPrimary
        case .quiet: LosttyTheme.textSecondary
        case .quietDanger: LosttyTheme.danger
        }
    }
}

extension ButtonStyle where Self == LosttyButtonStyle {
    static func lostty(_ kind: LosttyButtonStyle.Kind, fullWidth: Bool = false) -> LosttyButtonStyle {
        LosttyButtonStyle(kind: kind, fullWidth: fullWidth)
    }
}
```

- [ ] **Step 5: Write `LosttyCard.swift`**

```swift
import SwiftUI

/// A rounded surface with a hairline border.
struct LosttyCard<Content: View>: View {
    var padding: CGFloat
    let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LosttyTheme.surface,
                        in: RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous)
                .strokeBorder(LosttyTheme.hairline, lineWidth: 1))
    }
}

enum StatusRowStatus { case ok, warning, missing }

/// A checklist row: status icon, title, wrapping detail, trailing buttons.
struct StatusRow<Trailing: View>: View {
    var status: StatusRowStatus
    var title: String
    var detail: String
    let trailing: Trailing

    init(status: StatusRowStatus, title: String, detail: String, @ViewBuilder trailing: () -> Trailing) {
        self.status = status
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityLabel(status == .ok ? "Ready" : status == .warning ? "Needs attention" : "Not ready")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LosttyFont.bodyEmphasis).foregroundStyle(LosttyTheme.textPrimary)
                Text(detail).font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { trailing }
                .fixedSize()
        }
        .padding(.vertical, 10)
    }

    private var icon: String {
        switch status {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .missing: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .ok: LosttyTheme.success
        case .warning: LosttyTheme.warning
        case .missing: LosttyTheme.danger
        }
    }
}
```

- [ ] **Step 6: Write `LosttyScreen.swift`** (iOS)

```swift
#if os(iOS)
import SwiftUI

extension View {
    /// A Lostty screen: near-black background and a matching navigation bar.
    func losttyScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(LosttyTheme.background.ignoresSafeArea())
            .toolbarBackground(LosttyTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
#endif
```

- [ ] **Step 7: Run the tests and both builds**

Run: `macos/skins-test.sh PairingProgressTests` → `** TEST SUCCEEDED **`; the iOS and Mac build commands from Global Constraints → both `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/LosttyDesign macos/Tests/LosttyDesign/PairingProgressTests.swift
git commit -m "lostty: design components — buttons, cards, status rows, pairing steps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: iPhone icon and launch screen

**Files:**
- Create: `macos/Assets.xcassets/LosttyPhoneIcon.appiconset/Contents.json`, `…/LosttyPhoneIcon-1024.png`
- Create: `macos/Assets.xcassets/LaunchBackground.colorset/Contents.json`
- Create: `macos/Assets.xcassets/LaunchAxolotl.imageset/Contents.json` and its three PNGs
- Modify: `macos/Lostty-iOS-Info.plist`
- Modify: `macos/Ghostty.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1's rendered `LaunchAxolotl@1x/2x/3x.png` (re-render with Task 1 Step 8 if `/tmp/lostty-render` is gone).

- [ ] **Step 1: Make the iPhone icon image**

The Mac icon (`macos/Assets.xcassets/AppIconImage.imageset/macOS-AppIcon-1024px.png`) is a macOS-style image: transparent margin and corners, a page curl. iOS needs a full-bleed, opaque 1024×1024 square (iOS rounds the corners itself). Create it with this script (run from the repo root):

```bash
mkdir -p macos/Assets.xcassets/LosttyPhoneIcon.appiconset
cat > /tmp/lostty-phone-icon.swift <<'EOF'
import AppKit
let source = NSImage(contentsOfFile: CommandLine.arguments[1])!
let rep = NSBitmapImageRep(data: source.tiffRepresentation!)!
// The icon's square body sits inside a ~10% transparent margin.
let crop = CGRect(x: 96, y: 96, width: 832, height: 832)
let cropped = rep.cgImage!.cropping(to: crop)!
let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Fill with the icon's magenta so the rounded corners' transparency becomes solid.
ctx.setFillColor(CGColor(srgbRed: 0xE5/255, green: 0x19/255, blue: 0x9C/255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
EOF
swift /tmp/lostty-phone-icon.swift macos/Assets.xcassets/AppIconImage.imageset/macOS-AppIcon-1024px.png macos/Assets.xcassets/LosttyPhoneIcon.appiconset/LosttyPhoneIcon-1024.png
sips -g pixelWidth -g pixelHeight -g hasAlpha macos/Assets.xcassets/LosttyPhoneIcon.appiconset/LosttyPhoneIcon-1024.png
```

Expected: 1024 × 1024, `hasAlpha: no`. Open the PNG (Read tool) and check the magenta fills the square edge to edge with the white frame, grid and ghost visible; if the crop clips the frame or leaves a transparent band, adjust the 96/832 crop and say so in the report.

`macos/Assets.xcassets/LosttyPhoneIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "LosttyPhoneIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: Launch screen assets**

`macos/Assets.xcassets/LaunchBackground.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x0E", "green" : "0x0B", "red" : "0x0C" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Copy `/tmp/lostty-render/LaunchAxolotl@1x.png`, `@2x`, `@3x` into `macos/Assets.xcassets/LaunchAxolotl.imageset/` as `LaunchAxolotl.png`, `LaunchAxolotl@2x.png`, `LaunchAxolotl@3x.png`, with:

```json
{
  "images" : [
    { "filename" : "LaunchAxolotl.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "LaunchAxolotl@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "LaunchAxolotl@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

The launch PNGs are the axolotl alone on a transparent background, which is what the launch screen needs (iOS draws `LaunchBackground` behind it).

- [ ] **Step 3: Info.plist launch screen**

In `macos/Lostty-iOS-Info.plist`, add inside the top-level `<dict>`:

```xml
	<key>UILaunchScreen</key>
	<dict>
		<key>UIColorName</key>
		<string>LaunchBackground</string>
		<key>UIImageName</key>
		<string>LaunchAxolotl</string>
		<key>UIImageRespectsSafeAreaInsets</key>
		<true/>
	</dict>
```

- [ ] **Step 4: Project settings**

In `macos/Ghostty.xcodeproj/project.pbxproj`, in each of the three build configurations that contain `PRODUCT_BUNDLE_IDENTIFIER = "com.lawliang.lostty-mobile";`:
- change `ASSETCATALOG_COMPILER_APPICON_NAME = Ghostty;` to `ASSETCATALOG_COMPILER_APPICON_NAME = LosttyPhoneIcon;`
- delete the line `INFOPLIST_KEY_UILaunchScreen_Generation = YES;` (the Info.plist now defines the launch screen).

Remove the Ghostty icon from the iPhone target only: in the Resources phase `A5D4499B2B53AE7B000F5B83 /* Resources */`, delete the line `A553F4132E06EB1600257779 /* Ghostty.icon in Resources */,`, and delete the build-file line `A553F4132E06EB1600257779 /* Ghostty.icon in Resources */ = {isa = PBXBuildFile; …};` (the other build file, `A553F4142E06EB1600257779`, belongs to the Mac target and stays).

- [ ] **Step 5: Build and check**

Run both builds → `** BUILD SUCCEEDED **`. Then:
`plutil -p macos/build/Debug-iphonesimulator/Ghostty-iOS.app/Info.plist | grep -A6 -E 'UILaunchScreen|CFBundleIconName'` → `UIColorName => LaunchBackground`, `UIImageName => LaunchAxolotl`, `CFBundleIconName => LosttyPhoneIcon`.
`plutil -p macos/build/Debug/Ghostty.app/Contents/Info.plist | grep CFBundleIconName` → unchanged from before this task (the Mac icon must not change; record the before and after values).

- [ ] **Step 6: Commit**

```bash
git add macos/Assets.xcassets/LosttyPhoneIcon.appiconset macos/Assets.xcassets/LaunchBackground.colorset macos/Assets.xcassets/LaunchAxolotl.imageset macos/Lostty-iOS-Info.plist macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "lostty: iPhone gets the Lostty icon and a dark axolotl launch screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: iPhone welcome and session list

**Files:**
- Modify: `macos/Sources/App/iOS/WelcomeScreen.swift` (rewrite)
- Modify: `macos/Sources/App/iOS/SessionsScreen.swift`
- Modify: `macos/Sources/App/iOS/iOSApp.swift`

**Interfaces:**
- Consumes: Tasks 1–2 (`LosttyTheme`, `LosttyFont`, `Axolotl`, `BlueprintBackground`, `LosttyCard`, `.lostty(_:)`, `.losttyScreen()`); `MobileStore.noSessionsMessage`, `needsPairing`, `sessions`, `message`, `loading` (existing).

- [ ] **Step 1: Rewrite `WelcomeScreen.swift`**

```swift
#if os(iOS)
import SwiftUI

/// First run: nothing paired or typed yet.
struct WelcomeScreen: View {
    var pair: () -> Void
    var settings: () -> Void

    var body: some View {
        ZStack {
            BlueprintBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Axolotl(pose: .resting)
                        .frame(width: 160, height: 160)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    Text("Open your Mac's Lostty sessions from here.")
                        .font(LosttyFont.largeTitle)
                        .foregroundStyle(LosttyTheme.textPrimary)
                    VStack(alignment: .leading, spacing: LosttyTheme.gap) {
                        step(1, "Install Tailscale on your Mac and this iPhone, signed into the same account.")
                        step(2, "On your Mac, open Lostty → Phone Access.")
                        step(3, "Tap Pair with Mac.")
                    }
                }
                .padding(LosttyTheme.margin)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    Button("Pair with Mac", action: pair).buttonStyle(.lostty(.primary, fullWidth: true))
                    Button("Set Up by Hand", action: settings).buttonStyle(.lostty(.quiet))
                }
                .padding(LosttyTheme.margin)
                .background(LosttyTheme.background.opacity(0.9))
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(LosttyFont.mono(.footnote, size: 13, weight: .semibold))
                .foregroundStyle(LosttyTheme.accent)
                .frame(width: 26, height: 26)
                .background(LosttyTheme.accentSoft, in: Circle())
            Text(text)
                .font(LosttyFont.body)
                .foregroundStyle(LosttyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
```

- [ ] **Step 2: Restyle `SessionsScreen.swift`**

Replace the `sessionList` property with:

```swift
    private var sessionList: some View {
        List {
            if let message = store.message, !showsEmptyState {
                LosttyCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(message).font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                        if store.needsPairing {
                            Button("Pair Again") { showPairing = true }.buttonStyle(.lostty(.primary))
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: LosttyTheme.margin, bottom: 6, trailing: LosttyTheme.margin))
            }
            ForEach(store.sessions, id: \.id) { session in
                Button {
                    guard let app = ghostty.app, let terminal = store.terminal(for: session, app: app) else { return }
                    open = (session, terminal.view, terminal.io)
                    path = ["terminal"]
                } label: {
                    LosttyCard(padding: 14) {
                        HStack(spacing: 12) {
                            Text(session.name)
                                .font(LosttyFont.mono(.callout, weight: .medium))
                                .foregroundStyle(LosttyTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            if session.owner != nil {
                                Circle().fill(LosttyTheme.accent).frame(width: 8, height: 8)
                                    .accessibilityLabel("Open on the Mac")
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(LosttyTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: LosttyTheme.margin, bottom: 6, trailing: LosttyTheme.margin))
                .swipeActions {
                    Button("Close", role: .destructive) { confirmKill = session }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if showsEmptyState {
                EmptySessions()
            } else if store.loading && store.sessions.isEmpty {
                ProgressView().tint(LosttyTheme.accent)
            }
        }
        .refreshable { await store.refresh() }
    }

    /// No sessions and nothing else to say: the friendly empty state.
    private var showsEmptyState: Bool {
        store.sessions.isEmpty && !store.loading && store.message == MobileStore.noSessionsMessage
    }
```

and add at the end of the file (inside `#if os(iOS)`):

```swift
private struct EmptySessions: View {
    var body: some View {
        ZStack {
            BlueprintBackground()
            VStack(spacing: 16) {
                Axolotl(pose: .resting).frame(width: 120, height: 120)
                Text("Nothing running yet. Open Lostty on your Mac.")
                    .font(LosttyFont.body)
                    .foregroundStyle(LosttyTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(LosttyTheme.margin)
        }
    }
}
```

In `body`, after `.navigationTitle("Lostty")` add `.losttyScreen()`. Change the gear button's image to `Image(systemName: "gearshape").foregroundStyle(LosttyTheme.textSecondary)`.

- [ ] **Step 3: App-wide tint**

In `iOSApp.swift`, after `.preferredColorScheme(.dark)` add `.tint(LosttyTheme.accent)`.

- [ ] **Step 4: Build**

Run both builds → `** BUILD SUCCEEDED **`; `cd macos/LosttyRemote && swift test` → pass.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/App/iOS/WelcomeScreen.swift macos/Sources/App/iOS/SessionsScreen.swift macos/Sources/App/iOS/iOSApp.swift
git commit -m "lostty: iPhone welcome and session list in the Lostty look

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: iPhone pairing screen

**Files:**
- Modify: `macos/Sources/App/iOS/PairingScreen.swift`

**Interfaces:**
- Consumes: `PairingProgress`, `StepIndicator`, `Axolotl`, `BlueprintBackground`, `.lostty(_:)`, `.losttyScreen()`; `MobileStore.pairing` (`PairingPhase`), `pair(link:)`, `retryPairingTest()`, `resetPairing()`, `cancelPairing()` (existing, unchanged).

- [ ] **Step 1: Replace `body` and add helpers**

Keep the stored properties, `startPendingLink()`, and every modifier from `.navigationTitle` down (toolbar Cancel, `.onAppear`, `.onChange`, `.task`, `.onDisappear`) unchanged. Replace the `VStack(spacing: 20) { switch … }` and its `.padding()` with:

```swift
        ZStack {
            BlueprintBackground()
            ScrollView {
                VStack(spacing: 20) {
                    switch store.pairing {
                    case .idle:
                        viewfinder
                        Text("On your Mac, open Lostty → Phone Access → Pair a Phone, then point the camera at the code.")
                            .font(LosttyFont.body)
                            .foregroundStyle(LosttyTheme.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Paste Pairing Link") {
                            let link = UIPasteboard.general.string ?? ""
                            Task { await store.pair(link: link) }
                        }
                        .buttonStyle(.lostty(.secondary))
                    case .finding, .waitingForAllow, .testing:
                        Axolotl(pose: .waiting).frame(width: 120, height: 120).padding(.top, 24)
                        Text(waitingTitle)
                            .font(LosttyFont.title)
                            .foregroundStyle(LosttyTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        LosttyCard { StepIndicator(progress: progress) }
                    case .failed(let text, let canRetryTest):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(LosttyTheme.warning)
                            .padding(.top, 24)
                        Text(text)
                            .font(LosttyFont.body)
                            .foregroundStyle(LosttyTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        if canRetryTest {
                            Button("Try Again") { Task { await store.retryPairingTest() } }
                                .buttonStyle(.lostty(.primary, fullWidth: true))
                        } else {
                            Button("Scan Again") { store.resetPairing() }
                                .buttonStyle(.lostty(.primary, fullWidth: true))
                        }
                    case .done:
                        Axolotl(pose: .happy).frame(width: 140, height: 140).padding(.top, 24)
                        Text("Paired.").font(LosttyFont.largeTitle).foregroundStyle(LosttyTheme.textPrimary)
                        Text("Your Mac's sessions are ready.")
                            .font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                        Button("Done") { dismiss() }.buttonStyle(.lostty(.primary, fullWidth: true))
                    }
                }
                .padding(LosttyTheme.margin)
            }
        }
        .sensoryFeedback(.success, trigger: store.pairing == .done) { _, done in done }
        .losttyScreen()
```

and add these members to `PairingScreen`:

```swift
    /// The scanner in a rounded frame with magenta corner brackets, or why
    /// there is none.
    @ViewBuilder private var viewfinder: some View {
        if QRScannerView.isSupported && cameraAllowed == true {
            QRScannerView { link in Task { await store.pair(link: link) } }
                .clipShape(RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous))
                .overlay(ViewfinderBrackets().stroke(LosttyTheme.accent,
                                                     style: StrokeStyle(lineWidth: 4, lineCap: .round)))
                .frame(height: 320)
        } else if cameraAllowed == false {
            LosttyCard {
                Text("Lostty can't use the camera. Allow it in Settings → Lostty, or on the Mac click Copy Pairing Link and paste it here.")
                    .font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
            }
        } else if !QRScannerView.isSupported {
            LosttyCard {
                Text("This device can't scan codes. On the Mac, click Copy Pairing Link, then paste it here.")
                    .font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
            }
        }
    }

    private var progress: PairingProgress {
        switch store.pairing {
        case .finding: .finding
        case .waitingForAllow: .waitingForAllow
        case .testing: .testing
        case .done: .finished
        case .idle, .failed: .notStarted
        }
    }

    private var waitingTitle: String {
        switch store.pairing {
        case .finding: "Looking for your Mac nearby…"
        case .waitingForAllow: "Waiting for your Mac to say yes…"
        default: "Connecting over Tailscale…"
        }
    }
```

and at the end of the file (inside `#if os(iOS)`):

```swift
/// Four corner brackets, inset from the viewfinder's edge.
private struct ViewfinderBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 18, arm: CGFloat = 28
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                 (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        return path
    }
}
```

The "Paired. Your Mac's sessions are ready." line is split into "Paired." (title) and the existing remainder; the failure texts and buttons are unchanged.

- [ ] **Step 2: Build**

Run both builds → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/App/iOS/PairingScreen.swift
git commit -m "lostty: iPhone pairing with a viewfinder, step progress and the axolotl

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: iPhone settings, terminal bar and key row

**Files:**
- Modify: `macos/Sources/App/iOS/SettingsScreen.swift`
- Modify: `macos/Sources/App/iOS/TerminalScreen.swift`
- Modify: `macos/Sources/Ghostty/Surface View/KeyRow_UIKit.swift`

**Interfaces:**
- Consumes: `LosttyTheme`, `LosttyFont`, `LosttyUIColor`, `.losttyScreen()`.
- Produces: `TerminalTitle(name: String)` (used by the gallery in Task 8).

- [ ] **Step 1: Settings**

In `SettingsScreen.body`:
- after `.navigationTitle("Settings")` add `.losttyScreen()`;
- add `.listRowBackground(LosttyTheme.surface)` to both `Section`s (after each `Section`'s closing brace);
- change `LabeledContent("Paired with", value: store.settings.host)` to
  `LabeledContent("Paired with") { Text(store.settings.host).font(LosttyFont.mono(.callout)).foregroundStyle(LosttyTheme.textSecondary) }`;
- change the key's `Text(publicKey).font(.footnote.monospaced())` to `.font(LosttyFont.mono(.footnote, size: 13))`;
- change both `.foregroundStyle(.red)` to `.foregroundStyle(LosttyTheme.danger)`.

- [ ] **Step 2: Terminal title**

In `TerminalScreen.swift`, add inside `.toolbar { … }`, before the `Menu`:

```swift
            ToolbarItem(placement: .principal) { TerminalTitle(name: session.name) }
```

wrap the existing `Menu { … } label: { … }` in `ToolbarItem(placement: .topBarTrailing) { … }`, add `.losttyScreen()` after `.navigationBarTitleDisplayMode(.inline)`, and add at the end of the file (inside `#if os(iOS)`):

```swift
/// The session's name in the terminal's top bar.
struct TerminalTitle: View {
    var name: String
    var body: some View {
        Text(name)
            .font(LosttyFont.mono(.headline, weight: .semibold))
            .foregroundStyle(LosttyTheme.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
```

- [ ] **Step 3: Key row**

In `KeyRow_UIKit.swift`, in `init()`, replace the button styling lines (`backgroundColor = .secondarySystemBackground` and `layer.cornerRadius = 5`) with:

```swift
                button.backgroundColor = LosttyUIColor.surfaceRaised
                button.setTitleColor(LosttyUIColor.textPrimary, for: .normal)
                button.layer.cornerRadius = 8
                button.layer.cornerCurve = .continuous
```

and replace `setCtrl(_:)` with:

```swift
        /// Shows whether Ctrl is latched; a light tap when it latches.
        func setCtrl(_ on: Bool) {
            ctrlButton?.backgroundColor = on ? LosttyUIColor.accent : LosttyUIColor.surfaceRaised
            ctrlButton?.setTitleColor(on ? .white : LosttyUIColor.textPrimary, for: .normal)
            if on { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
```

- [ ] **Step 4: Build**

Run both builds → `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/App/iOS/SettingsScreen.swift macos/Sources/App/iOS/TerminalScreen.swift "macos/Sources/Ghostty/Surface View/KeyRow_UIKit.swift"
git commit -m "lostty: iPhone settings, terminal bar and key row in the Lostty look

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The Mac Phone Access window

**Files:**
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift` (rewrite the view and sheet; keep `qrImage`)
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessUI.swift`
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessModel.swift`
- Test: `macos/Tests/LosttyDesign/PhoneAccessReadinessTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2; `PhoneAccessStore` (`rows`, `status`, `checking`, `canPair`, `message`, `phones`, `pairing`, `refresh()`, `fix(_:)`, `startPairing()`, `stopPairing()`, `rename(_:to:)`, `remove(_:)`, `turnOff()`), `PhoneAccessRow`, `PairedPhone` (existing).
- Produces: `PhoneAccessRow.readiness(_ rows: [PhoneAccessRow]) -> (ready: Int, total: Int)`.

- [ ] **Step 1: Write the failing test**

`macos/Tests/LosttyDesign/PhoneAccessReadinessTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Ghostty

struct PhoneAccessReadinessTests {
    func row(_ state: PhoneAccessRow.State) -> PhoneAccessRow {
        PhoneAccessRow(id: .tmux, title: "", detail: "", state: state, fixes: [])
    }

    @Test func countsOnlyReadyRows() {
        #expect(PhoneAccessRow.readiness([row(.ok), row(.ok), row(.warning), row(.missing)]) == (2, 4))
        #expect(PhoneAccessRow.readiness([]) == (0, 0))
    }
}
#endif
```

- [ ] **Step 2: Run it to see it fail**

Run: `macos/skins-test.sh PhoneAccessReadinessTests` → build fails (`readiness` not found).

- [ ] **Step 3: Add `readiness`**

In `PhoneAccessModel.swift`, inside `struct PhoneAccessRow`, add:

```swift
    /// "5 of 7 ready": ⚠ counts as not ready.
    static func readiness(_ rows: [PhoneAccessRow]) -> (ready: Int, total: Int) {
        (rows.filter { $0.state == .ok }.count, rows.count)
    }
```

Run `macos/skins-test.sh PhoneAccessReadinessTests` → `** TEST SUCCEEDED **`.

- [ ] **Step 4: Rewrite `PhoneAccessView`**

Replace `struct PhoneAccessView`'s `body` (keep its stored properties, `label(_:)`, and remove `icon(_:)`/`color(_:)`, now in `StatusRow`) with:

```swift
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LosttyCard(padding: 4) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Rectangle().fill(LosttyTheme.hairline).frame(height: 1) }
                            StatusRow(status: status(row.state), title: row.title, detail: row.detail) {
                                ForEach(row.fixes, id: \.self) { fix in
                                    Button(label(fix)) { store.fix(fix) }.buttonStyle(.lostty(.secondary))
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                        if store.status == nil {
                            ProgressView().controlSize(.small).padding(16)
                        }
                    }
                }
                Text("Your phone can reach this Mac only while it's awake.")
                    .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)

                Button("Pair a Phone…") { store.startPairing() }
                    .buttonStyle(.lostty(.primary, fullWidth: true))
                    .disabled(!store.canPair)
                if let message = store.message {
                    Text(message).font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                }

                Text("Paired phones").font(LosttyFont.title).foregroundStyle(LosttyTheme.textPrimary)
                LosttyCard(padding: 4) {
                    VStack(spacing: 0) {
                        if store.phones.isEmpty {
                            Text("None yet.").font(LosttyFont.body).foregroundStyle(LosttyTheme.textSecondary)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(store.phones.enumerated()), id: \.element.id) { index, phone in
                            if index > 0 { Rectangle().fill(LosttyTheme.hairline).frame(height: 1) }
                            HStack(spacing: 12) {
                                Image(systemName: "iphone").foregroundStyle(LosttyTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phone.name).font(LosttyFont.bodyEmphasis).foregroundStyle(LosttyTheme.textPrimary)
                                    if let paired = phone.paired {
                                        Text("Paired \(paired.formatted(date: .abbreviated, time: .omitted))")
                                            .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                                    }
                                }
                                Spacer()
                                Button("Rename…") {
                                    newName = phone.name
                                    renaming = phone
                                }
                                .buttonStyle(.lostty(.quiet))
                                Button("Remove") { store.remove(phone) }.buttonStyle(.lostty(.quietDanger))
                            }
                            .padding(12)
                        }
                    }
                }
                Button("Turn Off Phone Access…") { store.turnOff() }
                    .buttonStyle(.lostty(.quietDanger))
            }
            .padding(24)
        }
        .frame(width: 560)
        .frame(minHeight: 520)
        .background(LosttyTheme.background)
        .sheet(item: Binding(get: { store.pairing.map(PairingSheetItem.init) }, set: { if $0 == nil { store.stopPairing() } })) { item in
            PairingSheet(pairing: item.pairing).environmentObject(store)
        }
        .alert("Rename Phone", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let phone = renaming { store.rename(phone, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Axolotl(pose: .resting).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Phone Access").font(LosttyFont.largeTitle).foregroundStyle(LosttyTheme.textPrimary)
                let readiness = PhoneAccessRow.readiness(store.rows)
                if readiness.total > 0 {
                    Text("\(readiness.ready) of \(readiness.total) ready")
                        .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                }
            }
            Spacer()
            if store.checking { ProgressView().controlSize(.small) }
            Button("Check Again") { store.refresh() }.buttonStyle(.lostty(.quiet)).disabled(store.checking)
        }
    }

    private func status(_ state: PhoneAccessRow.State) -> StatusRowStatus {
        switch state {
        case .ok: .ok
        case .warning: .warning
        case .missing: .missing
        }
    }
```

Replace `PairingSheet.body` with:

```swift
    var body: some View {
        ZStack {
            BlueprintBackground()
            VStack(spacing: 18) {
                switch pairing {
                case .showing(let payload, let expires):
                    Axolotl(pose: .waiting).frame(width: 56, height: 56)
                    Text("Scan this with Lostty on your iPhone.")
                        .font(LosttyFont.title).foregroundStyle(LosttyTheme.textPrimary)
                        .multilineTextAlignment(.center)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        qrTile(payload, fraction: PairingCountdown.fraction(now: context.date, expires: expires))
                    }
                    Text("The code works once and expires \(expires, style: .relative).")
                        .font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                    Button("Copy Pairing Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(payload.url.absoluteString, forType: .string)
                    }
                    .buttonStyle(.lostty(.secondary))
                case .expired:
                    Axolotl(pose: .resting).frame(width: 56, height: 56)
                    Text("This code expired.").font(LosttyFont.title).foregroundStyle(LosttyTheme.textPrimary)
                    Button("Show a New Code") { store.startPairing() }.buttonStyle(.lostty(.primary))
                }
                Button("Cancel", role: .cancel) { store.stopPairing() }
                    .buttonStyle(.lostty(.quiet))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(28)
        }
        .frame(width: 380)
    }

    /// The QR on white (cameras read dark-on-light best), with a magenta ring
    /// that empties as the code's two minutes run out.
    private func qrTile(_ payload: PairingPayload, fraction: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: LosttyTheme.radius + 8, style: .continuous)
                .stroke(LosttyTheme.hairline, lineWidth: 4)
            RoundedRectangle(cornerRadius: LosttyTheme.radius + 8, style: .continuous)
                .trim(from: 0, to: fraction)
                .stroke(LosttyTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .animation(LosttyTheme.motion, value: fraction)
            if let image = Self.qrImage(payload.url.absoluteString) {
                Image(nsImage: image).interpolation(.none).resizable()
                    .frame(width: 220, height: 220)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous))
                    .padding(12)
                    .accessibilityLabel("Pairing code")
            }
        }
        .frame(width: 280, height: 280)
    }
```

- [ ] **Step 5: Window**

In `PhoneAccessUI.show()`, after `window.styleMask = …`, add:

```swift
            // Always dark: a branded setup window, one palette.
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(LosttyTheme.background)
            window.titlebarAppearsTransparent = true
            window.contentMinSize = NSSize(width: 560, height: 520)
            window.contentMaxSize = NSSize(width: 560, height: 4000)
```

- [ ] **Step 6: Tests and builds**

Run: `macos/skins-test.sh PhoneAccessReadinessTests`, `PhoneAccessRowsTests`, `PairingDecisionTests` → each `** TEST SUCCEEDED **`; both builds → `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/PhoneAccess macos/Tests/LosttyDesign/PhoneAccessReadinessTests.swift
git commit -m "lostty: Mac Phone Access window and pairing sheet in the Lostty look

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Design Galleries

**Files:**
- Modify: `macos/Sources/App/iOS/MobileStore.swift` (Debug-only gallery hooks)
- Create: `macos/Sources/App/iOS/DesignGallery.swift` (iOS, Debug)
- Modify: `macos/Sources/App/iOS/iOSApp.swift`
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessStore.swift` (Debug-only gallery factory)
- Create: `macos/Sources/Features/PhoneAccess/PhoneAccessGallery.swift` (macOS, Debug)
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (Debug menu item)

**Interfaces:**
- Consumes: everything above.
- Produces: `MobileStore.gallery(sessions:message:pairing:needsPairing:settings:) -> MobileStore` and `isGallery` (Debug); `PhoneAccessStore.gallery(status:lockdownSkipped:phones:pairing:message:) -> PhoneAccessStore` (Debug); `DesignGalleryScreen`, `PhoneAccessGallery.show()`.

- [ ] **Step 1: Gallery hooks in `MobileStore`** (inside the class)

```swift
    #if DEBUG
    /// Design Gallery only: a store frozen in one state that never connects.
    private(set) var isGallery = false

    static func gallery(
        sessions: [RemoteSession] = [], message: String? = nil, pairing: PairingPhase = .idle,
        needsPairing: Bool = false, settings: RemoteHostSettings = RemoteHostSettings()
    ) -> MobileStore {
        let store = MobileStore(defaults: UserDefaults(suiteName: "lostty-design-gallery")!)
        store.isGallery = true
        store.settings = settings
        store.sessions = sessions
        store.message = message
        store.pairing = pairing
        store.needsPairing = needsPairing
        return store
    }
    #endif
```

and add a gallery guard as the first lines of each of these existing methods, so a gallery store never connects or changes state:

- `func refresh() async`, `func resetPairing()`, `func cancelPairing()`, `func pair(link: String) async`, `func retryPairingTest() async`:

```swift
        #if DEBUG
        if isGallery { return }
        #endif
```

- `func kill(_ session: RemoteSession) async -> Bool`:

```swift
        #if DEBUG
        if isGallery { return false }
        #endif
```

- [ ] **Step 2: `DesignGallery.swift`** (iOS)

```swift
#if os(iOS) && DEBUG
import LosttyRemote
import SwiftUI

/// Debug only: every Lostty screen in every state, with fake data, for
/// review. Open with launch argument `-LosttyDesignGallery YES`. Each entry
/// opens full screen (screens bring their own navigation stacks, which
/// can't be nested), with a Close button.
struct DesignGalleryScreen: View {
    private struct Entry: Identifiable {
        let id: String
        let screen: () -> AnyView
    }

    private static let paired = RemoteHostSettings(
        host: "laws-macbook-pro.tail278d1f.ts.net", port: 22, user: "lawliang",
        fallbackHost: "100.126.63.10", pairedAt: Date(timeIntervalSince1970: 1_791_000_000))
    private static let sessions = [
        RemoteSession(id: "$1", name: "lostty", surface: "A", owner: 1),
        RemoteSession(id: "$2", name: "ghostty-skins-experiments-with-a-very-long-name", surface: nil, owner: nil),
        RemoteSession(id: "$3", name: "home", surface: "B", owner: 1),
    ]

    @State private var shown: Entry?

    private var sections: [(String, [Entry])] {
        func entry(_ title: String, _ screen: @escaping () -> some View) -> Entry {
            Entry(id: title, screen: { AnyView(screen()) })
        }
        func pairing(_ title: String, _ phase: MobileStore.PairingPhase) -> Entry {
            entry(title) {
                NavigationStack { PairingScreen() }
                    .environmentObject(MobileStore.gallery(pairing: phase, settings: Self.paired))
            }
        }
        return [
            ("First run", [
                entry("Welcome") { WelcomeScreen(pair: {}, settings: {}) },
                entry("Welcome — large text") { WelcomeScreen(pair: {}, settings: {}).dynamicTypeSize(.xxxLarge) },
            ]),
            ("Sessions", [
                entry("Three sessions") {
                    SessionsScreen().environmentObject(MobileStore.gallery(sessions: Self.sessions, settings: Self.paired))
                },
                entry("Three sessions — large text") {
                    SessionsScreen().environmentObject(MobileStore.gallery(sessions: Self.sessions, settings: Self.paired))
                        .dynamicTypeSize(.xxxLarge)
                },
                entry("Message and Pair Again") {
                    SessionsScreen().environmentObject(MobileStore.gallery(
                        message: "Your Mac doesn't accept this phone anymore.", needsPairing: true, settings: Self.paired))
                },
                entry("Empty") {
                    SessionsScreen().environmentObject(MobileStore.gallery(message: MobileStore.noSessionsMessage, settings: Self.paired))
                },
            ]),
            ("Pairing", [
                pairing("Scan", .idle),
                pairing("Finding", .finding),
                pairing("Waiting for Allow", .waitingForAllow),
                pairing("Connecting", .testing),
                pairing("Failed, can retry", .failed(
                    "Your Mac allowed this phone, but Lostty couldn't reach it. \(MobileStore.tailscaleHint)", canRetryTest: true)),
                pairing("Failed", .failed("Your Mac declined. Try again from Phone Access.", canRetryTest: false)),
                pairing("Paired", .done),
            ]),
            ("Other", [
                entry("Settings") {
                    NavigationStack { SettingsScreen() }.environmentObject(MobileStore.gallery(settings: Self.paired))
                },
                entry("Terminal bar and key row (Ctrl latched)") { NavigationStack { TerminalBarPreview() } },
            ]),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { title, entries in
                    Section(title) {
                        ForEach(entries) { entry in
                            Button(entry.id) { shown = entry }
                        }
                    }
                }
            }
            .navigationTitle("Design Gallery")
            .losttyScreen()
        }
        .fullScreenCover(item: $shown) { entry in
            entry.screen()
                .overlay(alignment: .bottomTrailing) {
                    Button("Close") { shown = nil }
                        .buttonStyle(.lostty(.secondary))
                        .padding(LosttyTheme.margin)
                }
        }
    }
}

/// The terminal's top bar over an empty terminal, and the key row with Ctrl
/// latched.
private struct TerminalBarPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.black
            KeyRowPreview().frame(height: 52)
        }
        .toolbar { ToolbarItem(placement: .principal) { TerminalTitle(name: "lostty") } }
        .navigationBarTitleDisplayMode(.inline)
        .losttyScreen()
    }
}

private struct KeyRowPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> Ghostty.KeyRowView {
        let row = Ghostty.KeyRowView()
        row.setCtrl(true)
        return row
    }

    func updateUIView(_ view: Ghostty.KeyRowView, context: Context) {}
}
#endif
```

`SessionsScreen` needs the `Ghostty.App` environment object; the gallery is opened from the app's root (Step 3), which already provides it, and full-screen covers inherit it.

- [ ] **Step 3: Open the gallery** — in `iOSApp.swift`, replace `SessionsScreen()` in the `WindowGroup` with:

```swift
            Group {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "LosttyDesignGallery") {
                    DesignGalleryScreen()
                } else {
                    SessionsScreen()
                }
                #else
                SessionsScreen()
                #endif
            }
```

(keeping all modifiers that followed `SessionsScreen()`).

- [ ] **Step 4: Mac gallery factory** — in `PhoneAccessStore` (inside the class):

```swift
    #if DEBUG
    /// Design Gallery only: a window frozen in one state.
    static func gallery(
        status: PhoneAccessStatus, lockdownSkipped: Bool = false, phones: [PairedPhone] = [],
        pairing: Pairing? = nil, message: String? = nil
    ) -> PhoneAccessStore {
        let store = PhoneAccessStore()
        store.status = status
        store.phones = phones
        store.pairing = pairing
        store.message = message
        store.galleryLockdownSkipped = lockdownSkipped
        return store
    }
    private var galleryLockdownSkipped: Bool?
    #endif
```

Replace the `lockdownSkipped` property with:

```swift
    var lockdownSkipped: Bool {
        get {
            #if DEBUG
            if let galleryLockdownSkipped { return galleryLockdownSkipped }
            #endif
            return defaults.bool(forKey: Self.skipDefaultsKey)
        }
        set {
            defaults.set(newValue, forKey: Self.skipDefaultsKey)
            objectWillChange.send()
        }
    }
```

A gallery store must never probe the Mac, run the admin prompt, start a pairing server, or touch `~/.ssh`. Add this as the first lines of `refresh()`, `reloadPhones()`, `fix(_:)`, `startPairing()`, `rename(_:to:)`, `remove(_:)` and `turnOff()`:

```swift
        #if DEBUG
        if galleryLockdownSkipped != nil { return }
        #endif
```

(`stopPairing()` stays unguarded so the gallery's sheet can close.)

- [ ] **Step 5: `PhoneAccessGallery.swift`** (macOS, Debug)

```swift
#if os(macOS) && DEBUG
import AppKit
import LosttyRemote
import SwiftUI

/// Debug only: the Phone Access window in each state, for review.
@MainActor
enum PhoneAccessGallery {
    private static var window: NSWindow?

    static func show() {
        let ready = PhoneAccessStatus(
            tailscale: .init(running: true, name: "laws-macbook-pro.tail278d1f.ts.net", ipv4: "100.126.63.10"),
            tmuxPath: "/opt/homebrew/bin/tmux", remoteLogin: true, authMethods: ["publickey"],
            lockdownFileExists: true, blockAllIncoming: false, terminfoInstalled: true,
            folders: ["Desktop": true, "Documents": true, "Downloads": true])
        var mixed = ready
        mixed.authMethods = ["publickey", "password"]
        mixed.lockdownFileExists = false
        mixed.terminfoInstalled = false
        mixed.folders = nil
        let phones = [
            PairedPhone(id: "a", name: "iPhone 13", paired: Date(timeIntervalSince1970: 1_791_000_000)),
            PairedPhone(id: "b", name: "Law's other iPhone", paired: nil),
        ]
        let payload = try? PairingPayload(
            name: "laws-macbook-pro.tail278d1f.ts.net", ip: "100.126.63.10", user: "lawliang",
            hostKey: "AAAAC3NzaC1lZDI1NTE5AAAAIO2ib6szt8DC6VJejVmS+ZXbDzWg/68qdlqbp2uhPYfl",
            secret: Data(repeating: 7, count: 32))
        let variants: [(String, PhoneAccessStore)] = [
            ("All ready, two phones", .gallery(status: ready, phones: phones)),
            ("Mixed checklist, no phones", .gallery(status: mixed)),
            ("Password logins skipped", .gallery(status: mixed, lockdownSkipped: true)),
            ("Pairing sheet", .gallery(status: ready, pairing: payload.map { .showing($0, expires: Date().addingTimeInterval(75)) })),
            ("Expired code", .gallery(status: ready, pairing: .expired)),
        ]
        let content = TabView {
            ForEach(variants.indices, id: \.self) { index in
                PhoneAccessView().environmentObject(variants[index].1)
                    .tabItem { Text(variants[index].0) }
            }
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "Phone Access Design Gallery"
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 600, height: 760))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
#endif
```

In `AppDelegate.swift`, inside the existing `#if DEBUG` block that installs "Preview Claude Trace" (after `RemoteDebugUI.installMenuItems(after: item)`), add a menu item:

```swift
            let gallery = NSMenuItem(title: "Phone Access Design Gallery", action: #selector(showPhoneAccessGallery(_:)), keyEquivalent: "")
            gallery.target = self
            menu.insertItem(gallery, at: menu.index(of: item) + 1)
```

and next to `previewClaudeTrace(_:)`:

```swift
    @objc private func showPhoneAccessGallery(_ sender: Any?) {
        MainActor.assumeIsolated { PhoneAccessGallery.show() }
    }
```

- [ ] **Step 6: Builds and suites**

Run both builds (Debug) → `** BUILD SUCCEEDED **`; also build the iOS app in Release (`-configuration Release`) to prove the gallery is compiled out → `** BUILD SUCCEEDED **`. Run `macos/skins-test.sh PhoneAccessRowsTests` and `PairingDecisionTests` → pass.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/App/iOS/MobileStore.swift macos/Sources/App/iOS/DesignGallery.swift macos/Sources/App/iOS/iOSApp.swift macos/Sources/Features/PhoneAccess/PhoneAccessStore.swift macos/Sources/Features/PhoneAccess/PhoneAccessGallery.swift macos/Sources/App/macOS/AppDelegate.swift
git commit -m "lostty: Debug-only Design Galleries for the iPhone app and Phone Access

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Screenshots and review (controller and human)

Not an implementer task. The controller:

1. Boots an iPhone simulator, installs the Debug iOS build with launch argument `-LosttyDesignGallery YES`, and screenshots every gallery entry (XcodeBuildMCP `screenshot`), including the large-text variants.
2. Opens the Mac Debug build, chooses **Phone Access Design Gallery**, and screenshots each tab (`screencapture -l <window id>`).
3. Shows the screenshots to the human for review, with Review Focus 1–5 called out.
4. After approval: installs on the human's iPhone and runs the full suite (`macos/skins-test.sh`) and the package tests once more.
