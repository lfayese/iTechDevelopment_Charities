<#
.Synopsis
    OSDCloud Workspace and ISO Creation Script with Enhanced WinPE Support
.DESCRIPTION
    Created: 2025-03-25
    Version: 2.0

    This script creates an OSDCloud workspace and ISO with PowerShell 7 support,
    custom modules, and optimized WinPE configuration.
.PARAMETER WorkspacePath
    Path where the OSDCloud workspace will be created.
.PARAMETER CustomFilesPath
    Path containing custom files to be added to the workspace.
.PARAMETER TemplateName
    Name of the OSDCloud template to use.
.PARAMETER CompressISO
    Switch to compress the final ISO file using 7-Zip.
.PARAMETER Language
    Language to use for WinPE components. Default is "en-us".
.EXAMPLE
    .\Create-OSDCloudWorkspace.ps1 -WorkspacePath "F:\OSDCloudProd_master" -CustomFilesPath "G:\CustomFiles"
.EXAMPLE
    .\Create-OSDCloudWorkspace.ps1 -WorkspacePath "F:\OSDCloudProd_master" -CustomFilesPath "G:\CustomFiles" -CompressISO
.NOTES
    Requires administrative privileges and Windows ADK installation.
#>

[CmdletBinding()]
param(
	[string]$WorkspacePath = "F:\OSDCloudProd_master",
	[string]$CustomFilesPath = "G:\CustomFiles",
	[string]$TemplateName = "WinRE_prod",
	[string]$Language = "en-us",
	[switch]$CompressISO
)

#region Functions

function Add-WinPEPackage {
	param (
		[string]$PackagePath,
		[string]$LanguagePath,
		[string]$MountPath
	)

	Write-Host "Adding package: $PackagePath"

	# Use DISM from Windows ADK if available, otherwise use system DISM
	$dismExe = "dism.exe"

	& $dismExe /Image:"$MountPath" /Add-Package /PackagePath:"$PackagePath"
	if ($LASTEXITCODE -ne 0) {
		Write-Warning "Failed to add package: $PackagePath"
		return $false
	}

	if ($LanguagePath -and (Test-Path -Path $LanguagePath)) {
		Write-Host "Adding language package: $LanguagePath"
		& $dismExe /Image:"$MountPath" /Add-Package /PackagePath:"$LanguagePath"
		if ($LASTEXITCODE -ne 0) {
			Write-Warning "Failed to add language package: $LanguagePath"
			return $false
		}
	} else {
		Write-Warning "Language package not found or not specified: $LanguagePath"
	}

	return $true
}

function Set-OfflineRegistryValue {
	param (
		[string]$Path,
		[string]$Name,
		[string]$Type,
		[string]$Value
	)

	try {
		Write-Host "Setting registry value: $Name = $Value at $Path"
		$null = New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force -ErrorAction Stop
		return $true
	} catch {
		Write-Warning "Failed to set registry value $Name at $Path. Error: $($_.Exception.Message)"
		return $false
	}
}

function Clear-Environment {
	param (
		[switch]$Force,
		[string]$RegistryHive = "HKLM\OfflineWinPE",
		[string]$MountPath
	)

	$success = $true

	# Check if registry is loaded and unload it
	try {
		if (Test-Path "Registry::$RegistryHive") {
			Write-Host "Unloading registry hive: $RegistryHive"

			# Clean up variables and force garbage collection
			[System.GC]::Collect()
			Start-Sleep -Seconds 5

			# Unload registry
			$unloadResult = reg unload $RegistryHive 2>&1
			if ($LASTEXITCODE -ne 0) {
				Write-Warning "Failed to unload registry: $unloadResult"
				$success = $false

				if ($Force) {
					Write-Warning "Forcing process continuation despite registry unload failure"
				} else {
					return $false
				}
			}
		}
	} catch {
		Write-Warning "Error during registry cleanup: $($_.Exception.Message)"
		$success = $false
	}

	# Check if image is mounted and dismount it
	try {
		$mountedImages = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
		if ($mountedImages | Where-Object { $_.MountPath -eq $MountPath }) {
			Write-Host "Dismounting WinPE image from $MountPath"
			Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction Stop
			Write-Warning "Discarded changes to WinPE image due to cleanup"
		}
	} catch {
		Write-Warning "Failed to dismount WinPE image: $($_.Exception.Message)"
		$success = $false

		if ($Force) {
			Write-Warning "Forcing process continuation despite dismount failure"
		} else {
			return $false
		}
	}

	return $success
}

#endregion Functions

#region Main Script

# Start script execution
Write-Host "Starting OSDCloud workspace and ISO creation" -ForegroundColor Cyan

# Ensure running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
	Write-Error "Please run this script as Administrator."
	exit 1
}

# Register cleanup on script exit
$script:MountFolder = $null
trap {
	Write-Warning "Script execution interrupted. Performing cleanup..."
	if ($script:MountFolder) {
		Clear-Environment -Force -MountPath $script:MountFolder
	}
	break
}

# Install and import required modules (latest versions)
$modules = @("OSD", "Microsoft.Graph", "Az", "PackageManagement", "PSWindowsUpdate", "PowerShellGet")
foreach ($mod in $modules) {
	try {
		if (-not (Get-Module -ListAvailable -Name $mod)) {
			Write-Host "Installing module: $mod" -ForegroundColor Yellow
			Install-Module -Name $mod -Force -Scope AllUsers -AllowClobber
		}
		Write-Host "Importing module: $mod" -ForegroundColor Yellow
		Import-Module $mod -Force
	} catch {
		Write-Warning "Failed to install or import module: $mod - $($_.Exception.Message)"
	}
}

# Build a lookup for available modules (first available version)
$AvailableModules = @{}
foreach ($mod in $modules) {
	$modInfo = Get-Module -Name $mod -ListAvailable | Select-Object -First 1
	if ($modInfo) {
		$AvailableModules[$mod] = $modInfo.ModuleBase
		Write-Host "Located module: $mod at $($modInfo.ModuleBase)"
	}
}

# Import OSD module globally
Write-Host "Importing OSD module globally" -ForegroundColor Yellow
Import-Module OSD -Global -Force

# Define paths using Join-Path for clarity
$templateBase = Join-Path $env:ProgramData "OSDCloud\Templates"
$templatePath = Join-Path $templateBase $TemplateName
$bootWim      = Join-Path $templatePath "Media\sources\boot.wim"
$pwsh7Zip     = Join-Path $PSScriptRoot "PowerShell-7.5.0-win-x64.zip"
$wimFile      = Join-Path $CustomFilesPath "Windows11_24H2_Custom.wim"
$mediaFolder  = Join-Path $WorkspacePath "Media"
$osFolder     = Join-Path $mediaFolder "OSDCloud\OS"
$automateFolder = Join-Path $mediaFolder "OSDCloud\Automate"
$modulesFolder = Join-Path $mediaFolder "OSDCloud\Automate\Modules"

# Create required folders
$folders = @($WorkspacePath, $mediaFolder, $osFolder, $automateFolder, $modulesFolder)
foreach ($folder in $folders) {
	if (-not (Test-Path $folder)) {
		Write-Host "Creating folder: $folder"
		New-Item -Path $folder -ItemType Directory -Force | Out-Null
	}
}

# Create OSDCloud template with WinRE and 7Zip support
Write-Host "Creating OSDCloud template: $TemplateName" -ForegroundColor Cyan
New-OSDCloudTemplate -Name $TemplateName -WinRE -Add7Zip

# Define mount paths
$mountBase = Join-Path $env:TEMP "OSDCloudMount"
$mountFolder = Join-Path $mountBase "Mount"
$script:MountFolder = $mountFolder

# Ensure mount folders exist
New-Item -ItemType Directory -Path $mountFolder -Force | Out-Null

# Create a copy of boot.wim for mounting
$bootWimTemp = Join-Path $mountBase "boot.wim"
if (!(Test-Path -Path (Split-Path -Path $bootWimTemp -Parent))) {
	New-Item -Path (Split-Path -Path $bootWimTemp -Parent) -ItemType Directory -Force | Out-Null
}

Write-Host "Copying boot.wim to temporary location: $bootWimTemp"
Copy-Item -Path $bootWim -Destination $bootWimTemp -Force

# Mount the boot.wim
try {
	Write-Host "Mounting boot.wim to $mountFolder" -ForegroundColor Cyan
	Mount-WindowsImage -ImagePath $bootWimTemp -Path $mountFolder -Index 1 -ErrorAction Stop
} catch {
	Write-Error "Failed to mount the WinPE image: $($_.Exception.Message)"
	exit 1
}

# Add PowerShell 7
if (-not (Test-Path $pwsh7Zip)) {
	Write-Warning "PowerShell 7 ZIP not found at: $pwsh7Zip"
	$downloadPwsh = Read-Host "Would you like to download PowerShell 7.5.0? (Y/N)"
	if ($downloadPwsh -eq 'Y' -or $downloadPwsh -eq 'y') {
		$pwsh7Url = "https://github.com/PowerShell/PowerShell/releases/download/v7.5.0/PowerShell-7.5.0-win-x64.zip"
		Write-Host "Downloading PowerShell 7 from $pwsh7Url" -ForegroundColor Yellow
		Invoke-WebRequest -Uri $pwsh7Url -OutFile $pwsh7Zip
	} else {
		Write-Error "PowerShell 7 ZIP is required but not found. Script cannot continue."
		Cleanup-Environment -Force -MountPath $mountFolder
		exit 1
	}
}

# Install PowerShell 7
$pwsh7Path = Join-Path $mountFolder "Program Files\PowerShell\7"
Write-Host "Creating PowerShell 7 directory: $pwsh7Path"
New-Item -ItemType Directory -Path $pwsh7Path -Force | Out-Null

Write-Host "Extracting PowerShell 7 to $pwsh7Path" -ForegroundColor Cyan
try {
	Expand-Archive -Path $pwsh7Zip -DestinationPath $pwsh7Path -Force
} catch {
	Write-Error "Failed to extract PowerShell 7: $($_.Exception.Message)"
	Cleanup-Environment -Force -MountPath $mountFolder
	exit 1
}

# Add native WinPE optional components
$WinPE_OCs_Path = Join-Path $env:ProgramFiles "Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs"
$WinPE_Lang_Path = Join-Path $WinPE_OCs_Path "$Language"

if (Test-Path $WinPE_OCs_Path) {
	Write-Host "Adding WinPE optional components from $WinPE_OCs_Path" -ForegroundColor Cyan

	# Define packages to add
	$packages = @(
		@{Package = Join-Path -Path $WinPE_OCs_Path -ChildPath "WinPE-WMI.cab";
			Language = Join-Path -Path $WinPE_Lang_Path -ChildPath "WinPE-WMI_$Language.cab"
		},
		@{Package = Join-Path -Path $WinPE_OCs_Path -ChildPath "WinPE-NetFx.cab";
			Language = Join-Path -Path $WinPE_Lang_Path -ChildPath "WinPE-NetFx_$Language.cab"
		},
		@{Package = Join-Path -Path $WinPE_OCs_Path -ChildPath "WinPE-PowerShell.cab";
			Language = Join-Path -Path $WinPE_Lang_Path -ChildPath "WinPE-PowerShell_$Language.cab"
		},
		@{Package = Join-Path -Path $WinPE_OCs_Path -ChildPath "WinPE-DismCmdlets.cab";
			Language = Join-Path -Path $WinPE_Lang_Path -ChildPath "WinPE-DismCmdlets_$Language.cab"
		},
		@{Package = Join-Path -Path $WinPE_OCs_Path -ChildPath "WinPE-EnhancedStorage.cab";
			Language = Join-Path -Path $WinPE_Lang_Path -ChildPath "WinPE-EnhancedStorage_$Language.cab"
		},
		@{Package = Join-Path -Path $WinPE_OCs_Path -ChildPath "WinPE-StorageWMI.cab";
			Language = Join-Path -Path $WinPE_Lang_Path -ChildPath "WinPE-StorageWMI_$Language.cab"
		},
		@{Package = Join-Path -Path $WinPE_OCs_Path -ChildPath "WinPE-Scripting.cab";
			Language = Join-Path -Path $WinPE_Lang_Path -ChildPath "WinPE-Scripting_$Language.cab"
		}
	)

	$packageSuccess = $true
	foreach ($pkg in $packages) {
		if (Test-Path $pkg.Package) {
			if (-not (Add-WinPEPackage -PackagePath $pkg.Package -LanguagePath $pkg.Language -MountPath $mountFolder)) {
				$packageSuccess = $false
				Write-Warning "Package installation failed for $($pkg.Package). Continuing with available components."
			}
		} else {
			Write-Warning "Package not found: $($pkg.Package)"
		}
	}

	if ($packageSuccess) {
		Write-Host "All WinPE packages were installed successfully." -ForegroundColor Green
	} else {
		Write-Warning "Some WinPE packages failed to install. WinPE functionality may be limited."
	}
} else {
	Write-Warning "WinPE components path not found: $WinPE_OCs_Path"
	Write-Warning "Skipping WinPE component installation"
}

# Inject modules using pre-cached lookup
foreach ($mod in $modules) {
	if ($AvailableModules.ContainsKey($mod)) {
		$modPath = $AvailableModules[$mod]
		$modDirName = Split-Path $modPath -Leaf
		$target = Join-Path $mountFolder "Program Files\WindowsPowerShell\Modules\$modDirName"

		# Create module directory if it doesn't exist
		Write-Host "Copying module $mod to $target"
		New-Item -ItemType Directory -Path $target -Force | Out-Null
		Copy-Item -Path $modPath -Destination $target -Recurse -Force
	}
}

# Update the offline environment PATH for PowerShell 7
$HivePath = Join-Path -Path $mountFolder -ChildPath "Windows\System32\config\SYSTEM"
try {
	Write-Host "Loading registry hive from $HivePath" -ForegroundColor Cyan
	$regLoadOutput = reg load "HKLM\OfflineWinPE" $HivePath 2>&1
	if ($LASTEXITCODE -ne 0) {
		Write-Error "Failed to load registry hive: $regLoadOutput"
		Clear-Environment -MountPath $mountFolder -Force
		exit 1
	}

	Start-Sleep -Seconds 5

	# Add PowerShell 7 Paths to Path and PSModulePath
	$RegistryKey = "HKLM:\OfflineWinPE\ControlSet001\Control\Session Manager\Environment"

	# Ensure the registry key exists
	if (!(Test-Path -Path $RegistryKey)) {
		Write-Host "Creating registry key: $RegistryKey"
		$null = New-Item -Path $RegistryKey -Force
	}

	# Get current Path value
	$CurrentPath = (Get-ItemProperty -Path $RegistryKey -Name "Path" -ErrorAction SilentlyContinue).Path
	if (-not $CurrentPath) {
		$CurrentPath = ""
		Write-Warning "No existing PATH found, creating new one"
	}

	$NewPath = $CurrentPath + ";%ProgramFiles%\PowerShell\7\"

	# Get current PSModulePath value
	$CurrentPSModulePath = (Get-ItemProperty -Path $RegistryKey -Name "PSModulePath" -ErrorAction SilentlyContinue).PSModulePath
	if (-not $CurrentPSModulePath) {
		$CurrentPSModulePath = ""
		Write-Warning "No existing PSModulePath found, creating new one"
	}

	$NewPSModulePath = $CurrentPSModulePath + ";%ProgramFiles%\PowerShell\;%ProgramFiles%\PowerShell\7\;%SystemRoot%\system32\config\systemprofile\Documents\PowerShell\Modules\"

	# Set registry values with improved error handling
	$regValues = @(
		@{Path = $RegistryKey; Name = "Path"; Type = "ExpandString"; Value = $NewPath },
		@{Path = $RegistryKey; Name = "PSModulePath"; Type = "ExpandString"; Value = $NewPSModulePath },
		@{Path = $RegistryKey; Name = "APPDATA"; Type = "String"; Value = "%SystemRoot%\System32\Config\SystemProfile\AppData\Roaming" },
		@{Path = $RegistryKey; Name = "HOMEDRIVE"; Type = "String"; Value = "%SystemDrive%" },
		@{Path = $RegistryKey; Name = "HOMEPATH"; Type = "String"; Value = "%SystemRoot%\System32\Config\SystemProfile" },
		@{Path = $RegistryKey; Name = "LOCALAPPDATA"; Type = "String"; Value = "%SystemRoot%\System32\Config\SystemProfile\AppData\Local" }
	)

	$registrySuccess = $true
	foreach ($reg in $regValues) {
		if (-not (Set-OfflineRegistryValue -Path $reg.Path -Name $reg.Name -Type $reg.Type -Value $reg.Value)) {
			$registrySuccess = $false
		}
	}

	if (-not $registrySuccess) {
		Write-Warning "Some registry operations failed. WinPE environment may not function as expected."
	}

	# Cleanup registry resources
	Remove-Variable -Name RegistryKey -ErrorAction SilentlyContinue
	[System.GC]::Collect()
	Start-Sleep -Seconds 5

	# Unload the registry hive
	Write-Host "Unloading registry hive" -ForegroundColor Cyan
	$regUnloadOutput = reg unload "HKLM\OfflineWinPE" 2>&1
	if ($LASTEXITCODE -ne 0) {
		Write-Warning "Failed to unload registry hive: $regUnloadOutput"
	}
} catch {
	Write-Error "Registry operation failed: $($_.Exception.Message)"
	# Try to unload registry if it was loaded
	reg unload "HKLM\OfflineWinPE" 2>$null
	Clear-Environment -MountPath $mountFolder -Force
	exit 1
}

# Write winpeshl.ini that launches PowerShell 7
$winpeshlPath = Join-Path -Path $mountFolder -ChildPath "Windows\System32\winpeshl.ini"
Write-Host "Creating winpeshl.ini at $winpeshlPath"
@'
[LaunchApps]
%WINDIR%\System32\wpeinit.exe
%ProgramFiles%\PowerShell\7\pwsh.exe -NoExit -ExecutionPolicy Bypass -Command "& { Set-Location X:\OSDCloud }"
'@ | Out-File -FilePath $winpeshlPath -Encoding utf8 -Force

# Copy custom scripts (if available)
$modularFolders = @("Main", "Autopilot", "Modules", "Assets")
foreach ($folder in $modularFolders) {
	$srcFolder = Join-Path $CustomFilesPath $folder
	$dstFolder = Join-Path $mountFolder "OSDCloud\Automate\$folder"

	if (Test-Path $srcFolder) {
		# Create destination directory if it doesn't exist
		Write-Host "Copying $folder scripts from $srcFolder to $dstFolder"
		New-Item -ItemType Directory -Path $dstFolder -Force | Out-Null
		Copy-Item -Path "$srcFolder\*" -Destination $dstFolder -Recurse -Force
	} else {
		Write-Host "Creating empty $folder directory: $dstFolder"
		New-Item -ItemType Directory -Path $dstFolder -Force | Out-Null
	}
}

# Create startnet.cmd for auto-launching custom scripts
$startnetPath = Join-Path -Path $mountFolder -ChildPath "Windows\System32\startnet.cmd"
Write-Host "Creating custom startnet.cmd at $startnetPath"
@"
@echo off
wpeinit
set ENTRY_SCRIPT=
IF EXIST X:\OSDCloud\Automate\Main\iTechDcUI.ps1 (set ENTRY_SCRIPT=X:\OSDCloud\Automate\Main\iTechDcUI.ps1)
IF NOT "%ENTRY_SCRIPT%"=="" (
    IF EXIST %ProgramFiles%\PowerShell\7\pwsh.exe (
        %ProgramFiles%\PowerShell\7\pwsh.exe -NoL -ExecutionPolicy Bypass -Command "& {
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Modules' -Filter *.psm1 -Recurse | ForEach-Object { Import-Module \$_.FullName -Force }
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Main' -Filter *.ps1 -Recurse | ForEach-Object { . \$_.FullName }
            . '%ENTRY_SCRIPT%'
        }"
    ) ELSE (
        PowerShell -NoL -ExecutionPolicy Bypass -Command "& {
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Modules' -Filter *.psm1 -Recurse | ForEach-Object { Import-Module \$_.FullName -Force }
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Main' -Filter *.ps1 -Recurse | ForEach-Object { . \$_.FullName }
            . '%ENTRY_SCRIPT%'
        }"
    )
)
"@ | Out-File -FilePath $startnetPath -Encoding ASCII -Force

# Write unattend.xml file to change screen resolution
$unattendPath = Join-Path -Path $mountFolder -ChildPath "Unattend.xml"
Write-Host "Creating unattend.xml at $unattendPath"
@'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <Display>
                <ColorDepth>32</ColorDepth>
                <HorizontalResolution>1280</HorizontalResolution>
                <RefreshRate>60</RefreshRate>
                <VerticalResolution>720</VerticalResolution>
            </Display>
        </component>
    </settings>
</unattend>
'@ | Out-File -FilePath $unattendPath -Encoding utf8 -Force

# Unmount the WinPE image and save changes
try {
	Write-Host "Unmounting and saving WinPE image" -ForegroundColor Cyan
	Dismount-WindowsImage -Path $mountFolder -Save -ErrorAction Stop
	Write-Host "Successfully saved WinPE image" -ForegroundColor Green
} catch {
	Write-Error "Failed to unmount and save the WinPE image: $($_.Exception.Message)"
	Clear-Environment -MountPath $mountFolder -Force
	exit 1
}

# Copy the modified boot.wim back to the template
Write-Host "Copying modified boot.wim back to template"
Copy-Item -Path $bootWimTemp -Destination $bootWim -Force

# Clean up temporary files
Write-Host "Cleaning up temporary files"
if (Test-Path $mountBase) {
	Remove-Item -Path $mountBase -Recurse -Force -ErrorAction SilentlyContinue
}

# Create workspace
Write-Host "Creating OSDCloud workspace at $WorkspacePath" -ForegroundColor Cyan
New-OSDCloudWorkspace -WorkspacePath $WorkspacePath

# Optional custom WIM with optimization
if (Test-Path $wimFile) {
	$destWim = Join-Path $osFolder "CustomImage.wim"
	Write-Host "Copying custom WIM from $wimFile to $destWim"
	Copy-Item -Path $wimFile -Destination $destWim -Force

	# Optimize WIM compression (Maximum)
	Write-Host "Optimizing WIM compression" -ForegroundColor Cyan
	$tempWim = "$destWim.temp"
	$compressArgs = @(
		"/Export-Image"
		"/SourceImageFile:$destWim"
		"/SourceIndex:1"
		"/DestinationImageFile:$tempWim"
		"/Compress:maximum"
	)

	$proc = Start-Process -FilePath "dism.exe" -ArgumentList $compressArgs -NoNewWindow -Wait -PassThru
	if ($proc.ExitCode -eq 0) {
		Move-Item -Path $tempWim -Destination $destWim -Force
		Write-Host "WIM optimization completed successfully" -ForegroundColor Green
	} else {
		Write-Warning "WIM optimization failed (DISM exit code: $($proc.ExitCode))"
	}
}

# Save the startnet.cmd content for Edit-OSDCloudWinPE
$startnetContent = @"
@echo off
wpeinit
set ENTRY_SCRIPT=
IF EXIST X:\OSDCloud\Automate\Main\iTechDcUI.ps1 (set ENTRY_SCRIPT=X:\OSDCloud\Automate\Main\iTechDcUI.ps1)
IF NOT "%ENTRY_SCRIPT%"=="" (
    IF EXIST %ProgramFiles%\PowerShell\7\pwsh.exe (
        %ProgramFiles%\PowerShell\7\pwsh.exe -NoL -ExecutionPolicy Bypass -Command "& {
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Modules' -Filter *.psm1 -Recurse | ForEach-Object { Import-Module \$_.FullName -Force }
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Main' -Filter *.ps1 -Recurse | ForEach-Object { . \$_.FullName }
            . '%ENTRY_SCRIPT%'
        }"
    ) ELSE (
        PowerShell -NoL -ExecutionPolicy Bypass -Command "& {
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Modules' -Filter *.psm1 -Recurse | ForEach-Object { Import-Module \$_.FullName -Force }
            Get-ChildItem -Path 'X:\OSDCloud\Automate\Main' -Filter *.ps1 -Recurse | ForEach-Object { . \$_.FullName }
            . '%ENTRY_SCRIPT%'
        }"
    )
)
"@

# Apply custom startnet.cmd to workspace
Write-Host "Applying custom startnet.cmd to workspace" -ForegroundColor Cyan
Edit-OSDCloudWinPE -WorkspacePath $WorkspacePath -Startnet $startnetContent -CloudDriver "*" -Add7Zip -WirelessConnect

# Create ISO
Write-Host "Creating OSDCloud ISO at $WorkspacePath" -ForegroundColor Cyan
New-OSDCloudISO -WorkspacePath $WorkspacePath

# Compress ISO if requested
if ($CompressISO) {
	$isoPath = Join-Path $WorkspacePath "OSDCloud.iso"
	$compressed = Join-Path $WorkspacePath "OSDCloud_compressed.iso"

	if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
		Write-Host "Compressing ISO using 7-Zip" -ForegroundColor Cyan
		$compressArgs = @(
			"a"
			"-tzip"
			"`"$compressed`""
			"`"$isoPath`""
		)

		Start-Process -Wait -NoNewWindow -FilePath "7z.exe" -ArgumentList $compressArgs
		Move-Item -Path $compressed -Destination $isoPath -Force
		Write-Host "ISO compression completed" -ForegroundColor Green
	} else {
		Write-Warning "7-Zip not found. Cannot compress ISO."
	}
}

Write-Host "Script completed successfully" -ForegroundColor Green
Write-Host "ISO ready at: $WorkspacePath\OSDCloud.iso" -ForegroundColor Green

Write-Host "`n✅ Script completed. ISO ready at: $WorkspacePath\OSDCloud.iso" -ForegroundColor Green

#endregion Main Script