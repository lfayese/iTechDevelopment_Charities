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
function Remove-WinPETemporaryFiles {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,
                  Position=0,
                  HelpMessage="Path containing temporary files")]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter(Position=1,
                  HelpMessage="The mount point path to clean up")]
        [string]$MountPoint,
        
        [Parameter(Position=2,
                  HelpMessage="Path containing PowerShell 7 temporary files")]
        [string]$PS7TempPath,
        
        [Parameter(HelpMessage="Skip cleanup of temporary files")]
        [switch]$SkipCleanup
    )
    
    if ($SkipCleanup) {
        Write-OSDCloudLog -Message "Skipping cleanup of temporary files (SkipCleanup specified)" -Level Info -Component "Remove-WinPETemporaryFiles"
        return
    }
    
    Write-OSDCloudLog -Message "Cleaning up temporary files from the WinPE update process" -Level Info -Component "Remove-WinPETemporaryFiles"
    
    $pathsToRemove = @()
    
    # Add specified paths if they exist
    if ($MountPoint -and (Test-Path -Path $MountPoint -PathType Container)) {
        $pathsToRemove += $MountPoint
        Write-OSDCloudLog -Message "Adding mount point to cleanup list: $MountPoint" -Level Info -Component "Remove-WinPETemporaryFiles"
    }
    
    if ($PS7TempPath -and (Test-Path -Path $PS7TempPath -PathType Container)) {
        $pathsToRemove += $PS7TempPath
        Write-OSDCloudLog -Message "Adding PS7 temp path to cleanup list: $PS7TempPath" -Level Info -Component "Remove-WinPETemporaryFiles"
    }
    
    # If specific paths weren't provided, try to find pattern-based paths in the temp directory
    if ((-not $MountPoint -or -not $PS7TempPath) -and (Test-Path -Path $TempPath -PathType Container)) {
        Write-OSDCloudLog -Message "Looking for pattern-based temporary directories in: $TempPath" -Level Info -Component "Remove-WinPETemporaryFiles"
        
        if (-not $MountPoint) {
            $mountPatterns = Get-ChildItem -Path $TempPath -Directory -Filter "Mount_*"
            foreach ($dir in $mountPatterns) {
                Write-OSDCloudLog -Message "Adding detected mount point to cleanup list: $($dir.FullName)" -Level Info -Component "Remove-WinPETemporaryFiles"
                $pathsToRemove += $dir.FullName
            }
        }
        
        if (-not $PS7TempPath) {
            $ps7Patterns = Get-ChildItem -Path $TempPath -Directory -Filter "PS7_*"
            foreach ($dir in $ps7Patterns) {
                Write-OSDCloudLog -Message "Adding detected PS7 temp directory to cleanup list: $($dir.FullName)" -Level Info -Component "Remove-WinPETemporaryFiles"
                $pathsToRemove += $dir.FullName
            }
        }
    }
    
    # Process all paths to remove
    foreach ($path in $pathsToRemove) {
        try {
            if ($PSCmdlet.ShouldProcess($path, "Remove temporary directory")) {
                Write-OSDCloudLog -Message "Removing temporary directory: $path" -Level Info -Component "Remove-WinPETemporaryFiles"
                
                # Check if path exists before attempting to remove it
                if (Test-Path -Path $path -PathType Container) {
                    # First, ensure all files are not read-only
                    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | 
                        Where-Object { -not $_.PSIsContainer } | 
                        ForEach-Object { $_.IsReadOnly = $false }
                    
                    # Then remove the directory
                    Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                    Write-OSDCloudLog -Message "Successfully removed: $path" -Level Info -Component "Remove-WinPETemporaryFiles"
                }
                else {
                    Write-OSDCloudLog -Message "Path not found, skipping: $path" -Level Warning -Component "Remove-WinPETemporaryFiles"
                }
            }
        }
        catch {
            # Log but continue with other directories
            $errorMessage = "Warning: Failed to remove temporary directory $path: $_"
            Write-OSDCloudLog -Message $errorMessage -Level Warning -Component "Remove-WinPETemporaryFiles"
        }
    }
    
    # Check temp path for leftover files pattern-matching common PowerShell 7 packages
    try {
        if ($PSCmdlet.ShouldProcess($TempPath, "Clean up PowerShell package files")) {
            $ps7PackageFiles = Get-ChildItem -Path $TempPath -Filter "PowerShell-7*.zip" -File -ErrorAction SilentlyContinue
            
            foreach ($file in $ps7PackageFiles) {
                try {
                    Write-OSDCloudLog -Message "Removing PowerShell package file: $($file.FullName)" -Level Info -Component "Remove-WinPETemporaryFiles"
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                }
                catch {
                    Write-OSDCloudLog -Message "Failed to remove PowerShell package file: $($file.FullName) - $_" -Level Warning -Component "Remove-WinPETemporaryFiles"
                }
            }
        }
    }
    catch {
        Write-OSDCloudLog -Message "Error cleaning up PowerShell package files: $_" -Level Warning -Component "Remove-WinPETemporaryFiles"
    }
    
    Write-OSDCloudLog -Message "Temporary file cleanup completed" -Level Info -Component "Remove-WinPETemporaryFiles"
}

# Export the function
Export-ModuleMember -Function Remove-WinPETemporaryFiles