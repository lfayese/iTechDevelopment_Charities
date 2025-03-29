function Copy-CustomWimToWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$WimPath,
        
        [Parameter(Mandatory=$true)]
        [string]$WorkspacePath
    )
    
    Write-Host "Copying custom WIM file to workspace..." -ForeColor Cyan
    
    try {
        # Create the OS directory in Media\OSDCloud
        $osDir = Join-Path $WorkspacePath "Media\OSDCloud\OS"
        if (-not (Test-Path $osDir)) {
            New-Item -Path $osDir -ItemType Directory -Force | Out-Null
        }
        
        # Copy the WIM file to the new location using robocopy for better performance
        Copy-WimFileEfficiently -SourcePath $WimPath -DestinationPath "$osDir\CustomImage.wim"
        
        # Also maintain a copy in the OSDCloud directory for backward compatibility
        $osdCloudDir = Join-Path $WorkspacePath "OSDCloud"
        if (-not (Test-Path $osdCloudDir)) {
            New-Item -Path $osdCloudDir -ItemType Directory -Force | Out-Null
        }
        Copy-WimFileEfficiently -SourcePath $WimPath -DestinationPath (Join-Path $osdCloudDir "custom.wim")
        
        Write-Host "Custom WIM file copied successfully" -ForeColor Green
    } catch {
        Write-Error "Failed to copy custom WIM file: $_"
        throw "Failed to copy custom WIM file: $_"
    }
}