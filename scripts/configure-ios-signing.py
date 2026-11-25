#!/usr/bin/env python3
"""Configure local iOS signing identifiers without changing the generated project.

Usage: python3 scripts/configure-ios-signing.py TEAM_ID [--bundle-id com.example.QinXu]
Only a public Apple Team ID and bundle identifier are written, never credentials.
"""
import argparse
import os
from pathlib import Path
import re
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / 'Config/LocalSigning.xcconfig'
DEFAULT_BUNDLE_ID = 'com.ifeng.QinXu'
BEGIN = '// BEGIN QinXu managed signing identifiers'
END = '// END QinXu managed signing identifiers'
HEADER = '// Local-only signing identifiers. Do not commit this file or add credentials.\n'
BUNDLE_PATTERN = re.compile(r'[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+')


def team_identifier(value):
    if not re.fullmatch(r'[A-Za-z0-9]{10}', value):
        raise ValueError('Team ID must contain exactly 10 ASCII letters or digits.')
    return value.upper()


def bundle_identifier(value):
    # Conservative application limit leaves room for UITests and runner suffixes.
    if len(value) > 200 or BUNDLE_PATTERN.fullmatch(value) is None:
        raise ValueError('Bundle ID must be at most 200 characters, with two or more dot-separated ASCII letter/digit/hyphen components, each starting and ending with a letter or digit.')
    return value


def configure_signing(team_id, bundle_id=None, destination=DESTINATION):
    team_id = team_identifier(team_id)
    if bundle_id is not None:
        bundle_id = bundle_identifier(bundle_id)
    destination = Path(destination)
    if destination.is_symlink():
        raise ValueError('Refusing to replace a symbolic-link signing configuration.')
    previous_bundle = DEFAULT_BUNDLE_ID
    prefix, suffix = HEADER, '\n'
    if destination.exists():
        original = destination.read_text(encoding='utf-8')
        if original.count(BEGIN) != 1 or original.count(END) != 1:
            raise ValueError('LocalSigning.xcconfig is not managed by this script; it was left unchanged. Add DEVELOPMENT_TEAM and QINXU_BUNDLE_IDENTIFIER there manually, or move it aside yourself.')
        start, end = original.index(BEGIN), original.index(END)
        if start >= end:
            raise ValueError('Invalid managed signing block; the existing file was left unchanged.')
        managed = original[start + len(BEGIN):end]
        fields = {}
        for line in managed.splitlines():
            if not line.strip():
                continue
            match = re.fullmatch(r'(DEVELOPMENT_TEAM|QINXU_BUNDLE_IDENTIFIER) = ([A-Za-z0-9.-]+)', line)
            if not match or match[1] in fields:
                raise ValueError('The managed signing block has custom content; move custom settings outside its markers before retrying. The file was left unchanged.')
            fields[match[1]] = match[2]
        if set(fields) != {'DEVELOPMENT_TEAM', 'QINXU_BUNDLE_IDENTIFIER'}:
            raise ValueError('Incomplete managed signing block; the existing file was left unchanged.')
        team_identifier(fields['DEVELOPMENT_TEAM'])
        previous_bundle = bundle_identifier(fields['QINXU_BUNDLE_IDENTIFIER'])
        # Preserve user comments and custom build settings outside our exact block.
        prefix, suffix = original[:start], original[end + len(END):]
    selected_bundle = bundle_id if bundle_id is not None else previous_bundle
    content = (prefix + BEGIN + '\n' + f'DEVELOPMENT_TEAM = {team_id}\n'
               + f'QINXU_BUNDLE_IDENTIFIER = {selected_bundle}\n' + END + suffix)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=destination.parent,
                                         prefix='.LocalSigning.', suffix='.tmp', delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('team_id', help='The 10-character public Apple developer Team ID.')
    parser.add_argument('--bundle-id', help='App bundle identifier; keeps the existing local value when omitted.')
    args = parser.parse_args()
    try:
        configure_signing(args.team_id, args.bundle_id)
    except (ValueError, OSError, UnicodeError) as error:
        parser.exit(1, f'Signing configuration not changed: {error}\n')
    print('Configured Config/LocalSigning.xcconfig (ignored by Git). No credentials saved. Project regeneration preserves this configuration.')
