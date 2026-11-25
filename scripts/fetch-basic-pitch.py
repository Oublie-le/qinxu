#!/usr/bin/env python3
"""Fetch the unmodified, pinned Apache-2.0 Basic Pitch CoreML package.
Model binaries are local build inputs, never Git-tracked. Every byte is verified.
"""
import argparse
import hashlib
from pathlib import Path
import urllib.request

COMMIT = 'fa5997af0a8210982619003269994a1be25eddf3'
BASE = f'https://raw.githubusercontent.com/spotify/basic-pitch/{COMMIT}/'
ROOT = Path(__file__).resolve().parents[1] / 'Sources/QinXuApp/Resources'
FILES = {
    'Manifest.json': ('c1fa5ef8acc34703edcd4e90e9a8640bd4673d9f3a68753c3b9d1ca0365e2928', 617),
    'Data/com.apple.CoreML/model.mlmodel': ('af7bf7d49bc167e0bf0c30aa2ca6b432c3e10df048d2dd4173ff3a738c020858', 123027),
    'Data/com.apple.CoreML/weights/weight.bin': ('691a6b63c7ddcdde0ee131ff3986dcb1250df47cd738612efde966ba9b4c99cd', 145956),
}

def fetch(relative, destination, digest, size, check_only=False):
    if destination.is_file() and hashlib.sha256(destination.read_bytes()).hexdigest() == digest:
        return
    if check_only:
        raise RuntimeError(f"Missing or corrupt model resource: {destination}. Run python3 scripts/fetch-basic-pitch.py.")
    with urllib.request.urlopen(BASE + relative, timeout=60) as response:
        data = response.read(size + 1)
    if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError(f'Integrity check failed: {relative}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + '.download')
    temporary.write_bytes(data)
    temporary.replace(destination)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify local files without network access or changes.')
    args = parser.parse_args()
    for name, (digest, size) in FILES.items():
        fetch('basic_pitch/saved_models/icassp_2022/nmp.mlpackage/' + name,
              ROOT / 'BasicPitch.mlpackage' / name, digest, size, args.check)
    fetch('LICENSE', ROOT / 'BasicPitch-LICENSE.txt',
          '929c910bae2152fa87199a5d0660e09263419b7eee6d4b301d05ee2aaf211c37', 11384, args.check)
    print('Basic Pitch CoreML verified: 269,600 model bytes, Apache-2.0 license retained.')
