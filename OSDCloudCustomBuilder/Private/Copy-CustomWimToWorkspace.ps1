# You'll need to modify Copy-CustomWimToWorkspace to support robocopy
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
    
    $destination = Join-Path -Path $WorkspacePath -ChildPath (Split-Path -Path $WimPath -Leaf)
    
    if ($UseRobocopy -and (Get-Command "robocopy.exe" -ErrorAction SilentlyContinue)) {
        $sourceDir = Split-Path -Path $WimPath -Parent
        $sourceFile = Split-Path -Path $WimPath -Leaf
        $destDir = $WorkspacePath
        
        # Use robocopy for faster copying of large files
        # /J = copy using unbuffered I/O (faster for large files)
        # /MT = multithreaded copying
        $robocopyParams = @(
            "`"$sourceDir`"",
            "`"$destDir`"",
            "`"$sourceFile`"",
            "/J",
            "/MT:8"
        )
        
        $robocopyResult = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyParams -NoNewWindow -Wait -PassThru
        
        # Robocopy has special exit codes
        # 0-7 are success codes, 8+ are failure codes
        if ($robocopyResult.ExitCode -gt 7) {
            throw "Robocopy failed with exit code $($robocopyResult.ExitCode)"
        }
    }
    else {
        # Fall back to Copy-Item if robocopy is not available
        Copy-Item -Path $WimPath -Destination $destination -Force
    }
}