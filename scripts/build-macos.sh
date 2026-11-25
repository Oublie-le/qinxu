#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/.local-build/QinXu.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/QinXuPreview" "$app_dir/Contents/MacOS/QinXu"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QinXu</string>
<key>CFBundleIdentifier</key><string>com.ifeng.QinXu.mac</string>
<key>CFBundleName</key><string>琴序 · 开发预览</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>识别逐个弹奏的钢琴音，音频仅在本机处理。</string>
</dict></plist>
PLIST
codesign --force --sign - --entitlements Config/macOS.entitlements "$app_dir"
printf '%s\n' "$app_dir"
