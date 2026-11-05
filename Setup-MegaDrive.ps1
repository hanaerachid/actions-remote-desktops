# ============================================================
# 1. INSTALL MEGACMD IF NECESSARY
# ============================================================

Write-Step 'Checking MEGAcmd installation...'

$MegaInstallPath = Join-Path $env:LOCALAPPDATA 'MEGAcmd'
$MegaServerExe = Join-Path $MegaInstallPath 'MEGAcmdServer.exe'
$InstallerPath = Join-Path $env:TEMP 'MEGAcmdSetup64.exe'

if (-not (Test-Path $MegaServerExe)) {

    Write-Step 'MEGAcmd not found. Installing...'

    # Download official installer
    Invoke-WebRequest `
        -Uri 'https://mega.nz/MEGAcmdSetup64.exe' `
        -OutFile $InstallerPath

    if (-not (Test-Path $InstallerPath)) {
        throw 'Failed to download MEGAcmd installer.'
    }

    # Silent installation
    $InstallProcess = Start-Process `
        -FilePath $InstallerPath `
        -ArgumentList '/S' `
        -Wait `
        -PassThru

    if ($InstallProcess.ExitCode -ne 0) {
        throw "MEGAcmd installation failed: $($InstallProcess.ExitCode)"
    }

    Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue

    # Verify installation
    if (-not (Test-Path $MegaServerExe)) {
        throw "MEGAcmd installation completed but server was not found: $MegaServerExe"
    }

    Write-Step 'MEGAcmd installed successfully.'
}
else {
    Write-Step 'MEGAcmd is already installed.'
}

# Add MEGAcmd to PATH
$env:PATH = "$MegaInstallPath;$env:PATH"

# Verify client command availability
if (-not (Test-Path (Join-Path $MegaInstallPath 'mega-login.bat'))) {
    throw 'MEGAcmd client commands are missing.'
}

Write-Step 'MEGAcmd installation verified.'
