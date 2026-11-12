param([Parameter(Mandatory=$true)][string]$GameDirectory)
$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'QueensDomain-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Queen''s Domain before installing.'
}
$chosen = (Resolve-Path -LiteralPath $GameDirectory).Path
if (Test-Path -LiteralPath (Join-Path $chosen 'QueensDomain-Win64-Shipping.exe')) {
    $runtime = $chosen
} else {
    $runtime = Join-Path $chosen 'QueensDomain\Binaries\Win64'
}
$runtime = (Resolve-Path -LiteralPath $runtime).Path
if (!(Test-Path -LiteralPath (Join-Path $runtime 'ue4ss\UE4SS.dll'))) { throw 'Install UE4SS first.' }
$modRoot = Join-Path $runtime 'ue4ss\Mods'
$target = Join-Path $modRoot 'HatchlingsWeaponWheel'
$source = Join-Path $PSScriptRoot 'Mods\HatchlingsWeaponWheel'
$data = Join-Path $env:LOCALAPPDATA 'QueensDomain\Saved\WeaponWheel'
New-Item -ItemType Directory -Force -Path $data | Out-Null
$backupRoot = [IO.Path]::GetFullPath((Join-Path $data 'install-backups'))
foreach ($name in @('QueensWeaponWheel','HatchlingsWeaponWheel')) {
    $existing = Join-Path $modRoot $name
    if (!(Test-Path -LiteralPath $existing)) { continue }
    $resolved = (Resolve-Path -LiteralPath $existing).Path
    $expected = [IO.Path]::GetFullPath((Join-Path $modRoot $name))
    if (![string]::Equals($resolved,$expected,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unexpected mod path; no files were moved.'
    }
    $backup = [IO.Path]::GetFullPath((Join-Path $backupRoot (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff')))
    if (![string]::Equals([IO.Path]::GetDirectoryName($backup),$backupRoot,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unexpected backup path; no files were moved.'
    }
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    if ($name -eq 'QueensWeaponWheel') {
        Move-Item -LiteralPath $resolved -Destination $backup
    } else {
        Copy-Item -LiteralPath $resolved -Destination $backup -Recurse
    }
}
New-Item -ItemType Directory -Force -Path $target | Out-Null
Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $target -Recurse -Force
Set-Content -LiteralPath (Join-Path $target 'enabled.txt') -Value ''
$mods = Join-Path $modRoot 'mods.txt'
$lines = if (Test-Path -LiteralPath $mods) { @(Get-Content -LiteralPath $mods) } else { @() }
$lines = @($lines | Where-Object { $_ -notmatch '^\s*(QueensWeaponWheel|HatchlingsWeaponWheel)\s*:' })
$lines += 'HatchlingsWeaponWheel : 1'
Set-Content -LiteralPath $mods -Value $lines
Write-Output 'Installed Hatchling''s Weapon Wheel. Start the game; hold Alt to use it, F10 to customize.'
