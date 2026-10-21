#!/usr/bin/env bash
set -euo pipefail
sdk=${1:?Windows LLVM SDK}
plugin=${2:?Windows plugin DLL}
consumer=${3:?Windows consumer executable}
source_dir=${4:?plugin test inputs}
output=${5:?output directory}
command -v wine >/dev/null
command -v winepath >/dev/null
command -v wineserver >/dev/null
scratch=$(mktemp -d "$output/.wine.XXXXXX")
export WINEPREFIX="$scratch/prefix"
export WINEDEBUG=${WINEDEBUG:--all}
export XDG_CACHE_HOME="$scratch/cache"
export XDG_RUNTIME_DIR="$scratch/runtime"
mkdir -p -- "$WINEPREFIX" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
cleanup() {
  wineserver -k || true
  rm -r -- "$scratch"
}
trap cleanup EXIT
export WINEDLLOVERRIDES="vcruntime140=n;vcruntime140_1=n;msvcp140=n;msvcp140_1=n;msvcp140_2=n;msvcp140_atomic_wait=n;msvcp140_codecvt_ids=n"
windows_sdk=$(winepath -w "$sdk")
export WINEPATH="$windows_sdk\\bin"
windows_plugin=$(winepath -w "$plugin")
windows_input=$(winepath -w "$source_dir/input.ll")
wine "$sdk/bin/opt.exe" -load-pass-plugin "$windows_plugin" -passes=llvmkit-count \
  -disable-output "$windows_input" 2> "$output/count.log"
grep -q 'functions=3 instructions=15' "$output/count.log"
wine "$sdk/bin/opt.exe" -load-pass-plugin "$windows_plugin" \
  '-passes=module(llvmkit-count),function(llvmkit-inline),verify' \
  -S "$windows_input" -o "$(winepath -w "$output/pipeline.ll")"
grep -q alwaysinline "$output/pipeline.ll"
if grep -q '\bnoinline\b' "$output/pipeline.ll"; then
  echo 'Function pass did not remove noinline' >&2
  exit 1
fi
wine "$sdk/bin/clang.exe" -O1 "-fpass-plugin=$windows_plugin" \
  -S -emit-llvm "$(winepath -w "$source_dir/input.c")" \
  -o "$(winepath -w "$output/clang.ll")"
grep -q '"llvmkit.plugin"="loaded"' "$output/clang.ll"
mkdir -p "$scratch/app"
cp "$consumer" "$scratch/app/llvm_consumer.exe"
cp "$sdk/bin/"*.dll "$scratch/app/"
wine "$scratch/app/llvm_consumer.exe" 2> "$output/consumer.log"
echo 'Runtime checks passed under Wine: opt module/function passes, verified pipeline, Clang extension, DLL consumer.'
