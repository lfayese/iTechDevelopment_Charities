#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enhanced OSDCloud Build Automation Script
.DESCRIPTION
    Automates the creation and configuration of OSDCloud WinPE/WinRE environments.
    This script verifies prerequisites, sets up the workspace, injects required packages and drivers,
    integrates custom WIM files, and creates ISO/USB boot media.
.NOTES
    Version: 7.1
    Updated: 2025-03-21
    Basic usage:
      .\osdcloud_build_v7.ps1 -WorkspacePath "D:\OSDCloud" -CreateISO

    Advanced usage with WinRE, drivers and autopilot enabled:
      .\osdcloud_build_v7.ps1 -WorkspacePath "D:\OSDCloud" -TemplateType WinRE -IncludeDrivers -CreateUSB -EnableAutopilot

    .\osdcloud_build_v7.ps1 -WorkspacePath "C:\OSDCloudProd" -TemplateType "WinRE" -IncludeDrivers -CustomWimPath "E:\idcwin11.wim" -CreateISO -StartupScriptPath ".\start-osdclouddeploy.ps1"

    Cleanup workspace:
      .\osdcloud_build_v7.ps1 -WorkspacePath "D:\OSDCloud" -Cleanup
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateScript({
        if(-not (Test-Path $_) -and -not (New-Item $_ -ItemType Directory -Force -ErrorAction SilentlyContinue)) {
            throw "Cannot create or access directory: $_"
        }
        # Check for at least 5GB free space
        $drive = Split-Path $_ -Qualifier
        $freeSpace = (Get-PSDrive $drive.Replace(':', '')).Free
        if ($freeSpace -lt 5GB) {
            throw "Insufficient disk space on $drive. At least 5GB required, found $([math]::Round($freeSpace/1GB, 2))GB."
        }
        return $true
    })]
    [string]$WorkspacePath = "C:\OSDCloud",

    [Parameter(Mandatory = $false)]
    [ValidateSet("WinPE", "WinRE")]
    [string]$TemplateType = "WinPE",

    [Parameter(Mandatory = $false)]
    [ValidateScript({
        if ($_ -and -not (Test-Path $_)) {
            throw "Custom WIM file not found: $_"
        }
        return $true
    })]
    [string]$CustomWimPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDrivers,

    [Parameter(Mandatory = $false)]
    [switch]$CreateISO,

    [Parameter(Mandatory = $false)]
    [switch]$CreateUSB,

    [Parameter(Mandatory = $false)]
    [ValidateScript({
        if ($_ -and -not (Test-Path $_)) {
            throw "Startup script not found: $_"
        }
        return $true
    })]
    [string]$StartupScriptPath,

    [Parameter(Mandatory = $false)]
    [switch]$EnableAutopilot,

    [Parameter(Mandatory = $false)]
    [switch]$Cleanup
)

# Script version information
$script:VersionInfo = @{
    Version = "7.1"
    ReleaseDate = "2025-03-21"
    Author = "OSDCloud Team"
    Changes = @(
        "Added more granular error handling for individual operations",
        "Improved parameter validation with disk space and permission checks",
        "Externalized configuration to JSON files for easier customization",
        "Added progress reporting for long-running operations",
        "Implemented cleanup functionality to reset workspace",
        "Fixed module loading issues in WinPE environment",
        "Added wrapper script for reliable module loading",
        "Improved path handling between build and runtime environments",
        "Added default fallback startup script with robust module loading",
        "Enhanced error handling and recovery mechanisms",
        "Added version tracking and build information"
    )
}

# Initialize environment paths
$script:Paths = @{
    Root  = $WorkspacePath
    Media = Join-Path $WorkspacePath "Media"
    Mount = Join-Path $WorkspacePath "Mount"
    ADK   = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit"
    WinPE = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment"
    Logs  = Join-Path $WorkspacePath "Logs"
    Config = Join-Path $WorkspacePath "Config"
    Temp  = Join-Path $WorkspacePath "Temp"
}

# Load or create configuration files
function Initialize-Configuration {
    [CmdletBinding()]
    param()

    # Create config directory if it doesn't exist
    if (-not (Test-Path $script:Paths.Config)) {
        New-Item -Path $script:Paths.Config -ItemType Directory -Force | Out-Null
        Write-BuildLog "Created configuration directory: $($script:Paths.Config)" -Level Info
    }

    # Define configuration files
    $script:ConfigFiles = @{
        WinPEPackages = Join-Path $script:Paths.Config "WinPEPackages.json"
        PSModules = Join-Path $script:Paths.Config "PSModules.json"
        Drivers = Join-Path $script:Paths.Config "Drivers.json"
    }

    # Create default WinPE packages configuration if it doesn't exist
    if (-not (Test-Path $script:ConfigFiles.WinPEPackages)) {
        $defaultWinPEPackages = @(
            "WinPE-WMI",
            "WinPE-NetFX",
            "WinPE-Scripting",
            "WinPE-PowerShell",
            "WinPE-SecureStartup",
            "WinPE-DismCmdlets",
            "WinPE-EnhancedStorage",
            "WinPE-StorageWMI",
            "WinPE-WDS-Tools"
        )
        $defaultWinPEPackages | ConvertTo-Json | Set-Content -Path $script:ConfigFiles.WinPEPackages -Force
        Write-BuildLog "Created default WinPE packages configuration: $($script:ConfigFiles.WinPEPackages)" -Level Info
    }

    # Create default PS modules configuration if it doesn't exist
    if (-not (Test-Path $script:ConfigFiles.PSModules)) {
        $defaultPSModules = @(
            "osd",
            "osdcloud",
            "PackageManagement",
            "PSWindowsUpdate",
            "Get-WindowsAutoPilotInfo",
            "PowerShellGet",
            "az",
            "Microsoft.Graph",
            "Microsoft.Entra",
            "Microsoft.Graph.Beta",
            "Microsoft.Entra.Beta"
        )
        $defaultPSModules | ConvertTo-Json | Set-Content -Path $script:ConfigFiles.PSModules -Force
        Write-BuildLog "Created default PowerShell modules configuration: $($script:ConfigFiles.PSModules)" -Level Info
    }

    # Create default drivers configuration if it doesn't exist
    if (-not (Test-Path $script:ConfigFiles.Drivers)) {
        $defaultDrivers = @(
            "Dell",
            "HP",
            "IntelNet",
            "USB",
            "WiFi"
        )
        $defaultDrivers | ConvertTo-Json | Set-Content -Path $script:ConfigFiles.Drivers -Force
        Write-BuildLog "Created default drivers configuration: $($script:ConfigFiles.Drivers)" -Level Info
    }

    # Load configurations
    $script:WinPEPackages = Get-Content -Path $script:ConfigFiles.WinPEPackages -Raw | ConvertFrom-Json
    $script:PSModules = Get-Content -Path $script:ConfigFiles.PSModules -Raw | ConvertFrom-Json
    $script:Drivers = Get-Content -Path $script:ConfigFiles.Drivers -Raw | ConvertFrom-Json

    Write-BuildLog "Configuration files loaded successfully" -Level Success
}

function Write-BuildLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )

    # Create logs directory if it doesn't exist
    if (-not (Test-Path $script:Paths.Logs)) {
        New-Item -Path $script:Paths.Logs -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFile = Join-Path $script:Paths.Logs "OSDCloud_Build_$(Get-Date -Format 'yyyyMMdd').log"

    # Format based on level
    $levelText = switch ($Level) {
        "Info"    { "INFO" }
        "Warning" { "WARN" }
        "Error"   { "ERROR" }
        "Success" { "SUCCESS" }
        default   { "INFO" }
    }

    # Write to console with color
    switch ($Level) {
        "Info"    { Write-Host "$timestamp [$levelText] $Message" -ForegroundColor Gray }
        "Warning" { Write-Host "$timestamp [$levelText] $Message" -ForegroundColor Yellow }
        "Error"   { Write-Host "$timestamp [$levelText] $Message" -ForegroundColor Red }
        "Success" { Write-Host "$timestamp [$levelText] $Message" -ForegroundColor Green }
        default   { Write-Host "$timestamp [$levelText] $Message" }
    }

    # Write to log file
    "$timestamp [$levelText] $Message" | Out-File -FilePath $logFile -Append
}

function Show-ScriptVersion {
    [CmdletBinding()]
    param()

    Write-Host "`n=== OSDCloud Build Script v$($script:VersionInfo.Version) ===" -ForegroundColor Cyan
    Write-Host "Released: $($script:VersionInfo.ReleaseDate)" -ForegroundColor Cyan
    Write-Host "Author:   $($script:VersionInfo.Author)" -ForegroundColor Cyan
    Write-Host "`nChanges in this version:" -ForegroundColor Cyan

    foreach ($change in $script:VersionInfo.Changes) {
        Write-Host " • $change" -ForegroundColor White
    }

    Write-Host "`n=== Build Configuration ===" -ForegroundColor Cyan
    Write-Host "Workspace Path:  $WorkspacePath" -ForegroundColor White
    Write-Host "Template Type:   $TemplateType" -ForegroundColor White
    Write-Host "Include Drivers: $($IncludeDrivers.IsPresent)" -ForegroundColor White
    Write-Host "Create ISO:      $($CreateISO.IsPresent)" -ForegroundColor White
    Write-Host "Create USB:      $($CreateUSB.IsPresent)" -ForegroundColor White
    Write-Host "Cleanup Mode:    $($Cleanup.IsPresent)" -ForegroundColor White

    if ($StartupScriptPath) {
        Write-Host "Startup Script:  $StartupScriptPath" -ForegroundColor White
    }

    if ($CustomWimPath) {
        Write-Host "Custom WIM:      $CustomWimPath" -ForegroundColor White
    }

    Write-Host "Enable Autopilot: $($EnableAutopilot.IsPresent)" -ForegroundColor White
    Write-Host "`n" -ForegroundColor White
}

function Test-InternetConnectivity {
    [CmdletBinding()]
    param()
    Write-BuildLog "Testing internet connectivity..." -Level Info
    try {
        $testSites = @(
            "https://www.microsoft.com",
            "https://www.google.com",
            "https://www.powershellgallery.com"
        )

        foreach ($site in $testSites) {
            try {
                Invoke-WebRequest -Uri $site -UseBasicParsing -TimeoutSec 5 | Out-Null
                Write-BuildLog "Internet connectivity verified via $site." -Level Success
                return $true
            } catch {
                Write-BuildLog "Could not connect to $site, trying alternative..." -Level Info
                continue
            }
        }

        Write-BuildLog "All connectivity tests failed." -Level Warning
        return $false
    } catch {
        Write-BuildLog "Internet connectivity test failed with unexpected error: $_" -Level Warning
        return $false
    }
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()
    Write-BuildLog "Checking prerequisites..." -Level Info

    # Set a permissive execution policy for this process
    try {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
        Write-BuildLog "Set execution policy to RemoteSigned for current process" -Level Success
    } catch {
        Write-BuildLog "Failed to set execution policy: $_" -Level Warning
        Write-BuildLog "Some script operations may fail due to execution policy restrictions" -Level Warning
    }

    # Check internet connectivity
    $internetAvailable = Test-InternetConnectivity

    # Check for Windows ADK
    if (-not (Test-Path $script:Paths.ADK)) {
        throw "Windows ADK not found at $($script:Paths.ADK). Please install Windows ADK first."
    }

    # Check for WinPE Add-on
    if (-not (Test-Path $script:Paths.WinPE)) {
        throw "Windows PE Add-on for ADK not found at $($script:Paths.WinPE). Please install the WinPE add-on."
    }

    # Check for the OSD module (and install if missing)
    if (-not (Get-Module -ListAvailable -Name OSD)) {
        if ($internetAvailable) {
            Write-BuildLog "OSD module not found. Attempting to install..." -Level Info
            try {
                Write-Progress -Activity "Installing OSD Module" -Status "Downloading and installing..." -PercentComplete 50
                Install-Module OSD -Force -Verbose
                Write-Progress -Activity "Installing OSD Module" -Completed
                Write-BuildLog "OSD module installed successfully." -Level Success
            } catch {
                Write-Progress -Activity "Installing OSD Module" -Completed
                throw "Failed to install OSD module: $_"
            }
        } else {
            throw "OSD module not found and internet connectivity is unavailable. Please install the OSD module manually."
        }
    } else {
        Write-BuildLog "OSD module is installed." -Level Success
    }

    # Check for the OSDCloud module (and install if missing)
    if (-not (Get-Module -ListAvailable -Name OSDCloud)) {
        if ($internetAvailable) {
            Write-BuildLog "OSDCloud module not found. Attempting to install..." -Level Info
            try {
                Write-Progress -Activity "Installing OSDCloud Module" -Status "Downloading and installing..." -PercentComplete 50
                Install-Module OSDCloud -Force -Verbose
                Write-Progress -Activity "Installing OSDCloud Module" -Completed
                Write-BuildLog "OSDCloud module installed successfully." -Level Success
            } catch {
                Write-Progress -Activity "Installing OSDCloud Module" -Completed
                Write-BuildLog "Failed to install OSDCloud module directly. Will try installing through OSD module." -Level Warning
                try {
                    Import-Module OSD -Force
                    Write-BuildLog "Attempting to install OSDCloud module through OSD..." -Level Info
                    Write-Progress -Activity "Installing OSDCloud Module" -Status "Trying alternative method..." -PercentComplete 75
                    Install-Module OSDCloud -Force -Verbose
                    Write-Progress -Activity "Installing OSDCloud Module" -Completed
                    Write-BuildLog "OSDCloud module installed through OSD." -Level Success
                } catch {
                    Write-Progress -Activity "Installing OSDCloud Module" -Completed
                    throw "Failed to install OSDCloud module: $_"
                }
            }
        } else {
            throw "OSDCloud module not found and internet connectivity is unavailable. Please install the OSDCloud module manually."
        }
    } else {
        Write-BuildLog "OSDCloud module is installed." -Level Success
    }

    # Create required directories
    $requiredPaths = @($script:Paths.Root, $script:Paths.Media, $script:Paths.Mount, $script:Paths.Logs, $script:Paths.Temp)
    foreach ($path in $requiredPaths) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
            Write-BuildLog "Created directory: $path" -Level Info
        }
    }

    Write-BuildLog "Prerequisites check completed successfully." -Level Success
}

function Add-WinPEPackages {
    [CmdletBinding()]
    param(
        [string]$MountPath
    )
    Write-BuildLog "Injecting WinPE packages to $MountPath..." -Level Info

    # Load packages from configuration
    $packages = $script:WinPEPackages

    $totalPackages = $packages.Count
    $currentPackage = 0
    $successCount = 0
    $failCount = 0

    foreach ($package in $packages) {
        $currentPackage++
        $percentComplete = [math]::Round(($currentPackage / $totalPackages) * 100)
        Write-Progress -Activity "Adding WinPE Packages" -Status "Processing $package ($currentPackage of $totalPackages)" -PercentComplete $percentComplete

        $cabPath = Join-Path $script:Paths.WinPE "amd64\WinPE_OCs\$package.cab"
        if (Test-Path $cabPath) {
            try {
                Add-WindowsPackage -Path $MountPath -PackagePath $cabPath -ErrorAction Stop | Out-Null
                $successCount++
                Write-BuildLog "Successfully added package: $package" -Level Success
            } catch {
                $failCount++
                Write-BuildLog "Failed to add package $package $_" -Level Warning

                # Try alternative method if first attempt fails
                try {
                    Write-BuildLog "Attempting alternative method for package $package..." -Level Info
                    $dismPath = Join-Path $env:SystemRoot "System32\Dism.exe"
                    $dismArgs = "/Image:""$MountPath"" /Add-Package /PackagePath:""$cabPath"""
                    Start-Process -FilePath $dismPath -ArgumentList $dismArgs -Wait -NoNewWindow

                    # Verify package was added
                    $packageInfo = Get-WindowsPackage -Path $MountPath | Where-Object { $_.PackageName -like "*$package*" }
                    if ($packageInfo) {
                        $successCount++
                        $failCount--
                        Write-BuildLog "Successfully added package using DISM: $package" -Level Success
                    }
                } catch {
                    Write-BuildLog "Alternative method also failed for package $package $_" -Level Warning
                }
            }
        } else {
            Write-BuildLog "Package file not found: $cabPath" -Level Warning
            $failCount++
        }
    }

    Write-Progress -Activity "Adding WinPE Packages" -Completed
    Write-BuildLog "WinPE package injection completed. Success: $successCount, Failed: $failCount" -Level Info
}

function New-OSDTemplate {
    [CmdletBinding()]
    param()
    Write-BuildLog "Creating OSDCloud template ($TemplateType)..." -Level Info
    try {
        Write-Progress -Activity "Creating OSDCloud Template" -Status "Initializing template..." -PercentComplete 10

        if ($TemplateType -eq "WinRE") {
            # Create a WinRE template with WiFi support
            Write-Progress -Activity "Creating OSDCloud Template" -Status "Creating WinRE template..." -PercentComplete 30
            New-OSDCloudTemplate -Name "WinREWiFi" -WinRE
            Set-OSDCloudTemplate -Name "WinREWiFi"

            Write-Progress -Activity "Creating OSDCloud Template" -Status "Creating workspace..." -PercentComplete 50
            New-OSDCloudWorkspace -WorkspacePath $WorkspacePath

            # Additional configuration for WinRE environments
            $mountPath = Join-Path $script:Paths.Mount "WinRE"
            if (Test-Path $mountPath) {
                Write-Progress -Activity "Creating OSDCloud Template" -Status "Adding packages to WinRE..." -PercentComplete 70
                Add-WinPEPackages -MountPath $mountPath

                # Add extra WiFi support packages
                $wifiPackages = @("WinPE-Dot3Svc", "WinPE-WiFi-Package")
                foreach ($package in $wifiPackages) {
                    $cabPath = Join-Path $script:Paths.WinPE "amd64\WinPE_OCs\$package.cab"
                    if (Test-Path $cabPath) {
                        try {
                            Add-WindowsPackage -Path $mountPath -PackagePath $cabPath -ErrorAction Stop | Out-Null
                            Write-BuildLog "Successfully added WiFi package: $package" -Level Success
                        } catch {
                            Write-BuildLog "Failed to add WiFi package $package $_" -Level Warning

                            # Try alternative method
                            try {
                                $dismPath = Join-Path $env:SystemRoot "System32\Dism.exe"
                                $dismArgs = "/Image:""$mountPath"" /Add-Package /PackagePath:""$cabPath"""
                                Start-Process -FilePath $dismPath -ArgumentList $dismArgs -Wait -NoNewWindow
                                Write-BuildLog "Added WiFi package using DISM: $package" -Level Success
                            } catch {
                                Write-BuildLog "Alternative method also failed for WiFi package $package $_" -Level Warning
                            }
                        }
                    } else {
                        Write-BuildLog "WiFi package not found: $cabPath" -Level Warning
                    }
                }
            }
        } else {
            Write-Progress -Activity "Creating OSDCloud Template" -Status "Creating WinPE template..." -PercentComplete 30
            New-OSDCloudTemplate -Name "WinPE"
            Set-OSDCloudTemplate -Name "WinPE"

            Write-Progress -Activity "Creating OSDCloud Template" -Status "Creating workspace..." -PercentComplete 50
            New-OSDCloudWorkspace -WorkspacePath $WorkspacePath
        }

        Write-Progress -Activity "Creating OSDCloud Template" -Status "Creating default scripts..." -PercentComplete 80

        # Create default OSDCloud module loader script
        $scriptsPath = Join-Path $script:Paths.Media "OSDCloud\Scripts"
        if (-not (Test-Path $scriptsPath)) {
            New-Item -Path $scriptsPath -ItemType Directory -Force | Out-Null
        }

        # Create a default PowerShell startup script that ensures modules are loaded
        $defaultStartupContent = @"
# Default OSDCloud startup script - Created by OSDCloud Build v$($script:VersionInfo.Version)
# This script ensures the OSDCloud module is properly loaded

# Set error action preference to continue so script doesn't terminate on non-critical errors
`$ErrorActionPreference = 'Continue'

Write-Host "Starting OSDCloud deployment process..." -ForegroundColor Cyan
Write-Host "Script version: $($script:VersionInfo.Version) (Build date: $($script:VersionInfo.ReleaseDate))" -ForegroundColor Cyan

# Ensure required modules are loaded
try {
    Import-Module OSD -ErrorAction Stop
    Write-Host "OSD module loaded successfully" -ForegroundColor Green
} catch {
    Write-Warning "Failed to load OSD module: `$_"
    # Try to find the module path
    `$modulePaths = `$env:PSModulePath -split ';'
    Write-Host "Module search paths:" -ForegroundColor Yellow
    foreach(`$path in `$modulePaths) {
        Write-Host "  `$path"
        # Check if module exists in this path
        if(Test-Path (Join-Path `$path "OSD")) {
            Write-Host "  > OSD module found!" -ForegroundColor Green
        }
    }
}

try {
    Import-Module OSDCloud -ErrorAction Stop
    Write-Host "OSDCloud module loaded successfully" -ForegroundColor Green

    # Start OSDCloud GUI if module loaded successfully
    Start-OSDCloud
} catch {
    Write-Warning "Failed to load OSDCloud module: `$_"
    # Try to locate the module
    `$possiblePaths = @(
        "X:\Program Files\WindowsPowerShell\Modules\OSDCloud",
        "X:\Windows\System32\WindowsPowerShell\v1.0\Modules\OSDCloud",
        "X:\Program Files\WindowsPowerShell\Modules\OSD\OSDCloud",
        "X:\Windows\System32\WindowsPowerShell\v1.0\Modules\OSD\OSDCloud"
    )

    foreach(`$path in `$possiblePaths) {
        if(Test-Path `$path) {
            Write-Host "OSDCloud module found at: `$path" -ForegroundColor Yellow
            try {
                Import-Module `$path -ErrorAction Stop
                Write-Host "OSDCloud module loaded from direct path" -ForegroundColor Green
                Start-OSDCloud
                break
            } catch {
                Write-Warning "Failed to import from `$path: `$_"
            }
        }
    }

    # Last resort - try to download and install the module in WinPE
    Write-Host "Attempting to install OSDCloud module in WinPE environment..." -ForegroundColor Yellow
    try {
        # Make sure NuGet provider is available
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        # Install and import modules
        Install-Module OSD -Force | Out-Null
        Import-Module OSD -Force
        Install-Module OSDCloud -Force | Out-Null
        Import-Module OSDCloud -Force
        Write-Host "Successfully installed and imported modules in WinPE" -ForegroundColor Green
        Start-OSDCloud
    } catch {
        Write-Warning "Failed to install modules in WinPE: `$_"
        Write-Host "Please check network connectivity and try again" -ForegroundColor Red
    }
}
"@
        $defaultStartupPath = Join-Path $scriptsPath "Start-OSDCloudDefault.ps1"
        Set-Content -Path $defaultStartupPath -Value $defaultStartupContent -Force
        Write-BuildLog "Created default OSDCloud startup script at $defaultStartupPath" -Level Success

        # Create version info file
        $versionInfoContent = @"
OSDCloud Build Script Information
================================
Version:      $($script:VersionInfo.Version)
Build Date:   $($script:VersionInfo.ReleaseDate)
Author:       $($script:VersionInfo.Author)
Template:     $TemplateType
Build Time:   $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Changes in this version:
$(($script:VersionInfo.Changes | ForEach-Object { "- $_" }) -join "`n")

Build Configuration:
- Workspace Path:  $WorkspacePath
- Template Type:   $TemplateType
- Include Drivers: $($IncludeDrivers.IsPresent)
- Create ISO:      $($CreateISO.IsPresent)
- Create USB:      $($CreateUSB.IsPresent)
- Startup Script:  $($StartupScriptPath ? $StartupScriptPath : "Default")
- Custom WIM:      $($CustomWimPath ? $CustomWimPath : "None")
- Enable Autopilot: $($EnableAutopilot.IsPresent)
"@
        $versionInfoPath = Join-Path $scriptsPath "OSDCloudBuildInfo.txt"
        Set-Content -Path $versionInfoPath -Value $versionInfoContent -Force
        Write-BuildLog "Created build info file at $versionInfoPath" -Level Success

        Write-Progress -Activity "Creating OSDCloud Template" -Status "Optimizing workspace..." -PercentComplete 90
        Optimize-Workspace
        Write-Progress -Activity "Creating OSDCloud Template" -Completed
        Write-BuildLog "OSDCloud template creation completed." -Level Success
    } catch {
        Write-Progress -Activity "Creating OSDCloud Template" -Completed
        Write-BuildLog "Failed to create OSDCloud template: $_" -Level Error
        throw
    }
}

function Optimize-Workspace {
    [CmdletBinding()]
    param()
    Write-BuildLog "Optimizing workspace by removing unnecessary language folders..." -Level Info
    $KeepTheseDirs = @('OSDCloud','boot', 'efi', 'en-us', 'sources', 'fonts', 'resources')
    $mediaPath = Join-Path $WorkspacePath "Media"

    $allDirs = Get-ChildItem $mediaPath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
    $dirsToRemove = $allDirs | Where-Object { $_.Name -notin $KeepTheseDirs }
    $totalDirs = $dirsToRemove.Count
    $currentDir = 0

    foreach ($dir in $dirsToRemove) {
        $currentDir++
        $percentComplete = [math]::Round(($currentDir / $totalDirs) * 100)
        Write-Progress -Activity "Optimizing Workspace" -Status "Removing $($dir.Name) ($currentDir of $totalDirs)" -PercentComplete $percentComplete

        Write-BuildLog "Removing unnecessary directory: $($dir.FullName)" -Level Info
        Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    $bootPath = Join-Path $mediaPath "Boot"
    if (Test-Path $bootPath) {
        Get-ChildItem $bootPath -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer -and $_.Name -notin $KeepTheseDirs } |
        ForEach-Object {
            Write-BuildLog "Removing unnecessary boot directory: $($_.FullName)" -Level Info
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $efiBootPath = Join-Path $mediaPath "EFI\Microsoft\Boot"
    if (Test-Path $efiBootPath) {
        Get-ChildItem $efiBootPath -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer -and $_.Name -notin $KeepTheseDirs } |
        ForEach-Object {
            Write-BuildLog "Removing unnecessary EFI boot directory: $($_.FullName)" -Level Info
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Progress -Activity "Optimizing Workspace" -Completed
    Write-BuildLog "Workspace optimization completed." -Level Success
}

function Add-CustomContent {
    [CmdletBinding()]
    param()
    if ($CustomWimPath -and (Test-Path $CustomWimPath)) {
        Write-BuildLog "Adding custom WIM file from $CustomWimPath..." -Level Info
        $osPath = Join-Path $script:Paths.Media "OSDCloud\OS"
        if (-not (Test-Path $osPath)) {
            New-Item -Path $osPath -ItemType Directory -Force | Out-Null
            Write-BuildLog "Created OS directory: $osPath" -Level Info
        }

        try {
            $destinationWim = Join-Path $osPath "custom.wim"
            Write-BuildLog "Exporting custom WIM to $destinationWim..." -Level Info

            Write-Progress -Activity "Processing Custom WIM" -Status "Exporting image (this may take several minutes)..." -PercentComplete 10

            # Get WIM info to show progress
            $wimInfo = Get-WindowsImage -ImagePath $CustomWimPath -Index 1
            $wimSize = (Get-Item $CustomWimPath).Length

            Write-Progress -Activity "Processing Custom WIM" -Status "Exporting $($wimInfo.ImageName) ($([math]::Round($wimSize/1GB, 2)) GB)" -PercentComplete 25

            # Export with progress tracking
            $exportProcess = Start-Process -FilePath "dism.exe" -ArgumentList "/Export-Image /SourceImagePath:""$CustomWimPath"" /SourceIndex:1 /DestinationImagePath:""$destinationWim"" /Compress:max" -NoNewWindow -PassThru

            # Poll for process completion with progress updates
            while (-not $exportProcess.HasExited) {
                if (Test-Path $destinationWim) {
                    $currentSize = (Get-Item $destinationWim).Length
                    $percentComplete = [math]::Min(90, [math]::Round(($currentSize / $wimSize) * 100))
                    Write-Progress -Activity "Processing Custom WIM" -Status "Exporting: $percentComplete% complete" -PercentComplete $percentComplete
                }
                Start-Sleep -Seconds 2
            }

            Write-Progress -Activity "Processing Custom WIM" -Status "Finalizing..." -PercentComplete 95

            # Verify the export was successful
            if (Test-Path $destinationWim) {
                try {
                    $exportedWimInfo = Get-WindowsImage -ImagePath $destinationWim -Index 1 -ErrorAction Stop
                    Write-BuildLog "Custom WIM processed and saved to: $destinationWim" -Level Success
                    Write-BuildLog "Exported image: $($exportedWimInfo.ImageName), Size: $([math]::Round((Get-Item $destinationWim).Length/1GB, 2)) GB" -Level Info
                } catch {
                    Write-BuildLog "WIM export completed but verification failed: $_" -Level Warning
                }
            } else {
                throw "WIM export completed but destination file not found"
            }

            Write-Progress -Activity "Processing Custom WIM" -Completed
        } catch {
            Write-Progress -Activity "Processing Custom WIM" -Completed
            Write-BuildLog "Failed to process custom WIM: $_" -Level Error

            # Try alternative method if first attempt fails
            try {
                Write-BuildLog "Attempting alternative method for WIM export..." -Level Info
                Copy-Item -Path $CustomWimPath -Destination $destinationWim -Force
                Write-BuildLog "Custom WIM copied directly to: $destinationWim" -Level Success
            } catch {
                Write-BuildLog "Alternative method also failed: $_" -Level Error
                throw
            }
        }
    } else {
        if ($CustomWimPath) {
            Write-BuildLog "Custom WIM path specified but file not found: $CustomWimPath" -Level Warning
        } else {
            Write-BuildLog "No custom WIM path provided, skipping custom WIM integration." -Level Info
        }
    }
}

function Add-Drivers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StartupScriptPath
    )
    if ($IncludeDrivers) {
        Write-BuildLog "Adding driver support and configuring startup script..." -Level Info
        try {
            # Create the scripts directory in OSDCloud workspace if it doesn't exist
            $scriptsPath = Join-Path $script:Paths.Media "OSDCloud\Scripts"
            if (-not (Test-Path $scriptsPath)) {
                New-Item -Path $scriptsPath -ItemType Directory -Force | Out-Null
                Write-BuildLog "Created scripts directory: $scriptsPath" -Level Info
            }

            # If a startup script is specified and exists, use it
            if ($StartupScriptPath -and (Test-Path $StartupScriptPath)) {
                $scriptName = Split-Path $StartupScriptPath -Leaf
                $destinationPath = Join-Path $scriptsPath $scriptName
                Copy-Item -Path $StartupScriptPath -Destination $destinationPath -Force
                Write-BuildLog "Copied startup script to: $destinationPath" -Level Success

                # Create a wrapper script that imports modules before running the main script
                $wrapperContent = @"
@echo off
X:
cd \
@echo Loading PowerShell environment...
PowerShell.exe -Command "Write-Host 'Loading OSD and OSDCloud modules...' -ForegroundColor Cyan; Import-Module OSD; Import-Module OSDCloud; Write-Host 'Modules loaded successfully' -ForegroundColor Green"
PowerShell.exe -ExecutionPolicy Bypass -File X:\OSDCloud\Scripts\$scriptName
"@
                $wrapperPath = Join-Path $scriptsPath "StartOSDCloud.cmd"
                Set-Content -Path $wrapperPath -Value $wrapperContent -Force
                Write-BuildLog "Created module loading wrapper script: $wrapperPath" -Level Success

                # Set the startup command to use the CMD wrapper
                $startnetCommand = "X:\OSDCloud\Scripts\StartOSDCloud.cmd"

                # Get driver list from configuration
                $driverList = $script:Drivers -join ','

                # Get module list from configuration
                $moduleList = $script:PSModules -join ','

                Write-Progress -Activity "Adding Drivers" -Status "Configuring OSDCloud WinPE with drivers..." -PercentComplete 30

                # Call Edit-OSDCloudWinPE with driver injection and startup script configuration
                Write-BuildLog "Configuring OSDCloud WinPE with drivers and startup command..." -Level Info
                Edit-OSDCloudWinPE -WorkspacePath $WorkspacePath `
                    -CloudDriver $driverList `
                    -PSModuleInstall $moduleList `
                    -Startnet $startnetCommand

                Write-Progress -Activity "Adding Drivers" -Status "Updating startup configuration..." -PercentComplete 70

                # Explicitly update Startnet.cmd with the desired startup command
                $bootPath = Join-Path $script:Paths.Media "OSDCloud\Boot"
                $startnetFile = Join-Path $bootPath "Startnet.cmd"
                if (Test-Path $startnetFile) {
                    Set-Content -Path $startnetFile -Value $startnetCommand -Force
                    Write-BuildLog "Startnet.cmd updated with custom startup command." -Level Success
                } else {
                    Write-BuildLog "Startnet.cmd not found at $startnetFile" -Level Warning
                }

                Write-Progress -Activity "Adding Drivers" -Completed
            } else {
                # If no startup script is specified or it doesn't exist, use the default one
                $defaultScript = Join-Path $scriptsPath "Start-OSDCloudDefault.ps1"
                if (Test-Path $defaultScript) {
                    Write-BuildLog "Using default OSDCloud startup script: $defaultScript" -Level Info

                    # Create a wrapper script for the default script
                    $wrapperContent = @"
@echo off
X:
cd \
@echo Loading PowerShell environment...
PowerShell.exe -Command "Write-Host 'Loading OSD and OSDCloud modules...' -ForegroundColor Cyan; Import-Module OSD; Import-Module OSDCloud; Write-Host 'Modules loaded successfully' -ForegroundColor Green"
PowerShell.exe -ExecutionPolicy Bypass -File X:\OSDCloud\Scripts\Start-OSDCloudDefault.ps1
"@
                    $wrapperPath = Join-Path $scriptsPath "StartOSDCloud.cmd"
                    Set-Content -Path $wrapperPath -Value $wrapperContent -Force
                    Write-BuildLog "Created module loading wrapper script: $wrapperPath" -Level Success

                    # Set the startup command to use the CMD wrapper
                    $startnetCommand = "X:\OSDCloud\Scripts\StartOSDCloud.cmd"

                    # Get driver list from configuration
                    $driverList = $script:Drivers -join ','

                    # Get module list from configuration
                    $moduleList = $script:PSModules -join ','

                    Write-Progress -Activity "Adding Drivers" -Status "Configuring OSDCloud WinPE with drivers..." -PercentComplete 30

                    # Configure OSDCloud WinPE with the default script
                    Edit-OSDCloudWinPE -WorkspacePath $WorkspacePath `
                        -CloudDriver $driverList `
                        -PSModuleInstall $moduleList `
                        -Startnet $startnetCommand

                    Write-Progress -Activity "Adding Drivers" -Status "Updating startup configuration..." -PercentComplete 70

                    # Explicitly update Startnet.cmd with the desired startup command
                    $bootPath = Join-Path $script:Paths.Media "OSDCloud\Boot"
                    $startnetFile = Join-Path $bootPath "Startnet.cmd"
                    if (Test-Path $startnetFile) {
                        Set-Content -Path $startnetFile -Value $startnetCommand -Force
                        Write-BuildLog "Startnet.cmd updated with default startup command." -Level Success
                    } else {
                        Write-BuildLog "Startnet.cmd not found at $startnetFile" -Level Warning
                    }

                    Write-Progress -Activity "Adding Drivers" -Completed
                } else {
                    # If no default script exists either, just inject drivers without a specific startup script
                    Write-BuildLog "No startup script specified and no default script found. Configuring with standard OSDCloud startup." -Level Warning

                    # Get driver list from configuration
                    $driverList = $script:Drivers -join ','

                    # Get module list from configuration
                    $moduleList = $script:PSModules -join ','

                    Write-Progress -Activity "Adding Drivers" -Status "Configuring OSDCloud WinPE with drivers..." -PercentComplete 50

                    Edit-OSDCloudWinPE -WorkspacePath $WorkspacePath `
                        -CloudDriver $driverList `
                        -PSModuleInstall $moduleList

                    Write-Progress -Activity "Adding Drivers" -Completed
                }
            }
            Write-BuildLog "Driver support and startup configuration added successfully." -Level Success
        } catch {
            Write-Progress -Activity "Adding Drivers" -Completed
            Write-BuildLog "Failed to add drivers or configure startup: $_" -Level Error
            throw
        }
    } else {
        Write-BuildLog "Driver inclusion not requested, skipping driver injection." -Level Info
    }
}

function Add-CustomScripts {
    [CmdletBinding()]
    param()
    $sourceScriptsPath = "C:\ProgramData\OSDCloud\Config\Scripts"
    $destinationScriptsPath = Join-Path $script:Paths.Media "OSDCloud\Scripts"

    if (Test-Path $sourceScriptsPath) {
        Write-BuildLog "Copying custom scripts from $sourceScriptsPath to $destinationScriptsPath..." -Level Info
        if (-not (Test-Path $destinationScriptsPath)) {
            New-Item -Path $destinationScriptsPath -ItemType Directory -Force | Out-Null
            Write-BuildLog "Created destination scripts directory: $destinationScriptsPath" -Level Info
        }

        try {
            $scriptFiles = Get-ChildItem -Path $sourceScriptsPath -File -Recurse
            $totalFiles = $scriptFiles.Count
            $currentFile = 0

            foreach ($file in $scriptFiles) {
                $currentFile++
                $percentComplete = [math]::Round(($currentFile / $totalFiles) * 100)
                Write-Progress -Activity "Copying Custom Scripts" -Status "Copying $($file.Name) ($currentFile of $totalFiles)" -PercentComplete $percentComplete

                $relativePath = $file.FullName.Substring($sourceScriptsPath.Length)
                $targetPath = Join-Path $destinationScriptsPath $relativePath
                $targetDir = Split-Path $targetPath -Parent

                if (-not (Test-Path $targetDir)) {
                    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
                }

                Copy-Item -Path $file.FullName -Destination $targetPath -Force
                Write-BuildLog "Copied script: $($file.Name) to $targetPath" -Level Info
            }

            Write-Progress -Activity "Copying Custom Scripts" -Completed
            Write-BuildLog "Successfully copied custom scripts to the OSDCloud workspace." -Level Success
        } catch {
            Write-Progress -Activity "Copying Custom Scripts" -Completed
            Write-BuildLog "Failed to copy custom scripts: $_" -Level Warning

            # Try copying files individually to identify problematic files
            Write-BuildLog "Attempting to copy files individually..." -Level Info
            foreach ($file in $scriptFiles) {
                try {
                    $relativePath = $file.FullName.Substring($sourceScriptsPath.Length)
                    $targetPath = Join-Path $destinationScriptsPath $relativePath
                    $targetDir = Split-Path $targetPath -Parent

                    if (-not (Test-Path $targetDir)) {
                        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
                    }

                       Copy-Item -Path $file.FullName -Destination $targetPath -Force -ErrorAction Stop
                    Write-BuildLog "Individually copied: $($file.Name)" -Level Info
                } catch {
                    Write-BuildLog "Failed to copy individual file $($file.Name): $_" -Level Warning
                }
            }
        }
    } else {
        Write-BuildLog "Custom scripts source directory not found: $sourceScriptsPath" -Level Info
    }
}

function Dismount-PendingImages {
    [CmdletBinding()]
    param()
    Write-BuildLog "Checking for mounted images..." -Level Info
    $mountedImages = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue

    if ($mountedImages) {
        Write-BuildLog "Found $($mountedImages.Count) mounted image(s) to dismount." -Level Info
        $totalImages = $mountedImages.Count
        $currentImage = 0

        foreach ($image in $mountedImages) {
            $currentImage++
            $percentComplete = [math]::Round(($currentImage / $totalImages) * 100)
            $mountPath = $image.MountPath

            Write-Progress -Activity "Dismounting Images" -Status "Processing $mountPath ($currentImage of $totalImages)" -PercentComplete $percentComplete
            Write-BuildLog "Processing mounted image at: $mountPath" -Level Info

            try {
                Write-BuildLog "Attempting to save and dismount image at $mountPath" -Level Info
                Dismount-WindowsImage -Path $mountPath -Save -ErrorAction Stop
                Write-BuildLog "Successfully dismounted image with changes saved" -Level Success
            } catch {
                Write-BuildLog "Failed to dismount image with save at $mountPath. Attempting discard... Error: $_" -Level Warning
                try {
                    Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Stop
                    Write-BuildLog "Image dismounted with changes discarded" -Level Warning
                } catch {
                    Write-BuildLog "Failed to dismount image at $mountPath. Error: $_" -Level Error

                    # Last resort - try using DISM directly
                    try {
                        Write-BuildLog "Attempting to use DISM directly to dismount image..." -Level Info
                        $dismPath = Join-Path $env:SystemRoot "System32\Dism.exe"
                        $dismArgs = "/Unmount-Image /MountDir:""$mountPath"" /Discard"
                        Start-Process -FilePath $dismPath -ArgumentList $dismArgs -Wait -NoNewWindow

                        # Check if the mount point still exists in the registry
                        $stillMounted = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue |
                                        Where-Object { $_.MountPath -eq $mountPath }

                        if (-not $stillMounted) {
                            Write-BuildLog "Successfully dismounted image using DISM directly" -Level Success
                        } else {
                            throw "Image still appears to be mounted after DISM command"
                        }
                    } catch {
                        Write-BuildLog "All dismount attempts failed. Manual cleanup may be required: $_" -Level Error
                        # Continue with other images rather than throwing and stopping everything
                    }
                }
            }
        }

        Write-Progress -Activity "Dismounting Images" -Completed
    } else {
        Write-BuildLog "No mounted images found." -Level Info
    }
}

function New-OSDMedia {
    [CmdletBinding()]
    param()

    # First handle any mounted images
    try {
        Dismount-PendingImages
    } catch {
        Write-BuildLog "Failed to handle mounted images before media creation: $_" -Level Error
        throw
    }

    if ($CreateISO) {
        Write-BuildLog "Creating ISO..." -Level Info
        try {
            Write-Progress -Activity "Creating Media" -Status "Building ISO file..." -PercentComplete 30
            New-OSDCloudISO

            # Verify ISO was created
            $isoPath = Join-Path $WorkspacePath "OSDCloud.iso"
            if (Test-Path $isoPath) {
                $isoInfo = Get-Item $isoPath
                Write-BuildLog "ISO creation succeeded. File: $isoPath (Size: $([math]::Round($isoInfo.Length / 1MB, 2)) MB)" -Level Success
                Write-Progress -Activity "Creating Media" -Status "ISO created successfully" -PercentComplete 100
            } else {
                Write-Progress -Activity "Creating Media" -Status "ISO file not found at expected location" -PercentComplete 100
                Write-BuildLog "ISO file not found at expected location: $isoPath" -Level Warning
            }

            Write-Progress -Activity "Creating Media" -Completed
        } catch {
            Write-Progress -Activity "Creating Media" -Completed
            Write-BuildLog "Failed to create ISO: $_" -Level Error

            # Try alternative method
            try {
                Write-BuildLog "Attempting alternative method for ISO creation..." -Level Info
                $oscdiskPath = Join-Path $script:Paths.Media "OSDCloud"

                # Check if oscdisk module is available
                if (Get-Module -ListAvailable -Name OSDisk) {
                    Write-BuildLog "Using OSDisk module for ISO creation" -Level Info
                    Import-Module OSDisk -Force
                    New-OSDisk -CreateISO -ImagePath $oscdiskPath -DestinationPath $isoPath
                } else {
                    Write-BuildLog "OSDisk module not available, using built-in tools" -Level Info
                    # Use built-in Windows tools as last resort
                    $oscdiskPath = Join-Path $script:Paths.Media "OSDCloud"
                    $isoPath = Join-Path $WorkspacePath "OSDCloud.iso"

                    # Use oscdimg if available
                    $oscdimgPath = Join-Path $script:Paths.ADK "Deployment Tools\amd64\Oscdimg\oscdimg.exe"
                    if (Test-Path $oscdimgPath) {
                        $etfsbootPath = Join-Path $script:Paths.ADK "Deployment Tools\amd64\Oscdimg\etfsboot.com"
                        $efisysPath = Join-Path $script:Paths.ADK "Deployment Tools\amd64\Oscdimg\efisys.bin"

                        if (Test-Path $etfsbootPath -and Test-Path $efisysPath) {
                            $oscdimgArgs = "-bootdata:2#p0,e,b""$etfsbootPath""#pEF,e,b""$efisysPath"" -u1 -udfver102 ""$oscdiskPath"" ""$isoPath"""
                            Start-Process -FilePath $oscdimgPath -ArgumentList $oscdimgArgs -Wait -NoNewWindow

                            if (Test-Path $isoPath) {
                                Write-BuildLog "ISO created using oscdimg: $isoPath" -Level Success
                            } else {
                                throw "oscdimg completed but ISO file not found"
                            }
                        } else {
                            throw "Required boot files not found for oscdimg"
                        }
                    } else {
                        throw "oscdimg.exe not found in ADK path"
                    }
                }
            } catch {
                Write-BuildLog "Alternative ISO creation method also failed: $_" -Level Error
                throw
            }
        }
    }

    if ($CreateUSB) {
        Write-BuildLog "Creating USB media..." -Level Info
        try {
            Write-Progress -Activity "Creating Media" -Status "Preparing USB media (select drive when prompted)..." -PercentComplete 50
            New-OSDCloudUSB
            Write-Progress -Activity "Creating Media" -Status "USB media creation completed" -PercentComplete 100
            Write-BuildLog "USB media creation succeeded." -Level Success
            Write-Progress -Activity "Creating Media" -Completed
        } catch {
            Write-Progress -Activity "Creating Media" -Completed
            Write-BuildLog "Failed to create USB media: $_" -Level Error
            throw
        }
    }
}

function Add-AutopilotSupport {
    [CmdletBinding()]
    param()
    if ($EnableAutopilot) {
        Write-BuildLog "Setting up Windows Autopilot support..." -Level Info
        Write-Progress -Activity "Configuring Autopilot" -Status "Setting up Autopilot support..." -PercentComplete 10

        # Create the Automate directory if it doesn't exist
        $automateDir = Join-Path $script:Paths.Media "OSDCloud\Automate"
        if (-not (Test-Path $automateDir)) {
            New-Item -Path $automateDir -ItemType Directory -Force | Out-Null
            Write-BuildLog "Created Autopilot directory: $automateDir" -Level Info
        }

        Write-Progress -Activity "Configuring Autopilot" -Status "Checking for existing configuration..." -PercentComplete 30

        # Check for existing Autopilot configuration
        $autopilotFile = Join-Path $automateDir "AutopilotConfigurationFile.json"
        if (Test-Path $autopilotFile) {
            Write-BuildLog "Existing Autopilot configuration file found: $autopilotFile" -Level Success
        } else {
            # Create a placeholder configuration file
            $placeholderContent = @'
{
    "Comment": "This is a placeholder Autopilot configuration file. Replace with your actual configuration.",
    "Version": 2.0,
    "Settings": [
        {
            "Name": "AddToAutopilotsDeviceGroup",
            "Value": "True"
        }
    ]
}
'@
            Set-Content -Path $autopilotFile -Value $placeholderContent -Force
            Write-BuildLog "Created placeholder Autopilot configuration file: $autopilotFile" -Level Info
            Write-BuildLog "IMPORTANT: Replace this placeholder with your actual Autopilot configuration before deployment." -Level Warning
        }

        Write-Progress -Activity "Configuring Autopilot" -Status "Setting up Autopilot modules..." -PercentComplete 60

        # Make sure the Get-WindowsAutoPilotInfo module is included
        $modulesPath = Join-Path $script:Paths.Media "OSDCloud\Modules"
        if (-not (Test-Path $modulesPath)) {
            New-Item -Path $modulesPath -ItemType Directory -Force | Out-Null
        }

        # Check if the module is already installed
        $autopilotModulePath = Join-Path $modulesPath "Get-WindowsAutoPilotInfo"
        if (-not (Test-Path $autopilotModulePath)) {
            # Try to download the module
            try {
                Save-Module -Name Get-WindowsAutoPilotInfo -Path $modulesPath -Force
                Write-BuildLog "Downloaded Get-WindowsAutoPilotInfo module to: $modulesPath" -Level Success
            } catch {
                Write-BuildLog "Failed to download Get-WindowsAutoPilotInfo module: $_" -Level Warning
                Write-BuildLog "The module will be installed during OSDCloud startup instead." -Level Info
            }
        } else {
            Write-BuildLog "Get-WindowsAutoPilotInfo module already exists in workspace." -Level Info
        }

        Write-Progress -Activity "Configuring Autopilot" -Status "Creating helper scripts..." -PercentComplete 80

        # Create a helper script for Autopilot
        $autopilotHelperScript = @"
<#
.SYNOPSIS
    Windows Autopilot Helper Script
.DESCRIPTION
    This script assists with Windows Autopilot device registration
.NOTES
    Version: 1.0
    Created by OSDCloud Build v$($script:VersionInfo.Version)
#>

# Ensure we're running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run as Administrator"
    break
}

Write-Host "Windows Autopilot Registration Helper" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Check if running in WinPE
$isWinPE = Test-Path -Path 'X:\Windows\System32'
if ($isWinPE) {
    Write-Host "Running in Windows PE environment" -ForegroundColor Yellow
} else {
    Write-Host "Running in full Windows environment" -ForegroundColor Green
}

# Import the module
try {
    Import-Module Get-WindowsAutoPilotInfo -ErrorAction Stop
    Write-Host "Successfully loaded Windows Autopilot module" -ForegroundColor Green
} catch {
    Write-Warning "Failed to load Windows Autopilot module. Attempting to install..."
    try {
        Install-Module Get-WindowsAutoPilotInfo -Force
        Import-Module Get-WindowsAutoPilotInfo -Force
        Write-Host "Successfully installed and loaded Windows Autopilot module" -ForegroundColor Green
    } catch {
        Write-Error "Failed to install Windows Autopilot module: $_"
        break
    }
}

# Prompt for tenant information
Write-Host ""
Write-Host "Please enter your Microsoft 365 tenant information:" -ForegroundColor Cyan
$tenantName = Read-Host "Tenant Name (e.g., contoso.onmicrosoft.com)"
$userName = Read-Host "Admin Username"

# Register the device
Write-Host ""
Write-Host "Registering device with Windows Autopilot..." -ForegroundColor Cyan
try {
    Get-WindowsAutoPilotInfo -Online -TenantName $tenantName -UserName $userName
    Write-Host "Device registration completed successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to register device: $_"
}
"@
        $autopilotHelperPath = Join-Path $automateDir "Register-AutopilotDevice.ps1"
        Set-Content -Path $autopilotHelperPath -Value $autopilotHelperScript -Force
        Write-BuildLog "Created Autopilot helper script: $autopilotHelperPath" -Level Success

        Write-Progress -Activity "Configuring Autopilot" -Completed
        Write-BuildLog "Windows Autopilot support configured successfully." -Level Success
    }
}

function Show-TroubleshootingTips {
    [CmdletBinding()]
    param()

    Write-Host "`n=== Troubleshooting Tips ===" -ForegroundColor Yellow
    Write-Host "If you encounter issues with the OSDCloud environment, check the following:" -ForegroundColor White

    Write-Host "`n1. Module Loading Issues:" -ForegroundColor Yellow
    Write-Host "   • The script now includes a wrapper CMD file that loads modules before running scripts" -ForegroundColor White
    Write-Host "   • Default startup script attempts to load modules from multiple locations" -ForegroundColor White
    Write-Host "   • Check X:\Windows\Logs\DISM\dism.log for package installation issues" -ForegroundColor White

    Write-Host "`n2. File Path Issues:" -ForegroundColor Yellow
     Write-Host "   • Ensure scripts use X:\ paths when running in WinPE" -ForegroundColor White
    Write-Host "   • The boot environment uses X: as the root drive, not C:" -ForegroundColor White
    Write-Host "   • All paths in startnet.cmd should use X:\ prefix" -ForegroundColor White

    Write-Host "`n3. Log Locations:" -ForegroundColor Yellow
    Write-Host "   • Build logs: $($script:Paths.Logs)" -ForegroundColor White
    Write-Host "   • WinPE logs: X:\Windows\Logs\DISM" -ForegroundColor White
    Write-Host "   • OSDCloud logs: X:\Windows\Logs\OSDCloud" -ForegroundColor White

    Write-Host "`n4. Common Solutions:" -ForegroundColor Yellow
    Write-Host "   • If modules fail to load, the default script will attempt to install them in WinPE" -ForegroundColor White
    Write-Host "   • The wrapper script (StartOSDCloud.cmd) ensures modules are loaded before running scripts" -ForegroundColor White
    Write-Host "   • Network connectivity is required for module installation in WinPE" -ForegroundColor White
    Write-Host "   • Check that all required drivers are included with -IncludeDrivers parameter" -ForegroundColor White

    Write-Host "`n5. Recovery Options:" -ForegroundColor Yellow
    Write-Host "   • Press F8 in WinPE to access command prompt for troubleshooting" -ForegroundColor White
    Write-Host "   • Run 'X:\OSDCloud\Scripts\Start-OSDCloudDefault.ps1' manually if startup fails" -ForegroundColor White
    Write-Host "   • The default script includes extensive error handling and recovery options" -ForegroundColor White

    Write-Host "`nFor more information, visit: https://osdcloud.osdeploy.com/" -ForegroundColor Cyan
}

function Invoke-Cleanup {
    [CmdletBinding()]
    param()

    Write-BuildLog "Starting workspace cleanup..." -Level Info

    # First dismount any mounted images
    try {
        Dismount-PendingImages
    } catch {
        Write-BuildLog "Error during image dismounting: $_" -Level Warning
        # Continue with cleanup despite errors
    }

    # Define paths to clean up
    $cleanupPaths = @(
        (Join-Path $script:Paths.Root "Mount"),
        (Join-Path $script:Paths.Root "Temp"),
        (Join-Path $script:Paths.Root "*.iso")
    )

    $totalPaths = $cleanupPaths.Count
    $currentPath = 0

    foreach ($path in $cleanupPaths) {
        $currentPath++
        $percentComplete = [math]::Round(($currentPath / $totalPaths) * 100)

        # Handle wildcard paths
        if ($path -like "*`**") {
            $items = Get-Item -Path $path -ErrorAction SilentlyContinue
            if ($items) {
                foreach ($item in $items) {
                    Write-Progress -Activity "Cleaning Workspace" -Status "Removing $($item.FullName)" -PercentComplete $percentComplete
                    Write-BuildLog "Removing file: $($item.FullName)" -Level Info
                    try {
                        Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                    } catch {
                        Write-BuildLog "Failed to remove $($item.FullName): $_" -Level Warning
                    }
                }
            }
        } else {
            # Handle directory paths
            if (Test-Path $path) {
                Write-Progress -Activity "Cleaning Workspace" -Status "Removing $path" -PercentComplete $percentComplete
                Write-BuildLog "Removing directory: $path" -Level Info
                try {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                } catch {
                    Write-BuildLog "Failed to remove $path $_" -Level Warning

                    # Try alternative method for stubborn directories
                    try {
                        # Use robocopy to empty the directory (a known trick for stubborn folders)
                        $emptyDir = Join-Path $script:Paths.Temp "Empty"
                        if (-not (Test-Path $emptyDir)) {
                            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
                        }

                        # Use robocopy with /MIR to empty the directory
                        $robocopyArgs = "`"$emptyDir`" `"$path`" /MIR /NFL /NDL /NJH /NJS /NC /NS /NP"
                        Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -NoNewWindow

                        # Now try to remove the directory again
                        Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                        Write-BuildLog "Successfully removed $path using alternative method" -Level Success
                    } catch {
                        Write-BuildLog "All attempts to remove $path failed: $_" -Level Warning
                    }
                }
            }
        }
    }

    Write-Progress -Activity "Cleaning Workspace" -Completed
    Write-BuildLog "Workspace cleanup completed." -Level Success
}

#----------------------------------------------------------------------------------
# Main execution block
try {
    Show-ScriptVersion

    # Handle cleanup mode if specified
    if ($Cleanup) {
        Write-BuildLog "Running in cleanup mode" -Level Info
        Invoke-Cleanup
        Write-BuildLog "Cleanup completed successfully" -Level Success
        return
    }

    Write-BuildLog "Starting OSDCloud build process..." -Level Info

    # Initialize configuration files
    Initialize-Configuration

    # Check prerequisites
    Test-Prerequisites

    # Import required modules
    Import-Module OSD -Force
    Import-Module OSDCloud -Force

    # Create OSDCloud template and workspace
    New-OSDTemplate

    # Add custom content if specified
    Add-CustomContent

    # Add custom scripts from standard location
    Add-CustomScripts

    # If no startup script is provided, use the default one created in New-OSDTemplate
    if (-not $StartupScriptPath -or -not (Test-Path $StartupScriptPath)) {
        $defaultScript = Join-Path $script:Paths.Media "OSDCloud\Scripts\Start-OSDCloudDefault.ps1"
        if (Test-Path $defaultScript) {
            Write-BuildLog "Using default OSDCloud startup script" -Level Info
            $StartupScriptPath = $defaultScript
        }
    }

    # Add drivers and configure startup
    Add-Drivers -StartupScriptPath $StartupScriptPath

    # Add Autopilot support if requested
    if ($EnableAutopilot) {
        Add-AutopilotSupport
    }

    # Ensure all images are properly dismounted before media creation
    Dismount-PendingImages

    # Create media (ISO and/or USB)
    New-OSDMedia

    # Display build summary
    Write-BuildLog "OSDCloud build completed successfully" -Level Success

    # Display version information
    Write-Host "`n=== Build Summary ===" -ForegroundColor Cyan
    Write-Host "OSDCloud Build Script v$($script:VersionInfo.Version)" -ForegroundColor White
    Write-Host "Workspace: $WorkspacePath" -ForegroundColor White

    if ($CreateISO) {
        $isoPath = Join-Path $WorkspacePath "OSDCloud.iso"
        if (Test-Path $isoPath) {
            $isoInfo = Get-Item $isoPath
            Write-Host "ISO created: $isoPath (Size: $([math]::Round($isoInfo.Length / 1MB, 2)) MB)" -ForegroundColor Green
        }
    }

    if ($CreateUSB) {
        Write-Host "USB media creation completed" -ForegroundColor Green
    }

    # Display troubleshooting tips
    Show-TroubleshootingTips

} catch {
    Write-BuildLog "Critical error during OSDCloud build: $_" -Level Error
    Write-Host "`nBuild process failed. Check the log file for details: $($script:Paths.Logs)" -ForegroundColor Red

    # Attempt to provide more detailed error information
    Write-Host "`n=== Error Details ===" -ForegroundColor Red
    Write-Host "Error Type: $($_.Exception.GetType().FullName)" -ForegroundColor White
    Write-Host "Error Message: $($_.Exception.Message)" -ForegroundColor White

    if ($_.ScriptStackTrace) {
        Write-Host "`nStack Trace:" -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor White
    }

    Write-Host "`nTo clean up the workspace and start fresh, run:" -ForegroundColor Yellow
    Write-Host ".\osdcloud_build_v7.ps1 -WorkspacePath `"$WorkspacePath`" -Cleanup" -ForegroundColor White

    throw
}