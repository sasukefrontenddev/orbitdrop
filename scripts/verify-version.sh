#!/bin/sh
set -eu

VERSION="${1#v}"

echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
  echo "Version must use the form 1.2.3" >&2
  exit 1
}

BUILD_NUMBER="$(echo "$VERSION" | awk -F. '{ print ($1 * 10000) + ($2 * 100) + $3 }')"

if ! grep -q "<Version>$VERSION</Version>" windows/OrbitDrop.Native.csproj; then
  echo "windows/OrbitDrop.Native.csproj does not contain version $VERSION" >&2
  exit 1
fi

if ! grep -A1 'CFBundleShortVersionString' macos/Info.plist | grep -q "<string>$VERSION</string>"; then
  echo "macos/Info.plist does not contain version $VERSION" >&2
  exit 1
fi

if ! grep -A1 'CFBundleVersion' macos/Info.plist | grep -q "<string>$BUILD_NUMBER</string>"; then
  echo "macos/Info.plist does not contain build number $BUILD_NUMBER" >&2
  exit 1
fi

if ! grep -q "assemblyIdentity version=\"$VERSION.0\"" windows/app.manifest; then
  echo "windows/app.manifest does not contain version $VERSION.0" >&2
  exit 1
fi

echo "OrbitDrop version $VERSION is consistent"
