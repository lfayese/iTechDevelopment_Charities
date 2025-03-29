# Autopilot Prerequisites Check Script
[CmdletBinding()]
param()

# Function to check network connectivity
function Test-NetworkConnectivity {
    $TestUrls = @(
        "login.microsoftonline.com",
        "devicemanagement.microsoft.com",
        "enterpriseregistration.windows.net"
    )
    
    foreach ($Url in $TestUrls) {
        $Result = Test-NetConnection -ComputerName $Url -Port 443
        if (-not $Result.TcpTestSucceeded) {
            return $false
        }
    }
    return $true
}

# Function to check TPM status
function Test-TPMStatus {
    try {
        $TPM = Get-Tpm
        return $TPM.TpmPresent -and $TPM.TpmReady -and $TPM.TpmEnabled
    }
    catch {
        return $false
    }
}

# Function to check secure boot status
function Test-SecureBootStatus {
    try {
        $SecureBoot = Confirm-SecureBootUEFI
        return $SecureBoot
    }
    catch {
        return $false
    }
}

# Function to check BitLocker readiness
function Test-BitLockerReadiness {
    $BLConfig = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
    return ($null -ne $BLConfig)
}

# Function to validate Windows version
function Test-WindowsVersion {
    $OS = Get-WmiObject -Class Win32_OperatingSystem
    $Version = [System.Version]($OS.Version)
    return $Version.Major -ge 10
}

# Function to check for Microsoft Store connectivity
function Test-MicrosoftStoreAccess {
    $StoreUrl = "www.microsoft.com"
    return (Test-NetConnection -ComputerName $StoreUrl -Port 443).TcpTestSucceeded
}

# Main check execution
$Results = @{
    "Network Connectivity" = Test-NetworkConnectivity
    "TPM Status" = Test-TPMStatus
    "Secure Boot" = Test-SecureBootStatus
    "BitLocker Ready" = Test-BitLockerReadiness
    "Windows Version" = Test-WindowsVersion
    "Microsoft Store Access" = Test-MicrosoftStoreAccess
}

# Process and display results
$AllChecksPassed = $true
Write-Host "`nAutopilot Prerequisites Check Results:" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

foreach ($Check in $Results.GetEnumerator()) {
    Write-Host "$($Check.Key): " -NoNewline
    if ($Check.Value) {
        Write-Host "Passed" -ForegroundColor Green
    }
    else {
        Write-Host "Failed" -ForegroundColor Red
        $AllChecksPassed = $false
    }
}

Write-Host "`nOverall Status: " -NoNewline
if ($AllChecksPassed) {
    Write-Host "All prerequisites met" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Some checks failed" -ForegroundColor Red
    exit 1
}