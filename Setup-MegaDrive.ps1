[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MegaEmail,

    [Parameter(Mandatory = $true)]
    [string]$MegaPassword,

    [Parameter()]
    [string]$SourceRoot = $env:USERPROFILE,

    [Parameter()]
    [string[]]$TargetFolders = @(
        'Desktop',
        'Documents',
        'Downloads'
    ),

    [Parameter()]
    [string]$RemoteRoot = '/WindowsServer-Backups'
)

$ErrorActionPreference = 'Stop'

# ============================================================
# CONFIGURATION
# ============================================================

$MegaInstallPath = Join-Path $env:LOCALAPPDATA 'MEGAcmd'
$MegaServerExe = Join-Path $MegaInstallPath 'MEGAcmdServer.exe'

# ============================================================
# HELPERS
# ============================================================

function Write-Step {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Cyan
}

function Invoke-Mega {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$Arguments = @()
    )

    $CommandPath = Join-Path $MegaInstallPath "$Command.bat"

    if (-not (Test-Path $CommandPath)) {
        $Found = Get-Command $Command -ErrorAction SilentlyContinue

        if (-not $Found) {
            throw "MEGA command not found: $Command"
        }

        $CommandPath = $Found.Source
    }

    $PreviousPreference = $ErrorActionPreference

    try {
        $ErrorActionPreference = 'Continue'

        $Output = @(& $CommandPath @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE

        if ($ExitCode -ne 0) {
            $Message = $Output | ForEach-Object {
                $_.ToString()
            }

            throw "$Command failed (exit $ExitCode): $($Message -join ' ')"
        }

        return $Output
    }
    finally {
        $ErrorActionPreference = $PreviousPreference
    }
}

# ============================================================
# 1. VALIDATE INSTALLATION
# ============================================================

Write-Step 'Checking MEGAcmd installation...'

if (-not (Test-Path $MegaServerExe)) {
    throw "MEGAcmd server not found: $MegaServerExe. Install MEGAcmd first."
}

if (-not (Test-Path $SourceRoot -PathType Container)) {
    throw "Source profile does not exist: $SourceRoot"
}

# ============================================================
# 2. START MEGACMD SERVER
# ============================================================

Write-Step 'Starting MEGAcmd server...'

$ServerProcess = Get-Process MEGAcmdServer -ErrorAction SilentlyContinue

if (-not $ServerProcess) {
    Start-Process -FilePath $MegaServerExe -WindowStyle Hidden
    Start-Sleep -Seconds 5
}

if (-not (Get-Process MEGAcmdServer -ErrorAction SilentlyContinue)) {
    throw 'MEGAcmd server failed to start.'
}

# ============================================================
# 3. AUTHENTICATE
# ============================================================

Write-Step 'Checking MEGA authentication...'

$LoggedIn = $false

try {
    Invoke-Mega -Command 'mega-whoami' | Out-Null
    $LoggedIn = $true
}
catch {
    Write-Step 'No active MEGA session. Logging in...'
}

if (-not $LoggedIn) {
    Invoke-Mega -Command 'mega-login' -Arguments @(
        $MegaEmail,
        $MegaPassword
    ) | Out-Null
}

Write-Step 'MEGA authentication successful.'

# ============================================================
# 4. CREATE REMOTE ROOT
# ============================================================

Write-Step "Creating remote root: $RemoteRoot"

Invoke-Mega -Command 'mega-mkdir' -Arguments @(
    '-p',
    $RemoteRoot
) | Out-Null

# ============================================================
# 5. REGISTER SYNCHRONIZATIONS
# ============================================================

Write-Step 'Checking existing synchronizations...'

$ExistingSyncs = (
    Invoke-Mega -Command 'mega-sync' -Arguments @(
        '--output-cols=LOCALPATH'
    )
) -join "`n"

foreach ($Folder in $TargetFolders) {

    # Only permit simple folder names.
    if (
        [string]::IsNullOrWhiteSpace($Folder) -or
        $Folder -match '[\\/]' -or
        $Folder -in @('.', '..')
    ) {
        throw "Invalid target folder: $Folder"
    }

    $LocalPath = Join-Path $SourceRoot $Folder
    $RemotePath = "$RemoteRoot/$Folder"

    if (-not (Test-Path $LocalPath -PathType Container)) {
        Write-Warning "Skipping missing folder: $LocalPath"
        continue
    }

    Write-Step "Processing $Folder..."

    # Avoid duplicate synchronization configurations.
    if ($ExistingSyncs -match [regex]::Escape($LocalPath)) {
        Write-Step "Synchronization already configured: $LocalPath"
        continue
    }

    Write-Step "Registering: $LocalPath -> $RemotePath"

    Invoke-Mega -Command 'mega-sync' -Arguments @(
        $LocalPath,
        $RemotePath
    ) | Out-Null

    Write-Host "[OK] Synchronization registered: $Folder" `
        -ForegroundColor Green
}

# ============================================================
# 6. VERIFY
# ============================================================

Write-Step 'Current MEGA synchronizations:'

Invoke-Mega -Command 'mega-sync' | ForEach-Object {
    Write-Host $_
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
Write-Host ' MEGA SYNC CONFIGURATION COMPLETED' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Green

Write-Host "Windows profile: $SourceRoot"
Write-Host "MEGA destination: $RemoteRoot"
Write-Host 'MEGAcmd server remains running.'
