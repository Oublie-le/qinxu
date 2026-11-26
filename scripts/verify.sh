#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Prefer the installed full Xcode for this process without changing system settings.
if [[ -z "${DEVELOPER_DIR:-}" && -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
require_ios=false
if [[ "${1:-}" == "--require-ios" ]]; then
  require_ios=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: bash scripts/verify.sh [--require-ios]" >&2
  exit 2
fi

python3 scripts/generate_project.py --check
python3 scripts/fetch-basic-pitch.py --check
python3 scripts/fetch-beyer.py --check
python3 scripts/fetch-notation-font.py --check
python3 scripts/fetch-sheet-music.py --check
plutil -lint Config/Info.plist Config/macOS.entitlements QinXu.xcodeproj/project.pbxproj
swift test --enable-code-coverage

if xcrun --sdk iphonesimulator --show-sdk-path >/dev/null 2>&1; then
  xcodebuild -project QinXu.xcodeproj -scheme QinXu \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .local-build/DerivedData CODE_SIGNING_ALLOWED=NO build
  echo "PASS: automated tests and iOS Simulator build. Physical piano tests remain separate."
elif [[ "$require_ios" == true ]]; then
  echo "FAIL: iOS Simulator SDK is unavailable. Install full Xcode and its iOS platform components." >&2
  exit 1
else
  echo "PASS: automated tests. SKIP: iOS Simulator build (full Xcode / iOS SDK unavailable)."
fi
