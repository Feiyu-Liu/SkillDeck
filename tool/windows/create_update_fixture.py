"""Sign a loopback-only Windows test feed; never publish production metadata."""
import argparse
import base64
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("installer", type=Path)
    parser.add_argument("--private-key", required=True, type=Path)
    parser.add_argument("--public-key", required=True, type=Path)
    args = parser.parse_args()
    installer = args.installer.resolve()
    digest = subprocess.run(
        ["openssl", "dgst", "-sha1", "-binary", str(installer)],
        check=True, capture_output=True,
    ).stdout
    signature = subprocess.run(
        ["openssl", "dgst", "-sha1", "-sign", str(args.private_key)],
        input=digest, check=True, capture_output=True,
    ).stdout
    signature_file = installer.parent / "installer.dsa"
    signature_file.write_bytes(signature)
    subprocess.run(
        ["openssl", "dgst", "-sha1", "-verify", str(args.public_key),
         "-signature", str(signature_file)],
        input=digest, check=True,
    )
    ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ET.register_namespace("sparkle", ns)
    feed = ET.Element("rss", version="2.0")
    channel = ET.SubElement(feed, "channel")
    ET.SubElement(channel, "title").text = "SkillDeck Lifecycle Test"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = "SkillDeck Lifecycle Test 0.0.2"
    ET.SubElement(item, "enclosure", {
        "url": f"http://127.0.0.1:5013/{installer.name}",
        "length": str(installer.stat().st_size),
        "type": "application/octet-stream",
        f"{{{ns}}}os": "windows",
        f"{{{ns}}}version": "0.0.2.2",
        f"{{{ns}}}shortVersionString": "0.0.2",
        f"{{{ns}}}dsaSignature": base64.b64encode(signature).decode(),
        f"{{{ns}}}installerArguments": "/SILENT /SP- /NOICONS",
    })
    ET.ElementTree(feed).write(installer.parent / "appcast.xml", encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
