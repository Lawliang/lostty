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
- **Gestures:** pinch zooms anywhere. Two-finger scroll pans from
  anywhere, over a terminal too (focused or not); holding Option (⌥)
  scrolls the terminal under the pointer instead. A card moves by dragging
  its header.
- **Agent aids in the first beta:** a trace on each working card's edge;
  Jump to What Needs You; Ready for Response on the waiting card only.
  (Status labels and zoomed-out status tiles were tried and dropped: cards
  show their terminals at every zoom, with no "Ready" label.)

## 3. What it looks like

### 3.1 The canvas window

- **Window → Canvas** (⌃⌘K) opens it, or brings it forward. It's one
  ordinary macOS window (resizable, can go full screen, can sit on any
  Space). Closing it hides it; its terminals keep running and come back
  when you reopen it. Quitting Lostty with the canvas open asks, as
  quitting with terminal windows open does.
- Its title bar shows the focused card's project pill. (Each card has its
  own bottom bar; §3.2.)
- The background is the Lostty website's: its paper color (`#0E0B12` dark,
  `#F3F2F6` light) and dot grid (`#2A2432` / `#CDC6D7` dots, solid to 1pt
  and soft to 1.6pt), four times as dense: 9 × 12.375pt apart on screen at
  every zoom (half the website's spacing each way), moving with panning so
  motion reads.
- It does not join native tab groups.

### 3.2 Cards

- Each card looks like a small Lostty window. Its **title bar** (a standard
  title bar's height, in the color of its panes' background, as a window's)
  has, as a Lostty window's does, the red, yellow and green buttons, then
  the focused pane's folder icon and the card's title, at the left, and the
  project pill (`lostty/skins`, the repo and branch in the focused pane's
  skin, hidden outside a repo) at the right. Red closes the card,
  yellow zooms out to every card (§3.4), green zooms to the card at 100%.
  The buttons are colored on the focused card and gray on the others, as on
  inactive windows. Drag the title bar to move the card. Double-click it to
  zoom to the card (§3.4).
- Under the title bar, the card's **split tree**, drawn by today's split
  view, then its own **bottom bar** (Claude's usage, or the apps behind
  its apps button), as a window has (no mascot on the canvas). Splitting, resizing splits, closing panes
  and moving focus between panes work as in a window, with the same key
  bindings.
- While the canvas is zoomed away from 100%, SwiftUI can't take clicks: a
  click in a pane still goes to that pane, and a click on the card's
  bottom bar zooms to the card at 100%.
- Drag any card edge or corner to resize it. A card is at least 320 × 200
  points (at 100% zoom). Its terminals keep their size while you drag (their
  pixels pinned top-left) and resize once, on release; so does dragging a
  split divider inside a card. Normal windows still resize live.
- Cards may overlap; clicking a card brings it to the front and focuses it.
- Closing a card's last pane closes the card. The close button closes all
  its panes, asking first as closing a window with running programs does.
- A card has a Mac window's rounded corners, hairline edge and shadow; the
  focused card's shadow is deeper.

### 3.3 Getting terminals on and off

- **Window → Move to Canvas** moves the current window's whole split tree
  onto the canvas as a new card (the window closes; nothing restarts).
- **Move to Window** in a card's header menu (and the Window menu while a
  card is focused) does the reverse: the card becomes a normal window.
- **⌘N** (New Window) while the canvas is key makes a new card in the middle
  of the view instead of a window. **⌘T** (New Tab, from the keyboard or
  the File menu) makes a card beside the focused one (edge to edge), as big, starting in
  its focused pane's folder: to its right, else below, left or above,
  whichever side is free. Cards have no tabs of their own.
- A new card opens 720 × 500 points at the current zoom, centered in view,
  nudged so it doesn't sit exactly on another card.

### 3.4 Moving around

- **Pinch** zooms around the pointer, 25%–200%.
- **Two-finger scroll** pans anywhere, over terminals too. **⌥ + scroll**
  over a terminal scrolls that terminal (its history, or the program in
  it). Each gesture is decided as it starts, momentum included.
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
  on-screen size. **Zooming never resizes a terminal**: a pane keeps the
  grid it has at 100% at every zoom. (A cell is a whole number of pixels,
  so its size in points rounds differently at each scale; left alone, a
  720-point pane went from 89×22 at 100% to 92×21 at 200%, and every such
  resize leaves a copy of a zsh prompt in tmux's history.) The pane's size
  moves by whole cells to hold the grid, leaving a sliver of background at
  most. Where the grid doesn't quite fit it draws up to ~10% under the
  zoom's scale; where the font can't shrink enough (far out, e.g. 30%) it
  draws at its 100% pixels and the compositor scales them down.
- **Panning** moves layers only; no terminal redraws (only the dot grid
  does, a single cheap fill).

## 5. Agent aids

### 5.1 Card trace

- The trace follows the Claude Trace Style setting, as in a window: Skin
  Traces runs on the working pane's own edge inside the card; Window Light
  runs the website's light round the **card's edge**, chosen the way a
  window's is (focused pane first, Claude itself before subagents only).

### 5.2 Jump to What Needs You

- **⌃⌘J**, or the Jump button in the canvas's title bar, pans and
  zooms to the next card with a pane waiting (Ready for Response) and
  focuses that pane. Pressing it again goes to the next one, oldest wait
  first, wrapping round. With nothing waiting it beeps.

### 5.3 Ready for Response

- A waiting pane dims **its card** (header included), not the canvas, with
  the same "❯ Ready for response" line. Focusing the pane clears it.

## 6. Performance rules

- A card out of view has its terminals paused with the
  engine's occlusion call (what a hidden window gets), and resumed when it
  comes back into view. "In view" includes a margin of half a card so
  panning doesn't show a stale frame.
- Traces and Ready overlays exist only on cards that need them, and stop
  when the canvas window is hidden or covered.
- The canvas surface, cards and headers are AppKit views; SwiftUI is used
  only round the canvas (each card's bottom bar, as in a window) and
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
  title and pill), the card's `TerminalView` in a hosting view (which
  brings the split view and Ready for Response), and the Window Light
  host.
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
4. Gestures, zoom settle and culling.
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
