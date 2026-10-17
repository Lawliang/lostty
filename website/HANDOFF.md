# Lostty website — handoff

Last updated 2026-10-15. Branch: `website`. Everything below is committed.

## Where things are

| What | File | Published (private, owner only) |
|---|---|---|
| **Custom** — the design we're building | `website/custom.html` | https://claude.ai/artifact/4MNPpJ7EaKYb3seA4vJ5bn |
| Concept 1 · Neon Signal | `website/concepts/1-neon-signal.html` | https://claude.ai/artifact/XonsET8b3oJ9phPa26fhpJ |
| Concept 2 · Aurora Glass | `website/concepts/2-aurora-glass.html` | https://claude.ai/artifact/5P4CS5pvwTFRQZSaiS6XW3 |
| Concept 3 · Skin Shifter | `website/concepts/3-skin-shifter.html` | https://claude.ai/artifact/34Y46vrqv4ooe6xt54amYr |
| Concept 4 · Handoff | `website/concepts/4-handoff.html` (built by `concepts/handoff-build/gen.py`) | https://claude.ai/artifact/8kJMCvbFpxQuPpJZdYoTtU |
| Concept 5 · Kinetic Mono | `website/concepts/5-kinetic-mono.html` | https://claude.ai/artifact/2gDLx5dDfdpUWw3H4E6AH5 |

- Every change to Custom is its own commit on `website` (`git log --oneline -- website/custom.html`), so any earlier state can be restored with `git show <sha>:website/custom.html`. The artifact also keeps its own version history (version 70 at the last handoff update).
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
- Description (JetBrains Mono 16px): "A Mac-native terminal-based coding harness that supports multi-agent orchestration, designed to sync with our iPhone app" then, on its own line, "— for serious builders **on the go**."
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

**Demo** (`#demo`, right under the hero): Aurora Glass's hero animation, ported whole with every class, id and keyframe prefixed `ag-` (CSS block "demo (Aurora Glass's hero animation)"; script block of the same name). The section has no title or lede, and sits closer to the hero divider than other sections (`padding-top: clamp(48px, 5vw, 72px)`). The Mac and iPhone keep Aurora's own arrangement (the Mac turned toward the left, the iPhone over its lower-right corner, both leaning toward the pointer) and sit on the right, the iPhone's right edge at the section's edge. Two step lists sit side by side on the left, flush with the section's left edge: **On Mac** (Claude works / Stops to ask / Carries on / Ready) and **On iPhone** (Shows it working / Puts it first / You tap Yes / Back in your pocket); both highlight the current step together, as Kinetic Mono's step boxes (magenta edge on the current one), both columns the same width; the numbers sit in one shared column on the left as magenta circles with white numerals, lined up with each row through CSS subgrid. The section's heading, "Swap intuitively." (`.ag-title`, the site's h2 style with the scramble), sits above the lists on desktop and first in the section when stacked. Kinetic Mono's axolotl sits centred above both lists and changes with the step (happy while working, waving while waiting, standing when ready), using the page's `#m-happy`, `#m-wait`, `#m-ready` images, standing on a soft oval shadow (`--ag-platform`: plum in light, magenta in dark). Both start lit. Clicking a category's heading (`.ag-cat-h`) lights only that list, puts a page-coloured veil over the other device and pushes it back (`data-focus` on `#ag-cats` and `#ag-stage`), without restarting the loop; when the loop comes back round to the step it was on, both are lit again. Tapping the lit heading again lights both straight away. The veil is a `::after`, because opacity or a filter on a device pulls it out of the 3D scene. The lists fill the space left of the devices (two columns sized to their text, 14px apart like the circles and the boxes, Onest 19px headings and 17px steps). Under 1040px of content width they go under the devices, still side by side. Type scales with the width (`container-type: inline-size` on the section's `.wrap`, 70em across); under 640px the steps go back to a row under the devices. The owner tried other arrangements (Mac/steps/iPhone across, both devices turned right, the iPhone moved further out) and settled on this on 2026-10-16. Sized like Aurora's (13px type at most, a ~610px Mac). Behind it runs Aurora's WebGL glow (`#ag-aurora`, the same shader changed to output light with alpha so Custom's paper and dot grid show through), faded at the section's top and bottom, drawn from the same loop as the tilt and only while on screen; `.ag-aurora-fallback` gradients stand in without WebGL. The old Kinetic Mono demo (clickable card, Yes key, step buttons, mascot) is gone.

**Headings**: every section heading (and the Docs page titles) uses the hero title's type, Onest 700 with -.04em tracking, at its own size; the Docs `## ` subheads stay mono.

**Sections below the demo**: as in Kinetic Mono, minus the `~/lostty ❯ …` prompt lines (removed). Headings still do the brief scramble when they scroll into view.

**Footer logo**: same as the header (Onest "Lostty" plus the blinking `_`).

**Download page** (`#download`, a view like Docs)
- Stable: https://github.com/Lawliang/lostty/releases/latest/download/Lostty.dmg
- Beta: https://github.com/Lawliang/lostty/releases/download/beta/Lostty-Beta.dmg (fixed `beta` pre-release; each beta is tagged `vX.Y-beta.N`; beta replaces stable, shows as "Lostty Beta")
- Copy says macOS 14 or later. That's right for the app (deployment target 14.0); Docs' Getting Started says macOS 15 because building from source needs Xcode 26, matching the README.
- **Both links 404 until the first release**; beta work is on branch `lostty-beta`, the first release waits on a signing fix (per the session doing release work).

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
