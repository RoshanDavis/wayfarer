# Build a Windows MSIX for Wayfarer.
#
# `dart run msix:create` cannot be used as-is here: the msix package's bundled
# makeappx.exe fails to start on this machine ("side-by-side configuration is
# incorrect" — a missing VC++ runtime for that bundled binary). So this script
# generates the package contents with `dart run msix:build` (whose bundled
# makepri works fine) and then packs + signs with the Windows SDK's own
# makeappx.exe / signtool.exe, which are installed with the VS C++ workload.
#
# Usage:
#   ./tool/build_msix.ps1            # local self-signed test package
#   ./tool/build_msix.ps1 -Store     # unsigned package for Microsoft Store upload
#
# Before the first -Store build, reserve the app in Partner Center and fill in
# the three STORE values in pubspec.yaml > msix_config (identity_name,
# publisher_display_name, publisher). The Store does the signing on upload, so
# -Store produces an unsigned .msix on purpose.

[CmdletBinding()]
param(
    [switch]$Store
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo  # dart run resolves pubspec.yaml from the current directory
$release = Join-Path $repo 'build\windows\x64\runner\Release'
$outName = if ($Store) { 'wayfarer-store.msix' } else { 'wayfarer.msix' }
$out = Join-Path $repo "build\windows\x64\runner\$outName"

# 1. Generate the unpackaged MSIX files (AppxManifest, logos, resources.pri).
Write-Host '==> Generating MSIX files (dart run msix:build)...' -ForegroundColor Cyan
$buildArgs = @('run', 'msix:build')
if ($Store) { $buildArgs += '--store' }
& dart @buildArgs
if ($LASTEXITCODE -ne 0) { throw "msix:build failed (exit $LASTEXITCODE)" }

# 2. Locate the Windows SDK tools (highest installed version, x64).
function Find-SdkTool([string]$name) {
    $base = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    Get-ChildItem -Path $base -Recurse -Filter $name -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\10\.\d+\.\d+\.\d+\\x64\\' } |
        Sort-Object { [version]$_.Directory.Parent.Name } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
$makeappx = Find-SdkTool 'makeappx.exe'
if (-not $makeappx) { throw 'makeappx.exe not found — install the Windows 10/11 SDK.' }

# 3. Pack. Output lives outside the content dir so it is not packed into itself.
Write-Host "==> Packing $out ..." -ForegroundColor Cyan
& $makeappx pack /o /d $release /p $out
if ($LASTEXITCODE -ne 0) { throw "makeappx failed (exit $LASTEXITCODE)" }

# 4. Sign — local test packages only. Store packages are signed by Microsoft.
if (-not $Store) {
    $pfx = Get-ChildItem "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\msix-*\lib\assets\test_certificate.pfx" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $pfx) { throw 'test_certificate.pfx not found in the msix package cache.' }
    $signtool = Find-SdkTool 'signtool.exe'
    if (-not $signtool) { throw 'signtool.exe not found — install the Windows 10/11 SDK.' }
    Write-Host '==> Signing with the msix test certificate...' -ForegroundColor Cyan
    & $signtool sign /fd SHA256 /f $pfx /p 1234 $out
    if ($LASTEXITCODE -ne 0) { throw "signtool failed (exit $LASTEXITCODE)" }
    $script:testPfx = $pfx
}

Write-Host ''
Write-Host "MSIX created: $out" -ForegroundColor Green
if ($Store) {
    Write-Host 'Upload this file in Partner Center; Microsoft signs it on submission.' -ForegroundColor Green
} else {
    Write-Host 'Local test package. To install it, first trust the test cert once (run as admin):' -ForegroundColor Yellow
    Write-Host "  Import-PfxCertificate -FilePath `"$script:testPfx`" -Password (ConvertTo-SecureString '1234' -AsPlainText -Force) -CertStoreLocation Cert:\LocalMachine\Root" -ForegroundColor Yellow
    Write-Host 'Then double-click the .msix (or: Add-AppxPackage <path>).' -ForegroundColor Yellow
}
