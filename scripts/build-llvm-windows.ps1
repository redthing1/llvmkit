param(
    [string]$WorkRoot = (Join-Path $PSScriptRoot '..\build\windows'),
    [int]$Jobs = 0
)
. "$PSScriptRoot\windows-common.ps1"
$repo = (Resolve-Path "$PSScriptRoot\..").Path
$inputs = Read-ReleaseInputs "$repo\versions.env"
Initialize-Msvc
foreach ($tool in 'cmake.exe', 'ninja.exe', 'python.exe', 'curl.exe', 'tar.exe') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required build tool missing: $tool" }
}
Invoke-Checked python.exe @('--version')
if ($Jobs -eq 0) {
    $memoryGiB = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    $memoryJobs = [Math]::Max(1, [Math]::Floor(($memoryGiB - 4) / 1.5))
    $Jobs = [Math]::Min([Environment]::ProcessorCount, [Math]::Min(32, $memoryJobs))
}
if ($Jobs -lt 1) { throw 'Jobs must be positive.' }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force $WorkRoot, "$repo\dist" | Out-Null
$version = $inputs.LLVM_VERSION
$targets = $inputs.LLVM_TARGETS
if ($inputs.ContainsKey('LLVM_WINDOWS_TARGETS')) { $targets = $inputs.LLVM_WINDOWS_TARGETS }
$compiler = (Get-Item (Get-Command cl.exe).Source).VersionInfo.FileVersion
$identity = @($version, $inputs.LLVM_SHA256, $inputs.LLVM_PROJECTS, $targets,
              $inputs.LLVM_ASSERTIONS, $compiler, $env:WindowsSDKVersion)
foreach ($file in @('scripts/build-llvm-windows.ps1', 'scripts/windows-common.ps1',
                    'scripts/apply-llvm-windows-patches.py',
                    'scripts/verify-sdk-windows.ps1', 'consumer/toolchain.cmake',
                    'tests/plugins/CMakeLists.txt', 'tests/plugins/passes.cpp',
                    'tests/plugins/input.ll', 'tests/plugins/input.c',
                    'tests/consumer/CMakeLists.txt', 'tests/consumer/llvm_consumer.cpp')) {
    $identity += Get-Sha256 (Join-Path $repo $file)
}
$patchHashes = [ordered]@{}
foreach ($patch in Get-ChildItem "$repo\patches\llvm\windows\*.patch" | Sort-Object Name) {
    $patchHashes[$patch.Name] = Get-Sha256 $patch.FullName
    $identity += $patchHashes[$patch.Name]
}
$hasher = [Security.Cryptography.SHA256]::Create()
try {
    $digest = $hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes(($identity -join "`n")))
    $buildId = ([BitConverter]::ToString($digest) -replace '-', '').ToLowerInvariant().Substring(0,12)
} finally { $hasher.Dispose() }
$sourceArchive = Join-Path $WorkRoot "llvm-project-$version.src.tar.xz"
if (-not (Test-Path $sourceArchive)) {
    Invoke-Checked curl.exe @('-fL', '--retry', '5',
        "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/llvm-project-$version.src.tar.xz",
        '-o', "$sourceArchive.partial")
    if ((Get-Sha256 "$sourceArchive.partial") -ne $inputs.LLVM_SHA256) { throw 'LLVM source checksum mismatch.' }
    Move-Item "$sourceArchive.partial" $sourceArchive
}
if ((Get-Sha256 $sourceArchive) -ne $inputs.LLVM_SHA256) { throw 'LLVM source checksum mismatch.' }
$source = Join-Path $WorkRoot "src-$version"
if (-not (Test-Path "$source\.llvmkit-extracted")) {
    New-Item -ItemType Directory -Force $source | Out-Null
    # Test fixtures and optional MLGO Python entry points contain Unix symlinks.
    # They are not built or distributed by this SDK.
    Invoke-Checked tar.exe @('-xf', $sourceArchive, '-C', $source, '--strip-components=1',
        '--exclude', '*/test/*', '--exclude', '*/unittests/*',
        '--exclude', '*/llvm/utils/mlgo-utils/combine_training_corpus.py',
        '--exclude', '*/llvm/utils/mlgo-utils/extract_ir.py',
        '--exclude', '*/llvm/utils/mlgo-utils/make_corpus.py')
    $inputs.LLVM_SHA256 | Set-Content "$source\.llvmkit-extracted" -Encoding ASCII
}
Invoke-Checked python.exe @("$repo\scripts\apply-llvm-windows-patches.py", $source, "$repo\patches\llvm\windows")
$build = Join-Path $WorkRoot "build-$version"
$install = Join-Path $WorkRoot "install-$buildId"
$sdk = Join-Path $install 'sdk'
Invoke-Checked cmake.exe @('-S', "$source\llvm", '-B', $build, '-G', 'Ninja',
    '-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_INSTALL_PREFIX=$sdk",
    '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL', '-DLLVM_USE_CRT_RELEASE=MD',
    "-DLLVM_ENABLE_PROJECTS=$($inputs.LLVM_PROJECTS)", "-DLLVM_TARGETS_TO_BUILD=$targets",
    "-DLLVM_ENABLE_ASSERTIONS=$($inputs.LLVM_ASSERTIONS)", '-DLLVM_ENABLE_RTTI=ON',
    '-DLLVM_ENABLE_PLUGINS=ON', '-DLLVM_BUILD_LLVM_DYLIB=ON',
    '-DLLVM_BUILD_LLVM_DYLIB_VIS=ON', '-DLLVM_LINK_LLVM_DYLIB=ON',
    '-DCLANG_LINK_CLANG_DYLIB=OFF', '-DCLANG_ENABLE_STATIC_ANALYZER=OFF',
    '-DCLANG_ENABLE_ARCMT=OFF', '-DLLVM_INCLUDE_TESTS=OFF',
    '-DLLVM_INCLUDE_EXAMPLES=OFF', '-DLLVM_INCLUDE_BENCHMARKS=OFF',
    '-DLLVM_INCLUDE_DOCS=OFF', '-DLLVM_ENABLE_LIBEDIT=OFF',
    '-DLLVM_ENABLE_LIBXML2=OFF', '-DLLVM_ENABLE_ZLIB=OFF',
    '-DLLVM_ENABLE_ZSTD=OFF', '-DLLVM_ENABLE_DIA_SDK=OFF', '-DLLVM_PARALLEL_LINK_JOBS=2')
Invoke-Checked cmake.exe @('--build', $build, '--parallel', "$Jobs")
Invoke-Checked cmake.exe @('--install', $build)

# Keep the tools usable on a machine without Visual Studio or a redist install.
$crt = @(Get-ChildItem "$env:VCToolsRedistDir\x64" -Directory -Filter 'Microsoft.VC*.CRT')
if ($crt.Count -ne 1) { throw 'Could not identify the redistributable x64 MSVC runtime.' }
Copy-Item "$($crt[0].FullName)\*.dll" "$sdk\bin"
New-Item -ItemType Directory -Force "$sdk\share\cmake", "$sdk\share\llvmkit\patches\llvm", "$sdk\share\licenses\llvm" | Out-Null
Copy-Item "$repo\patches\llvm\windows\*.patch" "$sdk\share\llvmkit\patches\llvm"
Copy-Item "$repo\consumer\toolchain.cmake" "$sdk\share\cmake"
Copy-Item "$source\llvm\LICENSE.TXT" "$sdk\share\licenses\llvm"
New-Item -ItemType Directory -Force "$sdk\share\licenses\msvc" | Out-Null
@'
This SDK includes unmodified x64 MSVC runtime DLLs from VCToolsRedistDir.
Their redistribution is governed by Microsoft Software License Terms.
https://visualstudio.microsoft.com/license-terms/
https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution
'@ | Set-Content "$sdk\share\licenses\msvc\README.txt" -Encoding UTF8
foreach ($project in ($inputs.LLVM_PROJECTS -split ';')) {
    New-Item -ItemType Directory -Force "$sdk\share\licenses\$project" | Out-Null
    Copy-Item "$source\$project\LICENSE.TXT" "$sdk\share\licenses\$project"
}
$config = "$sdk\lib\cmake\llvm\LLVMConfig.cmake"
$text = [IO.File]::ReadAllText($config) -replace '(?m)^set\(LLVM_DEFAULT_EXTERNAL_LIT .*\r?\n', ''
[IO.File]::WriteAllText($config, $text)
$runtime = @{}
foreach ($dll in Get-ChildItem "$sdk\bin\*.dll") { $runtime[$dll.Name] = Get-Sha256 $dll.FullName }
$manifest = [ordered]@{
    artifact = 'llvm'; abi = 'windows-x86_64-msvc'; build_id = $buildId
    llvm_version = $version; llvm_sha256 = $inputs.LLVM_SHA256
    llvm_targets = $targets; llvm_projects = $inputs.LLVM_PROJECTS
    llvm_assertions = $inputs.LLVM_ASSERTIONS; llvm_rtti = 'ON'; llvm_plugins = 'ON'
    llvm_dylib_visibility = 'ON'; llvm_dia = 'OFF'; msvc_runtime = 'MD'; compiler_version = $compiler
    windows_sdk_version = $env:WindowsSDKVersion.TrimEnd('\'); runtime_dlls = $runtime
    patches = $patchHashes
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content "$sdk\share\llvmkit\manifest.json" -Encoding UTF8
$version.Split('.')[0] | Set-Content "$sdk\share\llvmkit\llvm-major" -Encoding ASCII
foreach ($dir in @("$sdk\lib\cmake", "$sdk\share\cmake")) {
    foreach ($file in Get-ChildItem $dir -Recurse -Filter '*.cmake') {
        $content = [IO.File]::ReadAllText($file.FullName).Replace('\', '/')
        if ($content.Contains($WorkRoot.Replace('\', '/'))) { throw "Build path retained in $($file.FullName)" }
    }
}

$name = "llvm-$version-windows-x86_64-msvc-$buildId"
$temporaryArchive = Join-Path $repo "dist\$name.partial.zip"
if (Test-Path $temporaryArchive) { Remove-Item $temporaryArchive }
Invoke-Checked tar.exe @('-a', '-cf', $temporaryArchive, '-C', $install, 'sdk')
$checksum = Get-Sha256 $temporaryArchive
$archive = Join-Path $repo "dist\$name-$($checksum.Substring(0,12)).zip"
if (Test-Path $archive) { Remove-Item $temporaryArchive } else { Move-Item $temporaryArchive $archive }
"$checksum  $([IO.Path]::GetFileName($archive))" | Set-Content "$archive.sha256" -Encoding ASCII
# Verify the actual archive after extraction to a different prefix with spaces.
& "$PSScriptRoot\verify-sdk-windows.ps1" -Archive $archive -ProbeDirectory (Join-Path $WorkRoot 'runtime-probe')
Write-Host "Verified archive: $archive"
