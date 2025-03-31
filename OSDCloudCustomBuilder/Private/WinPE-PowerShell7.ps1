<#
.SYNOPSIS
    Functions for customizing WinPE with PowerShell 7 support.
.DESCRIPTION
    This file contains modular functions for working with WinPE and adding PowerShell 7 support.
.NOTES
    Version: 0.2.0
    Author: OSDCloud Team
#>

function Initialize-WinPEMountPoint {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter()]
        [string]$InstanceId = [Guid]::NewGuid().ToString()
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
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
        [string]$ImagePath,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPath,
        
        [Parameter()]
        [int]$Index = 1,
        
        [Parameter()]
        [int]$MaxRetries = 3,
        
        [Parameter()]
        [int]$TimeoutSec = 300
    )
    
    # Get module configuration
    $config = Get-ModuleConfiguration
    $timeoutSec = $config.Timeouts.Mount
    
    Write-OSDCloudLog -Message "Mounting WinPE image $ImagePath to $MountPath (Index: $Index)" -Level Info -Component "Mount-WinPEImage"
    
    # Use Measure-OSDCloudOperation for telemetry
    Measure-OSDCloudOperation -Name "Mount-WinPEImage" -ScriptBlock {
        for ($i = 0; $i -lt $MaxRetries; $i++) {
            try {
                if ($PSCmdlet.ShouldProcess($ImagePath, "Mount Windows Image")) {
                    Mount-WindowsImage -ImagePath $ImagePath -Index $Index -Path $MountPath -LogLevel 1
                    Write-OSDCloudLog -Message "Successfully mounted WinPE image" -Level Info -Component "Mount-WinPEImage"
                    return
                }
            }
            catch {
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
        if (Test-Path -Path $backupPath) {
            Copy-Item -Path $backupPath -Destination $startNetPath -Force
            Write-OSDCloudLog -Message "Restored original startnet.cmd from backup" -Level Warning -Component "Update-WinPEStartup"
        }
        
        return $false
    }
}

function Dismount-WinPEImage {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPath,
        
        [Parameter()]
        [switch]$Save = $true,
        
        [Parameter()]
        [int]$MaxRetries = 3,
        
        [Parameter()]
        [switch]$Discard
    )
    
    # Get module configuration
    $config = Get-ModuleConfiguration
    $timeoutSec = $config.Timeouts.Dismount
    
    # If Discard is specified, override Save
    if ($Discard) {
        $Save = $false
    }
    
    $saveText = if ($Save) { "saving changes" } else { "discarding changes" }
    Write-OSDCloudLog -Message "Dismounting WinPE image from $MountPath ($saveText)" -Level Info -Component "Dismount-WinPEImage"
    
    # Use Measure-OSDCloudOperation for telemetry
    Measure-OSDCloudOperation -Name "Dismount-WinPEImage" -ScriptBlock {
        for ($i = 0; $i -lt $MaxRetries; $i++) {
            try {
                if ($PSCmdlet.ShouldProcess($MountPath, "Dismount Windows Image ($saveText)")) {
                    Dismount-WindowsImage -Path $MountPath -Save:$Save -LogLevel 1
                    Write-OSDCloudLog -Message "Successfully dismounted WinPE image" -Level Info -Component "Dismount-WinPEImage"
                    return
                }
            }
            catch {
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
}

function Customize-WinPEWithPowerShell7 {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkspacePath,
        
        [Parameter()]
        [ValidateScript({
            if (Test-ValidPowerShellVersion -Version $_) { 
                return $true 
            }
            throw "Invalid PowerShell version format. Must be in X.Y.Z format and be a supported version."
        })]
        [string]$PowerShellVersion = "7.3.4",
        
        [Parameter()]
        [string]$PowerShell7File
    )
    
    # This function is kept for backward compatibility
    # It redirects to Update-WinPEWithPowerShell7
    
    Write-OSDCloudLog -Message "Customize-WinPEWithPowerShell7 is deprecated. Using Update-WinPEWithPowerShell7 instead." -Level Warning -Component "Customize-WinPEWithPowerShell7"
    
    $params = @{
        TempPath = $TempPath
        WorkspacePath = $WorkspacePath
        PowerShellVersion = $PowerShellVersion
    }
    
    if ($PowerShell7File) {
        $params.PowerShell7File = $PowerShell7File
    }
    
    return Update-WinPEWithPowerShell7 @params
}

# For backward compatibility
Set-Alias -Name Update-WinPEWithPowerShell7 -Value Customize-WinPEWithPowerShell7

# Export all functions and aliases
Export-ModuleMember -Function * -Alias *