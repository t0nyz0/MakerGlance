#!/usr/bin/env python3
"""Check local Markdown/HTML links and exported image metadata without network access."""
from pathlib import Path
import argparse
import re
import struct
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strip-png-metadata", action="store_true", help="Remove text/EXIF chunks only; preserve rendered pixels and color profiles")
    args = parser.parse_args()
    issues = []
    documents = [ROOT / "README.md", ROOT / "SECURITY.md", ROOT / "CONTRIBUTING.md", *ROOT.glob("docs/**/*.md")]
    links = 0
    for document in documents:
        text = document.read_text()
        targets = re.findall(r"\]\(([^\s)]+)(?:\s+[^)]*)?\)", text)
        targets += re.findall(r'(?:href|src)="([^"]+)"', text)
        for target in targets:
            parsed = urlsplit(target.strip("<>"))
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            links += 1
            path = (document.parent / unquote(parsed.path)).resolve()
            if not path.is_relative_to(ROOT) or not path.exists():
                issues.append(f"{document.relative_to(ROOT)}: missing/outside local target {target}")
    images = list(ROOT.glob("docs/**/*.png"))
    # Text/EXIF payloads are unnecessary for these native renders and screenshots.
    for path in images:
        data = path.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            issues.append(f"{path.relative_to(ROOT)}: invalid PNG signature")
            continue
        offset = 8
        approved = bytearray(data[:8])
        removed = False
        while offset + 12 <= len(data):
            size = struct.unpack(">I", data[offset:offset + 4])[0]
            chunk = data[offset + 4:offset + 8]
            if chunk in {b"tEXt", b"iTXt", b"zTXt", b"eXIf"}:
                if args.strip_png_metadata:
                    removed = True
                else:
                    issues.append(f"{path.relative_to(ROOT)}: unnecessary text/EXIF metadata")
            else:
                approved.extend(data[offset:offset + size + 12])
            offset += size + 12
        if removed:
            path.write_bytes(approved)
    for issue in issues:
        print(issue)
    print(f"Checked {len(documents)} documents, {links} local links and {len(images)} PNG metadata containers; {len(issues)} issues.")
    return bool(issues)

if __name__ == "__main__":
    sys.exit(main())
