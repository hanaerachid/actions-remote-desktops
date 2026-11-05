<#
.SYNOPSIS
  Mounts a Mega folder (rclone + WinFsp) and maps user-profile folders onto it
  with symlinks, so their content persists across GitHub-hosted runners.

.EXAMPLE
  ./mega-persist.ps1 -Action Start -UserName runneradmin -Folders Desktop,Documents,Downloads
  ./mega-persist.ps1 -Action Stop  -UserName runneradmin
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Start', 'Stop')]
    [string]$Action,

    # Credentials: pass explicitly or let them default to the environment
    [string]$Email    = $env:MEGA_EMAIL,
    [string]$Password = $env:MEGA_PASSWORD,

    # User whose profile folders are mapped (default: the user running the step)
    [string]$UserName = $env:USERNAME,

    # Folders relative to that user's profile
    [string[]]$Folders = @('Desktop', 'Documents', 'Downloads'),

    # Root folder on Mega; data goes to <RemoteRoot>/<UserName>/<Folder>
    [string]$RemoteRoot = 'GitHubRunnerPersist',

    # Use a different drive letter and RC port for each mount in the same job
    [string]$DriveLetter = 'M:',
    [int]$RcPort = 5572,

    [string]$CacheMaxSize = '8G',
    [int]$FlushTimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) { Write-Host "==> $Message" }

$UserKey   = $UserName -replace '[^\w\.-]', '_'
$Drive     = ($DriveLetter.TrimEnd(':').ToUpper()) + ':'
$TempRoot  = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$StateFile = Join-Path $TempRoot "mega-persist-$UserKey.json"
$LogFile   = Join-Path $TempRoot "mega-persist-$UserKey.log"
$RcUrl     = "http://127.0.0.1:$RcPort"

function Show-LogTail {
    if (Test-Path $LogFile) {
        Write-Host '--- rclone log (tail) ---'
        Get-Content $LogFile -Tail 40 | ForEach-Object { Write-Host $_ }
        Write-Host '-------------------------'
    }
}

function Resolve-UserProfile([string]$User) {
    try {
        $sid = (New-Object Security.Principal.NTAccount($User)).Translate(
            [Security.Principal.SecurityIdentifier]).Value
        $p = Get-CimInstance Win32_UserProfile -Filter "SID='$sid'" -ErrorAction Stop
        if ($p -and $p.LocalPath -and (Test-Path -LiteralPath $p.LocalPath)) { return $p.LocalPath }
    } catch { }
    $fallback = Join-Path "$env:SystemDrive\Users" $User
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    throw "Profile for user '$User' not found (has the user ever logged on / been created?)."
}

function Install-Prerequisites {
    $codes = @(0, 1641, 3010)   # success / reboot-pending codes

    $winfspPresent = (Test-Path "${env:ProgramFiles(x86)}\WinFsp") -or (Test-Path "$env:ProgramFiles\WinFsp")
    if (-not $winfspPresent) {
        Write-Step 'Installing WinFsp...'
        choco install winfsp -y --no-progress | Out-Host
        if ($codes -notcontains $LASTEXITCODE) { throw "WinFsp install failed ($LASTEXITCODE)." }
    }

    if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
        Write-Step 'Installing rclone...'
        choco install rclone -y --no-progress | Out-Host
        if ($codes -notcontains $LASTEXITCODE) { throw "rclone install failed ($LASTEXITCODE)." }
        $env:PATH = "$env:ChocolateyInstall\bin;$env:PATH"
        if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) { throw 'rclone not found on PATH after install.' }
    }
    $global:LASTEXITCODE = 0
    Write-Step ((& rclone version | Select-Object -First 1))
}

function Save-State($State) {
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Stop-Persistence {
    if (-not (Test-Path -LiteralPath $StateFile)) {
        Write-Warning "No state file for '$UserName' ($StateFile); nothing to stop."
        return $true
    }
    $st = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
    $ok = $true

    # 1. Wait until every pending upload has reached Mega
    Write-Step 'Waiting for pending uploads to finish...'
    $deadline = (Get-Date).AddMinutes($FlushTimeoutMinutes)
    Start-Sleep -Seconds 2
    while ($true) {
        $raw = & rclone rc --url $st.rcUrl vfs/queue 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'Could not query the upload queue (mount already gone?).'
            $global:LASTEXITCODE = 0
            break
        }
        $queue = @((($raw -join "`n") | ConvertFrom-Json).queue)
        if ($queue.Count -eq 0) { Write-Step 'All uploads finished.'; break }
        if ((Get-Date) -gt $deadline) {
            Write-Warning "Timed out with $($queue.Count) upload(s) still pending."
            $ok = $false
            break
        }
        Write-Step "$($queue.Count) upload(s) pending..."
        Start-Sleep -Seconds 5
    }

    # 2. Remove symlinks (never recursive) and put the original folders back
    foreach ($l in @($st.links)) {
        try {
            $item   = Get-Item -LiteralPath $l.link -Force -ErrorAction SilentlyContinue
            $isLink = $item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
            if ($item -and -not $isLink) {
                Write-Warning "$($l.link) is not a link; leaving it untouched."
                continue
            }
            if ($isLink) { [IO.Directory]::Delete($l.link) }   # removes only the link
            if ($l.original -and (Test-Path -LiteralPath $l.original)) {
                Move-Item -LiteralPath $l.original -Destination $l.link
                Write-Step "Restored original $($l.link)"
            }
        } catch {
            Write-Warning "Failed to unmap $($l.link): $_"
            $ok = $false
        }
    }

    # 3. Unmount cleanly; kill only as a last resort
    Write-Step 'Unmounting Mega...'
    & rclone rc --url $st.rcUrl mount/unmount "mountPoint=$($st.drive)" | Out-Null
    $global:LASTEXITCODE = 0
    $p = Get-Process -Id $st.pid -ErrorAction SilentlyContinue
    if ($p -and -not $p.WaitForExit($FlushTimeoutMinutes * 60 * 1000)) {
        Write-Warning 'rclone did not exit in time; killing it.'
        taskkill /PID $st.pid /T /F | Out-Null
        $global:LASTEXITCODE = 0
        $ok = $false
    }

    Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
    Show-LogTail
    return $ok
}

# ============================================================
if ($Action -eq 'Stop') {
    if (Stop-Persistence) { Write-Step 'Stop completed.'; exit 0 }
    Write-Error 'Stop finished with problems (see warnings above).'
    exit 1
}

# ---------------------------- START ---------------------------
if (-not $Email -or -not $Password) { throw 'Email/Password missing (-Email/-Password or MEGA_EMAIL/MEGA_PASSWORD).' }
if (Test-Path -LiteralPath $StateFile) { throw "Already started for '$UserName' ($StateFile exists)." }
if (Test-Path "$Drive\") { throw "Drive $Drive is already in use; pass another -DriveLetter." }

$profilePath = Resolve-UserProfile $UserName
Write-Step "Profile of '$UserName': $profilePath"

$relFolders = foreach ($f in $Folders) {
    if ([IO.Path]::IsPathRooted($f) -or $f -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Folder '$f' must be a plain path relative to the user profile."
    }
    $f.Trim('\', '/') -replace '/', '\'
}

Install-Prerequisites

$Email    = $Email.Trim()
$Password = $Password.Trim()
$obscured = (& rclone obscure -- $Password) | Select-Object -First 1
if ($LASTEXITCODE -ne 0 -or -not $obscured) { throw 'rclone obscure failed.' }
Write-Host "::add-mask::$obscured"
Write-Host "::add-mask::$Password"
$env:RCLONE_CONFIG           = Join-Path $TempRoot 'rclone.conf'
$env:RCLONE_CONFIG_MEGA_TYPE = 'mega'
$env:RCLONE_CONFIG_MEGA_USER = $Email
$env:RCLONE_CONFIG_MEGA_PASS = $obscured

$remote = "mega:$RemoteRoot/$UserKey"
Write-Step "Ensuring $remote exists..."
& rclone mkdir $remote
if ($LASTEXITCODE -ne 0) { throw 'Could not reach/log in to Mega (check credentials).' }

Write-Step "Mounting $remote on $Drive ..."
$mountArgs = @(
    'mount', $remote, $Drive,
    '--vfs-cache-mode', 'full',
    '--vfs-write-back', '5s',
    '--vfs-cache-max-size', $CacheMaxSize,
    '--cache-dir', (Join-Path $TempRoot "rclone-cache-$UserKey"),
    '--volname', 'Mega',
    '--rc', '--rc-addr', "127.0.0.1:$RcPort", '--rc-no-auth',
    '--log-file', $LogFile, '--log-level', 'INFO',
    '--no-console'
)
$argString = ($mountArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
$proc = Start-Process -FilePath (Get-Command rclone).Source -ArgumentList $argString `
                      -PassThru -WindowStyle Hidden

$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    if ($proc.HasExited) { Show-LogTail; throw "rclone mount exited early (code $($proc.ExitCode))." }
    if (Test-Path "$Drive\") { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) {
    taskkill /PID $proc.Id /T /F | Out-Null
    Show-LogTail
    throw "Mount did not become ready within 90s."
}
Write-Step "Mount ready on $Drive"

$state = [ordered]@{
    pid   = $proc.Id
    drive = $Drive
    rcUrl = $RcUrl
    user  = $UserName
    links = @()
}
Save-State $state

try {
    foreach ($rel in $relFolders) {
        $link   = Join-Path $profilePath $rel
        $target = Join-Path "$Drive\" $rel
        New-Item -ItemType Directory -Path $target -Force | Out-Null

        $original = $null
        if (Test-Path -LiteralPath $link) {
            $item = Get-Item -LiteralPath $link -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$link is already a link/junction; refusing to touch it."
            }
            $original = "$link.runner-original"
            if (Test-Path -LiteralPath $original) {
                $original = "$link.runner-original-$(Get-Date -Format yyyyMMddHHmmss)"
            }
            Write-Step "Moving existing $link aside..."
            Move-Item -LiteralPath $link -Destination $original

            # Merge runner's original content into Mega WITHOUT overwriting anything
            # already persisted (/XC /XN /XO = skip files that exist at the destination)
            Write-Step "Merging original content of $rel into Mega (no overwrite)..."
            robocopy $original $target /E /XJ /XC /XN /XO /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
            $rc = $LASTEXITCODE
            $global:LASTEXITCODE = 0
            if ($rc -ge 8) {
                Move-Item -LiteralPath $original -Destination $link   # roll back this folder
                throw "robocopy failed for $rel (exit $rc)."
            }
        }
        else {
            New-Item -ItemType Directory -Path (Split-Path $link -Parent) -Force | Out-Null
        }

        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        } catch {
            if ($original) { Move-Item -LiteralPath $original -Destination $link }
            throw
        }

        $state.links += [pscustomobject]@{ link = $link; original = $original; target = $target }
        Save-State $state
        Write-Step "$link  ->  $target"
    }
}
catch {
    Write-Warning "Mapping failed: $_ -- rolling back."
    Stop-Persistence | Out-Null
    throw
}

Write-Step 'Start completed.'
exit 0