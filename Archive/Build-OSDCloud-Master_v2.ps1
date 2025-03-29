# Master OSDCloud Deployment Script - Windows 11 24H2 (Optimized & Fixed)
# --- Helper Functions ---
function New-Folder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    # Cache Test-Path result to avoid repetitive filesystem lookups.
    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
}
function Confirm-Yes {
    param(
        [string]$Prompt
    )
    $response = Read-Host -Prompt $Prompt
    # Use case-insensitive comparison directly.
    return $response.Trim().Equals('Y', [System.StringComparison]::InvariantCultureIgnoreCase)
}
function Get-InstalledModules {
    # Using Group-Object to build a hash table (if running on PS v5.1+).
    $modules = @{}
    Get-Module -ListAvailable | ForEach-Object {
        if (-not $modules.ContainsKey($_.Name)) { $modules[$_.Name] = $_ }
    }
    return $modules
}
function Install-Modules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ModuleNames
    )
    # Cache installed modules once to minimize repeated lookups.
    $installedModules = Get-InstalledModules
    # Ensure PowerShellGet is installed only once.
    if (-not $installedModules.ContainsKey('PowerShellGet')) {
        Write-Warning "PowerShellGet module not found in cache. Installing..."
        Install-Module -Name PowerShellGet -Force -AllowClobber -Scope AllUsers -ErrorAction Stop -Confirm:$false
        # Add to the cache (storing only the module name to keep it lightweight).
        $installedModules['PowerShellGet'] = @{ Name = 'PowerShellGet' }
    }
    foreach ($module in $ModuleNames) {
        if (-not $installedModules.ContainsKey($module)) {
            try {
                Install-Module -Name $module -Force -AllowClobber -Scope AllUsers -ErrorAction Stop -Confirm:$false
                Import-Module -Name $module -Force -ErrorAction Stop
                Write-Host "✅ Successfully installed module: $module"
                # Update cache.
                $installedModules[$module] = @{ Name = $module }
            } catch {
                Write-Warning "⚠️ Failed to install $module. Error: $($_.Exception.Message)"
                throw
            }
        } else {
            Write-Host "ℹ️ Module '$module' is already installed."
        }
    }
}
# --- Main Script ---
# List of all required modules
$requiredModules = @(
    'OSD', 'PackageManagement', 'PSWindowsUpdate',
    'PowerShellGet', 'Az', 'Microsoft.Graph', 'Microsoft.Entra',
    'Microsoft.Graph.Beta', 'Microsoft.Entra.Beta'
)
# Install Get-WindowsAutoPilotInfo script separately
try {
    Install-Script -Name Get-WindowsAutoPilotInfo -Force -Scope AllUsers -ErrorAction Stop
    Write-Host "✅ Successfully installed Get-WindowsAutoPilotInfo script"
} catch {
    Write-Warning "⚠️ Failed to install Get-WindowsAutoPilotInfo script. Error: $($_.Exception.Message)"
    throw
}
# Install other required modules via centralized function
Install-Modules -ModuleNames $requiredModules
# Ensure the 'OSD' module is imported (exit on failure)
if (Get-Module -ListAvailable -Name 'OSD') {
    Import-Module OSD -Force
} else {
    Write-Error "❌ OSD Module not found. Please install it before proceeding."
    exit 1
}
# === [ 0. Create OSDCloud Template with WinRE and PowerShell 7 ] ===
$templateName = "WinRE_prod"
$pwsh7ScriptPath = "$PSScriptRoot\winpe_pwsh7_add.ps1"
$templateBasePath = "$env:ProgramData\OSDCloud\Templates"
$templatePath = "$templateBasePath\$templateName"
$bootWimPath = "$templatePath\Media\sources\boot.wim"
Write-Host "Creating OSDCloud Template with WinRE named '$templateName'" -ForegroundColor Cyan
try {
    # Create the template with WinRE
    New-OSDCloudTemplate -Name $templateName -WinRE -Add7Zip
    Write-Host "✅ OSDCloud Template with WinRE created successfully" -ForegroundColor Green
    # Check and cache boot.wim existence
    $bootWimExists = Test-Path $bootWimPath
    if ($bootWimExists) {
        Write-Host "✅ Verified boot.wim exists at $bootWimPath" -ForegroundColor Green
        if (Test-Path $pwsh7ScriptPath) {
            Write-Host "Adding PowerShell 7 to the boot.wim using $pwsh7ScriptPath" -ForegroundColor Cyan
            # Create and cache a temporary folder location once.
            $tempFolder = "$env:TEMP\OSDCloud_PWSH7_Temp"
            New-Folder -Path $tempFolder
            Copy-Item -Path $bootWimPath -Destination "$tempFolder\boot.wim" -Force
            # Define parameters for the script
            $params = @{
                PowerShell7File   = "$PSScriptRoot\PowerShell-7.5.0-win-x64.zip"
                WinPE_BuildFolder = $tempFolder
                WinPE_MountFolder = "$tempFolder\Mount"
            }
            # Create a temporary script that passes the parameters; this avoids multiple file reads.
            $tempScriptContent = @"
# Settings from the parent script
`$PowerShell7File = '$($params.PowerShell7File)'
`$WinPE_BuildFolder = '$($params.WinPE_BuildFolder)'
`$WinPE_MountFolder = '$($params.WinPE_MountFolder)'
. '$pwsh7ScriptPath'
"@
            $tempScriptPath = "$tempFolder\temp_pwsh7_add.ps1"
            Set-Content -Path $tempScriptPath -Value $tempScriptContent
            # Run the temporary script
            & $tempScriptPath
            Write-Host "Injecting PowerShell modules into boot.wim..." -ForegroundColor Cyan
            $modulesToInject = @("OSD", "Microsoft.Graph", "Az", "PackageManagement", "PSWindowsUpdate",
                "PowerShellGet", "Microsoft.Entra", "Microsoft.Graph.Beta", "Microsoft.Entra.Beta")
            # 1. Use PowerShell 5 to inject modules
            Write-Host "Using PowerShell 5 to inject modules..." -ForegroundColor Cyan
            try {
                Copy-PSModuleToWim -ExecutionPolicy Bypass `
                    -ImagePath "$tempFolder\boot.wim" `
                    -Index 1 `
                    -Name $modulesToInject
                Write-Host "✅ Successfully injected modules using PowerShell 5" -ForegroundColor Green
            } catch {
                Write-Warning "⚠️ Failed to inject modules using PowerShell 5: $($_.Exception.Message)"
            }
            # 2. Attempt using PowerShell 7 if available
            if (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") {
                Write-Host "Using PowerShell 7 to inject modules..." -ForegroundColor Cyan
                try {
                    & "$env:ProgramFiles\PowerShell\7\pwsh.exe" -Command {
                        param($wimPath, $moduleNames)
                        Import-Module OSD -Force -ErrorAction Stop
                        Copy-PSModuleToWim -ExecutionPolicy Bypass `
                            -ImagePath $wimPath `
                            -Index 1 `
                            -Name $moduleNames
                    } -Args "$tempFolder\boot.wim", $modulesToInject
                    Write-Host "✅ Successfully injected modules using PowerShell 7" -ForegroundColor Green
                } catch {
                    Write-Warning "⚠️ Failed to inject modules using PowerShell 7: $($_.Exception.Message)"
                }
            } else {
                Write-Warning "⚠️ PowerShell 7 not found on this system. Only PowerShell 5 injection was attempted."
            }
            # Update boot.wim in the template from the modified copy in the temporary folder.
            if (Test-Path "$tempFolder\boot.wim") {
                Copy-Item -Path "$tempFolder\boot.wim" -Destination $bootWimPath -Force
                Write-Host "✅ Successfully added PowerShell 7 and modules to the boot.wim in the template" -ForegroundColor Green
            } else {
                Write-Warning "❌ Failed to find modified boot.wim at $tempFolder\boot.wim"
            }
            # Clean up temporary folder.
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Warning "⚠️ PowerShell 7 script not found at $pwsh7ScriptPath. PowerShell 7 will not be added to boot.wim."
        }
    } else {
        Write-Warning "⚠️ boot.wim not found at expected location: $bootWimPath"
    }
} catch {
    Write-Error "❌ Failed to create OSDCloud Template: $($_.Exception.Message)"
}
# === [ 1. Create OSDCloud Workspace using the custom template ] ===
$workspace      = "G:\OSDCloudProd"
$customFolder   = "G:\CustomFiles"
$wimFile        = "$customFolder\Windows11_24H2_Custom.wim"
$mediaFolder    = "$workspace\Media"
$osFolder       = "$mediaFolder\OSDCloud\OS"
$automateFolder = "$mediaFolder\OSDCloud\Automate"
Write-Host "Creating/Reinitializing workspace at $workspace using template $templateName" -ForegroundColor Cyan
try {
    New-OSDCloudWorkspace -WorkspacePath $workspace
    Write-Host "✅ Workspace setup completed at $workspace using custom template" -ForegroundColor Green
} catch {
    Write-Error "❌ Failed to create/reinitialize workspace: $($_.Exception.Message)"
    try {
        Write-Host "Attempting to use default template instead..." -ForegroundColor Yellow
        New-OSDCloudWorkspace -WorkspacePath $workspace
        Write-Host "✅ Workspace setup completed at $workspace with default template" -ForegroundColor Green
    } catch {
        Write-Error "❌ Failed to create workspace with default template: $($_.Exception.Message)"
    }
}
# Cache folder creation to avoid repetitive Test-Path calls.
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
        # Retrieve directories once and filter using -Exclude.
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
# Optimize script loading by reducing redundant checks and conditional loading
$startnetContent = @'
@ECHO OFF
wpeinit
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
cd\
title OSDCloud Deployment Environment

REM Set paths to check for scripts
SET UI_SCRIPT=
SET AUTOPILOT_SCRIPT=
SET TENANT_SCRIPT=
SET UPLOAD_SCRIPT=
SET GUI_SCRIPT=

REM Check for scripts in both locations (only once per script)
IF EXIST X:\Automate\iTechDcUI.ps1 (SET UI_SCRIPT=X:\Automate\iTechDcUI.ps1) ELSE IF EXIST X:\OSDCloud\Automate\iTechDcUI.ps1 (SET UI_SCRIPT=X:\OSDCloud\Automate\iTechDcUI.ps1)
IF EXIST X:\Automate\Autopilot.ps1 (SET AUTOPILOT_SCRIPT=X:\Automate\Autopilot.ps1) ELSE IF EXIST X:\OSDCloud\Automate\Autopilot.ps1 (SET AUTOPILOT_SCRIPT=X:\OSDCloud\Automate\Autopilot.ps1)
IF EXIST X:\Automate\OSDCloud_Tenant_Lockdown.ps1 (SET TENANT_SCRIPT=X:\Automate\OSDCloud_Tenant_Lockdown.ps1) ELSE IF EXIST X:\OSDCloud\Automate\OSDCloud_Tenant_Lockdown.ps1 (SET TENANT_SCRIPT=X:\OSDCloud\Automate\OSDCloud_Tenant_Lockdown.ps1)
IF EXIST X:\Automate\OSDCloud_UploadAutopilot.ps1 (SET UPLOAD_SCRIPT=X:\Automate\OSDCloud_UploadAutopilot.ps1) ELSE IF EXIST X:\OSDCloud\Automate\OSDCloud_UploadAutopilot.ps1 (SET UPLOAD_SCRIPT=X:\OSDCloud\Automate\OSDCloud_UploadAutopilot.ps1)
IF EXIST X:\Automate\iTechDcOSDCloudGUI.ps1 (SET GUI_SCRIPT=X:\Automate\iTechDcOSDCloudGUI.ps1) ELSE IF EXIST X:\OSDCloud\Automate\iTechDcOSDCloudGUI.ps1 (SET GUI_SCRIPT=X:\OSDCloud\Automate\iTechDcOSDCloudGUI.ps1)

REM Check if PowerShell 7 is available and use it, otherwise fall back to Windows PowerShell
IF EXIST %ProgramFiles%\PowerShell\7\pwsh.exe (
    %ProgramFiles%\PowerShell\7\pwsh.exe -NoL -ExecutionPolicy Bypass -Command "& {
        # Create an array of script paths to process in order
        $scriptPaths = @(
            if ('!UI_SCRIPT!' -ne '') { '!UI_SCRIPT!' }
            if ('!AUTOPILOT_SCRIPT!' -ne '') { '!AUTOPILOT_SCRIPT!' }
            if ('!TENANT_SCRIPT!' -ne '') { '!TENANT_SCRIPT!' }
            if ('!UPLOAD_SCRIPT!' -ne '') { '!UPLOAD_SCRIPT!' }
            if ('!GUI_SCRIPT!' -ne '') { '!GUI_SCRIPT!' }
        )

        # Process each script in sequence
        foreach ($script in $scriptPaths) {
            if ($script -and (Test-Path $script)) {
                Write-Host 'Loading script: ' $script -ForegroundColor Cyan
                try {
                    . $script
                    Write-Host 'Successfully loaded: ' $script -ForegroundColor Green
                }
                catch {
                    Write-Host 'Error loading: ' $script -ForegroundColor Red
                    Write-Host $_.Exception.Message -ForegroundColor Red
                }
            }
        }
    }"
) ELSE (
    PowerShell -NoL -ExecutionPolicy Bypass -Command "& {
        # Create an array of script paths to process in order
        $scriptPaths = @(
            if ('!UI_SCRIPT!' -ne '') { '!UI_SCRIPT!' }
            if ('!AUTOPILOT_SCRIPT!' -ne '') { '!AUTOPILOT_SCRIPT!' }
            if ('!TENANT_SCRIPT!' -ne '') { '!TENANT_SCRIPT!' }
            if ('!UPLOAD_SCRIPT!' -ne '') { '!UPLOAD_SCRIPT!' }
            if ('!GUI_SCRIPT!' -ne '') { '!GUI_SCRIPT!' }
        )

        # Process each script in sequence
        foreach ($script in $scriptPaths) {
            if ($script -and (Test-Path $script)) {
                Write-Host 'Loading script: ' $script -ForegroundColor Cyan
                try {
                    . $script
                    Write-Host 'Successfully loaded: ' $script -ForegroundColor Green
                }
                catch {
                    Write-Host 'Error loading: ' $script -ForegroundColor Red
                    Write-Host $_.Exception.Message -ForegroundColor Red
                }
            }
        }
    }"
)
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
$allUsersScriptPath = "$env:ProgramFiles\WindowsPowerShell\Scripts"
$psScriptsToCopy = @()
$autoPilotScript = Join-Path $allUsersScriptPath "Get-WindowsAutoPilotInfo.ps1"
if (Test-Path $autoPilotScript) {
    $psScriptsToCopy += $autoPilotScript
    Write-Host "✅ Found script: $autoPilotScript" -ForegroundColor Green
} else {
    Write-Warning "Script not found: $autoPilotScript"
}
try {
    Write-Host "Customizing WinPE for deployment" -ForegroundColor Cyan
    # Pass $psScriptsToCopy to the ExtraFiles parameter
    Edit-OSDCloudWinPE -Startnet $startnetContent -CloudDriver "*" -ExtraFiles $psScriptsToCopy -Add7Zip -WirelessConnect -Verbose
    if (-not $useCustomWim) {
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
            useCustomWim       = $false
            customWimPath      = $null
        }
        $osdCloudGUIConfig | ConvertTo-Json -Depth 4 | Set-Content -Path "$automateFolder\Start-OSDCloudGUI.json" -Force
        Write-Host "✅ Created OSDCloudGUI configuration at $automateFolder\Start-OSDCloudGUI.json" -ForegroundColor Green
    }
} catch {
    Write-Error "❌ Failed to customize WinPE: $($_.Exception.Message)"
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
        New-OSDCloudUSB -WorkspacePath $workspace -Startnet $startnetContent -CloudDriver "*" -ExtraFiles $psScriptsToCopy -Add7Zip -WirelessConnect -Verbose
        Write-Host "✅ OSDCloud USB created successfully" -ForegroundColor Green
        if (Confirm-Yes "Would you like to add offline drivers and OS to the USB? (Y/N)") {
            try {
                if ($useCustomWim) {
                    $startTime = Get-Date
                    Write-Host "Starting custom OS update at $startTime. This may take several minutes..." -ForegroundColor Cyan
                    try {
                        Update-OSDCloudUSB -CustomOS -Startnet $startnetContent -CloudDriver "*" -ExtraFiles $psScriptsToCopy -Add7Zip -WirelessConnect -Verbose -ErrorAction Stop
                        $duration = New-TimeSpan -Start $startTime -End (Get-Date)
                        Write-Host "✅ Custom OS update completed in $($duration.Minutes) minutes and $($duration.Seconds) seconds" -ForegroundColor Green
                    } catch {
                        $errorDetails = $_.Exception.Message
                        Write-Error "❌ Custom OS update failed with error: $errorDetails"
                        if ($errorDetails -match "access denied|locked") {
                            Write-Host "💡 Troubleshooting: Ensure USB drive is not write-protected and no applications are using it" -ForegroundColor Yellow
                        } elseif ($errorDetails -match "space|storage") {
                            Write-Host "💡 Troubleshooting: Ensure USB drive has sufficient free space (8GB+ recommended)" -ForegroundColor Yellow
                        }
                        if (Confirm-Yes "Would you like to try with standard Windows images instead? (Y/N)") {
                            Update-OSDCloudUSB -DriverPack "*" -OSVersion "Windows 11" -OSBuild "24H2" -Verbose -ErrorAction SilentlyContinue
                        }
                    }
                } else {
                    Write-Host "Adding standard Windows 11 24H2 image and drivers to USB..." -ForegroundColor Cyan
                    Update-OSDCloudUSB -DriverPack "*" -OSVersion "Windows 11" -OSBuild "24H2" -Verbose
                    Write-Host "✅ Standard Windows 11 24H2 image and drivers added to USB" -ForegroundColor Green
                }
                # Verify USB readiness by checking for critical files.
                $usbDrive = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.FileSystemLabel -like 'OSDCloud*' } | Select-Object -First 1
                if ($usbDrive) {
                    $usbRoot = "$($usbDrive.DriveLetter):"
                    $criticalFiles = @(
                        "$usbRoot\Sources\boot.wim",
                        "$usbRoot\EFI\Boot\bootx64.efi"
                    )
                    $allFilesExist = $true
                    foreach ($file in $criticalFiles) {
                        if (-not (Test-Path $file)) {
                            $allFilesExist = $false
                            Write-Warning "Missing critical file: $file"
                        }
                    }
                    if ($allFilesExist) {
                        Write-Host "✅ USB verification successful - all critical files present" -ForegroundColor Green
                    } else {
                        Write-Warning "⚠️ USB may not be bootable - missing critical files"
                    }
                }
            } catch {
                Write-Error "❌ Failed to update USB media: $($_.Exception.Message)"
                Write-Host "💡 Try running the following command manually:" -ForegroundColor Yellow
                Write-Host "   Update-OSDCloudUSB -DriverPack '*' -OSVersion 'Windows 11' -OSBuild '24H2'" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Error "❌ Failed to create USB media: $($_.Exception.Message)"
        Write-Host "💡 Try connecting a different USB drive or running New-OSDCloudUSB manually" -ForegroundColor Yellow
    }
}
# === [ 9. Summary Output ] ===
Write-Host "`nDeployment Ready! ISO is fully configured for Windows 11 24H2." -ForegroundColor Green
Write-Host "ISO Path: $workspace\OSDCloud.iso"
Write-Host "ISO (NoPrompt): $workspace\OSDCloud_NoPrompt.iso"
Write-Host "JSON Config: $automateFolder\Start-OSDCloudGUI.json"
Write-Host "USB Boot Media: $workspace\OSDCloudUSB (if created)"
Write-Host "Custom WIM Used: $useCustomWim"
# Create a quick reference guide file
$guideContent = @"
# OSDCloud Deployment Guide
## Quick Reference
- **ISO Location**: $workspace\OSDCloud.iso
- **USB Media**: Created at $workspace\OSDCloudUSB (if you selected this option)
- **Custom Image**: $($useCustomWim ? "Yes - Using custom Windows 11 24H2 image" : "No - Using standard Microsoft image")
## Boot Instructions
1. Boot from the USB/ISO media
2. WinPE will automatically load with PowerShell 7 (if available)
3. The deployment scripts will run automatically
4. Follow the on-screen prompts to complete the deployment
## Troubleshooting
- If deployment fails, check logs at X:\Windows\Logs\OSDCloud
- For wireless connectivity issues, use the WirelessConnect utility
- For manual intervention, use PowerShell console and run Start-OSDCloud or Start-OSDCloudGUI
## Further Assistance
For assistance, please contact your system administrator.
Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm")
"@
$guideFilePath = "$workspace\OSDCloud-QuickGuide.md"
Set-Content -Path $guideFilePath -Value $guideContent -Force
Write-Host "📄 Quick reference guide created at: $guideFilePath" -ForegroundColor Green
# Optionally notify script completion via toast notification (if available on Windows 10/11)
if ([Environment]::OSVersion.Version.Major -ge 10) {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
        $toastXml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
        $toastText = $toastXml.GetElementsByTagName("text")
        $toastText[0].AppendChild($toastXml.CreateTextNode("OSDCloud Deployment Ready")) | Out-Null
        $toastText[1].AppendChild($toastXml.CreateTextNode("Your deployment media has been successfully created.")) | Out-Null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($toastXml)
        $toast.Tag = "OSDCloud"
        $toast.Group = "OSDCloud"
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("OSDCloud Deployment").Show($toast)
    } catch {
        # Silent failure if notifications arent available.
    }
}