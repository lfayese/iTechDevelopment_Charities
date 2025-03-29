<#
.SYNOPSIS
    Configures Windows during OOBE phase after OSDCloud deployment
.DESCRIPTION
    This script handles various post-deployment tasks including:
    - Setting up Autopilot registration
    - Configuring Windows regional settings
    - Installing required PowerShell modules
    - Performing system optimizations
.PARAMETER NoAutopilot
    Skip Autopilot registration process
.PARAMETER SkipUpdates
    Skip Windows Updates during OOBE
.PARAMETER Region
    Sets the Windows region (default: US)
.PARAMETER Language
    Sets the Windows language (default: en-US)
.EXAMPLE
    .\BootOOBE.ps1 -Region "GB" -Language "en-GB"
.NOTES
    Author: OSDCloud Administrator
    Updated: Based on OSDCloud.com best practices
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$NoAutopilot,

    [Parameter()]
    [switch]$SkipUpdates,

    [Parameter()]
    [string]$Region = "US",

    [Parameter()]
    [string]$Language = "en-US"
)

#Start logging
$logFolder = "$env:ProgramData\OSDCloud\Logs"
if (-not (Test-Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path "$logFolder\BootOOBE-$(Get-Date -Format 'yyyyMMdd-HHmmss').log" -Force

function Test-InternetConnection {
    $internetConnected = $false
    $retryCount = 0
    $maxRetries = 5

    Write-Host "Testing internet connectivity..."

    while (-not $internetConnected -and $retryCount -lt $maxRetries) {
        $retryCount++
        try {
            $testConnection = Test-NetConnection -ComputerName 8.8.8.8 -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop
            if ($testConnection) {
                Write-Host "Internet connection established!" -ForegroundColor Green
                $internetConnected = $true
            }
            else {
                Write-Host "No internet connection. Attempt $retryCount of $maxRetries..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
            }
        }
        catch {
            Write-Host "Error testing internet connection: $_" -ForegroundColor Red
            Start-Sleep -Seconds 5
        }
    }

    if (-not $internetConnected) {
        Write-Warning "No internet connection available after $maxRetries attempts."
        # Open network connection dialog
        Write-Host "Opening Network Connection dialog..." -ForegroundColor Cyan
        Start-Process "ms-availablenetworks:"
        Start-Sleep -Seconds 10
    }

    return $internetConnected
}

function Install-RequiredModule {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,

        [Parameter(Mandatory = $false)]
        [switch]$AllowPrerelease
    )

    Write-Host "Installing $ModuleName PowerShell Module..." -ForegroundColor Cyan

    # Check if NuGet package provider is installed
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Write-Host "Installing NuGet package provider..."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
    }

    # Check if module is already installed
    $module = Get-InstalledModule -Name $ModuleName -ErrorAction SilentlyContinue

    if ($module) {
        Write-Host "$ModuleName module is already installed (Version: $($module.Version))"
    }
    else {
        try {
            if ($AllowPrerelease) {
                Install-Module -Name $ModuleName -Force -AllowClobber -Scope CurrentUser -AllowPrerelease -ErrorAction Stop
            }
            else {
                Install-Module -Name $ModuleName -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            }
            Write-Host "$ModuleName module installed successfully!" -ForegroundColor Green
        }
        catch {
            Write-Error "Error installing $ModuleName module: $_"
            return $false
        }
    }

    Import-Module -Name $ModuleName -Force
    return $true
}

function Start-AutopilotRegistration {
    Write-Host "Starting Autopilot device registration process..." -ForegroundColor Cyan

    # Install required modules
    $modulesInstalled = $true
    $modulesInstalled = $modulesInstalled -and (Install-RequiredModule -ModuleName WindowsAutopilotIntune)

    if (-not $modulesInstalled) {
        Write-Error "Failed to install one or more required modules. Autopilot registration cannot proceed."
        return $false
    }

    # Attempt to find existing Autopilot configuration file
    $autopilotConfigFile = $null
    $searchPaths = @(
        "C:\OSDCloud\Autopilot\AutopilotConfigurationFile.json",
        "C:\Windows\Temp\AutopilotConfigurationFile.json",
        "C:\ProgramData\OSDeploy\AutopilotConfigurationFile.json"
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $autopilotConfigFile = $path
            Write-Host "Found Autopilot configuration file at: $autopilotConfigFile" -ForegroundColor Green
            break
        }
    }

    if ($autopilotConfigFile) {
        # Use existing Autopilot configuration file
        Write-Host "Applying existing Autopilot configuration..." -ForegroundColor Cyan
        try {
            # Copy to Windows\Provisioning\Autopilot directory
            $autopilotFolder = "C:\Windows\Provisioning\Autopilot"
            if (-not (Test-Path $autopilotFolder)) {
                New-Item -Path $autopilotFolder -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path $autopilotConfigFile -Destination "$autopilotFolder\AutopilotConfigurationFile.json" -Force
            Write-Host "Autopilot configuration applied successfully" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to apply Autopilot configuration: $_"
            return $false
        }
    }
    else {
        # No config file found - register device using Get-WindowsAutopilotInfo
        Write-Host "No Autopilot configuration file found. Attempting online registration..." -ForegroundColor Yellow
        try {
            Install-RequiredModule -ModuleName "Get-WindowsAutopilotInfo"

            # Prompt for credentials
            Write-Host "Please provide Microsoft Intune admin credentials to register this device" -ForegroundColor Cyan
            $credential = Get-Credential -Message "Enter your Microsoft Intune admin credentials"

            if ($credential) {
                Write-Host "Registering device with Autopilot..." -ForegroundColor Cyan
                Get-WindowsAutoPilotInfo -Online -Credential $credential -GroupTag "OSDCloud" -Verbose
                Write-Host "Device registration submitted. It may take up to 15 minutes to complete." -ForegroundColor Green
                return $true
            }
            else {
                Write-Warning "No credentials provided. Autopilot registration skipped."
                return $false
            }
        }
        catch {
            Write-Error "Failed to register device with Autopilot: $_"
            return $false
        }
    }
}

function Set-RegionalSettings {
    param (
        [string]$Region,
        [string]$Language
    )

    Write-Host "Setting regional settings (Region: $Region, Language: $Language)..." -ForegroundColor Cyan

    try {
        # Set language settings
        Set-Culture -CultureInfo $Language
        Set-WinSystemLocale -SystemLocale $Language
        Set-WinUserLanguageList $Language -Force

        # Set region settings
        Set-WinHomeLocation -GeoId (Get-GeoId -CountryCode $Region).Id

        Write-Host "Regional settings applied successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to set regional settings: $_"
        return $false
    }
}

function Install-Updates {
    if ($SkipUpdates) {
        Write-Host "Windows Updates skipped per parameter" -ForegroundColor Yellow
        return
    }

    Write-Host "Checking for Windows Updates..." -ForegroundColor Cyan

    try {
        Install-RequiredModule -ModuleName PSWindowsUpdate

        # Check for updates
        $updates = Get-WindowsUpdate

        if ($updates.Count -eq 0) {
            Write-Host "No Windows Updates found" -ForegroundColor Green
            return
        }

        Write-Host "Found $($updates.Count) updates to install" -ForegroundColor Yellow

        # Install updates but don't force reboot
        Install-WindowsUpdate -AcceptAll -IgnoreReboot
        Write-Host "Windows Updates installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install Windows Updates: $_"
    }
}

# Main execution flow
try {
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "         OSDCloud - OOBE Configuration Tool         " -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "Computer Name: $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan

    # Check for internet connection and attempt to connect if needed
    if (-not (Test-InternetConnection)) {
        Write-Host "Please connect to the internet and press any key to continue..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }

    # Set regional settings
    Set-RegionalSettings -Region $Region -Language $Language

    # Handle Autopilot registration
    if (-not $NoAutopilot) {
        $autopilotResult = Start-AutopilotRegistration
        if ($autopilotResult) {
            Write-Host "Autopilot configuration completed" -ForegroundColor Green
        }
        else {
            Write-Warning "Autopilot configuration could not be completed"
        }
    }
    else {
        Write-Host "Autopilot registration skipped per parameter" -ForegroundColor Yellow
    }

    # Install Windows Updates
    Install-Updates

    # Set up automatic cleanup task to remove deployment files
    Write-Host "Setting up automatic cleanup task..." -ForegroundColor Cyan
    $cleanupScript = @'
Remove-Item -Path 'C:\OSDCloud\Logs' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'C:\OSDCloud\OS' -Recurse -Force -ErrorAction SilentlyContinue
'@

    $cleanupScriptPath = "$env:ProgramData\OSDCloud\cleanup.ps1"
    $cleanupScript | Out-File -FilePath $cleanupScriptPath -Force

    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$cleanupScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName "OSDCloudCleanup" -Action $action -Trigger $trigger -Description "Clean up OSDCloud deployment files" -User "SYSTEM" -RunLevel Highest -Force

    Write-Host "OOBE Configuration completed successfully!" -ForegroundColor Green

} catch {
    Write-Error "An error occurred during OOBE configuration: $_"
} finally {
    # Provide a visual indicator of completion
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "      OOBE Configuration process completed          " -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan

    Stop-Transcript
}

# Set global transcript file name and start transcript logging
$Global:Transcript = "$(Get-Date -Format 'yyyy-MM-dd-HHmmss')-OOBEScripts.log"
$TranscriptPath = Join-Path -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD" -ChildPath $Global:Transcript
Start-Transcript -Path $TranscriptPath -ErrorAction Stop

# Terminate any running sysprep processes
Get-Process sysprep -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Cleanup actions
Remove-Item -Path "C:\Windows\Panther\unattend.xml" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Setup\Scripts\init.ps1" -Recurse -Force -ErrorAction SilentlyContinue # Prevent loop after OOBE

# Copy init.ps1 from USB to Windows
$SourcePath = "X:\OSDCloud\Scripts\init.ps1"
$DestinationFolder = 'C:\Windows\Setup\Scripts'
$DestinationPath = Join-Path -Path $DestinationFolder -ChildPath 'init.ps1'

# Create destination directory if it doesn't exist
if (!(Test-Path -Path $DestinationFolder)) {
    New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
}

# Copy file with error handling
try {
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
    Write-Host "File copied successfully to $DestinationPath"
} catch {
    Write-Error "Failed to copy init.ps1: $_"
    exit 1
}

# Ensure setup scripts directory exists
$setupScriptsDir = 'C:\Windows\Setup\Scripts'
if (!(Test-Path -Path $setupScriptsDir)) {
    New-Item -Path $setupScriptsDir -ItemType Directory -Force | Out-Null
}

# Generate SetupComplete.cmd file
$SetupCompleteCMDContent = @"
powershell.exe -command set-executionpolicy remotedsigned -force
powershell.exe -file "%~dp0init.ps1"
powershell.exe -command "& 'X:\OSDCloud\Scripts\oobetasks.osdcloud.ps1'"
"@

$SetupCompleteCMDPath = Join-Path $setupScriptsDir 'SetupComplete.cmd'

try {
    $SetupCompleteCMDContent | Out-File -FilePath $SetupCompleteCMDPath -Encoding ascii -Force -ErrorAction Stop
    Write-Host "Successfully created SetupComplete.cmd"
} catch {
    Write-Error "Failed to create SetupComplete.cmd: $_"
    exit 1
}

# Copy unattend.xml from USB to sysprep folder
$UnattendSource = 'X:\OSDCloud\Scripts\unattend.xml'
$UnattendDest = 'C:\Windows\system32\sysprep\unattend.xml'

# Ensure sysprep directory exists
$sysprepDir = Split-Path $UnattendDest -Parent
if (!(Test-Path -Path $sysprepDir)) {
    New-Item -Path $sysprepDir -ItemType Directory -Force | Out-Null
}

try {
    Copy-Item -Path $UnattendSource -Destination $UnattendDest -Force -ErrorAction Stop
    Write-Host "Unattend.xml copied successfully"
} catch {
    Write-Error "Failed to copy unattend.xml: $_"
    exit 1
}

# Execute sysprep
Start-Process -FilePath "C:\Windows\System32\Sysprep\sysprep.exe" -ArgumentList "/oobe /quiet /reboot /unattend:$UnattendDest" -Wait

exit(0)