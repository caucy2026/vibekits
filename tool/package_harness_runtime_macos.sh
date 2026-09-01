#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: package_harness_runtime_macos.sh <App bundle>" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$PROJECT_ROOT/native/harness/macos/runtime"
APP_BUNDLE="$1"
DESTINATION="$APP_BUNDLE/Contents/Resources/tools/harness"
LEGACY_DESTINATION="$APP_BUNDLE/Contents/MacOS/tools/harness"

if [ ! -f "$SOURCE/harness-runtime.json" ] || \
   [ ! -x "$SOURCE/bin/node" ] || \
   [ ! -f "$SOURCE/vibekits-mcp-server.mjs" ] || \
   [ ! -f "$SOURCE/vibekits-approval.mjs" ] || \
   [ ! -f "$SOURCE/vibekits-android-stress-mcp.mjs" ]; then
  echo "Bundled macOS Harness runtime is missing or incomplete." >&2
  echo "Run tool/prepare_harness_runtime_macos.sh before Release packaging." >&2
  exit 3
fi

rm -rf "$DESTINATION" "$LEGACY_DESTINATION"
mkdir -p "$(dirname "$DESTINATION")"
ditto "$SOURCE" "$DESTINATION"
chmod 755 "$DESTINATION/bin/node"
codesign --force --sign - "$DESTINATION/bin/node"
echo "Packaged Harness runtime: $DESTINATION"

# Harness ADB tools intentionally resolve an App-private executable instead of
# PATH. A Release without this payload would advertise an Android handler that
# can never start, so packaging must fail rather than ship a false-ready App.
ADB_SOURCE="${VIBEKITS_ADB_SOURCE:-}"
if [ -z "$ADB_SOURCE" ] && command -v adb >/dev/null 2>&1; then
  ADB_SOURCE="$(command -v adb)"
fi
if [ -z "$ADB_SOURCE" ] && [ -n "${ANDROID_SDK_ROOT:-}" ]; then
  ADB_SOURCE="$ANDROID_SDK_ROOT/platform-tools/adb"
fi
if [ -z "$ADB_SOURCE" ] && [ -n "${ANDROID_HOME:-}" ]; then
  ADB_SOURCE="$ANDROID_HOME/platform-tools/adb"
fi
if [ -z "$ADB_SOURCE" ] || [ ! -x "$ADB_SOURCE" ]; then
  echo "Official Android Platform-Tools adb was not found." >&2
  echo "Set VIBEKITS_ADB_SOURCE or put adb on PATH before Release packaging." >&2
  exit 4
fi
if [ -L "$ADB_SOURCE" ]; then
  ADB_LINK_TARGET="$(readlink "$ADB_SOURCE")"
  if [[ "$ADB_LINK_TARGET" = /* ]]; then
    ADB_SOURCE="$ADB_LINK_TARGET"
  else
    ADB_SOURCE="$(dirname "$ADB_SOURCE")/$ADB_LINK_TARGET"
  fi
fi

ADB_DESTINATION="$APP_BUNDLE/Contents/MacOS/tools/adb"
rm -rf "$ADB_DESTINATION"
mkdir -p "$ADB_DESTINATION"
ditto "$ADB_SOURCE" "$ADB_DESTINATION/adb"
chmod 755 "$ADB_DESTINATION/adb"
codesign --force --sign - "$ADB_DESTINATION/adb"

ADB_SOURCE_DIRECTORY="$(dirname "$ADB_SOURCE")"
for ADB_METADATA in NOTICE.txt source.properties package.xml; do
  if [ -f "$ADB_SOURCE_DIRECTORY/$ADB_METADATA" ]; then
    ditto "$ADB_SOURCE_DIRECTORY/$ADB_METADATA" \
      "$ADB_DESTINATION/$ADB_METADATA"
  fi
done
echo "Packaged ADB runtime: $ADB_DESTINATION/adb"
