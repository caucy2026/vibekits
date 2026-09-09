#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: prepare_rustdesk_harness_relay_macos.sh <vibekits-harness-relay>" >&2
  exit 64
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$1"
DESTINATION="$PROJECT_ROOT/native/rustdesk/macos/runtime/vibekits-harness-relay"

if [ ! -x "$SOURCE" ]; then
  echo "Harness relay is missing or not executable: $SOURCE" >&2
  exit 2
fi
case "$(file -b "$SOURCE")" in
  Mach-O*) ;;
  *)
    echo "Harness relay is not a macOS Mach-O executable." >&2
    exit 2
    ;;
esac
for MARKER in transport_connected transport_connect_timeout; do
  if ! strings "$SOURCE" | grep -F "$MARKER" >/dev/null; then
    echo "Harness relay is stale; missing marker: $MARKER" >&2
    exit 2
  fi
done

mkdir -p "$(dirname "$DESTINATION")"
ditto "$SOURCE" "$DESTINATION"
chmod 755 "$DESTINATION"
shasum -a 256 "$DESTINATION"
file "$DESTINATION"
