#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MODULE_CACHE="${TMPDIR:-/private/tmp}/orbitdrop-test-module-cache"
TEST_BINARY="$SCRIPT_DIR/build/OrbitDropTests"
FIXTURES_DIR="$SCRIPT_DIR/Tests/Fixtures"

mkdir -p "$SCRIPT_DIR/build" "$MODULE_CACHE"

SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx13.0 \
  -swift-version 5 \
  -parse-as-library \
  "$SCRIPT_DIR/Sources/TriggerKey.swift" \
  "$SCRIPT_DIR/Sources/FinderBridge.swift" \
  "$SCRIPT_DIR/Sources/UpdateChecker.swift" \
  "$SCRIPT_DIR/Sources/RadialPanel.swift" \
  "$SCRIPT_DIR/Sources/FileOperations.swift" \
  "$SCRIPT_DIR/Tests/OperationTests.swift" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework QuartzCore \
  -o "$TEST_BINARY"

"$TEST_BINARY" "$FIXTURES_DIR/sample.png" "$FIXTURES_DIR/conversion-sample.docx"
