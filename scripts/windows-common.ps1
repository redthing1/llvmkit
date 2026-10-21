Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    $command = Get-Command $Program -ErrorAction Stop
    $savedPreference = $ErrorActionPreference
    try {
        # PowerShell 5.1 treats redirected native stderr as ErrorRecord objects.
        # Capture diagnostics without treating a successful tool's stderr as failure.
        $ErrorActionPreference = 'Continue'
        & $command @Arguments 2>&1 | ForEach-Object { $_.ToString() } | Out-Host
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($exitCode -ne 0) { throw "$Program exited with code $exitCode" }
}

function Read-ReleaseInputs {
    param([string]$Path)
    $inputs = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^([A-Z0-9_]+)=(.*)$') {
            $inputs[$Matches[1]] = $Matches[2].Trim().Trim("'", '"')
        }
    }
    return $inputs
}

function Initialize-Msvc {
    if ($env:VSCMD_ARG_TGT_ARCH -eq 'x64' -and (Get-Command cl.exe -ErrorAction SilentlyContinue)) { return }
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { throw 'Install Visual Studio 2022 C++ Build Tools and the Windows SDK first.' }
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'No Visual Studio installation with x64 C++ tools found.' }
    $devcmd = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
    $lines = & $env:ComSpec /d /s /c "`"`"$devcmd`" -no_logo -arch=x64 -host_arch=x64 && set`""
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the MSVC environment.' }
    foreach ($line in $lines) {
        if ($line -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
