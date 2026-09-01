#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1/Contents" ]; then
  echo "usage: sign_and_notarize_macos_release.sh <App bundle>" >&2
  exit 2
fi

APP_BUNDLE="$(cd "$1" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${VIBEKITS_DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${VIBEKITS_NOTARY_PROFILE:-}"

if [ -z "$IDENTITY" ]; then
  echo "Set VIBEKITS_DEVELOPER_ID_APPLICATION to a Developer ID Application identity." >&2
  exit 3
fi
if [ -z "$NOTARY_PROFILE" ]; then
  echo "Set VIBEKITS_NOTARY_PROFILE to a notarytool keychain profile." >&2
  exit 3
fi
VIBEKITS_DEVELOPER_ID_APPLICATION="$IDENTITY" \
  "$PROJECT_ROOT/tool/sign_macos_developer_id.sh" "$APP_BUNDLE"

ARCHIVE="${APP_BUNDLE%.app}-notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
echo "Developer ID signed, notarized and stapled: $APP_BUNDLE"
