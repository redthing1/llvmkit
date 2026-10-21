# llvmkit

Build relocatable LLVM SDKs for Linux and Windows, with Clang, LLD, headers,
libraries, and CMake packages.

| Flavor | Host | Contents |
| --- | --- | --- |
| LLVM | Linux x86-64 | LLVM, Clang, and LLD |
| Lab | Linux x86-64 | LLVM plus Remill, LIEF, and their dependencies |
| Windows LLVM | Windows x64 | LLVM with a shared LLVM DLL and bundled runtime DLLs |
| Windows cross | Linux x86-64 | Linux build tools, Windows LLVM, and Microsoft headers and libraries |

Each archive extracts to one relocatable `sdk/` directory. Linux SDKs require
glibc 2.34 or newer.

## Build

On Linux x86-64 with rootless Podman 4.9 or newer:

```sh
./llvmkit build llvm
```

Archives go to `dist/`. Use `build lab` for Remill and LIEF, or `build all`
for both Linux flavors. See [building](doc/building.md) for Windows and build
options.

## Use

Extract a native SDK and point your project at its LLVM package:

```sh
cmake -S . -B build -DLLVM_DIR="$PWD/sdk/lib/cmake/llvm"
cmake --build build
```

Projects use `find_package(LLVM CONFIG)`. The Lab SDK also provides
`find_package(remill CONFIG)` and `find_package(LIEF CONFIG)`.

To use bundled Clang as your compiler, configure with
`-DCMAKE_TOOLCHAIN_FILE="$PWD/sdk/share/cmake/toolchain.cmake"`.

- [Use an SDK](doc/using.md)
- [Build Windows binaries from Linux](doc/windows-cross.md)
