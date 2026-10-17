# Lostty website — handoff

Last updated 2026-10-16. Branch: `website`. Everything below is committed.

## Where things are

| What | File | Published (private, owner only) |
|---|---|---|
| **Custom** — the design we're building | `website/custom.html` | https://claude.ai/artifact/4MNPpJ7EaKYb3seA4vJ5bn |
| Concept 1 · Neon Signal | `website/concepts/1-neon-signal.html` | https://claude.ai/artifact/XonsET8b3oJ9phPa26fhpJ |
| Concept 2 · Aurora Glass | `website/concepts/2-aurora-glass.html` | https://claude.ai/artifact/5P4CS5pvwTFRQZSaiS6XW3 |
| Concept 3 · Skin Shifter | `website/concepts/3-skin-shifter.html` | https://claude.ai/artifact/34Y46vrqv4ooe6xt54amYr |
| Concept 4 · Handoff | `website/concepts/4-handoff.html` (built by `concepts/handoff-build/gen.py`) | https://claude.ai/artifact/8kJMCvbFpxQuPpJZdYoTtU |
| Concept 5 · Kinetic Mono | `website/concepts/5-kinetic-mono.html` | https://claude.ai/artifact/2gDLx5dDfdpUWw3H4E6AH5 |

- Every change to Custom is its own commit on `website` (`git log --oneline -- website/custom.html`), so any earlier state can be restored with `git show <sha>:website/custom.html`. The artifact also keeps its own version history (see the read result for the current version).
- The concepts are frozen drafts; only Custom is being edited.
- `website/concepts/BRIEF.md` is the brief the five concepts were built from.

## How to keep working on Custom

1. Edit `website/custom.html`.
2. Publish to the **same** artifact. From a new session, first read it with the Artifact tool (`action: "read"`, `url` above), then publish `website/custom.html` with that `url` — publishing without `url` creates a new artifact.
3. Commit: `git add website/custom.html && git commit` (stage only `website/` files — see "Shared checkout").

The owner gives one small change per message and expects: make it, publish, commit, and report in a line or two with the link and commit. Copy the owner's wording exactly (fix only obvious typos, and say so).

## What Custom is

Kinetic Mono as the base (JetBrains Mono, character-grid look, light "paper terminal" and dark themes), with these changes:

**Header**
- Logo: the Kinetic Mono axolotl icon, wordmark "Lostty" in Onest 700 17px (Aurora Glass's logo type) plus the magenta blinking `_`.
- Nav: **Download** (full-strength text even when not current), Features, Skins, Docs. On phones the `❯` current-page marker is hidden so the nav fits.

**Hero** (`.hero`, glyph-field canvas `#field`)
- Height 800px on desktop (`.hero-in`), content starts 72px from the top; on phones (<900px) it sizes to content.
- Headline (Onest 700, clamp 38–72px): "Finally, you can go touch some grass." / "With Lostty." It is capped at `max-width: 9.6em` so the first sentence always breaks after "Finally, you can go" (below ~720px the type stops at 38px and the sentence would otherwise fit on one line). "grass." (with its period) is filled with a photo of grass (`.grass`: CC0 "Green grass texture (Unsplash)" from Wikimedia Commons, 560px JPEG inlined) with a white glint that sweeps in time with the sheen. It carries Aurora Glass's sheen (a rose-to-magenta glint sweeps across every 7s; `--rose`, `--sheen-hi`).
- Description (JetBrains Mono 16px): "A Mac-native terminal-based coding harness that supports multi-agent orchestration, designed in sync with our iPhone app" then, on its own line, "— for indie builders **on the go**."
- Bullets (Neon Signal's body type: Bricolage Grotesque 16px; magenta `❯` markers):
  1. Install builds, view artifacts and simulators, & access your skills and MCPs, all remotely on your phone.
  2. Built-in caffeinate and auto-hotspot switching designed to keep your MacBook running even on a closed lid.
  3. Supports Claude Code & Codex CLI.
- Buttons: **Download for Mac** (magenta, laptop icon, goes to `#download`) and **Read docs** (`/` hint, solid page-colored fill). Both round into pills on hover (radius = half the button height, so there's no dead time leaving hover).
- Removed: the `~ ❯ open -a Lostty` line, the mouse hint, the requirements line.

**The dark boxes in the field ("quiet zones")** — the subtle part. Code: `hug()`, `lineBoxes()`, `quietZone()`, `inQuiet()` in the field script.
- The field is a grid of character cells (~8.4px × 18px desktop, ~7px × 15px phones). A cell inside a quiet zone is dimmed, which reads as a dark box.
- Each block (headline, description paragraph, bullet list, buttons) gets its own box; each **row** of a box spans only the text lines beside it, so boxes wrap around ragged lines.
- Boxes are measured from the letters' ink (canvas font metrics), not line boxes, so the gap is even on all sides: ~14px target (`G = 14`), snapped to cells.
- Rows are 18px tall, so vertical gaps can only move in ~9px steps. To make top = bottom, the headline is nudged down (<1 row, `translateY`) and the later blocks are placed one shared distance `D` apart (searched 30–60px) chosen so their boxes also fit the rows. Gaps between blocks come out equal (~45px desktop).
- At least one row of field always runs between blocks.
- The buttons keep their place in this layout but get **no** box.
- Known limit, explained to the owner: top/bottom can't exactly equal left/right because of the 18px rows; they land within a few px. One offered but undone fix: tweak headline font size per width so it fits rows evenly.

**Demo** (`#demo`, right under the hero): Aurora Glass's hero animation, ported whole with every class, id and keyframe prefixed `ag-` (CSS block "demo (Aurora Glass's hero animation)"; script block of the same name). The section has no title or lede, and sits closer to the hero divider than other sections (`padding-top: clamp(64px, 7vw, 104px)`), with the same padding at the bottom, above the skin strip (which has no padding of its own); the section clips only sideways (`overflow:clip visible`) so the device shadows run on past its bottom instead of ending in a hard line. The Mac and iPhone keep Aurora's own arrangement (the Mac turned toward the left, the iPhone over its lower-right corner, both leaning toward the pointer) and sit on the right, the iPhone's right edge at the section's edge. The steps are one column: the **On Mac** / **On iPhone** headings above a vertical carousel of the loop's five stages, each with a second line and a tag for where it happens: Working… (Mac), Waiting for response (Mac → iPhone), You tap Allow (iPhone → Mac), Running tests… (Mac), Ready (Mac → iPhone). The current stage sits on top at full opacity with a border a step lighter than the others' grey rule (28% toward the text colour); the next ones follow, dimmer the further away (`data-d` 0–3, four in view, the last fading out). When the stage moves on, the top one slides up and out and the rest follow (`carShow`; the seven animation steps map to stages through `STAGE`), wrapping round. The section's heading, "Swap intuitively." (`.ag-title`, the site's h2 style with the scramble), is sized to exactly the list's width (the text is 7.276em, so font-size = list width / 7.276) and sits 56px above it on desktop (24px when stacked) and first in the section when stacked. Kinetic Mono's axolotl sits at the right end of the On Mac / On iPhone row and changes with the step (happy while working, waving while waiting, standing when ready), using the page's `#m-happy`, `#m-wait`, `#m-ready` images, standing on a soft oval shadow (`--ag-platform`: plum in light, magenta in dark). Both headings start lit. Clicking one (`.ag-cat-h`) dims the other heading (the picked one keeps its normal colour, no pink), puts that device in front without changing either one's size: the device coming forward slides out sideways and back, along x only (the Mac to the left, the iPhone to the right) and the layers swap at the far point (`data-front`, set by `setFront`; picking the Mac slides the iPhone just behind it, scaled and shifted so its outline on screen stays put; the 3D depth and perspective are in em so one set of numbers holds at every width), and puts a page-coloured veil over the other device (`data-focus` on `#ag-cats` and `#ag-stage`), without restarting the loop; when the loop comes back round to the step it was on, both are lit again. Tapping the lit heading again lights both straight away. Tapping the Mac or the iPhone picks it too (tapping the picked one keeps it for another loop). The veil is a `::after`, because opacity or a filter on a device pulls it out of the 3D scene. The column is 24rem wide; under 1040px of content width it goes under the devices. Type scales with the width (`container-type: inline-size` on the section's `.wrap`, 70em across); The owner tried other arrangements (Mac/steps/iPhone across, both devices turned right, the iPhone moved further out) and settled on this on 2026-10-16. On desktop the Mac runs to the content's right edge and the iPhone overhangs it into the page margin by 5% of the Mac's width (~32px), as in Aurora; when the section stacks, right padding brings it back inside. Sized like Aurora's (13px type at most, a ~610px Mac). Behind it runs Aurora's WebGL glow (`#ag-aurora`, the same shader changed to output light with alpha so Custom's paper and dot grid show through), faded at the section's top and bottom, drawn from the same loop as the tilt and only while on screen; `.ag-aurora-fallback` gradients stand in without WebGL. The Mac is Neon Signal's window (`.ag-mac*`, Neon's px / 13 in em): purple bar with a centred "skins — claude" title and a status pill (moved next to the lights, since the iPhone covers the right end; it turns magenta while waiting), the grid-and-scanline terminal, the "Welcome to Claude Code" box, the glowing permission box (option 1 turns green when Allow is tapped), and Neon's comet trace with bloom while Claude works. Aurora's usage bar, dim shade and Ready pill are gone. A tether (`#ag-tether`, an SVG behind both devices) hangs from the bottom centre of the Mac (dropping straight down first) to the bottom centre of the iPhone: a soft cable (`--ag-cable`) and Neon's glowing pulse, which runs Mac → iPhone when Claude stops to ask and when it's done, and iPhone → Mac when Allow is tapped. The script redraws it each frame from `.ag-anchor` points inside each device, so it follows the tilt and the swap slide. The iPhone is Neon Signal's: its layered frame, status bar, "Lostty" header with bell and plus, Connected count, filter chips and session cards with axolotls (`.ag-n-*`; the frame in em, the screen in cqw of itself so Neon's px values carry over). The lostty/skins card follows the Mac: it moves to the top as Waiting on You, its Allow / Don't allow row slides open, Allow is tapped, it works again, then turns Ready; cards reorder with a FLIP slide using offsetTop. Aurora's swipe to a terminal view on the phone is gone. The old Kinetic Mono demo (clickable card, Yes key, step buttons, mascot) is gone.

**Skin strip** (`#skin-strip`, right under the demo): two headings, "Unlock skins..." above the cards and "... by spending tokens." below them, staggered: on desktop the first starts the same distance in from the column's left edge as the second ends from its right edge (`--sk-inset: 10cqi`, ~116px at 1440); below 1040px of column, where the type grows to fill it, they sit flush left and flush right (both with the scramble, the same size as "Swap intuitively.": its `.skstrip-head` wrap is a size container with the same font-size rules as `.ag-title`), then a short edge-to-edge strip of skin cards (208×52px, 184×48 on phones; each shows only `❯ name`, no rarity line). No divider above it or below it (`.skstrip + .sec` drops the next section's dashed rule). The cards drift right to left (moved by script, one copy of the list per 110s; the track holds the list twice and wraps by half; each card's gap is its margin so the halves match), faded at both ends, and with the mouse (or keyboard focus) on it the speed eases down to a stop, then eases back up when it leaves (exponential, `TAU = 0.55`s, so ~1.5s either way; a click's leftover focus doesn't hold it). It only runs while on screen. Every card is dimmed (.36) except the one hovered; the worn skin keeps a ring in its own accent. Cards are built in script from `SKINS`, with a first **lostty** card (the site's own look, Neon's Mac colours) that takes the skin off. Tapping a card sets `data-skin` and `--sk-bg/fg/a1/a2` on the root (settled with the owner 2026-10-16: accents + the demo Mac change, backgrounds and theme stay; the lostty card is the way back; nothing is remembered). The CSS then makes `--magenta` the first accent and `--rose` the second, `--btn-bg` the accent with the skin's bg as text, `--magenta-ink` the accent mixed 62% toward the ink in light (the raw accent in dark). The demo Mac's colours are variables (`--mk-*` on `.ag-demo`, Neon's values by default), which a skin replaces with ones mixed from its colours; its grid gives way to the skin's texture (`.tex` layers in `.ag-mac-body`; the `.tex` rules are no longer scoped to `.pane`). The phone's magenta touches, the tether pulse and the trace follow `--mk-a1`. Script-drawn colours follow too: `wear()` calls `themeChanged()` (the hero field re-reads `--magenta`) and fires a `lostty-skin` event, on which Aurora's glow takes the accents (`uMag/uRose/uVio/uTeal` uniforms). Reduced motion: no drift, the strip scrolls by hand.

**Headings**: every section heading (and the Docs page titles) uses the hero title's type, Onest 700 with -.04em tracking, at its own size; the Docs `## ` subheads stay mono.

**Sections below the demo**: as in Kinetic Mono, minus the `~/lostty ❯ …` prompt lines (removed). Headings still do the brief scramble when they scroll into view.

**Footer logo**: same as the header (Onest "Lostty" plus the blinking `_`).

**Download page** (`#download`, a view like Docs)
- Stable: https://github.com/Lawliang/lostty/releases/latest/download/Lostty.dmg
- Beta: https://github.com/Lawliang/lostty/releases/download/beta/Lostty-Beta.dmg (fixed `beta` pre-release; each beta is tagged `vX.Y-beta.N`; beta replaces stable, shows as "Lostty Beta")
- Copy says macOS 14 or later. That's right for the app (deployment target 14.0); Docs' Getting Started says macOS 15 because building from source needs Xcode 26, matching the README.
- **Both links 404 until the first release**; beta work is on branch `lostty-beta`, the first release waits on a signing fix (per the session doing release work).

## Next task
None open. Last done: the skin strip (see "Skin strip" above).

## Settled with the owner (2026-10-15, on recommendation)
- Kept: the footer `❯ exit … [Process completed]`, the docs `LOSTTY(1)` man bar, the bullets' `❯` markers, and the hero button going to the Download page.
- The field starts even if measuring the hero boxes throws (`try { quietZone(); } catch …` in `resize`).

## Checking changes (`website/tools/`)

Headless Chrome scripts using the Playwright install in `../aheadly/node_modules` (machine-specific paths). Output PNGs go to `$OUT` or the system temp dir. Run them in the background with a time cap; they sometimes hang on exit.
- `anim.cjs <file>` — is the field animating after load (home, `#download`, `#docs`)? Prints script errors.
- `vgap2.cjs <file>` — gaps between hero blocks and where the buttons end vs. the hero height.
- `shot-noise.cjs <file>` — screenshots during the dense "noise" phase (where box edges are visible), desktop/phone, dark/light.
- `overlay.cjs <dbg-file>` — draws the quiet-zone rows in pink. Needs a debug copy that exposes them:
  `sed 's#      qz = rowsZ;#      qz = rowsZ; window.__z = { rows: rowsZ, cw: cw, chh: chh };#' website/custom.html > /tmp/dbg.html`
- `dl.cjs <file>` — Download page screenshots plus Home/Docs/Download switching.
- Always also run `node --check` on the extracted inline script after edits.

## Shared checkout
Other Claude sessions use this same working tree (iPhone app and release work). Their uncommitted files under `macos/` show up in `git status`; never stage them. Branch `website` also carries 8 commits of the Mac download/update work (already on `main`), which will merge in as duplicates.
