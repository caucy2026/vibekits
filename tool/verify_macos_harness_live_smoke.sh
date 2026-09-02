#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1/Contents" ]; then
  echo "usage: verify_macos_harness_live_smoke.sh <running App bundle>" >&2
  exit 2
fi

APP_BUNDLE="$(cd "$1" && pwd)"
RUNTIME="$APP_BUNDLE/Contents/Resources/tools/harness"
NODE="$RUNTIME/bin/node"
DSH="$RUNTIME/node_modules/@deepseek-ai/dsh/lib/bin.js"
BRIDGE_FILE="$HOME/Library/Application Support/Vibekits/Mcp/tool-bridge.json"
HARNESS_HOME="$HOME/Library/Application Support/Vibekits/Harness"
DEBUG_ROOT="$(mktemp -d /private/tmp/vibekits-harness-live-smoke.XXXXXX)"

if [ ! -f "$BRIDGE_FILE" ]; then
  echo "The signed candidate is not publishing its live Harness bridge" >&2
  exit 3
fi
BRIDGE_PID="$(plutil -extract processId raw -o - "$BRIDGE_FILE")"
if ! lsof -p "$BRIDGE_PID" 2>/dev/null | grep -Fq \
  "$APP_BUNDLE/Contents/MacOS/Vibekits"; then
  echo "Harness bridge PID $BRIDGE_PID does not belong to $APP_BUNDLE" >&2
  exit 4
fi

# New installs keep the credential in the official DSH store. Retain the
# legacy Keychain lookup only as an optional migration fallback; requiring it
# made a correctly migrated production App fail the release smoke gate.
DEEPSEEK_KEY="$(security find-generic-password \
  -a deepseek-api-key -s com.vibekits.database -w 2>/dev/null || true)"
BRIDGE_URL="$(plutil -extract endpoint raw -o - "$BRIDGE_FILE")"
BRIDGE_TOKEN="$(plutil -extract token raw -o - "$BRIDGE_FILE")"

if [ -n "$DEEPSEEK_KEY" ]; then
  export DEEPSEEK_API_KEY="$DEEPSEEK_KEY"
fi
export DEEPSEEK_BASE_URL="https://api.deepseek.com"
export DEEPSEEK_MODEL="deepseek-v4-flash"
export DSH_HOME="$HARNESS_HOME"
export DSH_TELEMETRY_MODE="DISABLED"
export DSH_TELEMETRY_DISABLED="1"
export DSH_PERMISSION_MODE="workspace-write"
export DSH_LOG_DIR="$DEBUG_ROOT/logs"
export VIBEKITS_DEBUG_DIR="$DEBUG_ROOT"
export VIBEKITS_SCREENSHOT_DIR="$DEBUG_ROOT/screenshots"
export TEMP="$DEBUG_ROOT/temp"
export TMP="$DEBUG_ROOT/temp"
export TMPDIR="$DEBUG_ROOT/temp"
export VIBEKITS_NODE_EXECUTABLE="$NODE"
export VIBEKITS_MCP_SERVER="$RUNTIME/vibekits-mcp-server.mjs"
export VIBEKITS_ANDROID_STRESS_MCP_SERVER="$RUNTIME/vibekits-android-stress-mcp.mjs"
export VIBEKITS_STRESS_REPORT_DIR="$DEBUG_ROOT/stress"
export VIBEKITS_TOOL_BRIDGE_URL="$BRIDGE_URL"
export VIBEKITS_TOOL_BRIDGE_TOKEN="$BRIDGE_TOKEN"
mkdir -p "$DSH_LOG_DIR" "$VIBEKITS_SCREENSHOT_DIR" "$TEMP" \
  "$VIBEKITS_STRESS_REPORT_DIR"

PROMPT='只调用只读工具 vibekits.system.capability_check，确认 VibeKits 本机工具桥可用，不读取或发送局域网 MCP 目录，不调用任何其他工具。最后单独输出 VIBEKITS_HARNESS_LIVE_SMOKE_OK。'
OUTPUT="$(cd /private/tmp && "$NODE" --expose-internals "$DSH" --profile headless "$PROMPT")"
printf '%s\n' "$OUTPUT"
case "$OUTPUT" in
  *"VIBEKITS_HARNESS_LIVE_SMOKE_OK"*) ;;
  *) echo "Harness did not complete the live MCP smoke marker" >&2; exit 5 ;;
esac
echo "Verified live Harness MCP call: App PID=$BRIDGE_PID"
