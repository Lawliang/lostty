#!/usr/bin/env python3
"""Writes an iPhone app's over-the-air install page: Lostty's (ship-phone.sh),
and any other app's (the install-ios-build skill's ship-ios.sh), so every
app's page looks the same but for its name, accent color and the picture on
top (Lostty's axolotl, else the app's icon).

With --build, records that build (its manifest and info-<build>.json) first.
Then it drops all but the newest three builds and rewrites index.html and
latest.json from the builds left, so running it with no --build just
redraws the page.
"""

import argparse
import datetime
import html
import json
import pathlib
import re

KEEP = 3


def main():
    args = parse_args()
    www = pathlib.Path(args.www)
    if args.build:
        record(www, args)
    builds = prune(www, args.prefix)
    if builds:
        write_page(www, args, builds)
        write_latest(www, args.url, builds[0])


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("www")
    p.add_argument("url")
    p.add_argument("bundle")
    p.add_argument("--build")
    p.add_argument("--commit", default="")
    p.add_argument("--version", default="")
    p.add_argument("--branch", default="")
    p.add_argument("--terminal", default="")
    p.add_argument("--note", action="append", default=[])
    p.add_argument("--name", default="Lostty", help="the app's name, on the page and in iOS's prompt")
    p.add_argument("--prefix", help="its builds are <prefix>-<build>.ipa (default: the name)")
    p.add_argument("--accent", default="#e5199c", help="#rrggbb")
    p.add_argument("--accent-from", help="an AccentColor.colorset/Contents.json to take it from")
    p.add_argument("--mascot", action="store_true", help="Lostty's axolotl on top, not the app's icon")
    args = p.parse_args()
    args.prefix = args.prefix or args.name
    if args.accent_from:
        args.accent = colorset_hex(pathlib.Path(args.accent_from)) or args.accent
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", args.accent):
        p.error(f"--accent wants #rrggbb, not {args.accent}")
    return args


def colorset_hex(path):
    """An asset catalog color's light (or only) value as #rrggbb; None when
    it can't be read."""
    try:
        colors = json.loads(path.read_text())["colors"]
        color = next(c for c in colors if not c.get("appearances"))["color"]["components"]
        def channel(value):
            value = str(value)
            if value.startswith("0x"):
                return int(value, 16)
            return round(float(value) * 255) if "." in value else int(value)
        return "#" + "".join(f"{channel(color[k]):02x}" for k in ("red", "green", "blue"))
    except (OSError, KeyError, StopIteration, ValueError):
        return None


def record(www, args):
    commit, _, dirty = args.commit.partition("-")
    info = {
        "build": args.build,
        "version": args.version,
        "commit": commit,
        "dirty": dirty == "dirty",
        "branch": args.branch,
        "terminal": terminal_title(args.terminal),
        "built": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "notes": args.note,
    }
    (www / f"info-{args.build}.json").write_text(json.dumps(info, indent=2) + "\n")
    (www / f"manifest-{args.build}.plist").write_text(manifest(args, args.build, www))


def terminal_title(title):
    """Claude Code starts its title with a status glyph ("✳ Fix the bug")."""
    return title.lstrip(" ✳✶✻✽✢·⠀⠁⠂⠄⡀⢀⠠⠐⠈").strip()


def manifest(args, build, www):
    url = args.url
    # The icon iOS shows while installing, when the page has one.
    icons = "".join(f"""
    <dict><key>kind</key><string>{kind}</string>
      <key>url</key><string>{url}/{file}</string></dict>"""
        for kind, file in (("display-image", "icon-57.png"), ("full-size-image", "icon-512.png"))
        if (www / file).exists())
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
  <key>assets</key><array>
    <dict><key>kind</key><string>software-package</string>
      <key>url</key><string>{url}/{args.prefix}-{build}.ipa</string></dict>{icons}
  </array>
  <key>metadata</key><dict>
    <key>bundle-identifier</key><string>{html.escape(args.bundle)}</string>
    <key>bundle-version</key><string>{html.escape(args.version)}</string>
    <key>kind</key><string>software</string>
    <key>title</key><string>{html.escape(args.name)}</string>
  </dict>
</dict></array></dict></plist>
"""


def prune(www, prefix):
    """Keeps the newest builds and returns their info, newest first."""
    ipas = sorted(www.glob(f"{prefix}-*.ipa"), reverse=True)
    for old in ipas[KEEP:]:
        build = old.stem.removeprefix(f"{prefix}-")
        for path in (old, www / f"manifest-{build}.plist", www / f"info-{build}.json"):
            path.unlink(missing_ok=True)
    return [info(www, ipa.stem.removeprefix(f"{prefix}-")) for ipa in ipas[:KEEP]]


def info(www, build):
    path = www / f"info-{build}.json"
    if path.exists():
        return json.loads(path.read_text())
    # Builds from before info files existed: the build number is the time.
    when = datetime.datetime.strptime(build[:12], "%Y%m%d%H%M").astimezone()
    return {"build": build, "version": "", "commit": "", "dirty": False,
            "built": when.isoformat(timespec="seconds"), "notes": []}


def when_text(built):
    """A fallback for when the page's script doesn't run."""
    when = datetime.datetime.fromisoformat(built)
    return when.strftime("%b %-d, %-I:%M %p")


def install_link(url, build):
    return f"itms-services://?action=download-manifest&amp;url={url}/manifest-{build}.plist"


# Feather-style glyphs, drawn in the text's colour.
BRANCH_ICON = ('<svg viewBox="0 0 24 24"><circle cx="6" cy="5" r="2.2"/><circle cx="6" cy="19" r="2.2"/>'
               '<circle cx="18" cy="7" r="2.2"/><path d="M6 7.2v9.6M18 9.2c0 5-12 3-12 7.6"/></svg>')
CHEVRON_ICON = '<svg class="chevron" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>'
CLOCK_ICON = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>'


def task(b, indent):
    """The title of the terminal it was built from."""
    if not b.get("terminal"):
        return ""
    return f'\n{indent}<p class="task">{html.escape(b["terminal"])}</p>'


def chips(b, indent, row=False):
    """Its branch, commit and when; a row already says the branch and when."""
    parts = []
    if b.get("branch") and not row:
        parts.append(f'{BRANCH_ICON}{html.escape(b["branch"])}')
    if b["commit"]:
        edits = ' <span class="edits">+ changes</span>' if b["dirty"] else ""
        parts.append(f'<code>{html.escape(b["commit"][:7])}</code>{edits}')
    if not row:
        parts.append(f'{CLOCK_ICON}<time data-built="{b["built"]}" data-short>{when_text(b["built"])}</time>')
    if not parts:
        return ""
    spans = "".join(f'\n{indent}  <span class="chip">{c}</span>' for c in parts)
    return f'\n{indent}<div class="chips">{spans}\n{indent}</div>'


def note_list(b, indent):
    if not b["notes"]:
        return ""
    items = "".join(f"<li>{html.escape(n)}</li>" for n in b["notes"])
    return f'\n{indent}<ul class="notes">{items}</ul>'


def history_row(url, b, current):
    """A row that opens to the same things the latest build shows, smaller.
    The latest build's row says so where the others offer to install."""
    inner = "          "
    button = ('<span class="install small current">Current</span>' if current
              else f'<a class="install small" href="{install_link(url, b["build"])}">Install this build</a>')
    return f"""
      <li><details>
        <summary>
          <div>
            <time data-built="{b['built']}">{when_text(b['built'])}</time>
            <span class="meta">{history_meta(b)}</span>
          </div>
          {CHEVRON_ICON}
        </summary>
        <div class="more">{task(b, inner)}{chips(b, inner, row=True)}{note_list(b, inner)}
          {button}
        </div>
      </details></li>"""


def write_page(www, args, builds):
    url, name, accent = args.url, html.escape(args.name), args.accent
    latest = builds[0]
    notes = note_list(latest, "    ")
    notes_section = f"""
  <section class="card">
    <h2>What’s new</h2>
{notes}
  </section>""" if notes else ""
    rows = "".join(history_row(url, b, b is latest) for b in builds)
    history_section = f"""
  <section class="card">
    <h2>Build history</h2>
    <ul class="builds">{rows}
    </ul>
  </section>"""
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark">
<title>{name}</title>
<link rel="apple-touch-icon" href="icon-180.png">
<style>
  /* LosttyTheme's colors: the page is always dark, like the app, in the
     app's own accent. */
  :root {{
    --bg: #0c0b0e; --surface: #17151b; --hairline: #2c2833;
    --text: #f4f1f6; --text-2: #a39caa; --accent: {accent};
    --accent-soft: {accent}24; --accent-glow: {accent}38;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; background: var(--bg); color: var(--text); overflow-x: hidden;
    font: 17px/1.4 -apple-system, system-ui, sans-serif;
    -webkit-text-size-adjust: 100%;
  }}
  main {{
    max-width: 440px; margin: 0 auto;
    padding: max(56px, env(safe-area-inset-top)) 16px max(32px, env(safe-area-inset-bottom));
  }}
  header {{ text-align: center; margin-bottom: 28px; }}
  /* Lostty's Axolotl in its .ready pose, or the app's icon, and losttyGlow
     behind it. */
  .mascot {{ position: relative; width: 140px; height: 140px; margin: 0 auto 12px; }}
  .mascot::before {{
    content: ""; position: absolute; left: 50%; top: 50%; width: 330px; height: 330px;
    transform: translate(-50%, -50%); pointer-events: none;
    background: radial-gradient(closest-side, var(--accent-glow), transparent);
  }}
  .mascot svg {{ position: relative; display: block; width: 100%; height: 100%; }}
  .mascot.icon {{ display: flex; align-items: center; justify-content: center; }}
  .mascot.icon img, .mascot .letter {{
    position: relative; width: 104px; height: 104px; border-radius: 23px;
    box-shadow: 0 0 0 0.5px #ffffff1f, 0 10px 30px #00000080;
  }}
  .mascot .letter {{
    display: flex; align-items: center; justify-content: center;
    background: var(--accent); color: #fff; font-size: 52px; font-weight: 700;
  }}
  .tail {{
    transform-box: view-box; transform-origin: 61px 80px;
    animation: wag 0.45s ease-in-out infinite alternate;
  }}
  @keyframes wag {{ from {{ transform: rotate(-14deg); }} to {{ transform: rotate(14deg); }} }}
  @media (prefers-reduced-motion: reduce) {{ .tail {{ animation: none; }} }}
  h1 {{ font-size: 28px; font-weight: 700; letter-spacing: -0.01em; margin: 0; }}
  .task {{
    margin: 6px auto 0; max-width: 340px; color: var(--text-2); font-size: 15px;
    display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
  }}
  .chips {{ display: flex; flex-wrap: wrap; justify-content: center; gap: 8px; margin-top: 14px; }}
  .chip {{
    display: inline-flex; align-items: center; gap: 6px; padding: 5px 11px;
    border-radius: 999px; background: var(--surface); border: 0.5px solid var(--hairline);
    color: var(--text-2); font-size: 13px; line-height: 18px; white-space: nowrap;
  }}
  .chip svg {{
    width: 13px; height: 13px; flex: none; fill: none; stroke: currentColor;
    stroke-width: 2; stroke-linecap: round; stroke-linejoin: round;
  }}
  .chip code {{ font: 13px ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--text); }}
  .edits {{ color: var(--accent); }}
  .install {{
    display: block; width: 100%; max-width: 280px; margin: 24px auto 0;
    padding: 14px 20px; border-radius: 14px; background: var(--accent);
    color: #fff; text-align: center; font-weight: 600; text-decoration: none;
  }}
  .install:active {{ opacity: 0.8; }}
  .card {{
    background: var(--surface); border: 0.5px solid var(--hairline);
    border-radius: 16px; padding: 16px; margin-top: 16px;
  }}
  h2 {{
    font-size: 13px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em;
    color: var(--text-2); margin: 0 0 10px;
  }}
  ul {{ margin: 0; padding: 0; list-style: none; }}
  .notes li {{ position: relative; padding-left: 18px; }}
  .notes li + li {{ margin-top: 8px; }}
  .notes li::before {{
    content: ""; position: absolute; left: 2px; top: 0.6em;
    width: 6px; height: 6px; border-radius: 50%; background: var(--accent);
  }}
  .builds > li + li {{ border-top: 0.5px solid var(--hairline); margin-top: 10px; padding-top: 10px; }}
  .builds summary {{
    display: flex; align-items: center; justify-content: space-between; gap: 12px;
    list-style: none; cursor: pointer; -webkit-tap-highlight-color: transparent;
  }}
  .builds summary::-webkit-details-marker {{ display: none; }}
  .meta {{ display: block; color: var(--text-2); font-size: 13px; }}
  .chevron {{
    width: 16px; height: 16px; flex: none; fill: none; stroke: var(--text-2);
    stroke-width: 2.4; stroke-linecap: round; stroke-linejoin: round; transition: transform 0.2s;
  }}
  details[open] .chevron {{ transform: rotate(90deg); }}
  /* The latest build's header, condensed. */
  .more {{ padding: 4px 0 2px; }}
  .more .task {{ margin: 6px 0 0; max-width: none; font-size: 14px; }}
  .more .chips {{ justify-content: flex-start; margin-top: 10px; }}
  .more .notes {{ margin-top: 12px; font-size: 15px; }}
  .more .notes li + li {{ margin-top: 4px; }}
  /* Second to the latest build's button: tinted, not filled. */
  .install.small {{
    max-width: none; margin-top: 14px; padding: 10px 16px; border-radius: 12px; font-size: 15px;
    background: var(--accent-soft); color: var(--accent);
  }}
  .install.current {{ background: var(--hairline); color: var(--text-2); }}
{STARTED_CSS}</style></head>
<body><main>
  <header>
    {hero(args, www)}
    <h1>{name}</h1>
    {(task(latest, "    ") + chips(latest, "    ")).lstrip()}
    <a class="install" href="{install_link(url, latest['build'])}">Install</a>
  </header>{notes_section}{history_section}
</main>{STARTED_HTML.replace("{NAME}", name)}
<script>
  // "Today at 1:43 PM" reads better than a date, but only the phone knows
  // what today is.
  const day = d => new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const today = day(new Date());
  for (const el of document.querySelectorAll("time[data-built]")) {{
    const built = new Date(el.dataset.built);
    const days = Math.round((today - day(built)) / 86400000);
    const time = built.toLocaleTimeString([], {{ hour: "numeric", minute: "2-digit" }});
    const date = days === 0 ? "today" : days === 1 ? "yesterday"
      : built.toLocaleDateString([], {{ month: "short", day: "numeric" }});
    // Short, in the header's chip: the time today, else just the day.
    const text = "short" in el.dataset ? (days === 0 ? time : date) : `${{date}} at ${{time}}`;
    el.textContent = text[0].toUpperCase() + text.slice(1);
  }}
{STARTED_JS}</script>
</body></html>
"""
    (www / "index.html").write_text(page)


# After a tap on Install: the page clears, the button swirls into a circle
# with a check, and a word on where to watch. iOS asks to confirm the install
# in its own prompt, which the page can't see, so it keeps a way back.
STARTED_CSS = """  .ghost {
    position: fixed; z-index: 2; display: flex; align-items: center; justify-content: center;
    background: var(--accent); color: #fff; font-weight: 600; overflow: hidden;
    box-shadow: 0 0 0 0 transparent;
  }
  .ghost svg {
    position: absolute; width: 48px; height: 48px; fill: none; stroke: #fff;
    stroke-width: 3.2; stroke-linecap: round; stroke-linejoin: round;
    stroke-dasharray: 40; stroke-dashoffset: 40;
  }
  .ring {
    position: fixed; z-index: 1; border-radius: 50%; border: 2px solid var(--accent);
    opacity: 0; pointer-events: none;
  }
  .started {
    position: fixed; left: 0; right: 0; z-index: 2; padding: 0 32px; text-align: center;
    opacity: 0; pointer-events: none;
  }
  .started.shown { pointer-events: auto; }
  .started h2 {
    font-size: 24px; font-weight: 700; letter-spacing: -0.01em; text-transform: none;
    color: var(--text); margin: 0 0 8px;
  }
  .started p { color: var(--text-2); margin: 0 auto; max-width: 300px; }
  .started button {
    margin-top: 28px; padding: 8px 14px; border: 0; border-radius: 999px;
    background: none; color: var(--text-2); font: 15px -apple-system, system-ui, sans-serif;
  }
"""

STARTED_HTML = """
<div class="started" aria-live="polite">
  <h2>{NAME} is on its way</h2>
  <p>Head to your Home Screen: its icon fills in as it downloads.</p>
  <button type="button">Didn&rsquo;t start? Back to the page</button>
</div>"""

STARTED_JS = """  // Tapping Install opens iOS's own prompt; behind it, this plays.
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const started = document.querySelector(".started");
  const main = document.querySelector("main");
  const accent = getComputedStyle(document.documentElement).getPropertyValue("--accent").trim();
  let pieces = [];
  for (const link of document.querySelectorAll('a.install[href^="itms-services"]')) {
    link.addEventListener("click", () => play(link));
  }
  started.querySelector("button").addEventListener("click", rewind);

  function play(link) {
    if (pieces.length) return;
    const from = link.getBoundingClientRect();
    const size = 112;
    const x = innerWidth / 2 - size / 2;
    const y = Math.min(innerHeight * 0.36, innerHeight / 2 - 120) - size / 2;
    const ghost = document.createElement("div");
    ghost.className = "ghost";
    ghost.innerHTML = '<span>' + link.textContent + '</span><svg viewBox="0 0 48 48"><path d="M14 25l7 7 14-15"/></svg>';
    Object.assign(ghost.style, {
      left: from.left + "px", top: from.top + "px",
      width: from.width + "px", height: from.height + "px",
      borderRadius: getComputedStyle(link).borderRadius,
    });
    const ring = document.createElement("div");
    ring.className = "ring";
    Object.assign(ring.style, { left: x + "px", top: y + "px", width: size + "px", height: size + "px" });
    document.body.append(ring, ghost);
    pieces = [ghost, ring];
    link.style.visibility = "hidden";
    started.style.top = (y + size + 32) + "px";

    const slow = still ? 0 : 1;
    main.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "scale(0.97)" }],
      { duration: 300, easing: "ease-out", fill: "forwards" });
    main.style.pointerEvents = "none";
    ghost.querySelector("span").animate([{ opacity: 1 }, { opacity: 0 }],
      { duration: 150, delay: 200 * slow, fill: "forwards" });
    // Round and round, into a circle in the middle.
    ghost.animate([
      { left: from.left + "px", top: from.top + "px", width: from.width + "px",
        height: from.height + "px", borderRadius: ghost.style.borderRadius, transform: "rotate(0)" },
      { offset: 0.5, borderRadius: "36px", transform: "rotate(240deg)" },
      { left: x + "px", top: y + "px", width: size + "px", height: size + "px",
        borderRadius: size / 2 + "px", transform: "rotate(360deg)" },
    ], { duration: 900 * slow, delay: 250 * slow, easing: "cubic-bezier(.65,0,.25,1)", fill: "forwards" });
    const settled = 1150 * slow;
    ghost.querySelector("path").animate([{ strokeDashoffset: 40 }, { strokeDashoffset: 0 }],
      { duration: 350, delay: settled, easing: "ease-out", fill: "forwards" });
    ghost.animate([
      { boxShadow: "0 0 0 0 " + accent + "00", transform: "rotate(360deg) scale(1)" },
      { offset: 0.4, boxShadow: "0 0 48px 8px " + accent + "66", transform: "rotate(360deg) scale(1.08)" },
      { boxShadow: "0 0 40px 4px " + accent + "40", transform: "rotate(360deg) scale(1)" },
    ], { duration: 600 * slow || 1, delay: settled, easing: "ease-out", fill: "forwards", composite: "replace" });
    if (!still) {
      ring.animate([{ opacity: 0.8, transform: "scale(1)" }, { opacity: 0, transform: "scale(1.9)" }],
        { duration: 800, delay: settled + 100, easing: "ease-out", fill: "forwards" });
    }
    started.animate([{ opacity: 0, transform: "translateY(10px)" }, { opacity: 1, transform: "none" }],
      { duration: 450, delay: settled + 250 * slow, easing: "ease-out", fill: "forwards" });
    started.classList.add("shown");
  }

  // Back to the page as it was: iOS's prompt was cancelled, say.
  function rewind() {
    for (const piece of pieces) piece.remove();
    pieces = [];
    for (const link of document.querySelectorAll("a.install")) link.style.visibility = "";
    for (const animation of [...main.getAnimations(), ...started.getAnimations()]) animation.cancel();
    main.style.pointerEvents = "";
    started.classList.remove("shown");
  }
"""


def hero(args, www):
    """What sits on top: Lostty's axolotl, else the app's icon, else its
    initial on the accent."""
    if args.mascot:
        return f'<div class="mascot">{MASCOT}</div>'
    if (www / "icon-180.png").exists():
        return '<div class="mascot icon"><img src="icon-180.png" alt=""></div>'
    return f'<div class="mascot icon"><span class="letter">{html.escape(args.name[:1].upper())}</span></div>'


def history_meta(b):
    """"Build 202610131331 · skins"."""
    meta = f"Build {b['build']}"
    if b.get("branch"):
        meta += f" · {html.escape(b['branch'])}"
    return meta


# Axolotl.swift's drawing (AxolotlShapes.swift), in its 100-unit box.
MASCOT = """<svg viewBox="0 0 100 100" aria-hidden="true">
      <path class="tail" fill="#ec97c6" d="M60 82C70 86 80 84 84 76C86 72 82 70 80 73C77 78 70 79 63 76Z"/>
      <ellipse fill="#ec97c6" cx="50" cy="76" rx="15" ry="12"/>
      <ellipse fill="#f7b2d8" cx="50" cy="79" rx="8" ry="6"/>
      <g fill="#f7b2d8">
        <ellipse cx="39" cy="80" rx="4.2" ry="3.2"/><ellipse cx="61" cy="80" rx="4.2" ry="3.2"/>
        <ellipse cx="43" cy="88" rx="5" ry="3"/><ellipse cx="57" cy="88" rx="5" ry="3"/>
      </g>
      <g fill="#e5199c">
        <ellipse cx="14" cy="21" rx="9" ry="4.6" transform="rotate(-42 14 21)"/>
        <ellipse cx="9" cy="34" rx="9" ry="4.6" transform="rotate(-12 9 34)"/>
        <ellipse cx="11" cy="47" rx="8.5" ry="4.3" transform="rotate(18 11 47)"/>
        <ellipse cx="86" cy="21" rx="9" ry="4.6" transform="rotate(42 86 21)"/>
        <ellipse cx="91" cy="34" rx="9" ry="4.6" transform="rotate(12 91 34)"/>
        <ellipse cx="89" cy="47" rx="8.5" ry="4.3" transform="rotate(-18 89 47)"/>
      </g>
      <path fill="#f7b2d8" d="M50 15C76.4 15 83 26.7 83 42.3C83 60.5 69.8 67 50 67C30.2 67 17 60.5 17 42.3C17 26.7 23.6 15 50 15Z"/>
      <ellipse fill="#fff" fill-opacity="0.35" cx="34" cy="24" rx="7" ry="3.2" transform="rotate(-18 34 24)"/>
      <g fill="#e5199c" fill-opacity="0.45">
        <ellipse cx="26" cy="55" rx="5" ry="3"/><ellipse cx="75" cy="55" rx="5" ry="3"/>
      </g>
      <g fill="none" stroke="#3a1530" stroke-linecap="round" stroke-linejoin="round">
        <path stroke-width="4.4" d="M33 36L42 43L33 50M56 43L68 43"/>
        <path stroke-width="2.4" d="M46 53Q48 56 50 53.5Q52 56 54 53"/>
      </g>
    </svg>"""


def write_latest(www, url, latest):
    # For the app's "new build" banner later.
    commit = latest["commit"] + ("-dirty" if latest["dirty"] else "")
    data = {"build": latest["build"], "commit": commit,
            "manifest": f"{url}/manifest-{latest['build']}.plist"}
    (www / "latest.json").write_text(json.dumps(data) + "\n")


if __name__ == "__main__":
    main()
