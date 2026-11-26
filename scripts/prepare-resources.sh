#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Versioned sources and SHA-256 checks live in each downloader. No credentials needed.
python3 scripts/fetch-basic-pitch.py
python3 scripts/fetch-beyer.py
python3 scripts/fetch-notation-font.py
python3 scripts/fetch-sheet-music.py
python3 scripts/fetch-piano-soundfont.py
