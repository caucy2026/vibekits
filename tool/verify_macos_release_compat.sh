#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1/Contents" ]; then
  echo "usage: verify_macos_release_compat.sh <App bundle>" >&2
  exit 2
fi

APP_BUNDLE="$(cd "$1" && pwd)"

require_arches() {
  ITEM="$1"
  ARCHES="$(lipo -archs "$ITEM")"
  case " $ARCHES " in *" x86_64 "*) ;; *) echo "Missing x86_64: $ITEM" >&2; exit 3;; esac
  case " $ARCHES " in *" arm64 "*) ;; *) echo "Missing arm64: $ITEM" >&2; exit 3;; esac
}

require_file() {
  ITEM="$1"
  if [ ! -f "$ITEM" ]; then
    echo "Missing compatibility payload: $ITEM" >&2
    exit 4
  fi
}

for ITEM in \
  "$APP_BUNDLE/Contents/MacOS/Vibekits" \
  "$APP_BUNDLE/Contents/MacOS/tools/adb/adb" \
  "$APP_BUNDLE/Contents/Resources/tools/harness/bin/node" \
  "$APP_BUNDLE/Contents/Frameworks/App.framework/Versions/A/App" \
  "$APP_BUNDLE/Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS"; do
  require_file "$ITEM"
  require_arches "$ITEM"
done

for ITEM in \
  "$APP_BUNDLE/Contents/Resources/tools/harness/node_modules/@vscode/ripgrep-darwin-arm64/bin/rg" \
  "$APP_BUNDLE/Contents/Resources/tools/harness/node_modules/@vscode/ripgrep-darwin-x64/bin/rg" \
  "$APP_BUNDLE/Contents/Resources/tools/harness/node_modules/node-pty/prebuilds/darwin-arm64/pty.node" \
  "$APP_BUNDLE/Contents/Resources/tools/harness/node_modules/node-pty/prebuilds/darwin-x64/pty.node" \
  "$APP_BUNDLE/Contents/Resources/tools/harness/node_modules/@img/sharp-darwin-arm64/lib/sharp-darwin-arm64-0.35.4.node" \
  "$APP_BUNDLE/Contents/Resources/tools/harness/node_modules/@img/sharp-darwin-x64/lib/sharp-darwin-x64-0.35.4.node"; do
  require_file "$ITEM"
done

MINIMUM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_BUNDLE/Contents/Info.plist")"
if [ "$MINIMUM" != "10.15" ]; then
  echo "Expected LSMinimumSystemVersion 10.15, got $MINIMUM" >&2
  exit 5
fi

X64_MINIMUM="$(xcrun vtool -show-build "$APP_BUNDLE/Contents/MacOS/Vibekits" | awk '
  /architecture x86_64/ { x64=1; next }
  x64 && /minos/ { print $2; exit }
')"
if [ "$X64_MINIMUM" != "10.15" ]; then
  echo "Expected x86_64 minimum macOS 10.15, got $X64_MINIMUM" >&2
  exit 5
fi

NODE_X64_MINIMUM="$(xcrun vtool -show-build \
  "$APP_BUNDLE/Contents/Resources/tools/harness/bin/node" | awk '
  /architecture x86_64/ { x64=1; next }
  x64 && /minos/ { print $2; exit }
')"
if [ "$NODE_X64_MINIMUM" != "11.0" ]; then
  echo "Expected Harness Node x86_64 minimum macOS 11.0, got $NODE_X64_MINIMUM" >&2
  exit 5
fi

echo "Verified Universal macOS Release: App x86_64=10.15+, Harness=11.0+, arm64=11.0+, App=$APP_BUNDLE"
