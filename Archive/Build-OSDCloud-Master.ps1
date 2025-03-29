# ================================
# Master OSDCloud Deployment Script - Windows 11 24H2 (Optimized & Fixed)
# ================================

# --- Helper Functions ---

function New-Folder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
}

function Set-ScriptFile {
    param(
        [string]$FilePath,
        [string]$Content
    )
    $Content | Set-Content -Path $FilePath -Force -ErrorAction Stop
}

function Confirm-Yes {
    param(
        [string]$Prompt
    )
    $response = Read-Host -Prompt $Prompt
    return $response.Trim().ToUpper() -eq 'Y'
}

function Install-RequiredModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [hashtable]$InstalledModules
    )

    if ($InstalledModules.ContainsKey($ModuleName)) {
        Write-Host "ℹ️ Module '$ModuleName' is already installed."
    } else {
        try {
            if (-not $InstalledModules.ContainsKey("PowerShellGet")) {
                Write-Warning "PowerShellGet module not found in cache. Installing..."
                Install-Module PowerShellGet -Force -AllowClobber -Scope AllUsers -ErrorAction Stop -Confirm:$false
                $InstalledModules["PowerShellGet"] = $true
            }
            Install-Module -Name $ModuleName -Force -AllowClobber -Scope AllUsers -ErrorAction Stop -Confirm:$false
            Import-Module -Name $ModuleName -Force -ErrorAction Stop
            Write-Host "✅ Successfully installed module: $ModuleName"
            $InstalledModules[$ModuleName] = $true
        } catch {
            Write-Warning "⚠️ Failed to install $ModuleName. Error: $($_.Exception.Message)"
            throw
        }
    }
}

# --- Main Script ---

$requiredModules = @(
    'OSD', 'PackageManagement', 'PSWindowsUpdate', 'Get-WindowsAutoPilotInfo',
    'PowerShellGet', 'Az', 'Microsoft.Graph', 'Microsoft.Entra',
    'Microsoft.Graph.Beta', 'Microsoft.Entra.Beta'
)

$installedModuleNames = @{}
Get-Module -ListAvailable | ForEach-Object { $installedModuleNames[$_.Name] = $true }

foreach ($module in $requiredModules) {
    Install-RequiredModule -ModuleName $module -InstalledModules $installedModuleNames
}

if ($installedModuleNames['OSD']) {
    Import-Module OSD -Force
} else {
    Write-Error "❌ OSD Module not found. Please install it before proceeding."
}

# === [ 1. Create OSDCloud Workspace ] ===
$workspace      = "G:\OSDCloudProd"
$customFolder   = "G:\CustomFiles"
$wimFile        = "$customFolder\Windows11_24H2_Custom.wim"
$mediaFolder    = "$workspace\Media"
$osFolder       = "$mediaFolder\OSDCloud\OS"
$automateFolder = "$mediaFolder\OSDCloud\Automate"

Write-Host "Creating/Reinitializing workspace at $workspace" -ForegroundColor Cyan
try {
    New-OSDCloudWorkspace -WorkspacePath $workspace
    Write-Host "✅ Workspace setup completed at $workspace" -ForegroundColor Green
} catch {
    Write-Error "❌ Failed to create/reinitialize workspace: $($_.Exception.Message)"
}

$foldersToCheck = @($workspace, $mediaFolder, $customFolder, $osFolder, $automateFolder)
foreach ($folder in $foldersToCheck) {
    New-Folder -Path $folder
}

# === [ 2. Cleanup OSDCloud Workspace Media ] ===
$KeepTheseDirs = @('boot','efi','en-us','sources','fonts','resources','OSDCloud')
$mediaPaths = @(
    "$workspace\Media",
    "$workspace\Media\Boot",
    "$workspace\Media\EFI\Microsoft\Boot"
)
foreach ($path in $mediaPaths) {
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Directory -Exclude $KeepTheseDirs -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# === [ 3. Setup custom scripts ] ===
$scriptMappings = @(
    @{ Source = "$customFolder\iTechDcUI.ps1"; Destination = "$automateFolder\iTechDcUI.ps1" },
    @{ Source = "$customFolder\iTechDcOSDCloudGUI.ps1"; Destination = "$automateFolder\iTechDcOSDCloudGUI.ps1" },
    @{ Source = "$customFolder\Autopilot.ps1"; Destination = "$automateFolder\Autopilot.ps1" },
    @{ Source = "$customFolder\OSDCloud_Tenant_Lockdown.ps1"; Destination = "$automateFolder\OSDCloud_Tenant_Lockdown.ps1" },
    @{ Source = "$customFolder\OSDCloud_UploadAutopilot.ps1"; Destination = "$automateFolder\OSDCloud_UploadAutopilot.ps1" }
)

foreach ($map in $scriptMappings) {
    if (Test-Path $map.Source) {
        try {
            Copy-Item -Path $map.Source -Destination $map.Destination -Force -ErrorAction Stop
            Write-Host "✅ Copied $($map.Source) to $($map.Destination)" -ForegroundColor Green
        } catch {
            Write-Error "Failed to copy $($map.Source): $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Source file '$($map.Source)' not found."
    }
}

# === [ 4. Configure WinPE Startnet ] ===
$startnetContent = @'
@ECHO OFF
wpeinit
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
cd\
title OSDCloud Deployment Environment
PowerShell -NoL -ExecutionPolicy Bypass -Command ""& {
    if (Test-Path 'X:\Automate\iTechDcUI.ps1') { . X:\Automate\iTechDcUI.ps1 }
    elseif (Test-Path 'X:\OSDCloud\Automate\iTechDcUI.ps1') { . X:\OSDCloud\Automate\iTechDcUI.ps1 }
    if (Test-Path 'X:\Automate\Autopilot.ps1') { . X:\Automate\Autopilot.ps1 }
    elseif (Test-Path 'X:\OSDCloud\Automate\Autopilot.ps1') { . X:\OSDCloud\Automate\Autopilot.ps1 }
    if (Test-Path 'X:\Automate\OSDCloud_Tenant_Lockdown.ps1') { . X:\Automate\OSDCloud_Tenant_Lockdown.ps1 }
    elseif (Test-Path 'X:\OSDCloud\Automate\OSDCloud_Tenant_Lockdown.ps1') { . X:\OSDCloud\Automate\OSDCloud_Tenant_Lockdown.ps1 }
    if (Test-Path 'X:\Automate\OSDCloud_UploadAutopilot.ps1') { . X:\Automate\OSDCloud_UploadAutopilot.ps1 }
    elseif (Test-Path 'X:\OSDCloud\Automate\OSDCloud_UploadAutopilot.ps1') { . X:\OSDCloud\Automate\OSDCloud_UploadAutopilot.ps1 }
    if (Test-Path 'X:\Automate\iTechDcOSDCloudGUI.ps1') { . X:\Automate\iTechDcOSDCloudGUI.ps1 }
    elseif (Test-Path 'X:\OSDCloud\Automate\iTechDcOSDCloudGUI.ps1') { . X:\OSDCloud\Automate\iTechDcOSDCloudGUI.ps1 }
}"
'@

# === [ 5. Copy Custom WIM File ] ===
$useCustomWim = $false
if (Test-Path $wimFile) {
    New-Folder -Path $osFolder
    Copy-Item -Path $wimFile -Destination "$osFolder\CustomImage.wim" -Force -ErrorAction Stop
    $useCustomWim = $true
    Write-Host "✓ Custom WIM copied to $osFolder" -ForegroundColor Green
} else {
    Write-Host "Info: No custom WIM found at $wimFile - will use standard Microsoft images" -ForegroundColor Yellow
}

# === [ 6. Edit WinPE ] ===
$allUsersModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules"
$psModulesToCopy = New-Object System.Collections.ArrayList
$allModules = @{}
if (Test-Path $allUsersModulePath) {
    Get-ChildItem -Path $allUsersModulePath -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { $allModules[$_.Name] = $_.FullName }
}
foreach ($module in $requiredModules) {
    if ($allModules.ContainsKey($module)) {
        $null = $psModulesToCopy.Add($module)
    } else {
        Write-Warning "Module $module not found in AllUsers scope."
    }
}

if ($useCustomWim) {
    Write-Host "Using custom WIM file for deployment" -ForegroundColor Cyan
    try {
        Edit-OSDCloudWinPE -Startnet $startnetContent -CloudDriver "*" -PSModuleCopy $psModulesToCopy -Add7Zip -WirelessConnect -Verbose
    } catch {
        Write-Error "❌ Failed to customize WinPE with custom WIM: $($_.Exception.Message)"
    }
} else {
    Write-Host "Using standard Microsoft images for deployment" -ForegroundColor Cyan
    try {
        $osdCloudGUIConfig = @{
            BrandName          = "iTechDC Cloud"
            BrandColor         = "#0066CC"
            OSName             = "Windows 11 24H2"
            OSEdition          = "Pro For Workstation"
            OSLanguage         = "en-us"
            OSActivation       = "Volume"
            DriverPackName     = "Microsoft Update Catalog"
            captureScreenshots = $false
            updateFirmware     = $false
            restartComputer    = $true
            ZTI                = $true
            SkipAutopilot      = $true
            useCustomWim       = $useCustomWim
            customWimPath      = $null
        }
        $osdCloudGUIConfig | ConvertTo-Json -Depth 4 | Set-Content -Path "$automateFolder\Start-OSDCloudGUI.json" -Force
        Write-Host "✅ Created OSDCloudGUI configuration at $automateFolder\Start-OSDCloudGUI.json" -ForegroundColor Green
    } catch {
        Write-Error "Failed to generate GUI configuration: $($_.Exception.Message)"
    }
}

# === [ 7. Generate ISO ] ===
New-OSDCloudISO

# === [ 8. Create USB Boot Media ] ===
Write-Host "`nUSB Boot Media Creation" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan
Write-Host "To create a USB Boot Media, please connect a USB drive and run:" -ForegroundColor Cyan
Write-Host "   New-OSDCloudUSB" -ForegroundColor Yellow
if (Confirm-Yes "Would you like to create a USB boot media now? (Y/N)") {
    try {
        New-OSDCloudUSB -WorkspacePath $workspace -Startnet $startnetContent -CloudDriver "*" -PSModuleCopy $psModulesToCopy -Add7Zip -WirelessConnect -Verbose
        Write-Host "✅ OSDCloud USB created successfully" -ForegroundColor Green
        if (Confirm-Yes "Would you like to add offline drivers and OS to the USB? (Y/N)") {
            try {
                if ($useCustomWim) {
                    Update-OSDCloudUSB -CustomOS -Startnet $startnetContent -CloudDriver "*" -PSModuleInstall $psModulesToCopy -Add7Zip -WirelessConnect -Verbose
                } else {
                    Update-OSDCloudUSB -DriverPack "*" -OSVersion "Windows 11" -OSBuild "24H2" -Verbose
                }
                Write-Host "✅ Offline drivers and OS added to USB" -ForegroundColor Green
            } catch {
                Write-Error "❌ Failed to update USB media: $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Error "❌ Failed to create USB media: $($_.Exception.Message)"
    }
}

# === [ 9. Summary Output ] ===
Write-Host "`nDeployment Ready! ISO is fully configured for Windows 11 24H2." -ForegroundColor Green
Write-Host "ISO Path: $workspace\OSDCloud.iso"
Write-Host "ISO (NoPrompt): $workspace\OSDCloud_NoPrompt.iso"
Write-Host "JSON Config: $automateFolder\Start-OSDCloudGUI.json"
Write-Host "USB Boot Media: $workspace\OSDCloudUSB (if created)"
Write-Host "Custom WIM Used: $useCustomWim"