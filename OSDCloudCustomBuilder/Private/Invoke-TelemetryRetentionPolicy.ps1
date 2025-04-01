# Invoke-TelemetryRetentionPolicy.ps1
# This function implements a configurable retention policy for telemetry data
# Created: March 2023
# Author: OSDCloudCustomBuilder Team

function Invoke-TelemetryRetentionPolicy {
    <#
    .SYNOPSIS
        Applies retention policy to telemetry data
    .DESCRIPTION
        This function applies retention policies to telemetry data. It can:
        - Remove telemetry entries older than the specified retention period
        - Archive old telemetry files
        - Purge empty telemetry files
    .PARAMETER RetentionDays
        Number of days to keep telemetry data. Entries older than this will be removed.
    .PARAMETER TelemetryPath
        Path to the telemetry data files. If not specified, uses the path from module configuration.
    .PARAMETER ArchiveExpiredData
        If specified, moves expired telemetry files to an archive location instead of modifying them.
    .PARAMETER ArchivePath
        Path to archive expired telemetry files. Required when ArchiveExpiredData is specified.
    .PARAMETER PurgeEmptyFiles
        If specified, removes telemetry files that have no entries after processing.
    .EXAMPLE
        Invoke-TelemetryRetentionPolicy -RetentionDays 90
        Removes telemetry entries older than 90 days from all telemetry files.
    .EXAMPLE
        Invoke-TelemetryRetentionPolicy -RetentionDays 30 -ArchiveExpiredData -ArchivePath "D:\TelemetryArchive"
        Archives telemetry files older than 30 days to the specified archive path.
    .EXAMPLE
        Invoke-TelemetryRetentionPolicy -RetentionDays 60 -PurgeEmptyFiles
        Removes telemetry entries older than 60 days and deletes any files that end up empty.
    .NOTES
        This function is part of the telemetry management system for OSDCloudCustomBuilder.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$RetentionDays,
        [Parameter(Mandatory = $false)]
        [string]$TelemetryPath,
        [Parameter(Mandatory = $false)]
        [switch]$ArchiveExpiredData,
        [Parameter(Mandatory = $false)]
        [string]$ArchivePath,
        [Parameter(Mandatory = $false)]
        [switch]$PurgeEmptyFiles
    )
    try {
        # Get module configuration
        $config = Get-ModuleConfiguration
        # Use specified path or default from config
        if (-not $TelemetryPath) {
            $TelemetryPath = $config.Telemetry.StoragePath
        }
        if (-not (Test-Path -Path $TelemetryPath)) {
            Write-Error "Telemetry path '$TelemetryPath' does not exist"
            return $false
        }
        # Validate archive path if archiving is enabled
        if ($ArchiveExpiredData -and -not $ArchivePath) {
            Write-Error "ArchivePath parameter is required when ArchiveExpiredData is specified"
            return $false
        }
        if ($ArchiveExpiredData -and -not (Test-Path -Path $ArchivePath)) {
            try {
                New-Item -Path $ArchivePath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created archive directory at '$ArchivePath'"
            }
            catch {
                Write-Error "Failed to create archive directory at '$ArchivePath': $_"
                return $false
            }
        }
        # Calculate retention date once
        $retentionDate = (Get-Date).AddDays(-$RetentionDays)
        $retentionDateFormatted = $retentionDate.ToString('yyyy-MM-dd')
        Write-Verbose "Keeping telemetry data from $retentionDateFormatted forward"
        # Get all telemetry files
        $telemetryFiles = Get-ChildItem -Path $TelemetryPath -Filter "*.json" -File
        # Initialize result metrics
        $result = @{
            FilesProcessed   = 0
            FilesArchived    = 0
            FilesPurged      = 0
            EntriesProcessed = 0
            EntriesRemoved   = 0
        }
        foreach ($file in $telemetryFiles) {
            Write-Verbose "Processing telemetry file: $($file.Name)"
            $result.FilesProcessed++
            # Archive whole file if appropriate
            if ($ArchiveExpiredData -and $file.LastWriteTime -lt $retentionDate) {
                Write-Verbose "Archiving telemetry file: $($file.Name)"
                try {
                    $destinationPath = Join-Path -Path $ArchivePath -ChildPath $file.Name
                    Move-Item -Path $file.FullName -Destination $destinationPath -Force
                    $result.FilesArchived++
                }
                catch {
                    Write-Warning "Failed to archive telemetry file '$($file.FullName)': $_"
                }
                continue
            }
            # Load telemetry data from file
            try {
                $fileContent = Get-Content -Path $file.FullName -Raw
                $telemetryData = $fileContent | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to parse telemetry file '$($file.FullName)': $_"
                continue
            }
            # Process telemetry entries if available
            if ($telemetryData.Entries -and $telemetryData.Entries.Count -gt 0) {
                $originalCount = $telemetryData.Entries.Count
                $result.EntriesProcessed += $originalCount
                # Create a new list of valid entries using a loop (avoids pipeline overhead)
                $filteredEntries = @()
                foreach ($entry in $telemetryData.Entries) {
                    $timestampStr = $entry.Timestamp
                    $timestamp = $null
                    # Use TryParse instead of exceptions for performance
                    if ([datetime]::TryParse($timestampStr, [ref]$timestamp)) {
                        if ($timestamp -ge $retentionDate) {
                            $filteredEntries += $entry
                        }
                    }
                    else {
                        # Log and keep entry with invalid timestamp
                        Write-Warning "Failed to parse timestamp in entry: $timestampStr"
                        $filteredEntries += $entry
                    }
                }
                $telemetryData.Entries = $filteredEntries
                $entriesRemoved = $originalCount - $telemetryData.Entries.Count
                $result.EntriesRemoved += $entriesRemoved
                if ($entriesRemoved -gt 0) {
                    Write-Verbose "Removed $entriesRemoved entries from $($file.Name)"
                }
                # Purge file if empty and purging is enabled
                if ($PurgeEmptyFiles -and $telemetryData.Entries.Count -eq 0) {
                    Write-Verbose "Purging empty telemetry file: $($file.Name)"
                    try {
                        Remove-Item -Path $file.FullName -Force
                        $result.FilesPurged++
                    }
                    catch {
                        Write-Warning "Failed to purge empty telemetry file '$($file.FullName)': $_"
                    }
                }
                else {
                    # Write updated telemetry data back to file
                    try {
                        $telemetryData | ConvertTo-Json -Depth 10 | Set-Content -Path $file.FullName -Force
                    }
                    catch {
                        Write-Warning "Failed to write updated telemetry data to '$($file.FullName)': $_"
                    }
                }
            }
            elseif ($PurgeEmptyFiles) {
                # In case there are no entries and purging was requested:
                Write-Verbose "Purging empty telemetry file: $($file.Name)"
                try {
                    Remove-Item -Path $file.FullName -Force
                    $result.FilesPurged++
                }
                catch {
                    Write-Warning "Failed to purge empty telemetry file '$($file.FullName)': $_"
                }
            }
        }
        # Return processing results
        return $result
    }
    catch {
        Write-Error "Failed to process telemetry retention policy: $_"
        return $false
    }
}
# Export the function
Export-ModuleMember -Function Invoke-TelemetryRetentionPolicy