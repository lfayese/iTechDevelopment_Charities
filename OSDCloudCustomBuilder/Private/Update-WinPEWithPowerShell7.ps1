<#
.SYNOPSIS
    Updates a WinPE image with PowerShell 7 support.
.DESCRIPTION
    This function updates a WinPE image by adding PowerShell 7 support, configuring startup settings,
    and updating environment variables. It handles the entire process of mounting the WIM file,
    making modifications, and dismounting with changes saved.
.PARAMETER TempPath
    The temporary path where working files will be stored.
.PARAMETER WorkspacePath
    The workspace path containing the WinPE image to update.
.PARAMETER PowerShellVersion
    The PowerShell version to install. Default is "7.3.4".
.PARAMETER PowerShell7File
    The path to the PowerShell 7 zip file. If not specified, it will be downloaded.
.PARAMETER MountTimeout
    Maximum time in seconds to wait for mount operations (default: from configuration).
.PARAMETER DismountTimeout
    Maximum time in seconds to wait for dismount operations (default: from configuration).
.PARAMETER DownloadTimeout
    Maximum time in seconds to wait for download operations (default: from configuration).
.EXAMPLE
    Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace"
.EXAMPLE
    Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShellVersion "7.3.4"
.EXAMPLE
    Update-WinPEWithPowerShell7 -TempPath "C:\Temp\OSDCloud" -WorkspacePath "C:\OSDCloud\Workspace" -PowerShell7File "C:\Temp\PowerShell-7.3.4-win-x64.zip"
.NOTES
    This function requires administrator privileges and the Windows ADK installed.
#>
function Update-WinPEWithPowerShell7 {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkspacePath,
        
        [Parameter()]
        [ValidateScript({
            if (Test-ValidPowerShellVersion -Version $_) { 
                return $true 
            }
            throw "Invalid PowerShell version format. Must be in X.Y.Z format and be a supported version."
        })]
        [string]$PowerShellVersion,
        
        [Parameter()]
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
        [string]$PowerShell7File,
        
        [Parameter()]
        [int]$MountTimeout,
        
        [Parameter()]
        [int]$DismountTimeout,
        
        [Parameter()]
        [int]$DownloadTimeout
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
        
        # Apply timeout parameters from config if not specified
        if (-not $MountTimeout) {
            $MountTimeout = $config.Timeouts.Mount
        }
        
        if (-not $DismountTimeout) {
            $DismountTimeout = $config.Timeouts.Dismount
        }
        
        if (-not $DownloadTimeout) {
            $DownloadTimeout = $config.Timeouts.Download
        }
        
        # Log operation start
        Write-OSDCloudLog -Message "Starting WinPE update with PowerShell 7 v$PowerShellVersion" -Level Info -Component "Update-WinPEWithPowerShell7"
        
        # If PowerShell7File is not specified, try to use cached or download it
        if ([string]::IsNullOrEmpty($PowerShell7File)) {
            try {
                # First check if we have a cached copy
                $cachedPackage = Get-CachedPowerShellPackage -Version $PowerShellVersion
                if ($cachedPackage) {
                    $PowerShell7File = $cachedPackage
                    Write-OSDCloudLog -Message "Using cached PowerShell 7 package: $PowerShell7File" -Level Info -Component "Update-WinPEWithPowerShell7"
                }
                else {
                    # Download the package
                    $downloadPath = Join-Path -Path $TempPath -ChildPath "PowerShell-$PowerShellVersion-win-x64.zip"
                    
                    Write-OSDCloudLog -Message "Downloading PowerShell 7 v$PowerShellVersion" -Level Info -Component "Update-WinPEWithPowerShell7"
                    
                    $PowerShell7File = Get-PowerShell7Package -Version $PowerShellVersion -DownloadPath $downloadPath
                    
                    if (-not $PowerShell7File -or -not (Test-Path $PowerShell7File)) {
                        throw "Failed to download PowerShell 7 package"
                    }
                }
            }
            catch {
                $errorMessage = "Failed to download PowerShell 7 package: $_"
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
                throw
            }
        }
        
        # Verify PowerShell 7 file exists
        if (-not (Test-Path -Path $PowerShell7File)) {
            $errorMessage = "PowerShell 7 file not found at path: $PowerShell7File"
            Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7"
            throw $errorMessage
        }
    }
    
    process {
        $mountInfo = $null
        
        try {
            # Step 1: Initialize mount point and temporary directories
            $mountInfo = Initialize-WinPEMountPoint -TempPath $TempPath -InstanceId $instanceId
            $uniqueMountPoint = $mountInfo.MountPoint
            $ps7TempPath = $mountInfo.PS7TempPath
            
            # Step 2: Create startup profile directory
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Create startup profile directory")) {
                New-WinPEStartupProfile -MountPoint $uniqueMountPoint
            }
            
            # Step 3: Mount WinPE Image
            $wimPath = Join-Path -Path $WorkspacePath -ChildPath "Media\Sources\boot.wim"
            if (-not (Test-Path -Path $wimPath)) {
                $errorMessage = "WinPE image not found at path: $wimPath"
                Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7"
                throw $errorMessage
            }
            
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Mount image for customization")) {
                Mount-WinPEImage -ImagePath $wimPath -MountPath $uniqueMountPoint
            }
            
            # Step 4: Install PowerShell 7
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Install PowerShell 7")) {
                Install-PowerShell7ToWinPE -PowerShell7File $PowerShell7File -TempPath $ps7TempPath -MountPoint $uniqueMountPoint
            }
            
            # Step 5: Update registry
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Update registry settings")) {
                Update-WinPERegistry -MountPoint $uniqueMountPoint -PowerShell7Path "X:\Windows\System32\PowerShell7"
            }
            
            # Step 6: Update startup configuration
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Update startup configuration")) {
                Update-WinPEStartup -MountPoint $uniqueMountPoint -PowerShell7Path "X:\Windows\System32\PowerShell7"
            }
            
            # Step 7: Dismount WinPE Image
            if ($PSCmdlet.ShouldProcess("WinPE Image", "Dismount image and save changes")) {
                Dismount-WinPEImage -MountPath $uniqueMountPoint -Save
            }
            
            # Log success
            Write-OSDCloudLog -Message "WinPE update with PowerShell 7 completed successfully" -Level Info -Component "Update-WinPEWithPowerShell7"
            
            # Return the boot.wim path
            return $wimPath
        }
        catch {
            $errorMessage = "Failed to update WinPE: $_"
            Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
            
            # Try to dismount if mounted (don't save changes)
            try {
                if ($mountInfo -and (Test-Path -Path $mountInfo.MountPoint)) {
                    if ($PSCmdlet.ShouldProcess("WinPE Image", "Dismount image and discard changes due to error")) {
                        Dismount-WinPEImage -MountPath $mountInfo.MountPoint -Discard
                    }
                }
            }
            catch {
                $cleanupError = "Error during cleanup: $_"
                Write-OSDCloudLog -Message $cleanupError -Level Warning -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
            }
            
            throw
        }
        finally {
            # Clean up temporary resources
            try {
                if ($mountInfo) {
                    # Clean up mount point
                    if (Test-Path -Path $mountInfo.MountPoint) {
                        Remove-Item -Path $mountInfo.MountPoint -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    
                    # Clean up PowerShell 7 temp path
                    if (Test-Path -Path $mountInfo.PS7TempPath) {
                        Remove-Item -Path $mountInfo.PS7TempPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                
                # Force garbage collection to free up memory
                [System.GC]::Collect()
                
                Write-OSDCloudLog -Message "Cleanup of temporary resources completed" -Level Info -Component "Update-WinPEWithPowerShell7"
            }
            catch {
                $cleanupError = "Error cleaning up temporary resources: $_"
                Write-OSDCloudLog -Message $cleanupError -Level Warning -Component "Update-WinPEWithPowerShell7" -Exception $_.Exception
            }
        }
    }
}

# Add an alias for backward compatibility
New-Alias -Name Customize-WinPEWithPowerShell7 -Value Update-WinPEWithPowerShell7 -Description "Backward compatibility alias" -Force

# Export both the function and the alias
Export-ModuleMember -Function Update-WinPEWithPowerShell7 -Alias Customize-WinPEWithPowerShell7