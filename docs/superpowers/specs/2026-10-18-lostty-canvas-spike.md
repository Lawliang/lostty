# Lostty Canvas — spike results

Date: 2026-10-18. Code: branch `canvas-spike` (throwaway, never merged),
`macos/Sources/Features/Canvas/CanvasSpike.swift`. Debug build, Retina
screen (backing 2.0).

## Verdict per check

| Check | Result |
|---|---|
| S1 focus routing between cards (window first responder, KVO) | Pass |
| S2 menu action reaches the card through the responder chain | Pass |
| S3 the core's split notification reaches only the pane's card | Pass |
| S4 zoom re-renders at the screen's scale × the zoom | Pass, **variant A**; columns can shift by one (see below) |
| S5 a click lands on the pane when zoomed | **Fail as is; pass with a fix** (see below) |
| S9 bringing a card forward keeps keyboard focus | Pass |
| S10 a card's panes move to a normal window and keep running | Pass |
| F1 ≤ 1.2 × F3 (CPU, 8 busy terminals) | Pass: 53.3% vs 64.0% |
| F2 ≤ 0.3 × F1 (hidden cards pause) | Pass: 14.1% vs 53.3% |

## Findings

- **Variant A.** The scroll view's magnification reaches the pane's
  `convertToBacking` (100 pt → 400 px at 200% on a 2× screen), and AppKit
  already re-runs the pane's backing-properties code when the
  magnification changes: content scale and pixel size follow the zoom with
  no extra call. The plan's hook (`canvasZoomDidSettle`, variant A) stays
  as the explicit re-render at settle, and the layer's `contentsScale`
  must follow the zoom (it read 4.0 at 200% once set).
- **Columns can shift by one.** Rows stayed 24 at every zoom; columns read
  44 at 87.5%, 45 at 200%, 44 at 50% and 44 at 100% for a 359-point pane.
  The cell is a whole number of pixels at each scale, so its width in
  points rounds differently (7.75 pt at 4×, 8 pt at 1×). A zoom can send
  the shell a one-column resize. The spec's "never resizes" holds for rows
  but not always for columns.
- **Clicks at a zoom other than 100%.** SwiftUI's hosting view doesn't
  find the panes inside it when an ancestor is magnified: at 200% a point
  inside a pane hit the `NSHostingView`, not the pane (at 100% it hit the
  pane). Fix, verified in the spike: the card's terminal hosting view
  overrides `hitTest`; when SwiftUI keeps a point for itself and it falls
  inside a pane, the pane takes it. Cost: at zooms other than 100%, a
  SwiftUI control over a pane (the search bar, a split divider's edge)
  may lose clicks to the terminal; a hand check.
- The first "100%" reading in the log is really 87.5% (the spike's
  zoom-to-fit); it matches the later readings once scaled.
- CPU is the process's (all threads, getrusage) over 10 s each, in the
  Debug build. GPU was not measured.

## Logs

Checks (last run):

```
start mode=checks backing=2.0
S1 two.focused=true one.focused=true
S2 sendAction handled=true one.count=2 two.count=1 (want 2, 1)
S3 one.count=2 two.count=2 (want 2, 2)
S4 at 1.0: cols=44 rows=24 cell=14x33 px=628x812 frame=(359.0, 464.0)   [really 87.5%]
S4 at 2.0 before re-render: convertToBacking(100pt)=400.0 (A: 400.0, B: 200.0) cols=45 rows=24 cell=31x76 px=1435x1856
S4 at 2.0 after re-render: cols=45 rows=24 cell=31x76 px=1435x1856 contentsScale=4.0
S9 firstResponder still pane=true
S4 at 0.5 after re-render: cols=44 rows=24 cell=8x19 px=358x464
S4 back at 1.0: cols=44 rows=24 cell=16x37 px=717x928
S5 1.0 hit=SurfaceView isPane=true
S5 2.0 (before the fix) hit=NSHostingView<TerminalView<SpikeCard>> isPane=false
S5 2.0 (with the fix) hit=SurfaceView isPane=true
S10 pane window=TransparentTitlebarTerminalWindow alive=true (×2)
```

Flood:

```
F1 eight live cards: cpu=53.3%
F2 eight cards occluded and out of view: cpu=14.1%
F3 eight splits in one window: cpu=64.0%
```
