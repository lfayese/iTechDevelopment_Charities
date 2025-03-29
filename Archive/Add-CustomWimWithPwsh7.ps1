<#
.SYNOPSIS
    Creates an OSDCloud ISO with a custom Windows Image (WIM) file and PowerShell 7 support.
.DESCRIPTION
    This script creates a complete OSDCloud ISO with a custom Windows Image (WIM) file,
    PowerShell 7 support, and the iDCMDM customizations. It handles the entire process from
    template creation to ISO generation.
.EXAMPLE
    .\Add-CustomWimWithPwsh7.ps1 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud"
.EXAMPLE
    .\Add-CustomWimWithPwsh7.ps1 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud" -ISOFileName "CustomOSDCloud.iso"
.EXAMPLE
    .\Add-CustomWimWithPwsh7.ps1 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud" -IncludeWinRE
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$WimPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputPath,
    
    [Parameter(Mandatory=$false)]
    [string]$ISOFileName = "OSDCloudCustomWIM.iso",
    
    [Parameter(Mandatory=$false)]
    [string]$PowerShell7Url = "https://github.com/PowerShell/PowerShell/releases/download/v7.5.0/PowerShell-7.5.0-win-x64.zip",
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeWinRE,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipCleanup
)

#Requires -RunAsAdministrator

# Function to efficiently copy WIM files using Robocopy
function Copy-WimFileEfficiently {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        
        [Parameter(Mandatory=$false)]
        [string]$NewName = $null
    )
    
    Write-Host "Copying WIM file to $DestinationPath..." -ForeColor Cyan
    
    # Create destination directory if it doesn't exist
    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }
    
    # Get source file details
    $sourceDir = Split-Path -Parent $SourcePath
    $sourceFileName = Split-Path -Leaf $SourcePath
    
    # Use Robocopy for better performance with large files
    $robocopyArgs = @(
        "`"$sourceDir`"",
        "`"$destDir`"",
        "`"$sourceFileName`"",
        "/J",          # Unbuffered I/O for large file optimization
        "/NP",         # No progress - avoid screen clutter
        "/R:2",        # Retry 2 times
        "/W:5"         # Wait 5 seconds between retries
    )
    
    $robocopyProcess = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
    
    # Robocopy exit codes: 0-7 are success (8+ are failures)
    if ($robocopyProcess.ExitCode -lt 8) {
        # Rename if requested
        if ($NewName) {
            $tempPath = Join-Path $destDir $sourceFileName
            $finalPath = Join-Path $destDir $NewName
            Rename-Item -Path $tempPath -NewName $NewName -Force
            Write-Host "WIM file renamed to $NewName" -ForeColor Green
        }
        
        Write-Host "WIM file copied successfully" -ForeColor Green
        return $true
    } else {
        Write-Error "Failed to copy WIM file. Robocopy exit code: $($robocopyProcess.ExitCode)"
        return $false
    }
}

# Ensure the OSDCloud module is installed and imported
if (-not (Get-Module -ListAvailable -Name OSD)) {
    Write-Host "Installing OSD PowerShell Module..." -ForeColor Cyan
    Install-Module OSD -Force
}
# Import the OSD module with the -Global parameter
Import-Module OSD -Global -Force

# Validate parameters
if (-not (Test-Path $WimPath)) {
    Write-Error "The specified WIM file does not exist: $WimPath"
    exit 1
}

if (-not (Test-Path $OutputPath -PathType Container)) {
    try {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Host "Created output directory: $OutputPath" -ForeColor Green
    } catch {
        Write-Error "Failed to create output directory: $_"
        exit 1
    }
}

# Check if the file is a valid WIM
try {
    $wimInfo = Get-WindowsImage -ImagePath $WimPath -Index 1 -ErrorAction Stop
    Write-Host "Found Windows image: $($wimInfo.ImageName)" -ForeColor Green
    Write-Host "Image Description: $($wimInfo.ImageDescription)" -ForeColor Green
    Write-Host "Image Size: $([math]::Round($wimInfo.ImageSize / 1GB, 2)) GB" -ForeColor Green
} catch {
    Write-Error "The specified file is not a valid Windows Image file: $_"
    exit 1
}

# Create a temporary directory for our workspace
$tempWorkspacePath = Join-Path $OutputPath "TempWorkspace"
if (Test-Path $tempWorkspacePath) {
    Remove-Item -Path $tempWorkspacePath -Recurse -Force
}
New-Item -Path $tempWorkspacePath -ItemType Directory -Force | Out-Null

# Download PowerShell 7 if needed
$PowerShell7File = Join-Path $tempWorkspacePath "PowerShell-7.5.0-win-x64.zip"
if (-not (Test-Path $PowerShell7File)) {
    Write-Host "Downloading PowerShell 7..." -ForeColor Cyan
    try {
        Invoke-WebRequest -Uri $PowerShell7Url -OutFile $PowerShell7File -UseBasicParsing
        Write-Host "PowerShell 7 downloaded successfully" -ForeColor Green
    } catch {
        Write-Error "Failed to download PowerShell 7: $_"
        exit 1
    }
}

# Settings for WinPE customization
$WinPE_BuildFolder = Join-Path $tempWorkspacePath "WinPE_x64"
$WinPE_Architecture = "amd64" # Or x86
$WinPE_MountFolder = Join-Path $tempWorkspacePath "Mount"
$ADK_Path = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$WinPE_ADK_Path = $ADK_Path + "\Windows Preinstallation Environment"
$WinPE_OCs_Path = $WinPE_ADK_Path + "\$WinPE_Architecture\WinPE_OCs"
$DISM_Path = $ADK_Path + "\Deployment Tools" + "\$WinPE_Architecture\DISM"
$OSCDIMG_Path = $ADK_Path + "\Deployment Tools" + "\$WinPE_Architecture\Oscdimg"

# Validate ADK installation and required paths
If (!(Test-path $ADK_Path)){ Write-Warning "ADK Path does not exist, aborting..."; Break }
If (!(Test-path $WinPE_ADK_Path)){ Write-Warning "WinPE ADK Path does not exist, aborting..."; Break }
If (!(Test-path $OSCDIMG_Path)){ Write-Warning "OSCDIMG Path does not exist, aborting..."; Break }

# Step 1: Create a new OSDCloud template
Write-Host "Creating OSDCloud template..." -ForeColor Cyan
$templateName = "iDCMDMCustomWIM"
try {
    New-OSDCloudTemplate -Name $templateName -Verbose
} catch {
    Write-Error "Failed to create OSDCloud template: $_"
    exit 1
}

# Step 2: Create a new OSDCloud workspace
Write-Host "Creating OSDCloud workspace..." -ForeColor Cyan
try {
    $workspacePath = Join-Path $tempWorkspacePath "OSDCloudWorkspace"
    New-OSDCloudWorkspace -WorkspacePath $workspacePath -Verbose
} catch {
    Write-Error "Failed to create OSDCloud workspace: $_"
    exit 1
}

# Step 3: Copy the custom WIM file to the workspace
Write-Host "Copying custom WIM file to workspace..." -ForeColor Cyan
try {
    # Create the OS directory in Media\OSDCloud
    $osDir = Join-Path $workspacePath "Media\OSDCloud\OS"
    if (-not (Test-Path $osDir)) {
        New-Item -Path $osDir -ItemType Directory -Force | Out-Null
    }
    
    # Copy the WIM file to the new location
    Copy-Item -Path $WimPath -Destination "$osDir\CustomImage.wim" -Force
    
    # Also maintain a copy in the OSDCloud directory for backward compatibility
    $osdCloudDir = Join-Path $workspacePath "OSDCloud"
    if (-not (Test-Path $osdCloudDir)) {
        New-Item -Path $osdCloudDir -ItemType Directory -Force | Out-Null
    }
    Copy-Item -Path $WimPath -Destination (Join-Path $osdCloudDir "custom.wim") -Force
    
    Write-Host "Custom WIM file copied successfully" -ForeColor Green
} catch {
    Write-Error "Failed to copy custom WIM file: $_"
    exit 1
}

# Step 4: Create Automate directory structure
Write-Host "Creating Automate directory structure..." -ForeColor Cyan
$automateDir = Join-Path $workspacePath "Media\OSDCloud\Automate"
if (-not (Test-Path $automateDir)) {
    New-Item -Path $automateDir -ItemType Directory -Force | Out-Null
}

# Step 5: Copy the iDCMDM customization scripts to the workspace
Write-Host "Copying iDCMDM customization scripts..." -ForeColor Cyan
$scriptSourcePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptDestinationPath = Join-Path $workspacePath "OSDCloud"
$automateScriptDestinationPath = Join-Path $automateDir "Scripts"

if (-not (Test-Path $automateScriptDestinationPath)) {
    New-Item -Path $automateScriptDestinationPath -ItemType Directory -Force | Out-Null
}

try {
    # Copy the main scripts
    $scriptsToCopy = @(
        "iDCMDMUI.ps1",
        "iDcMDMOSDCloudGUI.ps1",
        "Autopilot.ps1"
    )
    
    foreach ($script in $scriptsToCopy) {
        $sourcePath = Join-Path $scriptSourcePath $script
        if (Test-Path $sourcePath) {
            # Copy to OSDCloud directory
            Copy-Item -Path $sourcePath -Destination (Join-Path $scriptDestinationPath $script) -Force
            
            # Also copy to Automate directory
            Copy-Item -Path $sourcePath -Destination (Join-Path $automateScriptDestinationPath $script) -Force
            
            # Update script to prefer PowerShell 7
            $scriptContent = Get-Content -Path $sourcePath -Raw
            $pwsh7Wrapper = @"
# PowerShell 7 wrapper
try {
    # Check if PowerShell 7 is available
    if (Test-Path -Path 'X:\Program Files\PowerShell\7\pwsh.exe') {
        # Execute the script in PowerShell 7
        & 'X:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -ExecutionPolicy Bypass -File `$PSCommandPath
        exit `$LASTEXITCODE
    }
} catch {
    Write-Warning "Failed to run with PowerShell 7, falling back to PowerShell 5: `$_"
    # Continue with PowerShell 5
}

# Original script content follows
$scriptContent
"@
            $pwsh7Wrapper | Out-File -FilePath (Join-Path $scriptDestinationPath $script) -Encoding utf8 -Force
            $pwsh7Wrapper | Out-File -FilePath (Join-Path $automateScriptDestinationPath $script) -Encoding utf8 -Force
            
            Write-Host "Copied and updated $script" -ForeColor Green
        } else {
            Write-Warning "Script not found: $sourcePath"
        }
    }
    
    # Create Autopilot directory structure
    Write-Host "Setting up Autopilot directory structure..." -ForeColor Cyan
    $autopilotSourceDir = Join-Path $scriptSourcePath "Autopilot"
    $autopilotDestDir = Join-Path $scriptDestinationPath "Autopilot"
    $automateAutopilotDestDir = Join-Path $automateScriptDestinationPath "Autopilot"
    
    if (-not (Test-Path $autopilotDestDir)) {
        New-Item -Path $autopilotDestDir -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Test-Path $automateAutopilotDestDir)) {
        New-Item -Path $automateAutopilotDestDir -ItemType Directory -Force | Out-Null
    }
    
    # Copy Autopilot files
    if (Test-Path $autopilotSourceDir) {
        # Copy all files from Autopilot directory
        $autopilotFiles = Get-ChildItem -Path $autopilotSourceDir -File
        
        foreach ($file in $autopilotFiles) {
            # Copy to OSDCloud directory
            Copy-Item -Path $file.FullName -Destination (Join-Path $autopilotDestDir $file.Name) -Force
            
            # Also copy to Automate directory
            Copy-Item -Path $file.FullName -Destination (Join-Path $automateAutopilotDestDir $file.Name) -Force
            
            # Update PowerShell scripts to prefer PowerShell 7
            if ($file.Extension -eq ".ps1") {
                $scriptContent = Get-Content -Path $file.FullName -Raw
                $pwsh7Wrapper = @"
# PowerShell 7 wrapper
try {
    # Check if PowerShell 7 is available
    if (Test-Path -Path 'X:\Program Files\PowerShell\7\pwsh.exe') {
        # Execute the script in PowerShell 7
        & 'X:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -ExecutionPolicy Bypass -File `$PSCommandPath
        exit `$LASTEXITCODE
    }
} catch {
    Write-Warning "Failed to run with PowerShell 7, falling back to PowerShell 5: $_"
    # Continue with PowerShell 5
}

# Original script content follows
$scriptContent
"@
                $pwsh7Wrapper | Out-File -FilePath (Join-Path $autopilotDestDir $file.Name) -Encoding utf8 -Force
                $pwsh7Wrapper | Out-File -FilePath (Join-Path $automateAutopilotDestDir $file.Name) -Encoding utf8 -Force
            }
            
            Write-Host "Copied Autopilot file: $($file.Name)" -ForeColor Green
        }
    } else {
        Write-Warning "Autopilot directory not found: $autopilotSourceDir"
    }
    
    # Check for Autopilot_Upload.7z and 7za.exe
    $autopilotFiles = @(
        "Autopilot_Upload.7z",
        "7za.exe"
    )
    
    foreach ($file in $autopilotFiles) {
        $sourcePath = Join-Path $scriptSourcePath $file
        if (Test-Path $sourcePath) {
            # Copy to OSDCloud directory
            Copy-Item -Path $sourcePath -Destination (Join-Path $scriptDestinationPath $file) -Force
            
            # Also copy to Automate directory
            Copy-Item -Path $sourcePath -Destination (Join-Path $automateScriptDestinationPath $file) -Force
            
            Write-Host "Copied $file" -ForeColor Green
        } else {
            Write-Warning "Autopilot file not found: $sourcePath. Autopilot functionality may be limited."
        }
    }
} catch {
    Write-Error "Failed to copy customization scripts: $_"
    exit 1
}

# Step 6: Create a startup script to launch the iDCMDM UI
Write-Host "Creating startup script..." -ForeColor Cyan
$startupPath = Join-Path $workspacePath "Startup"
if (-not (Test-Path $startupPath)) {
    New-Item -Path $startupPath -ItemType Directory -Force | Out-Null
}

$startupScriptContent = @"
# OSDCloud Startup Script
Write-Host "Starting iDCMDM OSDCloud..." -ForeColor Cyan

# Try to use PowerShell 7 if available
if (Test-Path -Path 'X:\Program Files\PowerShell\7\pwsh.exe') {
    Write-Host "Using PowerShell 7..." -ForeColor Green
    $scriptPath = Get-ChildItem -Path 'X:\' -Recurse -Filter 'iDCMDMUI.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($scriptPath) {
        Start-Process 'X:\Program Files\PowerShell\7\pwsh.exe' -ArgumentList "-NoL -ExecutionPolicy Bypass -File $scriptPath" -Wait
    } else {
        Write-Warning "iDCMDMUI.ps1 not found in X:\ drive"
    }
} else {
    Write-Host "Using PowerShell 5..." -ForeColor Yellow
    $scriptPath = Get-ChildItem -Path 'X:\' -Recurse -Filter 'iDCMDMUI.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($scriptPath) {
        Start-Process PowerShell -ArgumentList "-NoL -ExecutionPolicy Bypass -File $scriptPath" -Wait
    } else {
        Write-Warning "iDCMDMUI.ps1 not found in X:\ drive"
    }
}
"@

$startupScriptPath = Join-Path $startupPath "StartOSDCloud.ps1"
$startupScriptContent | Out-File -FilePath $startupScriptPath -Encoding utf8 -Force

# Step 7: Customize the WinPE boot.wim with PowerShell 7
Write-Host "Customizing WinPE boot.wim with PowerShell 7..." -ForeColor Cyan

# Delete existing WinPE build folder (if exist)
try {
    if (Test-Path -path $WinPE_BuildFolder) { Remove-Item -Path $WinPE_BuildFolder -Recurse -Force -ErrorAction Stop }
} catch {
    Write-Warning "Error: $($_.Exception.Message)"
    Write-Warning "Most common reason is existing WIM still mounted, use DISM /Cleanup-Wim to clean up and run script again"
    Break
}

# Create Mount folder
New-Item -Path $WinPE_MountFolder -ItemType Directory -Force

# Make a copy of the WinPE boot image from the workspace
if (!(Test-Path -path "$WinPE_BuildFolder\Sources")) { New-Item "$WinPE_BuildFolder\Sources" -Type Directory -Force }
$bootWimPath = Join-Path $workspacePath "Media\Sources\boot.wim"
Copy-Item $bootWimPath "$WinPE_BuildFolder\Sources\boot.wim" -Force

# Mount the WinPE image
$WimFile = "$WinPE_BuildFolder\Sources\boot.wim"
try {
    Mount-WindowsImage -ImagePath $WimFile -Path $WinPE_MountFolder -Index 1 -ErrorAction Stop
} catch {
    Write-Warning "Failed to mount the WinPE image: $($_.Exception.Message)"
    Break
}

# Add native WinPE optional components (using ADK version of dism.exe instead of Add-WindowsPackage)
# Install WinPE-WMI before you install WinPE-NetFX (dependency)
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\WinPE-WMI.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\en-us\WinPE-WMI_en-us.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\WinPE-NetFX.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\en-us\WinPE-NetFX_en-us.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\WinPE-PowerShell.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\en-us\WinPE-PowerShell_en-us.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\WinPE-DismCmdlets.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\en-us\WinPE-DismCmdlets_en-us.cab"

# Add PowerShell 7
Write-Host "Adding PowerShell 7 to WinPE..." -ForeColor Cyan
Expand-Archive -Path $PowerShell7File -DestinationPath "$WinPE_MountFolder\Program Files\PowerShell\7" -Force

# Update the offline environment PATH for PowerShell 7
$HivePath = "$WinPE_MountFolder\Windows\System32\config\SYSTEM"
try {
    reg load "HKLM\OfflineWinPE" $HivePath
    Start-Sleep -Seconds 5

    # Add PowerShell 7 Paths to Path and PSModulePath
    $RegistryKey = "HKLM:\OfflineWinPE\ControlSet001\Control\Session Manager\Environment"
    $CurrentPath = (Get-Item -path $RegistryKey).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $NewPath = $CurrentPath + ";%ProgramFiles%\PowerShell\7\"
    $null = New-ItemProperty -Path $RegistryKey -Name "Path" -PropertyType ExpandString -Value $NewPath -Force

    $CurrentPSModulePath = (Get-Item -path $RegistryKey).GetValue('PSModulePath', '', 'DoNotExpandEnvironmentNames')
    $NewPSModulePath = $CurrentPSModulePath + ";%ProgramFiles%\PowerShell\;%ProgramFiles%\PowerShell\7\;%SystemRoot%\system32\config\systemprofile\Documents\PowerShell\Modules\"
    $null = New-ItemProperty -Path $RegistryKey -Name "PSModulePath" -PropertyType ExpandString -Value $NewPSModulePath -Force

    # Add additional environment variables for PowerShell Gallery Support
    $APPDATA = "%SystemRoot%\System32\Config\SystemProfile\AppData\Roaming"
    $null = New-ItemProperty -Path $RegistryKey -Name "APPDATA" -PropertyType String -Value $APPDATA -Force

    $HOMEDRIVE = "%SystemDrive%"
    $null = New-ItemProperty -Path $RegistryKey -Name "HOMEDRIVE" -PropertyType String -Value $HOMEDRIVE -Force

    $HOMEPATH = "%SystemRoot%\System32\Config\SystemProfile"
    $null = New-ItemProperty -Path $RegistryKey -Name "HOMEPATH" -PropertyType String -Value $HOMEPATH -Force

    $LOCALAPPDATA = "%SystemRoot%\System32\Config\SystemProfile\AppData\Local"
    $null = New-ItemProperty -Path $RegistryKey -Name "LOCALAPPDATA" -PropertyType String -Value $LOCALAPPDATA -Force

    # Cleanup (to prevent access denied issue unloading the registry hive)
    Remove-Variable -Name RegistryKey -ErrorAction SilentlyContinue
    [System.GC]::Collect()
    Start-Sleep -Seconds 5

    # Unload the registry hive
    reg unload "HKLM\OfflineWinPE"
} catch {
    Write-Warning "Registry operation failed: $($_.Exception.Message)"
    # Try to unload registry if it was loaded
    reg unload "HKLM\OfflineWinPE" 2>$null
    Break
}

# Step 8: Copy OSDCloud scripts to the WinPE image
Write-Host "Copying OSDCloud scripts to WinPE image..." -ForeColor Cyan
$winpeOSDCloudDir = Join-Path $WinPE_MountFolder "OSDCloud"
if (-not (Test-Path $winpeOSDCloudDir)) {
    New-Item -Path $winpeOSDCloudDir -ItemType Directory -Force | Out-Null
}

# Copy OSDCloud directory contents to WinPE
Copy-Item -Path (Join-Path $workspacePath "OSDCloud\*") -Destination $winpeOSDCloudDir -Recurse -Force

# Create Autopilot directory in WinPE if it doesn't exist
$winpeAutopilotDir = Join-Path $winpeOSDCloudDir "Autopilot"
if (-not (Test-Path $winpeAutopilotDir)) {
    New-Item -Path $winpeAutopilotDir -ItemType Directory -Force | Out-Null
}

# Copy PCPKsp.dll for Autopilot hash generation if it exists
$pcpkspSource = Join-Path $scriptSourcePath "Autopilot\PCPKsp.dll"
if (Test-Path $pcpkspSource) {
    Copy-Item -Path $pcpkspSource -Destination $winpeAutopilotDir -Force
    Write-Host "Copied PCPKsp.dll for Autopilot hash generation" -ForeColor Green
}

@'
[LaunchApps]
cmd /c "if exist ""%ProgramFiles%\PowerShell\7\pwsh.exe"" (
  ""%ProgramFiles%\PowerShell\7\pwsh.exe"" -NoExit -ExecutionPolicy Bypass -Command ""& {
    $files = Get-ChildItem -Path 'X:\' -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue;
    $scriptPath = $files | Where-Object { $_.Name -ieq 'iDCMDMUI.ps1' } | Select-Object -First 1 -ExpandProperty FullName;
    $autopilotPath = $files | Where-Object { $_.Name -ieq 'Autopilot.ps1' } | Select-Object -First 1 -ExpandProperty FullName;
    $guiPath = $files | Where-Object { $_.Name -ieq 'iDcMDMOSDCloudGUI.ps1' } | Select-Object -First 1 -ExpandProperty FullName;
    if ($autopilotPath) { Import-Module $autopilotPath -Force -Global };
    if ($guiPath) { Import-Module $guiPath -Force -Global };
    if ($scriptPath) { Set-Location (Split-Path $scriptPath -Parent); & $scriptPath } else { Write-Warning 'Required scripts not found.' }
  }""
) else (
  ""%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"" -NoExit -ExecutionPolicy Bypass -Command ""& {
    $files = Get-ChildItem -Path 'X:\' -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue;
    $scriptPath = $files | Where-Object { $_.Name -ieq 'iDCMDMUI.ps1' } | Select-Object -First 1 -ExpandProperty FullName;
    $autopilotPath = $files | Where-Object { $_.Name -ieq 'Autopilot.ps1' } | Select-Object -First 1 -ExpandProperty FullName;
    $guiPath = $files | Where-Object { $_.Name -ieq 'iDcMDMOSDCloudGUI.ps1' } | Select-Object -First 1 -ExpandProperty FullName;
    if ($autopilotPath) { Import-Module $autopilotPath -Force -Global };
    if ($guiPath) { Import-Module $guiPath -Force -Global };
    if ($scriptPath) { Set-Location (Split-Path $scriptPath -Parent); & $scriptPath } else { Write-Warning 'Required scripts not found.' }
  }""
)"
'@ | Out-File "$WinPE_MountFolder\Windows\System32\winpeshl.ini" -Encoding utf8 -Force

# Write unattend.xml file to change screen resolution
@'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http
        ://schemas.microsoft.com/WMIConfig/2002/State">
            <Display>
                <ColorDepth>32</ColorDepth>
                <HorizontalResolution>1280</HorizontalResolution>
                <RefreshRate>60</RefreshRate>
                <VerticalResolution>720</VerticalResolution>
            </Display>
        </component>
    </settings>
</unattend>
'@ | Out-File "$WinPE_MountFolder\Unattend.xml" -Encoding utf8 -Force

# Unmount the WinPE image and save changes
try {
    Dismount-WindowsImage -Path $WinPE_MountFolder -Save -ErrorAction Stop
    Write-Host "Successfully saved WinPE image with PowerShell 7" -ForegroundColor Green
} catch {
    Write-Warning "Failed to unmount and save the WinPE image: $($_.Exception.Message)"
    Break
}

# Copy the modified boot.wim back to the workspace
Copy-Item "$WinPE_BuildFolder\Sources\boot.wim" $bootWimPath -Force

# Step 8.5: Clean up language directories to reduce ISO size
Write-Host "Cleaning up language directories to reduce ISO size..." -ForeColor Cyan
$KeepTheseDirs = @('boot','efi','en-us','sources','fonts','resources', 'OSDCloud')

# Clean Media folder
Get-ChildItem "$workspacePath\Media" | Where-Object {$_.PSIsContainer} | Where-Object {$_.Name -notin $KeepTheseDirs} | Remove-Item -Recurse -Force

# Clean Boot folder
Get-ChildItem "$workspacePath\Media\Boot" | Where-Object {$_.PSIsContainer} | Where-Object {$_.Name -notin $KeepTheseDirs} | Remove-Item -Recurse -Force

# Clean EFI Boot folder 
Get-ChildItem "$workspacePath\Media\EFI\Microsoft\Boot" | Where-Object {$_.PSIsContainer} | Where-Object {$_.Name -notin $KeepTheseDirs} | Remove-Item -Recurse -Force

Write-Host "Language cleanup complete" -ForeColor Green

# Step 9: Create the ISO
Write-Host "Creating OSDCloud ISO..." -ForeColor Cyan
$isoPath = Join-Path $OutputPath $ISOFileName
try {
    $params = @{
        WorkspacePath = $workspacePath
        BootType = if ($IncludeWinRE) { 'UEFI+BIOS+WinRE' } else { 'UEFI+BIOS' }
        Destination = $isoPath
    }
    
    New-OSDCloudISO @params -Verbose
    
    if (Test-Path $isoPath) {
        Write-Host "ISO created successfully: $isoPath" -ForeColor Green
    } else {
        Write-Error "ISO creation failed. Output file not found."
        exit 1
    }
} catch {
    Write-Error "Failed to create ISO: $_"
    exit 1
}

# Step 10: Clean up temporary files
if (-not $SkipCleanup) {
    Write-Host "Cleaning up temporary files..." -ForeColor Cyan
    try {
        Remove-Item -Path $tempWorkspacePath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Temporary files cleaned up" -ForeColor Green
    } catch {
        Write-Warning "Failed to clean up temporary files: $_"
    }
}

Write-Host "`nSUMMARY:" -ForeColor Yellow
Write-Host "=========" -ForeColor Yellow
Write-Host "Custom Windows Image: $($wimInfo.ImageName)" -ForeColor White
Write-Host "ISO File: $isoPath" -ForeColor White
Write-Host "ISO Size: $([math]::Round((Get-Item $isoPath).Length / 1GB, 2)) GB" -ForeColor White
Write-Host "`nThe ISO includes:" -ForeColor Yellow
Write-Host "- Custom Windows Image (custom.wim)" -ForeColor White
Write-Host "- PowerShell 7 support" -ForeColor White
Write-Host "- iDCMDM OSDCloud customizations" -ForeColor White
Write-Host "- Autopilot integration with 4K hash generation" -ForeColor White
if ($IncludeWinRE) {
    Write-Host "- WinRE for WiFi support" -ForeColor White
}

Write-Host "`nTo use this ISO:" -ForeColor Yellow
Write-Host "1. Burn the ISO to a USB drive using Rufus or similar tool" -ForeColor White
Write-Host "2. Boot the target computer from the USB drive" -ForeColor White
Write-Host "3. The iDCMDM UI will automatically start with PowerShell 7" -ForeColor White
Write-Host "4. Select 'Start-OSDCloud' to deploy the custom Windows image" -ForeColor White
Write-Host "   or 'Upload Device to Autopilot' to register the device" -ForeColor White