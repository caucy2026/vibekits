#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# DSH requires Node >=22.19. Node 22.19 is the lowest compatible official
# runtime and its Intel binary targets macOS 11.0, which is valid inside the
# full-function macOS 12+ application. The release verifier rejects any bundled
# Mach-O that requires a system newer than macOS 12.
NODE_VERSION="${NODE_VERSION:-22.19.0}"
DSH_VERSION="${DSH_VERSION:-0.1.1-rc.2}"
TARGET="${1:-$PROJECT_ROOT/native/harness/macos/runtime}"
DOWNLOADS="$PROJECT_ROOT/.tmp/harness-runtime-macos-downloads"
STAGING="$PROJECT_ROOT/.tmp/harness-runtime-macos-staging"
NPM_CACHE="$PROJECT_ROOT/.tmp/npm-cache-harness-macos"
NODE_DIST="$STAGING/node-universal"
PACKAGE_ROOT="$STAGING/package"

case "$NODE_VERSION" in
  *[!0-9.]*|'') echo "Invalid Node version: $NODE_VERSION" >&2; exit 2 ;;
esac
case "$DSH_VERSION" in
  *[!0-9A-Za-z.-]*|'') echo "Invalid DSH version: $DSH_VERSION" >&2; exit 2 ;;
esac

mkdir -p "$DOWNLOADS" "$NPM_CACHE"
rm -rf "$STAGING"
mkdir -p "$NODE_DIST" "$PACKAGE_ROOT"

BASE_URL="https://nodejs.org/dist/v$NODE_VERSION"
SHASUMS="$DOWNLOADS/SHASUMS256-v$NODE_VERSION.txt"
curl --fail --location --silent --show-error "$BASE_URL/SHASUMS256.txt" --output "$SHASUMS"

for ARCH in arm64 x64; do
  ARCHIVE="node-v$NODE_VERSION-darwin-$ARCH.tar.gz"
  ARCHIVE_PATH="$DOWNLOADS/$ARCHIVE"
  EXPECTED="$(awk -v file="$ARCHIVE" '$2 == file { print $1 }' "$SHASUMS")"
  if [ -z "$EXPECTED" ]; then
    echo "Official checksum is missing for $ARCHIVE" >&2
    exit 3
  fi
  CACHED=''
  if [ -f "$ARCHIVE_PATH" ]; then
    CACHED="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{ print $1 }')"
  fi
  if [ "$CACHED" != "$EXPECTED" ]; then
    TEMP_ARCHIVE="$ARCHIVE_PATH.download"
    rm -f "$TEMP_ARCHIVE"
    curl --fail --location --silent --show-error \
      "$BASE_URL/$ARCHIVE" --output "$TEMP_ARCHIVE"
    mv "$TEMP_ARCHIVE" "$ARCHIVE_PATH"
  fi
  ACTUAL="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{ print $1 }')"
  if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "Node checksum mismatch for $ARCHIVE" >&2
    exit 3
  fi
  mkdir -p "$STAGING/node-$ARCH"
  tar -xzf "$ARCHIVE_PATH" -C "$STAGING/node-$ARCH" --strip-components=1
done

# npm and headers are architecture-neutral. Start with the arm64 distribution,
# then replace its executable with one signed universal Mach-O.
ditto "$STAGING/node-arm64" "$NODE_DIST"
lipo -create \
  "$STAGING/node-arm64/bin/node" \
  "$STAGING/node-x64/bin/node" \
  -output "$NODE_DIST/bin/node"
chmod 755 "$NODE_DIST/bin/node"
codesign --force --sign - "$NODE_DIST/bin/node"
if ! file "$NODE_DIST/bin/node" | grep -q 'universal binary'; then
  echo "Universal Node assembly failed" >&2
  exit 4
fi

cat > "$PACKAGE_ROOT/package.json" <<EOF
{"name":"vibekits-harness-runtime","private":true,"version":"1.0.0"}
EOF

NPM="$NODE_DIST/bin/npm"
NODE="$NODE_DIST/bin/node"
(
  export PATH="$NODE_DIST/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  cd "$PACKAGE_ROOT"
  "$NPM" install --omit=dev --ignore-scripts --legacy-peer-deps \
    --no-audit --no-fund "@deepseek-ai/dsh@$DSH_VERSION" \
    --registry=https://registry.npmjs.org --cache="$NPM_CACHE" \
    --fetch-timeout=30000 --fetch-retries=1 --loglevel=warn

  PASS=0
  while [ "$PASS" -lt 6 ]; do
    PEER_JSON="$("$NODE" "$PROJECT_ROOT/tool/list_harness_required_peers.mjs" "$PACKAGE_ROOT/node_modules")"
    if [ "$PEER_JSON" = "[]" ]; then
      break
    fi
    PEER_FILE="$STAGING/required-peers.bin"
    "$NODE" "$PROJECT_ROOT/tool/list_harness_required_peers.mjs" \
      "$PACKAGE_ROOT/node_modules" --null > "$PEER_FILE"
    xargs -0 "$NPM" install --omit=dev --ignore-scripts --legacy-peer-deps \
      --no-audit --no-fund \
      --registry=https://registry.npmjs.org --cache="$NPM_CACHE" \
      --fetch-timeout=30000 --fetch-retries=1 --loglevel=warn \
      < "$PEER_FILE"
    PASS=$((PASS + 1))
  done
  FINAL_PEERS="$("$NODE" "$PROJECT_ROOT/tool/list_harness_required_peers.mjs" "$PACKAGE_ROOT/node_modules")"
  if [ "$FINAL_PEERS" != "[]" ]; then
    echo "Harness required peer installation did not converge: $FINAL_PEERS" >&2
    exit 5
  fi

  install_native_package() {
    SPEC="$1"
    RELATIVE_TARGET="$2"
    PACK_JSON="$("$NPM" pack "$SPEC" --pack-destination "$STAGING" --json \
      --registry=https://registry.npmjs.org --cache="$NPM_CACHE" \
      --fetch-timeout=30000 --fetch-retries=1)"
    TARBALL="$("$NODE" -e '
      const value = JSON.parse(process.argv[1]);
      if (!Array.isArray(value) || !value[0]?.filename) process.exit(2);
      process.stdout.write(value[0].filename);
    ' "$PACK_JSON")"
    DESTINATION="$PACKAGE_ROOT/node_modules/$RELATIVE_TARGET"
    rm -rf "$DESTINATION"
    mkdir -p "$DESTINATION"
    tar -xzf "$STAGING/$TARBALL" -C "$DESTINATION" --strip-components=1
  }

  # npm selects optional native packages for the build host. GitHub macos-14
  # currently runs on Intel, while local release machines may be Apple Silicon.
  # Materialize both architectures explicitly so a clean checkout produces the
  # same Universal payload on either host instead of depending on npm's host
  # architecture selection.
  install_native_package '@img/sharp-darwin-arm64@0.35.4' '@img/sharp-darwin-arm64'
  install_native_package '@img/sharp-libvips-darwin-arm64@1.3.3' '@img/sharp-libvips-darwin-arm64'
  install_native_package '@koromix/koffi-darwin-arm64@3.1.6' '@koromix/koffi-darwin-arm64'
  install_native_package '@vscode/ripgrep-darwin-arm64@1.18.0' '@vscode/ripgrep-darwin-arm64'
  install_native_package '@img/sharp-darwin-x64@0.35.4' '@img/sharp-darwin-x64'
  install_native_package '@img/sharp-libvips-darwin-x64@1.3.3' '@img/sharp-libvips-darwin-x64'
  install_native_package '@koromix/koffi-darwin-x64@3.1.6' '@koromix/koffi-darwin-x64'
  install_native_package '@vscode/ripgrep-darwin-x64@1.18.0' '@vscode/ripgrep-darwin-x64'

  # node-pty ships every platform in one package. A macOS runtime needs only
  # its two Darwin slices; keeping PE/ELF addons complicates signing audits.
  rm -rf \
    "$PACKAGE_ROOT/node_modules/node-pty/prebuilds/linux-arm64" \
    "$PACKAGE_ROOT/node_modules/node-pty/prebuilds/linux-x64" \
    "$PACKAGE_ROOT/node_modules/node-pty/prebuilds/win32-arm64" \
    "$PACKAGE_ROOT/node_modules/node-pty/prebuilds/win32-x64"
)

PACKAGE_JSON="$PACKAGE_ROOT/node_modules/@deepseek-ai/dsh/package.json"
CLI_RELATIVE="$("$NODE" -e '
  const pkg = require(process.argv[1]);
  const bin = typeof pkg.bin === "string" ? pkg.bin : pkg.bin?.dsh;
  if (!bin) process.exit(2);
  process.stdout.write(`node_modules/@deepseek-ai/dsh/${bin.replaceAll("\\\\", "/")}`);
' "$PACKAGE_JSON")"

rm -rf "$TARGET"
mkdir -p "$TARGET/bin" "$TARGET/profile"
cp "$NODE_DIST/bin/node" "$TARGET/bin/node"
ditto "$PACKAGE_ROOT/node_modules" "$TARGET/node_modules"
# Published node-addon-require-builtin 0.1.5 Darwin binaries require macOS 15.
# The pinned official DSH loader supports Node's explicit --expose-internals
# path, which every macOS VibeKits launch uses. Remove the incompatible optional
# fallback packages instead of shipping a hidden macOS 15 dependency.
rm -rf \
  "$TARGET/node_modules/node-addon-require-builtin-darwin-arm64" \
  "$TARGET/node_modules/node-addon-require-builtin-darwin-x64"
for FILE in \
  vibekits-mcp-server.mjs \
  vibekits-codex-mcp.mjs \
  vibekits-approval.mjs \
  vibekits-parent-watchdog.mjs \
  vibekits-android-stress-mcp.mjs; do
  cp "$PROJECT_ROOT/native/harness/$FILE" "$TARGET/$FILE"
done

"$TARGET/bin/node" "$PROJECT_ROOT/tool/patch_harness_runtime.mjs" "$TARGET"

cat > "$TARGET/harness-runtime.json" <<EOF
{
  "version": "@deepseek-ai/dsh@$DSH_VERSION",
  "nodeVersion": "v$NODE_VERSION",
  "architectures": ["arm64", "x86_64"],
  "nodeArguments": ["--expose-internals"],
  "cli": "$CLI_RELATIVE"
}
EOF

"$TARGET/bin/node" --version
test -f "$TARGET/$CLI_RELATIVE"
test -f "$TARGET/vibekits-mcp-server.mjs"
test -f "$TARGET/vibekits-approval.mjs"
test -f "$TARGET/vibekits-parent-watchdog.mjs"
test -f "$TARGET/vibekits-android-stress-mcp.mjs"
test -f "$TARGET/node_modules/@img/sharp-darwin-arm64/lib/sharp-darwin-arm64-0.35.4.node"
test -f "$TARGET/node_modules/@img/sharp-darwin-x64/lib/sharp-darwin-x64-0.35.4.node"
test -f "$TARGET/node_modules/@koromix/koffi-darwin-arm64/darwin_arm64/koffi.node"
test -f "$TARGET/node_modules/@koromix/koffi-darwin-x64/darwin_x64/koffi.node"
test ! -d "$TARGET/node_modules/node-addon-require-builtin-darwin-arm64"
test ! -d "$TARGET/node_modules/node-addon-require-builtin-darwin-x64"
test -x "$TARGET/node_modules/@vscode/ripgrep-darwin-arm64/bin/rg"
test -x "$TARGET/node_modules/@vscode/ripgrep-darwin-x64/bin/rg"
echo "Prepared macOS Harness runtime: $TARGET"
