#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/OrbitDrop.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MODULE_CACHE="${TMPDIR:-/private/tmp}/orbitdrop-clang-module-cache"
ARM_BINARY="$BUILD_DIR/OrbitDrop-arm64"
INTEL_BINARY="$BUILD_DIR/OrbitDrop-x86_64"
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:--}"

if [[ -d "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$MODULE_CACHE"

for BUILD_ARCH in arm64 x86_64; do
  OUTPUT_BINARY="$ARM_BINARY"
  if [[ "$BUILD_ARCH" == "x86_64" ]]; then
    OUTPUT_BINARY="$INTEL_BINARY"
  fi

  SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE-$BUILD_ARCH" swiftc \
    -sdk "$SDK_PATH" \
    -target "$BUILD_ARCH-apple-macosx13.0" \
    -swift-version 5 \
    -parse-as-library \
    -O \
    "$SCRIPT_DIR"/Sources/*.swift \
    -framework AppKit \
    -framework ApplicationServices \
    -framework QuartzCore \
    -o "$OUTPUT_BINARY"
done

lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$APP_DIR/Contents/MacOS/OrbitDrop"

cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SCRIPT_DIR/OrbitDrop.icns" "$APP_DIR/Contents/Resources/OrbitDrop.icns"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_DIR"
else
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$SCRIPT_DIR/OrbitDrop.entitlements" \
    --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
