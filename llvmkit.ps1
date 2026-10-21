param(
    [Parameter(Position=0)][ValidateSet('build', 'verify', 'list')][string]$Command = 'build',
    [Parameter(Position=1)][string]$Archive,
    [string]$WorkRoot = (Join-Path $PSScriptRoot 'build\windows'),
    [int]$Jobs = 0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
switch ($Command) {
    build {
        if ($Archive -and $Archive -ne 'llvm') { throw 'Windows builds currently support the llvm profile only.' }
        & "$PSScriptRoot\scripts\build-llvm-windows.ps1" -WorkRoot $WorkRoot -Jobs $Jobs
    }
    verify {
        if (-not $Archive) { throw 'Usage: .\llvmkit.ps1 verify ARCHIVE.zip' }
        & "$PSScriptRoot\scripts\verify-sdk-windows.ps1" -Archive $Archive
    }
    list {
        if (Test-Path "$PSScriptRoot\dist") { Get-ChildItem "$PSScriptRoot\dist" -Filter '*windows*.zip*' }
    }
}
