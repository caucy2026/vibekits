#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-/Users/newlink/flutter/bin/flutter}"
TEAM_ID="${VIBEKITS_APP_STORE_TEAM_ID:-26T5WV4GLP}"
STORE_VERSION="${VIBEKITS_APP_STORE_VERSION:-1.9.225}"
STORE_BUILD_NUMBER="${VIBEKITS_APP_STORE_BUILD_NUMBER:-2226}"
STORE_CACHE="${VIBEKITS_APP_STORE_CACHE:-/Volumes/ORICO/kemi-build-cache/vibekits-app-store-dev225}"
ARCHIVE_PATH="${VIBEKITS_APP_STORE_ARCHIVE:-$STORE_CACHE/Vibekits.xcarchive}"
EXPORT_PATH="${VIBEKITS_APP_STORE_EXPORT:-$STORE_CACHE/export}"
DERIVED_DATA_PATH="${VIBEKITS_APP_STORE_DERIVED_DATA:-$STORE_CACHE/DerivedData}"
DART_DEFINES="$(printf '%s' 'VIBEKITS_DISTRIBUTION=mac-app-store' | base64),$(printf '%s' "VIBEKITS_APP_STORE_DISPLAY_VERSION=$STORE_VERSION" | base64)"
POD_BIN="${VIBEKITS_POD_BIN:-/Users/newlink/.gem/ruby/2.6.0/bin/pod}"

if [[ -x "$POD_BIN" ]]; then
  export PATH="$(dirname "$POD_BIN"):$PATH"
fi

cd "$PROJECT_ROOT"
[[ -d /Volumes/ORICO && -w /Volumes/ORICO ]] || { echo 'ORICO build volume unavailable' >&2; exit 2; }
export TMPDIR="$STORE_CACHE/tmp/"
export XDG_CONFIG_HOME="$STORE_CACHE/flutter-config"
mkdir -p "$TMPDIR" "$XDG_CONFIG_HOME"
[[ "$(dirname "$STORE_CACHE")" == "$(dirname "$PROJECT_ROOT")" ]] || {
  echo 'Store cache must be a sibling of the isolated worktree.' >&2
  exit 2
}
STORE_BUILD_DIR="../$(basename "$STORE_CACHE")/flutter-build"
"$FLUTTER_BIN" config --build-dir="$STORE_BUILD_DIR" >/dev/null
"$FLUTTER_BIN" pub get >/dev/null
APP="$PROJECT_ROOT/$STORE_BUILD_DIR/macos/Build/Products/Release/Vibekits.app"
# Flutter's incremental macOS build keeps files that were produced by an
# earlier distribution variant. Remove the product before the Store build so
# a direct-build `Contents/MacOS/tools` directory can never leak into the
# sandboxed archive.
rm -rf "$APP"
VIBEKITS_APP_STORE_BUILD=1 VIBEKITS_INFO_PLIST=Runner/InfoAppStore.plist \
  ASSETCATALOG_COMPILER_APPICON_NAME=AppIconStore \
  "$FLUTTER_BIN" build macos --release --no-pub \
  --target=lib/main_app_store.dart \
  --build-name="$STORE_VERSION" \
  --build-number="$STORE_BUILD_NUMBER" \
  --dart-define=VIBEKITS_DISTRIBUTION=mac-app-store \
  --dart-define="VIBEKITS_APP_STORE_DISPLAY_VERSION=$STORE_VERSION"

FLUTTER_BUILD_DIR="$(sed -n 's/^FLUTTER_BUILD_DIR=//p' macos/Flutter/ephemeral/Flutter-Generated.xcconfig | head -1)"
[[ "$FLUTTER_BUILD_DIR" == "$STORE_BUILD_DIR" ]] || {
  echo 'Flutter build directory escaped the isolated Store cache.' >&2
  exit 2
}
[[ -d "$APP/Contents" ]] || { echo 'Store Flutter app was not built' >&2; exit 2; }
if find "$APP/Contents" -path '*/tools/*' -print -quit | grep -q .; then
  echo "Store build unexpectedly contains external tool runtimes." >&2
  exit 3
fi
for excluded_asset in assets/cleaner assets/harness test_data; do
  if find "$APP/Contents" -path "*/flutter_assets/$excluded_asset*" -print -quit | grep -q .; then
    echo "Store build unexpectedly contains $excluded_asset." >&2
    exit 4
  fi
done

mkdir -p "$(dirname "$ARCHIVE_PATH")"
VIBEKITS_APP_STORE_BUILD=1 xcodebuild \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_ENTITLEMENTS=Runner/ReleaseAppStore.entitlements \
  VIBEKITS_INFO_PLIST=Runner/InfoAppStore.plist \
  ASSETCATALOG_COMPILER_APPICON_NAME=AppIconStore \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) VIBEKITS_APP_STORE' \
  ENABLE_HARDENED_RUNTIME=YES \
  FLUTTER_TARGET=lib/main_app_store.dart \
  DART_DEFINES="$DART_DEFINES" \
  archive

codesign --verify --deep --strict --verbose=2 \
  "$ARCHIVE_PATH/Products/Applications/Vibekits.app"

ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/Vibekits.app"
[[ -f "$ARCHIVED_APP/Contents/Resources/AppIconStore.icns" ]] || {
  echo 'Store archive is missing the final icon.' >&2
  exit 5
}
if find "$ARCHIVED_APP/Contents" -path '*/tools/*' -print -quit | grep -q .; then
  echo 'Store archive unexpectedly contains external tool runtimes.' >&2
  exit 5
fi
for forbidden_framework in \
  audioplayers_darwin.framework \
  webview_flutter_wkwebview.framework \
  libserialport_plus.framework \
  libsherpa-onnx-c-api.dylib \
  sqlite3.framework; do
  if find "$ARCHIVED_APP/Contents/Frameworks" -name "$forbidden_framework" -print -quit | grep -q .; then
    echo "Store archive unexpectedly contains $forbidden_framework." >&2
    exit 5
  fi
done

if {
  strings "$ARCHIVED_APP/Contents/MacOS/Vibekits"
  find "$ARCHIVED_APP/Contents/Frameworks/App.framework" -type f -perm -111 \
    -exec strings {} \;
} | grep -Eiq \
  'vibekits/harness_input|setRemoteLoginEnabled|REMOTE_LOGIN_|vibekits/simulator_host|org\.rustdesk\.rustdesk/host|应用中心|智能体（Harness）|MCP 协同|检查更新'; then
  echo "Store archive unexpectedly contains an excluded product marker." >&2
  exit 6
fi

rm -rf "$EXPORT_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist macos/ExportOptionsAppStore.plist \
  -allowProvisioningUpdates

echo "Created Mac App Store archive: $ARCHIVE_PATH"
echo "Exported Mac App Store package: $EXPORT_PATH"
echo "Mac App Store version: $STORE_VERSION ($STORE_BUILD_NUMBER)"
