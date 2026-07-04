#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Photos Caption Assistant"
APP_BUNDLE="${1:-$ROOT_DIR/dist/$APP_NAME.app}"
OUTPUT_DIR="${2:-$ROOT_DIR/dist}"
VOLUME_NAME="$APP_NAME"
CODE_SIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:-}"

plist_read() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing app Info.plist: $INFO_PLIST" >&2
  exit 1
fi

VERSION="$(plist_read "$INFO_PLIST" CFBundleShortVersionString)"
BUILD="$(plist_read "$INFO_PLIST" CFBundleVersion)"

mkdir -p "$OUTPUT_DIR"

DMG_NAME="Photos-Caption-Assistant-v${VERSION}-build-${BUILD}-macOS-universal.dmg"
FINAL_DMG="$OUTPUT_DIR/$DMG_NAME"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/photos-caption-assistant-dmg.XXXXXX")"
STAGING_DIR="$TEMP_DIR/staging"
RW_DMG="$TEMP_DIR/$DMG_NAME.rw.dmg"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG"

hdiutil convert "$RW_DMG" -ov -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"

if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
  codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$FINAL_DMG"
  codesign --verify --verbose=2 "$FINAL_DMG"
fi

echo "Built DMG: $FINAL_DMG"
