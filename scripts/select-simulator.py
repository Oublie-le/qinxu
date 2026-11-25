#!/usr/bin/env python3
"""Select an installed iOS simulator without depending on a runner's device names."""
import json
import re
import subprocess
import sys

family = sys.argv[1] if len(sys.argv) == 2 else ""
if family not in ("iPhone", "iPad"):
    raise SystemExit("Usage: python3 scripts/select-simulator.py iPhone|iPad")
inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
candidates = []
for runtime, devices in inventory["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(value) for value in re.findall(r"\d+", runtime.split(".iOS-")[-1]))
    if version < (17,):
        continue
    for device in devices:
        if device.get("isAvailable", False) and device["name"].startswith(family):
            candidates.append((version, device["name"], device["udid"]))
if not candidates:
    raise SystemExit(f"No available {family} simulator with iOS 17 or later. Install an iOS runtime in Xcode.")
version, name, udid = sorted(candidates, key=lambda item: (tuple(-v for v in item[0]), item[1]))[0]
print(f"Selected {name}, iOS {'.'.join(map(str, version))}: {udid}", file=sys.stderr)
print(udid)
