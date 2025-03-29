# Autopilot\Autopilot.ps1

Import-Module "$PSScriptRoot\..\Modules\UEFI.psm1"
Import-Module "$PSScriptRoot\..\Modules\Deployment.psm1"
Import-Module "$PSScriptRoot\..\Modules\Utils.psm1"

Write-Log "Starting Autopilot Upload..."

# Prompt for password to unlock 7z archive
$cred = Get-Credential -UserName "Autopilot Upload" -Message "Enter the USB Drive Password:"
$pw = $cred.GetNetworkCredential().Password
$arg = 'x "X:\Autopilot\Autopilot_Upload.7z" -o"X:\Autopilot\" -p"' + $pw + '"'

Write-Log "Extracting Autopilot_Upload.7z..."
Start-Process "X:\Autopilot\7za.exe" -ArgumentList $arg -Wait

if (Test-Path "X:\Autopilot\Get-AutoPilotHashAndUpload.ps1") {
    Write-Log "Autopilot script found, setting UEFI network flag..."
    Set-NetworkFlag

    Write-Log "Launching Autopilot upload script..."
    Start-Process powershell -ArgumentList "X:\Autopilot\Get-AutoPilotHashAndUpload.ps1" -Wait
    Write-Log "Upload script completed."
}
else {
    Show-MessageBox -Message "Autopilot Upload Error. Wrong password?" -Type Error
    Write-Log "Autopilot Upload script not found after extraction" -Level "ERROR"
}
