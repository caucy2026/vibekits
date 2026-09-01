#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1/Contents" ]; then
  echo "usage: sign_macos_developer_id.sh <App bundle>" >&2
  exit 2
fi

APP_BUNDLE="$(cd "$1" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${VIBEKITS_DEVELOPER_ID_APPLICATION:-}"

if [ -z "$IDENTITY" ]; then
  echo "Set VIBEKITS_DEVELOPER_ID_APPLICATION to a Developer ID Application identity." >&2
  exit 3
fi
if ! security find-identity -v -p codesigning | grep -Fq "$IDENTITY"; then
  echo "Developer ID Application identity is not installed: $IDENTITY" >&2
  exit 4
fi

while IFS= read -r -d '' ITEM; do
  KIND="$(/usr/bin/file -b "$ITEM")"
  case "$KIND" in
    Mach-O*) codesign --force --timestamp --options runtime --sign "$IDENTITY" "$ITEM" ;;
  esac
done < <(find \
  "$APP_BUNDLE/Contents/MacOS" \
  "$APP_BUNDLE/Contents/Resources/tools/harness" \
  "$APP_BUNDLE/Contents/Frameworks" \
  -type f -print0)

while IFS= read -r -d '' FRAMEWORK; do
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$FRAMEWORK"
done < <(find "$APP_BUNDLE/Contents/Frameworks" -depth -type d -name '*.framework' -print0)

codesign --force --timestamp --options runtime --sign "$IDENTITY" \
  --entitlements "$PROJECT_ROOT/macos/Runner/Release.entitlements" \
  "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "Developer ID signed and verified: $APP_BUNDLE"
