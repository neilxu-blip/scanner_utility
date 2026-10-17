#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIGURATION="${1:-debug}"
case "$BUILD_CONFIGURATION" in
    debug|release) ;;
    *) printf 'Usage: bash scripts/build-app.sh [debug|release]\n' >&2; exit 1 ;;
esac

export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/module-cache"
SWIFT_OPTIONS=(--package-path "$PROJECT_ROOT" --configuration "$BUILD_CONFIGURATION" --disable-sandbox
    --cache-path "$PROJECT_ROOT/.build/cache" --config-path "$PROJECT_ROOT/.build/config"
    --security-path "$PROJECT_ROOT/.build/security")
swift build "${SWIFT_OPTIONS[@]}"
BINARY_DIRECTORY="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"
APP_DIRECTORY="$PROJECT_ROOT/.build/Scanner Utility.app"
mkdir -p "$APP_DIRECTORY/Contents/MacOS"
# Replace the generated executable atomically so a running app keeps its old
# mapped binary and any in-memory document until the user saves and relaunches.
PENDING_BINARY="$(mktemp "$APP_DIRECTORY/Contents/MacOS/ScannerUtility.XXXXXX")"
cp -p "$BINARY_DIRECTORY/ScannerUtility" "$PENDING_BINARY"
mv "$PENDING_BINARY" "$APP_DIRECTORY/Contents/MacOS/ScannerUtility"
cat > "$APP_DIRECTORY/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ScannerUtility</string>
    <key>CFBundleIdentifier</key><string>dev.scannerutility.app</string>
    <key>CFBundleName</key><string>Scanner Utility</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.5.0</string>
    <key>CFBundleVersion</key><string>6</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP_DIRECTORY"
printf 'Built %s\n' "$APP_DIRECTORY"
