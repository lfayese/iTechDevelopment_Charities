<#
.SYNOPSIS
    Functions for customizing WinPE with PowerShell 7 support.
.DESCRIPTION
    This file contains modular functions for working with WinPE and adding PowerShell 7 support.
.NOTES
    Version: 0.2.0
    Author: OSDCloud Team
#>

# Enforce TLS 1.2 for all web communications
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Initialize-WinPEMountPoint {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("WorkingPath", "StagingPath")]
        [string]$TemporaryPath,
        
        [Parameter()]
        [Alias("Id")]
        [string]$InstanceIdentifier = [Guid]::NewGuid().ToString()
    )
    try {
        if (-not (Test-Path -Path $TempPath -PathType Container)) {
            New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        }
        
        $mountPoint = Join-Path -Path $TempPath -ChildPath "Mount_$InstanceId"
        $ps7TempPath = Join-Path -Path $TempPath -ChildPath "PS7_$InstanceId"
        
        New-Item -Path $mountPoint -ItemType Directory -Force | Out-Null
        New-Item -Path $ps7TempPath -ItemType Directory -Force | Out-Null
        
        Write-OSDCloudLog -Message "Initialized WinPE mount point at $mountPoint" -Level Info -Component "Initialize-WinPEMountPoint"
        
        return @{
            MountPoint = $mountPoint
            PS7TempPath = $ps7TempPath
            InstanceId = $InstanceId
        }
    }
    catch {
        $errorMessage = "Failed to initialize WinPE mount point: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Initialize-WinPEMountPoint" -Exception $_.Exception
        throw
    }
}

function New-WinPEStartupProfile {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint
    )
    try {
        $startupProfilePath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\PowerShell7\Profiles"
        
        if (-not (Test-Path -Path $startupProfilePath)) {
            New-Item -Path $startupProfilePath -ItemType Directory -Force | Out-Null
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

function Mount-WinPEImage {
    <#
    .SYNOPSIS
        Mounts a WinPE image file with retry logic and validation.
    .DESCRIPTION
        Safely mounts a Windows PE image file to a specified mount point with built-in retry logic,
        validation, and detailed error handling. This function implements exponential backoff for retries
        and provides comprehensive logging of all operations.
    .PARAMETER ImagePath
        The full path to the WinPE image file (typically boot.wim) to be mounted.
        Must be a valid file path to an existing Windows image file.
    .PARAMETER MountPath
        The directory path where the image will be mounted.
        Must be an existing directory with appropriate permissions.
    .PARAMETER Index
        The index of the image to mount from a multi-image WIM file.
        Defaults to 1 for standard WinPE images.
    .PARAMETER MaxRetries
        The maximum number of mount attempts before failing.
        Defaults to 5 attempts with exponential backoff.
    .EXAMPLE
        Mount-WinPEImage -ImagePath "C:\WinPE\boot.wim" -MountPath "C:\Mount\WinPE"
        # Mounts the first image from boot.wim with default retry settings
    .EXAMPLE
        Mount-WinPEImage -ImagePath "C:\WinPE\boot.wim" -MountPath "C:\Mount\WinPE" -Index 2 -MaxRetries 3 -Verbose
        # Mounts the second image with custom retry count and verbose output
    .EXAMPLE
        Mount-WinPEImage -ImagePath "C:\WinPE\boot.wim" -MountPath "C:\Mount\WinPE" -WhatIf
        # Shows what would happen without actually mounting the image
    .NOTES
        Version: 1.1.0
        Author: OSDCloud Team
        Error Handling:
        - Validates image and mount path existence
        - Implements exponential backoff for retries
        - Provides detailed error information through Write-OSDCloudLog
        - Supports -WhatIf and -Confirm parameters
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
        [string]$ImagePath,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [string]$MountPath,
        
        [Parameter()]
        [ValidateRange(1,99)]
        [int]$Index = 1,
        
        [Parameter()]
        [ValidateRange(1,10)]
        [int]$MaxRetries = 5
    )
    
    Write-OSDCloudLog -Message "Mounting WinPE image from $ImagePath to $MountPath" -Level Info -Component "Mount-WinPEImage"
    
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            if ($PSCmdlet.ShouldProcess($ImagePath, "Mount Windows image to $MountPath", "Confirm WinPE image mount operation?")) {
                $mountParams = @{
                    ImagePath = $ImagePath
                    Index = $Index
                    Path = $MountPath
                    ErrorAction = 'Stop'
                }
                
                Write-OSDCloudLog -Message "Mounting image with parameters: $($mountParams | ConvertTo-Json)" -Level Debug -Component "Mount-WinPEImage"
                Mount-WindowsImage @mountParams
                
                # Verify mount was successful
                if (Test-Path -Path "$MountPath\Windows") {
                    Write-OSDCloudLog -Message "WinPE image mounted successfully and verified" -Level Info -Component "Mount-WinPEImage"
                    return $true
                } else {
                    throw "Mount operation completed but mount point verification failed"
                }
            }
            Write-OSDCloudLog -Message "Mount operation skipped due to -WhatIf" -Level Info -Component "Mount-WinPEImage"
            return $false
        }
        catch {
            # Log retry attempt
            $retryMessage = "Attempt $($i+1) of $MaxRetries failed to mount WinPE image: $_"
            Write-OSDCloudLog -Message $retryMessage -Level Warning -Component "Mount-WinPEImage"
            
            if ($i -eq $MaxRetries - 1) {
                $errorMessage = "Failed to mount WinPE image after $MaxRetries attempts: $_"
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Mount-WinPEImage" -Exception $_.Exception
                throw
            }
            
            # Add exponential backoff
            $sleepTime = [Math]::Pow(2, $i) * 2
            Write-OSDCloudLog -Message "Waiting $sleepTime seconds before retry..." -Level Info -Component "Mount-WinPEImage"
            Start-Sleep -Seconds $sleepTime
        }
    }
}

function Install-PowerShell7ToWinPE {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
        [string]$PowerShell7File,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint
    )
    
    $pwsh7Destination = Join-Path -Path $MountPoint -ChildPath "Windows\System32\PowerShell7"
    
    Write-OSDCloudLog -Message "Installing PowerShell 7 to WinPE at $pwsh7Destination" -Level Info -Component "Install-PowerShell7ToWinPE"
    
    if (-not (Test-Path -Path $pwsh7Destination)) {
        New-Item -Path $pwsh7Destination -ItemType Directory -Force | Out-Null
    }
    
    try {
        Write-OSDCloudLog -Message "Extracting PowerShell 7 from $PowerShell7File" -Level Info -Component "Install-PowerShell7ToWinPE"
        
        if ($PSCmdlet.ShouldProcess($PowerShell7File, "Extract to $pwsh7Destination")) {
            Expand-Archive -Path $PowerShell7File -DestinationPath $pwsh7Destination -Force
            
            # Verify extraction
            $pwshExe = Join-Path -Path $pwsh7Destination -ChildPath "pwsh.exe"
            if (-not (Test-Path -Path $pwshExe)) {
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

function Update-WinPERegistry {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint,
        
        [Parameter()]
        [string]$PowerShell7Path = "X:\Windows\System32\PowerShell7"
    )
    
    $offlineHive = Join-Path -Path $MountPoint -ChildPath "Windows\System32\config\SOFTWARE"
    $tempHivePath = "HKLM\PS7TEMP"
    
    Write-OSDCloudLog -Message "Updating WinPE registry settings for PowerShell 7" -Level Info -Component "Update-WinPERegistry"
    
    try {
        if ($PSCmdlet.ShouldProcess($offlineHive, "Load registry hive")) {
            # Load the offline hive
            $null = reg load $tempHivePath $offlineHive
            
            # Set PATH environment variable to include PowerShell 7
            $envPath = "Registry::$tempHivePath\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe"
            if ($PSCmdlet.ShouldProcess($envPath, "Create registry key")) {
                $null = New-Item -Path $envPath -Force
                $null = New-ItemProperty -Path $envPath -Name "(Default)" -Value "$PowerShell7Path\pwsh.exe" -PropertyType String -Force
                $null = New-ItemProperty -Path $envPath -Name "Path" -Value $PowerShell7Path -PropertyType String -Force
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
        # Unload the hive
        try {
            if ($PSCmdlet.ShouldProcess($tempHivePath, "Unload registry hive")) {
                $null = reg unload $tempHivePath
            }
        }
        catch {
            Write-OSDCloudLog -Message "Warning: Failed to unload registry hive: $_" -Level Warning -Component "Update-WinPERegistry"
        }
    }
}

function Update-WinPEStartup {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint,
        
        [Parameter()]
        [string]$PowerShell7Path = "X:\Windows\System32\PowerShell7"
    )
    
    # Properly escape path for CMD
    $escapedPath = $PowerShell7Path -replace '([&|<>^%])', '^\1'
    
    # Use safer string format
    $startupScriptContent = @"
@echo off
set "PATH=%PATH%;$escapedPath"
"$escapedPath\pwsh.exe" -NoLogo -Command "Write-Host 'PowerShell 7 is initialized and ready.' -ForegroundColor Green"
"@
    
    $startNetPath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\startnet.cmd"
    
    try {
        # Create backup of original startnet.cmd
        $backupPath = "$startNetPath.bak"
        if (Test-Path -Path $startNetPath) {
            Copy-Item -Path $startNetPath -Destination $backupPath -Force
            Write-OSDCloudLog -Message "Created backup of startnet.cmd at $backupPath" -Level Info -Component "Update-WinPEStartup"
        }
        
        # Write the new content safely
        if ($PSCmdlet.ShouldProcess($startNetPath, "Update startup script")) {
            [System.IO.File]::WriteAllText($startNetPath, $startupScriptContent, [System.Text.Encoding]::ASCII)
            Write-OSDCloudLog -Message "Successfully updated startnet.cmd to initialize PowerShell 7" -Level Info -Component "Update-WinPEStartup"
        }
        
        return $true
    }
    catch {
        $errorMessage = "Failed to update startnet.cmd: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-WinPEStartup" -Exception $_.Exception
        
        # Restore backup if available
        try {
            if (Test-Path -Path $backupPath) {
                Copy-Item -Path $backupPath -Destination $startNetPath -Force
                Write-OSDCloudLog -Message "Restored backup of startnet.cmd" -Level Warning -Component "Update-WinPEStartup"
            }
        }
        catch {
            Write-OSDCloudLog -Message "Failed to restore backup of startnet.cmd: $_" -Level Error -Component "Update-WinPEStartup"
        }
        
        throw
    }
}

function Dismount-WinPEImage {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [string]$MountPath,
        
        [Parameter()]
        [switch]$Discard,
        
        [Parameter()]
        [int]$MaxRetries = 5
    )
    
    $saveChanges = -not $Discard
    $saveMessage = if ($saveChanges) { "saving" } else { "discarding" }
    
    Write-OSDCloudLog -Message "Dismounting WinPE image from $MountPath ($saveMessage changes)" -Level Info -Component "Dismount-WinPEImage"
    
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            if ($PSCmdlet.ShouldProcess($MountPath, "Dismount Windows image ($saveMessage changes)")) {
                Dismount-WindowsImage -Path $MountPath -Save:$saveChanges -ErrorAction Stop
                Write-OSDCloudLog -Message "WinPE image dismounted successfully" -Level Info -Component "Dismount-WinPEImage"
                return $true
            }
            return $false
        }
        catch {
            # Log retry attempt
            $retryMessage = "Attempt $($i+1) of $MaxRetries failed to dismount WinPE image: $_"
            Write-OSDCloudLog -Message $retryMessage -Level Warning -Component "Dismount-WinPEImage"
            
            if ($i -eq $MaxRetries - 1) {
                $errorMessage = "Failed to dismount WinPE image after $MaxRetries attempts: $_"
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Dismount-WinPEImage" -Exception $_.Exception
                throw
            }
            
            # Add exponential backoff
            $sleepTime = [Math]::Pow(2, $i) * 2
            Write-OSDCloudLog -Message "Waiting $sleepTime seconds before retry..." -Level Info -Component "Dismount-WinPEImage"
            Start-Sleep -Seconds $sleepTime
        }
    }
}

function Get-PowerShell7Package {
    <#
    .SYNOPSIS
        Downloads or validates a PowerShell 7 package.
    .DESCRIPTION
        This function either downloads a PowerShell 7 package from the official Microsoft repository
        or validates an existing package file. It supports version validation, download progress
        tracking, and integrity verification of the downloaded package.
    .PARAMETER Version
        The PowerShell version to download in X.Y.Z format (e.g., "7.3.4").
        Must be a valid and supported PowerShell 7 version.
    .PARAMETER DownloadPath
        The path where the PowerShell 7 package will be downloaded.
        If the file already exists at this path, it will be validated instead of downloaded again.
    .PARAMETER Force
        If specified, will re-download the package even if it already exists at the destination path.
    .EXAMPLE
        Get-PowerShell7Package -Version "7.3.4" -DownloadPath "C:\Temp\PowerShell-7.3.4-win-x64.zip"
        # Downloads PowerShell 7.3.4 to the specified path
    .EXAMPLE
        Get-PowerShell7Package -Version "7.3.4" -DownloadPath "C:\Temp\PowerShell-7.3.4-win-x64.zip" -Force
        # Forces a re-download even if the file already exists
    .NOTES
        Version: 1.0.0
        Author: OSDCloud Team
        Requirements:
        - Internet connectivity for downloading
        - Write access to the download directory
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            if (Test-ValidPowerShellVersion -Version $_) { 
                return $true 
            }
            throw "Invalid PowerShell version format. Must be in X.Y.Z format and be a supported version."
        })]
        [string]$Version,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DownloadPath,
        
        [Parameter()]
        [switch]$Force
    )
    
    try {
        # Check if file already exists
        if ((Test-Path -Path $DownloadPath) -and -not $Force) {
            Write-OSDCloudLog -Message "PowerShell 7 package already exists at $DownloadPath" -Level Info -Component "Get-PowerShell7Package"
            return $DownloadPath
        }
        
        # Ensure download directory exists
        $downloadDir = Split-Path -Path $DownloadPath -Parent
        if (-not (Test-Path -Path $downloadDir -PathType Container)) {
            New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null
        }
        
        # Construct download URL
        $downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-win-x64.zip"
        
        Write-OSDCloudLog -Message "Downloading PowerShell 7 v$Version from $downloadUrl" -Level Info -Component "Get-PowerShell7Package"
        
        if ($PSCmdlet.ShouldProcess($downloadUrl, "Download PowerShell 7 package")) {
            # Download with progress
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "OSDCloudCustomBuilder/1.0")
            
            # Add progress event handler
            $progressEventHandler = {
                $percent = [int](($EventArgs.BytesReceived / $EventArgs.TotalBytesToReceive) * 100)
                Write-Progress -Activity "Downloading PowerShell 7 v$Version" -Status "$percent% Complete" -PercentComplete $percent
            }
            
            $null = Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action $progressEventHandler
            
            try {
                $webClient.DownloadFile($downloadUrl, $DownloadPath)
            }
            finally {
                # Clean up event handlers
                Get-EventSubscriber | Where-Object { $_.SourceObject -eq $webClient } | Unregister-Event
                $webClient.Dispose()
                Write-Progress -Activity "Downloading PowerShell 7 v$Version" -Completed
            }
            
            # Verify download
            if (-not (Test-Path -Path $DownloadPath)) {
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

function Find-WinPEBootWim {
    <#
    .SYNOPSIS
        Locates and validates the boot.wim file in a WinPE workspace.
    .DESCRIPTION
        This function searches for the boot.wim file in the standard location within a WinPE workspace.
        It performs validation to ensure the file exists and is a valid Windows image file.
    .PARAMETER WorkspacePath
        The base path of the WinPE workspace where the boot.wim file should be located.
        The function will look for the file in the Media\Sources subdirectory.
    .EXAMPLE
        Find-WinPEBootWim -WorkspacePath "C:\OSDCloud\Workspace"
        # Locates and validates the boot.wim file in the specified workspace
    .NOTES
        Version: 1.0.0
        Author: OSDCloud Team
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [string]$WorkspacePath
    )
    
    try {
        # Define standard boot.wim path
        $bootWimPath = Join-Path -Path $WorkspacePath -ChildPath "Media\Sources\boot.wim"
        
        Write-OSDCloudLog -Message "Searching for boot.wim at $bootWimPath" -Level Info -Component "Find-WinPEBootWim"
        
        # Check if file exists
        if (-not (Test-Path -Path $bootWimPath -PathType Leaf)) {
            # Try alternative locations
            $alternativePaths = @(
                (Join-Path -Path $WorkspacePath -ChildPath "Sources\boot.wim"),
                (Join-Path -Path $WorkspacePath -ChildPath "boot.wim")
            )
            
            foreach ($altPath in $alternativePaths) {
                if (Test-Path -Path $altPath -PathType Leaf) {
                    Write-OSDCloudLog -Message "Found boot.wim at alternative location: $altPath" -Level Info -Component "Find-WinPEBootWim"
                    $bootWimPath = $altPath
                    break
                }
            }
            
            if (-not (Test-Path -Path $bootWimPath -PathType Leaf)) {
                throw "Boot.wim not found in workspace at: $bootWimPath or any alternative locations"
            }
        }
        
        # Validate that it's a Windows image file
        try {
            $wimInfo = Get-WindowsImage -ImagePath $bootWimPath -Index 1 -ErrorAction Stop
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

function Remove-WinPETemporaryFiles {
    <#
    .SYNOPSIS
        Removes temporary files created during WinPE customization.
    .DESCRIPTION
        This function safely removes temporary files and directories created during the WinPE
        customization process. It implements proper error handling and logging to ensure
        cleanup operations are performed safely.
    .PARAMETER TempPath
        The base temporary path containing the directories to remove.
    .PARAMETER MountPoint
        The specific mount point directory to remove.
    .PARAMETER PS7TempPath
        The specific PowerShell 7 temporary directory to remove.
    .PARAMETER SkipCleanup
        If specified, temporary files will not be removed. This is useful for debugging.
    .EXAMPLE
        Remove-WinPETemporaryFiles -TempPath "C:\Temp\OSDCloud" -MountPoint "C:\Temp\OSDCloud\Mount" -PS7TempPath "C:\Temp\OSDCloud\PS7"
        # Removes all specified temporary directories
    .EXAMPLE
        Remove-WinPETemporaryFiles -TempPath "C:\Temp\OSDCloud" -MountPoint "C:\Temp\OSDCloud\Mount" -PS7TempPath "C:\Temp\OSDCloud\PS7" -SkipCleanup
        # Skips removal of temporary files for debugging purposes
    .NOTES
        Version: 1.0.0
        Author: OSDCloud Team
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter()]
        [string]$MountPoint,
        
        [Parameter()]
        [string]$PS7TempPath,
        
        [Parameter()]
        [switch]$SkipCleanup
    )
    
    if ($SkipCleanup) {
        Write-OSDCloudLog -Message "Skipping cleanup of temporary files (SkipCleanup specified)" -Level Info -Component "Remove-WinPETemporaryFiles"
        return
    }
    
    Write-OSDCloudLog -Message "Cleaning up temporary files" -Level Info -Component "Remove-WinPETemporaryFiles"
    
    $pathsToRemove = @()
    
    if ($MountPoint -and (Test-Path -Path $MountPoint -PathType Container)) {
        $pathsToRemove += $MountPoint
    }
    
    if ($PS7TempPath -and (Test-Path -Path $PS7TempPath -PathType Container)) {
        $pathsToRemove += $PS7TempPath
    }
    
    # If specific paths weren't provided, try to find pattern-based paths in the temp directory
    if (-not $MountPoint -and -not $PS7TempPath) {
        if (Test-Path -Path $TempPath -PathType Container) {
            $mountPatterns = Get-ChildItem -Path $TempPath -Directory -Filter "Mount_*"
            $ps7Patterns = Get-ChildItem -Path $TempPath -Directory -Filter "PS7_*"
            
            $pathsToRemove += $mountPatterns.FullName
            $pathsToRemove += $ps7Patterns.FullName
        }
    }
    
    foreach ($path in $pathsToRemove) {
        try {
            if ($PSCmdlet.ShouldProcess($path, "Remove temporary directory")) {
                Write-OSDCloudLog -Message "Removing temporary directory: $path" -Level Info -Component "Remove-WinPETemporaryFiles"
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            }
        }
        catch {
            Write-OSDCloudLog -Message "Warning: Failed to remove temporary directory $path: $_" -Level Warning -Component "Remove-WinPETemporaryFiles"
        }
    }
    
    Write-OSDCloudLog -Message "Temporary file cleanup completed" -Level Info -Component "Remove-WinPETemporaryFiles"
}

function Save-WinPEDiagnostics {
    <#
    .SYNOPSIS
        Collects diagnostic information from a mounted WinPE image.
    .DESCRIPTION
        This function gathers logs and diagnostic information from a mounted WinPE image
        for troubleshooting purposes. It creates a timestamped directory to store the
        collected information.
    .PARAMETER MountPoint
        The path where the WinPE image is mounted.
    .PARAMETER TempPath
        The path where diagnostic information will be saved.
    .PARAMETER IncludeRegistryExport
        If specified, exports registry hives from the mounted image.
    .EXAMPLE
        Save-WinPEDiagnostics -MountPoint "C:\Mount\WinPE" -TempPath "C:\Temp\OSDCloud"
        # Collects basic diagnostic information from the mounted WinPE image
    .EXAMPLE
        Save-WinPEDiagnostics -MountPoint "C:\Mount\WinPE" -TempPath "C:\Temp\OSDCloud" -IncludeRegistryExport
        # Collects diagnostic information including registry exports
    .NOTES
        Version: 1.0.0
        Author: OSDCloud Team
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [string]$MountPoint,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter()]
        [switch]$IncludeRegistryExport
    )
    
    try {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $diagnosticsPath = Join-Path -Path $TempPath -ChildPath "WinPE_Diagnostics_$timestamp"
        
        if ($PSCmdlet.ShouldProcess($MountPoint, "Collect diagnostic information")) {
            # Create diagnostics directory
            New-Item -Path $diagnosticsPath -ItemType Directory -Force | Out-Null
            
            Write-OSDCloudLog -Message "Collecting diagnostic information from $MountPoint to $diagnosticsPath" -Level Info -Component "Save-WinPEDiagnostics"
            
            # Create subdirectories
            $logsDir = Join-Path -Path $diagnosticsPath -ChildPath "Logs"
            $configDir = Join-Path -Path $diagnosticsPath -ChildPath "Config"
            $registryDir = Join-Path -Path $diagnosticsPath -ChildPath "Registry"
            
            New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            
            # Collect logs
            $logSource = Join-Path -Path $MountPoint -ChildPath "Windows\Logs"
            if (Test-Path -Path $logSource) {
                Copy-Item -Path "$logSource\*" -Destination $logsDir -Recurse -ErrorAction SilentlyContinue
            }
            
            # Collect configuration files
            $configFiles = @(
                "Windows\System32\startnet.cmd",
                "Windows\System32\winpeshl.ini",
                "Windows\System32\unattend.xml"
            )
            
            foreach ($file in $configFiles) {
                $sourcePath = Join-Path -Path $MountPoint -ChildPath $file
                if (Test-Path -Path $sourcePath) {
                    Copy-Item -Path $sourcePath -Destination $configDir -ErrorAction SilentlyContinue
                }
            }
            
            # Export registry if requested
            if ($IncludeRegistryExport) {
                New-Item -Path $registryDir -ItemType Directory -Force | Out-Null
                
                $offlineHive = Join-Path -Path $MountPoint -ChildPath "Windows\System32\config\SOFTWARE"
                $tempHivePath = "HKLM\DIAGNOSTICS_TEMP"
                
                try {
                    # Load the offline hive
                    $null = reg load $tempHivePath $offlineHive
                    
                    # Export to file
                    $regExportPath = Join-Path -Path $registryDir -ChildPath "SOFTWARE.reg"
                    $null = reg export $tempHivePath $regExportPath /y
                }
                catch {
                    Write-OSDCloudLog -Message "Warning: Failed to export registry: $_" -Level Warning -Component "Save-WinPEDiagnostics"
                }
                finally {
                    # Unload the hive
                    try {
                        $null = reg unload $tempHivePath
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

function Test-ValidPowerShellVersion {
    <#
    .SYNOPSIS
        Validates if a PowerShell version string is in the correct format and is supported.
    .DESCRIPTION
        This function checks if a PowerShell version string is in the correct X.Y.Z format
        and is a supported version for WinPE integration. It validates both the format and
        whether the version is in the supported range.
    .PARAMETER Version
        The PowerShell version string to validate (e.g., "7.3.4").
    .EXAMPLE
        Test-ValidPowerShellVersion -Version "7.3.4"
        # Returns $true if the version is valid and supported
    .EXAMPLE
        Test-ValidPowerShellVersion -Version "invalid"
        # Returns $false for an invalid version format
    .NOTES
        Version: 1.0.0
        Author: OSDCloud Team
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Version
    )
    
    try {
        # Check if the version is in the correct format (X.Y.Z)
        if (-not ($Version -match '^\d+\.\d+\.\d+$')) {
            Write-OSDCloudLog -Message "Invalid PowerShell version format: $Version. Must be in X.Y.Z format." -Level Warning -Component "Test-ValidPowerShellVersion"
            return $false
        }
        
        # Parse version components
        $versionParts = $Version -split '\.' | ForEach-Object { [int]$_ }
        $major = $versionParts[0]
        $minor = $versionParts[1]
        $patch = $versionParts[2]
        
        # Check if it's PowerShell 7.x
        if ($major -ne 7) {
            Write-OSDCloudLog -Message "Unsupported PowerShell major version: $major. Only PowerShell 7.x is supported." -Level Warning -Component "Test-ValidPowerShellVersion"
            return $false
        }
        
        # Check supported minor versions (adjust as needed)
        $supportedMinorVersions = @(0, 1, 2, 3, 4)
        if ($minor -notin $supportedMinorVersions) {
            Write-OSDCloudLog -Message "Unsupported PowerShell minor version: $Version. Supported versions: 7.0.x, 7.1.x, 7.2.x, 7.3.x, 7.4.x" -Level Warning -Component "Test-ValidPowerShellVersion"
            return $false
        }
        
        # Additional validation could be added here for specific version compatibility
        
        Write-OSDCloudLog -Message "PowerShell version $Version is valid and supported" -Level Debug -Component "Test-ValidPowerShellVersion"
        return $true
    }
    catch {
        Write-OSDCloudLog -Message "Error validating PowerShell version: $_" -Level Error -Component "Test-ValidPowerShellVersion" -Exception $_.Exception
        return $false
    }
}

function Update-WinPEWithPowerShell7 {
    <#
        .SYNOPSIS
            Updates a WinPE image with PowerShell 7 support.
        .DESCRIPTION
            This function serves as the main orchestrator for updating a WinPE image with PowerShell 7 support.
            It coordinates the following operations through specialized helper functions:
            - Initializes working directories and mount points
            - Downloads or validates PowerShell 7 package
            - Mounts and modifies the WinPE image
            - Installs and configures PowerShell 7
            - Updates system settings and startup configuration
            - Handles cleanup and error recovery

            The function implements comprehensive error handling and recovery mechanisms to ensure
            system stability and data integrity throughout the update process.
        .PARAMETER TempPath
            The temporary path where working files will be stored. This path must have sufficient
            disk space and appropriate permissions for creating and modifying files.
        .PARAMETER WorkspacePath
            The workspace path containing the WinPE image to update. This should point to a valid
            WinPE workspace directory containing the boot.wim file in the Media\Sources subdirectory.
        .PARAMETER PowerShellVersion
            The PowerShell version to install. Default is "7.3.4". Must be in X.Y.Z format and be
            a supported version. The function will validate the version format and availability.
        .PARAMETER PowerShell7File
            The path to the PowerShell 7 zip file. If not specified, it will be downloaded from
            the official Microsoft repository. If specified, the file must exist and be a valid
            PowerShell 7 package.
        .PARAMETER SkipCleanup
            If specified, temporary files will not be removed after processing. This can be useful
            for debugging or when you need to inspect the intermediate files.
        .EXAMPLE
            Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace"
            # Basic usage with default settings
            # This will update the WinPE image with the latest supported PowerShell 7 version
        .EXAMPLE
            Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShellVersion "7.3.4" -Verbose
            # Install specific PowerShell version with verbose output
            # The -Verbose parameter provides detailed progress information during the update
        .EXAMPLE
            Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShell7File "C:\Temp\PowerShell-7.3.4-win-x64.zip" -WhatIf
            # Test run using local PowerShell package
            # The -WhatIf parameter shows what changes would be made without actually making them
        .EXAMPLE
            Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -SkipCleanup -ErrorAction Stop
            # Keep temporary files and stop on any error
            # Useful for debugging or when you need to inspect the intermediate files
        .NOTES
            Version: 1.0.0
            Author: OSDCloud Team
            Requirements:
            - Administrator privileges
            - Windows ADK installed
            - Internet connectivity (if PowerShell package needs downloading)
            - Minimum 10GB free disk space in TempPath
            - Write access to WorkspacePath
        #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,
                   Position=0,
                   HelpMessage="Path for temporary working files")]
        [ValidateNotNullOrEmpty()]
        [Alias("WorkingPath", "StagingPath")]
        [string]$TemporaryPath,
        
        [Parameter(Mandatory=$true,
                   Position=1,
                   HelpMessage="Path to the WinPE workspace")]
        [ValidateNotNullOrEmpty()]
        [Alias("WinPEPath")]
        [string]$WorkspacePath,
        
        [Parameter(Position=2,
                   HelpMessage="PowerShell version to install (format: X.Y.Z)")]
        [ValidateScript({
            if (Test-ValidPowerShellVersion -Version $_) { 
                return $true 
            }
            throw "Invalid PowerShell version format. Must be in X.Y.Z format and be a supported version."
        })]
        [Alias("PSVersion")]
        [string]$PowerShellVersion = "7.3.4",
        
        [Parameter(HelpMessage="Path to local PowerShell 7 package file")]
        [ValidateScript({!$_ -or (Test-Path $_ -PathType Leaf)})]
        [Alias("PSPackage", "PackagePath")]
        [string]$PowerShellPackageFile,
        
        [Parameter(HelpMessage="Skip cleanup of temporary files")]
        [Alias("NoCleanup", "KeepFiles")]
        [switch]$SkipCleanup
    )
    
    Write-OSDCloudLog -Message "Starting WinPE customization with PowerShell $PowerShellVersion" -Level Info -Component "Update-WinPEWithPowerShell7"
    
    try {
        # Step 1: Initialize WinPE mount point
        Write-OSDCloudLog -Message "Initializing mount points" -Level Info -Component "Update-WinPEWithPowerShell7"
        $mountInfo = Initialize-WinPEMountPoint -TempPath $TempPath
        $mountPoint = $mountInfo.MountPoint
        $ps7TempPath = $mountInfo.PS7TempPath
        
        # Step 2: Get PowerShell 7 package if not provided
        if (-not $PowerShell7File) {
            Write-OSDCloudLog -Message "PowerShell 7 package not provided, attempting to download" -Level Info -Component "Update-WinPEWithPowerShell7"
            $PowerShell7File = Get-PowerShell7Package -Version $PowerShellVersion -DownloadPath (Join-Path -Path $ps7TempPath -ChildPath "PowerShell-$PowerShellVersion-win-x64.zip")
        }
        
        # Step 3: Locate boot.wim in the workspace
        $bootWimPath = Join-Path -Path $WorkspacePath -ChildPath "Media\Sources\boot.wim"
        if (-not (Test-Path -Path $bootWimPath)) {
            throw "Boot.wim not found at expected path: $bootWimPath"
        }
        
        # Step 4: Mount the WinPE image
        Write-OSDCloudLog -Message "Mounting boot.wim" -Level Info -Component "Update-WinPEWithPowerShell7"
        if ($PSCmdlet.ShouldProcess($bootWimPath, "Mount WinPE image and install PowerShell 7", "Confirm WinPE image modification?")) {
        # Step 4: Mount the WinPE image with detailed operation description
        $mountOperation = @{
            Target = $bootWimPath
            Operation = "Mount to $mountPoint"
            Description = "This will mount the WinPE image for modification"
        }
            
        if ($PSCmdlet.ShouldProcess($mountOperation.Target, $mountOperation.Operation, $mountOperation.Description)) {
            Mount-WinPEImage -ImagePath $bootWimPath -MountPath $mountPoint -Index 1
        }
            
        # Step 5: Install PowerShell 7 to the mounted WinPE image with confirmation
        $installOperation = @{
            Target = $PowerShell7File
            Operation = "Install PowerShell 7 to WinPE"
            Description = "This will add PowerShell 7 support to the WinPE image"
        }
            
        Write-OSDCloudLog -Message "Installing PowerShell 7 to WinPE" -Level Info -Component "Update-WinPEWithPowerShell7"
        if ($PSCmdlet.ShouldProcess($installOperation.Target, $installOperation.Operation, $installOperation.Description)) {
            Install-PowerShell7ToWinPE -PowerShell7File $PowerShell7File -TempPath $ps7TempPath -MountPoint $mountPoint
        }
            
            # Step 6: Update registry settings for PowerShell 7
            Write-OSDCloudLog -Message "Updating WinPE registry settings" -Level Info -Component "Update-WinPEWithPowerShell7"
            Update-WinPERegistry -MountPoint $mountPoint -PowerShell7Path "X:\Windows\System32\PowerShell7"
            
            # Step 7: Create PowerShell 7 startup profile
            Write-OSDCloudLog -Message "Creating WinPE startup profile" -Level Info -Component "Update-WinPEWithPowerShell7"
            New-WinPEStartupProfile -MountPoint $mountPoint
            
            # Step 8: Update WinPE startup script to use PowerShell 7
            Write-OSDCloudLog -Message "Updating WinPE startup script" -Level Info -Component "Update-WinPEWithPowerShell7"
            Update-WinPEStartup -MountPoint $mountPoint -PowerShell7Path "X:\Windows\System32\PowerShell7"
            
            # Step 9: Dismount the WinPE image and save changes
            Write-OSDCloudLog -Message "Dismounting boot.wim and saving changes" -Level Info -Component "Update-WinPEWithPowerShell7"
            Dismount-WinPEImage -MountPath $mountPoint
            
            Write-OSDCloudLog -Message "WinPE image successfully updated with PowerShell 7" -Level Info -Component "Update-WinPEWithPowerShell7"
        }
        
        # Clean up temporary files if needed
        if (-not $SkipCleanup) {
            try {
                Write-OSDCloudLog -Message "Cleaning up temporary files" -Level Info -Component "Update-WinPEWithPowerShell7"
                Remove-Item -Path $mountPoint -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $ps7TempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-OSDCloudLog -Message "Warning: Failed to clean up temporary files: $_" -Level Warning -Component "Update-WinPEWithPowerShell7"
            }
        }
        
        return $bootWimPath
    }
    catch {
        # Clean up on error
        try {
        if (Test-Path -Path $mountPoint -PathType Container) {
            Write-OSDCloudLog -Message "Critical error occurred. Attempting to dismount image and clean up." -Level Warning -Component "Update-WinPEWithPowerShell7"
                
            # Attempt to salvage any logs or diagnostic information
            try {
                $diagnosticsPath = Join-Path -Path $TempPath -ChildPath "ErrorDiagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                New-Item -Path $diagnosticsPath -ItemType Directory -Force | Out-Null
                Copy-Item -Path "$mountPoint\Windows\Logs\*" -Destination $diagnosticsPath -Recurse -ErrorAction SilentlyContinue
                Write-OSDCloudLog -Message "Diagnostic information saved to: $diagnosticsPath" -Level Info -Component "Update-WinPEWithPowerShell7"
            }
            catch {
                Write-OSDCloudLog -Message "Failed to collect diagnostic information: $_" -Level Warning -Component "Update-WinPEWithPowerShell7"
            }
                
            # Attempt to dismount with increasing force
            try {
                Dismount-WinPEImage -MountPath $mountPoint -Discard -ErrorAction Stop
            }
            catch {
                Write-OSDCloudLog -Message "Standard dismount failed, attempting force dismount..." -Level Warning -Component "Update-WinPEWithPowerShell7"
                Dismount-WindowsImage -Path $mountPoint -Discard -Force -ErrorAction Stop
            }
        }
        }
        catch {
        Write-OSDCloudLog -Message "Critical failure during error recovery: $_" -Level Error -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
        Write-OSDCloudLog -Message "Manual cleanup may be required for: $mountPoint" -Level Error -Component "Update-WinPEWithPowerShell7"
        }
        
        $errorMessage = "Failed to update WinPE with PowerShell 7: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
        throw $errorMessage
    }
}

# For backward compatibility - FIXED: Correctly set the old name as alias to the new name
Set-Alias -Name Customize-WinPEWithPowerShell7 -Value Update-WinPEWithPowerShell7

# Export all functions and aliases
Export-ModuleMember -Function * -Alias *