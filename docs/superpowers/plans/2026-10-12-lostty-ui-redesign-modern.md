# Lostty UI Redesign, Modern Pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the line-drawn axolotl with the approved chibi, swap the blueprint grid for a soft glow, give pairing native-style steps, and give the Mac Phone Access window its new layout. Nothing else changes.

**Architecture:** Everything shared lives in `macos/Sources/Features/LosttyDesign/` (compiled by both app targets). The axolotl keeps its API (`Axolotl(pose:)`, `AxolotlMotion`); only its drawing changes. A small `FlowLayout` wraps the Mac's fix buttons. A `CountdownRing` shape traces from top center so the trimmed ring counts down from 12 o'clock.

**Tech Stack:** Swift 5 mode; SwiftUI (iOS 17, macOS 14); Swift Testing (`GhosttyTests`, macOS host).

**Spec:** `docs/superpowers/specs/2026-10-12-lostty-ui-redesign-modern-design.md` (revises `docs/superpowers/specs/2026-10-12-lostty-ui-redesign-design.md`). The approved mock is `docs/superpowers/specs/assets/lostty-modern-mock.html` and the approved drawing is `docs/superpowers/specs/assets/lostty-chibi-axolotl.svg`.

## Global Constraints

- **No behavior changes.** Same flows, same buttons, same store and pairing logic. Every existing error, security and alert string stays exactly as it is.
- **New copy, verbatim:** "Nothing running yet" (empty sessions title) and "Open Lostty on your Mac." (its detail line). These replace the single line "Nothing running yet. Open Lostty on your Mac."
- **Chibi colors (exact):** head `#F7B2D8`, body and tail `#EC97C6`, gills `LosttyTheme.accent` (`#E5199C`), face ink `#3A1530`, blush accent at 45%, head highlight white at 35%. The check on the happy pose is accent.
- **Glow:** a radial gradient from `LosttyTheme.accent` at 22% to clear. It goes only behind the axolotl on welcome, pairing (waiting and paired), empty sessions and the Mac pairing sheet.
- **Motion:** keep `AxolotlMotion` as is (blink on 0.6 s / off 0.4 s, sway ±4°, `happyLift` 10). Everything is still under Reduce Motion.
- **Shared tokens:** `LosttyTheme`, `LosttyFont`, `LosttyButton`, `LosttyCard` and `.losttyScreen()` are unchanged.
- **Tests:**
  - App suites: `macos/skins-test.sh <Suite>`. To run several suites, pass them as one argument: `macos/skins-test.sh "SuiteA -only-testing:GhosttyTests/SuiteB"`.
  - Package tests: `swift test --package-path macos/LosttyRemote`.
  - Never wrap a command in `sh -c`.
- **Builds:** both must print `** BUILD SUCCEEDED **`.
  - iOS: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty-iOS -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO SYMROOT="$PWD/macos/build" CODE_SIGNING_ALLOWED=NO build`
  - Mac: `xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" build`
- **Stray `default.profraw`:** if one appears under `macos/Sources` or `macos/Tests`, delete it. Never stage any `default.profraw`.
- **Commits:** stage by path, and end each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never create a PR or issue. Leave `src/shell-integration/lostty-tmux/tmux.conf` alone (unrelated local change).

## Review Focus

1. **The chibi at small sizes:** at the Mac header (58 pt), the sheet (64 pt) and the launch image (120 pt), the face and gills stay readable and nothing pokes out of the box. Pinned by `AxolotlGeometryTests.drawingStaysInsideItsBox` (Task 1) and the renders in Task 1 and Task 6.
2. **Reduce Motion:** the waiting chibi holds still (eye shown, gills at rest). Pinned by the existing `AxolotlMotionTests.reduceMotionIsStill`, unchanged.
3. **The Mac row with two fix buttons:** with "Turn Off Password Logins…" and "Skip" in a 560 pt window, the buttons sit under the text and wrap to a new line instead of clipping. Pinned by `FlowLayoutTests` (Task 4) and the mixed-checklist render (Task 6).
4. **The countdown at full and at expiry:** the ring is whole at 1, gone at 0, and always anchored at 12 o'clock. Pinned by `CountdownRingTests` (Task 5) and the existing `PairingCountdownTests`.
5. **Largest standard Dynamic Type on the pairing steps:** each row's spinner or marker stays beside its title, and titles wrap. Pinned by the XXXL screenshots in Task 6.

---

## File Structure

| File | Change |
|---|---|
| `macos/Sources/Features/LosttyDesign/AxolotlShapes.swift` | Rewritten: chibi geometry and shapes |
| `macos/Sources/Features/LosttyDesign/Axolotl.swift` | Drawing replaced; `AxolotlMotion.lineWidth` removed |
| `macos/Sources/Features/LosttyDesign/LosttyGlow.swift` | New: `.losttyGlow(diameter:)` |
| `macos/Sources/Features/LosttyDesign/BlueprintBackground.swift` | Deleted |
| `macos/Sources/Features/LosttyDesign/PairingProgress.swift` | `StepIndicator` rows, pulse removed, `CountdownRing` added |
| `macos/Sources/Features/LosttyDesign/FlowLayout.swift` | New: wrapping layout |
| `macos/Sources/Features/LosttyDesign/LosttyCard.swift` | `StatusRow` new layout |
| `macos/Sources/App/iOS/WelcomeScreen.swift`, `SessionsScreen.swift`, `PairingScreen.swift` | Glow, empty state, dot glow, Done pinned |
| `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift` | Header, sheet glow, ring |
| `macos/Assets.xcassets/LaunchAxolotl.imageset/*.png` | Re-rendered |
| `macos/Tests/LosttyDesign/AxolotlGeometryTests.swift`, `FlowLayoutTests.swift`, `CountdownRingTests.swift` | New tests |
| `macos/Tests/LosttyDesign/PairingProgressTests.swift` | `StepPulseTests` removed |

---

### Task 1: The chibi axolotl

**Files:**
- Rewrite: `macos/Sources/Features/LosttyDesign/AxolotlShapes.swift`
- Modify: `macos/Sources/Features/LosttyDesign/Axolotl.swift`
- Replace: `macos/Assets.xcassets/LaunchAxolotl.imageset/LaunchAxolotl.png`, `LaunchAxolotl@2x.png`, `LaunchAxolotl@3x.png`
- Test: `macos/Tests/LosttyDesign/AxolotlGeometryTests.swift`

**Interfaces:**
- Produces:
  - `AxolotlGeometry.Petal` (`x, y, rx, ry, rotation: CGFloat`);
  - `AxolotlGeometry.gills(_: AxolotlSide) -> [Petal]`;
  - `AxolotlGeometry.gillAnchor(_:) -> UnitPoint`;
  - `AxolotlGeometry.skin / shade / ink: Color`;
  - `AxolotlPart(kind:)`, where `Kind` is `.tail, .body, .belly, .limbs, .gills(AxolotlSide), .head, .highlight, .blush`;
  - `AxolotlPart.unitPath(_:) -> Path` (in the 100-unit box);
  - `AxolotlEyes(cursorVisible:)`, `AxolotlMouth()`, `AxolotlCheck()`.
  
  `Axolotl(pose:)` and `AxolotlMotion` keep their current API, except that `lineWidth(forSide:)` is removed.

- [ ] **Step 1: Write the failing test**

`macos/Tests/LosttyDesign/AxolotlGeometryTests.swift`:

```swift
import SwiftUI
import Testing
@testable import Ghostty

struct AxolotlGeometryTests {
    @Test func rightGillsMirrorTheLeft() {
        let left = AxolotlGeometry.gills(.left)
        let right = AxolotlGeometry.gills(.right)
        #expect(left.count == 3)
        for (l, r) in zip(left, right) {
            #expect(r.x == 100 - l.x)
            #expect(r.y == l.y)
            #expect(r.rotation == -l.rotation)
        }
    }

    @Test func gillsFanUpwardFromTopToBottom() {
        #expect(AxolotlGeometry.gills(.left).map(\.rotation) == [-42, -12, 18])
    }

    @Test func drawingStaysInsideItsBox() {
        let kinds: [AxolotlPart.Kind] = [.tail, .body, .belly, .limbs, .gills(.left), .gills(.right),
                                         .head, .highlight, .blush]
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        for kind in kinds {
            #expect(box.contains(AxolotlPart.unitPath(kind).boundingRect))
        }
        #expect(box.contains(AxolotlCheck().path(in: box).boundingRect))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `macos/skins-test.sh AxolotlGeometryTests`
Expected: the build fails (`AxolotlPart` not found, and `AxolotlGeometry` has no member `gills`).

- [ ] **Step 3: Rewrite `AxolotlShapes.swift`**

```swift
import SwiftUI

/// The approved chibi axolotl (docs/superpowers/specs/assets/lostty-chibi-axolotl.svg),
/// drawn in a 100×100 box with y down.
enum AxolotlGeometry {
    /// One gill petal: an ellipse centred at (x, y), turned by `rotation` degrees.
    struct Petal: Equatable {
        var x: CGFloat
        var y: CGFloat
        var rx: CGFloat
        var ry: CGFloat
        var rotation: CGFloat
    }

    static let leftGills: [Petal] = [
        Petal(x: 14, y: 21, rx: 9, ry: 4.6, rotation: -42),
        Petal(x: 9, y: 34, rx: 9, ry: 4.6, rotation: -12),
        Petal(x: 11, y: 47, rx: 8.5, ry: 4.3, rotation: 18),
    ]

    /// The right side mirrors the left.
    static func gills(_ side: AxolotlSide) -> [Petal] {
        switch side {
        case .left: leftGills
        case .right: leftGills.map { Petal(x: 100 - $0.x, y: $0.y, rx: $0.rx, ry: $0.ry, rotation: -$0.rotation) }
        }
    }

    /// Where each side's gills meet the head, as a unit point for swaying them.
    static func gillAnchor(_ side: AxolotlSide) -> UnitPoint {
        side == .left ? UnitPoint(x: 0.20, y: 0.34) : UnitPoint(x: 0.80, y: 0.34)
    }

    static let skin = Color(losttyHex: 0xF7B2D8)
    static let shade = Color(losttyHex: 0xEC97C6)
    static let ink = Color(losttyHex: 0x3A1530)
}

enum AxolotlSide { case left, right }

private extension Path {
    /// Scales a path drawn in the 100-unit box into `rect`.
    func fitted(to rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        return applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale))
    }

    static func unitEllipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rotation: CGFloat = 0) -> Path {
        Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            .applying(CGAffineTransform(rotationAngle: rotation * .pi / 180)
                .concatenating(CGAffineTransform(translationX: x, y: y)))
    }
}

/// One filled part of the chibi; each part is a single colour.
struct AxolotlPart: Shape {
    enum Kind { case tail, body, belly, limbs, gills(AxolotlSide), head, highlight, blush }

    var kind: Kind

    func path(in rect: CGRect) -> Path { Self.unitPath(kind).fitted(to: rect) }

    static func unitPath(_ kind: Kind) -> Path {
        switch kind {
        case .tail:
            var path = Path()
            path.move(to: CGPoint(x: 60, y: 82))
            path.addCurve(to: CGPoint(x: 84, y: 76), control1: CGPoint(x: 70, y: 86), control2: CGPoint(x: 80, y: 84))
            path.addCurve(to: CGPoint(x: 80, y: 73), control1: CGPoint(x: 86, y: 72), control2: CGPoint(x: 82, y: 70))
            path.addCurve(to: CGPoint(x: 63, y: 76), control1: CGPoint(x: 77, y: 78), control2: CGPoint(x: 70, y: 79))
            path.closeSubpath()
            return path
        case .body:
            return .unitEllipse(50, 76, 15, 12)
        case .belly:
            return .unitEllipse(50, 79, 8, 6)
        case .limbs:
            var path = Path()
            let limbs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(39, 80, 4.2, 3.2), (61, 80, 4.2, 3.2), (43, 88, 5, 3), (57, 88, 5, 3)]
            for (x, y, rx, ry) in limbs { path.addPath(.unitEllipse(x, y, rx, ry)) }
            return path
        case .gills(let side):
            var path = Path()
            for petal in AxolotlGeometry.gills(side) {
                path.addPath(.unitEllipse(petal.x, petal.y, petal.rx, petal.ry, rotation: petal.rotation))
            }
            return path
        case .head:
            // A soft rounded square: flatter on top than an ellipse.
            var path = Path()
            path.move(to: CGPoint(x: 50, y: 15))
            path.addCurve(to: CGPoint(x: 83, y: 42.3), control1: CGPoint(x: 76.4, y: 15), control2: CGPoint(x: 83, y: 26.7))
            path.addCurve(to: CGPoint(x: 50, y: 67), control1: CGPoint(x: 83, y: 60.5), control2: CGPoint(x: 69.8, y: 67))
            path.addCurve(to: CGPoint(x: 17, y: 42.3), control1: CGPoint(x: 30.2, y: 67), control2: CGPoint(x: 17, y: 60.5))
            path.addCurve(to: CGPoint(x: 50, y: 15), control1: CGPoint(x: 17, y: 26.7), control2: CGPoint(x: 23.6, y: 15))
            path.closeSubpath()
            return path
        case .highlight:
            return .unitEllipse(34, 24, 7, 3.2, rotation: -18)
        case .blush:
            var path = Path()
            path.addPath(.unitEllipse(26, 55, 5, 3))
            path.addPath(.unitEllipse(75, 55, 5, 3))
            return path
        }
    }
}

/// The icon's prompt eyes: ">" and a "—" that blinks like a cursor.
struct AxolotlEyes: Shape {
    var cursorVisible = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 33, y: 36))
        path.addLine(to: CGPoint(x: 42, y: 43))
        path.addLine(to: CGPoint(x: 33, y: 50))
        if cursorVisible {
            path.move(to: CGPoint(x: 56, y: 43))
            path.addLine(to: CGPoint(x: 68, y: 43))
        }
        return path.fitted(to: rect)
    }
}

/// A small "w" mouth.
struct AxolotlMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 46, y: 53))
        path.addQuadCurve(to: CGPoint(x: 50, y: 53.5), control: CGPoint(x: 48, y: 56))
        path.addQuadCurve(to: CGPoint(x: 54, y: 53), control: CGPoint(x: 52, y: 56))
        return path.fitted(to: rect)
    }
}

/// The check the happy pose holds up, top right.
struct AxolotlCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 74, y: 14))
        path.addLine(to: CGPoint(x: 80, y: 20))
        path.addLine(to: CGPoint(x: 92, y: 6))
        return path.fitted(to: rect)
    }
}
```

- [ ] **Step 4: Replace the drawing in `Axolotl.swift`**

Replace the doc comment and `drawing(cursor:gills:)` with the code below. Keep `body`, `Pose`, `pose`, `reduceMotion`, and in `AxolotlMotion` keep `happyLift`, `cursorVisible`, `gillSway` and `frame`. Delete `AxolotlMotion.lineWidth(forSide:)` and its comment.

```swift
/// Lostty's mascot, a chibi axolotl. `.waiting` blinks its cursor eye and
/// sways its gills; `.happy` lifts its gills and holds a check. Decorative:
/// hidden from VoiceOver.
```

```swift
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
```

- [ ] **Step 5: Run the tests**

Run: `macos/skins-test.sh "AxolotlGeometryTests -only-testing:GhosttyTests/AxolotlMotionTests"`
Expected: `** TEST SUCCEEDED **` (3 + 4 tests).

- [ ] **Step 6: Render, compare and replace the launch image**

Run:
```bash
mkdir -p /tmp/lostty-render
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin TEST_RUNNER_LOSTTY_RENDER_DIR=/tmp/lostty-render xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/macos/build" -skip-testing GhosttyUITests -only-testing:GhosttyTests/LosttyRenderTests test > macos/build/render.log 2>&1
grep -E "\*\* TEST (SUCCEEDED|FAILED)" macos/build/render.log
cp /tmp/lostty-render/LaunchAxolotl@1x.png macos/Assets.xcassets/LaunchAxolotl.imageset/LaunchAxolotl.png
cp /tmp/lostty-render/LaunchAxolotl@2x.png /tmp/lostty-render/LaunchAxolotl@3x.png macos/Assets.xcassets/LaunchAxolotl.imageset/
```
Expected:
- the run prints `** TEST SUCCEEDED **`;
- `/tmp/lostty-render/axolotl-poses.png` shows resting, waiting and happy chibis;
- the launch PNGs are 120, 240 and 360 px wide, with transparent backgrounds.

Open `axolotl-poses.png` and the SVG (render it with `qlmanage -t -s 400 -o /tmp/lostty-render docs/superpowers/specs/assets/lostty-chibi-axolotl.svg`) and check that they match. The happy pose's gills sit a little higher and it has a magenta check top right.

- [ ] **Step 7: Both builds**

Run the iOS and Mac builds from Global Constraints.
Expected: both print `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/LosttyDesign/AxolotlShapes.swift macos/Sources/Features/LosttyDesign/Axolotl.swift macos/Tests/LosttyDesign/AxolotlGeometryTests.swift macos/Assets.xcassets/LaunchAxolotl.imageset
git commit -m "lostty: the chibi axolotl replaces the line drawing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: A glow instead of the blueprint grid

Purely visual: there's no pure logic to unit-test. It's verified by the builds, the `grep` and the Task 6 screenshots.

**Files:**
- Create: `macos/Sources/Features/LosttyDesign/LosttyGlow.swift`
- Delete: `macos/Sources/Features/LosttyDesign/BlueprintBackground.swift`
- Modify: `macos/Sources/App/iOS/WelcomeScreen.swift`, `macos/Sources/App/iOS/PairingScreen.swift`, `macos/Sources/App/iOS/SessionsScreen.swift`, `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift`

**Interfaces:**
- Produces: `View.losttyGlow(diameter: CGFloat) -> some View`.

- [ ] **Step 1: Write `LosttyGlow.swift`**

```swift
import SwiftUI

extension View {
    /// A soft magenta glow behind a hero element: the axolotl on welcome,
    /// pairing, empty sessions and the Mac pairing sheet.
    func losttyGlow(diameter: CGFloat) -> some View {
        background {
            RadialGradient(colors: [LosttyTheme.accent.opacity(0.22), LosttyTheme.accent.opacity(0)],
                           center: .center, startRadius: 0, endRadius: diameter / 2)
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
```

- [ ] **Step 2: Replace each `BlueprintBackground()`**

- **`WelcomeScreen.swift`:**
  - delete the line `BlueprintBackground()`;
  - change `Axolotl(pose: .resting)\n                        .frame(width: 160, height: 160)` to `Axolotl(pose: .resting)\n                        .frame(width: 160, height: 160)\n                        .losttyGlow(diameter: 360)`;
  - add `.background(LosttyTheme.background.ignoresSafeArea())` after the `ZStack { … }`'s closing brace.
- **`PairingScreen.swift`:**
  - delete the line `BlueprintBackground()`;
  - change `Axolotl(pose: .waiting).frame(width: 120, height: 120).padding(.top, 24)` to `Axolotl(pose: .waiting).frame(width: 120, height: 120).losttyGlow(diameter: 290).padding(.top, 24)`;
  - change `Axolotl(pose: .happy).frame(width: 140, height: 140).padding(.top, 24)` to `Axolotl(pose: .happy).frame(width: 140, height: 140).losttyGlow(diameter: 330).padding(.top, 24)`.
- **`SessionsScreen.swift`** (`EmptySessions`):
  - delete the line `BlueprintBackground()`;
  - change `Axolotl(pose: .resting).frame(width: 120, height: 120)` to `Axolotl(pose: .resting).frame(width: 120, height: 120).losttyGlow(diameter: 280)`.
- **`PhoneAccessView.swift`** (`PairingSheet`):
  - replace `BlueprintBackground()` with `LosttyTheme.background.ignoresSafeArea()`;
  - change `Axolotl(pose: .waiting).frame(width: 56, height: 56)` to `Axolotl(pose: .waiting).frame(width: 64, height: 64).losttyGlow(diameter: 220)`;
  - change `Axolotl(pose: .resting).frame(width: 56, height: 56)` to `Axolotl(pose: .resting).frame(width: 64, height: 64).losttyGlow(diameter: 220)`.

Then `git rm macos/Sources/Features/LosttyDesign/BlueprintBackground.swift`.

- [ ] **Step 3: Check nothing still uses it, and build**

Run: `grep -rn BlueprintBackground macos/Sources macos/Tests`
Expected: no output.
Then run both builds. Expected: both print `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Features/LosttyDesign/LosttyGlow.swift macos/Sources/App/iOS/WelcomeScreen.swift macos/Sources/App/iOS/PairingScreen.swift macos/Sources/App/iOS/SessionsScreen.swift macos/Sources/Features/PhoneAccess/PhoneAccessView.swift
git commit -m "lostty: a soft glow behind the axolotl instead of the blueprint grid

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: iPhone: pairing steps, empty state, live dot, Done

**Files:**
- Modify: `macos/Sources/Features/LosttyDesign/PairingProgress.swift` (`StepIndicator`; remove `PulsingDot`, `StepPulse`)
- Modify: `macos/Tests/LosttyDesign/PairingProgressTests.swift` (remove `StepPulseTests`)
- Modify: `macos/Sources/App/iOS/PairingScreen.swift`, `macos/Sources/App/iOS/SessionsScreen.swift`

**Interfaces:**
- Consumes: `PairingProgress`, `PairingStep`, `PairingStepState` (unchanged); `.losttyGlow(diameter:)` (Task 2).
- Produces: `StepIndicator(progress:)` with the same signature and a new look. Put it in a `LosttyCard(padding: 0)`.

- [ ] **Step 1: Remove the pulse and its tests**

In `PairingProgressTests.swift`, delete the whole `struct StepPulseTests { … }`. In `PairingProgress.swift`, delete `private struct PulsingDot` and `enum StepPulse`, including their doc comments.

Run: `macos/skins-test.sh "PairingProgressTests -only-testing:GhosttyTests/PairingCountdownTests"`
Expected: the build fails, because `StepIndicator` still references `PulsingDot`. Step 2 replaces it.

- [ ] **Step 2: Rewrite `StepIndicator`**

Replace `struct StepIndicator` and its doc comment with:

```swift
/// The pairing steps as rows: done ✓, the current one with a spinner, the
/// rest waiting.
struct StepIndicator: View {
    var progress: PairingProgress

    var body: some View {
        VStack(spacing: 0) {
            ForEach(PairingStep.allCases) { step in
                let state = progress.state(of: step)
                if step != .find { Rectangle().fill(LosttyTheme.hairline).frame(height: 1) }
                HStack(spacing: 12) {
                    marker(state).frame(width: 20, height: 20)
                    Text(step.title)
                        .font(state == .current ? LosttyFont.bodyEmphasis : LosttyFont.body)
                        .foregroundStyle(state == .pending ? LosttyTheme.textSecondary : LosttyTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.title), \(state == .done ? "done" : state == .current ? "in progress" : "not started")")
            }
        }
    }

    @ViewBuilder private func marker(_ state: PairingStepState) -> some View {
        switch state {
        case .done:
            Circle().fill(LosttyTheme.accent)
                .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
        case .current:
            ProgressView().controlSize(.small).tint(LosttyTheme.textPrimary)
        case .pending:
            Circle().strokeBorder(LosttyTheme.hairline, lineWidth: 1.5)
        }
    }
}
```

In `PairingScreen.swift`, change `LosttyCard { StepIndicator(progress: progress) }` to `LosttyCard(padding: 0) { StepIndicator(progress: progress) }`.

- [ ] **Step 3: Pin Done to the bottom of the Paired screen**

In `PairingScreen.swift`, delete the line `Button("Done") { dismiss() }.buttonStyle(.lostty(.primary, fullWidth: true))` from `case .done:`. Then add this right after the `ScrollView { … }` closing brace, before the `ZStack`'s closing brace:

```swift
            .safeAreaInset(edge: .bottom) {
                if store.pairing == .done {
                    Button("Done") { dismiss() }
                        .buttonStyle(.lostty(.primary, fullWidth: true))
                        .padding(LosttyTheme.margin)
                }
            }
```

- [ ] **Step 4: Empty state and live dot**

In `SessionsScreen.swift`, replace `EmptySessions`'s `body` with:

```swift
    var body: some View {
        VStack(spacing: 10) {
            Axolotl(pose: .resting).frame(width: 104, height: 104).losttyGlow(diameter: 260)
                .padding(.bottom, 6)
            Text("Nothing running yet")
                .font(LosttyFont.bodyEmphasis)
                .foregroundStyle(LosttyTheme.textPrimary)
            Text("Open Lostty on your Mac.")
                .font(LosttyFont.detail)
                .foregroundStyle(LosttyTheme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(LosttyTheme.margin)
    }
```

On the session card's live dot, change `Circle().fill(LosttyTheme.accent).frame(width: 8, height: 8)` to `Circle().fill(LosttyTheme.accent).frame(width: 8, height: 8)\n                                    .shadow(color: LosttyTheme.accent.opacity(0.7), radius: 4)`.

- [ ] **Step 5: Tests and builds**

Run: `macos/skins-test.sh "PairingProgressTests -only-testing:GhosttyTests/PairingCountdownTests"`
Expected: `** TEST SUCCEEDED **`.
Then run both builds. Expected: both print `** BUILD SUCCEEDED **`.
Then run `grep -rn "StepPulse\|PulsingDot" macos/Sources macos/Tests`. Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/LosttyDesign/PairingProgress.swift macos/Tests/LosttyDesign/PairingProgressTests.swift macos/Sources/App/iOS/PairingScreen.swift macos/Sources/App/iOS/SessionsScreen.swift
git commit -m "lostty: pairing steps with a spinner, a friendlier empty state, Done at the bottom

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Mac Phone Access window

**Files:**
- Create: `macos/Sources/Features/LosttyDesign/FlowLayout.swift`
- Modify: `macos/Sources/Features/LosttyDesign/LosttyCard.swift` (`StatusRow.body` and icon)
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift` (`header`)
- Test: `macos/Tests/LosttyDesign/FlowLayoutTests.swift`

**Interfaces:**
- Produces:
  - `FlowLayout(spacing: CGFloat = 8, topPadding: CGFloat = 0)`, a `Layout`;
  - `FlowLayout.origins(for sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> [CGPoint]`.
  
  The `StatusRow(status:title:detail:) { actions }` signature is unchanged, so no call site changes.

- [ ] **Step 1: Write the failing test**

`macos/Tests/LosttyDesign/FlowLayoutTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import Ghostty

struct FlowLayoutTests {
    let button = CGSize(width: 100, height: 28)

    @Test func fitsOnOneLine() {
        #expect(FlowLayout.origins(for: [button, CGSize(width: 50, height: 28)], maxWidth: 300, spacing: 8)
            == [CGPoint(x: 0, y: 0), CGPoint(x: 108, y: 0)])
    }

    @Test func wrapsWhenTheNextDoesNotFit() {
        // "Turn Off Password Logins…" then "Skip" in a narrow column.
        #expect(FlowLayout.origins(for: [CGSize(width: 200, height: 28), CGSize(width: 120, height: 28)],
                                   maxWidth: 300, spacing: 8)
            == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 36)])
    }

    @Test func aWideChildStillStartsTheFirstLine() {
        #expect(FlowLayout.origins(for: [CGSize(width: 400, height: 28)], maxWidth: 300, spacing: 8)
            == [CGPoint(x: 0, y: 0)])
    }

    @Test func noChildrenNoOrigins() {
        #expect(FlowLayout.origins(for: [], maxWidth: 300, spacing: 8).isEmpty)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `macos/skins-test.sh FlowLayoutTests`
Expected: the build fails (`FlowLayout` not found).

- [ ] **Step 3: Write `FlowLayout.swift`**

```swift
import SwiftUI

/// Lays children left to right and wraps to a new line when the next one
/// doesn't fit (the fix buttons under a checklist row). With no children it
/// takes no space, including its top padding.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var topPadding: CGFloat = 0

    /// Each child's origin, given the children's sizes and the width available.
    static func origins(for sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> [CGPoint] {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for size in sizes {
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return origins
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let origins = Self.origins(for: sizes, maxWidth: proposal.width ?? .infinity, spacing: spacing)
        let width = zip(origins, sizes).map { origin, size in origin.x + size.width }.max() ?? 0
        let height = zip(origins, sizes).map { origin, size in origin.y + size.height }.max() ?? 0
        return CGSize(width: width, height: height + topPadding)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let origins = Self.origins(for: sizes, maxWidth: bounds.width, spacing: spacing)
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + topPadding + origin.y),
                          proposal: .unspecified)
        }
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `macos/skins-test.sh FlowLayoutTests`
Expected: `** TEST SUCCEEDED **` (4 tests).

- [ ] **Step 5: New `StatusRow` layout**

In `LosttyCard.swift`, replace `StatusRow`'s `body` and `icon` (keep `color`, and change nothing else) with:

```swift
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(color)
                Image(systemName: glyph)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LosttyTheme.background)
            }
            .frame(width: 18, height: 18)
            .padding(.top, 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status == .ok ? "Ready" : status == .warning ? "Needs attention" : "Not ready")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LosttyFont.bodyEmphasis).foregroundStyle(LosttyTheme.textPrimary)
                Text(detail).font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                // Fix buttons sit under the text so the text keeps the full width.
                FlowLayout(spacing: 8, topPadding: 8) { trailing }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }

    private var glyph: String {
        switch status {
        case .ok: "checkmark"
        case .warning: "exclamationmark"
        case .missing: "xmark"
        }
    }
```

Update the doc comment above `struct StatusRow` to read: `/// A checklist row: status dot, title, wrapping detail, and fix buttons under it.`

- [ ] **Step 6: New header**

In `PhoneAccessView.swift`, in `header`, change `Axolotl(pose: .resting).frame(width: 52, height: 52)` to `Axolotl(pose: .resting).frame(width: 58, height: 58)`. Then change `Text("Phone Access").font(LosttyFont.largeTitle)` to `Text("Phone Access").font(.system(size: 24, weight: .bold))`.

- [ ] **Step 7: Suites and builds**

Run: `macos/skins-test.sh "FlowLayoutTests -only-testing:GhosttyTests/PhoneAccessReadinessTests -only-testing:GhosttyTests/PhoneAccessRowsTests -only-testing:GhosttyTests/PairingDecisionTests -only-testing:GhosttyTests/PhoneAccessGalleryTests"`
Expected: `** TEST SUCCEEDED **`.
Then run both builds. Expected: both print `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/LosttyDesign/FlowLayout.swift macos/Sources/Features/LosttyDesign/LosttyCard.swift macos/Sources/Features/PhoneAccess/PhoneAccessView.swift macos/Tests/LosttyDesign/FlowLayoutTests.swift
git commit -m "lostty: Phone Access rows put fix buttons under the text; bigger header

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The countdown ring starts at 12 o'clock

**Files:**
- Modify: `macos/Sources/Features/LosttyDesign/PairingProgress.swift` (add `CountdownRing`)
- Modify: `macos/Sources/Features/PhoneAccess/PhoneAccessView.swift` (`qrTile`)
- Test: `macos/Tests/LosttyDesign/CountdownRingTests.swift`

**Interfaces:**
- Consumes: `PairingCountdown.fraction(now:expires:total:)` (unchanged).
- Produces: `CountdownRing(cornerRadius: CGFloat)`, a `Shape`.

- [ ] **Step 1: Write the failing test**

`macos/Tests/LosttyDesign/CountdownRingTests.swift`:

```swift
import SwiftUI
import Testing
@testable import Ghostty

struct CountdownRingTests {
    let rect = CGRect(x: 0, y: 0, width: 280, height: 280)

    @Test func startsAndEndsAtTopCentre() {
        let path = CountdownRing(cornerRadius: 24).path(in: rect)
        var first: CGPoint?
        path.forEach { element in
            if first == nil, case .move(let point) = element { first = point }
        }
        #expect(first == CGPoint(x: 140, y: 0))
        #expect(path.currentPoint == CGPoint(x: 140, y: 0))
    }

    @Test func runsClockwiseTowardTheTopRightFirst() {
        let path = CountdownRing(cornerRadius: 24).path(in: rect)
        var second: CGPoint?
        path.forEach { element in
            guard second == nil else { return }
            switch element {
            case .line(let point), .quadCurve(let point, _), .curve(let point, _, _): second = point
            default: break
            }
        }
        #expect((second?.x ?? 0) > 140)
        #expect(second?.y == 0)
    }

    @Test func staysInsideItsRect() {
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(CountdownRing(cornerRadius: 24).path(in: rect).boundingRect))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `macos/skins-test.sh CountdownRingTests`
Expected: the build fails (`CountdownRing` not found).

- [ ] **Step 3: Add `CountdownRing`**

At the end of `PairingProgress.swift`:

```swift
/// A rounded square traced clockwise from top centre, so a trimmed ring
/// counts down from 12 o'clock.
struct CountdownRing: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        let top = CGPoint(x: rect.midX, y: rect.minY)
        var path = Path()
        path.move(to: top)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: top, radius: radius)
        path.addLine(to: top)
        return path
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `macos/skins-test.sh "CountdownRingTests -only-testing:GhosttyTests/PairingCountdownTests"`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Use it in the sheet**

In `PhoneAccessView.swift`'s `qrTile`, replace the two `RoundedRectangle(cornerRadius: LosttyTheme.radius + 8, style: .continuous)` ring layers with:

```swift
            CountdownRing(cornerRadius: LosttyTheme.radius + 8)
                .stroke(LosttyTheme.hairline, lineWidth: 4)
            // The empty part grows clockwise from 12 o'clock.
            CountdownRing(cornerRadius: LosttyTheme.radius + 8)
                .trim(from: 1 - fraction, to: 1)
                .stroke(LosttyTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .animation(LosttyTheme.motion, value: fraction)
```

- [ ] **Step 6: Build and commit**

Run the Mac build. Expected: `** BUILD SUCCEEDED **`.

```bash
git add macos/Sources/Features/LosttyDesign/PairingProgress.swift macos/Sources/Features/PhoneAccess/PhoneAccessView.swift macos/Tests/LosttyDesign/CountdownRingTests.swift
git commit -m "lostty: the pairing code's ring counts down from 12 o'clock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Screenshots and review (controller and human)

Not an implementer task. The controller does the following:

1. **Checks:** runs the full suite (`macos/skins-test.sh`), the package tests and both builds. It also builds iOS in Release and confirms `strings` on the Release binary finds no "Design Gallery".
2. **Mac renders:** re-renders the Mac window states and sheets (`LosttyRenderTests` with `TEST_RUNNER_LOSTTY_RENDER_DIR`, as in Task 1 Step 6), plus `axolotl-poses.png`.
3. **iPhone screenshots:** on the "Lostty iPhone" simulator (`675B048C-7AC7-428E-A108-AB55D2FCC646`), installs the Debug app and takes a screenshot of every gallery entry:
   - for each entry, run `xcrun simctl launch --terminate-running-process <sim> com.lawliang.lostty-mobile -LosttyDesignGallery YES -LosttyDesignGalleryEntry "<title>"`, wait 3 s, then `xcrun simctl io <sim> screenshot <file>`;
   - first at `xcrun simctl ui <sim> content_size large`, then again at `extra-extra-extra-large` for Welcome, Scan, Waiting for Allow, Failed (can retry), Paired, Settings, Message and Pair Again, and Empty.
4. **Review:** publishes the screenshots to the review artifact (`https://claude.ai/artifact/DAg2cYmtrRnz3gLprKZkHW`), with Review Focus 1–5 called out, and waits for the user's approval.
5. **After approval:** installs on the user's iPhone and runs the full suite and the package tests once more.
