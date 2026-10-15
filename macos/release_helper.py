"""Helper for macos/release.sh: the next version, the release notes and
Sparkle's appcast.xml. Standard library only; run with python3 -I.

  next-version --latest TAG --override X.Y   prints the stable version to release
  next-beta --stable TAG                     tags (stdin) → the next beta's number
  newest-tag                                 tags (stdin) → the newest release's tag
  notes                                      commit subjects (stdin) → "- …" lines
  appcast --version X.Y --build N --min-system V --notes-file F --url U --sign-output S [--beta-number N]
"""
import argparse
import email.utils
import html
import re
import sys
from datetime import datetime, timezone

FIRST = "0.2"
VERSION = re.compile(r"^v?(\d+)\.(\d+)$")
TAG = re.compile(r"^v(\d+)\.(\d+)(?:-beta\.(\d+))?$")


class ReleaseError(Exception):
    pass


def parse_version(text):
    match = VERSION.match(text.strip())
    if not match:
        raise ReleaseError(f"{text!r} isn't a version like 0.2")
    return int(match.group(1)), int(match.group(2))


def next_version(latest, override):
    """After `latest` (a tag like v0.2, or "" before the first release): one
    minor step up, or `override` when it is later."""
    if override:
        wanted = parse_version(override)
        if latest and wanted <= parse_version(latest):
            raise ReleaseError(f"{override} isn't after {latest.lstrip('v')}")
        return "%d.%d" % wanted
    if not latest:
        return FIRST
    major, minor = parse_version(latest)
    return f"{major}.{minor + 1}"


def parse_tag(tag):
    """(major, minor, beta) for vX.Y (beta 0) or vX.Y-beta.N; None for any
    other tag, such as the fixed `beta` release's."""
    match = TAG.match(tag.strip())
    if not match:
        return None
    return int(match.group(1)), int(match.group(2)), int(match.group(3) or 0)


def next_beta(stable, tags):
    """The number of the next beta of `stable` (a tag like v0.4): one more
    than its highest among `tags`, or 1."""
    base = parse_version(stable)
    numbers = [parsed[2] for parsed in map(parse_tag, tags)
               if parsed and parsed[:2] == base and parsed[2] > 0]
    return max(numbers, default=0) + 1


def newest_tag(tags):
    """The newest release among `tags`, stable or beta: v0.4-beta.2 comes
    after v0.4, and v0.5 after both. "" when none is a release tag."""
    releases = [(parsed, tag.strip()) for tag in tags if (parsed := parse_tag(tag))]
    return max(releases)[1] if releases else ""


def notes(subjects):
    """Bullets for the notes: `docs:` commits left out, the `lostty: `
    prefix dropped, the first letter capitalized."""
    bullets = []
    for subject in subjects:
        subject = subject.strip()
        if not subject or subject.startswith("docs:"):
            continue
        if subject.startswith("lostty: "):
            subject = subject[len("lostty: "):]
        bullets.append("- " + subject[0].upper() + subject[1:])
    return bullets


def parse_sign_output(text):
    """(signature, length) from sign_update's
    `sparkle:edSignature="…" length="…"`."""
    signature = re.search(r'sparkle:edSignature="([^"]+)"', text)
    length = re.search(r'\blength="(\d+)"', text)
    if not signature or not length:
        raise ReleaseError(f"sign_update printed {text.strip()!r}")
    return signature.group(1), int(length.group(1))


def appcast(version, build, min_system, bullets, url, signature, length, now, beta=None):
    """Sparkle's feed: one item. With `beta`, the beta's ("0.4 beta 2")."""
    short = f"{version} beta {beta}" if beta else version
    channel = "Lostty Beta" if beta else "Lostty"
    # Escaping turns any "]]>" into "]]&gt;", so the CDATA can't end early.
    items = "".join(
        "<li>%s</li>" % html.escape(b[2:] if b.startswith("- ") else b, quote=False)
        for b in bullets)
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>{channel}</title>
    <item>
      <title>Lostty {short}</title>
      <pubDate>{email.utils.format_datetime(now)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{short}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_system}</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>{items}</ul>]]></description>
      <enclosure url="{html.escape(url)}" length="{length}" type="application/octet-stream" sparkle:edSignature="{html.escape(signature)}"/>
    </item>
  </channel>
</rss>
"""


def main(argv):
    parser = argparse.ArgumentParser(prog="release_helper.py")
    commands = parser.add_subparsers(dest="command", required=True)
    version = commands.add_parser("next-version")
    version.add_argument("--latest", default="")
    version.add_argument("--override", default="")
    beta = commands.add_parser("next-beta")
    beta.add_argument("--stable", required=True)
    commands.add_parser("newest-tag")
    commands.add_parser("notes")
    feed = commands.add_parser("appcast")
    for name in ("--version", "--build", "--min-system", "--notes-file", "--url", "--sign-output"):
        feed.add_argument(name, required=True)
    feed.add_argument("--beta-number", default="")
    args = parser.parse_args(argv)
    try:
        if args.command == "next-version":
            print(next_version(args.latest, args.override))
        elif args.command == "next-beta":
            print(next_beta(args.stable, sys.stdin.read().splitlines()))
        elif args.command == "newest-tag":
            print(newest_tag(sys.stdin.read().splitlines()))
        elif args.command == "notes":
            print("\n".join(notes(sys.stdin.read().splitlines())))
        else:
            with open(args.notes_file, encoding="utf-8") as file:
                bullets = [line.rstrip("\n") for line in file if line.strip()]
            signature, length = parse_sign_output(args.sign_output)
            beta_number = int(args.beta_number) if args.beta_number else None
            sys.stdout.write(appcast(args.version, args.build, args.min_system, bullets,
                                     args.url, signature, length, datetime.now(timezone.utc),
                                     beta=beta_number))
    except ReleaseError as error:
        print(f"release: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
