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

- Every change to Custom is its own commit on `website` (`git log --oneline -- website/custom.html`), so any earlier state can be restored with `git show <sha>:website/custom.html`. The artifact also keeps its own version history (version 61 at handoff).
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
- Headline (Onest 700, clamp 38–72px): "Finally, go touch some grass." / "with Lostty."
- Description: "A fast, modern multi-agent terminal CLI coding harness designed to pair with our native iPhone app, for builders **on the go**."
- Bullets (magenta `❯` markers):
  1. Install builds, view artifacts & simulators, & access your MCPs, remotely on your phone.
  2. Built-in caffeinate and auto-hotspot-switch designed for your Mac to keep running.
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

**Sections below the hero**: as in Kinetic Mono, minus the `~/lostty ❯ …` prompt lines (removed). Headings still do the brief scramble when they scroll into view.

**Download page** (`#download`, a view like Docs)
- Stable: https://github.com/Lawliang/lostty/releases/latest/download/Lostty.dmg
- Beta: https://github.com/Lawliang/lostty/releases/download/beta/Lostty-Beta.dmg (fixed `beta` pre-release; each beta is tagged `vX.Y-beta.N`; beta replaces stable, shows as "Lostty Beta")
- Copy says macOS 14 or later (from the release session). Docs' Getting Started still says macOS 15 (build from source) — the owner may want these to agree.
- **Both links 404 until the first release**; beta work is on branch `lostty-beta`, the first release waits on a signing fix (per the session doing release work).

## Open questions left with the owner
- Footer `❯ exit … [Process completed]`, docs `LOSTTY(1)` man bar, and the bullets' `❯` markers: keep or remove?
- Second headline line "with Lostty." is lowercase after a period — capitalize?
- First bullet has two `&` in a row ("artifacts & simulators, & access") — change the first to "and"?
- Footer logo still uses the old lowercase "lostty" type.
- Hero button now goes to the Download page instead of the install section — confirm.
- Safety improvement offered: start the field animation even if the box measurement throws (once, after a refresh, the owner saw the animation not start; it couldn't be reproduced in Chrome).

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
