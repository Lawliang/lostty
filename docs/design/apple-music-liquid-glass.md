# Apple Music's 2026 Liquid Glass look

Research done on 2026-10-22 for the canvas's + button (`macos/Sources/Features/Canvas/CanvasAddMenu.swift`, commit 6fd137ed1). Read this before doing the research again. It records what Apple published, what the icon looks like, the SwiftUI glass APIs, and how Lostty copied the look.

## What Apple published

- **When:** Apple announced the rebrand on **October 21, 2026**. The wordmark was previewed in September, on promotion for Apple Music Hall at Battersea Power Station in London. The new app icon first appeared in the iOS 27.2 and macOS 27.2 betas around October 13 (beta 3).
- **Rollout:** with **iOS 27.2 and macOS 27.2**. Apple's Apple Music web page switched over on announcement day.
- **Name of the idea:** "Made by Sound." It was made with TBWA\Media Arts Lab, Fred again.. and NEST Acoustics.
- **How it was made:** the logo was etched into the glass floor of a shallow tank of mineral oil, with a transparent cover over it. Notes from a short Fred again.. piece were played through a transducer, the oil rippled at the notes' frequencies, and the distortion was filmed entirely in camera. Too many notes, or notes too high, made the oil unreadable, so the sound and the image were tuned together. The same composition is the brand's new audio signature.
- **Color:** **red and pink are gone.** The brand and icon are black and white:
  - light mode: a black note on white
  - dark mode: a white note on black
  - some campaign stills still use pink

  Users mostly disliked the loss of red.
- **Wordmark:** the Apple logo plus "music" in **lowercase**, in a custom, heavier SF Pro.
- **Elsewhere in iOS 27.2's Music app:**
  - monochrome widgets
  - a revised tab bar color
  - updated Library styling
  - a larger play button on artist pages
  - a floating mini-player, which on Android 7.0 is no longer docked to the tab bar

  Apple has not published a Newsroom post or developer article about any of this.

## What the icon looks like

These notes come from Apple's published images (The Apple Post's hero image, and MacRumors' old-versus-new comparison).

- **Body:** a **clear glass squircle**, the app icon shape, almost colorless. The background shows through it, slightly bent.
- **Edge:** a **thin, bright rim** all the way round, like the lit edge of a glass slab.
- **Colored light:** the light **splits into color at two opposite corners only**, the **top right** and the **bottom left**:
  - each is an arc hugging the rim, not a fill
  - mostly **cyan into deep blue**, with a thin **warm orange or red fringe** on the outer edge, like the chromatic aberration of real glass
  - the other two corners stay clear
- **Glyph:** the familiar double eighth note, solid black and slightly heavier, with **no gradient and no glass of its own**. In dark mode it's white with a soft glow.
- **Background in the hero shots:** soft white-grey, with faint concentric ripples round the icon.
- **Motion in the films:** ripples cross the logo, which bends as if under moving liquid. The ripples are the theme across the whole identity.

## SwiftUI Liquid Glass APIs (macOS 26 / iOS 26)

These come from third-party write-ups, since Apple's developer site didn't come up in the searches. Check them against Apple's documentation before relying on the details.

- **`glassEffect(_:in:)`** puts Liquid Glass behind a view, in a shape. `.regular` is the standard glass, and `.tint(color)` tints it.
- **`.interactive()`** adds press feedback: a scale, a bounce and a shimmer. It's meant for primary floating controls, not every button. On iOS, the touch point also lights nearby glass.
- **`GlassEffectContainer(spacing:)`** groups several glass shapes, so they render efficiently and blend when closer than `spacing`.
- **`glassEffectID(_:in:)`**, with a shared `@Namespace` inside an animation, morphs glass from one shape to another. `glassEffectUnion` makes several views one glass shape.
- **`.buttonStyle(.glass)` and `.glassProminent`** give standard glass buttons.
- **Guidance:** put glass on the navigation and control layer, not on content. Don't stack glass on glass. Keep tint for primary actions.
- **A reported bug:** on iOS 26.1, a `Menu` inside a `GlassEffectContainer` can break the morph animation.
- **Availability:** Lostty deploys to macOS 14, so every glass call needs `if #available(macOS 26, *)` and a material fallback.

## How Lostty's + button copies it

All of this is in `CanvasAddMenu.swift`. The button is a 44pt circle, not a squircle, because it's a button and not an app icon.

| Apple's icon | Lostty's + button |
| --- | --- |
| Clear glass body | `glassEffect(.regular.tint(white or black at 35%).interactive(), in: Circle())` on macOS 26. Before 26, `.ultraThinMaterial` with a shadow. |
| Thin bright rim | `CanvasAddRim`: a 0.8pt `strokeBorder` with a linear gradient from white at 80% (95% on hover) at the top left, through 25% (8% in dark mode), to 60% (35% in dark mode). |
| Color at the top right and bottom left | `CanvasAddPrism`: two arcs as stops of one angular gradient round the center, clear elsewhere, so they hug any shape's edge. The gradient runs clockwise from the right, so 0.75 is the top. The **top right**, 0.77–0.99, goes clear → white → cyan → blue → indigo (0.35, 0.25, 0.95) → clear. The **bottom left**, 0.27–0.49, goes clear → ember (1, 0.45, 0.2) → white → cyan → blue → clear. Each arc is a 4pt blurred bloom (blur 2.5, 60% opacity in light mode, 90% in dark) under a sharp 2.2pt line, inset 2pt. In dark mode they use `.plusLighter`, so they glow. |
| Monochrome glyph | SF Symbol `plus`, 18pt bold: black in light mode, white with a 5pt white glow (55%) in dark mode. It turns 45° into × while the menu is open. The old website magenta was dropped, as Apple dropped red. |
| Light moving across glass | On hover the prism's gradient turns 38° (the shape stays put) and the rim brightens, with a spring of response 0.6 and damping 0.75. |
| Ripples | `CanvasAddRipple`: each click sends two 1.2pt rings, the second 0.14s later, from scale 1 to 1.36 while fading from 1 to 0 over 0.75s, using `keyframeAnimator`. |
| — | Reduce Motion turns off the hover turn and the ripples. Nothing animates at rest. |

Things learned while building it:
- `keyframeAnimator` is needed for the ripple. Values computed from an animated `@State` number are not interpolated.
- Real glass already draws its own shadow. A shadow over the whole button doubled it and shadowed the ripples, so the shadow lives only in the pre-macOS 26 fallback.
- A scratch render can't draw real Liquid Glass. Judge the glass body in the app; only the rim, prism and glyph can be checked outside it.
- `Circle().trim` can't draw the arcs on a capsule, so they became gradient stops. The circle looks the same either way.

## The pill above the button

The pill of what the + adds (New Terminal, New Ticket) is the same glass as a capsule, through `CanvasAddLitGlass`, which puts the glass, rim and prism on any shape:
- the glass body is the same, but without `.interactive()`: the pill's icons are the buttons, so the pill itself has no press feedback
- the rim and the two prism arcs are the same, at the capsule's top right and bottom left
- while the pointer is over the pill, its light turns and its rim brightens, as on the button
- the icons are monochrome, as the + is: black in light mode, white with a 4pt glow (45%) in dark mode
- the old material fill, hairline border and drop shadow are gone; the glass casts its own shadow, and only the pre-macOS 26 fallback draws one

## Sources

- [MacRumors: Apple Music's New Look Officially Announced](https://www.macrumors.com/2026/10/21/apple-music-new-look-announced/) (Oct 21)
- [MacRumors: iOS 27.2 Adds New Apple Music Icon](https://www.macrumors.com/2026/10/13/ios-27-2-apple-music-icon/) (Oct 13)
- [MacRumors: Apple Music Is Getting a New Logo](https://www.macrumors.com/2026/10/06/apple-music-is-getting-a-new-logo/) (Oct 6)
- [The Apple Post: Apple Music unveils major rebrand with new logo made by sound](https://www.theapplepost.com/2026/10/21/73511/apple-music-unveils-major-rebrand-with-new-logo-made-by-sound/). Its hero image is the best picture of the glass icon: https://www.theapplepost.com/wp-content/uploads/2026/10/AppleMusicRebrand2026.jpg
- [Engadget: There's a new Apple Music logo and it looks like ripples in water](https://www.engadget.com/2293262/theres-a-new-apple-music-logo-and-it-looks-like-ripples-in-water/)
- [Creative Boom: Apple Music's new logo was shaped by sound and mineral oil](https://www.creativeboom.com/news/apple-musics-new-logo-was-shaped-by-fred-again-and-a-bath-of-mineral-oil/)
- [Digital Trends: Apple Music just got a new logo](https://www.digitaltrends.com/home-theater/apple-music-just-got-a-new-logo-and-yeah-its-inspired-by-sound-and-liquid/)
- [iPhone in Canada: Apple Music's New Logo Was Built Using Sound Waves](https://www.iphoneincanada.ca/2026/10/21/apple-musics-new-logo-was-built-using-sound-waves/)
- [AppleInsider: Modernized Apple Music logo is now chunkier than ever](https://appleinsider.com/articles/26/10/06/modernized-apple-music-logo-is-now-chunkier-than-ever)
- [9to5Google: Apple Music 7.0 beta brings Liquid Glass redesign to Android](https://9to5google.com/2026/09/30/apple-music-7-0-redesign-liquid-glass/)
- [Donny Wals: Designing custom UI with Liquid Glass on iOS 26](https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/)
- Apple's "Made by Sound" film on YouTube, linked from MacRumors: https://www.youtube.com/watch?v=1XxNXkOHKZw. Its thumbnail shows the lowercase wordmark bending under ripples in a clear tank. The other video on that page, AjEK6dtyvQg, is an unrelated Apple TV video.
