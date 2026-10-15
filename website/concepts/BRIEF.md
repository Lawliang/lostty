# Lostty website concept — shared brief

You are building ONE design concept (a self-contained HTML page) for Lostty's future website. Five agents build five
different directions in parallel; yours is described in your prompt. The owner will compare them and pick one; the
winner gets rebuilt in Astro later. So: make it look and move like the real thing, but it's a single HTML file.

## The ask, in the owner's words
"A modern, clean website for Lostty. It should feel technical, modern, and professional, but with smooth,
high-quality, and vibrant animations and colorways, like an extremely enhanced version of our lostty app."
The site is a landing page + docs.

## The product (read /Users/lawliang/projectrepos/lostty/README.md for the full copy — use real copy, no lorem)
Lostty — "Leave your desk, not your terminal." A fast, native Mac terminal (built on Ghostty's engine) with an
iPhone companion app, for people running coding agents (Claude Code, Codex). Every terminal keeps running on the
Mac; the phone shows which one needs you, and you answer right there. No Lostty server: the phone talks to the Mac
directly over SSH inside your own Tailscale network; the phone's SSH key never leaves the phone.
Four problems/fixes (README "Why Lostty Exists"):
1. The agent stopped and I didn't know -> sessions sorted into Waiting on you / Working / Ready / Idle; inbox under the bell.
2. My phone got a tiny useless Mac -> the phone app is a real terminal on the same session; smart keyboard (gap taps hit nearest key). Stay Awake: works lid-closed, hops to the iPhone hotspot.
3. Ten terminals, all the same black box -> skins: each project gets its own colors and texture; live "Editing App.swift" status + "✳ Working…" line; a soft glow traces the window while Claude works.
4. Starting anything meant going back to my desk -> tap + on the phone, pick a project folder, start Claude / Codex / shell and a model.
Built on Ghostty (credit Mitchell Hashimoto and the Ghostty contributors). MIT license. GitHub: https://github.com/Lawliang/lostty
Requirements: Mac on macOS 15+, iPhone on iOS 17+. Setup today: `git clone … && macos/setup.sh`, then `macos/install-phone.sh`, Tailscale on both, pair via Lostty → Phone Access… → Pair a Phone… and scan the QR code.

## Brand facts (from the app)
- Accent magenta `#E5199C`. Mascot: a chibi pink axolotl (head `#F7B2D8`, body `#EC97C6`, gills `#E5199C`, face ink `#3A1530`)
  whose eyes are a prompt: `>` and a blinking `—` cursor. States: waiting (waves, `—` blinks), ready, sleeping (idle), happy.
- Mascot SVG (1.8KB, inline it): /Users/lawliang/projectrepos/lostty/docs/superpowers/specs/assets/lostty-chibi-axolotl.svg
- Mascot PNGs (~30KB each, OK to embed as base64 data URIs): /Users/lawliang/projectrepos/lostty/images/lostty/mascot-{waiting-on-you,ready,sleeping,happy}.png
- Phone screenshot (205KB): /Users/lawliang/projectrepos/lostty/images/lostty/phone-terminals.png (dark UI; session cards tinted by skin:
  green "Waiting on You", purple "Working… Incubating… (3m 52s)", beige "Ready", dark "Idle"). Embedding is optional; a coded
  recreation of the phone/Mac UI usually animates better.
- Twelve skins (SKINS.md): neon-arcade (magenta+cyan on dark purple, legendary), sunset-drive (orange+pink on plum, scanlines),
  mint-protocol (neon green+yellow on dark teal), deep-dive (cyan+purple on dark blue), lava-rush (orange+yellow on brown, diagonal),
  bubble-pop (hot pink+yellow on purple, sparkles), thunderhead (gold on storm navy, lightning, Zeus), undertow (sea-foam on abyssal
  teal, Poseidon), bloodrite (battle red on dried blood, Ares), heartsease (rose on dusk rose, petals, Aphrodite), silverbow
  (hunter green on night forest, starfield, Artemis), stormsurge (gold lightning over teal swells, duo). Rarity labels: common,
  rare, epic, heroic, legendary, duo.

## What the page must contain
1. Nav (logo + mascot, Features, Skins, Docs, GitHub) — sticky.
2. Hero that states the thesis with a live, animated moment from the product (e.g. a Mac terminal where Claude stops on a
   permission prompt and the phone lights up "Waiting on you", you tap Allow, it carries on).
3. The four problems/fixes.
4. Skins showcase (interactive: hover/click re-skins something).
5. How it works / privacy (Mac ⇄ Tailscale ⇄ iPhone, no server).
6. Built on Ghostty credit.
7. Getting started CTA (requirements + the clone command with a working copy button).
8. A DOCS view: the site is landing + docs, so include a docs page layout — left sidebar nav (Getting Started, Phone Access,
   Skins, Manual Mac setup, Contributing), an article with real Getting Started content (steps, code blocks, a callout), and an
   on-this-page TOC. Make it reachable from the nav (e.g. a section at the bottom, or toggle between "Home" and "Docs" views
   in-page with a bare #docs hash). It must share the visual system with the landing page.
9. Footer.

## Hard technical rules (the Artifact page contract — follow exactly)
- FIRST load the `artifact-design` skill (Skill tool) and follow its page contract and design guidance. Also load
  `frontend-design:frontend-design` for direction.
- Write content only: no <!doctype>, <html>, <head>, <body> tags. Start the file with <title>…</title>,
  <meta name="claude:viewport-fit-sides" content="cover">, then <style>.
- Scripts only from cdnjs.cloudflare.com / cdn.jsdelivr.net/npm / unpkg.com, pinned exact versions (e.g. GSAP 3.12.5 from cdnjs is fine).
  Fonts only via Google Fonts <link>. All images inline (SVG or data: URIs). No other network.
- Must work at ~400px phone width with no horizontal scroll; side gutter `padding-left: max(16px, env(safe-area-inset-left, 0px))`
  and same for right. Sticky header uses `top: env(safe-area-inset-top, 0px)`.
- Colors as tokens on :root. A deliberately dark-only look is allowed (then set color-scheme: dark and explicit body
  background); otherwise implement both themes per the contract.
- Everything readable is visible at rest — never leave content at opacity:0 waiting for a scroll observer. Respect
  prefers-reduced-motion. No alert/confirm/prompt. Copy button uses navigator.clipboard inside the click handler with a fallback.
- Avoid the AI-default looks (Inter/Space Grotesk as the safe face, purple-to-blue gradient on white, emoji section markers, everything centered).
- Animations: smooth (transform/opacity, 60fps), vibrant, high quality. One or two orchestrated hero moments beat scattered effects.
- Keep the file under ~1.5MB.

## Deliverable
Write the page to the exact path given in your prompt. Do NOT publish it (the lead publishes all five). Do not touch the repo.
Before finishing, sanity-check the file: balanced tags, script parses (e.g. extract inline JS and run `node --check`), no
forbidden hosts. Then reply with: the file path, a 2-sentence description of the direction, and anything unfinished.
- Note: the mascot SVG has a dark background <rect> as its first child — drop it when inlining.
