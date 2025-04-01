function Copy-CustomWimToWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WimPath,
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath,
        [Parameter(Mandatory = $false)]
        [switch]$UseRobocopy
    )
    
    # Cache the split path results to avoid redundant calls
    $wimFile = Split-Path -Path $WimPath -Leaf
    $wimDir  = Split-Path -Path $WimPath -Parent
    if ($UseRobocopy -and (Get-Command "robocopy.exe" -ErrorAction SilentlyContinue)) {
        # Use robocopy for faster copying of large files
        # /J: copy using unbuffered I/O (faster for large files)
        # /MT: multithreaded copying
        $robocopyParams = @(
            "`"$wimDir`"",
            "`"$WorkspacePath`"",
            "`"$wimFile`"",
            "/J",
            "/MT:8"
        )
        $robocopyResult = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyParams -NoNewWindow -Wait -PassThru
        
        # Robocopy returns exit codes 0-7 for success; 8+ indicates a failure.
        if ($robocopyResult.ExitCode -gt 7) {
            throw "Robocopy failed with exit code $($robocopyResult.ExitCode)"
        }
    }
    else {
        # Compute destination only when needed
        $destination = Join-Path -Path $WorkspacePath -ChildPath $wimFile
        Copy-Item -Path $WimPath -Destination $destination -Force
    }
}