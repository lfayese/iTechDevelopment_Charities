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