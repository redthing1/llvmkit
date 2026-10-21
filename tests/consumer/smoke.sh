#!/usr/bin/env bash
set -euo pipefail

kind=${1:?expected llvm or lab}
sdk=/sdk

"$sdk/bin/clang" --version
"$sdk/bin/llvm-config" --version
printf 'define i32 @answer() { ret i32 42 }\n' \
  | "$sdk/bin/llvm-as" -o /tmp/llvmkit-answer.bc -
"$sdk/bin/opt" -passes=verify -disable-output /tmp/llvmkit-answer.bc

cmake -S /tests/consumer -B /tmp/llvmkit-consumer -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$sdk/share/cmake/toolchain.cmake" \
  -DLLVMKIT_WITH_LAB="$([[ "$kind" == lab ]] && echo ON || echo OFF)"
cmake --build /tmp/llvmkit-consumer --parallel 2
/tmp/llvmkit-consumer/llvm_consumer

cmake -S /tests/plugins -B /tmp/llvmkit-plugins -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$sdk/share/cmake/toolchain.cmake"
cmake --build /tmp/llvmkit-plugins --parallel 2
plugin=/tmp/llvmkit-plugins/LLVMKitPasses.so
"$sdk/bin/opt" -load-pass-plugin "$plugin" -passes=llvmkit-count \
  -disable-output /tests/plugins/input.ll 2>/tmp/llvmkit-count.log
grep -q 'functions=3 instructions=15' /tmp/llvmkit-count.log
"$sdk/bin/opt" -load-pass-plugin "$plugin" -passes=llvmkit-inline \
  -S /tests/plugins/input.ll -o /tmp/llvmkit-inline.ll
"$sdk/bin/opt" -load-pass-plugin "$plugin" \
  -passes='module(llvmkit-count),function(llvmkit-inline),verify' \
  -S /tests/plugins/input.ll -o /tmp/llvmkit-pipeline.ll
for output in /tmp/llvmkit-inline.ll /tmp/llvmkit-pipeline.ll; do
  grep -q alwaysinline "$output"
  if grep -q '\bnoinline\b' "$output"; then
    echo "Plugin did not remove noinline: $output" >&2
    exit 1
  fi
done
"$sdk/bin/clang" -O1 "-fpass-plugin=$plugin" -S -emit-llvm \
  /tests/plugins/input.c -o /tmp/llvmkit-clang.ll
grep -q '"llvmkit.plugin"="loaded"' /tmp/llvmkit-clang.ll

if [[ "$kind" == lab ]]; then
  llvm_major=$(cat "$sdk/share/llvmkit/llvm-major")
  REMILL_PC_METADATA=1 "$sdk/bin/remill-lift-${llvm_major}" --arch amd64 \
    --ir_pre_out /tmp/llvmkit-lift-pre.ll --ir_out /tmp/llvmkit-lift.ll \
    --bytes c704ba01000000
  grep -Eq '!remill\.pc ![0-9]+' /tmp/llvmkit-lift-pre.ll
  test -s /tmp/llvmkit-lift.ll
  "$sdk/bin/remill-lift-${llvm_major}" --arch aarch64 \
    --address 0x400544 --ir_out /tmp/llvmkit-aarch64.ll \
    --bytes FD7BBFA90000009000601891FD030091B7FFFF97E0031F2AFD7BC1A8C0035FD6
  test -s /tmp/llvmkit-aarch64.ll
  "$sdk/bin/remill-lift-${llvm_major}" --arch aarch64_sleigh \
    --address 0x400544 --ir_out /tmp/llvmkit-aarch64-sleigh.ll \
    --bytes 1F2003D5
  test -s /tmp/llvmkit-aarch64-sleigh.ll
  /tmp/llvmkit-consumer/remill_consumer
  "$sdk/bin/clang" -x c -o /tmp/llvmkit-lief-input - <<'C'
#include <stdio.h>
int main(void) { puts("lief-roundtrip-ok"); return 0; }
C
  /tmp/llvmkit-consumer/lief_consumer /tmp/llvmkit-lief-input /tmp/llvmkit-lief-output
  chmod +x /tmp/llvmkit-lief-output
  test "$(/tmp/llvmkit-lief-output)" = lief-roundtrip-ok
fi
