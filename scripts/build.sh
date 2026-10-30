#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
BUILD_DIR="${MATERIAL_BUILD_DIR:-$PWD/.build}"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/clang-cache"
mkdir -p "$BUILD_DIR"
if [[ ! -x Runtime/ffmpeg || ! -x Runtime/ffprobe ]]; then
  echo 'Missing runtime: run ./scripts/build-runtime.sh first.' >&2
  exit 1
fi
swift build -c release --scratch-path "$BUILD_DIR"
BIN_DIR=$(swift build -c release --scratch-path "$BUILD_DIR" --show-bin-path)
APP="$PWD/dist/素材工作台.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources/Licenses"
cp "$BIN_DIR/MaterialWorkbench" "$APP/Contents/MacOS/MaterialWorkbench"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/Licenses/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Runtime/ffmpeg Runtime/ffprobe "$APP/Contents/Helpers/"
cp Runtime/COPYING.LGPLv2.1 Runtime/ffmpeg-8.0-source.tar.xz "$APP/Contents/Resources/Licenses/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MaterialWorkbench</string>
<key>CFBundleIdentifier</key><string>local.spencer.MaterialWorkbench</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>素材工作台</string>
<key>CFBundleDisplayName</key><string>素材工作台</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/Helpers/ffmpeg"
codesign --force --sign - "$APP/Contents/Helpers/ffprobe"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
