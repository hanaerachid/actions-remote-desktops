while ($true) {
    Write-Host "Starting SSH tunnel..."

    ssh -o StrictHostKeyChecking=accept-new `
       -o ServerAliveInterval=30 `
       -o ServerAliveCountMax=3 `
       -p 27550 `
       -R 3389:localhost:3389 `
       admin@mainline.proxy.rlwy.net

    Write-Host "SSH stopped. Restarting in 3 seconds..."
    Start-Sleep -Seconds 3
}
