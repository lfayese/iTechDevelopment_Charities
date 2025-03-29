<#
.SYNOPSIS
  Optimized OSDCloud Deployment Script for Windows 11 24H2

.DESCRIPTION
  Automates OSDCloud template/workspace creation, module installations, WinPE customization,
  RAM disk setup, and ISO/USB generation using efficient PowerShell practices.

.AUTHOR
  iTechDC / ChatGPT Code Assistant

.LAST UPDATED
  $(Get-Date -Format 'yyyy-MM-dd')
#>

# ============================
# [0] Helper Functions
# ============================

function New-Folder {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)
    if (-not (Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Confirm-Yes {
    param([string]$Prompt)
    $resp = Read-Host -Prompt $Prompt
    return $resp.Trim().Equals('Y', [System.StringComparison]::InvariantCultureIgnoreCase)
}

function Get-InstalledModules {
    $modules = @{}
    Get-Module -ListAvailable | ForEach-Object {
        if (-not $modules.ContainsKey($_.Name)) {
            $modules[$_.Name] = $_
        }
    }
    return $modules
}

function Copy-IfDifferent {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    if (-not (Test-Path $Destination)) {
        Copy-Item -Path $Source -Destination $Destination -Force
        return
    }
    $srcHash = (Get-FileHash $Source).Hash
    $dstHash = (Get-FileHash $Destination).Hash
    if ($srcHash -ne $dstHash) {
        Copy-Item -Path $Source -Destination $Destination -Force
    }
}

function Install-ModulesParallel {
    param([string[]]$ModuleNames)

    $installedModules = Get-InstalledModules
    $jobs = @()

    foreach ($mod in $ModuleNames) {
        if (-not $installedModules.ContainsKey($mod)) {
            $jobs += Start-Job -ScriptBlock {
                param($module)
                try {
                    Install-Module -Name $module -Force -AllowClobber -Scope AllUsers -ErrorAction Stop
                    Import-Module -Name $module -Force -ErrorAction Stop
                    Write-Host "✅ Installed: $module"
                } catch {
                    Write-Warning "⚠️ Failed: $module - $($_.Exception.Message)"
                }
            } -ArgumentList $mod
        } else {
            Write-Host "ℹ️ Already installed: $mod"
        }
    }

    if ($jobs.Count -gt 0) {
        Write-Host "⏳ Waiting on background installations..." -ForegroundColor Cyan
        $jobs | Wait-Job | ForEach-Object { Receive-Job -Job $_; Remove-Job $_ }
    }
}

# ============================
# [1] Pre-setup & Module Installation
# ============================

Write-Host "`n🔧 Starting OSDCloud Build Master Deployment..." -ForegroundColor Cyan

$requiredModules = @(
    'OSD', 'PackageManagement', 'PSWindowsUpdate', 'PowerShellGet',
    'Az', 'Microsoft.Graph', 'Microsoft.Entra',
    'Microsoft.Graph.Beta', 'Microsoft.Entra.Beta'
)

try {
    Install-Script -Name Get-WindowsAutoPilotInfo -Force -Scope AllUsers -ErrorAction Stop
    Write-Host "✅ Installed Get-WindowsAutoPilotInfo script"
} catch {
    Write-Warning "⚠️ Could not install Get-WindowsAutoPilotInfo: $($_.Exception.Message)"
}

Install-ModulesParallel -ModuleNames $requiredModules

if (Get-Module -ListAvailable -Name 'OSD') {
    Import-Module OSD -Force
} else {
    Write-Error "❌ OSD module is not available. Aborting."
    exit 1
}
# ============================
# [2] Create OSDCloud Template with WinRE and PS7
# ============================

$templateName = "WinRE_prod"
$templateBasePath = "$env:ProgramData\OSDCloud\Templates"
$templatePath = Join-Path $templateBasePath $templateName
$bootWimPath = "$templatePath\Media\sources\boot.wim"
$pwsh7ScriptPath = "$PSScriptRoot\winpe_pwsh7_add.ps1"

Write-Host "`n🧱 Creating OSDCloud Template: $templateName" -ForegroundColor Cyan

try {
	New-OSDCloudTemplate -Name $templateName -WinRE -Add7Zip
	Write-Host "✅ Template created successfully."

	if (-not (Test-Path $bootWimPath)) {
		throw "boot.wim not found at: $bootWimPath"
	}

	$tempFolder = "$env:TEMP\OSDCloud_PWSH7_Temp"
	New-Folder -Path $tempFolder
	Copy-IfDifferent -Source $bootWimPath -Destination "$tempFolder\boot.wim"

	if (Test-Path $pwsh7ScriptPath) {
		Write-Host "🔧 Adding PowerShell 7 to boot.wim..." -ForegroundColor Cyan
		$params = @{
			PowerShell7File   = "$PSScriptRoot\PowerShell-7.5.0-win-x64.zip"
			WinPE_BuildFolder = $tempFolder
			WinPE_MountFolder = "$tempFolder\Mount"
		}

		$tempScriptPath = "$tempFolder\temp_pwsh7_add.ps1"
		Set-Content -Path $tempScriptPath -Value @"
`$PowerShell7File = '$($params.PowerShell7File)'
`$WinPE_BuildFolder = '$($params.WinPE_BuildFolder)'
`$WinPE_MountFolder = '$($params.WinPE_MountFolder)'
. '$pwsh7ScriptPath'
"@

		& $tempScriptPath

		$modulesToInject = @("OSD", "Microsoft.Graph", "Az", "PackageManagement", "PSWindowsUpdate",
			"PowerShellGet", "Microsoft.Entra", "Microsoft.Graph.Beta", "Microsoft.Entra.Beta")

		Write-Host "📦 Injecting PowerShell modules into boot.wim (via PS 5)..." -ForegroundColor Cyan
		try {
			Copy-PSModuleToWim -ExecutionPolicy Bypass `
				-ImagePath "$tempFolder\boot.wim" `
				-Index 1 `
				-Name $modulesToInject
			Write-Host "✅ Modules injected via PS5."
		} catch {
			Write-Warning "⚠️ PS5 injection failed: $($_.Exception.Message)"
		}

		if (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") {
			Write-Host "📦 Attempting PS7 module injection..." -ForegroundColor Cyan
			& "$env:ProgramFiles\PowerShell\7\pwsh.exe" -Command {
				param($wimPath, $moduleNames)
				Import-Module OSD -Force
				Copy-PSModuleToWim -ImagePath $wimPath -Index 1 -Name $moduleNames
			} -Args "$tempFolder\boot.wim", $modulesToInject
		}

		Copy-IfDifferent -Source "$tempFolder\boot.wim" -Destination $bootWimPath
		Write-Host "✅ Updated boot.wim with PS7 and modules."

		Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
	} else {
		Write-Warning "⚠️ PS7 script not found: $pwsh7ScriptPath"
	}
} catch {
	Write-Error "❌ Template build failed: $($_.Exception.Message)"
}
# ============================
# [3] Create Workspace & Setup Paths
# ============================

$workspace      = "G:\OSDCloudProd"
$customFolder   = "G:\CustomFiles"
$wimFile        = "$customFolder\Windows11_24H2_Custom.wim"
$mediaFolder    = "$workspace\Media"
$osFolder       = "$mediaFolder\OSDCloud\OS"
$automateFolder = "$mediaFolder\OSDCloud\Automate"

Write-Host "`n🛠️ Creating Workspace: $workspace" -ForegroundColor Cyan

try {
	New-OSDCloudWorkspace -WorkspacePath $workspace
	Write-Host "✅ Workspace initialized at $workspace"
} catch {
	Write-Warning "⚠️ Failed with template. Retrying default template..."
	try {
		New-OSDCloudWorkspace -WorkspacePath $workspace
		Write-Host "✅ Workspace initialized using default template"
	} catch {
		Write-Error "❌ Could not create workspace at all. $($_.Exception.Message)"
		exit 1
	}
}

# Create required folders
$foldersToCreate = @($workspace, $mediaFolder, $customFolder, $osFolder, $automateFolder)
foreach ($f in $foldersToCreate) { New-Folder -Path $f }

# ============================
# [4] Clean Up Media Folder
# ============================

$keepDirs = @('boot','efi','en-us','sources','fonts','resources','OSDCloud')
$mediaPaths = @(
	"$workspace\Media",
	"$workspace\Media\Boot",
	"$workspace\Media\EFI\Microsoft\Boot"
)
foreach ($p in $mediaPaths) {
	if (Test-Path $p) {
		Get-ChildItem -Path $p -Directory -Exclude $keepDirs -ErrorAction SilentlyContinue |
		Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
	}
}

# ============================
# [5] Copy Modular Scripts to Automate Folder
# ============================

Write-Host "`n📁 Copying Modular Scripts into Automate folder..." -ForegroundColor Cyan

$modularFolders = @("Main", "Autopilot", "Modules", "Assets")
$modularPaths = @()

foreach ($folder in $modularFolders) {
	$source = Join-Path $customFolder $folder
	$destination = Join-Path $automateFolder $folder

	if (Test-Path $source) {
		Write-Host "✅ Copying folder: $folder" -ForegroundColor Green
		Copy-Item -Path $source -Destination $destination -Recurse -Force
		$modularPaths += $destination
	} else {
		Write-Warning "⚠️ Missing folder: $source"
	}
}

# ============================
# [6] Script Cache Generator (for WinPE RAM)
# ============================

Write-Host "`n💾 Creating Script Cache..." -ForegroundColor Cyan

$scriptCachePath = "$automateFolder\ScriptCache.ps1"
$scriptsToCache = @{
	"iTechDcUI"       = Test-Path "$customFolder\iTechDcUI.ps1" ? (Get-Content -Raw "$customFolder\iTechDcUI.ps1") : $null
	"Autopilot"       = Test-Path "$customFolder\Autopilot.ps1" ? (Get-Content -Raw "$customFolder\Autopilot.ps1") : $null
	"TenantLockdown"  = Test-Path "$customFolder\OSDCloud_Tenant_Lockdown.ps1" ? (Get-Content -Raw "$customFolder\OSDCloud_Tenant_Lockdown.ps1") : $null
	"UploadAutopilot" = Test-Path "$customFolder\OSDCloud_UploadAutopilot.ps1" ? (Get-Content -Raw "$customFolder\OSDCloud_UploadAutopilot.ps1") : $null
	"OSDCloudGUI"     = Test-Path "$customFolder\iTechDcOSDCloudGUI.ps1" ? (Get-Content -Raw "$customFolder\iTechDcOSDCloudGUI.ps1") : $null
}

$cacheScript = @"
# Auto-generated Script Cache for WinPE
`$global:ScriptCache = @{}
Write-Host "📦 Loading scripts from cache..." -ForegroundColor Cyan
"@

foreach ($key in $scriptsToCache.Keys) {
	if ($scriptsToCache[$key]) {
		$escaped = $scriptsToCache[$key] -replace "'", "''"
		$cacheScript += "`$global:ScriptCache['$key'] = @'`n$escaped`n'@`n"
	}
}

$cacheScript += @"
function Invoke-ScriptFromCache {
    param([string]`$ScriptName)
    if (`$global:ScriptCache.ContainsKey(`$ScriptName)) {
        Invoke-Expression `$global:ScriptCache[`$ScriptName]
    }
}
function Invoke-AllCachedScripts {
    'iTechDcUI','Autopilot','TenantLockdown','UploadAutopilot','OSDCloudGUI' |
    ForEach-Object { Invoke-ScriptFromCache -ScriptName \$_ }
}
Write-Host "✅ Script cache initialized." -ForegroundColor Green
"@

Set-Content -Path $scriptCachePath -Value $cacheScript -Force
Write-Host "✅ Script cache saved: $scriptCachePath"
# ============================
# [7] Create RAM Disk Setup Script for WinPE
# ============================

Write-Host "`n🧠 Generating RAM Disk Setup Script..." -ForegroundColor Cyan

$ramDiskScriptPath = "$automateFolder\Setup-RAMDisk.ps1"
$ramDiskScriptContent = @"
function New-RAMDisk {
    param (
        [string]`$DriveLetter = 'R',
        [int]`$SizeMB = 512
    )
    if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
        Write-Warning 'Not in WinPE. Skipping RAM Disk.'
        return
    }
    try {
        `$diskPart = @'
create vdisk file=X:\Temp\ramdisk.vhd maximum=`$SizeMB type=expandable
select vdisk file=X:\Temp\ramdisk.vhd
attach vdisk
create partition primary
assign letter=`$DriveLetter
format fs=ntfs quick
'@
        New-Item -Path "X:\Temp" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        Set-Content -Path "X:\Temp\diskpart.txt" -Value `$diskPart
        diskpart /s X:\Temp\diskpart.txt
        New-Item -Path "$DriveLetter`:\Temp" -ItemType Directory -Force | Out-Null
        [Environment]::SetEnvironmentVariable("TEMP", "$DriveLetter`:\Temp", "Process")
        [Environment]::SetEnvironmentVariable("TMP", "$DriveLetter`:\Temp", "Process")
        Write-Host "✅ RAM Disk created at $DriveLetter`:"
    } catch {
        Write-Warning "❌ RAM Disk failed: `$($_.Exception.Message)"
    }
}
function New-OptimalRAMDisk {
    `$mem = (Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1MB
    `$size = [math]::Min(2048, [math]::Max(256, `$mem * 0.25))
    New-RAMDisk -SizeMB `$size
}
New-OptimalRAMDisk
"@

Set-Content -Path $ramDiskScriptPath -Value $ramDiskScriptContent -Force
Write-Host "✅ RAMDisk setup script created at $ramDiskScriptPath"

# ============================
# [8] Create startnet.cmd Loader
# ============================

Write-Host "`n🧩 Creating startnet.cmd..." -ForegroundColor Cyan

$startnetContent = @"
@echo off
wpeinit

set ENTRY_SCRIPT=
IF EXIST X:\OSDCloud\Automate\Main\iTechDcUI.ps1 (set ENTRY_SCRIPT=X:\OSDCloud\Automate\Main\iTechDcUI.ps1)

IF NOT "%ENTRY_SCRIPT%"=="" (
    IF EXIST %ProgramFiles%\PowerShell\7\pwsh.exe (
        %ProgramFiles%\PowerShell\7\pwsh.exe -NoL -ExecutionPolicy Bypass -Command "& {
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Modules' -Filter *.psm1 -Recurse | ForEach-Object { . \$_.FullName }
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Main' -Filter *.ps1 -Recurse | ForEach-Object { . \$_.FullName }
            . '%ENTRY_SCRIPT%'
        }"
    ) ELSE (
        PowerShell -NoL -ExecutionPolicy Bypass -Command "& {
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Modules' -Filter *.psm1 -Recurse | ForEach-Object { . \$_.FullName }
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Main' -Filter *.ps1 -Recurse | ForEach-Object { . \$_.FullName }
            . '%ENTRY_SCRIPT%'
        }"
    )
)
"@

$global:startnetContent = $startnetContent
Write-Host "✅ Modular startnet.cmd generated."

# ============================
# [9] Copy Custom WIM (if available)
# ============================

$useCustomWim = $false

if (Test-Path $wimFile) {
	New-Folder -Path $osFolder
	Copy-IfDifferent -Source $wimFile -Destination "$osFolder\CustomImage.wim"
	$useCustomWim = $true
	Write-Host "✅ Custom WIM copied to: $osFolder\CustomImage.wim" -ForegroundColor Green
} else {
	Write-Host "ℹ️ No custom WIM found at $wimFile — standard MS image will be used." -ForegroundColor Yellow
}

$extraFiles = @($psScriptsToCopy + $modularPaths)

Edit-OSDCloudWinPE -Startnet $global:startnetContent -CloudDriver "*" `
	-ExtraFiles $extraFiles -Add7Zip -WirelessConnect -Verbose

# ============================
# [11] Generate ISO
# ============================

Write-Host "`n📦 Generating OSDCloud ISO..." -ForegroundColor Cyan
try {
	New-OSDCloudISO
	Write-Host "✅ ISO created: $workspace\OSDCloud.iso"
} catch {
	Write-Error "❌ Failed to generate ISO: $($_.Exception.Message)"
}

# ============================
# [12] USB Boot Media Creation
# ============================

Write-Host "`n💽 USB Boot Media Creation" -ForegroundColor Cyan
Write-Host "---------------------------------" -ForegroundColor Cyan
Write-Host "To create a USB Boot Media, insert a USB and run:" -ForegroundColor Cyan
Write-Host "   New-OSDCloudUSB" -ForegroundColor Yellow

if (Confirm-Yes "Would you like to create a USB boot media now? (Y/N)") {
	try {
		New-OSDCloudUSB -WorkspacePath $workspace -Startnet $global:startnetContent `
			-CloudDriver "*" -ExtraFiles $psScriptsToCopy -Add7Zip -WirelessConnect -Verbose

		Write-Host "✅ USB boot media created!" -ForegroundColor Green

		if (Confirm-Yes "Add OS image and drivers to USB? (Y/N)") {
			if ($useCustomWim) {
				Write-Host "📦 Adding Custom WIM and Drivers..." -ForegroundColor Cyan
				try {
					Update-OSDCloudUSB -CustomOS -Startnet $global:startnetContent `
						-CloudDriver "*" -ExtraFiles $psScriptsToCopy -Add7Zip -WirelessConnect -Verbose
					Write-Host "✅ Custom OS injected to USB" -ForegroundColor Green
				} catch {
					Write-Warning "⚠️ Failed to update USB: $($_.Exception.Message)"
				}
			} else {
				Write-Host "📥 Downloading Standard Windows 11 24H2 + Drivers..." -ForegroundColor Cyan
				Update-OSDCloudUSB -DriverPack "*" -OSVersion "Windows 11" -OSBuild "24H2" -Verbose
				Write-Host "✅ Standard Windows 11 and drivers added" -ForegroundColor Green
			}

			# Optional: USB File Validation
			$usbDrive = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.FileSystemLabel -like 'OSDCloud*' } | Select-Object -First 1
			if ($usbDrive) {
				$usbRoot = "$($usbDrive.DriveLetter):"
				$criticalFiles = @("$usbRoot\Sources\boot.wim", "$usbRoot\EFI\Boot\bootx64.efi")
				$missing = $criticalFiles | Where-Object { -not (Test-Path $_) }

				if ($missing.Count -eq 0) {
					Write-Host "✅ USB verification passed. All critical files present." -ForegroundColor Green
				} else {
					Write-Warning "⚠️ Missing critical files on USB:"
					$missing | ForEach-Object { Write-Warning " - $_" }
				}
			}
		}
	} catch {
		Write-Error "❌ USB creation failed: $($_.Exception.Message)"
	}
}

# ============================
# [13] Summary Output + Guide
# ============================

Write-Host "`n✅ Deployment Media Ready!" -ForegroundColor Green
Write-Host "ISO Path: $workspace\OSDCloud.iso"
Write-Host "Custom WIM Used: $useCustomWim"
Write-Host "USB Media: $workspace\OSDCloudUSB (if created)"

# Generate Quick Guide Markdown
$guide = @"
# OSDCloud Quick Deployment Guide

## Deployment Artifacts
- **ISO**: $workspace\OSDCloud.iso
- **Custom WIM Used**: $($useCustomWim ? "Yes" : "No")
- **USB Media**: $workspace\OSDCloudUSB

## Boot Instructions
1. Boot from USB or ISO
2. WinPE auto-runs with PowerShell 7 (if available)
3. Scripts are executed from memory via ScriptCache.ps1
4. Autopilot, GUI, and OSDCloud will deploy automatically

## Troubleshooting
- View logs: `X:\Windows\Logs\OSDCloud`
- Use `WirelessConnect` if network isn't available
- Re-run: `Start-OSDCloudGUI` or `Invoke-AllCachedScripts`

## Support
Please contact your IT administrator.
Generated on: $(Get-Date -Format "yyyy-MM-dd HH:mm")
"@

Set-Content -Path "$workspace\OSDCloud-QuickGuide.md" -Value $guide -Force
Write-Host "📄 Deployment guide saved at: $workspace\OSDCloud-QuickGuide.md"

# ============================
# [14] Optional Toast Notification
# ============================

if ([Environment]::OSVersion.Version.Major -ge 10) {
	try {
		Add-Type -AssemblyName Windows.UI
		$template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
		$toastXml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
		$toastText = $toastXml.GetElementsByTagName("text")
		$toastText[0].AppendChild($toastXml.CreateTextNode("OSDCloud Deployment Ready")) | Out-Null
		$toastText[1].AppendChild($toastXml.CreateTextNode("Your deployment ISO/USB is ready.")) | Out-Null
		$toast = [Windows.UI.Notifications.ToastNotification]::new($toastXml)
		$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("OSDCloud")
		$notifier.Show($toast)
	} catch {
		# Silent fail (non-Windows client or PE)
	}
}