#!/usr/bin/env python3
"""Prepare the pinned Swift Sheet Music PDF/Core ML sources and model."""

import argparse
import hashlib
from pathlib import Path, PurePosixPath
import sys
import tarfile
import tempfile
from urllib.request import Request, urlopen

REVISION = "c11ab5e97f9242c159f1dc5d8e5ffb852a887a58"
ARCHIVE_URL = f"https://codeload.github.com/jiyimeta/swift-sheet-music/tar.gz/{REVISION}"
ARCHIVE_SHA256 = "5c4f250e77094d4fa1ad1163f527e114f2973e503e86f1051816b2403bd19ebb"
ARCHIVE_SIZE = 11_390_279
SOURCES_SHA256 = "b8e96ee4fa736fd34b095051fb423b1f50219ed2cb755cff7b9df51117f138bb"
ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "Dependencies/SwiftSheetMusic/Sources"
TARGETS = {
    "SheetMusicFoundation", "SheetMusicCore", "SheetMusicZip", "SheetMusicPDFSyntax",
    "SheetMusicLayout", "SheetMusicLayoutApple", "SheetMusicUI", "SheetMusicPDF", "SheetMusicOMRModel"
}


def verify_sources(directory):
    digest = hashlib.sha256()
    files = sorted(path for path in directory.rglob("*") if path.is_file())
    for path in files:
        relative = path.relative_to(directory).as_posix()
        fingerprint = hashlib.sha256(path.read_bytes()).hexdigest()
        digest.update(f"{relative}\0{fingerprint}\n".encode())
    if digest.hexdigest() != SOURCES_SHA256:
        raise ValueError("Swift Sheet Music sources differ from the pinned revision")


def prepare(archive, sources):
    if archive.stat().st_size != ARCHIVE_SIZE or hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise ValueError("Swift Sheet Music archive integrity check failed")
    with tarfile.open(archive, mode="r:gz") as package:
        for item in package:
            path = PurePosixPath(item.name)
            parts = path.parts
            if len(parts) < 4 or parts[:2] != (f"swift-sheet-music-{REVISION}", "Sources") or parts[2] not in TARGETS:
                continue
            if item.isdir():
                continue
            if not item.isfile() or ".." in parts:
                raise ValueError(f"Unexpected archive entry: {item.name}")
            target = sources.joinpath(*parts[2:])
            target.parent.mkdir(parents=True, exist_ok=True)
            with package.extractfile(item) as source:
                target.write_bytes(source.read())
    verify_sources(sources)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check existing files without network access")
    parser.add_argument("--archive", type=Path, help="use an already downloaded source archive")
    options = parser.parse_args()
    if DESTINATION.exists():
        verify_sources(DESTINATION)
    elif options.check:
        raise FileNotFoundError("Missing Swift Sheet Music sources; run bash scripts/prepare-resources.sh")
    else:
        with tempfile.TemporaryDirectory(dir=DESTINATION.parent) as directory:
            directory = Path(directory)
            archive = options.archive
            if archive is None:
                archive = directory / "sources.tar.gz"
                with urlopen(Request(ARCHIVE_URL, headers={"User-Agent": "QinXu-resource-preparation/1.0"}), timeout=60) as response:
                    archive.write_bytes(response.read(ARCHIVE_SIZE + 1))
            prepared = directory / "Sources"
            prepare(archive, prepared)
            prepared.rename(DESTINATION)
    print(f"PASS: Swift Sheet Music PDF/Core ML sources match {REVISION}.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, tarfile.TarError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
