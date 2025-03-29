# Script to track the process Hybrid Join, MDM enrollment, Defender for endpoint onboarding.

$logFilePath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderOnboarding.log"
$maxWaitTimeMinutes = 180 # 3 hours total wait time
$checkIntervalSeconds = 60 # Check every minute
$startTime = Get-Date

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error')]
        [string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFilePath -Value $logMessage
}

function Test-Timeout {
    $timeElapsed = (Get-Date) - $startTime
    if ($timeElapsed.TotalMinutes -gt $maxWaitTimeMinutes) {
        Write-Log -Level Error "Maximum wait time of $maxWaitTimeMinutes minutes exceeded" 
        return $true
    }
    return $false
}

Write-Log "Script started"

# Check Azure AD Join Status
try {
    do {
        $AADInfo = Get-Item "HKLM:/SYSTEM/CurrentControlSet/Control/CloudDomainJoin/JoinInfo" -ErrorAction Stop
        $guids = $AADInfo.GetSubKeyNames()
        $DeviceDisplayName = $false
        
        foreach ($guid in $guids) {
            $guidSubKey = $AADInfo.OpenSubKey($guid)
            if ($null -ne $guidSubKey.GetValue("DeviceDisplayName")) {
                $DeviceDisplayName = $true
                break
            }
        }
        
        if (-not $DeviceDisplayName) {
            Write-Log "Waiting for Azure AD Join..."
            Start-Sleep -Seconds $checkIntervalSeconds
        }
        
        if (Test-Timeout) { throw "Timeout waiting for Azure AD Join" }
    } while (-not $DeviceDisplayName)
    
    Write-Log "Successfully Hybrid Joined"
} catch {
    Write-Log -Level Error "Failed to verify Azure AD Join: $_"
}

# Check MDM Enrollment
try {
    do {
        $MDMEnrollment = $null -ne (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\MDMDeviceID -ErrorAction SilentlyContinue).DeviceClientID
        if (-not $MDMEnrollment) {
            Write-Log "Waiting for MDM enrollment..."
            Start-Sleep -Seconds $checkIntervalSeconds
        }
        
        if (Test-Timeout) { throw "Timeout waiting for MDM enrollment" }
    } while (-not $MDMEnrollment)
    
    Write-Log "Successfully enrolled in MDM"
} catch {
    Write-Log -Level Error "Failed to verify MDM enrollment: $_"
}

# Check Defender Onboarding
try {
    do {
        $MDEState = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status" -ErrorAction SilentlyContinue).onboardingstate -eq "1"
        if (-not $MDEState) {
            Write-Log "Waiting for Defender for Endpoint onboarding..."
            Start-Sleep -Seconds $checkIntervalSeconds
        }
        
        if (Test-Timeout) { throw "Timeout waiting for Defender onboarding" }
    } while (-not $MDEState)
    
    Write-Log "Successfully onboarded to Defender for Endpoint"
} catch {
    Write-Log -Level Error "Failed to verify Defender onboarding: $_"
}

# Cleanup scheduled task
try {
    if (Get-ScheduledTask -TaskName "waitforonboarding" -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName "waitforonboarding" -Confirm:$false
        Write-Log "Successfully removed scheduled task"
    }
} catch {
    Write-Log -Level Error "Failed to remove scheduled task: $_"
}

Write-Log "Script completed"