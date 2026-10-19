# Lostty Canvas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Lostty Beta–only canvas window: an infinite whiteboard of terminal cards (each a split group) that pans, pinch-zooms with crisp text, shows agent state per card, jumps to what needs you, and survives Restart to Update.

**Architecture:** One `CanvasController` (an `NSWindowController`) owns the canvas window: an `NSScrollView` with magnification over a 100,000-point flipped document, with a dot grid behind it, wrapped in the window's usual icon row and usage bar. Each card is a `CardController`, **a `BaseTerminalController` subclass** whose `window` is the canvas window, so splits, closing, focus, undo and confirmations run exactly as in a window; its `CardView` hosts the window's own `TerminalView`. Pure layout and agent logic lives in `CanvasModel.swift` and is unit-tested; AppKit glue is checked by hand in the Debug build.

**Tech Stack:** Swift 5.9+, AppKit, SwiftUI, Swift Testing, GhosttyKit C API (`ghostty_surface_set_occlusion`, `ghostty_surface_set_content_scale`), macOS 13.1+.

**Spec:** `docs/superpowers/specs/2026-10-18-lostty-canvas-design.md`

## Global Constraints

- Lostty Beta only: `LosttyChannel.current.hasCanvas` gates every menu item, shortcut, restore and `CanvasController` creation. Stable has no canvas: no menu item, no shortcut, no work done.
- All new code goes in `macos/Sources/Features/Canvas/`; tests in `macos/Tests/Canvas/`. Ghostty's own files get small hooks only.
- Shortcuts: ⌃⌘K Canvas, ⌃⌘J Jump to What Needs You, ⌃⌘0 Zoom to Fit, ⌃⌘1 Zoom Card to 100%, ⌃⌥⌘ + arrows move between cards. Do not take ⌃⌘ + arrows (resize_split), ⇧⌃⌘J (write_screen_file), ⌃⌘F, ⌃⌘[ / ⌃⌘], ⌃⌘=.
- Sizes: new card 720 × 440 points, smallest card 320 × 200, header 24 points, card corner radius 8, zoom 25%–200%, tiles below 45%, zoom settles after 150 ms without change, cull margin half a new card (360 × 220).
- Every file is wrapped in `#if os(macOS)` … `#endif`, like its neighbors. Match the code's comment density and its plain-words doc comments.
- Never use bare `git stash`. Never push. Never create issues or PRs. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Build: `macos/build.nu --configuration Debug` (output `macos/build/Debug/Lostty.app`). Tests: `macos/skins-test.sh <Suite>` (log in `macos/build/last-test.log`); whole suite `macos/skins-test.sh`. swiftlint is not installed; don't try to run it.
- Debug app by hand: `open -n macos/build/Debug/Lostty.app` (its own defaults, `com.lawliang.lostty.debug`). Quit it with `osascript -e 'tell application "<absolute path to macos/build/Debug/Lostty.app>" to quit'`. Never Restart to Update the Debug build. Never quit or kill `/Applications/Lostty.app`. Don't install anything.
- Do not use `screencapture` (no permission). Visual checks are the owner's, in the Debug build, at the end (Task 7).

## Review Focus

The inputs and conditions most likely to bite a person that no single task's happy path exercises. Each line names a test or check in the task that owns the code.

1. **Two cards both thinking they hold focus.** Focus in card B must unfocus card A's pane, or Ready for Response, cursors and typing go wrong. Pinned by `onlyTheActiveCardsFocusedPaneHasFocus` (Task 2) and Spike check S1 (Task 0).
2. **A zoom that resizes the grid.** After a settle at 25% or 200%, columns and rows must equal the 100% values (no SIGWINCH to the shell) and clicks must land on the clicked cell. Pinned by `aSettledZoomRendersAtTheScreensScaleTimesTheZoom` (Task 1), Spike S4/S5 (Task 0), hand check H5 (Task 7).
3. **The last pane of a card exits** (the shell's `exit`, or Close). The card must go, Undo must bring it back where it was, and the canvas must not keep a dead view. Pinned by `closedCardsAreKeptForUndoButNotForever` (Task 2) and hand check H3.
4. **Restart to Update with the canvas hidden.** Its terminals must come back attached to their tmux sessions, the canvas still hidden, and no "reopen sessions?" prompt for them. Pinned by `theSavedCanvasComesBackAsItWas` (Task 1), `theCanvasNeverOverwritesTheQuickTerminalsState` (Task 5) and hand check H8.
5. **Stable builds.** No canvas menu items, no shortcut, nothing restored. Pinned by `theCanvasIsOnlyInTheBeta` (Task 1), `stableHasNoCanvasItems` (Task 2) and check H10.

---

## File Structure

| File | Responsibility |
|---|---|
| `Features/Canvas/CanvasModel.swift` | Pure: card frames back to front, placement, clamping, resizing, handles, hit tests, culling, neighbors, fit; `CanvasZoom`, `CanvasGrid`, `CanvasWaits`, `CardStatus`, `CanvasSaved`. |
| `Features/Canvas/CanvasSurface.swift` | `CanvasScrollView` (magnifying, no scrollers), `CanvasDocumentView`, `CanvasGridView`, `CanvasSurfaceView`, `CanvasSurface` (representable). |
| `Features/Canvas/CanvasController.swift` | The window, the cards, focus routing, culling, zoom actions, Move to Window. |
| `Features/Canvas/CanvasController+Navigate.swift` | Zoom settle hook calls, Jump, ⌃⌥⌘ + arrows (Task 4). |
| `Features/Canvas/CanvasController+Restore.swift` | Saving and restoring the canvas (Task 5). |
| `Features/Canvas/CanvasRestorableState.swift` | `TerminalRestorable` wrapper with its own keys (Task 5). |
| `Features/Canvas/CardController.swift` | One card: a `BaseTerminalController` living in the canvas window. |
| `Features/Canvas/CardView.swift` | Card view, `CardTerminal`, `CardEdgeHandle`, `CardTraceHost`, `PassthroughHostingView`. |
| `Features/Canvas/CardHeaderView.swift` | AppKit header (drag, double-click, menu, close) and SwiftUI `CardHeaderContent`, `CardStatusLabel`. |
| `Features/Canvas/CardTile.swift` | The zoomed-out status tile. |
| `Features/Canvas/CanvasTitleAccessory.swift` | Title-bar Jump button and project pill. |
| `Features/Canvas/CanvasMenu.swift` | The Window-menu items and their validation. |
| `Features/Canvas/CanvasLookup.swift` | `BaseTerminalController.everyController`, `Ghostty.SurfaceView.terminalController` (Task 3). |
| `Features/Channel/LosttyChannel.swift` | `hasCanvas`. |
| `Features/Terminal/BaseTerminalController.swift` | `applyTitleToWindow` becomes overridable; split-drop search sees cards. |
| `Ghostty/Surface View/SurfaceView_AppKit.swift` | `canvasZoomDidSettle(_:)` hook; focus-follows-mouse lookup. |
| `Features/Terminal/TerminalController.swift` | `moveToCanvas()` (Task 6). |
| `App/macOS/AppDelegate.swift` (+ `+Ghostty.swift`) | Menu install, ⌘N on the canvas, lookups, quit, restore. |

---

## Task 0: Spike — go / no-go

Throwaway. It answers four questions before anything real is built: can several `BaseTerminalController`s share one window (focus, responder chain, split notifications); does the scroll view's magnification reach `convertToBacking` (picks the zoom hook's variant in Task 4); does a settled zoom keep the grid and land clicks right; and what does it cost.

**Files:**
- Create (on branch `canvas-spike` only): `macos/Sources/Features/Canvas/CanvasSpike.swift`
- Modify (on `canvas-spike` only): `macos/Sources/App/macOS/AppDelegate.swift` (the `#if DEBUG` block)
- Create (on `canvas`): `docs/superpowers/specs/2026-10-18-lostty-canvas-spike.md` (results)

- [ ] **Step 1: Branch off for the throwaway code**

```bash
cd /Users/lawliang/projectrepos/lostty/.claude/worktrees/canvas
git switch -c canvas-spike
```

- [ ] **Step 2: Write the spike**

Create `macos/Sources/Features/Canvas/CanvasSpike.swift`:

```swift
#if os(macOS) && DEBUG
import AppKit
import Combine
import GhosttyKit
import SwiftUI

/// THROWAWAY (branch canvas-spike, never merged). Launch the Debug build
/// with LOSTTY_CANVAS_SPIKE=checks or =flood; results go to
/// $TMPDIR/canvas-spike.log.
@MainActor
final class CanvasSpike: NSObject, NSWindowDelegate {
    static var shared: CanvasSpike?
    static let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-spike.log")

    let ghostty: Ghostty.App
    let window: NSWindow
    let scroll = NSScrollView()
    let document = SpikeDocument(frame: NSRect(x: 0, y: 0, width: 20_000, height: 20_000))
    var cards: [SpikeCard] = []
    var views: [ObjectIdentifier: NSView] = [:]
    private var monitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    static func start(_ ghostty: Ghostty.App, mode: String) {
        try? FileManager.default.removeItem(at: logURL)
        let spike = CanvasSpike(ghostty)
        shared = spike
        spike.log("start mode=\(mode) backing=\(spike.window.backingScaleFactor)")
        if mode == "flood" { spike.flood() } else { spike.checks() }
    }

    init(_ ghostty: Ghostty.App) {
        self.ghostty = ghostty
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Canvas Spike"
        window.isReleasedWhenClosed = false
        window.delegate = self
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 2
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.wantsLayer = true
        scroll.documentView = document
        window.contentView = scroll
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.publisher(for: \.firstResponder)
            .sink { [weak self] responder in self?.firstResponderChanged(responder) }
            .store(in: &cancellables)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .magnify {
                scroll.magnify(with: event)
                return nil
            }
            if event.modifierFlags.contains(.option) {
                scroll.scrollWheel(with: event)
                return nil
            }
            return event
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(didEndMagnify), name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
    }

    func log(_ line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: Self.logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: Self.logURL)
        }
    }

    @discardableResult
    func addCard(at origin: CGPoint, size: CGSize, config: Ghostty.SurfaceConfiguration? = nil) -> SpikeCard {
        let card = SpikeCard(ghostty, spike: self, config: config)
        let view = NSView(frame: CGRect(origin: origin, size: size))
        view.wantsLayer = true
        let host = NSHostingView(rootView: TerminalView(ghostty: ghostty, viewModel: card, delegate: card))
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
        document.addSubview(view)
        card.nextResponder = document
        view.nextResponder = card
        cards.append(card)
        views[ObjectIdentifier(card)] = view
        return card
    }

    func show(_ rect: CGRect) {
        scroll.magnify(toFit: rect)
    }

    private func firstResponderChanged(_ responder: NSResponder?) {
        guard let surface = responder as? Ghostty.SurfaceView,
              let card = cards.first(where: { $0.surfaceTree.contains(surface) }) else { return }
        card.focusedSurfaceDidChange(to: surface)
        log("S1 firstResponder -> card\(cards.firstIndex { $0 === card } ?? -1)")
    }

    @objc private func didEndMagnify() {
        log("live magnify ended at \(scroll.magnification)")
        rerender()
    }

    /// The settle experiment: re-run the pane's backing-properties code at
    /// the current magnification, with the layer scaled to match.
    func rerender() {
        for card in cards {
            for pane in card.surfaceTree {
                pane.viewDidChangeBackingProperties()
                let backing = pane.convertToBacking(NSRect(x: 0, y: 0, width: 1, height: 1)).width
                pane.layer?.contentsScale = backing
            }
        }
    }

    func size(_ pane: Ghostty.SurfaceView) -> String {
        guard let surface = pane.surface else { return "no surface" }
        let s = ghostty_surface_size(surface)
        return "cols=\(s.columns) rows=\(s.rows) cell=\(s.cell_width_px)x\(s.cell_height_px) px=\(s.width_px)x\(s.height_px)"
    }

    // MARK: checks

    func checks() {
        let one = addCard(at: CGPoint(x: 9000, y: 9000), size: CGSize(width: 720, height: 464))
        let two = addCard(at: CGPoint(x: 9800, y: 9000), size: CGSize(width: 720, height: 464))
        show(CGRect(x: 8950, y: 8950, width: 1600, height: 600))
        after(3) { [self] in
            guard let paneOne = one.surfaceTree.first, let paneTwo = two.surfaceTree.first else {
                log("FAIL no panes"); return
            }
            // S1: focus routing between cards.
            window.makeFirstResponder(paneTwo)
            after(0.5) { [self] in
                log("S1 two.focused=\(two.focusedSurface === paneTwo) one.focused=\(one.focusedSurface === paneOne)")
                // S2: menu actions reach a card through the responder chain.
                window.makeFirstResponder(paneOne)
                let handled = NSApp.sendAction(#selector(BaseTerminalController.splitRight(_:)), to: nil, from: nil)
                after(1) { [self] in
                    log("S2 sendAction handled=\(handled) one.count=\(one.surfaceTree.count) two.count=\(two.surfaceTree.count) (want 2, 1)")
                    // S3: the core's split notification reaches only the pane's card.
                    if let surface = paneTwo.surface { ghostty.split(surface: surface, direction: GHOSTTY_SPLIT_DIRECTION_DOWN) }
                    after(1) { [self] in
                        log("S3 one.count=\(one.surfaceTree.count) two.count=\(two.surfaceTree.count) (want 2, 2)")
                        zoomChecks(paneOne, one: one, two: two)
                    }
                }
            }
        }
    }

    private func zoomChecks(_ pane: Ghostty.SurfaceView, one: SpikeCard, two: SpikeCard) {
        log("S4 at 1.0: \(size(pane))")
        guard let view = views[ObjectIdentifier(one)] else { return }
        scroll.setMagnification(2, centeredAt: NSPoint(x: view.frame.midX, y: view.frame.midY))
        after(0.5) { [self] in
            let backing = pane.convertToBacking(NSRect(x: 0, y: 0, width: 100, height: 100)).width
            log("S4 at 2.0 before re-render: convertToBacking(100pt)=\(backing) (A: \(200 * window.backingScaleFactor), B: \(100 * window.backingScaleFactor)) \(size(pane))")
            rerender()
            after(0.5) { [self] in
                log("S4 at 2.0 after re-render: \(size(pane)) contentsScale=\(pane.layer?.contentsScale ?? 0)")
                // S5: a click at the pane's middle lands on the pane, at its middle.
                let middle = NSPoint(x: pane.bounds.midX, y: pane.bounds.midY)
                let inWindow = pane.convert(middle, to: nil)
                let hit = window.contentView?.hitTest(window.contentView?.convert(inWindow, from: nil) ?? .zero)
                let back = pane.convert(inWindow, from: nil)
                log("S5 hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil") isPaneOrInside=\(hit.map { $0 === pane || $0.isDescendant(of: pane) } ?? false) roundTrip=\(back) want=\(middle)")
                // S9: bringing a card forward keeps keyboard focus.
                window.makeFirstResponder(pane)
                document.sortSubviews({ a, b, _ in a.frame.minX < b.frame.minX ? .orderedDescending : .orderedAscending }, context: nil)
                after(0.5) { [self] in
                    log("S9 firstResponder still pane=\(window.firstResponder === pane)")
                    scroll.magnification = 0.5
                    rerender()
                    after(0.5) { [self] in
                        log("S4 at 0.5 after re-render: \(size(pane))")
                        moveCheck(two)
                    }
                }
            }
        }
    }

    /// S10: a card's panes move to a normal window and keep running.
    private func moveCheck(_ card: SpikeCard) {
        let tree = card.surfaceTree
        card.surfaceTree = .init()
        views.removeValue(forKey: ObjectIdentifier(card))?.removeFromSuperview()
        cards.removeAll { $0 === card }
        _ = TerminalController.newWindow(ghostty, tree: tree)
        after(1.5) { [self] in
            for pane in tree {
                log("S10 pane window=\(pane.window.map { String(describing: type(of: $0)) } ?? "nil") alive=\(pane.surface != nil)")
            }
            log("checks done; the spike window stays open for a look")
        }
    }

    // MARK: flood

    /// Eight busy panes as cards, then hidden, then as splits in a window:
    /// the process's CPU over ten seconds each.
    func flood() {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-flood.sh")
        try? "while :; do date; sleep 0.02; done\n".write(to: script, atomically: true, encoding: .utf8)
        var config = Ghostty.SurfaceConfiguration()
        config.command = "/bin/zsh \(script.path)"
        let size = CGSize(width: 350, height: 450)
        for row in 0..<2 {
            for column in 0..<4 {
                addCard(at: CGPoint(x: 5000 + CGFloat(column) * size.width, y: 5000 + CGFloat(row) * size.height),
                        size: size, config: config)
            }
        }
        show(CGRect(x: 5000, y: 5000, width: 1400, height: 900))
        after(4) { [self] in
            measure("F1 eight live cards") { [self] in
                for card in cards {
                    for pane in card.surfaceTree { if let s = pane.surface { ghostty_surface_set_occlusion(s, false) } }
                }
                scroll.contentView.scroll(to: NSPoint(x: 15_000, y: 15_000))
                measure("F2 eight cards occluded and out of view") { [self] in
                    for card in cards { card.surfaceTree = .init() }
                    document.subviews.forEach { $0.removeFromSuperview() }
                    cards = []
                    window.orderOut(nil)
                    floodWindow(config)
                }
            }
        }
    }

    private func floodWindow(_ config: Ghostty.SurfaceConfiguration) {
        guard let app = ghostty.app else { return }
        let panes = (0..<8).map { _ in Ghostty.SurfaceView(app, baseConfig: config) }
        var tree = SplitTree<Ghostty.SurfaceView>(view: panes[0])
        for i in 1..<4 { tree = (try? tree.inserting(view: panes[i], at: panes[i - 1], direction: .right)) ?? tree }
        for i in 0..<4 { tree = (try? tree.inserting(view: panes[i + 4], at: panes[i], direction: .down)) ?? tree }
        let controller = TerminalController.newWindow(ghostty, tree: tree)
        after(1) { controller.window?.setContentSize(NSSize(width: 1400, height: 900)) }
        after(4) { [self] in
            measure("F3 eight splits in one window") { [self] in
                controller.surfaceTree = .init()
                log("flood done")
            }
        }
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private func measure(_ name: String, then next: @escaping () -> Void) {
        let start = Self.cpuSeconds()
        after(10) { [self] in
            log("\(name): cpu=\(String(format: "%.1f", (Self.cpuSeconds() - start) * 10))%")
            next()
        }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

final class SpikeDocument: NSView {
    override var isFlipped: Bool { true }
}

/// A card: a window's controller with the spike's window as its own.
final class SpikeCard: BaseTerminalController {
    weak var spike: CanvasSpike?

    init(_ ghostty: Ghostty.App, spike: CanvasSpike, config: Ghostty.SurfaceConfiguration?) {
        self.spike = spike
        super.init(ghostty, baseConfig: config)
        focusedSurface = surfaceTree.first
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var window: NSWindow? {
        get { spike?.window }
        set {}
    }

    override func focusedSurfaceDidChange(to surface: Ghostty.SurfaceView?) {
        guard let surface, surfaceTree.contains(surface) else { return }
        super.focusedSurfaceDidChange(to: surface)
    }

    override func cellSizeDidChange(to: NSSize) {}
}
#endif
```

- [ ] **Step 3: Start it from the Debug build's launch environment**

In `macos/Sources/App/macOS/AppDelegate.swift`, inside the existing `#if DEBUG` block in `applicationDidFinishLaunching` (the one that adds "Preview Claude Trace"), add at its end:

```swift
        // THROWAWAY canvas spike (branch canvas-spike).
        if let mode = ProcessInfo.processInfo.environment["LOSTTY_CANVAS_SPIKE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { CanvasSpike.start(self.ghostty, mode: mode) }
        }
```

- [ ] **Step 4: Build**

Run: `macos/build.nu --configuration Debug`
Expected: `** BUILD SUCCEEDED **`. If `viewDidChangeBackingProperties` can't be called from outside the class, it is an `override func` with internal access and can be; fix any other compile error before going on.

- [ ] **Step 5: Run the checks**

```bash
rm -f "$TMPDIR/canvas-spike.log"
open -n --env LOSTTY_CANVAS_SPIKE=checks macos/build/Debug/Lostty.app
```

Wait about 15 seconds, then `cat "$TMPDIR/canvas-spike.log"`. Pass criteria:

| Check | Pass |
|---|---|
| S1 | `two.focused=true one.focused=true` and `S1 firstResponder -> card1` logged (the KVO route works) |
| S2 | `handled=true one.count=2 two.count=1` |
| S3 | `one.count=2 two.count=2` |
| S4 | cols and rows identical at 1.0, 2.0-after and 0.5-after; cell px at 2.0 is twice the 1.0 value; note which of A or B `convertToBacking` matched |
| S5 | `isPaneOrInside=true` and `roundTrip` equals `want` |
| S9 | `firstResponder still pane=true` |
| S10 | each pane `window=TerminalWindow`-family class and `alive=true` |

Leave the spike window open; quit the Debug app later (Step 7).

- [ ] **Step 6: Run the flood**

Quit the Debug app first (Step 7's command), then:

```bash
rm -f "$TMPDIR/canvas-spike.log"
open -n --env LOSTTY_CANVAS_SPIKE=flood macos/build/Debug/Lostty.app
```

Wait about 50 seconds, then read the log. Pass: F1 ≤ 1.2 × F3, and F2 ≤ 0.3 × F1. (CPU only; GPU is the owner's look in Activity Monitor if they want it.)

- [ ] **Step 7: Quit the Debug app**

```bash
osascript -e 'tell application "/Users/lawliang/projectrepos/lostty/.claude/worktrees/canvas/macos/build/Debug/Lostty.app" to quit'
```

If a "Quit Lostty?" alert appears it is the Debug app's, not the installed one's; answer it in the Debug app only.

- [ ] **Step 8: Record the results on `canvas` and drop the spike branch's code**

```bash
git switch canvas
```

Write `docs/superpowers/specs/2026-10-18-lostty-canvas-spike.md` with: the log of both runs verbatim, a pass/fail line per check, **the zoom variant (A or B)** from S4, and the CPU figures. Commit only that file:

```bash
git add docs/superpowers/specs/2026-10-18-lostty-canvas-spike.md
git commit -m "Canvas: spike results (go/no-go)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Keep branch `canvas-spike` (unmerged) until the owner decides; never merge it.

- [ ] **Step 9: STOP — the owner's call**

Report each check's result to the owner and offer the spike for a look in the Debug build (launch it again with `LOSTTY_CANVAS_SPIKE=checks`, pinch, read the text at 200% and 50%). Fallbacks, decided with the owner:
- S4 fails crisp re-render: re-render only at fixed zoom steps (50%, 75%, 100%, 150%) and snap pinches to them on settle.
- S1 fails (no KVO): route focus from `CardController.focusedSurfaceDidChange` alone (TerminalView's focused value) and re-run S1.
- S2 fails: the canvas forwards menu actions to `focusedCard` with `forwardingTarget(for:)` on `CanvasController`.
- F1 > 1.2 × F3: stop and discuss before Task 1.

Do not start Task 1 without the owner's go.

---

## Task 1: Beta flag and the canvas model

**Files:**
- Modify: `macos/Sources/Features/Channel/LosttyChannel.swift`
- Modify: `macos/Tests/Channel/LosttyChannelTests.swift`
- Create: `macos/Sources/Features/Canvas/CanvasModel.swift`
- Test: `macos/Tests/Canvas/CanvasModelTests.swift`

**Interfaces:**
- Produces: `LosttyChannel.hasCanvas: Bool`; `CanvasModel` (`Card`, `Edges`, `Direction`, statics `size`, `middle`, `newCardSize`, `minimumCardSize`, `nudge`, `fitMargin`, `handleThickness`, `handleCorner`, `handleEdges`; `cards`, `card(_:)`, `add(_:frame:)`, `remove(_:)`, `bringToFront(_:)`, `setFrame(_:of:)`, `card(at:)`, `placement(size:in:)`, `clamped(_:)`, `resized(_:edges:by:)`, `handleFrame(for:in:)`, `fitRect`, `cardsInView(_:)`, `neighbor(of:_:)`); `CanvasZoom` (`minimum`, `maximum`, `tilesBelow`, `settle`, `clamped(_:)`, `showsTiles(at:)`, `rect(centeredOn:zoom:viewport:)`, `contentScale(backing:zoom:)`); `CanvasGrid` (`spacing`, `minimumGap`, `gap(zoom:)`, `firstDot(origin:zoom:)`); `CanvasWaits` (`update(awaiting:now:)`, `order`, `next(after:among:)`); `CardStatus` (`.waiting`, `.working`, `.ready`, `title`, `of(panes:awaiting:phases:known:lastActivity:now:)`); `CanvasSaved<Tree: Codable>` (`visible`, `center`, `zoom`, `cards: [Card(frame, tree, focused)]`).

- [ ] **Step 1: Write the failing tests**

Append to `macos/Tests/Channel/LosttyChannelTests.swift`, inside `struct LosttyChannelTests`:

```swift
    @Test func theCanvasIsOnlyInTheBeta() {
        #expect(LosttyChannel.beta.hasCanvas)
        #expect(!LosttyChannel.stable.hasCanvas)
    }
```

Create `macos/Tests/Canvas/CanvasModelTests.swift`:

```swift
#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

struct CanvasModelTests {
    private let a = UUID(), b = UUID(), c = UUID()
    private let visible = CGRect(x: 50_000, y: 50_000, width: 1200, height: 800)

    private func model(_ frames: [(UUID, CGRect)]) -> CanvasModel {
        var model = CanvasModel()
        for (id, frame) in frames { model.add(id, frame: frame) }
        return model
    }

    @Test func aNewCardGoesInTheMiddleOfTheView() {
        #expect(CanvasModel().placement(in: visible) == CGRect(x: 50_240, y: 50_180, width: 720, height: 440))
    }

    @Test func aNewCardStepsOffAnotherOnesCorner() {
        let first = CanvasModel().placement(in: visible)
        let model = model([(a, first), (b, first.offsetBy(dx: 32, dy: 32))])
        #expect(model.placement(in: visible).origin == CGPoint(x: first.minX + 64, y: first.minY + 64))
    }

    @Test func cardsStayAtLeastTheMinimumAndInsideTheDocument() {
        #expect(CanvasModel.clamped(CGRect(x: -50, y: 10, width: 100, height: 100)) == CGRect(x: 0, y: 10, width: 320, height: 200))
        let far = CanvasModel.clamped(CGRect(x: 99_900, y: 99_950, width: 720, height: 440))
        #expect(far.maxX == CanvasModel.size && far.maxY == CanvasModel.size)
    }

    @Test func theLastCardIsOnTopForClicksAndBringingForwardMovesIt() {
        var model = model([(a, CGRect(x: 0, y: 0, width: 400, height: 300)), (b, CGRect(x: 100, y: 100, width: 400, height: 300))])
        #expect(model.card(at: CGPoint(x: 150, y: 150)) == b)
        #expect(model.card(at: CGPoint(x: 50, y: 50)) == a)
        #expect(model.card(at: CGPoint(x: 900, y: 900)) == nil)
        model.bringToFront(a)
        #expect(model.cards.map(\.id) == [b, a])
        #expect(model.card(at: CGPoint(x: 150, y: 150)) == a)
        model.remove(a)
        #expect(model.cards.map(\.id) == [b])
    }

    @Test func resizingStopsAtTheMinimumWithoutPushingTheCard() {
        let frame = CGRect(x: 1000, y: 1000, width: 720, height: 440)
        #expect(CanvasModel.resized(frame, edges: .right, by: CGSize(width: 80, height: 0)) == CGRect(x: 1000, y: 1000, width: 800, height: 440))
        #expect(CanvasModel.resized(frame, edges: [.left, .top], by: CGSize(width: 1000, height: 1000)) == CGRect(x: 1400, y: 1240, width: 320, height: 200))
        #expect(CanvasModel.resized(frame, edges: .bottom, by: CGSize(width: 50, height: -1000)) == CGRect(x: 1000, y: 1000, width: 720, height: 200))
    }

    @Test func resizeHandlesLineTheEdgesAndCorners() {
        let bounds = CGRect(x: 0, y: 0, width: 720, height: 440)
        #expect(CanvasModel.handleFrame(for: .left, in: bounds) == CGRect(x: 0, y: 14, width: 6, height: 412))
        #expect(CanvasModel.handleFrame(for: .top, in: bounds) == CGRect(x: 14, y: 0, width: 692, height: 6))
        #expect(CanvasModel.handleFrame(for: [.right, .bottom], in: bounds) == CGRect(x: 706, y: 426, width: 14, height: 14))
        #expect(CanvasModel.handleEdges.count == 8)
    }

    @Test func zoomingToFitShowsEveryCardWithAMargin() {
        #expect(CanvasModel().fitRect == nil)
        let model = model([(a, CGRect(x: 1000, y: 1000, width: 400, height: 300)), (b, CGRect(x: 2000, y: 1500, width: 400, height: 300))])
        #expect(model.fitRect == CGRect(x: 960, y: 960, width: 1480, height: 880))
    }

    @Test func onlyCardsNearTheViewDrawLive() {
        let view = CGRect(x: 10_000, y: 10_000, width: 1000, height: 800)
        let model = model([
            (a, CGRect(x: 10_100, y: 10_100, width: 400, height: 300)),
            // Within half a new card (360) of the view's right edge.
            (b, CGRect(x: 11_200, y: 10_100, width: 400, height: 300)),
            (c, CGRect(x: 13_000, y: 10_100, width: 400, height: 300)),
        ])
        #expect(model.cardsInView(view) == [a, b])
    }

    @Test func neighborsAreTheNearestCardThatWay() {
        let model = model([
            (a, CGRect(x: 1000, y: 1000, width: 400, height: 300)),
            (b, CGRect(x: 1600, y: 1050, width: 400, height: 300)),
            (c, CGRect(x: 1050, y: 2000, width: 400, height: 300)),
        ])
        #expect(model.neighbor(of: a, .right) == b)
        #expect(model.neighbor(of: a, .down) == c)
        #expect(model.neighbor(of: a, .left) == nil)
        #expect(model.neighbor(of: b, .left) == a)
        #expect(model.neighbor(of: c, .up) == a)
    }
}

struct CanvasZoomTests {
    @Test func zoomStaysBetweenAQuarterAndTwice() {
        #expect(CanvasZoom.clamped(0.1) == 0.25)
        #expect(CanvasZoom.clamped(3) == 2)
        #expect(CanvasZoom.clamped(0.8) == 0.8)
    }

    @Test func cardsTurnToTilesBelowFortyFivePercent() {
        #expect(CanvasZoom.showsTiles(at: 0.44))
        #expect(!CanvasZoom.showsTiles(at: 0.45))
    }

    @Test func zoomingToACardShowsAViewportOfItsCenter() {
        let rect = CanvasZoom.rect(centeredOn: CGPoint(x: 1000, y: 800), zoom: 2, viewport: CGSize(width: 1200, height: 800))
        #expect(rect == CGRect(x: 700, y: 600, width: 600, height: 400))
    }

    @Test func aSettledZoomRendersAtTheScreensScaleTimesTheZoom() {
        // Pixels per point follow the zoom; a pane's points don't, so its grid never resizes.
        #expect(CanvasZoom.contentScale(backing: 2, zoom: 2) == 4)
        #expect(CanvasZoom.contentScale(backing: 2, zoom: 0.5) == 1)
        #expect(CanvasZoom.contentScale(backing: 1, zoom: 5) == 2)
    }

    @Test func gridDotsStayOnTheDocumentAsItPans() {
        #expect(CanvasGrid.firstDot(origin: .zero, zoom: 1) == .zero)
        #expect(CanvasGrid.firstDot(origin: CGPoint(x: 10, y: 30), zoom: 1) == CGPoint(x: 14, y: 18))
    }

    @Test func gridDotsThinOutWhenZoomedFarOut() {
        #expect(CanvasGrid.gap(zoom: 1) == 24)
        #expect(CanvasGrid.gap(zoom: 0.25) == 12)
        #expect(CanvasGrid.firstDot(origin: CGPoint(x: 100, y: 0), zoom: 0.25) == CGPoint(x: 11, y: 0))
    }
}

struct CanvasWaitsTests {
    private let a = UUID(), b = UUID(), c = UUID()
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test func jumpGoesOldestWaitFirstAndWrapsRound() {
        var waits = CanvasWaits()
        waits.update(awaiting: [b], now: t0)
        waits.update(awaiting: [b, a], now: t0 + 5)
        waits.update(awaiting: [b, a, c], now: t0 + 9)
        let panes: Set<UUID> = [a, b, c]
        #expect(waits.order == [b, a, c])
        #expect(waits.next(after: nil, among: panes) == b)
        #expect(waits.next(after: b, among: panes) == a)
        #expect(waits.next(after: c, among: panes) == b)
    }

    @Test func aPaneThatStopsWaitingLeavesTheOrderAndComesBackLast() {
        var waits = CanvasWaits()
        waits.update(awaiting: [a], now: t0)
        waits.update(awaiting: [a, b], now: t0 + 1)
        waits.update(awaiting: [b], now: t0 + 2)
        #expect(waits.order == [b])
        waits.update(awaiting: [b, a], now: t0 + 3)
        #expect(waits.order == [b, a])
    }

    @Test func nothingWaitingOnTheCanvasMeansNoJump() {
        var waits = CanvasWaits()
        #expect(waits.next(after: nil, among: [a]) == nil)
        // A pane waiting in a normal window isn't the canvas's.
        waits.update(awaiting: [c], now: t0)
        #expect(waits.next(after: nil, among: [a, b]) == nil)
    }
}

struct CardStatusTests {
    private let a = UUID(), b = UUID()
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    private func status(
        awaiting: Set<UUID> = [], working: Set<UUID> = [], known: Set<UUID> = [], used: [UUID: Date] = [:]
    ) -> CardStatus? {
        let phases = Dictionary(uniqueKeysWithValues: working.map { ($0, TracePhase.racing(since: now)) })
        return CardStatus.of(panes: [a, b], awaiting: awaiting, phases: phases, known: known, lastActivity: used, now: now)
    }

    @Test func theMostUrgentPaneSpeaksForTheCard() {
        #expect(status(awaiting: [a], working: [b]) == .waiting)
        #expect(status(working: [b], known: [a], used: [a: now]) == .working)
        #expect(status(known: [a], used: [a: now]) == .ready)
        #expect(CardStatus.allCases.map(\.title) == ["Waiting", "Working", "Ready"])
    }

    @Test func idleOrUnknownPanesShowNothing() {
        #expect(status() == nil)
        #expect(status(known: [a], used: [a: now - SessionLabel.idleAfter - 1]) == nil)
        // A pane in another card or window doesn't count.
        #expect(CardStatus.of(panes: [a], awaiting: [b], phases: [:], known: [], lastActivity: [:], now: now) == nil)
    }
}

struct CanvasSavedTests {
    @Test func theSavedCanvasComesBackAsItWas() throws {
        let saved = CanvasSaved<String>(visible: false, center: CGPoint(x: 50_000, y: 50_400), zoom: 0.5, cards: [
            .init(frame: CGRect(x: 1, y: 2, width: 720, height: 440), tree: "back", focused: nil),
            .init(frame: CGRect(x: 30, y: 40, width: 320, height: 200), tree: "front", focused: "pane"),
        ])
        let data = try JSONEncoder().encode(saved)
        #expect(try JSONDecoder().decode(CanvasSaved<String>.self, from: data) == saved)
    }
}
#endif
```

- [ ] **Step 2: Run them to see them fail**

Run: `macos/skins-test.sh CanvasModelTests`
Expected: FAIL, the build stops with "cannot find 'CanvasModel' in scope" (and `hasCanvas` missing).

- [ ] **Step 3: Add the beta flag**

In `macos/Sources/Features/Channel/LosttyChannel.swift`, after `var hasBranches: Bool { isBeta }` (line 30), add (with a doc comment in the same style as its neighbors):

```swift
    /// The canvas: an infinite whiteboard window of terminal cards.
    var hasCanvas: Bool { isBeta }
```

- [ ] **Step 4: Write the model**

Create `macos/Sources/Features/Canvas/CanvasModel.swift`:

```swift
#if os(macOS)
import CoreGraphics
import Foundation
import LosttyRemote

/// The canvas's cards: frames in document points (the canvas scroll view's
/// flipped document, `size` square, y down), back to front. Pure
/// geometry; CanvasController applies it to views.
struct CanvasModel: Equatable {
    struct Card: Equatable, Identifiable {
        let id: UUID
        var frame: CGRect
    }

    /// The card edges a resize drags.
    struct Edges: OptionSet, Hashable {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    enum Direction: CaseIterable { case left, right, up, down }

    /// The document is this wide and tall; the first cards go in its middle.
    static let size: CGFloat = 100_000
    static let middle = CGPoint(x: size / 2, y: size / 2)
    /// A new card's size, and the smallest a card can be, at 100%.
    static let newCardSize = CGSize(width: 720, height: 440)
    static let minimumCardSize = CGSize(width: 320, height: 200)
    /// How far a new card steps down and right off another's corner.
    static let nudge: CGFloat = 32
    /// The room round the cards when zooming to fit them.
    static let fitMargin: CGFloat = 40
    /// The resize strips along a card's edges, and the squares at its corners.
    static let handleThickness: CGFloat = 6
    static let handleCorner: CGFloat = 14
    static let handleEdges: [Edges] = [
        .left, .right, .top, .bottom, [.left, .top], [.right, .top], [.left, .bottom], [.right, .bottom],
    ]

    /// Back to front: the last is drawn on top.
    private(set) var cards: [Card] = []

    func card(_ id: UUID) -> Card? {
        cards.first { $0.id == id }
    }

    mutating func add(_ id: UUID, frame: CGRect) {
        remove(id)
        cards.append(Card(id: id, frame: Self.clamped(frame)))
    }

    mutating func remove(_ id: UUID) {
        cards.removeAll { $0.id == id }
    }

    mutating func bringToFront(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards.append(cards.remove(at: index))
    }

    mutating func setFrame(_ frame: CGRect, of id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].frame = Self.clamped(frame)
    }

    /// The front-most card under `point`.
    func card(at point: CGPoint) -> UUID? {
        cards.last { $0.frame.contains(point) }?.id
    }

    /// Where a new card of `size` goes: centered in `visible`, stepped down
    /// and right while its top-left corner would sit on another card's.
    func placement(size: CGSize = newCardSize, in visible: CGRect) -> CGRect {
        var frame = CGRect(
            x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
            width: size.width, height: size.height)
        while cards.contains(where: { abs($0.frame.minX - frame.minX) < 1 && abs($0.frame.minY - frame.minY) < 1 }) {
            frame = frame.offsetBy(dx: Self.nudge, dy: Self.nudge)
        }
        return Self.clamped(frame)
    }

    /// `frame` at least the minimum size and inside the document.
    static func clamped(_ frame: CGRect) -> CGRect {
        let width = min(max(frame.width, minimumCardSize.width), size)
        let height = min(max(frame.height, minimumCardSize.height), size)
        return CGRect(
            x: min(max(frame.minX, 0), size - width), y: min(max(frame.minY, 0), size - height),
            width: width, height: height)
    }

    /// `frame` with `edges` dragged by `delta` (y down). A dragged edge stops
    /// at the minimum size instead of pushing the card along.
    static func resized(_ frame: CGRect, edges: Edges, by delta: CGSize) -> CGRect {
        var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
        if edges.contains(.left) { minX = min(minX + delta.width, maxX - minimumCardSize.width) }
        if edges.contains(.right) { maxX = max(maxX + delta.width, minX + minimumCardSize.width) }
        if edges.contains(.top) { minY = min(minY + delta.height, maxY - minimumCardSize.height) }
        if edges.contains(.bottom) { maxY = max(maxY + delta.height, minY + minimumCardSize.height) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Where the resize handle for `edges` sits in a card's `bounds` (y down):
    /// a strip along an edge between the corners, or a corner square.
    static func handleFrame(for edges: Edges, in bounds: CGRect) -> CGRect {
        let thick = handleThickness, corner = handleCorner
        let horizontal = edges.intersection([.left, .right]), vertical = edges.intersection([.top, .bottom])
        if !horizontal.isEmpty, !vertical.isEmpty {
            return CGRect(
                x: horizontal == .left ? 0 : bounds.width - corner, y: vertical == .top ? 0 : bounds.height - corner,
                width: corner, height: corner)
        }
        switch edges {
        case .left: return CGRect(x: 0, y: corner, width: thick, height: bounds.height - 2 * corner)
        case .right: return CGRect(x: bounds.width - thick, y: corner, width: thick, height: bounds.height - 2 * corner)
        case .top: return CGRect(x: corner, y: 0, width: bounds.width - 2 * corner, height: thick)
        default: return CGRect(x: corner, y: bounds.height - thick, width: bounds.width - 2 * corner, height: thick)
        }
    }

    /// What zooming to fit shows: every card, with a margin. nil with none.
    var fitRect: CGRect? {
        guard let first = cards.first?.frame else { return nil }
        return cards.dropFirst().reduce(first) { $0.union($1.frame) }
            .insetBy(dx: -Self.fitMargin, dy: -Self.fitMargin)
    }

    /// The cards to draw live: those touching `visible` grown by half a new
    /// card each way, so panning never shows a stale frame.
    func cardsInView(_ visible: CGRect) -> Set<UUID> {
        let near = visible.insetBy(dx: -Self.newCardSize.width / 2, dy: -Self.newCardSize.height / 2)
        return Set(cards.filter { $0.frame.intersects(near) }.map(\.id))
    }

    /// The nearest card whose center lies within 45° of `direction` from
    /// `id`'s center.
    func neighbor(of id: UUID, _ direction: Direction) -> UUID? {
        guard let from = card(id)?.frame else { return nil }
        var best: (id: UUID, distance: CGFloat)?
        for card in cards where card.id != id {
            let dx = card.frame.midX - from.midX, dy = card.frame.midY - from.midY
            let (along, across): (CGFloat, CGFloat) = switch direction {
            case .left: (-dx, dy)
            case .right: (dx, dy)
            case .up: (-dy, dx)
            case .down: (dy, dx)
            }
            guard along > 0, abs(across) <= along else { continue }
            let distance = dx * dx + dy * dy
            if best.map({ distance < $0.distance }) ?? true { best = (card.id, distance) }
        }
        return best?.id
    }
}

/// The canvas's zoom: its limits, where cards turn into tiles, and what a
/// zoom shows.
enum CanvasZoom {
    static let minimum: CGFloat = 0.25
    static let maximum: CGFloat = 2
    /// Below this, cards show status tiles instead of their terminals.
    static let tilesBelow: CGFloat = 0.45
    /// No zoom change for this long and the terminals re-render at the new scale.
    static let settle: TimeInterval = 0.15

    static func clamped(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, minimum), maximum)
    }

    static func showsTiles(at zoom: CGFloat) -> Bool {
        zoom < tilesBelow
    }

    /// The document rect a `viewport` of screen points shows at `zoom`,
    /// centered on `center`.
    static func rect(centeredOn center: CGPoint, zoom: CGFloat, viewport: CGSize) -> CGRect {
        let zoom = clamped(zoom)
        let size = CGSize(width: viewport.width / zoom, height: viewport.height / zoom)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// A pane's pixels per point at `zoom` on a screen of `backing` scale:
    /// its content scale once a zoom settles. Its size in points doesn't
    /// change, so neither does its grid.
    static func contentScale(backing: CGFloat, zoom: CGFloat) -> CGFloat {
        backing * clamped(zoom)
    }
}

/// The dot grid behind the cards: a dot every `spacing` document points,
/// thinned out (doubled) until dots are `minimumGap` screen points apart.
enum CanvasGrid {
    static let spacing: CGFloat = 24
    static let minimumGap: CGFloat = 12

    /// The gap between dots on screen at `zoom`.
    static func gap(zoom: CGFloat) -> CGFloat {
        var gap = spacing * zoom
        while gap < minimumGap { gap *= 2 }
        return gap
    }

    /// Where the first dot sits on screen (the view's top-left at 0, 0) when
    /// the view shows the document from `origin` at `zoom`, so dots stay put
    /// on the document as it pans.
    static func firstDot(origin: CGPoint, zoom: CGFloat) -> CGPoint {
        let gap = gap(zoom: zoom)
        func first(_ value: CGFloat) -> CGFloat {
            let screen = value * zoom
            return (screen / gap).rounded(.up) * gap - screen
        }
        return CGPoint(x: first(origin.x), y: first(origin.y))
    }
}

/// The panes waiting on you (Ready for Response), oldest first, for Jump
/// to What Needs You.
struct CanvasWaits: Equatable {
    private(set) var since: [UUID: Date] = [:]

    /// Keeps when each waiting pane began waiting; forgets the rest, so a
    /// pane that waits again goes to the back.
    mutating func update(awaiting: Set<UUID>, now: Date) {
        since = since.filter { awaiting.contains($0.key) }
        for id in awaiting where since[id] == nil { since[id] = now }
    }

    /// Oldest first; panes that began together in a stable order.
    var order: [UUID] {
        since.sorted { ($0.value, $0.key.uuidString) < ($1.value, $1.key.uuidString) }.map(\.key)
    }

    /// The pane to jump to after `current`: the next waiting one of `panes`
    /// (the canvas's), round and round; the oldest when `current` isn't
    /// waiting.
    func next(after current: UUID?, among panes: Set<UUID>) -> UUID? {
        let waiting = order.filter(panes.contains)
        guard let first = waiting.first else { return nil }
        guard let current, let index = waiting.firstIndex(of: current) else { return first }
        return waiting[(index + 1) % waiting.count]
    }
}

/// A card's agent state in its header and tile: its most urgent pane's,
/// each pane judged as the phone's rows and the sidebar mascot judge it.
enum CardStatus: CaseIterable, Equatable {
    case waiting, working, ready

    var title: String {
        switch self {
        case .waiting: "Waiting"
        case .working: "Working"
        case .ready: "Ready"
        }
    }

    /// nil when no pane of `panes` waits, works, or was used lately.
    static func of(
        panes: [UUID], awaiting: Set<UUID>, phases: [UUID: TracePhase],
        known: Set<UUID>, lastActivity: [UUID: Date], now: Date
    ) -> CardStatus? {
        let states = panes.compactMap { id -> PaneState? in
            let waiting = awaiting.contains(id), working = phases[id] != nil
            guard waiting || working || known.contains(id) else { return nil }
            return PaneState(waiting: waiting, working: working, lastActivity: lastActivity[id], now: now)
        }
        if states.contains(.waiting) { return .waiting }
        if states.contains(.working) { return .working }
        if states.contains(.ready) { return .ready }
        return nil
    }
}

/// What the canvas keeps across Restart to Update and relaunches: whether
/// it's shown, the view, and each card back to front. Generic over the
/// split tree, so tests can save plain values.
struct CanvasSaved<Tree: Codable>: Codable {
    struct Card: Codable {
        var frame: CGRect
        var tree: Tree
        /// The card's focused pane, as a UUID string.
        var focused: String?
    }

    var visible: Bool
    var center: CGPoint
    var zoom: CGFloat
    var cards: [Card]
}

extension CanvasSaved: Equatable where Tree: Equatable {}
extension CanvasSaved.Card: Equatable where Tree: Equatable {}
#endif
```

- [ ] **Step 5: Run the tests**

Run: `macos/skins-test.sh CanvasModelTests && macos/skins-test.sh CanvasZoomTests && macos/skins-test.sh CanvasWaitsTests && macos/skins-test.sh CardStatusTests && macos/skins-test.sh CanvasSavedTests && macos/skins-test.sh LosttyChannelTests`
Expected: each prints `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Channel/LosttyChannel.swift macos/Tests/Channel/LosttyChannelTests.swift macos/Sources/Features/Canvas/CanvasModel.swift macos/Tests/Canvas/CanvasModelTests.swift
git commit -m "Canvas: beta flag and the canvas model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 2: The canvas window and its cards

The window with its grid, icon row and usage bar; cards that run their panes like windows; header drag, double-click, menu and close; edge resizing; bringing forward; focus routed from the window's first responder; culling (live, tile, hidden) with occlusion; Window Light round a card; Window → Canvas (⌃⌘K); ⌘N on the canvas makes a card.

**Files:**
- Create: `macos/Sources/Features/Canvas/CanvasSurface.swift`, `CanvasController.swift`, `CardController.swift`, `CardView.swift`, `CardHeaderView.swift`, `CardTile.swift`, `CanvasTitleAccessory.swift`, `CanvasMenu.swift` (all in `macos/Sources/Features/Canvas/`)
- Modify: `macos/Sources/Features/Terminal/BaseTerminalController.swift:880`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (menu install near line 363; `newWindow` at line 1122; `ghosttyNewWindow` at line 888)
- Test: `macos/Tests/Canvas/CanvasControllerTests.swift`

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces: `CanvasController.shared`, `.key`, `.allCards`, `show(_:freshCard:)`, `ghostty`, `model`, `cards`, `focusedCard`, `sidebar`, `scrollView`, `views`, `settledZoom`, `settleWork`, `waits`, `pendingView`, `newCard(baseConfig:)`, `addCard(tree:frame:focused:)`, `cardSize(for:)`, `card(holding:)`, `focus(_:)`, `cardDidFocus(_:)`, `setFrame(_:of:)`, `cardFrameDidSettle()`, `cardTreeDidChange(_:from:to:)`, `reveal(_:)`, `zoomToFit()`, `zoom(to:zoom:)`, `settleZoom()`, `updateVisibility()`, `moveToWindow(_:)`, `saveSoon()`, `retiredLimit`; `CardController` (`id`, `canvas`, `header`, `paneIsFocused(...)`, `isFocusedCard`, `closeCard()`); `CardView` (`headerHeight`, `cornerRadius`, `Mode`, `mode`, `isFocusedCard`, `stackIndex`, `zoomDidSettle(_:)`); `CanvasMenu.install(before:channel:)`, `CanvasMenu.shared`; `BaseTerminalController.applyTitleToWindow()` now overridable.

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/Canvas/CanvasControllerTests.swift`:

```swift
#if os(macOS)
import AppKit
import Testing
@testable import Lostty

struct CardFocusTests {
    @Test func onlyTheActiveCardsFocusedPaneHasFocus() {
        #expect(CardController.paneIsFocused(windowIsKey: true, cardIsFocused: true, paletteShowing: false, isFocusedPane: true))
        #expect(!CardController.paneIsFocused(windowIsKey: true, cardIsFocused: false, paletteShowing: false, isFocusedPane: true))
        #expect(!CardController.paneIsFocused(windowIsKey: false, cardIsFocused: true, paletteShowing: false, isFocusedPane: true))
        #expect(!CardController.paneIsFocused(windowIsKey: true, cardIsFocused: true, paletteShowing: true, isFocusedPane: true))
        #expect(!CardController.paneIsFocused(windowIsKey: true, cardIsFocused: true, paletteShowing: false, isFocusedPane: false))
    }

    @Test func closedCardsAreKeptForUndoButNotForever() {
        #expect(CanvasController.retiredLimit == 10)
    }
}

@MainActor
struct CanvasMenuTests {
    private func windowMenu() -> (NSMenu, NSMenuItem) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Minimize", action: nil, keyEquivalent: "m")
        let anchor = menu.addItem(withTitle: "Bring All to Front", action: nil, keyEquivalent: "")
        return (menu, anchor)
    }

    @Test func stableHasNoCanvasItems() {
        let (menu, anchor) = windowMenu()
        CanvasMenu.install(before: anchor, channel: .stable)
        #expect(menu.items.map(\.title) == ["Minimize", "Bring All to Front"])
    }

    @Test func theBetaOpensTheCanvasWithControlCommandK() throws {
        let (menu, anchor) = windowMenu()
        CanvasMenu.install(before: anchor, channel: .beta)
        let item = try #require(menu.items.first { $0.title == "Canvas" })
        #expect(item.keyEquivalent == "k")
        #expect(item.keyEquivalentModifierMask == [.control, .command])
        #expect(menu.items.last === anchor)
        #expect(menu.items[menu.items.count - 2].isSeparatorItem)
    }
}
#endif
```

- [ ] **Step 2: Run them to see them fail**

Run: `macos/skins-test.sh CardFocusTests`
Expected: FAIL to build: "cannot find 'CardController' in scope".

- [ ] **Step 3: Make the title hook overridable**

In `macos/Sources/Features/Terminal/BaseTerminalController.swift` line 880, change

```swift
    private func applyTitleToWindow() {
```

to

```swift
    /// Shows the title on the window. A canvas card overrides it, so only
    /// the focused card titles the shared canvas window.
    func applyTitleToWindow() {
```

Then check nothing else defines it: `grep -rn "func applyTitleToWindow" macos/Sources` must list only this line.

- [ ] **Step 4: Write the canvas surface**

Create `macos/Sources/Features/Canvas/CanvasSurface.swift`:

```swift
#if os(macOS)
import AppKit
import SwiftUI

/// The canvas's scroll view: two-finger scrolling over empty canvas pans
/// it, pinching zooms it 25%–200% (its clip view scales, so clicks still
/// land on the right cell), and it has no scrollers.
final class CanvasScrollView: NSScrollView {
    let document = CanvasDocumentView(frame: NSRect(x: 0, y: 0, width: CanvasModel.size, height: CanvasModel.size))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowsMagnification = true
        minMagnification = CanvasZoom.minimum
        maxMagnification = CanvasZoom.maximum
        hasHorizontalScroller = false
        hasVerticalScroller = false
        drawsBackground = false
        contentView.drawsBackground = false
        contentView.postsBoundsChangedNotifications = true
        wantsLayer = true
        documentView = document
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// The canvas itself: the cards are its subviews, framed in document
/// points, y down. Draws nothing.
final class CanvasDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// The faint dot grid behind the canvas, moving with it as it pans and
/// zooms: one cheap fill per frame.
final class CanvasGridView: NSView {
    weak var scrollView: NSScrollView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        guard let scrollView, let context = NSGraphicsContext.current?.cgContext else { return }
        let zoom = scrollView.magnification
        let gap = CanvasGrid.gap(zoom: zoom)
        let first = CanvasGrid.firstDot(origin: scrollView.contentView.bounds.origin, zoom: zoom)
        let dot: CGFloat = 1.5
        var rects: [CGRect] = []
        var y = first.y
        while y < bounds.height {
            var x = first.x
            while x < bounds.width {
                rects.append(CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
                x += gap
            }
            y += gap
        }
        context.setFillColor(NSColor.tertiaryLabelColor.withAlphaComponent(0.35).cgColor)
        context.fill(rects)
    }
}

/// The grid with the scroll view over it.
final class CanvasSurfaceView: NSView {
    let scrollView = CanvasScrollView(frame: .zero)
    private let grid = CanvasGridView(frame: .zero)

    init() {
        super.init(frame: .zero)
        grid.scrollView = scrollView
        addSubview(grid)
        addSubview(scrollView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(canvasMoved), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        grid.frame = bounds
        scrollView.frame = bounds
    }

    @objc private func canvasMoved() {
        grid.needsDisplay = true
    }
}

/// The canvas inside the window's SwiftUI layout (the icon row and usage
/// bar below it). SwiftUI never re-evaluates for a pan or zoom.
struct CanvasSurface: NSViewRepresentable {
    let view: CanvasSurfaceView

    func makeNSView(context: Context) -> CanvasSurfaceView { view }
    func updateNSView(_ nsView: CanvasSurfaceView, context: Context) {}
}
#endif
```

- [ ] **Step 5: Write the card controller**

Create `macos/Sources/Features/Canvas/CardController.swift`:

```swift
#if os(macOS)
import AppKit
import GhosttyKit

/// One card on the canvas: a split group run exactly as a window's panes
/// are (splits, closing, focus, zoom, undo, close confirmations), by the
/// same base controller. It has no window of its own: `window` is the
/// canvas's, whose delegate (CanvasController) passes on what a card needs
/// to hear, and the card sits in the responder chain under its view.
final class CardController: BaseTerminalController {
    let id = UUID()
    private(set) weak var canvas: CanvasController?
    /// The card's focused pane, for its header's pill and its light.
    let header = ExtensionSidebarModel()

    init(
        _ ghostty: Ghostty.App, canvas: CanvasController,
        tree: SplitTree<Ghostty.SurfaceView>? = nil, baseConfig: Ghostty.SurfaceConfiguration? = nil
    ) {
        self.canvas = canvas
        super.init(ghostty, baseConfig: baseConfig, surfaceTree: tree)
        // As in a new window, the first pane starts focused.
        focusedSurface = surfaceTree.first
        header.focusedSurfaceID = focusedSurface?.id
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The canvas window: close confirmations, key state and the title come
    /// from it. Setting it does nothing; a card owns no window.
    override var window: NSWindow? {
        get { canvas?.window }
        set {}
    }

    /// Whether a card's pane has keyboard focus: the canvas is key, it's the
    /// canvas's focused card, no command palette covers it, and it's the
    /// card's focused pane. At most one pane on the canvas passes.
    static func paneIsFocused(windowIsKey: Bool, cardIsFocused: Bool, paletteShowing: Bool, isFocusedPane: Bool) -> Bool {
        windowIsKey && cardIsFocused && !paletteShowing && isFocusedPane
    }

    var isFocusedCard: Bool { canvas?.focusedCard === self }

    override func syncFocusToSurfaceTree() {
        for surfaceView in surfaceTree {
            surfaceView.focusDidChange(Self.paneIsFocused(
                windowIsKey: window?.isKeyWindow ?? false, cardIsFocused: isFocusedCard,
                paletteShowing: commandPaletteIsShowing, isFocusedPane: surfaceView == focusedSurface))
        }
    }

    /// Every card's view hears the window's focused pane; a card takes only
    /// its own, and then it is the canvas's focused card.
    override func focusedSurfaceDidChange(to surface: Ghostty.SurfaceView?) {
        guard let surface, surfaceTree.contains(surface) else { return }
        super.focusedSurfaceDidChange(to: surface)
        header.focusedSurfaceID = surface.id
        canvas?.cardDidFocus(self)
    }

    /// Panes added or gone: the canvas keeps, retires or brings back the card.
    override func surfaceTreeDidChange(from: SplitTree<Ghostty.SurfaceView>, to: SplitTree<Ghostty.SurfaceView>) {
        super.surfaceTreeDidChange(from: from, to: to)
        canvas?.cardTreeDidChange(self, from: from, to: to)
    }

    /// Only the focused card titles the canvas window.
    override func applyTitleToWindow() {
        guard isFocusedCard else { return }
        super.applyTitleToWindow()
    }

    override func pwdDidChange(to: URL?) {
        guard isFocusedCard else { return }
        super.pwdDidChange(to: to)
    }

    /// Step resizing would size the whole canvas window to one card's cells.
    override func cellSizeDidChange(to: NSSize) {}

    /// Bringing a pane forward (a notification, Branches, Jump) shows its
    /// card first.
    override func focusSurface(_ view: Ghostty.SurfaceView) {
        if surfaceTree.contains(view) { canvas?.reveal(self) }
        super.focusSurface(view)
    }

    /// ⇧⌘W closes the card, not the canvas.
    override func closeWindow(_ sender: Any) {
        closeCard()
    }

    /// Every pane, asking first when one runs something, as closing a window
    /// does. Undo brings the card back.
    func closeCard() {
        guard let root = surfaceTree.root else { return }
        closeSurface(root, withConfirmation: surfaceTree.contains(where: { $0.needsConfirmQuit }))
    }
}
#endif
```

- [ ] **Step 6: Write the card view**

Create `macos/Sources/Features/Canvas/CardView.swift`:

```swift
#if os(macOS)
import AppKit
import GhosttyKit
import SwiftUI

/// A card on the canvas: its header, its panes (the window's own
/// TerminalView, so splits and Ready for Response come with it), resize
/// handles on its edges, its tile for zooming far out, and the Window Light
/// round it. Puts its card's controller in the responder chain, so menu
/// actions reach the card.
final class CardView: NSView {
    static let headerHeight: CGFloat = 24
    static let cornerRadius: CGFloat = 8

    /// Live: the terminals draw. Tile: a status tile instead (zoomed far
    /// out). Hidden: out of view or the canvas is; the terminals pause.
    enum Mode { case live, tile, hidden }

    let card: CardController
    private let header: CardHeaderView
    private let terminal: CardTerminalHost
    private let tile: NSHostingView<CardTile>
    private let trace: CardTraceHost
    private var handles: [CardEdgeHandle] = []
    /// Back-to-front position among the canvas's cards.
    var stackIndex = 0

    var mode: Mode = .live {
        didSet { if mode != oldValue { applyMode() } }
    }

    var isFocusedCard = false {
        didSet { needsDisplay = true }
    }

    init(card: CardController, canvas: CanvasController) {
        self.card = card
        header = CardHeaderView(card: card, canvas: canvas)
        terminal = CardTerminalHost(rootView: CardTerminal(card: card))
        terminal.card = card
        let open: () -> Void = { [weak canvas, weak card] in
            if let canvas, let card { canvas.zoom(to: card) }
        }
        tile = NSHostingView(rootView: CardTile(card: card, zoom: canvas.settledZoom, open: open))
        trace = CardTraceHost(card: card)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        addSubview(terminal)
        addSubview(tile)
        addSubview(header)
        addSubview(trace)
        for edges in CanvasModel.handleEdges {
            let handle = CardEdgeHandle(edges: edges, card: card, canvas: canvas)
            handles.append(handle)
            addSubview(handle)
        }
        tile.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    /// The focused card has an accent outline; the others a hairline.
    override func updateLayer() {
        layer?.borderColor = (isFocusedCard ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.borderWidth = isFocusedCard ? 1 : 0.5
    }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight)
        terminal.frame = NSRect(x: 0, y: Self.headerHeight, width: bounds.width, height: max(0, bounds.height - Self.headerHeight))
        tile.frame = bounds
        trace.frame = bounds
        for handle in handles { handle.frame = CanvasModel.handleFrame(for: handle.edges, in: bounds) }
    }

    /// The card's controller answers menu actions (Split Right, Close…) for
    /// its panes, as a window's controller does for a window's.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        card.nextResponder = superview
        nextResponder = card
    }

    /// The canvas's zoom settled: the tile keeps its text readable at it.
    func zoomDidSettle(_ zoom: CGFloat) {
        tile.rootView = CardTile(card: card, zoom: zoom, open: tile.rootView.open)
    }

    private func applyMode() {
        terminal.isHidden = mode != .live
        tile.isHidden = mode != .tile
        header.isHidden = mode == .tile
        trace.isLit = mode == .live
        // What a hidden window's panes get: no drawing until shown again.
        for view in card.surfaceTree {
            if let surface = view.surface { ghostty_surface_set_occlusion(surface, mode == .live) }
        }
    }
}

/// A card's panes: the window's terminal view without the icon row and
/// usage bar (the canvas has one for all its cards). The panes leave the
/// Window Light to the card.
struct CardTerminal: View {
    let card: CardController

    var body: some View {
        TerminalView(ghostty: card.ghostty, viewModel: card, delegate: card)
            .environment(\.hostsWindowTrace, true)
    }
}

/// Hosts a card's panes. SwiftUI misses its panes when the canvas is
/// zoomed (an ancestor is magnified): a click it keeps for itself that
/// falls inside a pane goes to the pane (spike check S5).
final class CardTerminalHost: NSHostingView<CardTerminal> {
    weak var card: CardController?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard hit === self, let card, let superview else { return hit }
        for pane in card.surfaceTree where !pane.isHiddenOrHasHiddenAncestor {
            if pane.bounds.contains(pane.convert(point, from: superview)) { return pane }
        }
        return hit
    }
}

/// A strip along a card's edge, or a square at its corner, that resizes
/// the card by dragging.
final class CardEdgeHandle: NSView {
    let edges: CanvasModel.Edges
    private let card: CardController
    private weak var canvas: CanvasController?
    private var start: (point: CGPoint, frame: CGRect)?

    init(edges: CanvasModel.Edges, card: CardController, canvas: CanvasController) {
        self.edges = edges
        self.card = card
        self.canvas = canvas
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func resetCursorRects() {
        let cursor: NSCursor = switch edges {
        case .left, .right: .resizeLeftRight
        case .top, .bottom: .resizeUpDown
        default: .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let frame = canvas?.model.card(card.id)?.frame, let point = documentPoint(event) else { return }
        start = (point, frame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let start, let point = documentPoint(event) else { return }
        let delta = CGSize(width: point.x - start.point.x, height: point.y - start.point.y)
        canvas.setFrame(CanvasModel.resized(start.frame, edges: edges, by: delta), of: card)
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        canvas?.cardFrameDidSettle()
    }

    /// Where `event` is on the canvas document, however zoomed.
    private func documentPoint(_ event: NSEvent) -> CGPoint? {
        enclosingScrollView?.documentView?.convert(event.locationInWindow, from: nil)
    }
}

/// The Window Light round a card: the website's light while Claude works
/// in one of its panes and Lostty → Claude Trace Style is Window Light
/// (Skin Traces stay on the panes' own edges). Only while the card draws
/// live; out of view it stops animating altogether.
final class CardTraceHost: NSView {
    private let card: CardController
    private let edge = WindowTraceEdge()
    private var host: NSHostingView<WindowTraceView>?

    var isLit = true {
        didSet { if isLit != oldValue { update() } }
    }

    init(card: CardController) {
        self.card = card
        super.init(frame: .zero)
        edge.cornerRadius = CardView.cornerRadius
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func update() {
        if isLit, host == nil {
            let host = NSHostingView(rootView: WindowTraceView(controller: card, sidebar: card.header, edge: edge))
            host.frame = bounds
            host.autoresizingMask = [.width, .height]
            addSubview(host)
            self.host = host
        } else if !isLit {
            host?.removeFromSuperview()
            host = nil
        }
    }
}

/// A hosting view that never takes clicks, so they reach the view under it.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
```

- [ ] **Step 7: Write the header**

Create `macos/Sources/Features/Canvas/CardHeaderView.swift`:

```swift
#if os(macOS)
import AppKit
import SwiftUI

/// A card's header: its project pill and agent state, and a close button.
/// Dragging it moves the card; double-clicking zooms to the card at 100%;
/// its menu moves the card to a window or closes it.
final class CardHeaderView: NSView {
    private let card: CardController
    private weak var canvas: CanvasController?
    private let content: PassthroughHostingView<CardHeaderContent>
    private let close = NSButton()
    private var start: (point: CGPoint, origin: CGPoint)?

    init(card: CardController, canvas: CanvasController) {
        self.card = card
        self.canvas = canvas
        content = PassthroughHostingView(rootView: CardHeaderContent(card: card))
        super.init(frame: .zero)
        wantsLayer = true
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Card")
        close.isBordered = false
        close.imageScaling = .scaleProportionallyDown
        close.target = self
        close.action = #selector(closeCard)
        close.toolTip = "Close Card"
        addSubview(content)
        addSubview(close)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func layout() {
        super.layout()
        content.frame = bounds
        close.frame = NSRect(x: bounds.width - 24, y: 4, width: 16, height: 16)
    }

    override func mouseDown(with event: NSEvent) {
        canvas?.focus(card)
        if event.clickCount == 2 {
            canvas?.zoom(to: card)
            return
        }
        guard let point = documentPoint(event), let frame = canvas?.model.card(card.id)?.frame else { return }
        start = (point, frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let start, let point = documentPoint(event),
              var frame = canvas.model.card(card.id)?.frame else { return }
        frame.origin = CGPoint(x: start.origin.x + point.x - start.point.x, y: start.origin.y + point.y - start.point.y)
        canvas.setFrame(frame, of: card)
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        canvas?.cardFrameDidSettle()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Move to Window", action: #selector(moveToWindow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Card", action: #selector(closeCard), keyEquivalent: "").target = self
        return menu
    }

    @objc private func closeCard() {
        card.closeCard()
    }

    @objc private func moveToWindow() {
        canvas?.moveToWindow(card)
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint? {
        enclosingScrollView?.documentView?.convert(event.locationInWindow, from: nil)
    }
}

/// What a card's header shows: the focused pane's project pill and the
/// card's agent state, dimmed with the card while a pane waits on you.
struct CardHeaderContent: View {
    @ObservedObject var card: CardController
    @ObservedObject private var claude = ClaudeRuntime.shared
    @ObservedObject private var activity = PaneActivity.shared

    var body: some View {
        // Ready fades after a while without use; look again now and then.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let panes = card.surfaceTree.map(\.id)
            HStack(spacing: 8) {
                ProjectPill(model: card.header)
                if let status = CardStatus.of(
                    panes: panes, awaiting: claude.awaiting, phases: claude.phases,
                    known: activity.known, lastActivity: activity.lastActivity, now: timeline.date) {
                    CardStatusLabel(status: status)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                // The same dim as the panes' Ready for Response below it.
                if ClaudeReadyOverlay.waiting(in: panes, awaiting: claude.awaiting) != nil {
                    Color.black.opacity(0.45)
                }
            }
        }
    }
}

struct CardStatusLabel: View {
    let status: CardStatus
    var size: CGFloat = 11

    var body: some View {
        Text(status.title)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .waiting: .orange
        case .working: .pink
        case .ready: .green
        }
    }
}
#endif
```

- [ ] **Step 8: Write the tile**

Create `macos/Sources/Features/Canvas/CardTile.swift`:

```swift
#if os(macOS)
import SwiftUI

/// A card zoomed far out: a tile in its pane's skin colors with the
/// project, the agent state and what Claude is doing ("Editing
/// Foo.swift"). Clicking it zooms to the card.
struct CardTile: View {
    @ObservedObject var card: CardController
    /// The canvas's zoom: the tile is laid out at screen size and scaled
    /// up, so its text reads the same however far out.
    let zoom: CGFloat
    let open: () -> Void
    @ObservedObject private var claude = ClaudeRuntime.shared
    @ObservedObject private var activity = PaneActivity.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width * zoom, height: geo.size.height * zoom, alignment: .topLeading)
                .scaleEffect(1 / zoom, anchor: .topLeading)
        }
        .background(background)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var panes: [UUID] { card.surfaceTree.map(\.id) }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProjectPill(model: card.header)
            if let status = CardStatus.of(
                panes: panes, awaiting: claude.awaiting, phases: claude.phases,
                known: activity.known, lastActivity: activity.lastActivity, now: Date()) {
                CardStatusLabel(status: status, size: 13)
            }
            if let action = panes.lazy.compactMap({ claude.actions[$0] }).first {
                Text(action)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    private var background: Color {
        guard let pane = card.focusedSurface?.id ?? panes.first, let skin = skins.effectiveSkin(pane) else {
            return Color(nsColor: .windowBackgroundColor)
        }
        return TraceColors.color(skin.background)
    }
}
#endif
```

- [ ] **Step 9: Write the title-bar accessory and the menu**

Create `macos/Sources/Features/Canvas/CanvasTitleAccessory.swift`:

```swift
#if os(macOS)
import SwiftUI

/// At the right of the canvas's title bar: Jump to What Needs You, and the
/// focused card's project pill.
struct CanvasTitleAccessory: View {
    @ObservedObject var sidebar: ExtensionSidebarModel
    let jump: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: jump) {
                Image(systemName: "arrow.down.forward.circle")
            }
            .buttonStyle(.borderless)
            .help("Jump to What Needs You (⌃⌘J)")
            .accessibilityLabel("Jump to What Needs You")
            ProjectPill(model: sidebar)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }
}
#endif
```

Create `macos/Sources/Features/Canvas/CanvasMenu.swift`:

```swift
#if os(macOS)
import AppKit

/// Lostty Beta's canvas items in the Window menu, above Bring All to Front.
@MainActor
final class CanvasMenu: NSObject, NSMenuItemValidation {
    static let shared = CanvasMenu()

    /// Nothing in the stable app.
    static func install(before anchor: NSMenuItem?, channel: LosttyChannel = .current) {
        guard channel.hasCanvas, let anchor, let menu = anchor.menu else { return }
        var index = menu.index(of: anchor)
        for item in shared.items() + [.separator()] {
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    private func items() -> [NSMenuItem] {
        [
            item("Canvas", #selector(showCanvas(_:)), "k", [.control, .command]),
        ]
    }

    private func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = self
        return item
    }

    @objc private func showCanvas(_ sender: Any?) {
        guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }
        CanvasController.show(ghostty)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(showCanvas(_:)): true
        default: CanvasController.key != nil
        }
    }
}
#endif
```

- [ ] **Step 10: Write the canvas controller**

Create `macos/Sources/Features/Canvas/CanvasController.swift`:

```swift
#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Lostty Beta's canvas: one window that is an infinite whiteboard of
/// terminal cards. Owns the window, the cards' layout (CanvasModel) and
/// the cards (CardController, one per split group). Closing the window
/// hides it; its terminals keep running.
@MainActor
final class CanvasController: NSWindowController, NSWindowDelegate {
    /// The app's one canvas, made the first time it's opened or restored.
    /// Set only by `show(_:freshCard:)` and `restore(_:state:)`.
    static var shared: CanvasController?

    /// The canvas while it's the key window: where ⌘N makes a card.
    static var key: CanvasController? {
        shared.flatMap { $0.window?.isKeyWindow == true ? $0 : nil }
    }

    /// Every card's controller, for the app's pane lookups.
    static var allCards: [CardController] { shared?.cards ?? [] }

    /// Closed cards kept so Undo can bring one back.
    static let retiredLimit = 10

    let ghostty: Ghostty.App
    private(set) var model = CanvasModel()
    /// In the order they were added; `model.cards` has them back to front.
    private(set) var cards: [CardController] = []
    /// The card holding keyboard focus, or that last held it.
    private(set) weak var focusedCard: CardController?
    /// The icon row, usage bar and title-bar pill follow the focused card's pane.
    let sidebar = ExtensionSidebarModel()

    private let surface = CanvasSurfaceView()
    var scrollView: CanvasScrollView { surface.scrollView }
    private(set) var views: [UUID: CardView] = [:]
    /// Closed cards with where they were, newest last, for Undo.
    private var retired: [(card: CardController, frame: CGRect)] = []
    /// The zoom the terminals last rendered at.
    var settledZoom: CGFloat = 1
    var settleWork: DispatchWorkItem?
    var waits = CanvasWaits()
    /// The view to show when the window first opens (a restored canvas's).
    var pendingView: (center: CGPoint, zoom: CGFloat)?
    private var placed = false
    private var eventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    /// Opens the canvas, making it the first time; an empty canvas gets a
    /// fresh card unless panes are about to move in.
    @discardableResult
    static func show(_ ghostty: Ghostty.App, freshCard: Bool = true) -> CanvasController {
        let canvas = shared ?? CanvasController(ghostty)
        shared = canvas
        canvas.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if freshCard, canvas.cards.isEmpty { canvas.newCard() }
        return canvas
    }

    init(_ ghostty: Ghostty.App) {
        self.ghostty = ghostty
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Canvas"
        window.tabbingMode = .disallowed
        // Saved with the app's own state (CanvasRestorableState): window
        // restoration skips hidden windows, and a hidden canvas still holds
        // running terminals.
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 320)
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ExtensionSidebarLayout(model: sidebar) {
            CanvasSurface(view: surface)
        })
        if !window.setFrameUsingName("LosttyCanvas") { window.center() }
        window.setFrameAutosaveName("LosttyCanvas")
        installTitleAccessory()
        observe()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        defer { updateVisibility() }
        guard !placed else { return }
        // The first time: lay out, then show the restored view or the middle.
        placed = true
        window?.contentView?.layoutSubtreeIfNeeded()
        let view = pendingView ?? (CanvasModel.middle, 1)
        pendingView = nil
        scrollView.magnification = CanvasZoom.clamped(view.zoom)
        center(on: view.center)
        settleZoom()
    }

    private func installTitleAccessory() {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        let host = NSHostingView(rootView: CanvasTitleAccessory(sidebar: sidebar) { [weak self] in self?.jump() })
        host.frame.size = NSSize(width: 340, height: 28)
        accessory.view = host
        window?.addTitlebarAccessoryViewController(accessory)
    }

    private func observe() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(canvasMoved), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        // Focus follows the window's first responder: whichever card holds
        // it is the focused card.
        window?.publisher(for: \.firstResponder)
            .sink { [weak self] responder in self?.firstResponderChanged(responder) }
            .store(in: &cancellables)
        ClaudeRuntime.shared.$awaiting
            .sink { [weak self] awaiting in self?.waits.update(awaiting: awaiting, now: Date()) }
            .store(in: &cancellables)
        sidebar.focusTerminal = { [weak self] in
            if let surface = self?.focusedCard?.focusedSurface { Ghostty.moveFocus(to: surface) }
        }
        // A terminal has no use for pinches, so pinching anywhere zooms the
        // canvas; ⌥-scrolling pans it even over a terminal.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
            guard let self, event.window === window else { return event }
            if event.type == .magnify {
                scrollView.magnify(with: event)
                return nil
            }
            if event.modifierFlags.contains(.option) {
                scrollView.scrollWheel(with: event)
                return nil
            }
            return event
        }
    }

    // MARK: Cards

    /// A new card with one fresh terminal, in the middle of the view.
    @discardableResult
    func newCard(baseConfig: Ghostty.SurfaceConfiguration? = nil) -> CardController {
        let card = CardController(ghostty, canvas: self, baseConfig: baseConfig)
        add(card, frame: model.placement(in: scrollView.documentVisibleRect))
        focus(card)
        return card
    }

    /// A card holding `tree`: panes moved in from a window, or restored.
    @discardableResult
    func addCard(
        tree: SplitTree<Ghostty.SurfaceView>, frame: CGRect? = nil, focused: Ghostty.SurfaceView? = nil
    ) -> CardController {
        let card = CardController(ghostty, canvas: self, tree: tree)
        if let focused, tree.contains(focused) {
            card.focusedSurface = focused
            card.header.focusedSurfaceID = focused.id
        }
        add(card, frame: frame ?? model.placement(size: Self.cardSize(for: tree), in: scrollView.documentVisibleRect))
        return card
    }

    /// Big enough for `tree`'s panes as they were last laid out, plus a header.
    static func cardSize(for tree: SplitTree<Ghostty.SurfaceView>) -> CGSize {
        let panes = tree.viewBounds()
        guard panes.width > 0, panes.height > 0 else { return CanvasModel.newCardSize }
        return CGSize(width: panes.width, height: panes.height + CardView.headerHeight)
    }

    private func add(_ card: CardController, frame: CGRect) {
        cards.append(card)
        model.add(card.id, frame: frame)
        let view = CardView(card: card, canvas: self)
        view.stackIndex = model.cards.count - 1
        views[card.id] = view
        scrollView.document.addSubview(view)
        if let placed = model.card(card.id)?.frame { view.frame = placed }
        updateVisibility()
        saveSoon()
    }

    func card(holding surface: Ghostty.SurfaceView) -> CardController? {
        cards.first { $0.surfaceTree.contains(surface) }
    }

    /// Keyboard focus to `card`'s focused pane.
    func focus(_ card: CardController) {
        guard let surface = card.focusedSurface ?? card.surfaceTree.first else { return }
        card.focusSurface(surface)
    }

    private func firstResponderChanged(_ responder: NSResponder?) {
        guard let surface = responder as? Ghostty.SurfaceView, let card = card(holding: surface) else { return }
        card.focusedSurfaceDidChange(to: surface)
    }

    /// A card's pane took keyboard focus: it's the focused card now, in
    /// front, with the window's title, icon row and outline.
    func cardDidFocus(_ card: CardController) {
        let previous = focusedCard
        focusedCard = card
        if previous !== card {
            previous?.syncFocusToSurfaceTree()
            bringToFront(card)
        }
        card.syncFocusToSurfaceTree()
        card.applyTitleToWindow()
        sidebar.focusedSurfaceID = card.focusedSurface?.id
        for (id, view) in views { view.isFocusedCard = id == card.id }
    }

    private func bringToFront(_ card: CardController) {
        model.bringToFront(card.id)
        for (index, entry) in model.cards.enumerated() { views[entry.id]?.stackIndex = index }
        // Reorders without taking views out of the window, so the focused
        // pane keeps keyboard focus.
        scrollView.document.sortSubviews({ a, b, _ in
            let left = (a as? CardView)?.stackIndex ?? 0, right = (b as? CardView)?.stackIndex ?? 0
            return left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
        }, context: nil)
    }

    /// Moving or resizing, live.
    func setFrame(_ frame: CGRect, of card: CardController) {
        model.setFrame(frame, of: card.id)
        if let frame = model.card(card.id)?.frame { views[card.id]?.frame = frame }
    }

    /// A drag or resize ended.
    func cardFrameDidSettle() {
        updateVisibility()
        saveSoon()
    }

    /// A card's panes changed. With none left the card goes, kept a while
    /// for Undo; when Undo gives it its panes back, it returns where it was.
    func cardTreeDidChange(_ card: CardController, from old: SplitTree<Ghostty.SurfaceView>, to new: SplitTree<Ghostty.SurfaceView>) {
        if new.isEmpty {
            retire(card)
        } else if old.isEmpty, let index = retired.firstIndex(where: { $0.card === card }) {
            let frame = retired.remove(at: index).frame
            add(card, frame: frame)
            focus(card)
        }
        updateVisibility()
        saveSoon()
    }

    private func retire(_ card: CardController) {
        guard let frame = model.card(card.id)?.frame else { return }
        model.remove(card.id)
        cards.removeAll { $0 === card }
        views.removeValue(forKey: card.id)?.removeFromSuperview()
        retired.append((card, frame))
        if retired.count > Self.retiredLimit { retired.removeFirst() }
        if focusedCard === card {
            focusedCard = nil
            if let next = model.cards.last.flatMap({ entry in cards.first { $0.id == entry.id } }) { focus(next) }
        }
    }

    /// Shows the canvas and pans just enough to bring `card` into view.
    func reveal(_ card: CardController) {
        if window?.isVisible != true { showWindow(nil) }
        guard let view = views[card.id] else { return }
        view.scrollToVisible(view.bounds)
    }

    /// Move to Window: the card's panes become a normal window; nothing restarts.
    func moveToWindow(_ card: CardController) {
        let tree = card.surfaceTree
        guard !tree.isEmpty else { return }
        card.surfaceTree = .init()
        _ = TerminalController.newWindow(ghostty, tree: tree)
    }

    // MARK: View

    @objc private func canvasMoved() {
        updateVisibility()
    }

    private func center(on point: CGPoint) {
        let size = scrollView.contentView.bounds.size
        scrollView.contentView.scroll(to: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// ⌃⌘0: every card in view.
    func zoomToFit() {
        guard let rect = model.fitRect else { return }
        scrollView.magnify(toFit: rect)
        settleZoom()
    }

    /// ⌃⌘1, double-clicking a header, clicking a tile: `card` centered at
    /// `zoom` (100%).
    func zoom(to card: CardController, zoom: CGFloat = 1) {
        guard let frame = model.card(card.id)?.frame else { return }
        scrollView.magnify(toFit: CanvasZoom.rect(
            centeredOn: CGPoint(x: frame.midX, y: frame.midY), zoom: zoom, viewport: scrollView.contentSize))
        settleZoom()
    }

    /// The zoom stopped changing: tiles relayout, and cards switch between
    /// their terminals and tiles.
    func settleZoom() {
        settleWork?.cancel()
        settledZoom = scrollView.magnification
        for view in views.values { view.zoomDidSettle(settledZoom) }
        updateVisibility()
        saveSoon()
    }

    /// Which cards draw live, as tiles, or not at all: only those near the
    /// view, and none while the canvas is hidden or covered.
    func updateVisibility() {
        let shown = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        let inView = model.cardsInView(scrollView.documentVisibleRect)
        let tiles = CanvasZoom.showsTiles(at: settledZoom)
        for card in cards {
            views[card.id]?.mode = !shown || !inView.contains(card.id) ? .hidden : tiles ? .tile : .live
        }
    }

    /// The app saves its restorable state (and the canvas with it) soon.
    func saveSoon() {
        NSApp.invalidateRestorableState()
    }

    /// Jump to What Needs You; Task 4 fills it in.
    func jump() {}

    // MARK: NSWindowDelegate

    /// Closing the canvas hides it; its terminals keep running.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        updateVisibility()
        saveSoon()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Only the focused card restores keyboard focus to its pane.
        focusedCard?.windowDidBecomeKey(notification)
        for card in cards where card !== focusedCard { card.syncFocusToSurfaceTree() }
    }

    func windowDidResignKey(_ notification: Notification) {
        for card in cards { card.windowDidResignKey(notification) }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateVisibility()
    }

    func windowDidResize(_ notification: Notification) {
        updateVisibility()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (NSApp.delegate as? AppDelegate)?.undoManager
    }
}
#endif
```

- [ ] **Step 11: Wire the menu and ⌘N into the app**

In `macos/Sources/App/macOS/AppDelegate.swift`, after `RestartUI.installMenuItem(after: menuOpenConfig)` (line ~363), add:

```swift
        // Lostty Beta: the canvas, in the Window menu.
        CanvasMenu.install(before: menuBringAllToFront)
```

Replace `newWindow(_:)` (line ~1122):

```swift
    @IBAction func newWindow(_ sender: Any?) {
        // Lostty Canvas: on the canvas, New Window makes a card.
        if let canvas = CanvasController.key {
            canvas.newCard()
            return
        }
        _ = TerminalController.newWindow(ghostty)
    }
```

Replace the body of `ghosttyNewWindow(_:)` (line ~888):

```swift
    @objc private func ghosttyNewWindow(_ notification: Notification) {
        let configAny = notification.userInfo?[Ghostty.Notification.NewSurfaceConfigKey]
        let config = configAny as? Ghostty.SurfaceConfiguration
        // Lostty Canvas: new_window from a card's pane makes a card.
        if let surface = notification.object as? Ghostty.SurfaceView,
           let canvas = CanvasController.shared, canvas.card(holding: surface) != nil {
            canvas.newCard(baseConfig: config)
            return
        }
        _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
    }
```

- [ ] **Step 12: Build and run the tests**

Run: `macos/build.nu --configuration Debug`
Expected: `** BUILD SUCCEEDED **`. Likely compile fixes: `CanvasController` methods called from `CardView` closures must be reachable (they're internal); `TraceColors.color(_:)` is `static func color(_ rgb: RGB) -> Color` (Features/Claude/TraceColors.swift:33).

Run: `macos/skins-test.sh CardFocusTests && macos/skins-test.sh CanvasMenuTests`
Expected: `** TEST SUCCEEDED **` for both.

- [ ] **Step 13: Smoke check in the Debug build (no owner needed)**

```bash
open -n macos/build/Debug/Lostty.app
```

Check that it launched (`pgrep -f "build/Debug/Lostty.app"`), then quit it with the Global Constraints command. The owner's hands-on look comes in Task 7.

- [ ] **Step 14: Commit**

```bash
git add macos/Sources/Features/Canvas macos/Tests/Canvas/CanvasControllerTests.swift macos/Sources/Features/Terminal/BaseTerminalController.swift macos/Sources/App/macOS/AppDelegate.swift
git commit -m "Canvas: the canvas window and its cards (beta)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 3: Card-aware pane lookups

Code that finds a pane's controller through its window misses cards (the canvas window's controller is the `CanvasController`). Two lookups replace those casts. App Intents and AppleScript keep seeing only normal windows (out of scope by the spec); Float on Top, tab-group code, Update's window pick and `goto_window` stay as they are (the canvas isn't a terminal window for them).

**Files:**
- Create: `macos/Sources/Features/Canvas/CanvasLookup.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate+Ghostty.swift:8-19`, `macos/Sources/App/macOS/AppDelegate.swift` (`findSurface` ~1079, `anyPaneNeedsConfirmQuit` ~577, `setDockBadge` ~909), `macos/Sources/Features/Terminal/BaseTerminalController.swift:967`, `macos/Sources/Ghostty/Ghostty.App.swift` (lines ~1202, 1308, 1362, 1578, 1669, 1728, 1737), `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift:1091`, `macos/Sources/Ghostty/Surface View/SurfaceGrabHandle.swift:23`, `macos/Sources/Helpers/PaneFocus.swift:10-11`, `macos/Sources/Features/Sessions/SessionSync.swift:42`, `macos/Sources/Features/Sessions/SessionsUI.swift:15-17`, `macos/Sources/Features/Branches/SessionLocator.swift:28`, `macos/Sources/Features/Command Palette/TerminalCommandPalette.swift:143`

**Interfaces:**
- Consumes: `CanvasController.shared`, `.allCards`, `card(holding:)` (Task 2).
- Produces: `BaseTerminalController.everyController: [BaseTerminalController]`; `Ghostty.SurfaceView.terminalController: BaseTerminalController?`.

- [ ] **Step 1: Write the lookups**

Create `macos/Sources/Features/Canvas/CanvasLookup.swift`:

```swift
#if os(macOS)
import AppKit

extension BaseTerminalController {
    /// Every terminal controller: each window's (the Quick Terminal's too)
    /// and each canvas card's.
    @MainActor
    static var everyController: [BaseTerminalController] {
        NSApp.windows.compactMap { $0.windowController as? BaseTerminalController } + CanvasController.allCards
    }
}

extension Ghostty.SurfaceView {
    /// The controller whose split tree holds this pane: its canvas card's,
    /// else its window's.
    @MainActor
    var terminalController: BaseTerminalController? {
        CanvasController.shared?.card(holding: self) ?? window?.windowController as? BaseTerminalController
    }
}
#endif
```

- [ ] **Step 2: Switch the window-wide lists**

Apply each change exactly; read a few lines round each first so the edit lands on the right code.

`AppDelegate+Ghostty.swift`, `ghosttySurface(id:)` body:

```swift
    func ghosttySurface(id: UUID) -> Ghostty.SurfaceView? {
        for controller in BaseTerminalController.everyController {
            for surface in controller.surfaceTree where surface.id == id {
                return surface
            }
        }

        return nil
    }
```

`AppDelegate.swift`, `findSurface(forUUID:)` (keeps leaving out the Quick Terminal, as `TerminalController.all` did):

```swift
    func findSurface(forUUID uuid: UUID) -> Ghostty.SurfaceView? {
        let controllers: [BaseTerminalController] = TerminalController.all + CanvasController.allCards
        for c in controllers {
            for view in c.surfaceTree where view.id == uuid {
                return view
            }
        }

        return nil
    }
```

`AppDelegate.swift`, `anyPaneNeedsConfirmQuit()`:

```swift
    private static func anyPaneNeedsConfirmQuit() -> Bool {
        BaseTerminalController.everyController
            .contains { $0.surfaceTree.contains(where: { $0.needsConfirmQuit }) }
    }
```

`AppDelegate.swift`, `setDockBadge()` first statement:

```swift
        let bellCount = BaseTerminalController.everyController
            .reduce(0) { $0 + ($1.bell ? 1 : 0) }
```

`BaseTerminalController.swift` ~967, in `splitDidDrop`, replace

```swift
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else { continue }
            guard controller !== self else { continue }
```

with

```swift
        for controller in Self.everyController {
            guard controller !== self else { continue }
```

`SessionSync.swift` ~42:

```swift
            for controller in BaseTerminalController.everyController {
                controller.applySessionLabel()
            }
```

`SessionsUI.swift` ~15 (so a card's tmux sessions are never offered as orphans):

```swift
            let openPanes = Set(BaseTerminalController.everyController
                .flatMap { $0.surfaceTree.filter(\.inTmuxSession).map(\.id) })
```

`SessionLocator.swift` ~28 (Branches lists card panes):

```swift
        let controllers: [BaseTerminalController] = TerminalController.all + CanvasController.allCards
        return controllers.flatMap { controller in
```

`TerminalCommandPalette.swift` ~143 (jump to a card's pane from the palette). It reads `controller.window` and `(window as? TerminalWindow)?.tabColor`; a card's window is the canvas window, which has no tab color, so the same code works:

```swift
        let controllers: [BaseTerminalController] = TerminalController.all + CanvasController.allCards
        return controllers.flatMap { controller -> [CommandOption] in
```

If any of these closures use a `TerminalController`-only member, keep that site on `TerminalController.all`, and record it in the commit message instead of forcing it.

- [ ] **Step 3: Switch the pane-to-controller casts**

`Ghostty.App.swift`: at ~1202, ~1308, ~1362 and ~1578 replace `surfaceView.window?.windowController as? BaseTerminalController` with `surfaceView.terminalController`. At ~1669 (set_tab_title) and ~1737 (prompt_title, surface target) replace

```swift
                guard let window = surfaceView.window,
                      let controller = window.windowController as? BaseTerminalController
```

with

```swift
                guard let controller = surfaceView.terminalController
```

and keep the rest of each `guard` (`else { return false }`). If `window` is used later in that case, keep `let window = surfaceView.window,` as the guard's first clause. At ~1728 (prompt_title, app target), make the canvas's focused card count:

```swift
                    guard let window = NSApp.mainWindow ?? NSApp.keyWindow,
                          let controller = (window.windowController as? BaseTerminalController)
                            ?? (window.firstResponder as? Ghostty.SurfaceView)?.terminalController
                    else { return false }
```

`SurfaceView_AppKit.swift` ~1091 (focus follows the mouse between card panes):

```swift
            if let window,
               let controller = terminalController,
```

`SurfaceGrabHandle.swift` ~23:

```swift
            guard let controller = surfaceView.terminalController else { return false }
```

(Use the name the surrounding code uses for the surface view; read the lines first.)

`PaneFocus.swift`:

```swift
        guard let surface = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: id),
              let controller = surface.terminalController
        else { return false }
```

- [ ] **Step 4: Check that nothing was missed**

Run: `grep -rn "windowController as? BaseTerminalController" macos/Sources | grep -v AppleScript | grep -v "App Intents"`
Expected: only `CanvasLookup.swift`, `TerminalWindow.swift`-family native-tab code, `AppDelegate.swift:440` (DEBUG trace preview), `Ghostty.App.swift` goto_window (~1247/1284) and the prompt_title app-target line from Step 3. Anything else: switch it as above, or note in the commit why not.

- [ ] **Step 5: Build and run the whole suite**

Run: `macos/build.nu --configuration Debug` → `** BUILD SUCCEEDED **`.
Run: `macos/skins-test.sh` → `** TEST SUCCEEDED **` (BranchesModelTests can flake under load; if only they fail, re-run `macos/skins-test.sh BranchesModelTests` alone before treating it as real).

- [ ] **Step 6: Commit**

```bash
git add -A macos/Sources
git commit -m "Canvas: card-aware pane lookups (focus, notifications, Branches, sessions, quit, drag)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 4: Crisp zoom, navigation and Jump

**Files:**
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (`viewDidChangeBackingProperties` ~920, `sizeDidChange` ~556 for variant B)
- Create: `macos/Sources/Features/Canvas/CanvasController+Navigate.swift`
- Modify: `macos/Sources/Features/Canvas/CanvasController.swift` (`canvasMoved`, `settleZoom`, `add`, `cardTreeDidChange`, remove the `jump()` stub)
- Modify: `macos/Sources/Features/Canvas/CanvasMenu.swift`
- Test: `macos/Tests/Canvas/CanvasControllerTests.swift`

**Interfaces:**
- Consumes: Task 0's zoom variant (A or B); `CanvasController` (Task 2); `CanvasWaits` (Task 1).
- Produces: `Ghostty.SurfaceView.canvasZoomDidSettle(_ zoom: CGFloat)`; `CanvasController.scheduleSettle()`, `jump()`, `moveFocus(_:)`.

- [ ] **Step 1: Write the failing menu test**

Append to `CanvasMenuTests` in `macos/Tests/Canvas/CanvasControllerTests.swift`:

```swift
    @Test func theCanvasShortcutsStayClearOfTheTerminals() throws {
        let (menu, anchor) = windowMenu()
        CanvasMenu.install(before: anchor, channel: .beta)
        func item(_ title: String) throws -> NSMenuItem { try #require(menu.items.flatMap { [$0] + ($0.submenu?.items ?? []) }.first { $0.title == title }) }
        #expect(try item("Jump to What Needs You").keyEquivalent == "j")
        #expect(try item("Jump to What Needs You").keyEquivalentModifierMask == [.control, .command])
        #expect(try item("Zoom to Fit").keyEquivalent == "0")
        #expect(try item("Zoom Card to 100%").keyEquivalent == "1")
        let left = try item("Select Card Left")
        #expect(left.keyEquivalentModifierMask == [.control, .option, .command])
        #expect(left.keyEquivalent == String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
    }
```

Run: `macos/skins-test.sh CanvasMenuTests` → FAIL (`Jump to What Needs You` not found).

- [ ] **Step 2: Add the zoom hook to the pane**

Use the variant Task 0 recorded in `docs/superpowers/specs/2026-10-18-lostty-canvas-spike.md`. **The spike found variant A** (keep variant B only as the record of the alternative).

**Variant A** (the canvas's magnification reaches `convertToBacking`). In `SurfaceView_AppKit.swift`, in `viewDidChangeBackingProperties()`, replace

```swift
                layer?.contentsScale = window.backingScaleFactor
```

with

```swift
                // Lostty Canvas: on a zoomed canvas a point covers more (or
                // fewer) pixels than the screen's scale.
                let backing = convertToBacking(NSRect(x: 0, y: 0, width: 1, height: 1)).width
                layer?.contentsScale = backing > 0 ? backing : window.backingScaleFactor
```

and add after `viewDidChangeBackingProperties()`:

```swift
        /// Lostty Canvas: the canvas's zoom settled. Its scaled clip view
        /// already makes this pane's pixels per point the screen's × the
        /// zoom; re-rasterize at that (crisp text) with the grid unchanged.
        func canvasZoomDidSettle(_ zoom: CGFloat) {
            guard window != nil, frame.width > 0, frame.height > 0 else { return }
            viewDidChangeBackingProperties()
        }
```

**Variant B** (it doesn't). Add a property next to `contentSize`:

```swift
        /// Lostty Canvas: the canvas's zoom, which the pane renders at; 1
        /// everywhere else.
        private(set) var canvasZoom: CGFloat = 1
```

In `sizeDidChange(_:)` replace `let scaledSize = self.convertToBacking(size)` with

```swift
            let backing = self.convertToBacking(size)
            let scaledSize = CGSize(width: backing.width * canvasZoom, height: backing.height * canvasZoom)
```

In `viewDidChangeBackingProperties()` replace `layer?.contentsScale = window.backingScaleFactor` with `layer?.contentsScale = CanvasZoom.contentScale(backing: window.backingScaleFactor, zoom: canvasZoom)`, replace the two scale lines with

```swift
            let xScale = fbFrame.size.width / self.frame.size.width * canvasZoom
            let yScale = fbFrame.size.height / self.frame.size.height * canvasZoom
```

and replace `let scaledSize = self.convertToBacking(contentSize)` with

```swift
            let backing = self.convertToBacking(contentSize)
            let scaledSize = CGSize(width: backing.width * canvasZoom, height: backing.height * canvasZoom)
```

Then add:

```swift
        /// Lostty Canvas: the canvas's zoom settled; re-rasterize at it
        /// (crisp text) with the grid unchanged.
        func canvasZoomDidSettle(_ zoom: CGFloat) {
            canvasZoom = zoom
            guard window != nil, frame.width > 0, frame.height > 0 else { return }
            viewDidChangeBackingProperties()
        }
```

- [ ] **Step 3: Settle after a pinch, and render new panes at the zoom**

In `CanvasController.swift`, replace `canvasMoved()`:

```swift
    @objc private func canvasMoved() {
        updateVisibility()
        if scrollView.magnification != settledZoom { scheduleSettle() }
    }
```

In `settleZoom()`, after `settledZoom = scrollView.magnification`, add:

```swift
        for card in cards {
            for surface in card.surfaceTree { surface.canvasZoomDidSettle(settledZoom) }
        }
```

At the end of `add(_:frame:)` and of `cardTreeDidChange(_:from:to:)` add:

```swift
        for surface in card.surfaceTree { surface.canvasZoomDidSettle(settledZoom) }
```

(For a pane not yet in the window the hook does nothing; variant A picks up the zoom when AppKit calls `viewDidChangeBackingProperties` on attach; variant B has stored it.)

Delete the `jump()` stub ("Jump to What Needs You; Task 4 fills it in.") from `CanvasController.swift`.

- [ ] **Step 4: Write navigation and Jump**

Create `macos/Sources/Features/Canvas/CanvasController+Navigate.swift`:

```swift
#if os(macOS)
import AppKit

extension CanvasController {
    /// The zoom changed (a pinch): once it holds still for a moment, the
    /// terminals re-render at it.
    func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settleZoom() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CanvasZoom.settle, execute: work)
    }

    /// ⌃⌘J: the next pane waiting on you, oldest first, round and round:
    /// its card at 100% and the pane focused. A beep with none.
    func jump() {
        let panes = Set(cards.flatMap { $0.surfaceTree.map(\.id) })
        guard let id = waits.next(after: focusedCard?.focusedSurface?.id, among: panes),
              let card = cards.first(where: { $0.surfaceTree.contains { $0.id == id } }),
              let surface = card.surfaceTree.first(where: { $0.id == id })
        else {
            NSSound.beep()
            return
        }
        if window?.isVisible != true { showWindow(nil) }
        zoom(to: card)
        card.focusSurface(surface)
    }

    /// ⌃⌥⌘ + arrows: focus the nearest card that way, panning to show it.
    func moveFocus(_ direction: CanvasModel.Direction) {
        guard let from = focusedCard, let id = model.neighbor(of: from.id, direction),
              let card = cards.first(where: { $0.id == id })
        else {
            NSSound.beep()
            return
        }
        reveal(card)
        focus(card)
    }
}
#endif
```

- [ ] **Step 5: Add the menu items**

In `CanvasMenu.swift`, replace `items()` with:

```swift
    private func items() -> [NSMenuItem] {
        let view = NSMenuItem(title: "Canvas View", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Canvas View")
        for item in [
            item("Jump to What Needs You", #selector(jump(_:)), "j", [.control, .command]),
            item("Zoom to Fit", #selector(zoomToFit(_:)), "0", [.control, .command]),
            item("Zoom Card to 100%", #selector(zoomCard(_:)), "1", [.control, .command]),
            .separator(),
            item("Select Card Left", #selector(selectCard(_:)), Self.key(NSLeftArrowFunctionKey), [.control, .option, .command], tag: 0),
            item("Select Card Right", #selector(selectCard(_:)), Self.key(NSRightArrowFunctionKey), [.control, .option, .command], tag: 1),
            item("Select Card Above", #selector(selectCard(_:)), Self.key(NSUpArrowFunctionKey), [.control, .option, .command], tag: 2),
            item("Select Card Below", #selector(selectCard(_:)), Self.key(NSDownArrowFunctionKey), [.control, .option, .command], tag: 3),
        ] {
            submenu.addItem(item)
        }
        view.submenu = submenu
        return [item("Canvas", #selector(showCanvas(_:)), "k", [.control, .command]), view]
    }

    private static func key(_ code: Int) -> String {
        UnicodeScalar(code).map { String(Character($0)) } ?? ""
    }
```

Replace the `item(_:_:_:_:)` helper with one that also takes a tag:

```swift
    private func item(
        _ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags, tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = self
        item.tag = tag
        return item
    }
```

Add the actions:

```swift
    @objc private func jump(_ sender: Any?) {
        CanvasController.key?.jump()
    }

    @objc private func zoomToFit(_ sender: Any?) {
        CanvasController.key?.zoomToFit()
    }

    @objc private func zoomCard(_ sender: Any?) {
        guard let canvas = CanvasController.key, let card = canvas.focusedCard else { return }
        canvas.zoom(to: card)
    }

    @objc private func selectCard(_ sender: NSMenuItem) {
        let directions: [CanvasModel.Direction] = [.left, .right, .up, .down]
        guard directions.indices.contains(sender.tag) else { return }
        CanvasController.key?.moveFocus(directions[sender.tag])
    }
```

`validateMenuItem` already enables everything but Canvas only while the canvas is key; the submenu's own item has no action and stays enabled.

- [ ] **Step 6: Build and test**

Run: `macos/build.nu --configuration Debug` → `** BUILD SUCCEEDED **`.
Run: `macos/skins-test.sh CanvasMenuTests && macos/skins-test.sh CanvasZoomTests` → both succeed.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Ghostty/Surface\ View/SurfaceView_AppKit.swift macos/Sources/Features/Canvas macos/Tests/Canvas/CanvasControllerTests.swift
git commit -m "Canvas: crisp zoom once a pinch settles, Jump to What Needs You, card navigation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 5: Save and restore

**Files:**
- Create: `macos/Sources/Features/Canvas/CanvasRestorableState.swift`, `macos/Sources/Features/Canvas/CanvasController+Restore.swift`
- Modify: `macos/Sources/App/macOS/AppDelegate.swift` (`willEncodeRestorableState` ~1003, `didDecodeRestorableState` ~1019, first window ~467, quit check ~515)
- Test: `macos/Tests/Canvas/CanvasControllerTests.swift`

**Interfaces:**
- Consumes: `CanvasSaved` (Task 1); `CanvasController.addCard(tree:frame:focused:)`, `pendingView`, `shared` (Task 2).
- Produces: `CanvasRestorableState` (`selfKey "canvasState"`, `versionKey "canvasVersion"`, `version 1`, `saved`); `CanvasController.restorableState()`, `CanvasController.restore(_:state:)`.

- [ ] **Step 1: Write the failing test**

Append to `macos/Tests/Canvas/CanvasControllerTests.swift`:

```swift
struct CanvasRestoreTests {
    @Test func theCanvasNeverOverwritesTheQuickTerminalsState() {
        #expect(CanvasRestorableState.selfKey != QuickTerminalRestorableState.selfKey)
        #expect(CanvasRestorableState.versionKey != QuickTerminalRestorableState.versionKey)
        #expect(CanvasRestorableState.version == 1)
    }
}
```

Run: `macos/skins-test.sh CanvasRestoreTests` → FAIL to build ("cannot find 'CanvasRestorableState'").

- [ ] **Step 2: Write the state**

Create `macos/Sources/Features/Canvas/CanvasRestorableState.swift`:

```swift
#if os(macOS)
import Foundation

/// The canvas in the app's restorable state, beside the Quick Terminal's,
/// under its own keys so neither overwrites the other. Decoding it makes
/// the panes, which reattach to their tmux sessions as a restored window's
/// do.
struct CanvasRestorableState: TerminalRestorable {
    static var selfKey: String { "canvasState" }
    static var versionKey: String { "canvasVersion" }
    static var version: Int { 1 }

    var saved: CanvasSaved<SplitTree<Ghostty.SurfaceView>>

    init(saved: CanvasSaved<SplitTree<Ghostty.SurfaceView>>) {
        self.saved = saved
    }

    init(copy other: CanvasRestorableState) {
        self = other
    }
}
#endif
```

- [ ] **Step 3: Save and rebuild the canvas**

Create `macos/Sources/Features/Canvas/CanvasController+Restore.swift`:

```swift
#if os(macOS)
import AppKit

extension CanvasController {
    /// What the app saves for the canvas: shown or not, the view, and the
    /// cards back to front.
    func restorableState() -> CanvasRestorableState {
        let visible = scrollView.documentVisibleRect
        let saved = model.cards.compactMap { entry -> CanvasSaved<SplitTree<Ghostty.SurfaceView>>.Card? in
            guard let card = cards.first(where: { $0.id == entry.id }), !card.surfaceTree.isEmpty else { return nil }
            return .init(frame: entry.frame, tree: card.surfaceTree, focused: card.focusedSurface?.id.uuidString)
        }
        return CanvasRestorableState(saved: .init(
            visible: window?.isVisible ?? false, center: CGPoint(x: visible.midX, y: visible.midY),
            zoom: scrollView.magnification, cards: saved))
    }

    /// Rebuilds the canvas at launch; shown only if it was.
    static func restore(_ ghostty: Ghostty.App, state: CanvasRestorableState) {
        guard !state.saved.cards.isEmpty else { return }
        let canvas = shared ?? CanvasController(ghostty)
        shared = canvas
        for card in state.saved.cards {
            let focused = card.focused.flatMap { id in card.tree.first { $0.id.uuidString == id } }
            canvas.addCard(tree: card.tree, frame: card.frame, focused: focused)
        }
        canvas.pendingView = (state.saved.center, state.saved.zoom)
        if state.saved.visible {
            canvas.showWindow(nil)
        } else {
            // Hidden: its panes run but don't draw until it's opened.
            canvas.updateVisibility()
        }
    }
}
#endif
```

- [ ] **Step 4: Wire it into the app's state**

In `AppDelegate.swift`, at the end of `application(_:willEncodeRestorableState:)` (after the Quick Terminal `switch`):

```swift
        // Lostty Canvas: the canvas, shown or hidden.
        if let canvas = CanvasController.shared, !canvas.cards.isEmpty {
            canvas.restorableState().encode(with: coder)
        }
```

At the end of `application(_:didDecodeRestorableState:)`:

```swift
        // Lostty Canvas: the canvas's cards, their panes reattaching.
        if ghostty.config.windowSaveState != "never", LosttyChannel.current.hasCanvas,
           let state = CanvasRestorableState(coder: coder) {
            CanvasController.restore(ghostty, state: state)
        }
```

In `applicationDidBecomeActive`, make a shown canvas count as a window, so it doesn't get an extra one:

```swift
            if TerminalController.all.isEmpty && CanvasController.shared?.window?.isVisible != true
                && derivedConfig.initialWindow {
```

In `applicationShouldTerminate`, a hidden canvas's running terminals still ask before quitting; replace

```swift
        if (windows.allSatisfy { !$0.isVisible }) {
```

with

```swift
        if (windows.allSatisfy { !$0.isVisible }) && CanvasController.allCards.isEmpty {
```

- [ ] **Step 5: Build and test**

Run: `macos/build.nu --configuration Debug` → `** BUILD SUCCEEDED **`.
Run: `macos/skins-test.sh CanvasRestoreTests && macos/skins-test.sh CanvasSavedTests` → both succeed.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/Canvas macos/Sources/App/macOS/AppDelegate.swift macos/Tests/Canvas/CanvasControllerTests.swift
git commit -m "Canvas: saved with the app's state, so it survives Restart to Update (shown or hidden)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 6: Move to Canvas and Move to Window

**Files:**
- Modify: `macos/Sources/Features/Terminal/TerminalController.swift` (add `moveToCanvas()` near `newWindow(_:tree:)`)
- Modify: `macos/Sources/Features/Canvas/CanvasMenu.swift`
- Test: `macos/Tests/Canvas/CanvasControllerTests.swift`

**Interfaces:**
- Consumes: `CanvasController.show(_:)`, `addCard(tree:frame:focused:)`, `moveToWindow(_:)`, `key`, `focusedCard` (Task 2).
- Produces: `TerminalController.moveToCanvas()`.

- [ ] **Step 1: Write the failing test**

Append to `CanvasMenuTests`:

```swift
    @Test func windowsAndCardsTradePlaces() throws {
        let (menu, anchor) = windowMenu()
        CanvasMenu.install(before: anchor, channel: .beta)
        let titles = menu.items.map(\.title)
        #expect(titles.contains("Move to Canvas"))
        #expect(titles.contains("Move to Window"))
    }
```

Run: `macos/skins-test.sh CanvasMenuTests` → FAIL.

- [ ] **Step 2: Move a window onto the canvas**

In `TerminalController.swift`, after `newWindow(_:tree:position:confirmUndo:)`, add:

```swift
    /// Lostty Canvas: this window's panes, splits and all, become a card on
    /// the canvas and the window closes; nothing restarts.
    func moveToCanvas() {
        let tree = surfaceTree
        guard !tree.isEmpty, LosttyChannel.current.hasCanvas else { return }
        let focused = focusedSurface
        let size = CanvasController.cardSize(for: tree)
        // An empty tree closes this window (surfaceTreeDidChange).
        surfaceTree = .init()
        // The card takes the panes once this window's views have let them go.
        DispatchQueue.main.async { [ghostty] in
            let canvas = CanvasController.show(ghostty)
            let frame = canvas.model.placement(size: size, in: canvas.scrollView.documentVisibleRect)
            let card = canvas.addCard(tree: tree, frame: frame, focused: focused)
            canvas.focus(card)
        }
    }
```

Then change `CanvasController.show(ghostty)` in it to `CanvasController.show(ghostty, freshCard: false)`, so moving into an empty canvas doesn't also make a fresh card.

- [ ] **Step 3: Add the menu items**

In `CanvasMenu.items()`, return:

```swift
        return [
            item("Canvas", #selector(showCanvas(_:)), "k", [.control, .command]),
            item("Move to Canvas", #selector(moveToCanvas(_:)), "", []),
            item("Move to Window", #selector(moveToWindow(_:)), "", []),
            view,
        ]
```

Add the actions:

```swift
    @objc private func moveToCanvas(_ sender: Any?) {
        (NSApp.keyWindow?.windowController as? TerminalController)?.moveToCanvas()
    }

    @objc private func moveToWindow(_ sender: Any?) {
        guard let canvas = CanvasController.key, let card = canvas.focusedCard else { return }
        canvas.moveToWindow(card)
    }
```

and in `validateMenuItem` add before `default`:

```swift
        case #selector(moveToCanvas(_:)): NSApp.keyWindow?.windowController is TerminalController
        case #selector(moveToWindow(_:)): CanvasController.key?.focusedCard != nil
```

- [ ] **Step 4: Build and test**

Run: `macos/build.nu --configuration Debug` → `** BUILD SUCCEEDED **`.
Run: `macos/skins-test.sh CanvasMenuTests` → succeeds.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/Terminal/TerminalController.swift macos/Sources/Features/Canvas macos/Tests/Canvas/CanvasControllerTests.swift
git commit -m "Canvas: Move to Canvas and Move to Window

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Task 7: Whole-branch checks with the owner

**Files:** none new, unless a check finds a bug (fix it in the owning task's files, with a test where the logic is pure).

- [ ] **Step 1: Full suite and a stable-channel look**

Run: `macos/skins-test.sh` → `** TEST SUCCEEDED **` (re-run BranchesModelTests alone if only they fail).

H10 (stable): `grep -rn "hasCanvas" macos/Sources` must show every entry point gated: `CanvasMenu.install`, `didDecodeRestorableState`, `moveToCanvas`. `CanvasController.shared` is only ever set by `show` (reachable only from the gated menu) and `restore` (gated).

- [ ] **Step 2: Build the Debug app and open it for the owner**

```bash
macos/build.nu --configuration Debug
open -n macos/build/Debug/Lostty.app
```

The Debug build reports itself as beta only if its Info.plist says `LosttyChannel = beta`; check with `/usr/libexec/PlistBuddy -c "Print :LosttyChannel" macos/build/Debug/Lostty.app/Contents/Info.plist`. If it says stable, tell the owner and ask how they want the beta channel set for the Debug build before going on.

- [ ] **Step 3: Walk the owner through the hand checks**

Ask the owner to try each, and record pass/fail:

| # | Check |
|---|---|
| H1 | Window → Canvas (⌃⌘K) opens a canvas with one card; typing works; ⌘N makes a second card beside it. |
| H2 | Drag a header to move a card; drag an edge and a corner to resize; it stops at 320 × 200; clicking a back card brings it forward and keeps typing in it. |
| H3 | ⌘D splits inside a card; ⌘W closes a pane; `exit` in a card's last pane removes the card; Edit → Undo brings it back where it was. |
| H4 | Two-finger scroll over empty canvas pans; over a terminal scrolls it; ⌥-scroll over a terminal pans. |
| H5 | Pinch to 200% and 50%: soft while pinching, crisp a moment after; `tput lines` is unchanged (`tput cols` may move by one, spike finding); click-drag selects the text under the pointer at both zooms; at 200% the search bar (⌘F) and a split divider still take clicks. |
| H6 | Below 45% cards become tiles; a tile click zooms to that card at 100%; ⌃⌘0 fits all; ⌃⌘1 zooms the focused card; double-clicking a header does too; ⌃⌥⌘ + arrows move between cards. |
| H7 | With Window Light chosen, a working Claude lights its card's edge; with Skin Traces, the pane's own edge. The header shows Working / Waiting / Ready; a waiting card dims, header included. Two cards waiting: ⌃⌘J goes to the older one first, then the other, then beeps when none are left. (Use the scratch `busy.sh` from the window-light work, or a tiny Claude prompt.) |
| H8 | Close the canvas (it hides); quit the Debug app and relaunch it with `open -n`: the canvas stays hidden; ⌃⌘K shows its cards, attached to the same tmux sessions (history intact), and no "reopen sessions?" prompt names them. Then repeat with the canvas shown. (Never Restart to Update the Debug build; quit + `open -n` is the stand-in.) |
| H9 | Window → Move to Canvas on a split window: the window closes, a card holds the same splits with their history; the header's Move to Window turns it back into a window. |
| H11 | Quitting with a busy pane only on a hidden canvas asks "Quit Lostty?". |

- [ ] **Step 4: Quit the Debug app and report**

Quit with the Global Constraints command. Report the results to the owner. Merging `canvas` into `skins`, installing, or pushing happens only when the owner asks (and a skins install first merges main into skins, tested).
