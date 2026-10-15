"""Tests for release_helper.py: python3 -I macos/release_helper_test.py"""
import importlib.util
import pathlib
import sys
import unittest
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

sys.dont_write_bytecode = True  # no __pycache__ in macos/
_spec = importlib.util.spec_from_file_location(
    "release_helper", pathlib.Path(__file__).with_name("release_helper.py"))
helper = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(helper)

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


class NextVersion(unittest.TestCase):
    def test_the_first_release_is_0_2(self):
        self.assertEqual(helper.next_version("", ""), "0.2")

    def test_each_release_is_one_minor_step(self):
        self.assertEqual(helper.next_version("v0.2", ""), "0.3")
        self.assertEqual(helper.next_version("v0.9", ""), "0.10")

    def test_a_named_version_can_jump(self):
        self.assertEqual(helper.next_version("v0.3", "1.0"), "1.0")
        self.assertEqual(helper.next_version("", "1.0"), "1.0")

    def test_a_named_version_must_be_later(self):
        for override in ("0.3", "0.2"):
            with self.assertRaises(helper.ReleaseError):
                helper.next_version("v0.3", override)

    def test_other_shapes_are_refused(self):
        for bad in ("1", "1.2.3", "v", "abc"):
            with self.assertRaises(helper.ReleaseError):
                helper.next_version("", bad)
        with self.assertRaises(helper.ReleaseError):
            helper.next_version("v1.3.1", "")


class Notes(unittest.TestCase):
    def test_bullets_without_the_prefix_or_docs(self):
        self.assertEqual(helper.notes([
            "lostty: observer: short notes in plain words",
            "docs: spec the download",
            "",
            "Fix a crash",
        ]), ["- Observer: short notes in plain words", "- Fix a crash"])


class SignOutput(unittest.TestCase):
    def test_reads_signature_and_length(self):
        text = 'sparkle:edSignature="abc+/=" length="1234"\n'
        self.assertEqual(helper.parse_sign_output(text), ("abc+/=", 1234))

    def test_anything_else_is_an_error(self):
        with self.assertRaises(helper.ReleaseError):
            helper.parse_sign_output("Error: no key")


class Appcast(unittest.TestCase):
    def make(self, bullets):
        return helper.appcast(
            "0.2", "202610141200", "14.0", bullets,
            "https://github.com/Lawliang/lostty/releases/download/v0.2/Lostty.dmg",
            "sig==", 5678, datetime(2026, 10, 14, 12, 0, tzinfo=timezone.utc))

    def test_one_item_sparkle_can_read(self):
        item = ET.fromstring(self.make(["- Faster"])).find("channel/item")
        self.assertEqual(item.find("title").text, "Lostty 0.2")
        self.assertEqual(item.find(SPARKLE + "version").text, "202610141200")
        self.assertEqual(item.find(SPARKLE + "shortVersionString").text, "0.2")
        self.assertEqual(item.find(SPARKLE + "minimumSystemVersion").text, "14.0")
        self.assertEqual(item.find("pubDate").text, "Wed, 14 Oct 2026 12:00:00 +0000")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"),
                         "https://github.com/Lawliang/lostty/releases/download/v0.2/Lostty.dmg")
        self.assertEqual(enclosure.get("length"), "5678")
        self.assertEqual(enclosure.get(SPARKLE + "edSignature"), "sig==")
        self.assertEqual(item.find("description").text, "<ul><li>Faster</li></ul>")

    def test_notes_with_markup_stay_valid(self):
        item = ET.fromstring(self.make(["- Fix <tab> & ]]> parsing"])).find("channel/item")
        self.assertEqual(item.find("description").text,
                         "<ul><li>Fix &lt;tab&gt; &amp; ]]&gt; parsing</li></ul>")


class Betas(unittest.TestCase):
    TAGS = ["beta", "v0.4-beta.2", "v0.4-beta.1", "v0.4", "v0.3-beta.7", "v0.3", "nightly"]

    def test_the_first_beta_of_a_stable_is_1(self):
        self.assertEqual(helper.next_beta("v0.5", self.TAGS), 1)
        self.assertEqual(helper.next_beta("v0.4", []), 1)

    def test_each_beta_is_one_more(self):
        self.assertEqual(helper.next_beta("v0.4", self.TAGS), 3)

    def test_an_older_stables_betas_dont_count(self):
        self.assertEqual(helper.next_beta("v0.3", ["v0.4-beta.9", "v0.3"]), 1)

    def test_the_newest_tag_of_either_kind(self):
        self.assertEqual(helper.newest_tag(self.TAGS), "v0.4-beta.2")
        self.assertEqual(helper.newest_tag(["v0.4", "v0.4-beta.1"]), "v0.4-beta.1")
        self.assertEqual(helper.newest_tag(["v0.5", "v0.4-beta.2"]), "v0.5")
        self.assertEqual(helper.newest_tag(["beta", "nightly"]), "")
        self.assertEqual(helper.newest_tag([]), "")

    def test_the_fixed_beta_tag_isnt_a_version(self):
        self.assertIsNone(helper.parse_tag("beta"))
        self.assertEqual(helper.parse_tag("v0.4-beta.2"), (0, 4, 2))
        self.assertEqual(helper.parse_tag("v0.4"), (0, 4, 0))


class BetaAppcast(unittest.TestCase):
    def test_a_beta_item_names_its_number(self):
        xml = helper.appcast(
            "0.4", "202610151200", "14.0", ["- Mascot"],
            "https://github.com/Lawliang/lostty/releases/download/v0.4-beta.2/Lostty-Beta.dmg",
            "sig==", 5678, datetime(2026, 10, 15, 12, 0, tzinfo=timezone.utc), beta=2)
        root = ET.fromstring(xml)
        self.assertEqual(root.find("channel/title").text, "Lostty Beta")
        item = root.find("channel/item")
        self.assertEqual(item.find("title").text, "Lostty 0.4 beta 2")
        self.assertEqual(item.find(SPARKLE + "shortVersionString").text, "0.4 beta 2")
        self.assertEqual(item.find(SPARKLE + "version").text, "202610151200")
        self.assertEqual(item.find("enclosure").get("url"),
                         "https://github.com/Lawliang/lostty/releases/download/v0.4-beta.2/Lostty-Beta.dmg")

    def test_stable_is_unchanged(self):
        root = ET.fromstring(helper.appcast(
            "0.4", "1", "14.0", [], "https://x/Lostty.dmg", "s", 1,
            datetime(2026, 10, 15, tzinfo=timezone.utc)))
        self.assertEqual(root.find("channel/title").text, "Lostty")
        self.assertEqual(root.find("channel/item/" + SPARKLE + "shortVersionString").text, "0.4")


if __name__ == "__main__":
    unittest.main()
