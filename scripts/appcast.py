#!/usr/bin/env python3
"""Writes the Sparkle appcast for one Freewire release (release.sh calls it; the feed only needs the newest item).

    appcast.py --version 1.2.0 --build 3 --signature <base64 Ed25519> --zip dist/Freewire-1.2.0.zip \
               --notes RELEASE_NOTES.md --out appcast.xml

The release notes (Markdown bullets, **bold**) become the HTML Sparkle shows in its update window.
"""
import argparse
import email.utils
import html
import os
import re

REPO = "https://github.com/sergioarojasm98/freewire"
MIN_MACOS = "14.0"


def notes_html(path):
    out, items = [], []
    for line in open(path, encoding="utf-8").read().splitlines():
        text = html.escape(line.strip())
        text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
        if line.startswith("- "):
            items.append(f"<li>{text[2:]}</li>")
            continue
        if items:
            out.append("<ul>" + "".join(items) + "</ul>")
            items = []
        if text:
            out.append(f"<p>{text}</p>")
    if items:
        out.append("<ul>" + "".join(items) + "</ul>")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    for name in ("version", "build", "signature", "zip", "notes", "out"):
        ap.add_argument(f"--{name}", required=True)
    a = ap.parse_args()
    tag = f"v{a.version}"
    name = os.path.basename(a.zip)
    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Freewire</title>
    <link>{REPO}</link>
    <item>
      <title>Freewire {a.version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <link>{REPO}/releases/tag/{tag}</link>
      <sparkle:version>{a.build}</sparkle:version>
      <sparkle:shortVersionString>{a.version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MIN_MACOS}</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes_html(a.notes)}]]></description>
      <enclosure url="{REPO}/releases/download/{tag}/{name}" length="{os.path.getsize(a.zip)}"
                 type="application/octet-stream" sparkle:edSignature="{a.signature}"/>
    </item>
  </channel>
</rss>
"""
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(xml)


if __name__ == "__main__":
    main()
