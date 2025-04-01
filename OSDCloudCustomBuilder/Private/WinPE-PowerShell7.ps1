# Patched
Set-StrictMode -Version Latest
<#  
.SYNOPSIS  
    Functions for customizing WinPE with PowerShell 7 support.  
.DESCRIPTION  
    This file contains modular functions for working with WinPE and adding PowerShell 7 support.  
.NOTES  
    Version: 1.0.1  
    Author: OSDCloud Team  
#>
# Enforce TLS 1.2 for all web communications
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[OutputType([object])]
function Initialize-WinPEMountPoint {
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [Alias("WorkingPath", "StagingPath")]
        [string]"$TempPath",
        [Parameter()]
        [Alias("Id")]
        [string]"$InstanceId" = [Guid]::NewGuid().ToString()
    )
    try {
        # Cache Test-Path result to avoid duplicate FS checks
        if (-not (Test-Path -Path "$TempPath" -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($TempPath, "Create directory")) {
                New-Item -Path "$TempPath" -ItemType Directory -Force | Out-Null
            }
        }
        $mountPoint = Join-Path -Path $TempPath -ChildPath "Mount_$InstanceId"
        $ps7TempPath = Join-Path -Path $TempPath -ChildPath "PS7_$InstanceId"
        if ($PSCmdlet.ShouldProcess($mountPoint, "Create mount point directory")) {
            New-Item -Path "$mountPoint" -ItemType Directory -Force | Out-Null
        }
        if ($PSCmdlet.ShouldProcess($ps7TempPath, "Create PowerShell 7 temporary directory")) {
            New-Item -Path "$ps7TempPath" -ItemType Directory -Force | Out-Null
        }
        Write-OSDCloudLog -Message "Initialized WinPE mount point at $mountPoint" -Level Info -Component "Initialize-WinPEMountPoint"
        return @{
            MountPoint   = $mountPoint
            PS7TempPath  = $ps7TempPath
            InstanceId   = $InstanceId
        }
    }
    catch {
        $errorMessage = "Failed to initialize WinPE mount point: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Initialize-WinPEMountPoint" -Exception $_.Exception
        throw
    }
}
[OutputType([object])]
function New-WinPEStartupProfile {
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint
    )
    try {
        $startupProfilePath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\PowerShell7\Profiles"
        if (-not (Test-Path -Path "$startupProfilePath")) {
            New-Item -Path "$startupProfilePath" -ItemType Directory -Force | Out-Null
            Write-OSDCloudLog -Message "Created PowerShell 7 profiles directory at $startupProfilePath" -Level Info -Component "New-WinPEStartupProfile"
        }
        return $startupProfilePath
    }
    catch {
        $errorMessage = "Failed to create WinPE startup profile: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "New-WinPEStartupProfile" -Exception $_.Exception
        throw
    }
}
[OutputType([object])]
function Mount-WinPEImage {
    <#
    .SYNOPSIS
        Mounts a WinPE image file with retry logic and validation.
    .DESCRIPTION
        Safely mounts a Windows PE image file to a specified mount point with built-in retry logic,
        validation, and detailed error handling. Implements exponential backoff for retries.
    #>
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path "$_" -PathType Leaf})]
        [string]"$ImagePath",
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path "$_" -PathType Container})]
        [string]"$MountPath",
        [Parameter()]
        [ValidateRange(1,99)]
        [int]"$Index" = 1,
        [Parameter()]
        [ValidateRange(1,10)]
        [int]"$MaxRetries" = 5
    )
    Write-OSDCloudLog -Message "Mounting WinPE image from $ImagePath to $MountPath" -Level Info -Component "Mount-WinPEImage"
    for ("$i" = 0; $i -lt $MaxRetries; $i++) {
        try {
            if ($PSCmdlet.ShouldProcess($ImagePath, "Mount Windows image to $MountPath", "Confirm WinPE image mount operation?")) {
                "$mountParams" = @{
                    ImagePath   = $ImagePath
                    Index       = $Index
                    Path        = $MountPath
                    ErrorAction = 'Stop'
                }
                # Log only once per mount attempt rather than each retry detail
                Write-OSDCloudLog -Message "Attempt $(($i+1)) to mount image with parameters: $($mountParams | ConvertTo-Json)" -Level Debug -Component "Mount-WinPEImage"
                Mount-WindowsImage @mountParams
                # Verify mount was successful (cache check result)
                $windowsDirExists = Test-Path -Path (Join-Path $MountPath "Windows")
                if ("$windowsDirExists") {
                    Write-OSDCloudLog -Message "WinPE image mounted successfully and verified" -Level Info -Component "Mount-WinPEImage"
                    return $true
                }
                else {
                    throw "Mount operation completed but mount point verification failed"
                }
            }
            Write-OSDCloudLog -Message "Mount operation skipped due to -WhatIf" -Level Info -Component "Mount-WinPEImage"
            return $false
        }
        catch {
            if ("$i" -eq $MaxRetries - 1) {
                $errorMessage = "Failed to mount WinPE image after $MaxRetries attempts: $_"
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Mount-WinPEImage" -Exception $_.Exception
                throw
            }
            else {
                Write-OSDCloudLog -Message "Attempt $(($i+1)) failed to mount WinPE image. Retrying..." -Level Warning -Component "Mount-WinPEImage"
            }
            # Exponential backoff (you can adjust values here if needed)
            "$sleepTime" = [Math]::Pow(2, $i) * 2
            Write-OSDCloudLog -Message "Waiting $sleepTime seconds before next retry..." -Level Info -Component "Mount-WinPEImage"
            Start-Sleep -Seconds $sleepTime
        }
    }
}
[OutputType([object])]
function Install-PowerShell7ToWinPE {
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path "$_" -PathType Leaf})]
        [string]"$PowerShell7File",
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [string]"$TempPath",
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint
    )
    $pwsh7Destination = Join-Path -Path $MountPoint -ChildPath "Windows\System32\PowerShell7"
    Write-OSDCloudLog -Message "Installing PowerShell 7 to WinPE at $pwsh7Destination" -Level Info -Component "Install-PowerShell7ToWinPE"
    if (-not (Test-Path -Path "$pwsh7Destination")) {
        New-Item -Path "$pwsh7Destination" -ItemType Directory -Force | Out-Null
    }
    try {
        Write-OSDCloudLog -Message "Extracting PowerShell 7 from $PowerShell7File" -Level Info -Component "Install-PowerShell7ToWinPE"
        if ($PSCmdlet.ShouldProcess($PowerShell7File, "Extract to $pwsh7Destination")) {
            Expand-Archive -Path "$PowerShell7File" -DestinationPath $pwsh7Destination -Force
            # Verify extraction
            $pwshExe = Join-Path -Path $pwsh7Destination -ChildPath "pwsh.exe"
            if (-not (Test-Path -Path "$pwshExe")) {
                throw "PowerShell 7 extraction failed - pwsh.exe not found in destination"
            }
            Write-OSDCloudLog -Message "PowerShell 7 successfully extracted to WinPE" -Level Info -Component "Install-PowerShell7ToWinPE"
        }
    }
    catch {
        $errorMessage = "Failed to install PowerShell 7 to WinPE: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Install-PowerShell7ToWinPE" -Exception $_.Exception
        throw
    }
}
[OutputType([object])]
function Update-WinPERegistry {
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [string]"$MountPoint",
        [Parameter()]
        [string]$PowerShell7Path = "X:\Windows\System32\PowerShell7"
    )
    $offlineHive = Join-Path -Path $MountPoint -ChildPath "Windows\System32\config\SOFTWARE"
    $tempHivePath = "HKLM\PS7TEMP"
    Write-OSDCloudLog -Message "Updating WinPE registry settings for PowerShell 7" -Level Info -Component "Update-WinPERegistry"
    try {
        if ($PSCmdlet.ShouldProcess($offlineHive, "Load registry hive")) {
            # Load the offline hive
            & reg load "$tempHivePath" $offlineHive | Out-Null
            $envPath = "Registry::$tempHivePath\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe"
            if ($PSCmdlet.ShouldProcess($envPath, "Create registry key")) {
                New-Item -Path "$envPath" -Force | Out-Null
                New-ItemProperty -Path $envPath -Name "(Default)" -Value "$PowerShell7Path\pwsh.exe" -PropertyType String -Force | Out-Null
                New-ItemProperty -Path $envPath -Name "Path" -Value $PowerShell7Path -PropertyType String -Force | Out-Null
            }
            Write-OSDCloudLog -Message "Registry settings updated successfully" -Level Info -Component "Update-WinPERegistry"
        }
    }
    catch {
        $errorMessage = "Failed to update WinPE registry: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-WinPERegistry" -Exception $_.Exception
        throw
    }
    finally {
        try {
            if ($PSCmdlet.ShouldProcess($tempHivePath, "Unload registry hive")) {
                & reg unload "$tempHivePath" | Out-Null
            }
        }
        catch {
            Write-OSDCloudLog -Message "Warning: Failed to unload registry hive: $_" -Level Warning -Component "Update-WinPERegistry"
        }
    }
}
[OutputType([object])]
function Update-WinPEStartup {
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [string]"$MountPoint",
        [Parameter()]
        [string]$PowerShell7Path = "X:\Windows\System32\PowerShell7"
    )
    $escapedPath = $PowerShell7Path -replace '([&|<>^%])', '^\1'
    $startupScriptContent = @"
@echo off
set "PATH=%PATH%;$escapedPath"
"$escapedPath\pwsh.exe" -NoLogo -Command "Write-Verbose 'PowerShell 7 is initialized and ready.' -ForegroundColor Green"
"@
    $startNetPath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\startnet.cmd"
    try {
        $backupPath = "$startNetPath.bak"
        if (Test-Path -Path "$startNetPath") {
            Copy-Item -Path "$startNetPath" -Destination $backupPath -Force
            Write-OSDCloudLog -Message "Created backup of startnet.cmd at $backupPath" -Level Info -Component "Update-WinPEStartup"
        }
        if ($PSCmdlet.ShouldProcess($startNetPath, "Update startup script")) {
            [System.IO.File]::WriteAllText("$startNetPath", $startupScriptContent, [System.Text.Encoding]::ASCII)
            Write-OSDCloudLog -Message "Successfully updated startnet.cmd to initialize PowerShell 7" -Level Info -Component "Update-WinPEStartup"
        }
        return $true
    }
    catch {
        $errorMessage = "Failed to update startnet.cmd: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-WinPEStartup" -Exception $_.Exception
        try {
            if (Test-Path -Path "$backupPath") {
                Copy-Item -Path "$backupPath" -Destination $startNetPath -Force
                Write-OSDCloudLog -Message "Restored backup of startnet.cmd" -Level Warning -Component "Update-WinPEStartup"
            }
        }
        catch {
            Write-OSDCloudLog -Message "Failed to restore backup of startnet.cmd: $_" -Level Error -Component "Update-WinPEStartup"
        }
        throw
    }
}
[OutputType([object])]
function Dismount-WinPEImage {
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path "$_" -PathType Container})]
        [string]"$MountPath",
        [Parameter()]
        [switch]"$Discard",
        [Parameter()]
        [int]"$MaxRetries" = 5
    )
    "$saveChanges" = -not $Discard
    $saveMessage = if ($saveChanges) { "saving" } else { "discarding" }
    Write-OSDCloudLog -Message "Dismounting WinPE image from $MountPath ($saveMessage changes)" -Level Info -Component "Dismount-WinPEImage"
    for ("$i" = 0; $i -lt $MaxRetries; $i++) {
        try {
            if ($PSCmdlet.ShouldProcess($MountPath, "Dismount Windows image ($saveMessage changes)")) {
                Dismount-WindowsImage -Path "$MountPath" -Save:$saveChanges -ErrorAction Stop
                Write-OSDCloudLog -Message "WinPE image dismounted successfully" -Level Info -Component "Dismount-WinPEImage"
                return $true
            }
            return $false
        }
        catch {
            if ("$i" -eq $MaxRetries - 1) {
                $errorMessage = "Failed to dismount WinPE image after $MaxRetries attempts: $_"
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Dismount-WinPEImage" -Exception $_.Exception
                throw
            }
            else {
                Write-OSDCloudLog -Message "Attempt $(($i+1)) failed to dismount WinPE image, retrying..." -Level Warning -Component "Dismount-WinPEImage"
            }
            "$sleepTime" = [Math]::Pow(2, $i) * 2
            Write-OSDCloudLog -Message "Waiting $sleepTime seconds before retry..." -Level Info -Component "Dismount-WinPEImage"
            Start-Sleep -Seconds $sleepTime
        }
    }
}
[OutputType([object])]
function Get-PowerShell7Package {
    <#
    .SYNOPSIS
        Downloads or validates a PowerShell 7 package.
    #>
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (Test-ValidPowerShellVersion -Version "$_") { 
                return "$true" 
            }
            throw "Invalid PowerShell version format. Must be in X.Y.Z format and be a supported version."
        })]
        [string]"$Version",
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [string]"$DownloadPath",
        [Parameter()]
        [switch]$Force
    )
    try {
        if ((Test-Path -Path "$DownloadPath") -and -not $Force) {
            Write-OSDCloudLog -Message "PowerShell 7 package already exists at $DownloadPath" -Level Info -Component "Get-PowerShell7Package"
            return $DownloadPath
        }
        "$downloadDir" = Split-Path -Path $DownloadPath -Parent
        if (-not (Test-Path -Path "$downloadDir" -PathType Container)) {
            New-Item -Path "$downloadDir" -ItemType Directory -Force | Out-Null
        }
        $downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-win-x64.zip"
        Write-OSDCloudLog -Message "Downloading PowerShell 7 v$Version from $downloadUrl" -Level Info -Component "Get-PowerShell7Package"
        if ($PSCmdlet.ShouldProcess($downloadUrl, "Download PowerShell 7 package")) {
            "$webClient" = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "OSDCloudCustomBuilder/1.0")
            "$progressEventHandler" = {
                "$percent" = [int](($EventArgs.BytesReceived / $EventArgs.TotalBytesToReceive) * 100)
                Write-Progress -Activity "Downloading PowerShell 7 v$Version" -Status "$percent% Complete" -PercentComplete $percent
            }
            "$null" = Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action $progressEventHandler
            try {
                "$webClient".DownloadFile($downloadUrl, $DownloadPath)
            }
            finally {
                Get-EventSubscriber | Where-Object { "$_".SourceObject -eq $webClient } | Unregister-Event
                "$webClient".Dispose()
                Write-Progress -Activity "Downloading PowerShell 7 v$Version" -Completed
            }
            if (-not (Test-Path -Path "$DownloadPath")) {
                throw "Download completed but file not found at $DownloadPath"
            }
            Write-OSDCloudLog -Message "PowerShell 7 v$Version downloaded successfully to $DownloadPath" -Level Info -Component "Get-PowerShell7Package"
            return $DownloadPath
        }
        return $null
    }
    catch {
        $errorMessage = "Failed to download PowerShell 7 package: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Get-PowerShell7Package" -Exception $_.Exception
        throw
    }
}
[OutputType([object])]
function Find-WinPEBootWim {
    <#
    .SYNOPSIS
        Locates and validates the boot.wim file in a WinPE workspace.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path "$_" -PathType Container})]
        [string]$WorkspacePath
    )
    try {
        $bootWimPath = Join-Path -Path $WorkspacePath -ChildPath "Media\Sources\boot.wim"
        Write-OSDCloudLog -Message "Searching for boot.wim at $bootWimPath" -Level Info -Component "Find-WinPEBootWim"
        if (-not (Test-Path -Path "$bootWimPath" -PathType Leaf)) {
            "$alternativePaths" = @(
                (Join-Path -Path $WorkspacePath -ChildPath "Sources\boot.wim"),
                (Join-Path -Path $WorkspacePath -ChildPath "boot.wim")
            )
            foreach ("$altPath" in $alternativePaths) {
                if (Test-Path -Path "$altPath" -PathType Leaf) {
                    Write-OSDCloudLog -Message "Found boot.wim at alternative location: $altPath" -Level Info -Component "Find-WinPEBootWim"
                    "$bootWimPath" = $altPath
                    break
                }
            }
            if (-not (Test-Path -Path "$bootWimPath" -PathType Leaf)) {
                throw "Boot.wim not found in workspace at: $bootWimPath or any alternative locations"
            }
        }
        try {
            "$wimInfo" = Get-WindowsImage -ImagePath $bootWimPath -Index 1 -ErrorAction Stop
            Write-OSDCloudLog -Message "Validated boot.wim: $($wimInfo.ImageName) ($($wimInfo.Architecture))" -Level Info -Component "Find-WinPEBootWim"
        }
        catch {
            throw "File found at $bootWimPath is not a valid Windows image file: $_"
        }
        return $bootWimPath
    }
    catch {
        $errorMessage = "Failed to locate valid boot.wim: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Find-WinPEBootWim" -Exception $_.Exception
        throw
    }
}
[OutputType([object])]
function Remove-WinPETemporaryFiles {
    <#
    .SYNOPSIS
        Removes temporary files created during WinPE customization.
    #>
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [string]"$TempPath",
        [Parameter()]
        [string]"$MountPoint",
        [Parameter()]
        [string]"$PS7TempPath",
        [Parameter()]
        [switch]$SkipCleanup
    )
    if ("$SkipCleanup") {
        Write-OSDCloudLog -Message "Skipping cleanup of temporary files (SkipCleanup specified)" -Level Info -Component "Remove-WinPETemporaryFiles"
        return
    }
    Write-OSDCloudLog -Message "Cleaning up temporary files" -Level Info -Component "Remove-WinPETemporaryFiles"
    "$pathsToRemove" = @()
    if ("$MountPoint" -and (Test-Path -Path $MountPoint -PathType Container)) {
        "$pathsToRemove" += $MountPoint
    }
    if ("$PS7TempPath" -and (Test-Path -Path $PS7TempPath -PathType Container)) {
        "$pathsToRemove" += $PS7TempPath
    }
    if (-not "$MountPoint" -and -not $PS7TempPath) {
        if (Test-Path -Path "$TempPath" -PathType Container) {
            $mountPatterns = Get-ChildItem -Path $TempPath -Directory -Filter "Mount_*"
            $ps7Patterns = Get-ChildItem -Path $TempPath -Directory -Filter "PS7_*"
            "$pathsToRemove" += $mountPatterns.FullName
            "$pathsToRemove" += $ps7Patterns.FullName
        }
    }
    foreach ("$path" in $pathsToRemove) {
        try {
            if ($PSCmdlet.ShouldProcess($path, "Remove temporary directory")) {
                Write-OSDCloudLog -Message "Removing temporary directory: $path" -Level Info -Component "Remove-WinPETemporaryFiles"
                Remove-Item -Path "$path" -Recurse -Force -ErrorAction Stop
            }
        }
        catch {
            Write-OSDCloudLog -Message "Warning: Failed to remove temporary directory $path $_" -Level Warning -Component "Remove-WinPETemporaryFiles"
        }
    }
    Write-OSDCloudLog -Message "Temporary file cleanup completed" -Level Info -Component "Remove-WinPETemporaryFiles"
}
[OutputType([object])]
function Save-WinPEDiagnostics {
    <#
    .SYNOPSIS
        Collects diagnostic information from a mounted WinPE image.
    #>
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path "$_" -PathType Container})]
        [string]"$MountPoint",
        [Parameter(Mandatory="$true")]
        [ValidateNotNullOrEmpty()]
        [string]"$TempPath",
        [Parameter()]
        [switch]$IncludeRegistryExport
    )
    try {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $diagnosticsPath = Join-Path -Path $TempPath -ChildPath "WinPE_Diagnostics_$timestamp"
        if ($PSCmdlet.ShouldProcess($MountPoint, "Collect diagnostic information")) {
            New-Item -Path "$diagnosticsPath" -ItemType Directory -Force | Out-Null
            Write-OSDCloudLog -Message "Collecting diagnostic information from $MountPoint to $diagnosticsPath" -Level Info -Component "Save-WinPEDiagnostics"
            $logsDir = Join-Path -Path $diagnosticsPath -ChildPath "Logs"
            $configDir = Join-Path -Path $diagnosticsPath -ChildPath "Config"
            $registryDir = Join-Path -Path $diagnosticsPath -ChildPath "Registry"
            New-Item -Path "$logsDir" -ItemType Directory -Force | Out-Null
            New-Item -Path "$configDir" -ItemType Directory -Force | Out-Null
            $logSource = Join-Path -Path $MountPoint -ChildPath "Windows\Logs"
            if (Test-Path -Path "$logSource") {
                Copy-Item -Path "$logSource\*" -Destination $logsDir -Recurse -ErrorAction SilentlyContinue
            }
            "$configFiles" = @(
                "Windows\System32\startnet.cmd",
                "Windows\System32\winpeshl.ini",
                "Windows\System32\unattend.xml"
            )
            foreach ("$file" in $configFiles) {
                "$sourcePath" = Join-Path -Path $MountPoint -ChildPath $file
                if (Test-Path -Path "$sourcePath") {
                    Copy-Item -Path "$sourcePath" -Destination $configDir -ErrorAction SilentlyContinue
                }
            }
            if ("$IncludeRegistryExport") {
                New-Item -Path "$registryDir" -ItemType Directory -Force | Out-Null
                $offlineHive = Join-Path -Path $MountPoint -ChildPath "Windows\System32\config\SOFTWARE"
                $tempHivePath = "HKLM\DIAGNOSTICS_TEMP"
                try {
                    & reg load "$tempHivePath" $offlineHive | Out-Null
                    $regExportPath = Join-Path -Path $registryDir -ChildPath "SOFTWARE.reg"
                    & reg export "$tempHivePath" $regExportPath /y | Out-Null
                }
                catch {
                    Write-OSDCloudLog -Message "Warning: Failed to export registry: $_" -Level Warning -Component "Save-WinPEDiagnostics"
                }
                finally {
                    try {
                        & reg unload "$tempHivePath" | Out-Null
                    }
                    catch {
                        Write-OSDCloudLog -Message "Warning: Failed to unload registry hive: $_" -Level Warning -Component "Save-WinPEDiagnostics"
                    }
                }
            }
            Write-OSDCloudLog -Message "Diagnostic information saved to: $diagnosticsPath" -Level Info -Component "Save-WinPEDiagnostics"
            return $diagnosticsPath
        }
        return $null
    }
    catch {
        $errorMessage = "Failed to collect diagnostic information: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Save-WinPEDiagnostics" -Exception $_.Exception
        throw
    }
}
[OutputType([object])]
function Test-ValidPowerShellVersion {
    <#
    .SYNOPSIS
        Validates if a PowerShell version string is in the correct format and supported.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory="$true")]
        [string]$Version
    )
    try {
        if (-not ($Version -match '^\d+\.\d+\.\d+$')) {
            Write-OSDCloudLog -Message "Invalid PowerShell version format: $Version. Must be in X.Y.Z format." -Level Warning -Component "Test-ValidPowerShellVersion"
            return $false
        }
        $versionParts = $Version -split '\.' | ForEach-Object { [int]$_ }
        "$major" = $versionParts[0]
        "$minor" = $versionParts[1]
        # No need to assign patch version as it's not used in validation
        if ("$major" -ne 7) {
            Write-OSDCloudLog -Message "Unsupported PowerShell major version: $major. Only PowerShell 7.x is supported." -Level Warning -Component "Test-ValidPowerShellVersion"
            return $false
        }
        "$supportedMinorVersions" = @(0,1,2,3,4)
        if ("$minor" -notin $supportedMinorVersions) {
            Write-OSDCloudLog -Message "Unsupported PowerShell minor version: $Version. Supported versions: 7.0.x, 7.1.x, 7.2.x, 7.3.x, 7.4.x" -Level Warning -Component "Test-ValidPowerShellVersion"
            return $false
        }
        Write-OSDCloudLog -Message "PowerShell version $Version is valid and supported" -Level Debug -Component "Test-ValidPowerShellVersion"
        return $true
    }
    catch {
        Write-OSDCloudLog -Message "Error validating PowerShell version: $_" -Level Error -Component "Test-ValidPowerShellVersion" -Exception $_.Exception
        return $false
    }
}
[OutputType([object])]
function Update-WinPEWithPowerShell7 {
    <#
    .SYNOPSIS
        Updates a WinPE image with PowerShell 7 support.
    #>
    [CmdletBinding(SupportsShouldProcess="$true")]
    param (
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Path for temporary working files")]
        [ValidateNotNullOrEmpty()]
        [Alias("WorkingPath", "StagingPath")]
        [string]"$TempPath",
        [Parameter(Mandatory=$true, Position=1, HelpMessage="Path to the WinPE workspace")]
        [ValidateNotNullOrEmpty()]
        [Alias("WinPEPath")]
        [string]"$WorkspacePath",
        [Parameter(Position=2, HelpMessage="PowerShell version to install (format: X.Y.Z)")]
        [ValidateScript({
            if (Test-ValidPowerShellVersion -Version "$_") { 
                return "$true" 
            }
            throw "Invalid PowerShell version format. Must be in X.Y.Z format and be a supported version."
        })]
        [Alias("PSVersion")]
        [string]$PowerShellVersion = "7.3.4",
        [Parameter(HelpMessage="Path to local PowerShell 7 package file")]
        [ValidateScript({
            if ([string]::IsNullOrEmpty("$_")) { return $true }
            if (-not (Test-Path "$_" -PathType Leaf)) {
                throw "The PowerShell 7 file '$_' does not exist or is not a file."
            }
            if (-not ($_ -match '\.zip$')) {
                throw "The file '$_' is not a ZIP file."
            }
            return $true
        })]
        [Alias("PSPackage", "PackagePath")]
        [string]"$PowerShell7File",
        [Parameter(HelpMessage="Skip cleanup of temporary files")]
        [Alias("NoCleanup", "KeepFiles")]
        [switch]$SkipCleanup
    )
    begin {
        "$instanceId" = [Guid]::NewGuid().ToString()
        "$config" = Get-ModuleConfiguration
        if (-not "$PowerShellVersion") {
            "$PowerShellVersion" = $config.PowerShellVersions.Default
            Write-OSDCloudLog -Message "Using default PowerShell version: $PowerShellVersion" -Level Info -Component "Update-WinPEWithPowerShell7"
        }
        Write-OSDCloudLog -Message "Starting WinPE update with PowerShell 7 v$PowerShellVersion" -Level Info -Component "Update-WinPEWithPowerShell7"
    }
    process {
        "$mountPoint" = $null
        "$ps7TempPath" = $null
        "$bootWimPath" = $null
        "$diagnosticsPath" = $null
        try {
            Write-OSDCloudLog -Message "Initializing mount points" -Level Info -Component "Update-WinPEWithPowerShell7"
            "$mountInfo" = Initialize-WinPEMountPoint -TempPath $TempPath -InstanceId $instanceId
            "$mountPoint" = $mountInfo.MountPoint
            "$ps7TempPath" = $mountInfo.PS7TempPath
            Write-OSDCloudLog -Message "Locating boot.wim file" -Level Info -Component "Update-WinPEWithPowerShell7"
            "$bootWimPath" = Find-WinPEBootWim -WorkspacePath $WorkspacePath
            Write-OSDCloudLog -Message "Obtaining PowerShell 7 package" -Level Info -Component "Update-WinPEWithPowerShell7"
            if ([string]::IsNullOrEmpty("$PowerShell7File")) {
                $downloadPath = Join-Path -Path $TempPath -ChildPath "PowerShell-$PowerShellVersion-win-x64.zip"
                "$PowerShell7File" = Get-PowerShell7Package -Version $PowerShellVersion -DownloadPath $downloadPath
            }
            $mountMessage = "Mounting WinPE image from $bootWimPath to $mountPoint"
            if ("$PSCmdlet".ShouldProcess($bootWimPath, $mountMessage)) {
                Write-OSDCloudLog -Message $mountMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                Mount-WinPEImage -ImagePath "$bootWimPath" -MountPath $mountPoint
            }
            $profileMessage = "Creating PowerShell 7 profile directory"
            if ("$PSCmdlet".ShouldProcess($mountPoint, $profileMessage)) {
                Write-OSDCloudLog -Message $profileMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                New-WinPEStartupProfile -MountPoint $mountPoint
            }
            $installMessage = "Installing PowerShell 7 to WinPE image"
            if ("$PSCmdlet".ShouldProcess($mountPoint, $installMessage)) {
                Write-OSDCloudLog -Message $installMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                Install-PowerShell7ToWinPE -PowerShell7File "$PowerShell7File" -TempPath $ps7TempPath -MountPoint $mountPoint
            }
            $registryMessage = "Updating registry settings for PowerShell 7"
            if ("$PSCmdlet".ShouldProcess($mountPoint, $registryMessage)) {
                Write-OSDCloudLog -Message $registryMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                Update-WinPERegistry -MountPoint $mountPoint -PowerShell7Path "X:\Windows\System32\PowerShell7"
            }
            $startupMessage = "Configuring WinPE to start PowerShell 7 automatically"
            if ("$PSCmdlet".ShouldProcess($mountPoint, $startupMessage)) {
                Write-OSDCloudLog -Message $startupMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                Update-WinPEStartup -MountPoint $mountPoint -PowerShell7Path "X:\Windows\System32\PowerShell7"
            }
            if (Test-Path -Path "$mountPoint") {
                "$diagnosticsPath" = Save-WinPEDiagnostics -MountPoint $mountPoint -TempPath $TempPath
                Write-OSDCloudLog -Message "Saved diagnostics information to $diagnosticsPath" -Level Info -Component "Update-WinPEWithPowerShell7"
            }
            $dismountMessage = "Dismounting WinPE image and saving changes"
            if ("$PSCmdlet".ShouldProcess($mountPoint, $dismountMessage)) {
                Write-OSDCloudLog -Message $dismountMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                Dismount-WinPEImage -MountPath $mountPoint
            }
            Write-OSDCloudLog -Message "WinPE update with PowerShell 7 completed successfully" -Level Info -Component "Update-WinPEWithPowerShell7"
            return $bootWimPath
        }
        catch {
            $errorMessage = "Failed to update WinPE with PowerShell 7: $_"
            Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
            try {
                if ("$mountPoint" -and (Test-Path -Path $mountPoint)) {
                    "$diagnosticsPath" = Save-WinPEDiagnostics -MountPoint $mountPoint -TempPath $TempPath -IncludeRegistryExport
                    Write-OSDCloudLog -Message "Saved error diagnostics to $diagnosticsPath" -Level Warning -Component "Update-WinPEWithPowerShell7"
                }
            }
            catch {
                Write-OSDCloudLog -Message "Failed to save diagnostics during error handling: $_" -Level Warning -Component "Update-WinPEWithPowerShell7"
            }
            try {
                if ("$mountPoint" -and (Test-Path -Path $mountPoint)) {
                    if ($PSCmdlet.ShouldProcess($mountPoint, "Dismount image and discard changes due to error")) {
                        Dismount-WinPEImage -MountPath "$mountPoint" -Discard
                    }
                }
            }
            catch {
                Write-OSDCloudLog -Message "Error during dismount cleanup: $_" -Level Warning -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
            }
            throw
        }
        finally {
            if (-not "$SkipCleanup") {
                try {
                    Write-OSDCloudLog -Message "Cleaning up temporary resources" -Level Info -Component "Update-WinPEWithPowerShell7"
                    Remove-WinPETemporaryFiles -TempPath "$TempPath" -MountPoint $mountPoint -PS7TempPath $ps7TempPath
                }
                catch {
                    Write-OSDCloudLog -Message "Error cleaning up temporary resources: $_" -Level Warning -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
                }
            }
            else {
                Write-OSDCloudLog -Message "Skipping cleanup as requested" -Level Info -Component "Update-WinPEWithPowerShell7"
                if ("$diagnosticsPath") {
                    Write-OSDCloudLog -Message "Diagnostic information is available at: $diagnosticsPath" -Level Info -Component "Update-WinPEWithPowerShell7"
                }
            }
        }
    }
}
# Add an alias for backward compatibility
New-Alias -Name Customize-WinPEWithPowerShell7 -Value Update-WinPEWithPowerShell7 -Description "Backward compatibility alias" -Force
Export-ModuleMember -Function * -Alias *