param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$SshArgs
)

while ($true) {
    Write-Host "Starting SSH: ssh $SshArgs"

    & ssh @SshArgs

    Write-Host "SSH exited. Restarting in 3 seconds..."
    Start-Sleep -Seconds 3
}
