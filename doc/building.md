# Building SDKs

Archives and `.sha256` checksum files are written to `dist/`.

## Linux

Requires Linux x86-64 with rootless Podman 4.9 or newer.

```sh
./llvmkit build all
```

Use `build llvm` or `build lab` to build one flavor. Build layers are cached
between runs. Parallelism follows the available CPU and memory; set `JOBS`
to choose a limit:

```sh
JOBS=8 ./llvmkit build all
```

`LLVM_JOBS`, `REMILL_JOBS`, and `LIEF_JOBS` override individual build stages.

## Windows

Requires Windows x64, Visual Studio 2022 C++ Build Tools with the Windows SDK,
Python 3.8+, CMake, and Ninja. Use a short work path with at least 40 GB free:

```powershell
.\llvmkit.ps1 build -WorkRoot C:\llvm-build
```

The script initializes MSVC, builds the LLVM SDK, and verifies the ZIP.
Sources and build files are retained for incremental builds. Parallelism
follows CPU and memory; use `-Jobs 8` to choose a limit.

For the Linux-hosted Windows cross package, see [Windows cross](windows-cross.md).

## Build options

Source versions and build options are in [`versions.env`](../versions.env).
Defaults include all LLVM targets, Clang, LLD, RTTI, assertions, shared LLVM,
and pass-plugin support in a Release build.

For a smaller SDK, set `LLVM_TARGETS='X86;AArch64'`, or another target subset.
`LLVM_WINDOWS_TARGETS` overrides this setting for Windows builds.

Lab includes LIEF's ELF, PE/COFF, and JSON support. Set `LIEF_MACHO=ON` or
`LIEF_ANDROID=ON` to include those formats.

## Verification

Check both current Linux flavors, or a single archive:

```sh
./llvmkit verify all
./llvmkit verify "$archive"
```

Verification relocates the SDK and builds and runs CMake consumers and pass
plugins on AlmaLinux 9, Ubuntu 22.04, and Debian 12.

Windows builds verify automatically. To check an existing ZIP:

```powershell
.\llvmkit.ps1 verify $archive
```
