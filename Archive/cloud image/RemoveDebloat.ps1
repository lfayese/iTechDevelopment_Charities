function Invoke-Debloat {
<#
.SYNOPSIS
   Modern Windows 11/10 debloating script for OSDCloud deployments
.DESCRIPTION
   Removes unnecessary apps, features, and settings from Windows 11/10
   Optimizes system performance and privacy
   Compatible with Windows 11 24H2 and Windows 10 22H2+
   Preserves essential functionality while removing bloatware
.NOTES
   Version: 5.2.0
   Updated: 2024-06-15
   Compatibility: Windows 10 21H2+, Windows 11 22H2+
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$PreserveOffice,

    [Parameter()]
    [switch]$PreserveStore,

    [Parameter()]
    [switch]$PreserveXbox,

    [Parameter()]
    [switch]$KeepDefenderAntivirus,

    [Parameter()]
    [ValidateSet("Minimal", "Balanced", "Aggressive")]
    [string]$DeBloatMode = "Balanced",

    [Parameter()]
    [switch]$DisableTelemetry,

    [Parameter()]
    [switch]$SkipReboot,

    [Parameter()]
    [switch]$OptimizeNetworking,

    [Parameter()]
    [switch]$PreserveCopilot
)

# Create log directory with improved error handling
$LogFolder = "$env:ProgramData\OSDCloud\Logs"
if (!(Test-Path $LogFolder)) {
    try {
        New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    catch {
        # Fallback to temp if we can't create the preferred log folder
        $LogFolder = "$env:TEMP\OSDCloud\Logs"
        New-Item -Path $LogFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

$Transcript = "$LogFolder\Debloat-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
Start-Transcript -Path $Transcript -Force

# Helper functions
function Write-StatusMessage {
    param (
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Debug')]
        [string]$Type = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    switch ($Type) {
        'Info'    { Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan }
        'Warning' { Write-Host "[$timestamp] [WARNING] $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red }
        'Success' { Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor Green }
        'Debug'   { Write-Verbose "[$timestamp] [DEBUG] $Message" }
    }
}

# Check for Admin Rights
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-StatusMessage "This script requires Administrator privileges. Please re-run as Administrator." -Type Error
    Stop-Transcript
    return
}

# Get Windows version information with better error handling
try {
    $OSVersionInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $OSVersion = $OSVersionInfo.Version
    $OSBuild = $OSVersionInfo.BuildNumber
    $IsWindows11 = $OSBuild -ge 22000
} catch {
    Write-StatusMessage "Failed to get OS version. Using fallback method." -Type Warning
    $OSVersionInfo = Get-WmiObject Win32_OperatingSystem
    $OSVersion = $OSVersionInfo.Version
    $OSBuild = $OSVersionInfo.BuildNumber
    $IsWindows11 = $OSBuild -ge 22000
}

Write-StatusMessage "Starting Windows Debloat process - $DeBloatMode Mode" -Type Info
Write-StatusMessage "OS Version: $($OSVersionInfo.Caption) (Build $OSBuild)" -Type Info
Write-StatusMessage "Windows 11 Detected: $IsWindows11" -Type Info

# Get all user SIDs for registry modifications with improved filtering and error handling
try {
    $UserSIDs = @()
    $ProfilesList = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" -ErrorAction Stop
    $UserSIDs = $ProfilesList | Where-Object { $_.PSChildName -match 'S-1-5-21-\d+-\d+-\d+-\d+$' } | Select-Object -ExpandProperty PSChildName

    if ($UserSIDs.Count -eq 0) {
        Write-StatusMessage "No user profiles found. Registry modifications will only apply to system-wide settings." -Type Warning
    }
} catch {
    Write-StatusMessage "Failed to enumerate user profiles: $_" -Type Error
    Write-StatusMessage "Continuing with system-wide modifications only." -Type Warning
    $UserSIDs = @()
}

# Define app whitelists based on preservation parameters
$WhitelistedApps = @(
    # Essential apps that should never be removed
    "Microsoft.DesktopAppInstaller",
    "Microsoft.WindowsStore",
    "Microsoft.StorePurchaseApp",
    "Microsoft.WindowsCalculator",
    "Microsoft.Windows.Photos",
    "Microsoft.WindowsNotepad",
    "Microsoft.WindowsTerminal",
    "Microsoft.WindowsCamera",
    "Microsoft.WindowsAlarms",
    "Microsoft.ScreenSketch",  # Windows 11 snipping tool
    "Microsoft.HEIFImageExtension", # HEIF image support
    "Microsoft.VP9VideoExtensions", # Video codec
    "Microsoft.WebpImageExtension", # WebP image support
    "Microsoft.RawImageExtension" # Camera RAW format support
)

# Add conditional apps based on parameters
if ($PreserveOffice) {
    $WhitelistedApps += @(
        "Microsoft.Office.Desktop",
        "Microsoft.Office.OneNote",
        "Microsoft.Office.Sway",
        "Microsoft.Office.Excel",
        "Microsoft.Office.Word",
        "Microsoft.Office.Outlook",
        "Microsoft.Office.PowerPoint",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.Office365.Desktop",
        "Microsoft.MicrosoftOffice.Desktop"
    )
}

if ($PreserveStore) {
    $WhitelistedApps += @(
        "Microsoft.WindowsStore",
        "Microsoft.StorePurchaseApp",
        "Microsoft.Services.Store.Engagement",
        "Microsoft.UI.Xaml*"
    )
}

if ($PreserveXbox) {
    $WhitelistedApps += @(
        "Microsoft.XboxApp",
        "Microsoft.XboxGameOverlay",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxIdentityProvider",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.Xbox.TCUI",
        "Microsoft.GamingApp",
        "Microsoft.GamingServices"
    )
}

if ($PreserveCopilot) {
    $WhitelistedApps += @(
        "MicrosoftWindows.Client.WebExperience",
        "Copilot*",
        "Windows.Copilot*"
    )
}

# Include manufacturer apps that should never be removed
$NonRemovable = @(
    "Microsoft.WindowsDefender",
    "Microsoft.Windows.Defender",
    "Microsoft.WindowsSecurityCenter",
    "Microsoft.BioEnrollment",
    "Microsoft-Windows-Client-Features",
    "Microsoft.AccountsControl",
    "Microsoft.Windows.ContentDeliveryManager",  # Core system component in newer Windows
    "Microsoft.Windows.ShellExperienceHost",     # Core UI component
    "Microsoft.UI.Xaml*",                       # Core UI framework
    "Microsoft.VCLibs*"                         # Visual C++ libraries (dependencies)
)

if ($KeepDefenderAntivirus) {
    $NonRemovable += @(
        "Microsoft.SecHealthUI",
        "Windows.CBSPreview",
        "Windows.immersivecontrolpanel",
        "Microsoft.Windows.SecHealthUI"
    )
}

# Define modern bloatware apps to remove (updated for 2024-2025)
$Bloatware = @(
    # Common Bloatware Apps
    "Microsoft.549981C3F5F10",
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.Messaging",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.NetworkSpeedTest",
    "Microsoft.MixedReality.Portal",
    "Microsoft.News",
    "Microsoft.Office.Lens",
    "Microsoft.OneConnect",
    "Microsoft.People",
    "Microsoft.Print3D",
    "Microsoft.SkypeApp",
    "Microsoft.Office.Todo.List",
    "microsoft.windowscommunicationsapps", # Mail & Calendar
    "Microsoft.WindowsMaps",
    "Microsoft.YourPhone",
    "MicrosoftTeams",
    "Microsoft.Todos",
    "Microsoft.PowerAutomateDesktop",
    "SpotifyAB.SpotifyMusic",
    "Disney.37853FC22B2CE",
    "*EclipseManager*",
    "*ActiproSoftwareLLC*",
    "*AdobeSystemsIncorporated.AdobePhotoshopExpress*",
    "*Duolingo-LearnLanguagesforFree*",
    "*PandoraMediaInc*",
    "*CandyCrush*",
    "*BubbleWitch3Saga*",
    "*Wunderlist*",
    "*Flipboard*",
    "*Twitter*",
    "*Facebook*",
    "*Spotify*",
    "*Minecraft*",
    "*Royal Revolt*",
    "*Sway*",
    "*Speed Test*",
    "*Dolby*",
    "*Disney*",
    "*LinkedIn*",
    "*TikTok*"
)

# Windows 11 specific apps to remove (updated for 24H2)
if ($IsWindows11) {
    $Bloatware += @(
        "Microsoft.Windows.DevHome",
        "MicrosoftCorporationII.MicrosoftFamily",
        "C27EB4BA.DropboxOEM",
        "clipchamp.clipchamp",
        "Microsoft.GetHelp",
        "Microsoft.MicrosoftStickyNotes",
        "*Microsoft.Whiteboard*",
        "*Microsoft.MinecraftUWP*",
        "MicrosoftTeams.Microphone" # Teams consumer/personal version in Windows 11
    )

    # Only remove Copilot if not preserved
    if (-not $PreserveCopilot) {
        $Bloatware += @(
            "MicrosoftWindows.Client.WebExperience"
        )
    }
}

# Aggressive mode adds more apps to remove
if ($DeBloatMode -eq "Aggressive") {
    $Bloatware += @(
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MicrosoftStickyNotes",
        "Microsoft.Wallet"
    )
}

Write-StatusMessage "Removing bloatware applications..." -Type Info

# Remove AppX packages with improved handling
foreach ($app in $Bloatware) {
    try {
        $appPackages = Get-AppxPackage -AllUsers | Where-Object {
            ($_.Name -like $app) -and
            ($WhitelistedApps | Where-Object { $_.Name -like $app }).Count -eq 0 -and
            ($NonRemovable | Where-Object { $_.Name -like $app }).Count -eq 0
        }

        if ($appPackages -and $appPackages.Count -gt 0) {
            foreach ($appPackage in $appPackages) {
                try {
                    Write-StatusMessage "Removing AppX package: $($appPackage.Name)" -Type Info
                    Remove-AppxPackage -Package $appPackage.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                } catch {
                    Write-StatusMessage "Failed to remove AppX package: $($appPackage.Name): $_" -Type Warning
                }
            }
        } else {
            Write-StatusMessage "No matching AppX packages found for pattern: $app" -Type Debug
        }

        # Remove provisioned packages
        $provisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object {
            ($_.DisplayName -like $app) -and
            ($WhitelistedApps | Where-Object { $_.Name -like $app }).Count -eq 0 -and
            ($NonRemovable | Where-Object { $_.Name -like $app }).Count -eq 0
        }

        if ($provisionedPackages) {
            foreach ($provisionedPackage in $provisionedPackages) {
                try {
                    Write-StatusMessage "Removing provisioned package: $($provisionedPackage.DisplayName)" -Type Info
                    Remove-AppxProvisionedPackage -Online -PackageName $provisionedPackage.PackageName -ErrorAction SilentlyContinue
                } catch {
                    Write-StatusMessage "Failed to remove provisioned package: $($provisionedPackage.DisplayName): $_" -Type Warning
                }
            }
        }
    } catch {
        Write-StatusMessage "Error processing app pattern '$app': $_" -Type Error
    }
}

# System tweaks based on mode
Write-StatusMessage "Applying system tweaks and optimizations..." -Type Info

function Set-RegistryKey {
    param (
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = "DWORD"
    )

    if (!(Test-Path $Path)) {
        try {
            New-Item -Path $Path -Force | Out-Null
            Write-StatusMessage "Created registry key: $Path" -Type Debug
        } catch {
            Write-StatusMessage "Failed to create registry key: $Path : $_" -Type Warning
            return $false
        }
    }

    try {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        return $true
    } catch {
        Write-StatusMessage "Failed to set registry value: $Path\$Name : $_" -Type Warning
        return $false
    }
}

# Disable Windows Feedback Experience
Write-StatusMessage "Disabling Windows Feedback Experience program" -Type Info
Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0

# Stop Cortana from being used in Windows Search
Write-StatusMessage "Stopping Cortana from being used as part of Windows Search" -Type Info
Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0

# Disable Bing Search in Start Menu
Write-StatusMessage "Disabling Bing Search in Start Menu" -Type Info
Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "DisableWebSearch" -Value 1
Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "ConnectedSearchUseWeb" -Value 0

# Apply registry changes to all user profiles
foreach ($sid in $UserSIDs) {
    Write-StatusMessage "Applying settings to user profile with SID: $sid" -Type Debug

    # Disable Bing Search
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0

    # Disable Windows Feedback
    Set-RegistryKey -Path "Registry::HKU\$sid\Software\Microsoft\Siuf\Rules" -Name "PeriodInNanoSeconds" -Value 0

    # Disable Content Delivery
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "ContentDeliveryAllowed" -Value 0
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "OemPreInstalledAppsEnabled" -Value 0
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEnabled" -Value 0
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEverEnabled" -Value 0
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Value 0
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338393Enabled" -Value 0
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338388Enabled" -Value 0
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0

    # Disable Live Tiles
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "NoTileApplicationNotification" -Value 1

    # Privacy settings
    Set-RegistryKey -Path "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0
}

# Disable scheduled tasks that are considered bloatware
Write-StatusMessage "Disabling unnecessary scheduled tasks..." -Type Info
$disableTasks = @(
    "XblGameSaveTask",
    "Consolidator",
    "UsbCeip",
    "DmClient",
    "DmClientOnScenarioDownload",
    "SmartScreenSpecific",
    "Microsoft-Windows-DiskDiagnosticDataCollector",
    "Microsoft\Office\OfficeTelemetryAgentLogOn"
)

foreach ($task in $disableTasks) {
    $taskPath = $task
    # Handle tasks that might be in the root or in subfolders
    if (-not $task.Contains('\')) {
        $taskPath = "\Microsoft\Windows\$task"
    }

    try {
        $scheduledTask = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($null -ne $scheduledTask) {
            Disable-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue | Out-Null
            Write-StatusMessage "Disabled scheduled task: $taskPath" -Type Success
        }
    } catch {
        # Try alternate approach if the path doesn't work
        try {
            $scheduledTask = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
            if ($null -ne $scheduledTask) {
                Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
                Write-StatusMessage "Disabled scheduled task: $task" -Type Success
            }
        } catch {
            Write-StatusMessage "Failed to disable scheduled task: $task" -Type Warning
        }
    }
}

# Windows 11 specific tweaks
if ($IsWindows11) {
    Write-StatusMessage "Applying Windows 11 specific optimizations..." -Type Info

    # Disable Windows Copilot if not preserved
    if (-not $PreserveCopilot) {
        Write-StatusMessage "Disabling Windows Copilot..." -Type Info
        Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows" -Name "TurnOffWindowsCopilot" -Value 1
    }

    # Disable Widgets
    Write-StatusMessage "Disabling Windows Widgets..." -Type Info
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests" -Name "value" -Value 0

    # Add back Snipping Tool functionality if it was removed
    Write-StatusMessage "Re-enabling essential Windows components..." -Type Info
    try {
        DISM /Online /Add-Capability /CapabilityName:Windows.Client.ShellComponents~~~~0.0.1.0 /NoRestart
        Write-StatusMessage "Windows Shell Components restored successfully" -Type Success
    } catch {
        Write-StatusMessage "Failed to restore Windows Shell Components: $_" -Type Warning
    }

    # Fix Explorer context menu to use classic style
    if ($DeBloatMode -eq "Aggressive") {
        Write-StatusMessage "Restoring classic context menu in Windows Explorer..." -Type Info
        Set-RegistryKey -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(Default)" -Value "" -Type String
    }
}

# Disable telemetry if requested
if ($DisableTelemetry) {
    Write-StatusMessage "Disabling Windows telemetry..." -Type Info
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0

    # Disable Connected User Experiences
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1

    # Disable diagnostic data
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" -Name "DiagTrackAuthorization" -Value 0
}

# Apply system-wide registry changes
Write-StatusMessage "Applying system-wide registry tweaks..." -Type Info

# Disable suggested content in settings app
Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338393Enabled" -Value 0
Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353694Enabled" -Value 0
Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353696Enabled" -Value 0

# Prevent Windows from suggesting apps
Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1

# Set default File Explorer view to This PC
Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1

# Configure User Experience
if ($DeBloatMode -eq "Aggressive" -or $DeBloatMode -eq "Balanced") {
    # Disable unnecessary animations
    Write-StatusMessage "Disabling unnecessary animations and effects..." -Type Info
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2

    # Disable OneDrive setup
    Write-StatusMessage "Disabling OneDrive setup..." -Type Info
    Set-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Value 1
}

# Optimize networking if requested
if ($OptimizeNetworking) {
    Write-StatusMessage "Applying network optimizations..." -Type Info

    # Enable DNS over HTTPS (DoH)
    Set-RegistryKey -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDoh" -Value 2

    # Set DNS Client service to Automatic start
    Set-Service -Name Dnscache -StartupType Automatic -ErrorAction SilentlyContinue

    # Set network adapter to full performance mode (disable power saving)
    try {
        # Get all network adapters that are physically connected
        $networkAdapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

        foreach ($adapter in $networkAdapters) {
            Write-StatusMessage "Optimizing network adapter: $($adapter.Name)" -Type Info

            # Set power management settings using PowerShell where available
            if ($adapter.PnPDeviceID) {
                $deviceID = $adapter.PnPDeviceID
                $devicePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\*"

                Get-ChildItem -Path $devicePath -ErrorAction SilentlyContinue | ForEach-Object {
                    if ((Get-ItemProperty $_.PSPath).DeviceInstanceID -eq $deviceID) {
                        # Disable power saving for network adapter
                        Set-ItemProperty -Path $_.PSPath -Name "PnPCapabilities" -Value 24 -Type DWORD -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    } catch {
        Write-StatusMessage "Error optimizing network adapters: $_" -Type Warning
    }
}

# Final optimizations
Write-StatusMessage "Applying final optimizations..." -Type Info

# Disable hibernation to free disk space
if ($DeBloatMode -eq "Aggressive") {
    try {
        Write-StatusMessage "Disabling hibernation to free disk space..." -Type Info
        powercfg /h off
    } catch {
        Write-StatusMessage "Failed to disable hibernation: $_" -Type Warning
    }
}

# Clean up WinSxS folder
if ($DeBloatMode -eq "Aggressive" -or $DeBloatMode -eq "Balanced") {
    try {
        Write-StatusMessage "Cleaning up WinSxS folder..." -Type Info
        Dism.exe /Online /Cleanup-Image /StartComponentCleanup /NoRestart
    } catch {
        Write-StatusMessage "Failed to clean up WinSxS folder: $_" -Type Warning
    }
}

# Cleanup temporary files
Write-StatusMessage "Cleaning up temporary files..." -Type Info
$tempFolders = @(
    "C:\Windows\Temp\*",
    "$env:TEMP\*",
    "$env:SystemRoot\SoftwareDistribution\Download\*"
)

foreach ($folder in $tempFolders) {
    try {
        Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
        Write-StatusMessage "Cleaned up folder: $folder" -Type Debug
    } catch {
        Write-StatusMessage "Error cleaning temporary folder $folder : $_" -Type Debug
    }
}

Write-StatusMessage "Windows debloat process completed successfully!" -Type Success

if (-not $SkipReboot) {
    Write-StatusMessage "System should be restarted to apply all changes. Restart recommended." -Type Warning
}

Stop-Transcript
}