#!/usr/bin/env bash
set -euo pipefail

: "${LLVM_SDK:?Set LLVM_SDK to the extracted Windows SDK prefix}"
: "${MSVC_WINE_ROOT:?Set MSVC_WINE_ROOT to the installed msvc-wine toolchain}"
: "${WINEPREFIX:?Set WINEPREFIX to a private Wine prefix}"
mkdir -p -- "$WINEPREFIX"
export XDG_CACHE_HOME="$WINEPREFIX/cache"
export XDG_RUNTIME_DIR="$WINEPREFIX/runtime"
mkdir -p -- "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
repo=${1:?repository root}
output=${2:?output directory}
mkdir -p "$output"
output=$(cd "$output" && pwd -P)
sdk=$(cd "$LLVM_SDK" && pwd -P)
major=$(tr -d '\r\n' < "$sdk/share/llvmkit/llvm-major")
runner="$MSVC_WINE_ROOT/bin/x64/wine-msvc.sh"
set +u
source "$MSVC_WINE_ROOT/bin/x64/msvcenv.sh"
set -u
export WINEPATH="Z:${sdk//\//\\}\\bin;$WINEPATH"
export WINEDLLOVERRIDES="$WINEDLLOVERRIDES;msvcp140=n;msvcp140_1=n;msvcp140_2=n;msvcp140_atomic_wait=n;msvcp140_codecvt_ids=n"

cmake -S "$repo/tests/plugins" -B "$output/plugin" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$repo/consumer/toolchain-wine.cmake"
cmake --build "$output/plugin" --parallel 2
plugin="$output/plugin/LLVMKitPasses.dll"
"$runner" "$sdk/bin/llvm-readobj.exe" --coff-imports "$plugin" > "$output/imports.txt"
grep -q "LLVM-$major.dll" "$output/imports.txt"
"$runner" "$sdk/bin/llvm-readobj.exe" --coff-exports "$plugin" > "$output/exports.txt"
grep -q llvmGetPassPluginInfo "$output/exports.txt"
"$runner" "$sdk/bin/opt.exe" -load-pass-plugin "$plugin" -passes=llvmkit-count \
  -disable-output "$repo/tests/plugins/input.ll" 2> "$output/count.log"
grep -q 'functions=3 instructions=15' "$output/count.log"
"$runner" "$sdk/bin/opt.exe" -load-pass-plugin "$plugin" \
  '-passes=module(llvmkit-count),function(llvmkit-inline),verify' \
  -S "$repo/tests/plugins/input.ll" -o "$output/pipeline.ll"
grep -q alwaysinline "$output/pipeline.ll"
if grep -q '\bnoinline\b' "$output/pipeline.ll"; then
  echo 'Function pass did not remove noinline' >&2
  exit 1
fi
"$runner" "$sdk/bin/clang.exe" -O1 "-fpass-plugin=Z:${plugin//\//\\}" \
  -S -emit-llvm "$repo/tests/plugins/input.c" -o "$output/clang.ll"
grep -q '"llvmkit.plugin"="loaded"' "$output/clang.ll"

cmake -S "$repo/tests/consumer" -B "$output/consumer" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DLLVMKIT_WITH_LAB=OFF \
  -DCMAKE_TOOLCHAIN_FILE="$repo/consumer/toolchain-wine.cmake"
cmake --build "$output/consumer" --parallel 2
# App-local DLLs also avoid Wine's builtin CRT precedence for external executables.
runtime=$(mktemp -d "$output/runtime.XXXXXX")
trap 'rm -r -- "$runtime"' EXIT
cp "$output/consumer/llvm_consumer.exe" "$sdk/bin/"*.dll "$runtime/"
"$runner" "$runtime/llvm_consumer.exe" 2> "$output/consumer.log"
echo 'Windows SDK verified under Wine: Windows Clang, DLL consumer, plugin imports/exports, opt passes, Clang extension.'
