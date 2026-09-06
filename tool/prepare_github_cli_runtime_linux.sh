#!/bin/sh
set -eu

VERSION='2.100.0'
PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MACHINE="$(uname -m)"
case "$MACHINE" in
  x86_64|amd64) ARCH='amd64'; SHA='e4d4bb4498e8d007abe545b6568926793ace1b6447da598294a610018cb164be' ;;
  aarch64|arm64) ARCH='arm64'; SHA='ea4e7a581a32ccad6cc7923cb1576ac5859ba4b9a16ab22eb8f8a96e78e2e961' ;;
  *) echo "Unsupported Linux architecture: $MACHINE" >&2; exit 2 ;;
esac
ARCHIVE="gh_${VERSION}_linux_${ARCH}.tar.gz"
URL="https://github.com/cli/cli/releases/download/v${VERSION}/${ARCHIVE}"
TEMP_ROOT="$PROJECT_ROOT/.tmp/github-cli-linux"
TARGET="$PROJECT_ROOT/native/github_cli/linux/runtime"
rm -rf "$TEMP_ROOT"
mkdir -p "$TEMP_ROOT"
trap 'rm -rf "$TEMP_ROOT"' EXIT
curl --fail --location --retry 3 "$URL" --output "$TEMP_ROOT/$ARCHIVE"
ACTUAL="$(sha256sum "$TEMP_ROOT/$ARCHIVE" | awk '{print $1}')"
[ "$ACTUAL" = "$SHA" ] || { echo "SHA-256 mismatch for $ARCHIVE" >&2; exit 3; }
tar -xzf "$TEMP_ROOT/$ARCHIVE" -C "$TEMP_ROOT"
rm -rf "$TARGET"
mkdir -p "$(dirname "$TARGET")"
mv "$TEMP_ROOT/gh_${VERSION}_linux_${ARCH}" "$TARGET"
printf '%s\n' "{\"distribution\":\"GitHub CLI\",\"version\":\"$VERSION\",\"platform\":\"linux\",\"architecture\":\"$ARCH\",\"sha256\":\"$SHA\",\"source\":\"$URL\",\"license\":\"MIT\"}" > "$TARGET/vibekits-github-cli-runtime.json"
"$TARGET/bin/gh" --version | head -n 1
echo "Prepared Linux GitHub CLI runtime: $TARGET"
