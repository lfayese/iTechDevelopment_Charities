# Start logging
$logPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD"
if (!(Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path "$logPath\init2-$(Get-Date -Format 'yyyyMMddHHmmss').log"

Write-Host "Starting cleanup process..."

$scriptsPath = "C:\Windows\Setup\Scripts"
if (Test-Path $scriptsPath) {
    try {
        Remove-Item $scriptsPath -Recurse -Force -ErrorAction Stop
        Write-Host "Successfully removed setup scripts directory"
    } catch {
        Write-Warning "Failed to remove setup scripts directory: $_"
        # Continue execution as this is not critical
    }
} else {
    Write-Host "Setup scripts directory does not exist - no cleanup needed"
}

Stop-Transcript
