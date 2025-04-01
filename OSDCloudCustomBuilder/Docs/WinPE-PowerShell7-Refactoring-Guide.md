# WinPE-PowerShell7.ps1 Refactoring Implementation Guide

This document provides a comprehensive implementation guide for refactoring the WinPE-PowerShell7.ps1 file to improve maintainability, error handling, and documentation.

## Overview

The goal is to break down the complex `Update-WinPEWithPowerShell7` function into smaller, more manageable pieces while maintaining the same functionality. The refactoring includes:

1. Renaming the main function from "Customize-WinPEWithPowerShell7" to "Update-WinPEWithPowerShell7" with an alias for backward compatibility
2. Implementing proper error handling with try/catch blocks in all functions
3. Adding comprehensive documentation with real-world examples
4. Supporting ShouldProcess where appropriate
5. Ensuring consistent parameter naming and validation

## Implementation Steps

### 1. Update File Header

Update the file header to reflect the new version number and improve the description:

```powershell
<#
.SYNOPSIS
    Functions for customizing WinPE with PowerShell 7 support.
.DESCRIPTION
    This file contains modular functions for working with WinPE and adding PowerShell 7 support.
.NOTES
    Version: 1.0.0
    Author: OSDCloud Team
#>
```

### 2. Fix Parameter Naming in Initialize-WinPEMountPoint

Fix the parameter naming in the Initialize-WinPEMountPoint function to ensure consistency:

```powershell
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
        if (-not (Test-Path -Path $TemporaryPath -PathType Container)) {
            New-Item -Path $TemporaryPath -ItemType Directory -Force | Out-Null
        }
        
        $mountPoint = Join-Path -Path $TemporaryPath -ChildPath "Mount_$InstanceIdentifier"
        $ps7TempPath = Join-Path -Path $TemporaryPath -ChildPath "PS7_$InstanceIdentifier"
        
        New-Item -Path $mountPoint -ItemType Directory -Force | Out-Null
        New-Item -Path $ps7TempPath -ItemType Directory -Force | Out-Null
        
        Write-OSDCloudLog -Message "Initialized WinPE mount point at $mountPoint" -Level Info -Component "Initialize-WinPEMountPoint"
        
        return @{
            MountPoint = $mountPoint
            PS7TempPath = $ps7TempPath
            InstanceId = $InstanceIdentifier
        }
    }
    catch {
        $errorMessage = "Failed to initialize WinPE mount point: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Initialize-WinPEMountPoint" -Exception $_.Exception
        throw
    }
}
```

### 3. Update the Update-WinPEWithPowerShell7 Function

Update the main function to use the proper parameter names and implement better error handling:

```powershell
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
    .PARAMETER TemporaryPath
        The temporary path where working files will be stored. This path must have sufficient
        disk space and appropriate permissions for creating and modifying files.
    .PARAMETER WorkspacePath
        The workspace path containing the WinPE image to update. This should point to a valid
        WinPE workspace directory containing the boot.wim file in the Media\Sources subdirectory.
    .PARAMETER PowerShellVersion
        The PowerShell version to install. Default is "7.3.4". Must be in X.Y.Z format and be
        a supported version. The function will validate the version format and availability.
    .PARAMETER PowerShellPackageFile
        The path to the PowerShell 7 zip file. If not specified, it will be downloaded from
        the official Microsoft repository. If specified, the file must exist and be a valid
        PowerShell 7 package.
    .PARAMETER SkipCleanup
        If specified, temporary files will not be removed after processing. This can be useful
        for debugging or when you need to inspect the intermediate files.
    .EXAMPLE
        Update-WinPEWithPowerShell7 -TemporaryPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace"
        # Basic usage with default settings
        # This will update the WinPE image with the latest supported PowerShell 7 version
    .EXAMPLE
        Update-WinPEWithPowerShell7 -TemporaryPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShellVersion "7.3.4" -Verbose
        # Install specific PowerShell version with verbose output
        # The -Verbose parameter provides detailed progress information during the update
    .EXAMPLE
        Update-WinPEWithPowerShell7 -TemporaryPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShellPackageFile "C:\Temp\PowerShell-7.3.4-win-x64.zip" -WhatIf
        # Test run using local PowerShell package
        # The -WhatIf parameter shows what changes would be made without actually making them
    .EXAMPLE
        Update-WinPEWithPowerShell7 -TemporaryPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -SkipCleanup -ErrorAction Stop
        # Keep temporary files and stop on any error
        # Useful for debugging or when you need to inspect the intermediate files
    .NOTES
        Version: 1.0.0
        Author: OSDCloud Team
        Requirements:
        - Administrator privileges
        - Windows ADK installed
        - Internet connectivity (if PowerShell package needs downloading)
        - Minimum 10GB free disk space in TemporaryPath
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
        $mountInfo = Initialize-WinPEMountPoint -TemporaryPath $TemporaryPath
        $mountPoint = $mountInfo.MountPoint
        $ps7TempPath = $mountInfo.PS7TempPath
        
        # Step 2: Get PowerShell 7 package if not provided
        if (-not $PowerShellPackageFile) {
            Write-OSDCloudLog -Message "PowerShell 7 package not provided, attempting to download" -Level Info -Component "Update-WinPEWithPowerShell7"
            $PowerShellPackageFile = Get-PowerShell7Package -Version $PowerShellVersion -DownloadPath (Join-Path -Path $ps7TempPath -ChildPath "PowerShell-$PowerShellVersion-win-x64.zip")
        }
        
        # Step 3: Locate boot.wim in the workspace
        $bootWimPath = Find-WinPEBootWim -WorkspacePath $WorkspacePath
        
        # Step 4: Mount the WinPE image with detailed operation description
        $mountOperation = @{
            Target = $bootWimPath
            Operation = "Mount to $mountPoint"
            Description = "This will mount the WinPE image for modification"
        }
            
        if ($PSCmdlet.ShouldProcess($mountOperation.Target, $mountOperation.Operation, $mountOperation.Description)) {
            Write-OSDCloudLog -Message "Mounting boot.wim" -Level Info -Component "Update-WinPEWithPowerShell7"
            Mount-WinPEImage -ImagePath $bootWimPath -MountPath $mountPoint -Index 1
        }
            
        # Step 5: Install PowerShell 7 to the mounted WinPE image with confirmation
        $installOperation = @{
            Target = $PowerShellPackageFile
            Operation = "Install PowerShell 7 to WinPE"
            Description = "This will add PowerShell 7 support to the WinPE image"
        }
            
        Write-OSDCloudLog -Message "Installing PowerShell 7 to WinPE" -Level Info -Component "Update-WinPEWithPowerShell7"
        if ($PSCmdlet.ShouldProcess($installOperation.Target, $installOperation.Operation, $installOperation.Description)) {
            Install-PowerShell7ToWinPE -PowerShell7File $PowerShellPackageFile -TempPath $ps7TempPath -MountPoint $mountPoint
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
        
        # Clean up temporary files if needed
        if (-not $SkipCleanup) {
            Remove-WinPETemporaryFiles -TempPath $TemporaryPath -MountPoint $mountPoint -PS7TempPath $ps7TempPath
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
                    Save-WinPEDiagnostics -MountPoint $mountPoint -TempPath $TemporaryPath
                }
                catch {
                    Write-OSDCloudLog -Message "Failed to collect diagnostic information: $_" -Level Warning -Component "Update-WinPEWithPowerShell7"
                }
                
                # Attempt to dismount with increasing force
                try {
                    Dismount-WinPEImage -MountPath $mountPoint -Discard
                }
                catch {
                    Write-OSDCloudLog -Message "Standard dismount failed, attempting force dismount..." -Level Warning -Component "Update-WinPEWithPowerShell7"
                    Dismount-WindowsImage -Path $mountPoint -Discard -Force
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
```

### 4. Add or Update the Alias for Backward Compatibility

Ensure the alias is properly set:

```powershell
# For backward compatibility
Set-Alias -Name Customize-WinPEWithPowerShell7 -Value Update-WinPEWithPowerShell7

# Export all functions and aliases
Export-ModuleMember -Function * -Alias *
```

### 5. Create the Save-WinPEDiagnostics Function

This function is used for error recovery and diagnostics collection:

```powershell
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
```

## Testing

After implementing the changes, run the Pester tests to ensure everything works as expected:

```powershell
Invoke-Pester -Path "D:\iTechDevelopment_Charities\OSDCloudCustomBuilder\Tests\Unit\Update-WinPEWithPowerShell7.Tests.ps1" -Output Detailed
```

## Rollback Plan

If issues are encountered during implementation, you can restore the original file from the backup:

```powershell
Copy-Item -Path "D:\iTechDevelopment_Charities\OSDCloudCustomBuilder\Private\WinPE-PowerShell7.ps1.20250401_backup" -Destination "D:\iTechDevelopment_Charities\OSDCloudCustomBuilder\Private\WinPE-PowerShell7.ps1" -Force
```

## Verification

After implementing the changes, verify that:

1. All functions have proper error handling with try/catch blocks
2. All functions have comprehensive documentation with real-world examples
3. All functions support ShouldProcess where appropriate
4. Parameter naming is consistent throughout the file
5. The main function has been renamed with the proper alias for backward compatibility
6. All tests pass successfully