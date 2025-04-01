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