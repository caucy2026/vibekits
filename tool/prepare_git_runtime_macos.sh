#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="2.53.0"
ARCHIVE="git-$VERSION.tar.xz"
EXPECTED_SHA256="5818bd7d80b061bbbdfec8a433d609dc8818a05991f731ffc4a561e2ca18c653"
URL="https://mirrors.edge.kernel.org/pub/software/scm/git/$ARCHIVE"
DESTINATION="$PROJECT_ROOT/native/git/macos/runtime"
TEMPORARY="$(mktemp -d)"
trap 'rm -rf "$TEMPORARY"' EXIT

if [ -n "${VIBEKITS_GIT_SOURCE_ARCHIVE:-}" ]; then
  if [ ! -f "$VIBEKITS_GIT_SOURCE_ARCHIVE" ]; then
    echo "VIBEKITS_GIT_SOURCE_ARCHIVE does not exist: $VIBEKITS_GIT_SOURCE_ARCHIVE" >&2
    exit 2
  fi
  ditto "$VIBEKITS_GIT_SOURCE_ARCHIVE" "$TEMPORARY/$ARCHIVE"
else
  curl -fL --retry 3 --connect-timeout 20 "$URL" -o "$TEMPORARY/$ARCHIVE"
fi

ACTUAL_SHA256="$(shasum -a 256 "$TEMPORARY/$ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "Git source SHA-256 mismatch: $ACTUAL_SHA256" >&2
  exit 3
fi

tar -xJf "$TEMPORARY/$ARCHIVE" -C "$TEMPORARY"
SOURCE="$TEMPORARY/git-$VERSION"
CPU_COUNT="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"

build_arch() {
  ARCH="$1"
  BUILD="$TEMPORARY/build-$ARCH"
  STAGE="$TEMPORARY/stage-$ARCH"
  ditto "$SOURCE" "$BUILD"
  (
    cd "$BUILD"
    MACOSX_DEPLOYMENT_TARGET=12.0 ./configure \
      --prefix=/ \
      --without-tcltk \
      CFLAGS="-O2 -arch $ARCH -mmacosx-version-min=12.0" \
      LDFLAGS="-arch $ARCH -mmacosx-version-min=12.0" >/dev/null
    MACOSX_DEPLOYMENT_TARGET=12.0 make -j"$CPU_COUNT" \
      NO_GETTEXT=YesPlease \
      NO_TCLTK=YesPlease \
      NO_PERL=YesPlease \
      NO_PYTHON=YesPlease \
      APPLE_COMMON_CRYPTO=YesPlease >/dev/null
    MACOSX_DEPLOYMENT_TARGET=12.0 make \
      NO_GETTEXT=YesPlease \
      NO_TCLTK=YesPlease \
      NO_PERL=YesPlease \
      NO_PYTHON=YesPlease \
      APPLE_COMMON_CRYPTO=YesPlease \
      DESTDIR="$STAGE" install >/dev/null
  )
  if [ ! -x "$STAGE/bin/git" ] || \
     [ ! -x "$STAGE/libexec/git-core/git-remote-https" ]; then
    echo "Git $ARCH build is incomplete." >&2
    exit 4
  fi
}

build_arch x86_64
build_arch arm64

rm -rf "$DESTINATION"
mkdir -p "$(dirname "$DESTINATION")"
ditto "$TEMPORARY/stage-arm64" "$DESTINATION"
mkdir -p "$DESTINATION/share/licenses/git" "$DESTINATION/share/source/git"
ditto "$SOURCE/COPYING" "$DESTINATION/share/licenses/git/COPYING"
ditto "$TEMPORARY/$ARCHIVE" \
  "$DESTINATION/share/source/git/$ARCHIVE"
printf '%s\n' \
  "Git $VERSION" \
  "Upstream: https://git.kernel.org/pub/scm/git/git.git" \
  "Source archive SHA-256: $EXPECTED_SHA256" \
  "Build target: x86_64 + arm64, macOS 12.0" \
  > "$DESTINATION/share/source/git/BUILD-INFO.txt"

MACHO_COUNT=0
while IFS= read -r -d '' ARM_ITEM; do
  KIND="$(/usr/bin/file -b "$ARM_ITEM")"
  case "$KIND" in
    Mach-O*)
      RELATIVE="${ARM_ITEM#"$TEMPORARY/stage-arm64/"}"
      X64_ITEM="$TEMPORARY/stage-x86_64/$RELATIVE"
      DEST_ITEM="$DESTINATION/$RELATIVE"
      if [ ! -f "$X64_ITEM" ]; then
        echo "Git x86_64 counterpart is missing: $RELATIVE" >&2
        exit 5
      fi
      lipo -create "$X64_ITEM" "$ARM_ITEM" -output "$DEST_ITEM"
      chmod 755 "$DEST_ITEM"
      for ARCH in x86_64 arm64; do
        MINIMUM="$(xcrun vtool -show-build "$DEST_ITEM" | awk -v arch="$ARCH" '
          $0 ~ "architecture " arch { selected=1; next }
          selected && /minos/ { print $2; exit }
        ')"
        if [ "$MINIMUM" != "12.0" ]; then
          echo "Git $RELATIVE $ARCH minimum macOS must be 12.0, got ${MINIMUM:-missing}" >&2
          exit 6
        fi
      done
      MACHO_COUNT=$((MACHO_COUNT + 1))
      ;;
  esac
done < <(find "$TEMPORARY/stage-arm64" -type f -print0)

if [ "$MACHO_COUNT" -lt 2 ]; then
  echo "Git Universal runtime is incomplete: $MACHO_COUNT Mach-O files." >&2
  exit 7
fi

# Git installs many built-in command names as hard links to the same binary.
# lipo materializes each path. Convert duplicates to relative symbolic links:
# this keeps the App compact, while allowing codesign to sign the one canonical
# file without breaking hard links and leaving unsigned aliases behind.
DEDUP_INDEX="$TEMPORARY/git-dedup-index.tsv"
: > "$DEDUP_INDEX"
DEDUP_COUNT=0
while IFS= read -r -d '' ITEM; do
  DIGEST="$(shasum -a 256 "$ITEM" | awk '{print $1}')"
  CANONICAL="$(awk -F '\t' -v digest="$DIGEST" '$1 == digest {print $2; exit}' "$DEDUP_INDEX")"
  if [ -n "$CANONICAL" ]; then
    RELATIVE_TARGET="$(/usr/bin/perl -MFile::Spec -e \
      'print File::Spec->abs2rel($ARGV[0], $ARGV[1])' \
      "$CANONICAL" "$(dirname "$ITEM")")"
    rm "$ITEM"
    ln -s "$RELATIVE_TARGET" "$ITEM"
    DEDUP_COUNT=$((DEDUP_COUNT + 1))
  else
    printf '%s\t%s\n' "$DIGEST" "$ITEM" >> "$DEDUP_INDEX"
  fi
done < <(find "$DESTINATION" -type f -print0)

ARCHS="$(lipo -archs "$DESTINATION/bin/git")"
"$DESTINATION/bin/git" --version | grep -F "git version $VERSION" >/dev/null
GIT_EXEC_PATH="$DESTINATION/libexec/git-core" \
  "$DESTINATION/bin/git" --exec-path | grep -F "$DESTINATION/libexec/git-core" >/dev/null
echo "Prepared Git $VERSION Universal runtime ($ARCHS, $MACHO_COUNT Mach-O files, $DEDUP_COUNT symbolic-link duplicates): $DESTINATION"
