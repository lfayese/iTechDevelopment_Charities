# Main\OSDCloud_Tenant_Lockdown.ps1

Import-Module "$PSScriptRoot\..\Modules\Deployment.psm1"
Import-Module "$PSScriptRoot\..\Modules\Utils.psm1"

Write-Log "Setting FORCED_NETWORK_FLAG via UEFI variable..."
try {
    Set-NetworkFlag
    Write-Log "Network lockdown variable set successfully."
}
catch {
    Write-Log "Failed to set network lockdown UEFI variable: $_" -Level "ERROR"
    Show-MessageBox -Message "Unable to apply tenant lockdown." -Type "Error"
}
