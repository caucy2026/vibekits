#!/bin/bash
set -euo pipefail

VERSION='2.100.0'
AMD64_SHA='fcd7799e85eb575f3c7d2b1679bfbfedaefa1269d4bc7d096b51e10939b4812b'
ARM64_SHA='45f9a62da2f6e641a7fad57e2ce39656dfd7ef331372d80a2a2aed65abb01642'
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_ROOT="$PROJECT_ROOT/.tmp/github-cli-macos"
TARGET="$PROJECT_ROOT/native/github_cli/macos/runtime"
rm -rf "$TEMP_ROOT"
mkdir -p "$TEMP_ROOT" "$TARGET/bin"
trap 'rm -rf "$TEMP_ROOT"' EXIT

for ARCH in amd64 arm64; do
  ARCHIVE="gh_${VERSION}_macOS_${ARCH}.zip"
  URL="https://github.com/cli/cli/releases/download/v${VERSION}/${ARCHIVE}"
  curl --fail --location --retry 3 "$URL" --output "$TEMP_ROOT/$ARCHIVE"
  EXPECTED="$AMD64_SHA"
  [ "$ARCH" = arm64 ] && EXPECTED="$ARM64_SHA"
  ACTUAL="$(shasum -a 256 "$TEMP_ROOT/$ARCHIVE" | awk '{print $1}')"
  [ "$ACTUAL" = "$EXPECTED" ] || { echo "SHA-256 mismatch for $ARCHIVE" >&2; exit 3; }
  ditto -x -k "$TEMP_ROOT/$ARCHIVE" "$TEMP_ROOT/$ARCH"
done

rm -rf "$TARGET"
mkdir -p "$TARGET/bin" "$TARGET/share/man/man1"
lipo -create \
  "$TEMP_ROOT/amd64/gh_${VERSION}_macOS_amd64/bin/gh" \
  "$TEMP_ROOT/arm64/gh_${VERSION}_macOS_arm64/bin/gh" \
  -output "$TARGET/bin/gh"
chmod 755 "$TARGET/bin/gh"
ditto "$TEMP_ROOT/arm64/gh_${VERSION}_macOS_arm64/share/man/man1" "$TARGET/share/man/man1"
ditto "$TEMP_ROOT/arm64/gh_${VERSION}_macOS_arm64/LICENSE" "$TARGET/LICENSE"
cat > "$TARGET/vibekits-github-cli-runtime.json" <<EOF
{"distribution":"GitHub CLI","version":"$VERSION","platform":"macos","architecture":"universal","sources":{"amd64Sha256":"$AMD64_SHA","arm64Sha256":"$ARM64_SHA"},"license":"MIT"}
EOF
"$TARGET/bin/gh" --version | head -n 1
lipo -archs "$TARGET/bin/gh"
echo "Prepared Universal GitHub CLI runtime: $TARGET"
