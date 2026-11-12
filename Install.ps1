param([string]$GameDirectory,[switch]$NoPause)

$ErrorActionPreference = 'Stop'
$script:ModSource = Join-Path $PSScriptRoot 'Mods\HatchlingsWeaponWheel'
$script:LoaderUrl = 'https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v4.0.0/UE4SS_v4.0.0.zip'
$script:LoaderHash = '251ad0d1381a241750e036f5918cbf2b5d7ec58ebc608cb2dd09d459d0c81e45'
$script:BackupDirectory = $null

function Get-GameRuntime([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (!(Test-Path -LiteralPath $Path)) { return }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { $Path = Split-Path -Parent $Path }
    foreach ($suffix in @('', 'QueensDomain\Binaries\Win64', 'Binaries\Win64', 'game\QueensDomain\Binaries\Win64')) {
        $candidate = $Path
        if ($suffix) { $candidate = Join-Path $Path $suffix }
        if (Test-Path -LiteralPath (Join-Path $candidate 'QueensDomain-Win64-Shipping.exe') -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
}

function Get-SearchDrives {
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        if ($drive.IsReady -and $drive.DriveType -in @('Fixed','Removable')) { $drive.RootDirectory.FullName }
    }
}

function Get-SteamRoots {
    foreach ($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $entry = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($entry) {
            foreach ($property in @('SteamPath','InstallPath')) {
                if ($entry.$property) { [string]$entry.$property }
            }
        }
    }
    foreach ($base in @(${env:ProgramFiles(x86)},$env:ProgramFiles)) {
        if ($base) { Join-Path $base 'Steam' }
    }
    foreach ($drive in Get-SearchDrives) {
        foreach ($suffix in @('Steam','SteamLibrary','Games\Steam','Games\SteamLibrary','Program Files (x86)\Steam','Program Files\Steam')) {
            Join-Path $drive $suffix
        }
    }
}

function Get-SteamLibraries {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in Get-SteamRoots) {
        if (!(Test-Path -LiteralPath $root -PathType Container)) { continue }
        $root = (Resolve-Path -LiteralPath $root).Path
        if ($seen.Add($root)) { $root }
        foreach ($relative in @('steamapps\libraryfolders.vdf','config\libraryfolders.vdf')) {
            $vdf = Join-Path $root $relative
            if (!(Test-Path -LiteralPath $vdf -PathType Leaf)) { continue }
            $content = Get-Content -LiteralPath $vdf -Raw -ErrorAction SilentlyContinue
            foreach ($match in [regex]::Matches([string]$content,'"(?:path|\d+)"\s*"([^"\r\n]+)"')) {
                $library = $match.Groups[1].Value.Replace('\\','\')
                if ([IO.Path]::IsPathRooted($library) -and (Test-Path -LiteralPath $library -PathType Container)) {
                    $library = (Resolve-Path -LiteralPath $library).Path
                    if ($seen.Add($library)) { $library }
                }
            }
        }
    }
}

function Find-SteamInstallations {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($library in Get-SteamLibraries) {
        $apps = Join-Path $library 'steamapps'
        if (!(Test-Path -LiteralPath $apps -PathType Container)) { continue }
        foreach ($manifest in Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue) {
            $content = [string](Get-Content -LiteralPath $manifest.FullName -Raw -ErrorAction SilentlyContinue)
            $name = [regex]::Match($content,'"name"\s*"([^"\r\n]+)"').Groups[1].Value
            $install = [regex]::Match($content,'"installdir"\s*"([^"\r\n]+)"').Groups[1].Value
            if (($name -replace '[^a-zA-Z0-9]','') -notmatch '^QueensDomain' -and ($install -replace '[^a-zA-Z0-9]','') -notmatch '^QueensDomain') { continue }
            if (!$install -or [IO.Path]::IsPathRooted($install) -or $install -match '(^|[\\/])\.\.([\\/]|$)') { continue }
            $runtime = Get-GameRuntime (Join-Path (Join-Path $apps 'common') $install)
            if ($runtime -and $seen.Add($runtime)) { $runtime }
        }
        $common = Join-Path $apps 'common'
        if (!(Test-Path -LiteralPath $common -PathType Container)) { continue }
        foreach ($folder in Get-ChildItem -LiteralPath $common -Directory -ErrorAction SilentlyContinue) {
            if (($folder.Name -replace '[^a-zA-Z0-9]','') -notmatch '^QueensDomain') { continue }
            $runtime = Get-GameRuntime $folder.FullName
            if ($runtime -and $seen.Add($runtime)) { $runtime }
        }
    }
}

function Get-RegisteredLocations {
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($entry in Get-ItemProperty -Path $key -ErrorAction SilentlyContinue) {
            if (([string]$entry.DisplayName -replace '[^a-zA-Z0-9]','') -notmatch '^QueensDomain') { continue }
            if ($entry.InstallLocation) { [string]$entry.InstallLocation }
            if ($entry.DisplayIcon) {
                $match = [regex]::Match([string]$entry.DisplayIcon,'^"([^"]+)"|^(.+?\.exe)')
                if ($match.Success) {
                    $executable = $match.Groups[1].Value
                    if (!$executable) { $executable = $match.Groups[2].Value }
                    Split-Path -Parent $executable
                }
            }
        }
    }
}

function Get-OtherSearchRoots {
    foreach ($drive in Get-SearchDrives) {
        foreach ($suffix in @('Games','GOG Games','XboxGames','Program Files','Program Files (x86)')) {
            Join-Path $drive $suffix
        }
    }
    foreach ($suffix in @('Games','Downloads','Desktop','Documents')) {
        if ($env:USERPROFILE) { Join-Path $env:USERPROFILE $suffix }
    }
}

function Find-InFolders([string[]]$Roots,[int]$MaxDepth = 4) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $found = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $queue = [Collections.Generic.Queue[object]]::new()
    foreach ($root in $Roots) {
        if (Test-Path -LiteralPath $root -PathType Container) { $queue.Enqueue(@{Path=$root;Depth=0}) }
    }
    while ($queue.Count -gt 0) {
        $next = $queue.Dequeue()
        $folder = Get-Item -LiteralPath $next.Path -Force -ErrorAction SilentlyContinue
        if (!$folder -or ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -or !$seen.Add($folder.FullName)) { continue }
        $runtime = Get-GameRuntime $folder.FullName
        if ($runtime) {
            if ($found.Add($runtime)) { $runtime }
            continue
        }
        if ($next.Depth -ge $MaxDepth) { continue }
        foreach ($child in Get-ChildItem -LiteralPath $folder.FullName -Directory -Force -ErrorAction SilentlyContinue) {
            if ($child.Name -in @('Windows','Windows.old','ProgramData','Users','AppData','System Volume Information','$Recycle.Bin','.git','node_modules','Content','Engine','ue4ss')) { continue }
            $queue.Enqueue(@{Path=$child.FullName;Depth=$next.Depth+1})
        }
    }
}

function Find-GameInstallations {
    Write-Host 'Looking for Queen''s Domain in Steam libraries...'
    $found = @(Find-SteamInstallations | Select-Object -Unique)
    if ($found.Count) { return $found }
    Write-Host 'Checking other installation locations...'
    $found = @(foreach ($location in Get-RegisteredLocations) { Get-GameRuntime $location })
    if ($found.Count) { return ($found | Select-Object -Unique) }
    $found = @(Find-InFolders -Roots @(Get-OtherSearchRoots) -MaxDepth 4)
    if ($found.Count) { return $found }
    Write-Host 'Checking other folders on local drives. This may take a moment...'
    Find-InFolders -Roots @(Get-SearchDrives) -MaxDepth 4
}

function Confirm-Action([string]$Question) {
    while ($true) {
        $reply = Read-Host "$Question [y/N]"
        if ($reply -match '^(?i)y(es)?$') { return $true }
        if ([string]::IsNullOrWhiteSpace($reply) -or $reply -match '^(?i)n(o)?$') { return $false }
        Write-Host 'Enter Y or N.'
    }
}

function Select-GameRuntime([string]$RequestedDirectory) {
    $candidates = @()
    if ($RequestedDirectory) {
        $runtime = Get-GameRuntime $RequestedDirectory
        if ($runtime) { $candidates = @($runtime) } else { Write-Host 'Queen''s Domain was not found at the supplied path.' }
    } else { $candidates = @(Find-GameInstallations) }
    while ($true) {
        $runtime = $null
        if ($candidates.Count -eq 1) { $runtime = $candidates[0] }
        elseif ($candidates.Count -gt 1) {
            Write-Host 'Found multiple installations:'
            for ($i=0; $i -lt $candidates.Count; $i++) { Write-Host ("{0}. {1}" -f ($i+1),$candidates[$i]) }
            $choice = Read-Host 'Choose an installation number, or press Enter to enter a path'
            $number = 0
            if ([int]::TryParse($choice,[ref]$number) -and $number -ge 1 -and $number -le $candidates.Count) { $runtime = $candidates[$number-1] }
            elseif ($choice) { Write-Host 'Invalid selection.'; continue }
        }
        if ($runtime) {
            $location = [IO.Path]::GetFullPath((Join-Path $runtime '..\..\..'))
            Write-Host "`nFound Queen's Domain: $location"
            Write-Host "Install location: $runtime"
            if (Confirm-Action 'Install Hatchling''s Weapon Wheel here?') { return $runtime }
        }
        $path = Read-Host 'Enter the game folder or executable path, or press Enter to cancel'
        if ([string]::IsNullOrWhiteSpace($path)) { return }
        $runtime = Get-GameRuntime $path
        if ($runtime) { $candidates = @($runtime) }
        else { Write-Host 'Queen''s Domain was not found there.'; $candidates = @() }
    }
}

function Assert-GameClosed {
    if (Get-Process -Name 'QueensDomain','QueensDomain-Win64-Shipping' -ErrorAction SilentlyContinue) {
        throw 'Close Queen''s Domain, then run the installer again.'
    }
}

function Get-LoaderRoot([string]$Runtime) {
    foreach ($root in @((Join-Path $Runtime 'ue4ss'),$Runtime)) {
        if (Test-Path -LiteralPath (Join-Path $root 'UE4SS.dll') -PathType Leaf) { return $root }
    }
}

function Get-BackupDirectory {
    if (!$script:BackupDirectory) {
        $root = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'QueensDomain\Saved\WeaponWheel\install-backups'))
        $name = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
        $script:BackupDirectory = Join-Path $root $name
        New-Item -ItemType Directory -Path $script:BackupDirectory -Force | Out-Null
    }
    return $script:BackupDirectory
}

function Install-Loader([string]$Runtime) {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $work = Join-Path $tempRoot ('HatchlingsWeaponWheel-'+[guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $work | Out-Null
        $zip = Join-Path $work 'UE4SS.zip'
        $expanded = Join-Path $work 'expanded'
        Write-Host 'Downloading UE4SS 4.0.0...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $script:LoaderUrl -OutFile $zip -UseBasicParsing
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $script:LoaderHash) { throw 'UE4SS download verification failed. No loader files were installed.' }
        Expand-Archive -LiteralPath $zip -DestinationPath $expanded
        $payload = Join-Path $expanded 'ue4ss'
        if (!(Test-Path -LiteralPath (Join-Path $payload 'UE4SS.dll') -PathType Leaf) -or !(Test-Path -LiteralPath (Join-Path $expanded 'dwmapi.dll') -PathType Leaf)) {
            throw 'The UE4SS archive does not contain the expected files.'
        }
        Assert-GameClosed
        $proxy = Join-Path $Runtime 'dwmapi.dll'
        if (Test-Path -LiteralPath $proxy) { Copy-Item -LiteralPath $proxy -Destination (Join-Path (Get-BackupDirectory) 'dwmapi.dll') }
        $loaderRoot = Join-Path $Runtime 'ue4ss'
        $hadModList = Test-Path -LiteralPath (Join-Path $loaderRoot 'Mods\mods.txt')
        foreach ($file in Get-ChildItem -LiteralPath $payload -File -Recurse) {
            $relative = $file.FullName.Substring($payload.Length).TrimStart('\')
            $target = Join-Path $loaderRoot $relative
            if (Test-Path -LiteralPath $target) { continue }
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
        if (!$hadModList) { [IO.File]::WriteAllText((Join-Path $loaderRoot 'Mods\mods.txt'),'') }
        Copy-Item -LiteralPath (Join-Path $expanded 'dwmapi.dll') -Destination $proxy -Force
        Write-Host "UE4SS installed in $loaderRoot"
        return $loaderRoot
    } finally {
        if (Test-Path -LiteralPath $work) {
            $resolved = (Resolve-Path -LiteralPath $work).Path
            if (![string]::Equals($resolved,[IO.Path]::GetFullPath($work),[StringComparison]::OrdinalIgnoreCase) -or ![string]::Equals([IO.Path]::GetDirectoryName($resolved),$tempRoot,[StringComparison]::OrdinalIgnoreCase)) {
                throw 'Unexpected temporary directory; cleanup was skipped.'
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

function Install-Wheel([string]$LoaderRoot) {
    Assert-GameClosed
    $modRoot = Join-Path $LoaderRoot 'Mods'
    New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
    $modRoot = (Resolve-Path -LiteralPath $modRoot).Path
    foreach ($name in @('QueensWeaponWheel','HatchlingsWeaponWheel')) {
        $existing = Join-Path $modRoot $name
        if (!(Test-Path -LiteralPath $existing)) { continue }
        $resolved = (Resolve-Path -LiteralPath $existing).Path
        $expected = [IO.Path]::GetFullPath((Join-Path $modRoot $name))
        if (![string]::Equals($resolved,$expected,[StringComparison]::OrdinalIgnoreCase) -or ((Get-Item -LiteralPath $resolved).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Unexpected mod path; no files were moved.'
        }
        $backup = [IO.Path]::GetFullPath((Get-BackupDirectory))
        $backupRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'QueensDomain\Saved\WeaponWheel\install-backups')).TrimEnd('\')+'\'
        if (!$backup.StartsWith($backupRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected backup path; no files were moved.' }
        if ($name -eq 'QueensWeaponWheel') { Move-Item -LiteralPath $resolved -Destination $backup }
        else { Copy-Item -LiteralPath $resolved -Destination $backup -Recurse }
    }
    $target = Join-Path $modRoot 'HatchlingsWeaponWheel'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Get-ChildItem -LiteralPath $script:ModSource -Force | Copy-Item -Destination $target -Recurse -Force
    [IO.File]::WriteAllText((Join-Path $target 'enabled.txt'),'')
    $mods = Join-Path $modRoot 'mods.txt'
    $lines = if (Test-Path -LiteralPath $mods) { @(Get-Content -LiteralPath $mods) } else { @() }
    $lines = @($lines | Where-Object { $_ -notmatch '^\s*(QueensWeaponWheel|HatchlingsWeaponWheel)\s*:' })
    $lines += 'HatchlingsWeaponWheel : 1'
    [IO.File]::WriteAllLines($mods,[string[]]$lines)
}

function Invoke-Installation([string]$RequestedDirectory) {
    $script:BackupDirectory = $null
    Write-Host "Hatchling's Weapon Wheel installer`n"
    if (!(Test-Path -LiteralPath (Join-Path $script:ModSource 'Scripts\main.lua') -PathType Leaf)) {
        throw 'Mod files are missing. Extract the entire release ZIP before running Install.cmd.'
    }
    Assert-GameClosed
    $runtime = Select-GameRuntime $RequestedDirectory
    if (!$runtime) { Write-Host 'Installation cancelled.'; return }
    Assert-GameClosed
    $loaderRoot = Get-LoaderRoot $runtime
    if (!$loaderRoot) {
        Write-Host "`nUE4SS was not found in the game installation. This mod requires it."
        if (!(Confirm-Action 'Download and install UE4SS 4.0.0?')) { Write-Host 'Installation cancelled. No mod files were installed.'; return }
        $loaderRoot = Install-Loader $runtime
    } else { Write-Host "UE4SS found in $loaderRoot. Keeping the existing installation." }
    Install-Wheel $loaderRoot
    Write-Host "`nHatchling's Weapon Wheel was installed successfully."
    Write-Host "Location: $(Join-Path $loaderRoot 'Mods\HatchlingsWeaponWheel')"
    if ($script:BackupDirectory) { Write-Host "Previous files were backed up to $script:BackupDirectory" }
    Write-Host 'Start the game. Hold Alt to select a weapon; press F10 to customize the wheel.'
}

function Wait-ForInstallerExit {
    if ($NoPause) { return }
    Write-Host "`nPress any key to close..."
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
    catch { $null = Read-Host 'Press Enter to close' }
}

if ($MyInvocation.InvocationName -ne '.') {
    $resultCode = 0
    try { Invoke-Installation $GameDirectory }
    catch {
        Write-Host "`nInstallation failed: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception -is [UnauthorizedAccessException]) { Write-Host 'Try running Install.cmd as administrator if the game folder requires it.' }
        $resultCode = 1
    } finally { Wait-ForInstallerExit }
    exit $resultCode
}
