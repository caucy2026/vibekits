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

BRIDGE_FILE="$HOME/Library/Application Support/Vibekits/Mcp/tool-bridge.json"
SMOKE_PID=""
cleanup_smoke() {
  if [ -n "$SMOKE_PID" ] && kill -0 "$SMOKE_PID" 2>/dev/null; then
    kill -TERM "$SMOKE_PID" 2>/dev/null || true
  fi
}
trap cleanup_smoke EXIT INT TERM

if [ -f "$BRIDGE_FILE" ]; then
  EXISTING_PID="$(plutil -extract processId raw -o - "$BRIDGE_FILE" 2>/dev/null || true)"
  if [ -n "$EXISTING_PID" ] && lsof -p "$EXISTING_PID" 2>/dev/null | \
    grep -Fq '/Vibekits.app/Contents/MacOS/Vibekits'; then
    echo "Quit the currently running Vibekits App before notarization." >&2
    exit 5
  fi
fi

open -n "$APP_BUNDLE"
for _ in $(seq 1 30); do
  if [ -f "$BRIDGE_FILE" ]; then
    CANDIDATE_PID="$(plutil -extract processId raw -o - "$BRIDGE_FILE" 2>/dev/null || true)"
    if [ -n "$CANDIDATE_PID" ] && lsof -p "$CANDIDATE_PID" 2>/dev/null | \
      grep -Fq "$APP_BUNDLE/Contents/MacOS/Vibekits"; then
      SMOKE_PID="$CANDIDATE_PID"
      break
    fi
  fi
  sleep 1
done
if [ -z "$SMOKE_PID" ]; then
  echo "Signed candidate did not publish its Harness bridge within 30 seconds." >&2
  exit 6
fi
"$PROJECT_ROOT/tool/verify_macos_harness_live_smoke.sh" "$APP_BUNDLE"
kill -TERM "$SMOKE_PID"
SMOKE_PID=""

ARCHIVE="${APP_BUNDLE%.app}-notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
"$PROJECT_ROOT/tool/verify_macos_harness_signed_runtime.sh" "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
trap - EXIT INT TERM
echo "Developer ID signed, notarized and stapled: $APP_BUNDLE"
