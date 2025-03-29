# Define log file path
$logFilePath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\DefenderOnboarding.log"

# Function to write to log file
function WriteToLogFile {
    param([string]$message)
    Add-Content -Path $logFilePath -Value "$message - $(Get-Date)"
}

# Ensure log directory exists
$logDirectory = Split-Path $logFilePath -Parent
if (-not (Test-Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

# Write OSD completion to log file
WriteToLogFile "OSD Complete Registering WaitForOnboarding Task"

# Define variables
$directory = "C:\OSDCloud\Scripts"
$targetLocation = Join-Path $directory "WaitforOnboarding.xml"
$targetLocation2 = Join-Path $directory "WaitforOnboard.ps1"

# Create directory if it doesn't exist
if (-not (Test-Path $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

# Copy files from USB
$sourceFiles = @{
    "WaitforOnboarding.xml" = $targetLocation
    "WaitforOnboard.ps1" = $targetLocation2
}

foreach ($file in $sourceFiles.GetEnumerator()) {
    $sourcePath = "X:\OSDCloud\Scripts\WaitForOnboarding\$($file.Key)"
    try {
        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination $file.Value -Force -ErrorAction Stop
            Write-Host "Successfully copied $($file.Key)"
            WriteToLogFile "Successfully copied $($file.Key) to $($file.Value)"
        } else {
            throw "Source file not found: $sourcePath"
        }
    } catch {
        $errorMsg = "Failed to copy $($file.Key): $_"
        Write-Host $errorMsg -ForegroundColor Red
        WriteToLogFile $errorMsg
        exit 1
    }
}

# Register the scheduled task
try {
    if (Test-Path $targetLocation) {
        $xmlContent = Get-Content $targetLocation -Raw -ErrorAction Stop
        $existingTask = Get-ScheduledTask -TaskName 'WaitforOnboarding' -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName 'WaitforOnboarding' -Confirm:$false
        }
        Register-ScheduledTask -Xml $xmlContent -TaskName 'WaitforOnboarding'
        WriteToLogFile "Scheduled task registered successfully"
    } else {
        throw "Task XML file not found at $targetLocation"
    }
} catch {
    $errorMsg = "Failed to register scheduled task: $_"
    Write-Host $errorMsg -ForegroundColor Red
    WriteToLogFile $errorMsg
    exit 1
}

function Test-AutopilotReadiness {
    param(
        [int]$RetryCount = 3,
        [int]$RetryIntervalSeconds = 60
    )

    $requirements = @(
        @{
            Test = { Get-TpmStatus }
            Name = "TPM"
            Required = $true
        },
        @{
            Test = { Get-BitLockerStatus }
            Name = "BitLocker"
            Required = $false
        },
        @{
            Test = { Test-NetworkConnectivity }
            Name = "Network"
            Required = $true
        }
    )

    $attempt = 1
    while ($attempt -le $RetryCount) {
        $ready = $true
        foreach ($req in $requirements) {
            try {
                $result = & $req.Test
                if (-not $result -and $req.Required) {
                    Write-Warning "$($req.Name) check failed (Attempt $attempt of $RetryCount)"
                    $ready = $false
                }
            }
            catch {
                Write-Error "Error checking $($req.Name): $_"
                if ($req.Required) { $ready = $false }
            }
        }

        if ($ready) { return $true }

        if ($attempt -lt $RetryCount) {
            Write-Host "Waiting $RetryIntervalSeconds seconds before retry..."
            Start-Sleep -Seconds $RetryIntervalSeconds
        }
        $attempt++
    }

    return $false
}

function Register-DeviceAutopilot {
    param(
        [string]$ProfilePath = "C:\Windows\Provisioning\Autopilot\AutopilotConfigurationFile.json",
        [switch]$Force
    )

    if (-not $Force) {
        $readiness = Test-AutopilotReadiness
        if (-not $readiness) {
            throw "System not ready for Autopilot registration"
        }
    }

    try {
        # Ensure we have the required module
        if (-not (Get-Module -ListAvailable WindowsAutopilotIntune)) {
            Install-Module WindowsAutopilotIntune -Force
        }

        Import-Module WindowsAutopilotIntune

        # Get device hardware hash
        $hash = Get-WindowsAutoPilotInfo -ComputerName $env:COMPUTERNAME

        # Register with Autopilot
        if (Test-Path $ProfilePath) {
            $profile = Get-Content $ProfilePath | ConvertFrom-Json
            Join-AutopilotDevice -HardwareHash $hash -GroupTag $profile.GroupTag
        }
        else {
            Join-AutopilotDevice -HardwareHash $hash
        }

        Write-Host "Device successfully registered with Autopilot" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to register device with Autopilot: $_"
        return $false
    }
}