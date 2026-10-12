# Lostty UI redesign, modern pass — design

Status: approved in brainstorming (2026-10-12); revises
`2026-10-12-lostty-ui-redesign-design.md`.

## Goal

After reviewing the first redesign, the user found the line-drawn axolotl
ugly and parts of the app not polished enough. This pass keeps the first
redesign's structure and palette and changes only what is listed here.

The approved mock is `assets/lostty-modern-mock.html` ("Modern Lostty").
The approved mascot drawing is `assets/lostty-chibi-axolotl.svg`.

### Success criteria

- Every screen matches the approved mock.
- No behavior changes. Every existing error, security and alert string stays
  exactly as it is.
- The Design Gallery screenshots (iPhone at default and largest standard text
  size; the Mac window and sheet) are reviewed by the user before anything is
  installed on the phone.

## What stays from the first redesign

Unchanged:
- the tokens: colors, type, 16 pt radius, spacing;
- `LosttyButton`, `LosttyCard`, `.losttyScreen()`;
- session cards, the message card, settings, the terminal bar and key row;
- the app icon and launch screen layout (the launch image is re-rendered);
- the pairing failure screens;
- the Design Galleries and their entries;
- the fixes already made: navigation titles, pull to refresh, the frozen gallery.

## Changes

### 1. Mascot: the chibi axolotl

The drawing in `assets/lostty-chibi-axolotl.svg` replaces the line-drawn
axolotl everywhere it appears today. That covers welcome, empty sessions,
pairing waits and success, the Mac header, the Mac pairing sheet and the
launch image.

| Part | Look |
|---|---|
| Proportions | Chibi: a big, soft, rounded-rectangle head; a small bean body with a lighter belly; four stubby limbs; a small tail curling right |
| Colors | Head pink `#F7B2D8`, body and tail `#EC97C6`, gills `accent` (`#E5199C`), face ink `#3A1530`, blush `accent` at 45%, a white highlight at 35% on the head |
| Gills | Three rounded petals per side, fanning upward |
| Face | The prompt eyes, `>` and `—` (the `—` blinks like a cursor); a small "w" mouth; blush under the eyes |

The poses and motion keep the first redesign's timing and API
(`Axolotl(pose:)`, `AxolotlMotion`):

- **Resting:** still.
- **Waiting:** the `—` eye blinks (on 0.6 s, off 0.4 s) and the gills sway
  ±4°, the left and right sides mirrored. Still under Reduce Motion.
- **Happy:** the gills lift, and a small magenta check appears top right.

The view stays decorative and hidden from VoiceOver.

### 2. A glow instead of the blueprint grid

The blueprint grid is removed. Hero screens get a soft radial glow centred
behind the axolotl, fading from `accent` at 22% to clear, on `background`.
The glow goes on welcome, the pairing screen, the empty sessions state and
the Mac pairing sheet.

### 3. iPhone

- **Welcome:** layout unchanged. Glow behind the axolotl.
- **Sessions:** cards unchanged. The live dot gets a soft accent glow. The gear
  stays the SF Symbol `gearshape`.
- **Empty sessions:** the axolotl over the glow. The existing new copy is
  split into a title, "Nothing running yet" (body, semibold), and a detail
  line, "Open Lostty on your Mac." (detail, secondary).
- **Pairing steps:** the steps card becomes rows separated by hairlines:
  - **Done:** an accent-filled circle with a white check.
  - **Current:** the system spinner (`ProgressView`, small), with the title
    in semibold.
  - **Pending:** a hollow hairline ring, with the title in secondary text.
  
  This replaces the pulsing dot. `PairingProgress` and the step titles are
  unchanged.
- **Paired:** the happy axolotl over the glow, "Paired.", the detail line, and
  **Done** pinned to the bottom.

### 4. Mac Phone Access window

- **Header:** the axolotl at about 58 pt, "Phone Access" in 24 pt bold, the
  readiness line ("4 of 7 ready") beneath it, and **Check Again** as a quiet
  button on the right.
- **Checklist card:** in each row, the status is a filled circle with a glyph:
  - ✓ in `success`;
  - ✕ in `danger`;
  - ! in `warning`.
  
  Next to it are the semibold title and the detail. The row's fix buttons
  move **below the detail**, in a row that wraps, so the text keeps the
  card's full width.
- **Unchanged:** the awake note, the full-width **Pair a Phone…**, paired
  phones and **Turn Off Phone Access…**.

### 5. Mac pairing sheet

The waiting axolotl (about 64 pt) sits over the glow. The countdown ring
starts and ends at **top center** and empties clockwise. The QR tile, the
copy and the buttons are unchanged.

## Testing

- The existing tests pass unchanged: `AxolotlMotionTests`, `PairingProgressTests`,
  `PairingCountdownTests`, `PhoneAccessReadinessTests`, `PhoneAccessGalleryTests`,
  the Phone Access suites and the `LosttyRemote` package.
- `StepPulseTests` is deleted along with the pulse.
- One new pure test: the countdown ring's path starts at the top center of
  its rect.
- Both app targets build. The iOS Release build doesn't contain the gallery.
- Review: the gallery is re-screenshotted on the iPhone simulator (default
  and largest standard text size) and the Mac is re-rendered in-process. The
  user reviews them before anything is installed on the phone.

## Risks

- **Matching the SVG:** the SwiftUI version must match the approved drawing.
  It is drawn from the same geometry (ellipses and a few paths), and the
  render test writes PNGs to compare against the SVG.
- **Wrapping fix buttons on macOS 14:** a wrapping button row needs a small
  flow layout (`Layout`). The two-button password row is the case to check.
