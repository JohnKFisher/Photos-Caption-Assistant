#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST_SOURCE="$ROOT_DIR/Sources/PhotosCaptionAssistant/Resources/Info.plist"
PROMPTS_SOURCE_DIR="$ROOT_DIR/Prompts"
APP_NAME="Photos Caption Assistant"
EXECUTABLE_NAME="PhotosCaptionAssistant"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
ARM64_TRIPLE="arm64-apple-macosx15.0"
X86_64_TRIPLE="x86_64-apple-macosx15.0"
ARM64_BINARY="$ROOT_DIR/.build/arm64-apple-macosx/release/$EXECUTABLE_NAME"
X86_64_BINARY="$ROOT_DIR/.build/x86_64-apple-macosx/release/$EXECUTABLE_NAME"
UNIVERSAL_DIR="$ROOT_DIR/.build/universal-apple-macosx/release"
UNIVERSAL_BINARY="$UNIVERSAL_DIR/$EXECUTABLE_NAME"
ICON_PATH="$ROOT_DIR/Sources/PhotosCaptionAssistant/Resources/AppIcon.icns"

plist_read() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

plist_set() {
  /usr/libexec/PlistBuddy -c "Set :$2 $3" "$1"
}

increment_patch_version() {
  local version="$1"
  local major minor patch
  IFS='.' read -r major minor patch <<<"$version"

  if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ || ! "$patch" =~ ^[0-9]+$ ]]; then
    echo "Version must be in major.minor.patch form: $version" >&2
    exit 1
  fi

  echo "$major.$minor.$((patch + 1))"
}

if [[ ! -f "$INFO_PLIST_SOURCE" ]]; then
  echo "Missing source Info.plist: $INFO_PLIST_SOURCE" >&2
  exit 1
fi

if [[ ! -f "$PROMPTS_SOURCE_DIR/photoprompt.txt" || ! -f "$PROMPTS_SOURCE_DIR/videoprompt.txt" ]]; then
  echo "Missing prompt files in: $PROMPTS_SOURCE_DIR" >&2
  exit 1
fi

CURRENT_VERSION="$(plist_read "$INFO_PLIST_SOURCE" CFBundleShortVersionString)"
CURRENT_BUILD="$(plist_read "$INFO_PLIST_SOURCE" CFBundleVersion)"
NEXT_VERSION="$(increment_patch_version "$CURRENT_VERSION")"

MAX_KNOWN_BUILD=0
if [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  MAX_KNOWN_BUILD="$CURRENT_BUILD"
fi

if [[ -f "$APP_BUNDLE/Contents/Info.plist" ]]; then
  DIST_BUILD="$(plist_read "$APP_BUNDLE/Contents/Info.plist" CFBundleVersion || true)"
  if [[ "$DIST_BUILD" =~ ^[0-9]+$ && "$DIST_BUILD" -gt "$MAX_KNOWN_BUILD" ]]; then
    MAX_KNOWN_BUILD="$DIST_BUILD"
  fi
fi

NEXT_BUILD=$((MAX_KNOWN_BUILD + 1))

plist_set "$INFO_PLIST_SOURCE" CFBundleShortVersionString "$NEXT_VERSION"
plist_set "$INFO_PLIST_SOURCE" CFBundleVersion "$NEXT_BUILD"

bash "$ROOT_DIR/scripts/generate_app_icon.sh"

swift build -c release --triple "$ARM64_TRIPLE" --package-path "$ROOT_DIR" --product "$EXECUTABLE_NAME"
swift build -c release --triple "$X86_64_TRIPLE" --package-path "$ROOT_DIR" --product "$EXECUTABLE_NAME"

if [[ ! -f "$ARM64_BINARY" ]]; then
  echo "Missing arm64 release binary: $ARM64_BINARY" >&2
  exit 1
fi

if [[ ! -f "$X86_64_BINARY" ]]; then
  echo "Missing x86_64 release binary: $X86_64_BINARY" >&2
  exit 1
fi

mkdir -p "$UNIVERSAL_DIR"
lipo -create -output "$UNIVERSAL_BINARY" "$ARM64_BINARY" "$X86_64_BINARY"

if [[ ! -f "$UNIVERSAL_BINARY" ]]; then
  echo "Missing universal release binary: $UNIVERSAL_BINARY" >&2
  exit 1
fi

UNIVERSAL_ARCHS="$(lipo -archs "$UNIVERSAL_BINARY")"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/Prompts"
cp "$UNIVERSAL_BINARY" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$PROMPTS_SOURCE_DIR/photoprompt.txt" "$APP_BUNDLE/Contents/Resources/Prompts/photoprompt.txt"
cp "$PROMPTS_SOURCE_DIR/videoprompt.txt" "$APP_BUNDLE/Contents/Resources/Prompts/videoprompt.txt"

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
    <string>com.jkfisher.PhotosCaptionAssistant</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$NEXT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$NEXT_BUILD</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Photos Caption Assistant needs automation access to read from Photos and update captions and keywords in Photos.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Photos Caption Assistant reads selected photos and videos and writes generated captions and keywords back to Photos.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
echo "Version: $NEXT_VERSION ($NEXT_BUILD)"
echo "Architectures: $UNIVERSAL_ARCHS"
