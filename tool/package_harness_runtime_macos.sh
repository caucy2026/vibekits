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
