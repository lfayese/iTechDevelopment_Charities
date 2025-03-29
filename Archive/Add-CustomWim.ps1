<#
.SYNOPSIS
    Creates an OSDCloud ISO with a custom Windows Image (WIM) file.
.DESCRIPTION
    This script creates a complete OSDCloud ISO with a custom Windows Image (WIM) file
    and the iDCMDM customizations. It handles the entire process from template creation
    to ISO generation.
.EXAMPLE
    .\Add-CustomWim.ps1 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud"
.EXAMPLE
    .\Add-CustomWim.ps1 -WimPath "C:\Path\to\your\windows.wim" -OutputPath "C:\OSDCloud" -ISOFileName "CustomOSDCloud.iso"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$WimPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputPath,
    
    [Parameter(Mandatory=$false)]
    [string]$ISOFileName = "OSDCloud-CustomWIM.iso",
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeWinRE
)

# Ensure the OSDCloud module is installed and imported
if (-not (Get-Module -ListAvailable -Name OSD)) {
    Write-Host "Installing OSD PowerShell Module..." -ForeColor Cyan
    Install-Module OSD -Force
}
Import-Module OSD -Force

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
    New-OSDCloudWorkspace -WorkspacePath $workspacePath -Template $templateName -Verbose
} catch {
    Write-Error "Failed to create OSDCloud workspace: $_"
    exit 1
}

# Step 3: Copy the custom WIM file to the workspace
Write-Host "Copying custom WIM file to workspace..." -ForeColor Cyan
$customWimDestination = Join-Path $workspacePath "OSDCloud\custom.wim"
try {
    # Create the OSDCloud directory if it doesn't exist
    $osdCloudDir = Join-Path $workspacePath "OSDCloud"
    if (-not (Test-Path $osdCloudDir)) {
        New-Item -Path $osdCloudDir -ItemType Directory -Force | Out-Null
    }
    
    Copy-Item -Path $WimPath -Destination $customWimDestination -Force
    Write-Host "Custom WIM file copied successfully" -ForeColor Green
} catch {
    Write-Error "Failed to copy custom WIM file: $_"
    exit 1
}

# Step 4: Copy the iDCMDM customization scripts to the workspace
Write-Host "Copying iDCMDM customization scripts..." -ForeColor Cyan
$scriptSourcePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptDestinationPath = Join-Path $workspacePath "OSDCloud"

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
            Copy-Item -Path $sourcePath -Destination (Join-Path $scriptDestinationPath $script) -Force
            Write-Host "Copied $script" -ForeColor Green
        } else {
            Write-Warning "Script not found: $sourcePath"
        }
    }
    
    # Check for Autopilot_Upload.7z and 7za.exe
    $autopilotFiles = @(
        "Autopilot_Upload.7z",
        "7za.exe"
    )
    
    foreach ($file in $autopilotFiles) {
        $sourcePath = Join-Path $scriptSourcePath $file
        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination (Join-Path $scriptDestinationPath $file) -Force
            Write-Host "Copied $file" -ForeColor Green
        } else {
            Write-Warning "Autopilot file not found: $sourcePath. Autopilot functionality may be limited."
        }
    }
} catch {
    Write-Error "Failed to copy customization scripts: $_"
    exit 1
}

# Step 5: Create a startup script to launch the iDCMDM UI
Write-Host "Creating startup script..." -ForeColor Cyan
$startupPath = Join-Path $workspacePath "Startup"
if (-not (Test-Path $startupPath)) {
    New-Item -Path $startupPath -ItemType Directory -Force | Out-Null
}

$startupScriptContent = @"
# OSDCloud Startup Script
Write-Host "Starting iDCMDM OSDCloud..." -ForeColor Cyan
Start-Process PowerShell -ArgumentList "-NoL -ExecutionPolicy Bypass -File X:\OSDCloud\iDCMDMUI.ps1" -Wait
"@

$startupScriptPath = Join-Path $startupPath "StartOSDCloud.ps1"
$startupScriptContent | Out-File -FilePath $startupScriptPath -Encoding utf8 -Force

# Step 6: Create the ISO
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

# Step 7: Clean up temporary files
Write-Host "Cleaning up temporary files..." -ForeColor Cyan
try {
    Remove-Item -Path $tempWorkspacePath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Temporary files cleaned up" -ForeColor Green
} catch {
    Write-Warning "Failed to clean up temporary files: $_"
}

Write-Host "`nSUMMARY:" -ForeColor Yellow
Write-Host "=========" -ForeColor Yellow
Write-Host "Custom Windows Image: $($wimInfo.ImageName)" -ForeColor White
Write-Host "ISO File: $isoPath" -ForeColor White
Write-Host "ISO Size: $([math]::Round((Get-Item $isoPath).Length / 1GB, 2)) GB" -ForeColor White
Write-Host "`nThe ISO includes:" -ForeColor Yellow
Write-Host "- Custom Windows Image (custom.wim)" -ForeColor White
Write-Host "- iDCMDM OSDCloud customizations" -ForeColor White
Write-Host "- Autopilot integration" -ForeColor White
if ($IncludeWinRE) {
    Write-Host "- WinRE for WiFi support" -ForeColor White
}

Write-Host "`nTo use this ISO:" -ForeColor Yellow
Write-Host "1. Burn the ISO to a USB drive using Rufus or similar tool" -ForeColor White
Write-Host "2. Boot the target computer from the USB drive" -ForeColor White
Write-Host "3. The iDCMDM UI will start automatically" -ForeColor White
Write-Host "4. Select 'Start-OSDCloud' and follow the prompts" -ForeColor White
Write-Host "5. The custom Windows image will be automatically detected and available for selection" -ForeColor White