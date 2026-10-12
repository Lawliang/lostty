# Lostty UI redesign — design

Status: draft for review (2026-10-12)

## Goal

Lostty's phone experience looks like a finished product a customer would
trust, and unmistakably Lostty: one dark, calm visual language shared by the
iPhone app and the Mac's Phone Access window, with an axolotl mascot.

### Success criteria

- Every iPhone screen and the Mac Phone Access window use the shared palette,
  type, spacing and components; nothing reads as a stock grouped list except
  the iPhone Settings screen (restyled on purpose).
- No behavior changes: same flows, same buttons, same pairing and connection
  logic. The only additions are two haptics.
- Every screen in every state can be seen in a debug-only Design Gallery,
  screenshotted for review before shipping.
- Magenta never carries small body text; Dynamic Type and VoiceOver work on
  every iPhone screen.

## Scope

In: iPhone welcome, pairing, session list, settings, terminal top bar, key
row, app icon (the existing Lostty icon) and launch screen; the Mac Phone
Access window and its pairing sheet.

Out: the terminal text area (Lostty skins own it), a light palette for the Mac
window, redrawing the app icon with the axolotl (a follow-up once the in-app
axolotl is settled), iPad layouts.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Palette | Dark and calm, magenta as the only accent | Developer tool, used at night, matches the terminal |
| Mac window in light mode | Always dark | One palette; a branded setup window |
| Mascot | Axolotl, white line-art, magenta gill tips, `>` and `—` prompt eyes | Pink, regrows what it loses (sessions survive drops); eyes tie it to the icon and the terminal |
| Poses | Resting, waiting (animated), happy | Covers every state; errors and security prompts get no mascot |
| Where the look lives | `macos/Sources/Features/LosttyDesign/`, compiled by both app targets | The repo's existing way of sharing iPhone/Mac code; no project changes |
| Copy | Personality only in empty, waiting and success states | Security and error wording stays exact |
| Session list | Compact cards | A handful of places to go, not settings |
| Terminal chrome | Slim dark top bar | Keeps "how do I get out" obvious |
| QR | Black on white in a white tile, magenta countdown ring | Scans reliably; the ring carries the brand |
| Review | Debug-only Design Gallery in both apps | Every state reviewable, including errors |

## 1. Visual system

### Color

| Token | Value | Use |
|---|---|---|
| `background` | `#0C0B0E` | Screens |
| `surface` | `#17151B` | Cards, rows |
| `surfaceRaised` | `#211E26` | Sheets, pressed states, keys |
| `hairline` | `#2C2833` | 1 pt card borders, dividers |
| `textPrimary` | `#F4F1F6` | Titles, body |
| `textSecondary` | `#A39CAA` | Detail lines |
| `accent` | `#E5199C` | Primary buttons, selection, live dot, sticky Ctrl, gill tips |
| `accentSoft` | `accent` at 16% opacity | Tinted backgrounds behind accent icons |
| `success` | `#3FB27F` | Checklist ✓ |
| `warning` | `#E0A23A` | Checklist ⚠ |
| `danger` | `#E5484D` | Checklist ✗, destructive actions |

`accent` was sampled from the app icon's face and may be tuned once against the
icon on screen. White on `accent` is about 4.2:1, so `accent` backgrounds only
carry semibold labels of 17 pt and up; magenta text on `background` (about
4.6:1) is allowed for short labels.

### Type

SF Pro for UI; SF Mono (`.monospaced` design) for session names, the Mac's
address, key-row labels and the `>` motif. Sizes: large title 28, title 20,
body 16, detail 13; regular and semibold only. All iPhone text uses Dynamic
Type text styles mapped to these sizes.

### Shape, space, motion

16 pt corner radius on cards, buttons and the QR tile; 1 pt `hairline` borders,
no shadows; 4 pt grid: 16 pt screen margins, 12 pt between cards. Motion: 0.2 s
fades and slides; the axolotl's `—` eye blinks like a cursor (on 0.6 s, off
0.4 s) and its gills sway slowly while waiting; nothing bounces. Animations
stop under Reduce Motion.

### Blueprint motif

A white line grid with the icon's circle and diagonal guides at about 6%
opacity, drawn in code. Only behind the welcome screen, the pairing screens,
the Mac pairing sheet and empty states; never behind lists, settings or the
terminal.

## 2. Components (`LosttyDesign`)

Each is one small SwiftUI file, `#if`-guarded only where AppKit and UIKit
differ:

- `LosttyTheme` — the color, type, spacing and radius tokens above.
- `LosttyButton` — primary (accent fill, white semibold 17), secondary
  (surface fill, hairline border), quiet (text only); a full-width option.
- `LosttyCard` — a `surface` rounded container with a hairline border.
- `StatusRow` — icon (✓ / ⚠ / ✗ in success / warning / danger), title,
  detail, trailing buttons; used by the Mac checklist.
- `StepIndicator` — numbered steps with done / current (pulsing) / pending.
- `Axolotl` — a vector `Shape`-based view with `pose: .resting | .waiting |
  .happy` and a size; white strokes, magenta gill tips, prompt eyes.
- `BlueprintBackground` — the grid motif as a background view.

The axolotl's drawing is approved from a rendered image beside the icon before
any screen uses it.

## 3. iPhone screens

- **App icon and launch.** The iPhone target uses the Lostty icon (the image
  in `AppIconImage.imageset`) instead of Ghostty's icon set. The launch screen is
  `background` with the resting axolotl centered.
- **Welcome** (nothing configured): blueprint background, resting axolotl,
  "Open your Mac's Lostty sessions from here.", the three existing steps, a
  full-width primary **Pair with Mac**, a quiet **Set Up by Hand**.
- **Sessions:** large title "Lostty", one compact `LosttyCard` per session:
  name in SF Mono, a magenta live dot when the session is open on the Mac,
  chevron. Swipe to close and its confirmation are unchanged. Messages (errors,
  Pair Again) appear as a card above the list. Empty state: blueprint
  background, resting axolotl, "Nothing running yet. Open Lostty on your Mac."
  (replaces "No sessions. Is Lostty open on your Mac?" only in this empty
  state).
- **Pairing:** viewfinder with magenta corner brackets; below it a
  `StepIndicator`: Find your Mac → Allow on Mac → Connect, driven by the
  existing `PairingPhase` (finding, waitingForAllow, testing). Waiting axolotl
  during the steps; "Waiting for your Mac to say yes…" while waiting for Allow.
  Success: happy axolotl, "Paired.", primary **Done**, and a success haptic.
  Failures show the existing message text unchanged, with the existing Try
  Again / Scan Again buttons as `LosttyButton`s.
- **Settings:** the existing grouped list with `background`, `surface` rows,
  SF Mono for the address and key; all items unchanged.
- **Terminal:** slim dark top bar: back chevron, session name in SF Mono, •••
  menu (unchanged contents).
- **Key row:** same keys, same order; dark `surfaceRaised` rounded keys with
  SF Mono labels; Ctrl fills with `accent` while latched, with a light haptic
  when it latches.

## 4. Mac Phone Access window

Always dark (`background`), about 560 pt wide, resizable in height only.

- **Header:** small resting axolotl, "Phone Access", and a progress line
  ("5 of 7 ready", counting ✓ rows; ⚠ counts as not ready).
- **Checklist:** one `LosttyCard` of `StatusRow`s with the existing rows,
  details and fix buttons; the awake note beneath it.
- **Pair a Phone…:** full-width primary `LosttyButton`, disabled under the
  same condition as today.
- **Paired phones:** a `LosttyCard`, name, paired date, Rename and Remove;
  "None yet." when empty.
- **Turn Off Phone Access…:** quiet danger text button at the bottom.
- **Pairing sheet:** blueprint background, small waiting axolotl, "Scan this
  with Lostty on your iPhone.", the QR as black modules on a white rounded tile
  with a magenta ring around the tile that empties over the code's two
  minutes; Copy Pairing Link and Cancel as secondary buttons. Expired state:
  "This code expired." with **Show a New Code**.

All alerts (Allow, skip warning, Turn Off, Replace) keep their current text and
stay system alerts.

## 5. Design Gallery and review

A debug-only gallery (excluded from Release builds) in each app shows every
screen and state with fake data: welcome; sessions with two sessions, with a
message card, empty; pairing in each phase, failure and success; settings;
terminal bar and key row with Ctrl latched; the Mac window with all rows ✓,
mixed ✓/⚠/✗, no phones and two phones; the pairing sheet showing and expired.
On iPhone it opens with launch argument `-LosttyDesignGallery YES`; on the Mac
from a Debug-only menu item. Screenshots from the simulator and the Mac are the
review artifact.

## Testing

- Existing unit tests keep passing unchanged (no logic moves).
- Unit tests for the little logic the redesign adds: the Mac progress count,
  the `PairingPhase` → step mapping, and the countdown fraction.
- Both app targets build; the Design Gallery is screenshotted on an iPhone
  simulator, the Mac, and once on the real iPhone (Dynamic Type at default
  and at the largest non-accessibility size), and reviewed by the human.
- Accessibility pass: VoiceOver reads every control; Reduce Motion stops the
  axolotl animation.

## Risks

- Drawing a charming axolotl as code paths can take a few rounds; the approval
  gate before any screen uses it contains that cost.
- Replacing the iPhone's app icon set must not change the Mac app's icon.
- Restyling `Form` and `List` backgrounds differs between iOS 17 and macOS 14
  (`scrollContentBackground`); the gallery screenshots catch regressions.
