#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1/Contents" ]; then
  echo "usage: sign_macos_developer_id.sh <App bundle>" >&2
  exit 2
fi

APP_BUNDLE="$(cd "$1" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${VIBEKITS_DEVELOPER_ID_APPLICATION:-}"
HARNESS_NODE="$APP_BUNDLE/Contents/Resources/tools/harness/bin/node"
HARNESS_NODE_ENTITLEMENTS="$PROJECT_ROOT/macos/Runner/HarnessNode.entitlements"
SIGNED_INODES="$(mktemp)"
trap 'rm -f "$SIGNED_INODES"' EXIT

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
    Mach-O*)
      INODE="$(stat -f '%i' "$ITEM")"
      if grep -Fxq "$INODE" "$SIGNED_INODES"; then
        continue
      fi
      printf '%s\n' "$INODE" >> "$SIGNED_INODES"
      codesign --force --timestamp --options runtime --sign "$IDENTITY" "$ITEM"
      ;;
  esac
done < <(find \
  "$APP_BUNDLE/Contents/MacOS" \
  "$APP_BUNDLE/Contents/Resources/tools" \
  "$APP_BUNDLE/Contents/Frameworks" \
  -type f \( -perm -111 -o -name '*.dylib' -o -name '*.node' \) -print0)

while IFS= read -r -d '' FRAMEWORK; do
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$FRAMEWORK"
done < <(find "$APP_BUNDLE/Contents/Frameworks" -depth -type d -name '*.framework' -print0)

# A generic Hardened Runtime signature strips the JIT exception required by
# V8. Re-sign the embedded Node explicitly before sealing the outer App.
codesign --force --timestamp --options runtime --sign "$IDENTITY" \
  --entitlements "$HARNESS_NODE_ENTITLEMENTS" \
  "$HARNESS_NODE"

codesign --force --timestamp --options runtime --sign "$IDENTITY" \
  --entitlements "$PROJECT_ROOT/macos/Runner/Release.entitlements" \
  "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

EXPECTED_TEAM_ID="$(codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | \
  awk -F= '/^TeamIdentifier=/{print $2; exit}')"
if [ -z "$EXPECTED_TEAM_ID" ] || [ "$EXPECTED_TEAM_ID" = "not set" ]; then
  echo "Developer ID App signature has no TeamIdentifier." >&2
  exit 5
fi

VERIFIED_MACHO_COUNT=0
while IFS= read -r -d '' ITEM; do
  KIND="$(/usr/bin/file -b "$ITEM")"
  case "$KIND" in
    Mach-O*)
      DETAILS="$(codesign -dv --verbose=4 "$ITEM" 2>&1)"
      if ! printf '%s\n' "$DETAILS" | grep -Fqx "Authority=$IDENTITY"; then
        echo "Unexpected signing authority: $ITEM" >&2
        exit 5
      fi
      if ! printf '%s\n' "$DETAILS" | grep -Fqx "TeamIdentifier=$EXPECTED_TEAM_ID"; then
        echo "Nested code TeamIdentifier mismatch: $ITEM" >&2
        exit 5
      fi
      if ! printf '%s\n' "$DETAILS" | grep -Eq '^CodeDirectory .*flags=.*runtime'; then
        echo "Nested code is missing Hardened Runtime: $ITEM" >&2
        exit 5
      fi
      VERIFIED_MACHO_COUNT=$((VERIFIED_MACHO_COUNT + 1))
      ;;
  esac
done < <(find \
  "$APP_BUNDLE/Contents/MacOS" \
  "$APP_BUNDLE/Contents/Resources/tools" \
  "$APP_BUNDLE/Contents/Frameworks" \
  -type f \( -perm -111 -o -name '*.dylib' -o -name '*.node' \) -print0)
if [ "$VERIFIED_MACHO_COUNT" -lt 20 ]; then
  echo "Developer ID verification found too few Mach-O payloads: $VERIFIED_MACHO_COUNT" >&2
  exit 5
fi
"$PROJECT_ROOT/tool/verify_macos_harness_signed_runtime.sh" "$APP_BUNDLE"
echo "Developer ID signed and verified $VERIFIED_MACHO_COUNT Mach-O files: $APP_BUNDLE"
