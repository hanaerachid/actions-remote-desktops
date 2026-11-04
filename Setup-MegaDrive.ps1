[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MegaEmail,

    [Parameter(Mandatory = $true)]
    [string]$MegaPassword,

    [Parameter()]
    [ValidatePattern('^[A-Za-z]$')]
    [string]$DriveLetter = 'X',

    [Parameter()]
    [string[]]$TargetFolders = @(),

    [Parameter()]
    [string]$TargetFolder,

    [Parameter()]
    [switch]$ReplaceEmptyFolders
)

$ErrorActionPreference = 'Stop'

# ============================================================
# CONFIGURATION
# ============================================================

$DriveLetter = $DriveLetter.TrimEnd(':').ToUpperInvariant()

if ($TargetFolder) {
    if ($TargetFolders.Count -gt 0) {
        throw 'Specify either TargetFolder or TargetFolders, not both.'
    }

    $TargetFolders = @($TargetFolder)
}

$MegaInstallPath = Join-Path $env:LOCALAPPDATA 'MEGAcmd'
$InstallerPath = Join-Path $env:TEMP 'MEGAcmdSetup64.exe'
$WebDavUrl = $null

# ============================================================
# HELPERS
# ============================================================

function Write-Step {
    param([string]$Message)

    Write-Host "[+] $Message" -ForegroundColor Cyan
}

function Stop-WithError {
    param([string]$Message)

    throw $Message
}

function Invoke-Mega {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$Arguments = @()
    )

    $PreviousPreference = $ErrorActionPreference

    try {
        # Native command output should not automatically terminate
        # the PowerShell script.
        $ErrorActionPreference = 'Continue'

        $Output = @(& $Command @Arguments 2>&1)

        $ExitCode = $LASTEXITCODE

        if ($ExitCode -ne 0) {
            $Message = $Output | ForEach-Object {
                $_.ToString()
            }

            throw "$Command failed with exit code $ExitCode. $($Message -join ' ')"
        }

        return $Output
    }
    finally {
        $ErrorActionPreference = $PreviousPreference
    }
}

# ============================================================
# 1. INSTALL MEGACMD IF NECESSARY
# ============================================================

Write-Step 'Checking MEGAcmd installation...'

$MegaLogin = Get-Command mega-login -ErrorAction SilentlyContinue

if (-not $MegaLogin) {

    if (Test-Path (Join-Path $MegaInstallPath 'mega-login.bat')) {
        $env:PATH += ";$MegaInstallPath"
    }
}

$MegaLogin = Get-Command mega-login -ErrorAction SilentlyContinue

if (-not $MegaLogin) {

    $Chocolatey = Get-Command choco -ErrorAction SilentlyContinue

    if ($Chocolatey) {

        Write-Step 'Installing MEGAcmd through Chocolatey...'

        & choco install megacmd -y --no-progress

        if ($LASTEXITCODE -ne 0) {
            Stop-WithError 'Chocolatey failed to install MEGAcmd.'
        }

    }
    else {

        Write-Step 'Chocolatey unavailable. Downloading official MEGAcmd installer...'

        Invoke-WebRequest `
            -Uri 'https://mega.nz/MEGAcmdSetup64.exe' `
            -OutFile $InstallerPath

        Start-Process `
            -FilePath $InstallerPath `
            -ArgumentList '/S' `
            -Wait `
            -NoNewWindow

        Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
    }

    $env:PATH += ";$MegaInstallPath"

    $MegaLogin = Get-Command mega-login -ErrorAction SilentlyContinue

    if (-not $MegaLogin) {
        Stop-WithError 'MEGAcmd installation completed, but mega-login could not be found.'
    }
}

Write-Step 'MEGAcmd is installed.'

# ============================================================
# 2. START MEGACMD SERVER
# ============================================================

Write-Step 'Starting MEGAcmd server...'

$ServerProcess = Get-Process MEGAcmdServer -ErrorAction SilentlyContinue

if (-not $ServerProcess) {

    $ServerExe = Join-Path $MegaInstallPath 'MEGAcmdServer.exe'

    if (-not (Test-Path $ServerExe)) {
        Stop-WithError "MEGAcmdServer.exe not found at $ServerExe"
    }

    Start-Process -FilePath $ServerExe -WindowStyle Hidden
}

# Wait for the server to become available.

$ServerReady = $false

for ($i = 0; $i -lt 20; $i++) {

    Start-Sleep -Seconds 1

    if (Get-Process MEGAcmdServer -ErrorAction SilentlyContinue) {
        $ServerReady = $true
        break
    }
}

if (-not $ServerReady) {
    Stop-WithError 'MEGAcmd server failed to start.'
}

# ============================================================
# 3. AUTHENTICATE
# ============================================================

Write-Step "Authenticating as $MegaEmail..."

# Do not write the password or command arguments to the log.

Write-Step 'Authenticating with MEGA...'

try {
    Invoke-Mega -Command 'mega-login' -Arguments @(
        $MegaEmail,
        $MegaPassword
    ) | Out-Null

    Write-Step 'Authentication command completed.'
}
catch {
    Write-Host "MEGA authentication failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Step 'MEGA authentication completed.'

# ============================================================
# 4. START WEBDAV
# ============================================================

Write-Step 'Starting MEGA WebDAV server...'

$WebDavOutput = Invoke-Mega -Command 'mega-webdav' -Arguments @('/')

$WebDavText = $WebDavOutput -join "`n"

$Match = [regex]::Match(
    $WebDavText,
    'https?://127\.0\.0\.1:\d+/[A-Za-z0-9_-]+'
)

if (-not $Match.Success) {
    Stop-WithError "Unable to determine MEGA WebDAV URL. Output: $WebDavText"
}

$WebDavUrl = $Match.Value

Write-Step "WebDAV endpoint: $WebDavUrl"

# ============================================================
# 5. MAP NETWORK DRIVE
# ============================================================

$DrivePath = "${DriveLetter}:"

Write-Step "Mapping MEGA to $DrivePath..."

$ExistingDrive = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue

if ($ExistingDrive) {
    Write-Step "$DrivePath already exists. Removing existing mapping..."

    $Network = New-Object -ComObject WScript.Network

    try {
        $Network.RemoveNetworkDrive($DrivePath, $true, $true)
    }
    catch {
        Write-Warning "Could not remove existing drive mapping: $_"
    }
}

$Network = New-Object -ComObject WScript.Network

$Network.MapNetworkDrive(
    $DrivePath,
    $WebDavUrl,
    $false
)

Start-Sleep -Seconds 3

if (-not (Test-Path $DrivePath)) {
    Stop-WithError "Drive mapping failed: $DrivePath"
}

Write-Step "MEGA successfully mapped to $DrivePath"

# ============================================================
# 6. CREATE TARGET FOLDERS AND SYMBOLIC LINKS
# ============================================================

if ($TargetFolders.Count -gt 0) {

    Write-Step 'Processing target folders...'

    foreach ($Folder in $TargetFolders) {

        # Only accept simple folder names.
        if (
            [string]::IsNullOrWhiteSpace($Folder) -or
            $Folder -match '[\\/]' -or
            $Folder -match '^[A-Za-z]:' -or
            $Folder -in @('.', '..')
        ) {
            Stop-WithError "Invalid target folder name: $Folder"
        }

        $LocalPath = Join-Path $env:USERPROFILE $Folder

        $CloudRoot = Join-Path $DrivePath 'EphemeralBackup'
        $CloudPath = Join-Path $CloudRoot $Folder

        Write-Step "Processing $Folder..."

        # Create the remote directory structure.

        if (-not (Test-Path $CloudRoot)) {
            New-Item -ItemType Directory -Path $CloudRoot -Force |
                Out-Null
        }

        if (-not (Test-Path $CloudPath)) {
            New-Item -ItemType Directory -Path $CloudPath -Force |
                Out-Null
        }

        # Do not overwrite an existing link.

        if (Test-Path $LocalPath) {

            $Item = Get-Item -LiteralPath $LocalPath -Force

            if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) {

                Write-Warning "Skipping existing symbolic link/junction: $LocalPath"
                continue
            }

            $Contents = @(Get-ChildItem -LiteralPath $LocalPath -Force)

            if ($Contents.Count -gt 0) {
                Stop-WithError @"
Folder is not empty: $LocalPath
Refusing to delete existing data.
Move the contents manually or back them up before retrying.
"@
            }

            if (-not $ReplaceEmptyFolders) {
                Stop-WithError @"
Folder already exists: $LocalPath
Use -ReplaceEmptyFolders to allow removal of empty directories.
"@
            }

            Remove-Item -LiteralPath $LocalPath -Force
        }

        # Create a directory symbolic link.
        # Unlike /J, /D supports targets on network drives.

        Write-Step "Creating link: $LocalPath -> $CloudPath"

        & cmd.exe /c mklink /D "`"$LocalPath`"" "`"$CloudPath`""

        if ($LASTEXITCODE -ne 0) {
            Stop-WithError "Failed to create symbolic link for $Folder"
        }

        Write-Host "[OK] $LocalPath -> $CloudPath" -ForegroundColor Green
    }
}

# ============================================================
# 7. COMPLETE
# ============================================================

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
Write-Host ' MEGA SETUP COMPLETED SUCCESSFULLY' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Green

Write-Host "Drive: $DrivePath"
Write-Host "WebDAV: $WebDavUrl"

if ($TargetFolders.Count -gt 0) {
    Write-Host "Linked folders: $($TargetFolders -join ', ')"
}

exit 0
