param(
    [Parameter(Mandatory)][string]$Archive,
    [string]$TestRoot = (Join-Path $PSScriptRoot '..\tests'),
    [string]$ProbeDirectory
)
. "$PSScriptRoot\windows-common.ps1"
Initialize-Msvc
$Archive = (Resolve-Path -LiteralPath $Archive).Path
$checksumLine = (Get-Content -LiteralPath "$Archive.sha256" -Raw).Trim()
if ($checksumLine -notmatch '^([0-9a-f]{64})  (.+)$') { throw 'Invalid archive checksum file.' }
if ($Matches[2] -ne [IO.Path]::GetFileName($Archive)) { throw 'Checksum filename mismatch.' }
if ((Get-Sha256 $Archive) -ne $Matches[1]) { throw 'Archive checksum mismatch.' }
$scratch = Join-Path ([IO.Path]::GetTempPath()) "llvmkit relocated $([Guid]::NewGuid())"
New-Item -ItemType Directory $scratch | Out-Null
$savedPath = $env:PATH
try {
    Invoke-Checked tar.exe @('-xf', $Archive, '-C', $scratch)
    $sdk = Join-Path $scratch 'sdk'
    $manifest = Get-Content "$sdk\share\llvmkit\manifest.json" -Raw | ConvertFrom-Json
    $major = $manifest.llvm_version.Split('.')[0]
    if (-not (Test-Path "$sdk\bin\LLVM-$major.dll")) { throw 'LLVM DLL missing.' }
    if (-not (Test-Path "$sdk\lib\LLVM-$major.lib")) { throw 'LLVM import library missing.' }
    foreach ($property in $manifest.runtime_dlls.PSObject.Properties) {
        if ((Get-Sha256 "$sdk\bin\$($property.Name)") -ne $property.Value) { throw "Runtime hash mismatch: $($property.Name)" }
    }
    # Exclude the builder's runtime directories from DLL resolution for tools.
    $env:PATH = "$sdk\bin;$env:SystemRoot\System32;$env:SystemRoot"
    foreach ($tool in @('clang', 'opt', 'llvm-config', 'llvm-nm', 'bugpoint', 'llvm-profgen', 'lld-link')) {
        Invoke-Checked "$sdk\bin\$tool.exe" @('--version')
    }
    $env:PATH = "$sdk\bin;$savedPath"
    Invoke-Checked cmake.exe @('-S', "$TestRoot\consumer", '-B', "$scratch\consumer", '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_PREFIX_PATH=$sdk",
        "-DCMAKE_CXX_COMPILER=$sdk\bin\clang-cl.exe", '-DLLVMKIT_WITH_LAB=OFF')
    Invoke-Checked cmake.exe @('--build', "$scratch\consumer", '--parallel', '2')
    Invoke-Checked "$scratch\consumer\llvm_consumer.exe" @()
    Invoke-Checked cmake.exe @('-S', "$TestRoot\plugins", '-B', "$scratch\plugins", '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_PREFIX_PATH=$sdk",
        "-DCMAKE_C_COMPILER=$sdk\bin\clang-cl.exe", "-DCMAKE_CXX_COMPILER=$sdk\bin\clang-cl.exe")
    Invoke-Checked cmake.exe @('--build', "$scratch\plugins", '--parallel', '2')
    $plugin = "$scratch\plugins\LLVMKitPasses.dll"
    $imports = & "$sdk\bin\llvm-readobj.exe" --coff-imports $plugin
    if ($LASTEXITCODE -ne 0 -or ($imports -join "`n") -notmatch "LLVM-$major\.dll") { throw 'Plugin must import the shared LLVM DLL.' }
    $exports = & "$sdk\bin\llvm-readobj.exe" --coff-exports $plugin
    if ($LASTEXITCODE -ne 0 -or ($exports -join "`n") -notmatch 'llvmGetPassPluginInfo') { throw 'Plugin entry point is not exported.' }
    $ir = "$TestRoot\plugins\input.ll"
    # Native stderr is redirected to files to support Windows PowerShell 5.1.
    $countLog = "$scratch\count.log"
    $p = Start-Process "$sdk\bin\opt.exe" -ArgumentList @('-load-pass-plugin', "`"$plugin`"",
        '-passes=llvmkit-count', '-disable-output', "`"$ir`"") -Wait -PassThru -NoNewWindow -RedirectStandardError $countLog
    if ($p.ExitCode -ne 0 -or (Get-Content $countLog -Raw) -notmatch 'functions=3 instructions=15') { throw 'Module plugin pass failed.' }
    Invoke-Checked "$sdk\bin\opt.exe" @('-load-pass-plugin', $plugin, '-passes=llvmkit-inline',
        '-S', $ir, '-o', "$scratch\inline.ll")
    Invoke-Checked "$sdk\bin\opt.exe" @('-load-pass-plugin', $plugin,
        '-passes=module(llvmkit-count),function(llvmkit-inline),verify', '-S', $ir, '-o', "$scratch\pipeline.ll")
    foreach ($output in @('inline.ll', 'pipeline.ll')) {
        $irText = Get-Content "$scratch\$output" -Raw
        if ($irText -notmatch 'alwaysinline' -or $irText -match '\bnoinline\b') { throw "Function plugin pass failed: $output" }
    }
    Invoke-Checked "$sdk\bin\clang.exe" @('-O1', "-fpass-plugin=$plugin", '-S', '-emit-llvm',
        "$TestRoot\plugins\input.c", '-o', "$scratch\clang.ll")
    if ((Get-Content "$scratch\clang.ll" -Raw) -notmatch '"llvmkit.plugin"="loaded"') { throw 'Clang pipeline extension failed.' }
    # Native SDK tools and a linked consumer also work without build-tool PATHs.
    $env:PATH = "$sdk\bin;$env:SystemRoot\System32;$env:SystemRoot"
    Invoke-Checked "$scratch\consumer\llvm_consumer.exe" @()
    Invoke-Checked "$sdk\bin\opt.exe" @('-load-pass-plugin', $plugin, '-passes=llvmkit-count', '-disable-output', $ir)
    if ($ProbeDirectory) {
        New-Item -ItemType Directory -Force $ProbeDirectory | Out-Null
        Copy-Item $plugin, "$scratch\consumer\llvm_consumer.exe", $ir,
            "$TestRoot\plugins\input.c" $ProbeDirectory
    }
    Write-Host 'Windows SDK verified: relocation, CMake consumer, module/function plugins, combined pipeline, Clang extension, bundled runtime.'
} finally {
    $env:PATH = $savedPath
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
