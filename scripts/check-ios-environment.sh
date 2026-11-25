#!/bin/bash
# Read-only preflight; does not install software or change xcode-select.
set -u

if [[ $# -gt 0 ]]; then
  echo "Usage: bash scripts/check-ios-environment.sh" >&2
  exit 2
fi

echo "macOS: $(sw_vers -productVersion) ($(uname -m))"
selected_developer_dir="$(xcode-select --print-path 2>/dev/null || true)"
echo "Selected developer directory: ${selected_developer_dir:-none}"

# Respect a caller's explicit DEVELOPER_DIR. Otherwise examine the installed
# default Xcode without changing the Mac's selected compiler.
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  qinxu_developer_dir="$DEVELOPER_DIR"
elif [[ "$selected_developer_dir" == *.app/Contents/Developer ]]; then
  qinxu_developer_dir="$selected_developer_dir"
else
  qinxu_developer_dir="/Applications/Xcode.app/Contents/Developer"
fi

if [[ ! -x "$qinxu_developer_dir/usr/bin/xcodebuild" ]]; then
  echo "MISSING: Full Xcode. Install the free Xcode app from the Mac App Store."
  echo "https://apps.apple.com/app/xcode/id497799835"
  echo "After installation, open Xcode and complete its first-launch setup."
  exit 1
fi

export DEVELOPER_DIR="$qinxu_developer_dir"
echo "Checking Xcode at: $DEVELOPER_DIR"
if ! xcodebuild -version; then
  echo "MISSING: Xcode first-launch setup or license acceptance. Open Xcode to complete it."
  exit 1
fi

qinxu_missing_platform=false
for qinxu_sdk in iphoneos iphonesimulator; do
  if qinxu_sdk_version="$(xcrun --sdk "$qinxu_sdk" --show-sdk-version 2>/dev/null)"; then
    echo "SDK $qinxu_sdk: $qinxu_sdk_version"
  else
    echo "MISSING: $qinxu_sdk SDK. Install iOS platform support in Xcode Settings > Components."
    qinxu_missing_platform=true
  fi
done

echo "Available iOS simulator runtimes:"
if ! xcrun simctl list runtimes; then
  echo "Simulator service is not ready. Complete Xcode first-launch setup."
  qinxu_missing_platform=true
fi

echo "Connected / paired development devices:"
if ! xcrun devicectl list devices --timeout 15; then
  echo "Device discovery failed. Unlock the iPad and accept Trust This Computer, then retry."
fi
echo "A listed device is not a hardware test. Signing and Developer Mode must also be ready."

if [[ "$qinxu_missing_platform" == true ]]; then
  exit 1
fi
