#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
family="${1:-iPhone}"
python3 scripts/generate_project.py --check
simulator="$(python3 scripts/select-simulator.py "$family")"
mkdir -p .local-build/results
result_dir="$(mktemp -d ".local-build/results/${family}.XXXXXX")"
xcrun simctl bootstatus "$simulator" -b
xcodebuild test -project QinXu.xcodeproj -scheme QinXu \
  -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath .local-build/DerivedData \
  -resultBundlePath "$result_dir/QinXu.xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$result_dir/xcodebuild.log"
