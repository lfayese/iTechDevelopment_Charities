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
        [ValidateScript({!$_ -or (Test-Path $_ -PathType Leaf)})]
        [Alias("PSPackage", "PackagePath")]
        [string]$PowerShell7File,
        
        [Parameter(HelpMessage="Skip cleanup of temporary files")]
        [Alias("NoCleanup", "KeepFiles")]
        [switch]$SkipCleanup
    )
    
    Write-OSDCloudLog -Message "Starting WinPE customization with PowerShell $PowerShellVersion" -Level Info -Component "Update-WinPEWithPowerShell7"
    
    try {
        # Step 1: Initialize WinPE mount point
        Write-OSDCloudLog -Message "Initializing mount points" -Level Info -Component "Update-WinPEWithPowerShell7"
        $mountInfo = Initialize-WinPEMountPoint -TemporaryPath $TempPath
        $mountPoint = $mountInfo.MountPoint
        $ps7TempPath = $mountInfo.PS7TempPath
        
        # Step 2: Get PowerShell 7 package if not provided
        if (-not $PowerShell7File) {
            Write-OSDCloudLog -Message "PowerShell 7 package not provided, attempting to download" -Level Info -Component "Update-WinPEWithPowerShell7"
            $PowerShell7File = Get-PowerShell7Package -Version $PowerShellVersion -DownloadPath (Join-Path -Path $ps7TempPath -ChildPath "PowerShell-$PowerShellVersion-win-x64.zip")
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
        
        # Step 10: Clean up temporary files if needed
        Remove-WinPETemporaryFiles -TempPath $TempPath -MountPoint $mountPoint -PS7TempPath $ps7TempPath -SkipCleanup:$SkipCleanup
        
        return $bootWimPath
    }
    catch {
        # Collect diagnostic information on error
        try {
            if (Test-Path -Path $mountPoint -PathType Container) {
                Write-OSDCloudLog -Message "Critical error occurred. Collecting diagnostics and attempting recovery." -Level Warning -Component "Update-WinPEWithPowerShell7"
                
                # Collect diagnostic information
                $diagnosticsPath = Save-WinPEDiagnostics -MountPoint $mountPoint -TempPath $TempPath -IncludeRegistryExport
                Write-OSDCloudLog -Message "Diagnostic information saved to: $diagnosticsPath" -Level Info -Component "Update-WinPEWithPowerShell7"
                
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