#!/usr/bin/env bash
# Build the optional Android proxy APK from the pinned official Mihomo release.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
run_root="${VIBEKITS_PROXY_BUILD_ROOT:-/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/android/proxy-component-v1}"
: "${KEMI_ANDROID_KEYSTORE:?Use the documented Android release signer}"
: "${KEMI_ANDROID_STORE_PASSWORD:?Missing Android release signer}"
: "${KEMI_ANDROID_KEY_ALIAS:?Missing Android release signer}"
: "${KEMI_ANDROID_KEY_PASSWORD:?Missing Android release signer}"
[[ -d /Volumes/ORICO && -w /Volumes/ORICO/kemi-build-cache ]] || {
  echo 'External build cache unavailable' >&2; exit 1;
}
mkdir -p "$run_root/tmp" "$run_root/artifacts"
export TMPDIR="$run_root/tmp/"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$run_root/gradle}"
asset="$run_root/mihomo-android-arm64-v8-v1.19.31.gz"
binary="$run_root/mihomo-android-arm64-v8-v1.19.31"
if [[ ! -f "$asset" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 \
    'https://github.com/MetaCubeX/mihomo/releases/download/v1.19.31/mihomo-android-arm64-v8-v1.19.31.gz' \
    --output "$asset"
fi
echo 'de00bc53ed151636ca078c812a82a5315687d8d52164db230f1935b2a37904f6  '"$asset" | shasum -a 256 --check
gzip -dc "$asset" > "$binary.tmp"
echo 'dbd8af275219a097d66362d543b32f65ba0d4de9d96a49bf5e9abdcdad3af6f1  '"$binary.tmp" | shasum -a 256 --check
mv "$binary.tmp" "$binary"
export VIBEKITS_ANDROID_MIHOMO_BIN="$binary"
(cd "$repo_root/android" && ./gradlew :proxy_component:clean :proxy_component:assembleRelease --no-daemon)
source_apk="$repo_root/build/proxy_component/outputs/apk/release/proxy_component-release.apk"
unzip -p "$source_apk" classes.dex | strings | grep -q 'ProxyRuntimeService' || {
  echo 'Signed proxy component is missing its Binder service' >&2; exit 1;
}
"${ANDROID_HOME:-/Users/newlink/android-sdk}/build-tools/35.0.0/apksigner" verify --verbose "$source_apk" >/dev/null
cp "$source_apk" "$run_root/artifacts/VibeKits-network-proxy-android-arm64-v1.apk"
shasum -a 256 "$run_root/artifacts/VibeKits-network-proxy-android-arm64-v1.apk"
