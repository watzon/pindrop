#!/usr/bin/env python3

import argparse
import xml.etree.ElementTree as ET
from pathlib import Path


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)


def get_or_create_child(parent: ET.Element, tag: str) -> ET.Element:
    child = parent.find(tag)
    if child is None:
        child = ET.SubElement(parent, tag)
    return child


def get_or_create_sparkle_child(parent: ET.Element, local_name: str) -> ET.Element:
    return get_or_create_child(parent, f"{{{SPARKLE_NS}}}{local_name}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Add release notes metadata to a Sparkle appcast")
    parser.add_argument("--appcast", required=True, help="Path to appcast.xml")
    parser.add_argument("--release-notes-url", required=True, help="URL to the version-specific release notes asset")
    parser.add_argument("--full-release-notes-url", required=True, help="URL to the full release notes or release page")
    parser.add_argument("--download-page-url", help="Optional human-facing page for the release item")
    args = parser.parse_args()

    appcast_path = Path(args.appcast)
    tree = ET.parse(appcast_path)
    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        raise SystemExit("Appcast is missing channel element")

    items = channel.findall("item")
    if not items:
        raise SystemExit("Appcast does not contain any items")

    for item in items:
        if args.download_page_url:
            link = get_or_create_child(item, "link")
            link.text = args.download_page_url

        release_notes_link = get_or_create_sparkle_child(item, "releaseNotesLink")
        release_notes_link.text = args.release_notes_url

        full_release_notes_link = get_or_create_sparkle_child(item, "fullReleaseNotesLink")
        full_release_notes_link.text = args.full_release_notes_url

    try:
        ET.indent(tree, space="    ")
    except AttributeError:
        pass

    tree.write(appcast_path, encoding="utf-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
