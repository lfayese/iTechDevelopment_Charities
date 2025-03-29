# Windows Updates and Driver Management Script
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$IncludeFirmware,

    [Parameter()]
    [string]$ManufacturerSpecificPath
)

# Start logging
$Global:Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-WindowsUpdates.log"
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD"
if (!(Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path (Join-Path $LogPath $Global:Transcript) -ErrorAction Stop

# Function to detect system manufacturer and model
function Get-SystemInfo {
    $ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem
    $SystemEnclosure = Get-WmiObject -Class Win32_SystemEnclosure

    return @{
        Manufacturer = $ComputerSystem.Manufacturer
        Model = $ComputerSystem.Model
        SerialNumber = $SystemEnclosure.SerialNumber
    }
}

# Function to handle Dell updates
function Update-DellSystem {
    param([string]$Path)

    Write-Host "Processing Dell system updates..." -ForegroundColor Cyan

    # Download Dell Command Update if needed
    $DCUPath = Join-Path $Path "DCU"
    if (-not (Test-Path "$DCUPath\dcu-cli.exe")) {
        Write-Host "Downloading Dell Command Update..." -ForegroundColor Cyan
        # Add Dell Command Update download and installation logic
    }

    # Run Dell updates
    if (Test-Path "$DCUPath\dcu-cli.exe") {
        Write-Host "Running Dell Command Update..." -ForegroundColor Cyan
        & "$DCUPath\dcu-cli.exe" /scan -report=$Path\DellUpdateReport.xml
        & "$DCUPath\dcu-cli.exe" /applyUpdates -reboot=disable
    }
}

# Function to handle HP updates
function Update-HPSystem {
    param([string]$Path)

    Write-Host "Processing HP system updates..." -ForegroundColor Cyan

    # Download HP Image Assistant if needed
    $HPIAPath = Join-Path $Path "HPIA"
    if (-not (Test-Path "$HPIAPath\HPImageAssistant.exe")) {
        Write-Host "Downloading HP Image Assistant..." -ForegroundColor Cyan
        # Add HPIA download and installation logic
    }

    # Run HP updates
    if (Test-Path "$HPIAPath\HPImageAssistant.exe") {
        Write-Host "Running HP Image Assistant..." -ForegroundColor Cyan
        & "$HPIAPath\HPImageAssistant.exe" /Operation:Analyze /Action:Install /Selection:All /Silent
    }
}

# Function to handle Lenovo updates
function Update-LenovoSystem {
    param([string]$Path)

    Write-Host "Processing Lenovo system updates..." -ForegroundColor Cyan

    # Download Lenovo System Update if needed
    $LSUPath = Join-Path $Path "LSU"
    if (-not (Test-Path "$LSUPath\UpdateInstaller.exe")) {
        Write-Host "Downloading Lenovo System Update..." -ForegroundColor Cyan
        # Add LSU download and installation logic
    }

    # Run Lenovo updates
    if (Test-Path "$LSUPath\UpdateInstaller.exe") {
        Write-Host "Running Lenovo System Update..." -ForegroundColor Cyan
        & "$LSUPath\UpdateInstaller.exe" /VERYSILENT /NORESTART
    }
}

function Update-MicrosoftCatalog {
    Write-Host "Processing Microsoft catalog updates..." -ForegroundColor Cyan

    # Install PSWindowsUpdate if not present
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Install-Module PSWindowsUpdate -Force
    }

    # Import module and install updates
    Import-Module PSWindowsUpdate

    # Install driver updates with increased timeout
    Write-Host "Installing driver updates from Microsoft Update Catalog..." -ForegroundColor Cyan
    Get-WindowsUpdate -UpdateType Driver -Install -AcceptAll -MaxSize 500MB -Timeout 120

    if ($IncludeFirmware) {
        Write-Host "Installing firmware updates from Microsoft Update Catalog..." -ForegroundColor Cyan
        Get-WindowsUpdate -UpdateType Software -Install -AcceptAll -NotCategory "Feature Packs","Security Updates","Service Packs" -MaxSize 500MB -Timeout 120
    }
}
try {
    Write-Host "Starting Windows Update and Driver Management..." -ForegroundColor Cyan

    # Get system information
    $SystemInfo = Get-SystemInfo

    # Create working directory if specified
    if ($ManufacturerSpecificPath) {
        New-Item -Path $ManufacturerSpecificPath -ItemType Directory -Force | Out-Null
    }

    # Process updates based on manufacturer
    switch -Regex ($SystemInfo.Manufacturer) {
        "Dell" { Update-DellSystem -Path $ManufacturerSpecificPath }
        "HP|Hewlett-Packard" { Update-HPSystem -Path $ManufacturerSpecificPath }
        "Lenovo" { Update-LenovoSystem -Path $ManufacturerSpecificPath }
        default {
            Write-Host "No manufacturer-specific update tool available. Using Microsoft Update Catalog..." -ForegroundColor Yellow
            Update-MicrosoftCatalog
        }
    }

    Write-Host "Update process completed successfully!" -ForegroundColor Green

    # Check for pending reboot
    if (Test-PendingReboot) {
        Write-Host "Updates require a system restart." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "An error occurred during update process: $_"
    exit 1
}

# Function to check and perform a reboot if needed
function Test-PendingReboot {
    try {
        $rebootPending = Get-WURebootStatus -Silent -ErrorAction Stop
        if ($rebootPending) {
            Write-Host "System restart is required to complete the updates"
            # Log the pending reboot status
            "Reboot pending after updates - $(Get-Date)" |
                Out-File -FilePath "$LogPath\PendingReboot.log" -Append
            return $true
        }
        return $false
    } catch {
        Write-Warning "Failed to check reboot status: $_"
        return $false
    }
}

# Check for pending reboots and handle gracefully
if (Test-PendingReboot) {
    Write-Host "Initiating system restart in 60 seconds..."
    Stop-Transcript
    Start-Sleep -Seconds 5  # Give time for transcript to complete
    shutdown /r /t 60 /c "Restarting to complete Windows Updates" /d p:4:1
} else {
    Write-Host "No reboot required. Update process complete."
}

Stop-Transcript