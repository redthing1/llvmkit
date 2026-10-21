#!/usr/bin/env bash
set -euo pipefail
sdk=${1:?SDK prefix}
project=${2:?external project fixtures}
output=${3:?output directory}
unset LLVM_SDK LLVM_NATIVE_TOOLCHAIN WINDOWS_SYSROOT MSVC_WINE_ROOT
for tool in cmake ninja clang-cl lld-link wine; do
  if command -v "$tool" >/dev/null; then
    echo "Expected a base image without installed developer tools: $tool" >&2
    exit 1
  fi
done
"$sdk/bin/cmake" --version
"$sdk/bin/ninja" --version
"$sdk/bin/clang-cl" --version
"$sdk/bin/cmake-windows" -S "$project/plugins" -B "$output/plugin"
"$sdk/bin/cmake-windows" --build "$output/plugin" --parallel 2 --verbose
"$sdk/bin/cmake-windows" -S "$project/consumer" -B "$output/consumer" -DLLVMKIT_WITH_LAB=OFF
"$sdk/bin/cmake-windows" --build "$output/consumer" --parallel 2 --verbose
plugin="$output/plugin/LLVMKitPasses.dll"
major=$(tr -d '\r\n' < "$sdk/targets/windows-x86_64/llvm/share/llvmkit/llvm-major")
"$sdk/bin/llvm-readobj" --coff-imports "$plugin" > "$output/imports.txt"
grep -q "LLVM-$major.dll" "$output/imports.txt"
"$sdk/bin/llvm-readobj" --coff-exports "$plugin" > "$output/exports.txt"
grep -q llvmGetPassPluginInfo "$output/exports.txt"
echo 'Self-contained cross package passed: relocated tools, plugin DLL, shared LLVM import, plugin export, consumer executable.'
