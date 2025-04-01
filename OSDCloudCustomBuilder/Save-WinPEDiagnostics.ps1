<#
.SYNOPSIS
    Collects diagnostic information from a mounted WinPE image.
.DESCRIPTION
    This function gathers logs and diagnostic information from a mounted WinPE image
    for troubleshooting purposes. It creates a timestamped directory to store the
    collected information including log files, configuration files, and optionally
    registry exports.
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
function Save-WinPEDiagnostics {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,
                   Position=0,
                   HelpMessage="Path to the mounted WinPE image")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [string]$MountPoint,
        
        [Parameter(Mandatory=$true,
                   Position=1,
                   HelpMessage="Path where diagnostic information will be saved")]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter(HelpMessage="Include registry exports in diagnostics")]
        [switch]$IncludeRegistryExport
    )
    
    try {
        # Create a timestamp for unique folder names
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $diagnosticsPath = Join-Path -Path $TempPath -ChildPath "WinPE_Diagnostics_$timestamp"
        
        if ($PSCmdlet.ShouldProcess($MountPoint, "Collect diagnostic information")) {
            # Create diagnostics directory
            if (-not (Test-Path -Path $diagnosticsPath)) {
                New-Item -Path $diagnosticsPath -ItemType Directory -Force | Out-Null
            }
            
            Write-OSDCloudLog -Message "Collecting diagnostic information from $MountPoint to $diagnosticsPath" -Level Info -Component "Save-WinPEDiagnostics"
            
            # Create subdirectories for organization
            $logsDir = Join-Path -Path $diagnosticsPath -ChildPath "Logs"
            $configDir = Join-Path -Path $diagnosticsPath -ChildPath "Config"
            $registryDir = Join-Path -Path $diagnosticsPath -ChildPath "Registry"
            $filesystemDir = Join-Path -Path $diagnosticsPath -ChildPath "FileSystem"
            
            New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            New-Item -Path $filesystemDir -ItemType Directory -Force | Out-Null
            
            # Collect Windows logs
            $logSource = Join-Path -Path $MountPoint -ChildPath "Windows\Logs"
            if (Test-Path -Path $logSource) {
                Write-OSDCloudLog -Message "Collecting Windows logs" -Level Info -Component "Save-WinPEDiagnostics"
                Copy-Item -Path "$logSource\*" -Destination $logsDir -Recurse -ErrorAction SilentlyContinue
            }
            
            # Collect setup logs if they exist
            $setupLogSource = Join-Path -Path $MountPoint -ChildPath "Windows\Panther"
            if (Test-Path -Path $setupLogSource) {
                Write-OSDCloudLog -Message "Collecting setup logs" -Level Info -Component "Save-WinPEDiagnostics"
                Copy-Item -Path "$setupLogSource\*" -Destination "$logsDir\Panther" -Recurse -ErrorAction SilentlyContinue
            }
            
            # Collect important configuration files
            $configFiles = @(
                "Windows\System32\startnet.cmd",
                "Windows\System32\winpeshl.ini",
                "Windows\System32\unattend.xml",
                "Windows\System32\wpeinit.ini",
                "Windows\System32\winpeshl.ini"
            )
            
            Write-OSDCloudLog -Message "Collecting configuration files" -Level Info -Component "Save-WinPEDiagnostics"
            foreach ($file in $configFiles) {
                $sourcePath = Join-Path -Path $MountPoint -ChildPath $file
                if (Test-Path -Path $sourcePath) {
                    $destFileName = $file.Replace("Windows\System32\", "")
                    $destPath = Join-Path -Path $configDir -ChildPath $destFileName
                    Copy-Item -Path $sourcePath -Destination $destPath -ErrorAction SilentlyContinue
                }
            }
            
            # Check PowerShell 7 installation
            $ps7Path = Join-Path -Path $MountPoint -ChildPath "Windows\System32\PowerShell7"
            if (Test-Path -Path $ps7Path) {
                Write-OSDCloudLog -Message "Collecting PowerShell 7 information" -Level Info -Component "Save-WinPEDiagnostics"
                
                # Get basic file structure
                $ps7FileList = Join-Path -Path $filesystemDir -ChildPath "PowerShell7_Files.txt"
                Get-ChildItem -Path $ps7Path -Recurse | Select-Object FullName, Length, LastWriteTime | 
                    Out-File -FilePath $ps7FileList -Encoding utf8
                
                # Copy PowerShell 7 profiles if they exist
                $ps7ProfilePath = Join-Path -Path $ps7Path -ChildPath "Profiles"
                if (Test-Path -Path $ps7ProfilePath) {
                    $ps7ProfileDest = Join-Path -Path $configDir -ChildPath "PowerShell7_Profiles"
                    New-Item -Path $ps7ProfileDest -ItemType Directory -Force | Out-Null
                    Copy-Item -Path "$ps7ProfilePath\*" -Destination $ps7ProfileDest -Recurse -ErrorAction SilentlyContinue
                }
            } else {
                Write-OSDCloudLog -Message "PowerShell 7 installation not found in WinPE image" -Level Warning -Component "Save-WinPEDiagnostics"
            }
            
            # Export registry if requested
            if ($IncludeRegistryExport) {
                Write-OSDCloudLog -Message "Exporting registry hives" -Level Info -Component "Save-WinPEDiagnostics"
                New-Item -Path $registryDir -ItemType Directory -Force | Out-Null
                
                # SOFTWARE hive contains most of the PowerShell 7 related settings
                $offlineHive = Join-Path -Path $MountPoint -ChildPath "Windows\System32\config\SOFTWARE"
                $tempHivePath = "HKLM\DIAGNOSTICS_TEMP"
                
                try {
                    # Load the offline hive
                    $null = reg load $tempHivePath $offlineHive
                    
                    # Export to file
                    $regExportPath = Join-Path -Path $registryDir -ChildPath "SOFTWARE.reg"
                    $null = reg export $tempHivePath $regExportPath /y
                    
                    # Export specific PowerShell 7 related keys if they exist
                    $psPathsToExport = @(
                        "Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe"
                    )
                    
                    foreach ($psPath in $psPathsToExport) {
                        $psRegKey = "Registry::$tempHivePath\$psPath"
                        $psRegExportPath = Join-Path -Path $registryDir -ChildPath "$($psPath.Replace('\', '_')).reg"
                        
                        if (Test-Path -Path $psRegKey) {
                            $null = reg export "$tempHivePath\$psPath" $psRegExportPath /y
                        }
                    }
                }
                catch {
                    Write-OSDCloudLog -Message "Warning: Failed to export registry: $_" -Level Warning -Component "Save-WinPEDiagnostics" -Exception $_.Exception
                }
                finally {
                    # Always unload the hive in finally block to ensure it's released
                    try {
                        if (Test-Path -Path "Registry::$tempHivePath") {
                            $null = reg unload $tempHivePath
                        }
                    }
                    catch {
                        Write-OSDCloudLog -Message "Warning: Failed to unload registry hive: $_" -Level Warning -Component "Save-WinPEDiagnostics" -Exception $_.Exception
                    }
                }
            }
            
            # Also include system info
            $systemInfoPath = Join-Path -Path $diagnosticsPath -ChildPath "SystemInfo.txt"
            "WinPE Diagnostics - $(Get-Date)" | Out-File -FilePath $systemInfoPath -Encoding utf8
            "Mount Point: $MountPoint" | Out-File -FilePath $systemInfoPath -Append -Encoding utf8
            "Collection Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $systemInfoPath -Append -Encoding utf8
            
            # Add OS Version from mounted image if available
            $systemVersionPath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\ntoskrnl.exe"
            if (Test-Path -Path $systemVersionPath) {
                $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($systemVersionPath)
                "WinPE Version: $($versionInfo.ProductVersion)" | Out-File -FilePath $systemInfoPath -Append -Encoding utf8
                "File Version: $($versionInfo.FileVersion)" | Out-File -FilePath $systemInfoPath -Append -Encoding utf8
            }
            
            Write-OSDCloudLog -Message "Diagnostic information saved to: $diagnosticsPath" -Level Info -Component "Save-WinPEDiagnostics"
            return $diagnosticsPath
        }
        
        return $null
    }
    catch {
        $errorMessage = "Failed to collect diagnostic information: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Save-WinPEDiagnostics" -Exception $_.Exception
        throw $errorMessage
    }
}

# Export the function
Export-ModuleMember -Function Save-WinPEDiagnostics