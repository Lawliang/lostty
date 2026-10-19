# Lostty Canvas — design

Date: 2026-10-18. Status: approved; refined while planning (see the
plan, `docs/superpowers/plans/2026-10-18-lostty-canvas.md`).
Branch: `canvas`, started from `window-light` (so it has the icon row,
Window Light and the window-wide Ready for Response).

## 1. Goal

A beta-only **canvas**: one app-wide window that is an infinite whiteboard
for terminals. It serves two jobs equally:

- **Organizing work spatially:** group terminals by project or task, the
  way you would on a whiteboard.
- **Watching agents:** see at a glance which Claude or Codex terminals are
  working, waiting or done, and get to the one that needs you.

Normal Lostty windows stay exactly as they are. The canvas is an extra kind
of window, not a replacement, so nothing a window does today is lost.

At normal size a terminal on the canvas must cost what it costs in its own
window: pausing what's out of view, crisp zoom only once a pinch settles,
and AppKit (not SwiftUI) for the canvas surface are requirements, not
optimizations.

## 2. Decisions (from the owner)

- **Lostty Beta only.** Stable has no canvas: no menu item, no shortcut, no
  work done.
- **One canvas per app**, next to normal windows. Terminals move between a
  window and the canvas.
- **A card is a split group:** a mini window with its own split tree. A
  fresh card holds one terminal; it splits like a window. Moving a window to
  the canvas keeps its splits.
- **Gestures:** pinch zooms anywhere. Two-finger scroll pans over empty
  canvas and card headers, and scrolls the terminal when over one. Holding
  Option (⌥) pans from anywhere. A card moves by dragging its header.
- **Agent aids, all four in the first beta:** a trace on each working card's
  edge plus a status in its header; Jump to What Needs You; a zoomed-out
  overview of status tiles; Ready for Response on the waiting card only.

## 3. What it looks like

### 3.1 The canvas window

- **Window → Canvas** (⌃⌘K) opens it, or brings it forward. It's one
  ordinary macOS window (resizable, can go full screen, can sit on any
  Space). Closing it hides it; its terminals keep running and come back
  when you reopen it. Quitting Lostty with the canvas open asks, as
  quitting with terminal windows open does.
- Its title bar shows the focused card's project pill. Its bottom has the
  icon row and the usage bar, as a normal window's does, following the
  focused card.
- The background is the plain window background with a faint dot grid that
  moves with panning and scaling, so motion reads.
- It does not join native tab groups.

### 3.2 Cards

- A **header** strip (24pt): the project pill (`lostty/skins`, in the
  card's focused pane's skin), the agent status (§5.1), and a close button.
  Drag the header to move the card. Double-click the header to zoom to the
  card (§3.4).
- Under the header, the card's **split tree**, drawn by today's split view.
  Splitting, resizing splits, closing panes and moving focus between panes
  work as in a window, with the same key bindings.
- Drag any card edge or corner to resize it. A card is at least 320 × 200
  points (at 100% zoom).
- Cards may overlap; clicking a card brings it to the front and focuses it.
- Closing a card's last pane closes the card. The close button closes all
  its panes, asking first as closing a window with running programs does.
- The focused card has a 1pt accent outline; others have a hairline.

### 3.3 Getting terminals on and off

- **Window → Move to Canvas** moves the current window's whole split tree
  onto the canvas as a new card (the window closes; nothing restarts).
- **Move to Window** in a card's header menu (and the Window menu while a
  card is focused) does the reverse: the card becomes a normal window.
- **⌘N** (New Window) while the canvas is key makes a new card in the middle
  of the view instead of a window. ⌘T is ignored on the canvas.
- A new card opens 720 × 440 points at the current zoom, centered in view,
  nudged so it doesn't sit exactly on another card.

### 3.4 Moving around

- **Pinch** zooms around the pointer, 25%–200%.
- **Two-finger scroll** over empty canvas or a card header pans; over a
  terminal it scrolls that terminal. **⌥ + scroll** pans anywhere.
- **⌃⌘0** zooms to fit every card. **⌃⌘1** zooms the focused card to 100%
  and centers it. Double-clicking a header does the same for that card.
- **⌃⌥⌘ + arrow keys** move focus to the nearest card in that direction and
  pan to show it. (⌃⌘ + arrows already resize splits.)
- Keyboard focus is a terminal pane, as in windows; the canvas only decides
  which card it's in.

## 4. Zoom and rendering

- **While a pinch is under way**, each card is scaled on the GPU (a layer
  transform). The terminals don't redraw, so it stays smooth, and text is
  briefly soft.
- **When the zoom settles** (no change for 150ms), every visible card's
  terminals re-render at the new pixel scale: the pane's content scale is
  set to the screen's backing scale × zoom, so glyphs rasterize at their
  on-screen size. Rows stay the same; columns can move by one at some
  zooms (a cell is a whole number of pixels, so its width in points rounds
  differently at each scale; spike finding), which the shell sees as a
  one-column resize. This is the engine's existing content-scale
  call, the one a move to a Retina screen uses.
- **Below 45%**, cards stop drawing their terminals and show a **status
  tile** instead (§5.3). Coming back above 45% re-renders them.
- **Panning** moves layers only; no terminal redraws (only the dot grid
  does, a single cheap fill).

## 5. Agent aids

### 5.1 Card trace and status

- The trace follows the Claude Trace Style setting, as in a window: Skin
  Traces runs on the working pane's own edge inside the card; Window Light
  runs the website's light round the **card's edge**, chosen the way a
  window's is (focused pane first, Claude itself before subagents only).
- The header shows the card's agent state, each pane judged by the rules
  the phone's rows and the sidebar mascot use (`PaneState`): **Waiting**
  (Ready for Response is up), **Working** (a trace runs), **Ready** (used
  lately), or nothing. The card shows its most urgent pane: Waiting, then
  Working, then Ready.

### 5.2 Jump to What Needs You

- **⌃⌘J**, or the Jump button in the canvas's title bar, pans and
  zooms to the next card with a pane waiting (Ready for Response) and
  focuses that pane. Pressing it again goes to the next one, oldest wait
  first, wrapping round. With nothing waiting it beeps.

### 5.3 Overview tiles

- Below 45% zoom each card is a tile in its skin's colors: the project pill,
  the agent state, and the pane's last action ("Editing Foo.swift") when
  Claude is working. Clicking a tile zooms to that card (as ⌃⌘1).

### 5.4 Ready for Response

- A waiting pane dims **its card** (header included), not the canvas, with
  the same "❯ Ready for response" line. Focusing the pane clears it.

## 6. Performance rules

- A card out of view, or shown as a tile, has its terminals paused with the
  engine's occlusion call (what a hidden window gets), and resumed when it
  comes back into view. "In view" includes a margin of half a card so
  panning doesn't show a stale frame.
- Traces and Ready overlays exist only on cards that need them, and stop
  when the canvas window is hidden or covered.
- The canvas surface, cards and headers are AppKit views; SwiftUI is used
  only round the canvas (the icon row and usage bar, as in a window) and
  inside a card (header contents, the split view, overlays), never for the
  canvas itself, so panning never re-evaluates SwiftUI.

## 7. Save and restore

- The canvas is saved with the app's own restorable state, as the Quick
  Terminal is (window restoration skips hidden windows, and a hidden canvas
  still holds running terminals). It saves whether it's shown, the
  viewport (center and zoom), and for each card its frame, its stacking
  order and its split tree (saved as a window's is).
- Each pane reattaches to its tmux session the way a restored window's
  pane does, so **Restart to Update keeps the canvas** and its terminals.
- A restored canvas that was hidden stays hidden until opened.

## 8. How it's built

All new code is in `macos/Sources/Features/Canvas/`. Ghostty's own files
get small hooks only: the menu items, `LosttyChannel.hasCanvas`, and Move
to Canvas in the terminal controller.

- `CanvasController` (an `NSWindowController`): owns the canvas window,
  the model and the cards; the window's delegate, passing on to the cards
  what a window's controller hears (key, resign key).
- `CardController`, one per card, **is a `BaseTerminalController`**, so a
  card runs its splits exactly as a window does: the same split, close,
  focus, zoom and resize notifications, the same undo and close
  confirmations. Its `window` is the canvas window. It sits in the
  responder chain under its card view, so menu actions reach it.
- `CanvasModel`: the cards' frames (document points) back to front, plus
  pure helpers: placement, hit tests, resizing, culling, neighbors, zoom
  to fit, jump order, card status, the saved state. Unit-tested.
- The canvas surface is an `NSScrollView` with magnification (25%–200%)
  over a large flipped document view; AppKit pans and pinch-zooms it, and
  its scaled clip view keeps clicks landing on the right cell. A dot grid
  view sits behind it.
- `CardView`: an AppKit view with the header (AppKit, with a small SwiftUI
  pill and status), the card's `TerminalView` in a hosting view (which
  brings the split view and Ready for Response), the tile, and the Window
  Light host.
- Code that finds a pane's controller through its window
  (`window.windowController as? BaseTerminalController`, `TerminalController.all`)
  goes through two card-aware lookups instead:
  `BaseTerminalController.everyController` and
  `Ghostty.SurfaceView.terminalController`.

Out of scope for the first beta: more than one canvas, AppleScript and
Shortcuts access to cards (scripts see only normal windows), a minimap,
snapping and alignment guides, grouping frames, and any canvas view on the
phone (the phone keeps listing sessions as now).

## 9. Build order

0. **Spike (throwaway, decides go/no-go):** a canvas window with two live
   cards; pan; pinch with the GPU scale and the settle re-render. Check that
   zoomed text is crisp and the grid never resizes; measure CPU and GPU with
   eight live cards with output running; check that occlusion pauses
   rendering. If crisp re-render fails, fall back to re-rendering only at
   fixed zoom steps (50%, 75%, 100%, 150%) before going further.
1. `CanvasModel` with its tests.
2. The canvas window, cards and headers (beta flag, Window → Canvas).
3. Routing split, close and focus actions to cards.
4. Gestures, zoom settle, culling and tiles.
5. Agent aids (§5).
6. Save and restore, including Restart to Update.
7. Move to Canvas and Move to Window.

## 10. Testing

- Unit tests for `CanvasModel` (§8) and for the routing lookup.
- Hands-on checks in the Debug build: the spike's checks, splitting inside
  a card, Restart to Update with the canvas open (the Debug build is
  quit and relaunched, never restarted to update), moving a split window
  to the canvas and back, and Jump with two waiting fake agents.
- Stable build: confirm no canvas menu item, shortcut or work.

## 11. Risks

- **Crisp zoom** depends on the content-scale call accepting scales beyond
  a screen's (up to 4× on Retina at 200%) without resizing the grid. The
  spike settles it.
- **Code that assumes a pane's window controller is a
  `BaseTerminalController`** (e.g. finding the controller through
  `surface.window?.windowController`) would see `CanvasController`. The
  plan inventories these call sites first and decides each one.
- **Ghostty actions with no card meaning** (new tab, toggle tab overview,
  window-level full screen per pane) are ignored on the canvas or applied
  to the canvas window as a whole; the plan lists each.
- **Several cards in one window:** SwiftUI's focused values and AppKit's
  responder chain were built for one terminal view per window. The canvas
  routes focus itself (from the window's first responder) and puts each
  card's controller in the chain; the spike checks both.
