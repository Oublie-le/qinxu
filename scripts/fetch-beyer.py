#!/usr/bin/env python3
"""Prepare the pinned public-domain reading edition; never substitute another PDF."""

import argparse
import hashlib
import os
from pathlib import Path
import sys
import tempfile
from urllib.request import Request, urlopen


SOURCE_URL = (
    "https://upload.wikimedia.org/wikipedia/commons/a/aa/"
    "Vorschule_im_Klavierspiel%2C_Op.101_"
    "%28IA_imslp-im-klavierspiel-op101-beyer-ferdinand%29.pdf"
)
EXPECTED_SHA256 = "369d3800bc8ad42c97fb4312b92060060a6d42aee4e642c35de797fb65ff23c2"
EXPECTED_BYTES = 10_301_776
DESTINATION = Path(__file__).resolve().parents[1] / "Sources/QinXuApp/Resources/Books/Beyer-Op101.pdf"


def verify(data: bytes) -> None:
    if len(data) != EXPECTED_BYTES or not data.startswith(b"%PDF-"):
        raise ValueError("Beyer PDF size or file signature does not match the pinned edition")
    actual = hashlib.sha256(data).hexdigest()
    if actual != EXPECTED_SHA256:
        raise ValueError(f"Beyer PDF SHA256 mismatch: {actual}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check the local resource without network access")
    options = parser.parse_args()

    if DESTINATION.exists():
        # A mismatch is reported instead of silently replacing an unexpected resource.
        verify(DESTINATION.read_bytes())
        print("PASS: bundled Beyer PDF matches the pinned 88-page edition.")
        return
    if options.check:
        raise FileNotFoundError("Missing bundled Beyer PDF; run python3 scripts/fetch-beyer.py")

    request = Request(SOURCE_URL, headers={"User-Agent": "QinXu-resource-preparation/1.0"})
    with urlopen(request, timeout=60) as response:
        data = response.read(EXPECTED_BYTES + 1)
    verify(data)
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(dir=DESTINATION.parent, prefix=".Beyer-", suffix=".download", delete=False) as stream:
            temporary_path = Path(stream.name)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, DESTINATION)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
    print("PASS: downloaded and verified the pinned 88-page public-domain Beyer PDF.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
