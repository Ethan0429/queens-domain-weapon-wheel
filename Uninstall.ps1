param([Parameter(Mandatory=$true)][string]$GameDirectory)
$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'QueensDomain-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Queen''s Domain before uninstalling.'
}
$chosen = (Resolve-Path -LiteralPath $GameDirectory).Path
$runtime = if (Test-Path -LiteralPath (Join-Path $chosen 'QueensDomain-Win64-Shipping.exe')) {
    $chosen
} else { Join-Path $chosen 'QueensDomain\Binaries\Win64' }
$runtime = (Resolve-Path -LiteralPath $runtime).Path
$modRoot = (Resolve-Path -LiteralPath (Join-Path $runtime 'ue4ss\Mods')).Path
$target = Join-Path $modRoot 'QueensWeaponWheel'
if (Test-Path -LiteralPath $target) {
    $resolved = (Resolve-Path -LiteralPath $target).Path
    $expected = [IO.Path]::GetFullPath((Join-Path $modRoot 'QueensWeaponWheel'))
    if (![string]::Equals($resolved,$expected,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unexpected mod path; no files were removed.'
    }
    if (![IO.Path]::GetFileName($resolved).Equals('QueensWeaponWheel')) { throw 'Unexpected directory name.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$mods = Join-Path $modRoot 'mods.txt'
if (Test-Path -LiteralPath $mods) {
    $lines = @(Get-Content -LiteralPath $mods | Where-Object { $_ -notmatch '^\s*QueensWeaponWheel\s*:' })
    Set-Content -LiteralPath $mods -Value $lines
}
Write-Output 'Removed the weapon wheel. Other mods, configuration, and saves were retained.'
