<#
.SYNOPSIS
    Updates a WinPE image with PowerShell 7 support.
.DESCRIPTION
    This function serves as the main orchestrator for updating a WinPE image with PowerShell 7 support.
    It coordinates the following operations:
    - Initializes working directories and mount points
    - Downloads or validates PowerShell 7 package
    - Mounts and modifies the WinPE image
    - Installs and configures PowerShell 7
    - Updates system settings and startup configuration
    - Handles cleanup and error recovery
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
.EXAMPLE
    Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShellVersion "7.3.4" -Verbose
    # Install specific PowerShell version with verbose output
.EXAMPLE
    Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShell7File "C:\Temp\PowerShell-7.3.4-win-x64.zip" -WhatIf
    # Test run using local PowerShell package
.EXAMPLE
    Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -SkipCleanup -ErrorAction Stop
    # Keep temporary files and stop on any error
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
function Update-WinPEWithPowerShell7 {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,
                   Position=0,
                   HelpMessage="Path for temporary working files")]
        [ValidateNotNullOrEmpty()]
        [Alias("WorkingPath", "StagingPath")]
        [string]$TempPath,
        
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
        [ValidateScript({
            if ([string]::IsNullOrEmpty($_)) { return $true }
            if (-not (Test-Path $_ -PathType Leaf)) {
                throw "The PowerShell 7 file '$_' does not exist or is not a file."
            }
            if (-not ($_ -match '\.zip$')) {
                throw "The file '$_' is not a ZIP file."
            }
            return $true
        })]
        [Alias("PSPackage", "PackagePath")]
        [string]$PowerShell7File,
        
        [Parameter(HelpMessage="Skip cleanup of temporary files")]
        [Alias("NoCleanup", "KeepFiles")]
        [switch]$SkipCleanup
    )
    
    begin {
        # Generate a unique ID for this execution instance
        $instanceId = [Guid]::NewGuid().ToString()
        
        # Get module configuration
        $config = Get-ModuleConfiguration
        
        # Set default PowerShell version if not specified
        if (-not $PowerShellVersion) {
            $PowerShellVersion = $config.PowerShellVersions.Default
            Write-OSDCloudLog -Message "Using default PowerShell version: $PowerShellVersion" -Level Info -Component "Update-WinPEWithPowerShell7"
        }
        
        # Log operation start
        Write-OSDCloudLog -Message "Starting WinPE update with PowerShell 7 v$PowerShellVersion" -Level Info -Component "Update-WinPEWithPowerShell7"
    }
    
    process {
        $mountPoint = $null
        $ps7TempPath = $null
        $bootWimPath = $null
        $diagnosticsPath = $null
        
        try {
            # Step 1: Initialize mount point and temporary directories
            Write-OSDCloudLog -Message "Initializing mount points" -Level Info -Component "Update-WinPEWithPowerShell7"
            $mountInfo = Initialize-WinPEMountPoint -TempPath $TempPath -InstanceId $instanceId
            $mountPoint = $mountInfo.MountPoint
            $ps7TempPath = $mountInfo.PS7TempPath
            
            # Step 2: Find and validate the boot.wim file
            Write-OSDCloudLog -Message "Locating boot.wim file" -Level Info -Component "Update-WinPEWithPowerShell7"
            $bootWimPath = Find-WinPEBootWim -WorkspacePath $WorkspacePath
            
            # Step 3: Get or validate PowerShell 7 package
            Write-OSDCloudLog -Message "Obtaining PowerShell 7 package" -Level Info -Component "Update-WinPEWithPowerShell7"
            if ([string]::IsNullOrEmpty($PowerShell7File)) {
                $downloadPath = Join-Path -Path $TempPath -ChildPath "PowerShell-$PowerShellVersion-win-x64.zip"
                $PowerShell7File = Get-PowerShell7Package -Version $PowerShellVersion -DownloadPath $downloadPath
            }
            
            # Step 4: Mount the WinPE image
            $mountMessage = "Mounting WinPE image from $bootWimPath to $mountPoint"
            if ($PSCmdlet.ShouldProcess($bootWimPath, $mountMessage)) {
                Write-OSDCloudLog -Message $mountMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                Mount-WinPEImage -ImagePath $bootWimPath -MountPath $mountPoint
            }
            
            # Step 5: Create PowerShell 7 startup profile directory
            $profileMessage = "Creating PowerShell 7 profile directory"
            if ($PSCmdlet.ShouldProcess($mountPoint, $profileMessage)) {
                Write-OSDCloudLog -Message $profileMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                New-WinPEStartupProfile -MountPoint $mountPoint
            }
            
            # Step 6: Install PowerShell 7
            $installMessage = "Installing PowerShell 7 to WinPE image"
            if ($PSCmdlet.ShouldProcess($mountPoint, $installMessage)) {
                Write-OSDCloudLog -Message $installMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                Install-PowerShell7ToWinPE -PowerShell7File $PowerShell7File -TempPath $ps7TempPath -MountPoint $mountPoint
            }
            
            # Step 7: Update registry settings
            $registryMessage = "Updating registry settings for PowerShell 7"
            if ($PSCmdlet.ShouldProcess($mountPoint, $registryMessage)) {
                Write-OSDCloudLog -Message $registryMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                Update-WinPERegistry -MountPoint $mountPoint -PowerShell7Path "X:\Windows\System32\PowerShell7"
            }
            
            # Step 8: Update startup configuration
            $startupMessage = "Configuring WinPE to start PowerShell 7 automatically"
            if ($PSCmdlet.ShouldProcess($mountPoint, $startupMessage)) {
                Write-OSDCloudLog -Message $startupMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                Update-WinPEStartup -MountPoint $mountPoint -PowerShell7Path "X:\Windows\System32\PowerShell7"
            }
            
            # Step 9: Save diagnostics information (optional)
            if (Test-Path -Path $mountPoint) {
                $diagnosticsPath = Save-WinPEDiagnostics -MountPoint $mountPoint -TempPath $TempPath
                Write-OSDCloudLog -Message "Saved diagnostics information to $diagnosticsPath" -Level Info -Component "Update-WinPEWithPowerShell7"
            }
            
            # Step 10: Dismount and save changes
            $dismountMessage = "Dismounting WinPE image and saving changes"
            if ($PSCmdlet.ShouldProcess($mountPoint, $dismountMessage)) {
                Write-OSDCloudLog -Message $dismountMessage -Level Info -Component "Update-WinPEWithPowerShell7"
                Dismount-WinPEImage -MountPath $mountPoint
            }
            
            # Log success
            Write-OSDCloudLog -Message "WinPE update with PowerShell 7 completed successfully" -Level Info -Component "Update-WinPEWithPowerShell7"
            
            # Return the path to the updated WIM file
            return $bootWimPath
        }
        catch {
            $errorMessage = "Failed to update WinPE with PowerShell 7: $_"
            Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
            
            # Try to collect diagnostics if we can
            try {
                if ($mountPoint -and (Test-Path -Path $mountPoint)) {
                    $diagnosticsPath = Save-WinPEDiagnostics -MountPoint $mountPoint -TempPath $TempPath -IncludeRegistryExport
                    Write-OSDCloudLog -Message "Saved error diagnostics to $diagnosticsPath" -Level Warning -Component "Update-WinPEWithPowerShell7"
                }
            }
            catch {
                Write-OSDCloudLog -Message "Failed to save diagnostics during error handling: $_" -Level Warning -Component "Update-WinPEWithPowerShell7"
            }
            
            # Try to dismount if mounted (don't save changes)
            try {
                if ($mountPoint -and (Test-Path -Path $mountPoint)) {
                    if ($PSCmdlet.ShouldProcess($mountPoint, "Dismount image and discard changes due to error")) {
                        Dismount-WinPEImage -MountPath $mountPoint -Discard
                    }
                }
            }
            catch {
                $cleanupError = "Error during dismount cleanup: $_"
                Write-OSDCloudLog -Message $cleanupError -Level Warning -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
            }
            
            throw
        }
        finally {
            # Clean up temporary resources if not explicitly skipped
            if (-not $SkipCleanup) {
                try {
                    Write-OSDCloudLog -Message "Cleaning up temporary resources" -Level Info -Component "Update-WinPEWithPowerShell7"
                    Remove-WinPETemporaryFiles -TempPath $TempPath -MountPoint $mountPoint -PS7TempPath $ps7TempPath
                }
                catch {
                    $cleanupError = "Error cleaning up temporary resources: $_"
                    Write-OSDCloudLog -Message $cleanupError -Level Warning -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
                }
            }
            else {
                Write-OSDCloudLog -Message "Skipping cleanup as requested" -Level Info -Component "Update-WinPEWithPowerShell7"
                if ($diagnosticsPath) {
                    Write-OSDCloudLog -Message "Diagnostic information is available at: $diagnosticsPath" -Level Info -Component "Update-WinPEWithPowerShell7"
                }
            }
            
            # Force garbage collection to free up memory
            [System.GC]::Collect()
        }
    }
}

# Add an alias for backward compatibility
New-Alias -Name Customize-WinPEWithPowerShell7 -Value Update-WinPEWithPowerShell7 -Description "Backward compatibility alias" -Force

# Export the function and alias
Export-ModuleMember -Function Update-WinPEWithPowerShell7 -Alias Customize-WinPEWithPowerShell7