#!/usr/bin/env python3
"""Fetch one unmodified MAESTRO v3 acoustic-piano recording for local evaluation.
CC BY-NC-SA 4.0. Never bundled in the app; files stay in ignored .local-build.
Range requests avoid downloading the 108 GB archive. Each extracted file is hashed.
"""
import argparse
import hashlib
import io
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1] / '.local-build/polyphonic-evaluation'
URL = ('https://storage.googleapis.com/magentadata/datasets/maestro/v3.0.0/'
       'maestro-v3.0.0.zip?generation=1606468421951352')
ARCHIVE_BYTES = 108445099632
STEM = 'maestro-v3.0.0/2008/MIDI-Unprocessed_09_R3_2008_01-07_ORIG_MID--AUDIO_09_R3_2008_wav--2'
FILES = {
    'reference.midi': (STEM + '.midi', 6879, 'fbff7b81e8eb9159e52f0a9f46f3fef1cbe14cb0737dca137d3b52498a2b58cc'),
    'recording.wav': (STEM + '.wav', 11845452, '8037f5a09bf1b1108893d664d25e82b9900aff805f3dfee3b075afaaf35474b0'),
}

class RemoteArchive(io.RawIOBase):
    def __init__(self):
        self.position = 0
        self.block_start = -1
        self.block = b''
        self.transferred = 0
    def seekable(self): return True
    def tell(self): return self.position
    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else self.position + offset if whence == 1 else ARCHIVE_BYTES + offset
        return self.position
    def read(self, count=-1):
        if count < 0: count = ARCHIVE_BYTES - self.position
        if not count: return b''
        if count > 16_000_000 or self.position < 0:
            raise ValueError('Refusing unbounded archive read')
        if self.block_start <= self.position and self.position + count <= self.block_start + len(self.block):
            offset = self.position - self.block_start
            result = self.block[offset:offset + count]
            self.position += len(result)
            return result
        start = self.position
        end = min(ARCHIVE_BYTES - 1, start + max(count, 1024*1024) - 1)
        request = urllib.request.Request(URL, headers={'Range': f'bytes={start}-{end}'})
        with urllib.request.urlopen(request, timeout=60) as response:
            if response.status != 206:
                raise RuntimeError('Server ignored Range; refusing full archive')
            data = response.read(end - start + 2)
        if len(data) != end - start + 1:
            raise RuntimeError('Invalid archive range length')
        self.transferred += len(data)
        if self.transferred > 20_000_000:
            raise RuntimeError('Fixture download exceeded 20 MB budget')
        self.block_start, self.block = start, data
        return self.read(count)

def valid(path, size, digest):
    return path.is_file() and path.stat().st_size == size and hashlib.sha256(path.read_bytes()).hexdigest() == digest

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Only verify existing local fixture.')
    args = parser.parse_args()
    missing = [(name, entry) for name, entry in FILES.items() if not valid(ROOT/name, entry[1], entry[2])]
    if missing and args.check:
        raise SystemExit('Missing or corrupt local MAESTRO fixture. Run scripts/fetch-polyphonic-fixture.py.')
    if missing:
        remote = RemoteArchive()
        with zipfile.ZipFile(remote) as archive:
            for name, (member, size, digest) in missing:
                entry = archive.getinfo(member)
                if entry.file_size != size or entry.compress_size > 12_000_000:
                    raise RuntimeError('Unexpected archive entry')
                data = archive.read(member)
                if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
                    raise RuntimeError('Fixture integrity check failed')
                ROOT.mkdir(parents=True, exist_ok=True)
                (ROOT/name).write_bytes(data)
        print(f'Transferred {remote.transferred:,} bytes from the official archive.')
    print('MAESTRO 3.0.0 fixture verified: Scarlatti Sonata K.525, test split, 2008.')
