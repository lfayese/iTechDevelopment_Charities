<#
.Synopsis
    Sample script for Deployment Research
.DESCRIPTION
    Created: 2022-07-01
    Version: 1.0

    Author : Johan Arwidmark
    Twitter: @jarwidmark
    Blog   : https://deploymentresearch.com

    Disclaimer: This script is provided "AS IS" with no warranties, confers no rights and
    is not supported by the author or DeploymentArtist..
.EXAMPLE
    N/A
#>

#Requires -RunAsAdministrator

# Settings
$PowerShell7File = "$PSScriptRoot\PowerShell-7.5.0-win-x64.zip"
$WinPE_BuildFolder = "C:\Setup\WinPE_x64"
$WinPE_Architecture = "amd64" # Or x86
$WinPE_MountFolder = "C:\Mount"
$WinPE_ISOFolder = "C:\ISO"
$WinPE_ISOfile = "$WinPE_ISOFolder\WinPE11_x64_PowerShell7.iso"

$ADK_Path = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$WinPE_ADK_Path = $ADK_Path + "\Windows Preinstallation Environment"
$WinPE_OCs_Path = $WinPE_ADK_Path + "\$WinPE_Architecture\WinPE_OCs"
$DISM_Path = $ADK_Path + "\Deployment Tools" + "\$WinPE_Architecture\DISM"
$OSCDIMG_Path = $ADK_Path + "\Deployment Tools" + "\$WinPE_Architecture\Oscdimg"

# Validate ADK installation and required paths
If (!(Test-path $ADK_Path)){ Write-Warning "ADK Path does not exist, aborting..."; Break }
If (!(Test-path $WinPE_ADK_Path)){ Write-Warning "WinPE ADK Path does not exist, aborting..."; Break }
If (!(Test-path $OSCDIMG_Path)){ Write-Warning "OSCDIMG Path does not exist, aborting..."; Break }
If (!(Test-path $PowerShell7File)){ Write-Warning "PowerShell7File Path does not exist, aborting..."; Break }


# Delete existing WinPE build folder (if exist)
try {
	if (Test-Path -path $WinPE_BuildFolder) { Remove-Item -Path $WinPE_BuildFolder -Recurse -Force -ErrorAction Stop }
} catch {
	Write-Warning "Oupps, Error: $($_.Exception.Message)"
	Write-Warning "Most common reason is existing WIM still mounted, use DISM /Cleanup-Wim to clean up and run script again"
	Break
}

# Create Mount folder
New-Item -Path $WinPE_MountFolder -ItemType Directory -Force

# Create ISO folder
New-Item -Path $WinPE_ISOFolder -ItemType Directory -Force

# Make a copy of the WinPE boot image from Windows ADK
if (!(Test-Path -path "$WinPE_BuildFolder\Sources")) { New-Item "$WinPE_BuildFolder\Sources" -Type Directory -Force }
Copy-Item "$WinPE_ADK_Path\$WinPE_Architecture\en-us\winpe.wim" "$WinPE_BuildFolder\Sources\boot.wim" -Force

# Copy WinPE boot files
Copy-Item "$WinPE_ADK_Path\$WinPE_Architecture\Media\*" "$WinPE_BuildFolder" -Recurse -Force

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
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\WinPE-NetFx.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\en-us\WinPE-NetFx_en-us.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\WinPE-PowerShell.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\en-us\WinPE-PowerShell_en-us.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\WinPE-DismCmdlets.cab"
& "$DISM_Path\dism.exe" /Image:"$WinPE_MountFolder" /Add-Package /PackagePath:"$WinPE_OCs_Path\en-us\WinPE-DismCmdlets_en-us.cab"

# Add PowerShell 7
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

# Write winpeshl.ini that launches PowerShell 7
@'
[LaunchApps]
%WINDIR%\System32\wpeinit.exe
%ProgramFiles%\PowerShell\7\pwsh.exe
'@ | Out-File "$WinPE_MountFolder\Windows\System32\winpeshl.ini" -Encoding utf8 -Force

# Write unattend.xml file to change screen resolution
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
'@ | Out-File "$WinPE_MountFolder\Unattend.xml" -Encoding utf8 -Force

# Unmount the WinPE image and save changes
try {
	Dismount-WindowsImage -Path $WinPE_MountFolder -Save -ErrorAction Stop
	Write-Host "Successfully saved WinPE image" -ForegroundColor Green
} catch {
	Write-Warning "Failed to unmount and save the WinPE image: $($_.Exception.Message)"
	Break
}

# Create a bootable WinPE ISO file
$BootData='2#p0,e,b"{0}"#pEF,e,b"{1}"' -f "$OSCDIMG_Path\etfsboot.com","$OSCDIMG_Path\efisys.bin"

try {
	$Proc = Start-Process -FilePath "$OSCDIMG_Path\oscdimg.exe" -ArgumentList @("-bootdata:$BootData",'-u2','-udfver102',"$WinPE_BuildFolder","$WinPE_ISOfile") -PassThru -Wait -NoNewWindow
	if($Proc.ExitCode -ne 0) {
		Throw "Failed to generate ISO with exitcode: $($Proc.ExitCode)"
	} else {
		Write-Host "Successfully created bootable ISO at: $WinPE_ISOfile" -ForegroundColor Green
	}
} catch {
	Write-Warning "Error creating ISO: $($_.Exception.Message)"
}
