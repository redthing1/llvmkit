# Windows cross SDK

Build Windows x64 binaries on Linux with the MSVC C++ ABI and `/MD` runtime.
The SDK includes Linux-native LLVM, CMake, and Ninja, plus Windows LLVM and
the Microsoft headers and libraries. It requires Linux x86-64 with glibc 2.34
or newer.

## Use

Extract the archive and use the bundled CMake wrapper:

```sh
sdk="$PWD/sdk"
"$sdk/bin/cmake-windows" -S . -B build-windows
"$sdk/bin/cmake-windows" --build build-windows
```

The wrapper uses Ninja and the Windows toolchain, and defaults to Release
mode. Projects use `find_package(LLVM CONFIG)` and `add_llvm_pass_plugin`.

Compilation and linking run natively on Linux. Run the resulting programs
on Windows or under Wine. The Windows LLVM tools and runtime DLLs are in
`sdk/targets/windows-x86_64/llvm/`.

The [fetch helper](using.md#fetch-and-cache) also accepts this archive; use
the returned SDK's `bin/cmake-windows` to configure and build.

## Build

Assembly requires rootless Podman, CMake, Python 3.9+, curl, tar, and zstd.
Build the [Linux and Windows LLVM SDKs](building.md), then place their
archives and `.sha256` files in `dist/` and run:

```sh
./llvmkit build windows-cross
```

To select the inputs explicitly:

```sh
./llvmkit build windows-cross "$linux_archive" "$windows_archive"
```

The inputs must use the same LLVM sources, projects, and assertions.
Assembly downloads Microsoft headers and libraries using xwin; its inputs
are configured in [`windows-cross.env`](../windows-cross.env).

## Verification

```sh
./llvmkit verify "$archive"
```

This builds a Windows consumer and pass plugin using only the SDK's tools
on AlmaLinux 9, Ubuntu 22.04, and Debian 12. To also run them under Wine:

```sh
./llvmkit verify --run "$archive"
```
