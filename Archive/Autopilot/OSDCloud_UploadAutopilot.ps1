# Autopilot\OSDCloud_UploadAutopilot.ps1

Import-Module "$PSScriptRoot\..\Modules\UEFI.psm1"
Import-Module "$PSScriptRoot\..\Modules\Utils.psm1"

Write-Log "Starting Autopilot hash generation and upload process..."

# Ensure NuGet is available
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Log "Installing NuGet provider..."
    Install-PackageProvider -Name NuGet -Force
}

# Ensure Autopilot module is available
if (-not (Get-Module -ListAvailable -Name WindowsAutopilotIntune)) {
    Write-Log "Installing WindowsAutopilotIntune module..."
    Install-Module -Name WindowsAutopilotIntune -Force -SkipPublisherCheck
}
Import-Module WindowsAutopilotIntune -Force

# Connect to Graph
Connect-MgGraph -UseDeviceCode

# Write required OA3 XML files
$inputXml = @'
<?xml version="1.0"?>
<Key>
  <ProductKey>XXXXX-XXXXX-XXXXX-XXXXX-XXXXX</ProductKey>
  <ProductKeyID>0000000000000</ProductKeyID>
  <ProductKeyState>0</ProductKeyState>
</Key>
'@

$oa3cfg = @'
<OA3>
  <FileBased>
    <InputKeyXMLFile>.\input.XML</InputKeyXMLFile>
  </FileBased>
  <OutputData>
    <AssembledBinaryFile>.\OA3.bin</AssembledBinaryFile>
    <ReportedXMLFile>.\OA3.xml</ReportedXMLFile>
  </OutputData>
</OA3>
'@

Set-Content "$PSScriptRoot\input.xml" $inputXml -Encoding UTF8
Set-Content "$PSScriptRoot\OA3.cfg" $oa3cfg -Encoding UTF8

# Register TPM if in WinPE
if (Test-Path "X:\Windows\System32\wpeutil.exe") {
    Write-Log "Detected WinPE, attempting TPM fix..."
    Copy-Item "$PSScriptRoot\PCPKsp.dll" "X:\Windows\System32\PCPKsp.dll" -Force
    rundll32 "X:\Windows\System32\PCPKsp.dll",DllInstall
}

# Run OA3Tool
Write-Log "Running OA3Tool to generate hardware hash..."
Start-Process "$PSScriptRoot\oa3tool.exe" -WorkingDirectory $PSScriptRoot -ArgumentList "/Report /ConfigFile=$PSScriptRoot\OA3.cfg /NoKeyCheck" -Wait

# Read hash from XML
if (!(Test-Path "$PSScriptRoot\OA3.xml")) {
    Show-MessageBox "OA3.xml not found. Hardware hash not generated." -Type Error
    return
}

[xml]$xml = Get-Content "$PSScriptRoot\OA3.xml"
$hash = $xml.Key.HardwareHash
$serial = (Get-CimInstance -Class Win32_BIOS).SerialNumber

Write-Log "Submitting device to Intune: Serial = $serial"

# Upload device
$importStart = Get-Date
$imported = Add-AutopilotImportedDevice -SerialNumber $serial -HardwareIdentifier $hash

# Wait for processing
$attempts = 0
do {
    Start-Sleep -Seconds 15
    $attempts++
    $current = Get-AutopilotImportedDevice -Id $imported.Id
    $status = $current.State.DeviceImportStatus
    Write-Log "Import status: $status (Attempt $attempts)"
} while ($status -eq 'unknown' -and $attempts -lt 10)

if ($current.State.DeviceImportStatus -eq 'complete') {
    Write-Log "Autopilot hash uploaded successfully for $serial"
    Show-MessageBox "Autopilot upload completed successfully." -Type Info
} else {
    Write-Log "Autopilot upload failed: $($current.State.DeviceErrorCode) - $($current.State.DeviceErrorName)" -Level "ERROR"
    Show-MessageBox "Autopilot upload failed. Please check logs." -Type Error
}
