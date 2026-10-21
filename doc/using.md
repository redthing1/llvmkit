# Using an SDK

Each archive contains a relocatable `sdk/` directory, with tools in `sdk/bin/`.
Use its CMake packages with your project's compiler, or select bundled Clang.

## Linux

Requires glibc 2.34 or newer and a C/C++ build environment. Extract the archive
and add `LLVM_DIR` to your usual CMake configuration:

```sh
tar --zstd -xf "$archive"
cmake -S . -B build -DLLVM_DIR="$PWD/sdk/lib/cmake/llvm"
cmake --build build
```

## Windows

Use an x64 Developer PowerShell with MSVC, the Windows SDK, CMake, and Ninja:

```powershell
Expand-Archive -LiteralPath $archive -DestinationPath .
cmake -S . -B build -G Ninja "-DLLVM_DIR=$PWD/sdk/lib/cmake/llvm"
cmake --build build
```

SDK tools include their runtime DLLs. Put `sdk/bin` on `PATH`, or copy its
runtime DLLs beside executables linked to shared LLVM.

## Bundled Clang

To use SDK Clang as your compiler, configure a new build directory with the
supplied toolchain file and Ninja:

```sh
cmake -S . -B build-clang -G Ninja "-DCMAKE_TOOLCHAIN_FILE=$PWD/sdk/share/cmake/toolchain.cmake"
cmake --build build-clang
```

## CMake packages

`LLVM_DIR` selects the LLVM package without changing your compiler or
toolchain. Set it in your configure command or CMake preset. A consumer can use:

```cmake
find_package(LLVM REQUIRED CONFIG)
add_executable(example main.cpp)
target_compile_features(example PRIVATE cxx_std_17)
target_include_directories(example SYSTEM PRIVATE ${LLVM_INCLUDE_DIRS})
separate_arguments(llvm_definitions NATIVE_COMMAND "${LLVM_DEFINITIONS}")
target_compile_options(example PRIVATE ${llvm_definitions})
target_link_libraries(example PRIVATE LLVM)
```

The Lab SDK also provides:

```cmake
find_package(remill REQUIRED CONFIG)
find_package(LIEF REQUIRED CONFIG COMPONENTS SHARED)
target_link_libraries(example PRIVATE remill LIEF::LIEF)
```

Set `CMAKE_PREFIX_PATH` to the SDK directory to discover all its packages,
including Remill and LIEF. See [`tests/consumer/`](../tests/consumer/) for
complete examples.

## Fetch and cache

For automatic downloads, copy [`fetch-sdk`](../consumer/fetch-sdk) and
[`toolchain.lock.example`](../consumer/toolchain.lock.example) into your
project. Save the example as `toolchain.lock` and set its archive URL or local
path and SHA-256 checksum. Relative paths start at the lockfile's directory.

```sh
sdk=$(./fetch-sdk toolchain.lock)
cmake -S . -B build -DLLVM_DIR="$sdk/lib/cmake/llvm"
cmake --build build
```

The helper verifies the checksum and caches the SDK. On Windows, use
[`fetch-sdk.ps1`](../consumer/fetch-sdk.ps1) with the same lockfile and a ZIP:

```powershell
$sdk = .\fetch-sdk.ps1 .\toolchain.lock
cmake -S . -B build -G Ninja "-DLLVM_DIR=$sdk/lib/cmake/llvm"
cmake --build build
```

## Pass plugins

Use `find_package(LLVM CONFIG)` and `add_llvm_pass_plugin`. The example in
[`tests/plugins/`](../tests/plugins/) includes module and function passes,
Windows DLL exports, and a Clang pipeline extension.

Build against the exact SDK that will load the plugin, with matching compiler
ABI, assertions, RTTI, and runtime settings.

## Remill guest-PC metadata

Set `REMILL_PC_METADATA=1` before `TraceLifter::Lift` to attach `remill.pc`
metadata to terminators of PC-indexed blocks. Each tag contains one `i64`
guest PC. Read it in the lift callback before LLVM transformations; synthetic
blocks have no tag, and later passes may discard it.
