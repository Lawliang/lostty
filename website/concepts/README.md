# Website concepts (drafts)

Five design directions for the Lostty website, each a single self-contained
HTML page with a landing page and a Docs view (`#docs`). They are drafts to
pick from and combine, not the site itself. Open any file in a browser.

| File | Direction | Published draft |
|---|---|---|
| `1-neon-signal.html` | Dark only, neon-arcade glow; the hero hands a permission prompt from the Mac to the iPhone | https://claude.ai/artifact/XonsET8b3oJ9phPa26fhpJ |
| `2-aurora-glass.html` | WebGL aurora, frosted glass, tilted devices, bento tiles with live demos; light and dark | https://claude.ai/artifact/5P4CS5pvwTFRQZSaiS6XW3 |
| `3-skin-shifter.html` | The page wears all twelve skins with animated textures; collectible boon cards | https://claude.ai/artifact/34Y46vrqv4ooe6xt54amYr |
| `4-handoff.html` | Light first, Apple-style scroll story: a pinned Mac and iPhone act out each fix | https://claude.ai/artifact/8kJMCvbFpxQuPpJZdYoTtU |
| `5-kinetic-mono.html` | Terminal grid as the design language; glyph-field hero; man-page docs with search | https://claude.ai/artifact/2gDLx5dDfdpUWw3H4E6AH5 |

`BRIEF.md` is the shared brief each concept was built from.

`4-handoff.html` is generated: edit the files in `handoff-build/` and run
`python3 website/concepts/handoff-build/gen.py`.

Skin colors in concepts 1 and 3 come from `SkinPresets.swift`; the other three
approximate them from `SKINS.md`.
