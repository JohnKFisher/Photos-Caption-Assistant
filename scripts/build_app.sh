#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST_SOURCE="$ROOT_DIR/Sources/PhotoDescriptionCreator/Resources/Info.plist"
APP_NAME="Photo Description Creator"
EXECUTABLE_NAME="PhotoDescriptionCreator"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
RELEASE_BINARY="$ROOT_DIR/.build/arm64-apple-macosx/release/$EXECUTABLE_NAME"
ICON_PATH="$ROOT_DIR/Sources/PhotoDescriptionCreator/Resources/AppIcon.icns"

plist_read() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

plist_set() {
  /usr/libexec/PlistBuddy -c "Set :$2 $3" "$1"
}

if [[ ! -f "$INFO_PLIST_SOURCE" ]]; then
  echo "Missing source Info.plist: $INFO_PLIST_SOURCE" >&2
  exit 1
fi

CURRENT_VERSION="$(plist_read "$INFO_PLIST_SOURCE" CFBundleShortVersionString)"
CURRENT_BUILD="$(plist_read "$INFO_PLIST_SOURCE" CFBundleVersion)"
NEXT_BUILD=1

if [[ -f "$APP_BUNDLE/Contents/Info.plist" ]]; then
  DIST_VERSION="$(plist_read "$APP_BUNDLE/Contents/Info.plist" CFBundleShortVersionString || true)"
  DIST_BUILD="$(plist_read "$APP_BUNDLE/Contents/Info.plist" CFBundleVersion || true)"
  if [[ "$DIST_VERSION" == "$CURRENT_VERSION" && "$DIST_BUILD" =~ ^[0-9]+$ ]]; then
    NEXT_BUILD=$((DIST_BUILD + 1))
  else
    NEXT_BUILD=1
  fi
elif [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  NEXT_BUILD=$((CURRENT_BUILD + 1))
fi

plist_set "$INFO_PLIST_SOURCE" CFBundleVersion "$NEXT_BUILD"

bash "$ROOT_DIR/scripts/generate_app_icon.sh"

swift build -c release --package-path "$ROOT_DIR"

if [[ ! -f "$RELEASE_BINARY" ]]; then
  echo "Missing release binary: $RELEASE_BINARY" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$RELEASE_BINARY" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.jkfisher.PhotoDescriptionCreator</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$CURRENT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$NEXT_BUILD</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Photo Description Creator needs automation access to update captions and keywords in Photos.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Photo Description Creator reads selected photos and videos to generate captions and keywords.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
echo "Version: $CURRENT_VERSION ($NEXT_BUILD)"
