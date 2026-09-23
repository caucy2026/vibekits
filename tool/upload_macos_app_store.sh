#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STORE_CACHE="${VIBEKITS_APP_STORE_CACHE:-/Volumes/ORICO/kemi-build-cache/vibekits-app-store-dev225}"
ARCHIVE_PATH="${VIBEKITS_APP_STORE_ARCHIVE:-$STORE_CACHE/Vibekits.xcarchive}"

cd "$PROJECT_ROOT"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$STORE_CACHE/upload" \
  -exportOptionsPlist macos/ExportOptionsAppStoreUpload.plist \
  -allowProvisioningUpdates
