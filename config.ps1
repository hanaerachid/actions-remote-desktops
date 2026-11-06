# Create the necessary registry keys
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Force | Out-Null

# App Level Dark Mode for all users
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name AppsUseLightTheme -Value 0 -Type Dword -Force
# System Level Dark Mode for all users
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name SystemUsesLightTheme -Value 0 -Type Dword -Force

# Hide First Run Experience in Edge 
$EdgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
New-Item -Path $EdgePath -Force | Out-Null
New-ItemProperty -Path $EdgePath -Name "HideFirstRunExperience" -PropertyType DWord -Value 1 -Force

# Invoke-WebRequest 'https://dl.google.com/drive-file-stream/GoogleDriveSetup.exe' -OutFile GoogleDriveSetup.exe
# GoogleDriveSetup --silent --desktop_shortcut --skip_launch_new

# Download files from Google Drive
Invoke-WebRequest 'https://www.googleapis.com/drive/v3/files/1j5VRLbVoTsgWg2gQjYVWqRYvKhp28UUK?alt=media&key=AIzaSyBD8tY90tF5DojRDNgAHN00gfoTCNOiuAI' -OutFile $Env:USERPROFILE/Downloads/Digitalisation_Tata_inlier.qgz
Invoke-WebRequest 'https://www.googleapis.com/drive/v3/files/1-gNqJntO86HkjEXIDbdnGo7vyzRQIb-i?alt=media&key=AIzaSyBD8tY90tF5DojRDNgAHN00gfoTCNOiuAI' -OutFile $Env:USERPROFILE/Downloads/Tata_inlier_Georef.tif
# Expand-Archive -Path ArcGIS_Setup.zip -DestinationPath C:\ArcGIS\ -Verbose
# Msiexec /i C:\ArcGIS\setup.msi INSTALLDIR="C:\ArcGIS" ESRI_LICENSE_HOST=GIS SOFTWARE_CLASS=Professional SEAT_PREFERENCE=Float /qb
# Invoke-WebRequest 'https://raw.githubusercontent.com/testonamonaco/actions-remote-desktops/main/AfCore.dll' -OutFile AfCore.dll
# Copy-Item AfCore.dll -Destination "C:\ArcGIS\Desktop10.8\bin"
