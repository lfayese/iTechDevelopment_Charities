# Patched
Set-StrictMode -Version Latest
function Copy-CustomWimToWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [string]"$WimPath",
        [Parameter(Mandatory = "$true")]
        [string]"$WorkspacePath",
        [Parameter(Mandatory = "$false")]
        [switch]$UseRobocopy
    )
    
    begin {
        try {
            # Validate WimPath to prevent path traversal and ensure it exists
            try {
                $validatedWimPath = [System.IO.Path]::GetFullPath($WimPath)
                if (-not (Test-Path -Path $validatedWimPath -PathType Leaf)) {
                    throw "WIM file not found: $WimPath"
                }
                $WimPath = $validatedWimPath
            } catch {
                throw "WimPath validation failed: $_"
            }
            
            # Validate WorkspacePath to prevent path traversal and ensure it exists
            try {
                $validatedWorkspacePath = [System.IO.Path]::GetFullPath($WorkspacePath)
                if (-not (Test-Path -Path $validatedWorkspacePath -PathType Container)) {
                    throw "Workspace directory not found: $WorkspacePath"
                }
                $WorkspacePath = $validatedWorkspacePath
            } catch {
                throw "WorkspacePath validation failed: $_"
            }
            
            # Initialize logging
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "Starting WIM copy from $WimPath to $WorkspacePath" -Level Info -Component "Copy-CustomWimToWorkspace"
            }
        } catch {
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "Error in Copy-CustomWimToWorkspace initialization: $_" -Level Error -Component "Copy-CustomWimToWorkspace" -Exception $_.Exception
            }
            throw
        }
    }
    
    process {
        try {
            # Cache the split path results to avoid redundant calls
            $wimFile = Split-Path -Path $WimPath -Leaf
            $wimDir = Split-Path -Path $WimPath -Parent
            
            if ($UseRobocopy -and (Get-Command "robocopy.exe" -ErrorAction SilentlyContinue)) {
                # Use robocopy for faster copying of large files
                # Properly escape parameters to prevent command injection
                $safeWimDir = $wimDir.Replace('"', '\"')
                $safeWorkspacePath = $WorkspacePath.Replace('"', '\"')
                $safeWimFile = $wimFile.Replace('"', '\"')
                
                # Use Start-Process with properly constructed ArgumentList
                $robocopyArgs = @(
                    "`"$safeWimDir`"",
                    "`"$safeWorkspacePath`"",
                    "`"$safeWimFile`"",
                    "/J",
                    "/MT:8"
                )
                
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "Using Robocopy for file transfer" -Level Info -Component "Copy-CustomWimToWorkspace"
                }
                
                $robocopyProcess = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
                
                # Robocopy returns exit codes 0-7 for success; 8+ indicates a failure.
                if ($robocopyProcess.ExitCode -gt 7) {
                    throw "Robocopy failed with exit code $($robocopyProcess.ExitCode)"
                }
            }
            else {
                # Compute destination only when needed
                $destination = Join-Path -Path $WorkspacePath -ChildPath $wimFile
                
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "Using PowerShell Copy-Item for file transfer" -Level Info -Component "Copy-CustomWimToWorkspace"
                }
                
                Copy-Item -Path "$WimPath" -Destination $destination -Force
            }
            
            # Log completion
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "WIM copy completed successfully" -Level Info -Component "Copy-CustomWimToWorkspace"
            }
        } catch {
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "Error copying WIM file: $_" -Level Error -Component "Copy-CustomWimToWorkspace" -Exception $_.Exception
            }
            throw
        }
    }
}