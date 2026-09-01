#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1/Contents" ]; then
  echo "usage: sign_macos_release.sh <App bundle>" >&2
  exit 2
fi

APP_BUNDLE="$(cd "$1" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$APP_BUNDLE/Contents/Resources/tools/harness"
TOOLS_ROOT="$APP_BUNDLE/Contents/Resources/tools"
HARNESS_NODE="$RUNTIME/bin/node"
SIGNED_MACHO=0
SIGNED_INODES="$(mktemp)"
trap 'rm -f "$SIGNED_INODES"' EXIT

sign_file() {
  ITEM="$1"
  INODE="$(stat -f '%i' "$ITEM")"
  if grep -Fxq "$INODE" "$SIGNED_INODES"; then
    return
  fi
  printf '%s\n' "$INODE" >> "$SIGNED_INODES"
  if codesign --display "$ITEM" >/dev/null 2>&1; then
    codesign --force --sign - \
      --preserve-metadata=identifier,entitlements,requirements \
      "$ITEM" >/dev/null
  else
    codesign --force --sign - "$ITEM" >/dev/null
  fi
  SIGNED_MACHO=$((SIGNED_MACHO + 1))
}

while IFS= read -r -d '' ITEM; do
  KIND="$(/usr/bin/file -b "$ITEM")"
  case "$KIND" in
    Mach-O*) sign_file "$ITEM" ;;
  esac
done < <(find "$TOOLS_ROOT" "$APP_BUNDLE/Contents/Frameworks" -type f \
  \( -perm -111 -o -name '*.dylib' -o -name '*.node' \) -print0)

# Re-seal framework bundles after their binaries have been signed.
while IFS= read -r -d '' FRAMEWORK; do
  codesign --force --sign - \
    --preserve-metadata=identifier,entitlements,requirements \
    "$FRAMEWORK" >/dev/null
done < <(find "$APP_BUNDLE/Contents/Frameworks" -depth -type d -name '*.framework' -print0)

codesign --force --options runtime --sign - \
  --entitlements "$PROJECT_ROOT/macos/Runner/HarnessNodeAdHoc.entitlements" \
  "$HARNESS_NODE" >/dev/null

codesign --force --sign - \
  --entitlements "$PROJECT_ROOT/macos/Runner/Release.entitlements" \
  "$APP_BUNDLE" >/dev/null

while IFS= read -r -d '' ITEM; do
  KIND="$(/usr/bin/file -b "$ITEM")"
  case "$KIND" in
    Mach-O*)
      VERIFY_INODE="$(stat -f '%i' "$ITEM")"
      if ! grep -Fxq "verify:$VERIFY_INODE" "$SIGNED_INODES"; then
        printf 'verify:%s\n' "$VERIFY_INODE" >> "$SIGNED_INODES"
        codesign --verify --strict "$ITEM"
      fi
      ;;
  esac
done < <(find "$TOOLS_ROOT" "$APP_BUNDLE/Contents/Frameworks" -type f \
  \( -perm -111 -o -name '*.dylib' -o -name '*.node' \) -print0)
codesign --verify --strict "$APP_BUNDLE"
echo "Signed and verified $SIGNED_MACHO Mach-O files: $APP_BUNDLE"
