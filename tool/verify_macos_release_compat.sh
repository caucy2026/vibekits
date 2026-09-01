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

minos_for_arch() {
  ITEM="$1"
  ARCH="$2"
  ARCHES="$(lipo -archs "$ITEM")"
  case "$ARCHES" in
    *' '*)
      xcrun vtool -show-build "$ITEM" | awk -v arch="$ARCH" '
        $0 ~ "architecture " arch { selected=1; next }
        selected && /minos|^[[:space:]]+version/ { print $2; exit }
      '
      ;;
    *)
      xcrun vtool -show-build "$ITEM" | awk '
        /minos|^[[:space:]]+version/ { print $2; exit }
      '
      ;;
  esac
}

require_minos_at_most_12() {
  ITEM="$1"
  for ARCH in $(lipo -archs "$ITEM"); do
    MINIMUM="$(minos_for_arch "$ITEM" "$ARCH")"
    if [ -z "$MINIMUM" ] || ! awk -v value="$MINIMUM" 'BEGIN {
      split(value, parts, ".")
      exit !((parts[1] + 0) < 12 || ((parts[1] + 0) == 12 && (parts[2] + 0) <= 0))
    }'; then
      echo "Mach-O requires newer than macOS 12.0 ($ARCH minos=${MINIMUM:-missing}): $ITEM" >&2
      exit 5
    fi
  done
}

for ITEM in \
  "$APP_BUNDLE/Contents/MacOS/Vibekits" \
  "$APP_BUNDLE/Contents/MacOS/tools/adb/adb" \
  "$APP_BUNDLE/Contents/Resources/tools/harness/bin/node" \
  "$APP_BUNDLE/Contents/Resources/tools/7zip/7zz" \
  "$APP_BUNDLE/Contents/Resources/tools/git/bin/git" \
  "$APP_BUNDLE/Contents/Frameworks/App.framework/Versions/A/App" \
  "$APP_BUNDLE/Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS"; do
  require_file "$ITEM"
  require_arches "$ITEM"
done

GIT_MACHO_COUNT=0
while IFS= read -r -d '' ITEM; do
  KIND="$(/usr/bin/file -b "$ITEM")"
  case "$KIND" in
    Mach-O*)
      require_arches "$ITEM"
      for ARCH in x86_64 arm64; do
        GIT_MINIMUM="$(minos_for_arch "$ITEM" "$ARCH")"
        if [ "$GIT_MINIMUM" != "12.0" ]; then
          echo "Expected Git $ARCH minimum macOS 12.0, got ${GIT_MINIMUM:-missing}: $ITEM" >&2
          exit 5
        fi
      done
      GIT_MACHO_COUNT=$((GIT_MACHO_COUNT + 1))
      ;;
  esac
done < <(find "$APP_BUNDLE/Contents/Resources/tools/git" -type f \
  \( -perm -111 -o -name '*.dylib' -o -name '*.node' \) -print0)
if [ "$GIT_MACHO_COUNT" -lt 2 ]; then
  echo "Expected complete Git runtime, found $GIT_MACHO_COUNT Mach-O files." >&2
  exit 5
fi

for ARCH in x86_64 arm64; do
  SEVEN_ZIP_MINIMUM="$(minos_for_arch \
    "$APP_BUNDLE/Contents/Resources/tools/7zip/7zz" "$ARCH")"
  if [ "$SEVEN_ZIP_MINIMUM" != "12.0" ]; then
    echo "Expected 7zz $ARCH minimum macOS 12.0, got ${SEVEN_ZIP_MINIMUM:-missing}" >&2
    exit 5
  fi
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
if [ "$MINIMUM" != "12.0" ]; then
  echo "Expected LSMinimumSystemVersion 12.0, got $MINIMUM" >&2
  exit 5
fi

X64_MINIMUM="$(minos_for_arch "$APP_BUNDLE/Contents/MacOS/Vibekits" x86_64)"
if [ "$X64_MINIMUM" != "12.0" ]; then
  echo "Expected x86_64 minimum macOS 12.0, got $X64_MINIMUM" >&2
  exit 5
fi

NODE_X64_MINIMUM="$(minos_for_arch \
  "$APP_BUNDLE/Contents/Resources/tools/harness/bin/node" x86_64)"
if [ "$NODE_X64_MINIMUM" != "11.0" ]; then
  echo "Expected Harness Node x86_64 minimum macOS 11.0, got $NODE_X64_MINIMUM" >&2
  exit 5
fi

while IFS= read -r -d '' ITEM; do
  KIND="$(/usr/bin/file -b "$ITEM")"
  case "$KIND" in
    Mach-O*) require_minos_at_most_12 "$ITEM" ;;
  esac
done < <(find "$APP_BUNDLE/Contents" -type f \
  \( -perm -111 -o -name '*.dylib' -o -name '*.node' \) -print0)

echo "Verified full-function Universal macOS 12+ Release: Harness, 7-Zip, Git and App=$APP_BUNDLE"
