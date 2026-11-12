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
$target = Join-Path $modRoot 'QueensWeaponWheel'
$source = Join-Path $PSScriptRoot 'Mods\QueensWeaponWheel'
$data = Join-Path $env:LOCALAPPDATA 'QueensDomain\Saved\WeaponWheel'
New-Item -ItemType Directory -Force -Path $data | Out-Null
if (Test-Path -LiteralPath $target) {
    $backup = Join-Path $data ('install-backups\' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    Copy-Item -LiteralPath $target -Destination $backup -Recurse
}
New-Item -ItemType Directory -Force -Path $target | Out-Null
Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $target -Recurse -Force
Set-Content -LiteralPath (Join-Path $target 'enabled.txt') -Value ''
$mods = Join-Path $modRoot 'mods.txt'
$lines = if (Test-Path -LiteralPath $mods) { @(Get-Content -LiteralPath $mods) } else { @() }
$lines = @($lines | Where-Object { $_ -notmatch '^\s*QueensWeaponWheel\s*:' })
$lines += 'QueensWeaponWheel : 1'
Set-Content -LiteralPath $mods -Value $lines
Write-Output 'Installed Hatchling''s Weapon Wheel. Start the game; hold Alt to use it, F10 to customize.'
