function Copy-WimFileEfficiently {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    Write-Host "Copying WIM file to $DestinationPath..." -ForeColor Cyan
    
    # Validate source file exists
    if (-not (Test-Path $SourcePath)) {
        Write-Error "Source file does not exist: $SourcePath"
        return $false
    }
    
    # Create destination directory if it doesn't exist
    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }
    
    # Skip if destination already exists and -Force not specified
    if ((Test-Path $DestinationPath) -and -not $Force) {
        Write-Host "Destination file already exists. Use -Force to overwrite." -ForeColor Yellow
        return $true
    }
    
    # Get source file details
    $sourceDir = Split-Path -Parent $SourcePath
    $sourceFileName = Split-Path -Leaf $SourcePath
    $destFileName = Split-Path -Leaf $DestinationPath
    
    # Use Robocopy for better performance with large files
    $robocopyArgs = @(
        "`"$sourceDir`"",
        "`"$destDir`"",
        "`"$sourceFileName`"",
        "/J",          # Unbuffered I/O for large file optimization
        "/NP",         # No progress - avoid screen clutter
        "/MT:8",       # Multi-threaded copying with 8 threads
        "/R:2",        # Retry 2 times
        "/W:5"         # Wait 5 seconds between retries
    )
    
    $robocopyProcess = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
    
    # Robocopy exit codes: 0-7 are success (8+ are failures)
    if ($robocopyProcess.ExitCode -lt 8) {
        # Rename if the destination filename is different from the source
        $copiedFilePath = Join-Path $destDir $sourceFileName
        if ($sourceFileName -ne $destFileName) {
            $finalPath = Join-Path $destDir $destFileName
            if (Test-Path $finalPath) {
                Remove-Item -Path $finalPath -Force
            }
            Rename-Item -Path $copiedFilePath -NewName $destFileName -Force
            Write-Host "WIM file renamed to $destFileName" -ForeColor Green
        }
        
        Write-Host "WIM file copied successfully" -ForeColor Green
        return $true
    } else {
        Write-Error "Failed to copy WIM file. Robocopy exit code: $($robocopyProcess.ExitCode)"
        return $false
    }
}