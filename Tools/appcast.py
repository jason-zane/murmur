#!/usr/bin/env python3
"""Generate an appcast for a locally signed release. No private key is read by Python."""
import argparse
import base64
from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess
from xml.etree import ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def appcast(archive: Path, version: str, build: str, signature: str) -> bytes:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not build.isdecimal():
        raise ValueError("Release version and build must be numeric")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("An Ed25519 signature is required")
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Concourse updates"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Concourse {version}"
    ET.SubElement(item, "pubDate").text = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = build
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = "26.0"
    ET.SubElement(item, f"{{{SPARKLE}}}releaseNotesLink").text = f"https://github.com/jason-zane/murmur/releases/tag/v{version}"
    ET.SubElement(item, "enclosure", {
        "url": f"https://github.com/jason-zane/murmur/releases/download/v{version}/{archive.name}",
        "length": str(archive.stat().st_size), "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": signature,
    })
    ET.indent(rss)
    return ET.tostring(rss, encoding="utf-8", xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--sign-tool", required=True)
    parser.add_argument("--output", type=Path, default=Path("dist/appcast.xml"))
    args = parser.parse_args()
    signature = subprocess.check_output([
        args.sign_tool, "--account", "com.jasonhunt.murmur", "-p", str(args.archive)
    ], text=True).strip()
    # Verify what we just signed before advertising an archive to installed clients.
    subprocess.run([args.sign_tool, "--account", "com.jasonhunt.murmur", "--verify", str(args.archive), signature], check=True)
    args.output.write_bytes(appcast(args.archive, args.version, args.build, signature))
    # Sparkle 2.10 also authenticates the feed itself.
    subprocess.run([args.sign_tool, "--account", "com.jasonhunt.murmur", str(args.output)], check=True)
    subprocess.run([args.sign_tool, "--account", "com.jasonhunt.murmur", "--verify", str(args.output)], check=True)


if __name__ == "__main__":
    main()
