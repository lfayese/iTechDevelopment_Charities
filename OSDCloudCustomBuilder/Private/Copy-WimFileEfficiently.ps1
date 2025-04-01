function Copy-WimFileEfficiently {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourcePath,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    Write-Verbose "Starting WIM file copy from '$SourcePath' to '$DestinationPath'."
    # Validate source file exists
    if (-not (Test-Path $SourcePath)) {
        Write-Error "Source file does not exist: $SourcePath"
        return $false
    }
    # Determine source and destination directories and file names in one go
    $sourceDir    = Split-Path -Parent $SourcePath
    $sourceFile   = Split-Path -Leaf $SourcePath
    $destDir      = Split-Path -Parent $DestinationPath
    $destFile     = Split-Path -Leaf $DestinationPath
    Write-Verbose "Source directory: $sourceDir, File: $sourceFile"
    Write-Verbose "Destination directory: $destDir, File: $destFile"
    # Create destination directory if it doesn't exist (use try/catch for safety)
    if (-not (Test-Path $destDir)) {
        try {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Created directory: $destDir"
        } catch {
            Write-Error "Failed to create destination directory: $destDir. Error: $_"
            return $false
        }
    }
    # Skip if destination file already exists and -Force is not specified
    if ((Test-Path $DestinationPath) -and -not $Force) {
        Write-Verbose "Destination file exists. Skipping copy (use -Force to overwrite)."
        return $true
    }
    Write-Verbose "Using robocopy to copy file."
    # Use Robocopy for better performance with large files
    $robocopyArgs = @(
        "`"$sourceDir`"",
        "`"$destDir`"",
        "`"$sourceFile`"",
        "/J",          # Unbuffered I/O for large file optimization
        "/NP",         # No progress – avoid screen clutter
        "/MT:8",       # Multi-threaded copying with 8 threads
        "/R:2",        # Retry 2 times
        "/W:5"         # Wait 5 seconds between retries
    )
    $robocopyProcess = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
    # Robocopy exit codes: 0-7 are success (8+ are failures)
    if ($robocopyProcess.ExitCode -lt 8) {
        $copiedFilePath = Join-Path $destDir $sourceFile
        # If destination file name differs, rename the copied file
        if ($sourceFile -ne $destFile) {
            $finalPath = Join-Path $destDir $destFile
            if (Test-Path $finalPath) {
                Remove-Item -Path $finalPath -Force
                Write-Verbose "Removed existing file at final destination: $finalPath"
            }
            Rename-Item -Path $copiedFilePath -NewName $destFile -Force
            Write-Verbose "Renamed copied file to: $destFile"
        }
        Write-Verbose "WIM file copied successfully."
        return $true
    } else {
        Write-Error "Failed to copy WIM file. Robocopy exit code: $($robocopyProcess.ExitCode)"
        return $false
    }
}