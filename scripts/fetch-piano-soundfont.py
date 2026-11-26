#!/usr/bin/env python3
"""Prepare the pinned FreePats CC0 piano SoundFont for offline playback."""

import argparse
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.request import Request, urlopen


SOURCE_URL = (
    "https://freepats.zenvoid.org/Piano/UprightPianoKW/"
    "UprightPianoKW-small-SF2-20190703.7z"
)
ARCHIVE_BYTES = 6_093_984
ARCHIVE_SHA256 = "3bd025e7c2ffa9e6f3f99215ce383c9cebbac991cfbf9be1453cdb4328ec3492"
BANK_MEMBER = "UprightPianoKW-small-SF2-20190703/UprightPianoKW-small-20190703.sf2"
BANK_BYTES = 9_456_310
BANK_SHA256 = "cf2a98eb38a32c4954b4b6e2caae4112d62dd8e892eceefdd7942b0e7d01ac2f"
DESTINATION = Path(__file__).resolve().parents[1] / "Sources/QinXuApp/Resources/Piano.sf2"


def verify(data: bytes, size: int, digest: str, label: str) -> None:
    if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
        raise ValueError(f"{label} does not match the pinned FreePats release")


def load_verified(path: Path, size: int, digest: str, label: str) -> bytes:
    with path.open("rb") as stream:
        data = stream.read(size + 1)
    verify(data, size, digest, label)
    return data


def prepare(local_archive: Path | None) -> None:
    if local_archive is None:
        request = Request(SOURCE_URL, headers={"User-Agent": "QinXu-resource-preparation/1.0"})
        with urlopen(request, timeout=60) as response:
            archive_data = response.read(ARCHIVE_BYTES + 1)
        verify(archive_data, ARCHIVE_BYTES, ARCHIVE_SHA256, "Piano archive")
    else:
        archive_data = load_verified(local_archive, ARCHIVE_BYTES, ARCHIVE_SHA256, "Piano archive")

    with tempfile.TemporaryDirectory(dir=DESTINATION.parent, prefix=".piano-soundfont-") as directory:
        folder = Path(directory)
        archive = folder / "piano.7z"
        bank = folder / "Piano.sf2"
        archive.write_bytes(archive_data)
        # Extract only the pinned member to standard output using macOS's libarchive.
        with bank.open("wb") as stream:
            subprocess.run(
                ["/usr/bin/bsdtar", "-xOf", str(archive), BANK_MEMBER],
                stdout=stream,
                check=True,
                timeout=60,
            )
        load_verified(bank, BANK_BYTES, BANK_SHA256, "Piano.sf2")
        bank.replace(DESTINATION)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the installed bank without network access")
    parser.add_argument("--archive", type=Path, help="use an already downloaded source archive")
    options = parser.parse_args()
    if DESTINATION.exists():
        load_verified(DESTINATION, BANK_BYTES, BANK_SHA256, "Piano.sf2")
    elif options.check:
        raise FileNotFoundError("Missing Piano.sf2; run bash scripts/prepare-resources.sh")
    else:
        prepare(options.archive)
    print("PASS: piano SoundFont matches the pinned CC0 FreePats release.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
