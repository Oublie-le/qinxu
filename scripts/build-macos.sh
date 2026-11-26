#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Prefer the installed full Xcode for this process without changing system settings.
if [[ -z "${DEVELOPER_DIR:-}" && -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/.local-build/QinXu.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/QinXuPreview" "$app_dir/Contents/MacOS/QinXu"
# Keep the SwiftPM resource bundle inside the signed app's standard resources folder.
mkdir -p "$app_dir/Contents/Resources"
bash scripts/create-macos-icon.sh "$app_dir/Contents/Resources/AppIcon.icns"
# Remove only the old generated bundle placement, which codesign rejects at the app root.
if [[ -d "$app_dir/QinXu_QinXuApp.bundle" ]]; then
  rm -rf "$app_dir/QinXu_QinXuApp.bundle"
fi
for resource_bundle in "$binary_dir"/QinXu_QinXuApp.bundle \
                       "$binary_dir"/swift-sheet-music_SheetMusicLayoutApple.bundle \
                       "$binary_dir"/swift-sheet-music_SheetMusicOMRModel.bundle; do
  [[ -d "$resource_bundle" ]] || continue
  cp -R "$resource_bundle" "$app_dir/Contents/Resources/"
done
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
<key>CFBundleExecutable</key><string>QinXu</string>
<key>CFBundleIdentifier</key><string>com.ifeng.QinXu.mac</string>
<key>CFBundleName</key><string>琴序 · 开发预览</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>识别弹奏的钢琴音，音频仅在本机处理。</string>
<key>UTImportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>org.musicxml.mxl</string>
    <key>UTTypeDescription</key><string>压缩 MusicXML 乐谱</string>
    <key>UTTypeConformsTo</key><array><string>public.zip</string></array>
    <key>UTTypeTagSpecification</key><dict>
        <key>public.filename-extension</key><array><string>mxl</string></array>
        <key>public.mime-type</key><array><string>application/vnd.recordare.musicxml</string></array>
    </dict>
</dict></array>
</dict></plist>
PLIST
codesign --force --sign - --entitlements Config/macOS.entitlements "$app_dir"
printf '%s\n' "$app_dir"
