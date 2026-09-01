#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="25.01"
ARCHIVE="7z2501-mac.tar.xz"
EXPECTED_SHA256="26aa75bc262bb10bf0805617b95569c3035c2c590a99f7db55c7e9607b2685e0"
URL="https://github.com/ip7z/7zip/releases/download/$VERSION/$ARCHIVE"
DESTINATION="$PROJECT_ROOT/native/7zip/macos/runtime"
TEMPORARY="$(mktemp -d)"
trap 'rm -rf "$TEMPORARY"' EXIT

if [ -n "${VIBEKITS_7ZIP_ARCHIVE:-}" ]; then
  if [ ! -f "$VIBEKITS_7ZIP_ARCHIVE" ]; then
    echo "VIBEKITS_7ZIP_ARCHIVE does not exist: $VIBEKITS_7ZIP_ARCHIVE" >&2
    exit 2
  fi
  ditto "$VIBEKITS_7ZIP_ARCHIVE" "$TEMPORARY/$ARCHIVE"
else
  curl -fL --retry 3 --connect-timeout 20 "$URL" -o "$TEMPORARY/$ARCHIVE"
fi
ACTUAL_SHA256="$(shasum -a 256 "$TEMPORARY/$ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "7-Zip SHA-256 mismatch: $ACTUAL_SHA256" >&2
  exit 3
fi
tar -xf "$TEMPORARY/$ARCHIVE" -C "$TEMPORARY"
if [ ! -x "$TEMPORARY/7zz" ]; then
  echo "Official archive does not contain executable 7zz." >&2
  exit 4
fi
ARCHS="$(lipo -archs "$TEMPORARY/7zz")"
case " $ARCHS " in
  *" arm64 "*) ;;
  *) echo "7zz is missing arm64: $ARCHS" >&2; exit 5 ;;
esac
case " $ARCHS " in
  *" x86_64 "*) ;;
  *) echo "7zz is missing x86_64: $ARCHS" >&2; exit 6 ;;
esac
for ARCH in x86_64 arm64; do
  MINIMUM="$(xcrun vtool -show-build "$TEMPORARY/7zz" | awk -v arch="$ARCH" '
    $0 ~ "architecture " arch { selected=1; next }
    selected && /minos/ { print $2; exit }
  ')"
  if [ "$MINIMUM" != "12.0" ]; then
    echo "7zz $ARCH minimum macOS must be 12.0, got ${MINIMUM:-missing}" >&2
    exit 7
  fi
done
rm -rf "$DESTINATION"
mkdir -p "$DESTINATION"
for ITEM in 7zz License.txt readme.txt History.txt; do
  if [ -f "$TEMPORARY/$ITEM" ]; then
    ditto "$TEMPORARY/$ITEM" "$DESTINATION/$ITEM"
  fi
done
chmod 755 "$DESTINATION/7zz"
SEVEN_ZIP_SHA256="$(shasum -a 256 "$DESTINATION/7zz" | awk '{print $1}')"
cat > "$DESTINATION/RUNTIME-INFO.txt" <<EOF
7-Zip macOS Release Runtime
Version: $VERSION
Upstream: $URL
Source archive SHA-256: $EXPECTED_SHA256
Bundled 7zz SHA-256: $SEVEN_ZIP_SHA256
Architectures: x86_64, arm64
Minimum macOS: 12.0

The pinned preparation recipe remains in tool/prepare_7zip_runtime_macos.sh.
License.txt, readme.txt and History.txt are copied from the verified upstream
archive and travel with this executable.
EOF
"$DESTINATION/7zz" i | grep -F "7-Zip $VERSION" >/dev/null
echo "Prepared official 7-Zip $VERSION runtime ($ARCHS): $DESTINATION"
