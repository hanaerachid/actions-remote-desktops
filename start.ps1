# net config server /hidden:yes /srvcomment:"Windows Server" > out.txt 2 >&1
# net user brooke Jacobs123 /add /active:yes /logonpasswordchg:no > nul
$Password = ConvertTo-SecureString "Jacobs123" -AsPlainText -Force
New-LocalUser -Name "brooke" -Password $Password -PasswordNeverExpires:$true -UserMayNotChangePassword:$true -AccountNeverExpires:$true
# Enable-LocalUser -Name "brooke"

# net localgroup Administrators brooke /add > nul
Add-LocalGroupMember -Group "Administrators" -Member "brooke"

# diskperf -y > nul
# Enable-DiskPerf -DriveLetter * -Counters * -Force

# sc config audiosrv start= auto > nul
Set-Service -Name "audiosrv" -StartupType Automatic

# sc start audiosrv > nul
Start-Service -Name "audiosrv"

# icacls C:\Windows\Temp /grant brooke:F > nul
# Add-Acl -Path "C:\Windows\Temp" -Account "brooke" -AccessRights "FullControl"
# icacls C:\Windows\installer /grant brooke:F > nul
# Add-Acl -Path "C:\Windows\installer" -Account "brooke" -AccessRights "FullControl"

# if (Get-Process ngrok -ErrorAction SilentlyContinue) {
#     $response = Invoke-WebRequest -Uri "http://localhost:4040/api/tunnels" -Method GET -UseBasicParsing
#     $responseJson = $response.Content | ConvertFrom-Json
#     $responseJson.tunnels[0].public_url
# } else {
#     "Failed to retreive NGROK authtoken - check again your authtoken"
# }

# Test-Connection -Count 10 -ComputerName "127.0.0.1"
