#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RES_DIR="$ROOT_DIR/Sources/PhotosCaptionAssistant/Resources"
ICONSET_DIR="$RES_DIR/AppIcon.iconset"
MASTER_PNG="$RES_DIR/AppIcon-1024.png"
ICNS_PATH="$RES_DIR/AppIcon.icns"
CACHE_HOME="$ROOT_DIR/.cache-home"
MODULE_CACHE_DIR="$ROOT_DIR/.build/module-cache"

mkdir -p "$ICONSET_DIR" "$CACHE_HOME" "$MODULE_CACHE_DIR"

# Keep swift transient cache writes inside the workspace so generation works in sandboxed environments.
export HOME="$CACHE_HOME"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

swift "$ROOT_DIR/scripts/generate_icon.swift" "$MASTER_PNG"

generate_png() {
  local size="$1"
  local output="$2"
  sips -z "$size" "$size" "$MASTER_PNG" --out "$ICONSET_DIR/$output" >/dev/null
}

generate_png 16   icon_16x16.png
generate_png 32   icon_16x16@2x.png
generate_png 32   icon_32x32.png
generate_png 64   icon_32x32@2x.png
generate_png 128  icon_128x128.png
generate_png 256  icon_128x128@2x.png
generate_png 256  icon_256x256.png
generate_png 512  icon_256x256@2x.png
generate_png 512  icon_512x512.png
generate_png 1024 icon_512x512@2x.png

if ! iconutil --convert icns --output "$ICNS_PATH" "$ICONSET_DIR"; then
  if [[ -f "$ICNS_PATH" ]]; then
    echo "warning: iconutil failed; keeping existing $ICNS_PATH" >&2
  else
    echo "error: iconutil failed and no existing $ICNS_PATH is available" >&2
    exit 1
  fi
fi

echo "Generated:"
echo "  $MASTER_PNG"
echo "  $ICONSET_DIR"
echo "  $ICNS_PATH"
