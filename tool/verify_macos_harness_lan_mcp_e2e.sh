#!/bin/bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ] || [ ! -d "$1/Contents" ]; then
  echo "usage: verify_macos_harness_lan_mcp_e2e.sh <running App bundle> <instance id> [readonly|quick]" >&2
  exit 2
fi

APP_BUNDLE="$(cd "$1" && pwd)"
INSTANCE_ID="$2"
MODE="${3:-readonly}"
RUNTIME="$APP_BUNDLE/Contents/Resources/tools/harness"
NODE="$RUNTIME/bin/node"
DSH="$RUNTIME/node_modules/@deepseek-ai/dsh/lib/bin.js"
BRIDGE_FILE="$HOME/Library/Application Support/Vibekits/Mcp/tool-bridge.json"
HARNESS_HOME="$HOME/Library/Application Support/Vibekits/Harness"
DEBUG_ROOT="$(mktemp -d /private/tmp/vibekits-harness-lan-e2e.XXXXXX)"

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

DEEPSEEK_KEY="$(security find-generic-password \
  -a deepseek-api-key -s com.vibekits.database -w)"
BRIDGE_URL="$(plutil -extract endpoint raw -o - "$BRIDGE_FILE")"
BRIDGE_TOKEN="$(plutil -extract token raw -o - "$BRIDGE_FILE")"

export DEEPSEEK_API_KEY="$DEEPSEEK_KEY"
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

case "$MODE" in
  readonly)
    PROMPT="你是 VibeKits Harness，必须自己完成真实局域网 MCP 只读闭环，不得使用 curl、shell 或缓存结果。先调用 vibekits.mcp.catalog_list，找到 instanceId=${INSTANCE_ID}，读取该实例实时工具目录并确认 online=true、callable=true、catalogState=verified。分析目录后，通过 vibekits.mcp.tool_call 调用该实例公开的只读最近结果工具（优先 kemi.benchmark.last_result；若名称变化，只能选择 annotations.readOnlyHint=true 且不新建任务的等价工具），参数严格按 tools/list Schema。最终必须原样报告 instanceId、目录 revision/version、实际 toolName、traceId、taskId、reportSha256、finalScore、grade、final/outcome/evidence 和 structuredContent；任何一步失败都如实报告，不能模拟成功。真实远程工具结果返回后最后单独输出 VIBEKITS_HARNESS_LAN_E2E_OK。"
    ;;
  quick)
    if [ "${VIBEKITS_ALLOW_REMOTE_BENCHMARK:-}" != "KEMI_BENCHMARK_QUICK_ONCE" ]; then
      echo "quick mode requires explicit VIBEKITS_ALLOW_REMOTE_BENCHMARK token" >&2
      exit 6
    fi
    PROMPT="你是 VibeKits Harness，必须自己完成真实局域网 MCP 闭环，不得使用 curl、shell 或缓存结果。先调用 vibekits.mcp.catalog_list，找到 instanceId=${INSTANCE_ID}，读取该实例实时工具目录并确认 online=true、callable=true、catalogState=verified。然后通过 vibekits.mcp.tool_call 调用该实例的 kemi.benchmark.run，arguments 使用 {\"mode\":\"quick\",\"idempotencyKey\":\"vibekits-dev145-nightly-001\"}。保存 run 返回的 taskId 和 traceId，按服务端建议间隔继续通过 vibekits.mcp.tool_call 调用 kemi.benchmark.status，arguments={\"taskId\":\"实际 taskId\"}，直到 final=true。最终必须原样报告 instanceId、工具目录 revision/version、run traceId、taskId、final status traceId、reportSha256、finalScore、grade、final、outcome/evidence；任何一步失败都如实报告，不能模拟成功。完成真实 final=true 后最后单独输出 VIBEKITS_HARNESS_LAN_E2E_OK。"
    ;;
  *) echo "unsupported mode: $MODE" >&2; exit 2 ;;
esac
OUTPUT="$(cd /private/tmp && "$NODE" --expose-internals "$DSH" --profile headless "$PROMPT")"
printf '%s\n' "$OUTPUT"
if ! printf '%s\n' "$OUTPUT" | grep -Fxq 'VIBEKITS_HARNESS_LAN_E2E_OK'; then
  echo "Harness did not complete the LAN MCP final-result marker" >&2
  exit 5
fi
echo "Verified live Harness LAN MCP E2E: App PID=$BRIDGE_PID, instance=$INSTANCE_ID"
