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
   [ ! -f "$SOURCE/vibekits-parent-watchdog.mjs" ] || \
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
ADB_METADATA_SOURCE_DIRECTORY="$(dirname "$ADB_SOURCE")"
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

ADB_RESOLVED_SOURCE_DIRECTORY="$(dirname "$ADB_SOURCE")"
ADB_METADATA_DESTINATION="$APP_BUNDLE/Contents/Resources/tools/adb"
rm -rf "$ADB_METADATA_DESTINATION"
mkdir -p "$ADB_METADATA_DESTINATION"
for ADB_METADATA in NOTICE.txt source.properties package.xml; do
  ADB_METADATA_SOURCE="$ADB_METADATA_SOURCE_DIRECTORY/$ADB_METADATA"
  if [ ! -f "$ADB_METADATA_SOURCE" ]; then
    ADB_METADATA_SOURCE="$ADB_RESOLVED_SOURCE_DIRECTORY/$ADB_METADATA"
  fi
  if [ -f "$ADB_METADATA_SOURCE" ]; then
    ditto "$ADB_METADATA_SOURCE" \
      "$ADB_METADATA_DESTINATION/$ADB_METADATA"
  fi
done
for ADB_REQUIRED_METADATA in NOTICE.txt source.properties; do
  if [ ! -f "$ADB_METADATA_DESTINATION/$ADB_REQUIRED_METADATA" ]; then
    echo "Official Android Platform-Tools metadata is missing: $ADB_REQUIRED_METADATA" >&2
    exit 4
  fi
done
echo "Packaged ADB runtime: $ADB_DESTINATION/adb"

# Archive features advertise RAR/ISO/ZSTD support on macOS only when the
# official App-private 7-Zip executable is present. Never fall back to PATH.
SEVEN_ZIP_SOURCE="$PROJECT_ROOT/native/7zip/macos/runtime"
SEVEN_ZIP_DESTINATION="$APP_BUNDLE/Contents/Resources/tools/7zip"
SEVEN_ZIP_EXPECTED_SHA256="5c2fd36f00a66f7787dcf1badd977d44a02b50063fe5678e1f19ff64797432ed"
if [ ! -x "$SEVEN_ZIP_SOURCE/7zz" ]; then
  echo "Official macOS 7-Zip runtime is missing." >&2
  echo "Run tool/prepare_7zip_runtime_macos.sh before Release packaging." >&2
  exit 5
fi
SEVEN_ZIP_SOURCE_SHA256="$(shasum -a 256 "$SEVEN_ZIP_SOURCE/7zz" | awk '{print $1}')"
if [ "$SEVEN_ZIP_SOURCE_SHA256" != "$SEVEN_ZIP_EXPECTED_SHA256" ]; then
  echo "Official macOS 7-Zip source SHA-256 mismatch: $SEVEN_ZIP_SOURCE_SHA256" >&2
  exit 5
fi
rm -rf "$SEVEN_ZIP_DESTINATION"
mkdir -p "$SEVEN_ZIP_DESTINATION"
ditto "$SEVEN_ZIP_SOURCE/7zz" "$SEVEN_ZIP_DESTINATION/7zz"
chmod 755 "$SEVEN_ZIP_DESTINATION/7zz"
for SEVEN_ZIP_METADATA in License.txt readme.txt History.txt RUNTIME-INFO.txt; do
  if [ -f "$SEVEN_ZIP_SOURCE/$SEVEN_ZIP_METADATA" ]; then
    ditto "$SEVEN_ZIP_SOURCE/$SEVEN_ZIP_METADATA" \
      "$SEVEN_ZIP_DESTINATION/$SEVEN_ZIP_METADATA"
  fi
done
codesign --force --sign - "$SEVEN_ZIP_DESTINATION/7zz"
echo "Packaged 7-Zip runtime: $SEVEN_ZIP_DESTINATION/7zz"

# Git features must work on a clean Mac without Xcode Command Line Tools.
# Package the pinned Universal runtime instead of falling back to /usr/bin/git.
GIT_SOURCE="$PROJECT_ROOT/native/git/macos/runtime"
GIT_DESTINATION="$APP_BUNDLE/Contents/Resources/tools/git"
if [ ! -x "$GIT_SOURCE/bin/git" ] || \
   [ ! -x "$GIT_SOURCE/libexec/git-core/git-remote-https" ] || \
   [ ! -d "$GIT_SOURCE/share/git-core/templates" ]; then
  echo "Official macOS Git runtime is missing or incomplete." >&2
  echo "Run tool/prepare_git_runtime_macos.sh before Release packaging." >&2
  exit 6
fi
rm -rf "$GIT_DESTINATION"
mkdir -p "$GIT_DESTINATION"
ditto "$GIT_SOURCE" "$GIT_DESTINATION"
GIT_SIGNED_INODES="$(mktemp)"
trap 'rm -f "$GIT_SIGNED_INODES"' EXIT
while IFS= read -r -d '' GIT_ITEM; do
  GIT_KIND="$(/usr/bin/file -b "$GIT_ITEM")"
  case "$GIT_KIND" in
    Mach-O*)
      GIT_INODE="$(stat -f '%i' "$GIT_ITEM")"
      if grep -Fxq "$GIT_INODE" "$GIT_SIGNED_INODES"; then
        continue
      fi
      printf '%s\n' "$GIT_INODE" >> "$GIT_SIGNED_INODES"
      chmod 755 "$GIT_ITEM"
      codesign --force --sign - "$GIT_ITEM"
      ;;
  esac
done < <(find "$GIT_DESTINATION" -type f -print0)
echo "Packaged Git runtime: $GIT_DESTINATION/bin/git"
