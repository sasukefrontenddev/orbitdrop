#!/bin/sh
set -eu

VERSION="${1#v}"
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
  echo "Version must use the form 1.2.3" >&2
  exit 1
}

BUILD_NUMBER="$(echo "$VERSION" | awk -F. '{ print ($1 * 10000) + ($2 * 100) + $3 }')"

OLD_VERSION="$(sed -n 's:.*<Version>\([^<]*\)</Version>.*:\1:p' "$ROOT/windows/OrbitDrop.Native.csproj")"
perl -0pi -e "s/<Version>\\Q$OLD_VERSION\\E<\\/Version>/<Version>$VERSION<\\/Version>/" "$ROOT/windows/OrbitDrop.Native.csproj"
perl -0pi -e "s/<key>CFBundleShortVersionString<\\/key>\\s*<string>[^<]+<\\/string>/<key>CFBundleShortVersionString<\\/key>\n    <string>$VERSION<\\/string>/" "$ROOT/macos/Info.plist"
perl -0pi -e "s/<key>CFBundleVersion<\\/key>\\s*<string>[^<]+<\\/string>/<key>CFBundleVersion<\\/key>\n    <string>$BUILD_NUMBER<\\/string>/" "$ROOT/macos/Info.plist"
perl -0pi -e "s/assemblyIdentity version=\"[^\"]+\"/assemblyIdentity version=\"$VERSION.0\"/" "$ROOT/windows/app.manifest"

cd "$ROOT"
sh scripts/verify-version.sh "$VERSION"
