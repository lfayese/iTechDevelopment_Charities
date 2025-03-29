#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enhanced OSDCloud Build Automation Script
.DESCRIPTION
    Automates the creation and configuration of OSDCloud WinPE/WinRE environments.
    This script verifies prerequisites, sets up the workspace, injects required packages and drivers,
    integrates custom WIM files, and creates ISO/USB boot media.
.NOTES
    Version: 4.1
    Updated: 2024-03-21
    Basic usage:
      .\Build-OSDCloud.ps1 -WorkspacePath "D:\OSDCloud" -CreateISO

    Advanced usage with WinRE, drivers and autopilot enabled:
      .\Build-OSDCloud.ps1 -WorkspacePath "D:\OSDCloud" -TemplateType WinRE -IncludeDrivers -CreateUSB -EnableAutopilot

    .\osdcloud_build_v4.ps1 -WorkspacePath "C:\OSDCloudProd" -TemplateType "WinRE" -IncludeDrivers -CustomWimPath "E:\idcwin11.wim" -CreateISO -StartupScriptPath ".\start-osdclouddeploy.ps1"
#>
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$WorkspacePath = "C:\OSDCloud",

    [Parameter(Mandatory = $false)]
    [ValidateSet("WinPE", "WinRE")]
    [string]$TemplateType = "WinPE",

    [Parameter(Mandatory = $false)]
    [string]$CustomWimPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDrivers,

    [Parameter(Mandatory = $false)]
    [switch]$CreateISO,

    [Parameter(Mandatory = $false)]
    [switch]$CreateUSB,

    [Parameter(Mandatory = $false)]
    [string]$StartupScriptPath,

    [Parameter(Mandatory = $false)]
    [switch]$EnableAutopilot
)

# Initialize environment paths (no logging directory)
$script:Paths = @{
    Root  = $WorkspacePath
    Media = Join-Path $WorkspacePath "Media"
    Mount = Join-Path $WorkspacePath "Mount"
    ADK   = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit"
    WinPE = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment"
}

function Test-InternetConnectivity {
    [CmdletBinding()]
    param()
    Write-Verbose "Testing internet connectivity..."
    try {
        Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing -TimeoutSec 10 | Out-Null
        Write-Verbose "Internet connectivity verified."
    } catch {
        Write-Warning "Internet connectivity test failed. Ensure you have a stable connection."
    }
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()
    Write-Verbose "Checking prerequisites..."
    # Set a permissive execution policy for this process
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
    Test-InternetConnectivity
    # Check for Windows ADK
    if (-not (Test-Path $script:Paths.ADK)) {
        throw "Windows ADK not found. Please install Windows ADK first."
    }
    # Check for WinPE Add-on
    if (-not (Test-Path $script:Paths.WinPE)) {
        throw "Windows PE Add-on for ADK not found. Please install the WinPE add-on."
    }
    # Check for the OSD module (and install if missing)
    if (-not (Get-Module -ListAvailable -Name OSD)) {
        try {
            Install-Module OSD -Force -Verbose
        } catch {
            throw "Failed to install OSD module: $_"
        }
    }
    # Create required directories
    $requiredPaths = @($script:Paths.Root, $script:Paths.Media, $script:Paths.Mount)
    foreach ($path in $requiredPaths) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
}

function Add-WinPEPackages {
    [CmdletBinding()]
    param(
        [string]$MountPath
    )
    Write-Verbose "Injecting WinPE packages..."
    $packages = @(
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
    foreach ($package in $packages) {
        $cabPath = Join-Path $script:Paths.WinPE "amd64\WinPE_OCs\$package.cab"
        if (Test-Path $cabPath) {
            try {
                Add-WindowsPackage -Path $MountPath -PackagePath $cabPath -ErrorAction Stop
                Write-Verbose "Successfully added package: $package"
            } catch {
                Write-Warning "Failed to add package $package $_"
            }
        } else {
            Write-Warning "Package file not found: $cabPath"
        }
    }
}

function New-OSDTemplate {
    [CmdletBinding()]
    param()
    Write-Verbose "Creating OSDCloud template..."
    try {
        if ($TemplateType -eq "WinRE") {
            # Create a WinRE template with WiFi support
            New-OSDCloudTemplate -Name "WinREWiFi" -WinRE
            Set-OSDCloudTemplate -Name "WinREWiFi"
            New-OSDCloudWorkspace -WorkspacePath $WorkspacePath
            # Additional configuration for WinRE environments
            $mountPath = Join-Path $script:Paths.Mount "WinRE"
            if (Test-Path $mountPath) {
                Add-WinPEPackages -MountPath $mountPath
                # Add extra WiFi support packages
                $wifiPackages = @("WinPE-Dot3Svc", "WinPE-WiFi-Package")
                foreach ($package in $wifiPackages) {
                    $cabPath = Join-Path $script:Paths.WinPE "amd64\WinPE_OCs\$package.cab"
                    if (Test-Path $cabPath) {
                        try {
                            Add-WindowsPackage -Path $mountPath -PackagePath $cabPath -ErrorAction Stop
                            Write-Verbose "Successfully added WiFi package: $package"
                        } catch {
                            Write-Warning "Failed to add WiFi package $package $_"
                        }
                    } else {
                        Write-Warning "WiFi package not found: $cabPath"
                    }
                }
            }
        } else {
            New-OSDCloudTemplate -Name "WinPE"
            Set-OSDCloudTemplate -Name "WinPE"
            New-OSDCloudWorkspace -WorkspacePath $WorkspacePath
        }
        Optimize-Workspace
    } catch {
        Write-Error "Failed to create OSDCloud template: $_"
        throw
    }
}

function Optimize-Workspace {
    [CmdletBinding()]
    param()
    Write-Verbose "Optimizing workspace by removing unnecessary language folders..."
    $KeepTheseDirs = @('OSDCloud','boot', 'efi', 'en-us', 'sources', 'fonts', 'resources')
    $mediaPath = Join-Path $WorkspacePath "Media"
    Get-ChildItem $mediaPath |
    Where-Object { $_.PSIsContainer -and $_.Name -in $KeepTheseDirs } |
    ForEach-Object {
        # Keep these folders intact
    }
    Get-ChildItem $mediaPath |
    Where-Object { $_.PSIsContainer -and $_.Name -notin $KeepTheseDirs } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $bootPath = Join-Path $mediaPath "Boot"
    if (Test-Path $bootPath) {
        Get-ChildItem $bootPath |
        Where-Object { $_.PSIsContainer -and $_.Name -in $KeepTheseDirs } |
        ForEach-Object {
            # Keep these folders intact
        }
        Get-ChildItem $bootPath |
        Where-Object { $_.PSIsContainer -and $_.Name -notin $KeepTheseDirs } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    $efiBootPath = Join-Path $mediaPath "EFI\Microsoft\Boot"
    if (Test-Path $efiBootPath) {
        Get-ChildItem $efiBootPath |
        Where-Object { $_.PSIsContainer -and $_.Name -in $KeepTheseDirs } |
        ForEach-Object {
            # Keep these folders intact
        }
        Get-ChildItem $efiBootPath |
        Where-Object { $_.PSIsContainer -and $_.Name -notin $KeepTheseDirs } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Verbose "Workspace optimization completed."
}

function Add-CustomContent {
    [CmdletBinding()]
    param()
    if ($CustomWimPath -and (Test-Path $CustomWimPath)) {
        Write-Verbose "Adding custom WIM file..."
        $osPath = Join-Path $script:Paths.Media "OSDCloud\OS"
        if (-not (Test-Path $osPath)) {
            New-Item -Path $osPath -ItemType Directory -Force | Out-Null
        }
        try {
            $destinationWim = Join-Path $osPath "custom.wim"
            Export-WindowsImage -SourceImagePath $CustomWimPath -SourceIndex 1 -DestinationImagePath $destinationWim -CompressionType max
            Write-Verbose "Custom WIM processed and saved to: $destinationWim"
        } catch {
            Write-Error "Failed to process custom WIM: $_"
            throw
        }
    } else {
        Write-Verbose "Custom WIM path not provided or does not exist."
    }
}

function Add-Drivers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StartupScriptPath
    )
    if ($IncludeDrivers) {
        Write-Verbose "Adding driver support and configuring startup script..."
        try {
            # Create the scripts directory in OSDCloud workspace if it doesn't exist
            $scriptsPath = Join-Path $script:Paths.Media "OSDCloud\Scripts"
            if (-not (Test-Path $scriptsPath)) {
                New-Item -Path $scriptsPath -ItemType Directory -Force | Out-Null
            }

            if ($StartupScriptPath -and (Test-Path $StartupScriptPath)) {
                $scriptName = Split-Path $StartupScriptPath -Leaf
                $destinationPath = Join-Path $scriptsPath $scriptName
                Copy-Item -Path $StartupScriptPath -Destination $destinationPath -Force

                $startnetCommand = "PowerShell.exe -ExecutionPolicy Bypass -File X:\OSDCloud\scripts\$scriptName"

                # Call Edit-OSDCloudWinPE with driver injection and startup script configuration
                Edit-OSDCloudWinPE -WorkspacePath $WorkspacePath `
                    -CloudDriver Dell,HP,IntelNet,USB,WiFi `
                    -PSModuleInstall osd,PackageManagement,PSWindowsUpdate,Get-WindowsAutoPilotInfo,PowerShellGet,az,Microsoft.Graph,Microsoft.Entra,Microsoft.Graph.Beta,Microsoft.Entra.Beta `
                    -Startnet $startnetCommand

                # Explicitly update Startnet.cmd with the desired startup command
                $bootPath = Join-Path $script:Paths.Media "OSDCloud\Boot"
                $startnetFile = Join-Path $bootPath "Startnet.cmd"
                if (Test-Path $startnetFile) {
                    Set-Content -Path $startnetFile -Value $startnetCommand -Force
                    Write-Verbose "Startnet.cmd updated with custom startup command."
                } else {
                    Write-Warning "Startnet.cmd not found at $startnetFile"
                }
            } else {
                # If no startup script is specified, inject drivers without startup configuration
                Edit-OSDCloudWinPE -WorkspacePath $WorkspacePath `
                    -CloudDriver Dell,HP,IntelNet,USB,WiFi `
                    -PSModuleInstall osd,PackageManagement,PSWindowsUpdate,Get-WindowsAutoPilotInfo,PowerShellGet,az,Microsoft.Graph,Microsoft.Entra,Microsoft.Graph.Beta,Microsoft.Entra.Beta
            }
            Write-Verbose "Driver support and startup configuration added successfully."
        } catch {
            Write-Warning "Failed to add drivers or configure startup: $_"
        }
    }
}

function Add-CustomScripts {
    [CmdletBinding()]
    param()
    $sourceScriptsPath = "C:\ProgramData\OSDCloud\Config\Scripts"
    $destinationScriptsPath = Join-Path $script:Paths.Media "OSDCloud\Scripts"
    if (Test-Path $sourceScriptsPath) {
        Write-Verbose "Copying custom scripts from $sourceScriptsPath to $destinationScriptsPath..."
        if (-not (Test-Path $destinationScriptsPath)) {
            New-Item -Path $destinationScriptsPath -ItemType Directory -Force | Out-Null
        }
        try {
            Copy-Item -Path (Join-Path $sourceScriptsPath "*") -Destination $destinationScriptsPath -Recurse -Force
            Write-Verbose "Successfully copied custom scripts to the OSDCloud workspace."
        } catch {
            Write-Warning "Failed to copy custom scripts: $_"
        }
    } else {
        Write-Verbose "Custom scripts source directory not found: $sourceScriptsPath"
    }
}

function Dismount-PendingImages {
    [CmdletBinding()]
    param()
    Write-Verbose "Checking for mounted images..."
    Get-WindowsImage -Mounted | ForEach-Object {
        $mountPath = $_.MountPath
        Write-Verbose "Found mounted image at: $mountPath"
        try {
            $saveChanges = $true
            Write-Verbose "Attempting to save and dismount image at $mountPath"
            Dismount-WindowsImage -Path $mountPath -Save -ErrorAction Stop
            Write-Verbose "Successfully dismounted image with changes saved"
        } catch {
            Write-Warning "Failed to dismount image with save at $mountPath. Attempting discard..."
            try {
                Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Stop
                Write-Warning "Image dismounted with changes discarded"
            } catch {
                Write-Error "Failed to dismount image at $mountPath $_"
                throw
            }
        }
    }
}

function New-OSDMedia {
    [CmdletBinding()]
    param()

    # First handle any mounted images
    try {
        Dismount-PendingImages
    } catch {
        Write-Error "Failed to handle mounted images before media creation: $_"
        throw
    }

    if ($CreateISO) {
        Write-Verbose "Creating ISO..."
        try {
            New-OSDCloudISO
            Write-Verbose "ISO creation succeeded."
        } catch {
            Write-Error "Failed to create ISO: $_"
            throw
        }
    }

    if ($CreateUSB) {
        Write-Verbose "Creating USB media..."
        try {
            New-OSDCloudUSB
            Write-Verbose "USB media creation succeeded."
        } catch {
            Write-Error "Failed to create USB media: $_"
            throw
        }
    }
}

#----------------------------------------------------------------------------------
# Main execution block
try {
    Write-Host "Starting OSDCloud build process..." -ForegroundColor Cyan
    Test-Prerequisites
    Import-Module OSD -Force
    New-OSDTemplate
    Add-CustomContent
    Add-CustomScripts
    Add-Drivers -StartupScriptPath $StartupScriptPath

    # Ensure all images are properly dismounted before media creation
    Dismount-PendingImages
    New-OSDMedia

    if ($EnableAutopilot) {
        $autopilotFile = Join-Path (Join-Path $WorkspacePath "Media\OSDCloud\Automate") "AutopilotConfigurationFile.json"
        if (Test-Path $autopilotFile) {
            Write-Verbose "Autopilot configuration file found: $autopilotFile"
        } else {
            Write-Warning "Autopilot enabled but configuration file not found at $autopilotFile."
        }
    }

    Write-Host "OSDCloud build completed successfully" -ForegroundColor Green
} catch {
    Write-Error "Critical error during OSDCloud build: $_"
    throw
}