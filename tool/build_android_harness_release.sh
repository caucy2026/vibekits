#!/usr/bin/env bash
# Rebuild the Android Harness JNI core before producing a signed APK.
# Signing inputs come from the approved local signing document, never this file.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${KEMI_ANDROID_KEYSTORE:?Set the documented signing keystore}"
: "${KEMI_ANDROID_STORE_PASSWORD:?Set signing password in the process environment}"
: "${KEMI_ANDROID_KEY_ALIAS:?Set signing alias}"
: "${KEMI_ANDROID_KEY_PASSWORD:?Set signing key password}"
: "${JAVA_HOME:?Set JDK 17}"
: "${GRADLE_USER_HOME:?Set the external Gradle cache}"
: "${VCPKG_ROOT:?Set the existing Android vcpkg tree}"
: "${VCPKG_INSTALLED_ROOT:?Set the Android ABI dependency tree}"
run_root="${VIBEKITS_ANDROID_BUILD_ROOT:-/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/android-harness-inbound}"
rust_root="${VIBEKITS_RUSTDESK_SOURCE:-/Users/newlink/kemi/RustDesk/client}"
flutter_bin="${VIBEKITS_FLUTTER_BIN:-/Volumes/ORICO/kemi-build-cache/shared/flutter-sdk/bin/flutter}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/Users/newlink/android-sdk/ndk/28.2.13676358}"
[[ -d /Volumes/ORICO && -w /Volumes/ORICO/kemi-build-cache ]] || { echo 'External build cache unavailable' >&2; exit 1; }
[[ -f "$KEMI_ANDROID_KEYSTORE" && -x "$flutter_bin" ]] || { echo 'Missing signing file or Flutter' >&2; exit 1; }
mkdir -p "$run_root/tmp"
export TMPDIR="$run_root/tmp"
export CARGO_TARGET_DIR="$run_root/rust-target"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"
(cd "$rust_root" && bash flutter/ndk_arm64.sh)
core="$CARGO_TARGET_DIR/aarch64-linux-android/release/liblibrustdesk.so"
nm_tool="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-nm"
# Check both JNI exports before replacing the packaged core.
exports="$($nm_tool --dynamic --defined-only "$core")"
for symbol in Java_ffi_FFI_harnessSetSimulatorAccess Java_ffi_FFI_harnessConnections; do
  [[ "$exports" == *" $symbol"* ]] || { echo "Missing JNI export: $symbol" >&2; exit 1; }
done
cp "$core" "$repo_root/android/app/src/main/jniLibs/arm64-v8a/librustdesk.so"
cd "$repo_root"
# Keep the complete icon font: font-subset stalled on an otherwise idle clean
# PAD release build, while the same source completed with this option.
"$flutter_bin" build apk --release --target-platform android-arm64 --no-tree-shake-icons --no-pub
(cd "$repo_root/android" && ./gradlew :model_component:assembleRelease --no-daemon)
python3 - "$repo_root/build/app/outputs/flutter-apk/app-release.apk" \
  "$repo_root/build/model_component/outputs/apk/release/model_component-release.apk" \
  "$core" "$repo_root/build/app/intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib/arm64-v8a/librustdesk.so" \
  "$repo_root/build/app/intermediates/stripped_native_libs/release/stripReleaseDebugSymbols/out/lib/arm64-v8a/librustdesk.so" <<'PY'
import hashlib, pathlib, sys, zipfile
core, component, rust_core, merged_core, stripped_core = sys.argv[1:]
def digest(data):
    return hashlib.sha256(data).hexdigest()
assert digest(pathlib.Path(rust_core).read_bytes()) == digest(pathlib.Path(merged_core).read_bytes()), 'New Rust core was not merged into Android build'
with zipfile.ZipFile(core) as z:
    names = set(z.namelist())
    assert not any('/test_data/models/' in name for name in names), 'Optional models leaked into core APK'
    assert 'lib/arm64-v8a/librustdesk.so' in names, 'Core Harness relay missing'
    assert digest(z.read('lib/arm64-v8a/librustdesk.so')) == digest(pathlib.Path(stripped_core).read_bytes()), 'Packaged Rust core differs from Gradle stripped output'
    assert not any(name.startswith('lib/x86_64/') or name.startswith('lib/armeabi-v7a/') for name in names), 'Unused ABI leaked into PAD APK'
with zipfile.ZipFile(component) as z:
    names = set(z.namelist())
    for name in ('assets/ppocrv6_tiny/det.onnx', 'assets/ppocrv6_tiny/rec.onnx', 'assets/ppocrv6_tiny/rec.yml', 'assets/silero_vad_v6.onnx'):
        assert name in names, f'Model component missing {name}'
print('Android core/component split verified')
PY
