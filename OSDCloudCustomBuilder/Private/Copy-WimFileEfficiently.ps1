function Copy-WimFileEfficiently {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        
        [Parameter(Mandatory=$false)]
        [string]$NewName = $null
    )
    
    Write-Host "Copying WIM file to $DestinationPath..." -ForeColor Cyan
    
    # Create destination directory if it doesn't exist
    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }
    
    # Get source file details
    $sourceDir = Split-Path -Parent $SourcePath
    $sourceFileName = Split-Path -Leaf $SourcePath
    
    # Use Robocopy for better performance with large files
    $robocopyArgs = @(
        "`"$sourceDir`"",
        "`"$destDir`"",
        "`"$sourceFileName`"",
        "/J",          # Unbuffered I/O for large file optimization
        "/NP",         # No progress - avoid screen clutter
        "/R:2",        # Retry 2 times
        "/W:5"         # Wait 5 seconds between retries
    )
    
    $robocopyProcess = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
    
    # Robocopy exit codes: 0-7 are success (8+ are failures)
    if ($robocopyProcess.ExitCode -lt 8) {
        # Rename if requested
        if ($NewName) {
            $tempPath = Join-Path $destDir $sourceFileName
            $finalPath = Join-Path $destDir $NewName
            Rename-Item -Path $tempPath -NewName $NewName -Force
            Write-Host "WIM file renamed to $NewName" -ForeColor Green
        }
        
        Write-Host "WIM file copied successfully" -ForeColor Green
        return $true
    } else {
        Write-Error "Failed to copy WIM file. Robocopy exit code: $($robocopyProcess.ExitCode)"
        return $false
    }
}