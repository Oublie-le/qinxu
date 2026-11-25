#!/usr/bin/env python3
"""Fetch the unmodified, pinned Bravura notation font and its SIL-OFL notice."""

import argparse
import hashlib
from pathlib import Path
import sys
from urllib.request import Request, urlopen

REVISION = "37b194378b710cc40e406ab6c4b07608bb9548ae"
BASE = f"https://raw.githubusercontent.com/steinbergmedia/bravura/{REVISION}/"
DESTINATION = Path(__file__).resolve().parents[1] / "Sources/QinXuApp/Resources/Fonts"
FILES = [
    ("redist/otf/Bravura.otf", "Bravura.otf", 889228,
     "cdf0f893ee1fdb64b7f6713d71ee0dcfc349c0ac01429a8e451b01a9e79f5f3b"),
    ("LICENSE.txt", "Bravura-LICENSE.txt", 4420,
     "bdca252186865f3b2c0e76da4a4e335c14ba1d37f80194fca254ddfa88e84fbf"),
]


def verify(data, size, digest, name):
    if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
        raise ValueError(f"Bravura integrity mismatch: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check existing files without network access")
    options = parser.parse_args()
    for source, name, size, digest in FILES:
        target = DESTINATION / name
        if target.exists():
            verify(target.read_bytes(), size, digest, name)
            continue
        if options.check:
            raise FileNotFoundError(f"Missing {name}; run python3 scripts/fetch-notation-font.py")
        with urlopen(Request(BASE + source, headers={"User-Agent": "QinXu-resource-preparation/1.0"}), timeout=60) as response:
            data = response.read(size + 1)
        verify(data, size, digest, name)
        DESTINATION.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(target.suffix + ".download")
        try:
            temporary.write_bytes(data)
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    print("PASS: Bravura 1.482 font and SIL-OFL license match the pinned official revision.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
