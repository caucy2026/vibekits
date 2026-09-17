#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ] || [ ! -d "$1/Contents" ]; then
  echo "usage: harness_app_restart_stress_macos.sh <App bundle> [count] [output.csv]" >&2
  exit 2
fi

APP_BUNDLE="$(cd "$1" && pwd)"
COUNT="${2:-100}"
OUTPUT="${3:-/private/tmp/vibekits-harness-restart-macos.csv}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
BRIDGE_FILE="$HOME/Library/Application Support/$BUNDLE_ID/Vibekits/Mcp/tool-bridge.json"
NODE="$APP_BUNDLE/Contents/Resources/tools/harness/bin/node"
VERIFY="$PROJECT_ROOT/tool/verify_harness_local_bridge.mjs"

if ! [[ "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "count must be a positive integer" >&2
  exit 2
fi
if [ ! -x "$NODE" ] || [ ! -f "$VERIFY" ]; then
  echo "Harness runtime or bridge verifier is missing" >&2
  exit 3
fi

mkdir -p "$(dirname "$OUTPUT")"
printf 'round,started,pid,bridge_ready,capability_ok,exit_ok,children_gone,duration_ms\n' > "$OUTPUT"

cleanup_pid=""
cleanup() {
  if [ -n "$cleanup_pid" ] && kill -0 "$cleanup_pid" 2>/dev/null; then
    kill -TERM "$cleanup_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

for round in $(seq 1 "$COUNT"); do
  started_ms="$(($(date +%s) * 1000))"
  rm -f "$BRIDGE_FILE"
  open -n "$APP_BUNDLE"
  pid=""
  for _ in $(seq 1 120); do
    if [ -f "$BRIDGE_FILE" ]; then
      candidate="$(plutil -extract processId raw -o - "$BRIDGE_FILE" 2>/dev/null || true)"
      if [ -n "$candidate" ] && kill -0 "$candidate" 2>/dev/null && \
         lsof -p "$candidate" 2>/dev/null | grep -Fq "$APP_BUNDLE/Contents/MacOS/Vibekits"; then
        pid="$candidate"
        break
      fi
    fi
    sleep 0.25
  done
  if [ -z "$pid" ]; then
    printf '%s,true,,false,false,false,false,%s\n' "$round" "$(($(date +%s) * 1000 - started_ms))" >> "$OUTPUT"
    echo "Round $round failed: App did not publish its Harness bridge" >&2
    exit 10
  fi
  cleanup_pid="$pid"

  if ! "$NODE" "$VERIFY" "$BRIDGE_FILE" "$pid" >/dev/null; then
    printf '%s,true,%s,true,false,false,false,%s\n' "$round" "$pid" "$(($(date +%s) * 1000 - started_ms))" >> "$OUTPUT"
    echo "Round $round failed: Harness capability check" >&2
    exit 11
  fi

  kill -TERM "$pid"
  exit_ok=false
  for _ in $(seq 1 80); do
    if ! kill -0 "$pid" 2>/dev/null; then
      exit_ok=true
      cleanup_pid=""
      break
    fi
    sleep 0.25
  done
  # The App terminates its Harness children asynchronously after the main
  # process exits. Give that normal shutdown a bounded grace period, while
  # still failing a genuinely orphaned DSH/MCP child instead of hiding it.
  children_gone=false
  for _ in $(seq 1 40); do
    if ! ps -axo command= | awk -v root="$APP_BUNDLE/Contents" 'index($0, root) && /dsh\/lib\/bin\.js|vibekits-mcp-server\.mjs/ {found=1} END {exit found ? 0 : 1}'; then
      children_gone=true
      break
    fi
    sleep 0.25
  done
  duration_ms="$(($(date +%s) * 1000 - started_ms))"
  printf '%s,true,%s,true,true,%s,%s,%s\n' \
    "$round" "$pid" "$exit_ok" "$children_gone" "$duration_ms" >> "$OUTPUT"
  if [ "$exit_ok" != true ] || [ "$children_gone" != true ]; then
    echo "Round $round failed: exit_ok=$exit_ok children_gone=$children_gone" >&2
    exit 12
  fi
  echo "Harness restart $round/$COUNT PASS (${duration_ms}ms)"
done

trap - EXIT INT TERM
echo "Harness restart stress PASS: $COUNT/$COUNT; evidence=$OUTPUT"
