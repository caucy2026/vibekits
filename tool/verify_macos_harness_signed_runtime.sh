#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1/Contents" ]; then
  echo "usage: verify_macos_harness_signed_runtime.sh <App bundle>" >&2
  exit 2
fi

APP_BUNDLE="$(cd "$1" && pwd)"
RUNTIME="$APP_BUNDLE/Contents/Resources/tools/harness"
NODE="$RUNTIME/bin/node"
DSH="$RUNTIME/node_modules/@deepseek-ai/dsh/lib/bin.js"

if [ ! -x "$NODE" ] || [ ! -f "$DSH" ]; then
  echo "Harness runtime is incomplete: $RUNTIME" >&2
  exit 3
fi

NODE_SIGNATURE="$(codesign --display --verbose=4 "$NODE" 2>&1)"
case "$NODE_SIGNATURE" in
  *"flags=0x10000(runtime)"*) ;;
  *) echo "Harness Node is missing Hardened Runtime signing" >&2; exit 4 ;;
esac

NODE_ENTITLEMENTS="$(codesign --display --entitlements - "$NODE" 2>&1)"
case "$NODE_ENTITLEMENTS" in
  *"com.apple.security.cs.allow-jit"*) ;;
  *) echo "Harness Node is missing com.apple.security.cs.allow-jit" >&2; exit 5 ;;
esac

NODE_VERSION="$($NODE --version)"
case "$NODE_VERSION" in
  v22.*|v24.*) ;;
  *) echo "Unexpected Harness Node version: $NODE_VERSION" >&2; exit 6 ;;
esac

"$NODE" "$DSH" --help >/dev/null
echo "Verified signed Harness runtime: Node=$NODE_VERSION, JIT=allowed, DSH=launchable"
