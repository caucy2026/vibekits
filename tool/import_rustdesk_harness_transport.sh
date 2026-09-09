#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <rustdesk-checkout> <librustdesk.so> <libc++_shared.so>" >&2
  exit 64
fi

source_root=$1
rust_library=$2
cpp_library=$3
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
destination="$project_root/android/app/src/main/jniLibs/arm64-v8a"

test -d "$source_root/.git"
test -f "$source_root/LICENCE"
test -f "$rust_library"
test -f "$cpp_library"

for symbol in \
  Java_ffi_FFI_init \
  Java_ffi_FFI_startHarnessServer \
  Java_ffi_FFI_harnessStatus \
  Java_ffi_FFI_harnessConnections \
  Java_ffi_FFI_harnessAuthorize \
  Java_ffi_FFI_harnessReject \
  Java_ffi_FFI_harnessOpenTunnel \
  Java_ffi_FFI_harnessCloseTunnel
do
  # Android release libraries are stripped, so the ordinary symbol table may
  # be absent. JNI export names remain in the dynamic string table.
  strings "$rust_library" | grep -F "$symbol" >/dev/null
done

mkdir -p "$destination"
if ! cmp -s "$rust_library" "$destination/librustdesk.so"; then
  cp "$rust_library" "$destination/librustdesk.so"
fi
if ! cmp -s "$cpp_library" "$destination/libc++_shared.so"; then
  cp "$cpp_library" "$destination/libc++_shared.so"
fi
cp "$source_root/LICENCE" "$project_root/third_party/rustdesk-transport/LICENCE"

git -C "$source_root" rev-parse HEAD
shasum -a 256 "$destination/librustdesk.so" "$destination/libc++_shared.so"
