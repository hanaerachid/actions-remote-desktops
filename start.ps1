# net config server /hidden:yes /srvcomment:"Windows Server" > out.txt 2 >&1
# net user brooke Jacobs123 /add /active:yes /logonpasswordchg:no > nul
$username = "brooke"
$Password = ConvertTo-SecureString "Jacobs123" -AsPlainText -Force
New-LocalUser -Name $username -Password $Password -PasswordNeverExpires:$true -UserMayNotChangePassword:$true -AccountNeverExpires:$true
# Enable-LocalUser -Name "brooke"

# net localgroup Administrators brooke /add > nul
Add-LocalGroupMember -Group "Administrators" -Member "brooke"

# Get the user's SID
$sid = (Get-LocalUser -Name $username).SID.Value

# Load the Windows API
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class UserProfile {
    [DllImport("userenv.dll", CharSet = CharSet.Unicode,
        SetLastError = true)]
    public static extern int CreateProfile(
        string pszUserSid,
        string pszUserName,
        StringBuilder pszProfilePath,
        uint cchProfilePath
    );
}
"@

# Create the user profile
$profilePath = New-Object System.Text.StringBuilder 260

$result = [UserProfile]::CreateProfile(
    $sid,
    $username,
    $profilePath,
    260
)

if ($result -ne 0) {
    throw "Failed to create user profile. HRESULT: $result"
}

Write-Host "Profile created at: $($profilePath.ToString())"

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
