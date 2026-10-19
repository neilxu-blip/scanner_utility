#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$PROJECT_ROOT/scripts/build-app.sh" release

APP_DIRECTORY="$PROJECT_ROOT/.build/Scanner Utility.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIRECTORY/Contents/Info.plist")"
APP_ARCH="$(lipo -archs "$APP_DIRECTORY/Contents/MacOS/ScannerUtility")"
case "$APP_ARCH" in
    arm64|x86_64) ;;
    *) printf 'Unsupported release architecture: %s\n' "$APP_ARCH" >&2; exit 1 ;;
esac
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Invalid app version: %s\n' "$APP_VERSION" >&2
    exit 1
fi

RELEASE_DIRECTORY="$PROJECT_ROOT/.build/releases/$APP_VERSION-$APP_ARCH"
ASSET_NAME="ScannerUtility-$APP_VERSION-macos-$APP_ARCH.zip"
CHECKSUM_NAME="$ASSET_NAME.sha256"
mkdir -p "$RELEASE_DIRECTORY"
if [[ -e "$RELEASE_DIRECTORY/$ASSET_NAME" || -e "$RELEASE_DIRECTORY/$CHECKSUM_NAME" ]]; then
    printf 'Release files already exist; refusing to replace them in %s\n' "$RELEASE_DIRECTORY" >&2
    exit 1
fi

# Keep staging and verification artifacts under ignored .build; never include
# scanner drivers, user scans, preferences, source files, or build caches.
STAGING_DIRECTORY="$(mktemp -d "$RELEASE_DIRECTORY/staging.XXXXXX")"
ditto --norsrc --noextattr --noqtn "$APP_DIRECTORY" "$STAGING_DIRECTORY/Scanner Utility.app"
# SwiftPM release executables can retain debug-map paths to the build machine.
# Remove those records from the distribution copy and renew its ad-hoc signature.
xcrun strip -S "$STAGING_DIRECTORY/Scanner Utility.app/Contents/MacOS/ScannerUtility"
codesign --force --sign - "$STAGING_DIRECTORY/Scanner Utility.app"
codesign --verify --deep --strict "$STAGING_DIRECTORY/Scanner Utility.app"
ditto -c -k --keepParent --norsrc --noextattr --noqtn \
    "$STAGING_DIRECTORY/Scanner Utility.app" "$RELEASE_DIRECTORY/$ASSET_NAME"
unzip -tq "$RELEASE_DIRECTORY/$ASSET_NAME"

VERIFICATION_DIRECTORY="$(mktemp -d "$RELEASE_DIRECTORY/verification.XXXXXX")"
ditto -x -k "$RELEASE_DIRECTORY/$ASSET_NAME" "$VERIFICATION_DIRECTORY"
codesign --verify --deep --strict "$VERIFICATION_DIRECTORY/Scanner Utility.app"
cmp "$STAGING_DIRECTORY/Scanner Utility.app/Contents/MacOS/ScannerUtility" \
    "$VERIFICATION_DIRECTORY/Scanner Utility.app/Contents/MacOS/ScannerUtility"
(
    cd "$RELEASE_DIRECTORY"
    shasum -a 256 "$ASSET_NAME" > "$CHECKSUM_NAME"
    shasum -a 256 -c "$CHECKSUM_NAME"
)
printf 'Release archive: %s\nChecksum: %s\n' \
    "$RELEASE_DIRECTORY/$ASSET_NAME" "$RELEASE_DIRECTORY/$CHECKSUM_NAME"
