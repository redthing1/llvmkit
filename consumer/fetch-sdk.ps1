param([Parameter(Mandatory, Position=0)][string]$Lock)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Lock = (Resolve-Path -LiteralPath $Lock).Path
$inputs = @{}
foreach ($line in Get-Content -LiteralPath $Lock) {
    if ($line -match '^(TOOLCHAIN_SOURCE|TOOLCHAIN_SHA256)=(.*)$') {
        $inputs[$Matches[1]] = $Matches[2].Trim().Trim("'", '"')
    }
}
if (-not $inputs.ContainsKey('TOOLCHAIN_SOURCE') -or
    -not $inputs.ContainsKey('TOOLCHAIN_SHA256') -or
    $inputs.TOOLCHAIN_SHA256 -cnotmatch '^[0-9a-f]{64}$') {
    throw 'Lock must define TOOLCHAIN_SOURCE and a lowercase TOOLCHAIN_SHA256.'
}
$cache = Join-Path $env:LOCALAPPDATA 'toolchain-sdks'
$target = Join-Path $cache $inputs.TOOLCHAIN_SHA256
function Test-Complete([string]$Prefix) {
    return (Test-Path "$Prefix\bin\clang-cl.exe") -and (Test-Path "$Prefix\share\cmake\toolchain.cmake")
}
if (Test-Complete $target) { Write-Output $target; return }
$scratch = Join-Path $cache ".fetch-$([Guid]::NewGuid())"
New-Item -ItemType Directory -Force $scratch | Out-Null
try {
    $archive = Join-Path $scratch 'archive.zip'
    $source = $inputs.TOOLCHAIN_SOURCE
    if ($source -match '^https?://') {
        & curl.exe -fL --retry 3 $source -o $archive
        if ($LASTEXITCODE -ne 0) { throw 'SDK download failed.' }
    } else {
        if (-not [IO.Path]::IsPathRooted($source)) { $source = Join-Path (Split-Path $Lock) $source }
        Copy-Item -LiteralPath $source -Destination $archive
    }
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $inputs.TOOLCHAIN_SHA256) { throw 'SDK checksum mismatch.' }
    & tar.exe -xf $archive -C $scratch
    if ($LASTEXITCODE -ne 0 -or -not (Test-Complete "$scratch\sdk")) { throw 'Invalid Windows SDK archive.' }
    if (-not (Test-Path $target)) {
        try { Move-Item -LiteralPath "$scratch\sdk" -Destination $target }
        catch { if (-not (Test-Complete $target)) { throw } }
    }
    if (-not (Test-Complete $target)) { throw "SDK cache entry is incomplete: $target" }
    Write-Output $target
} finally { Remove-Item -LiteralPath $scratch -Recurse -Force }
