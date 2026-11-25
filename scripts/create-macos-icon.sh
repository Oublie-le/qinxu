#!/bin/bash
# Package the approved iOS artwork for the shared-code Mac development preview.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/create-macos-icon.sh /path/to/AppIcon.icns" >&2
  exit 2
fi
icon_source="$PWD/Sources/QinXuApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
icon_output="$1"
icon_work="$(mktemp -d "${TMPDIR:-/tmp}/qinxu-icon.XXXXXX")"
trap 'rm -rf "$icon_work"' EXIT
iconset="$icon_work/AppIcon.iconset"
mkdir -p "$iconset" "$(dirname "$icon_output")"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$icon_source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$icon_source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$icon_output"
