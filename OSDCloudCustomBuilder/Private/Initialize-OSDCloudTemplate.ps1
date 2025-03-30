function Initialize-OSDCloudTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath
    )
    
    Write-Host "Creating OSDCloud workspace..." -ForeColor Cyan
    
    # Try to create the workspace
    try {
        New-OSDCloudWorkspace -WorkspacePath $WorkspacePath
    }
    catch {
        Write-Warning "Failed to create workspace using custom template, trying default..."
        try {
            New-OSDCloudWorkspace -WorkspacePath $WorkspacePath
            Write-Host "Workspace created using default template" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to create workspace: $_"
            throw "Workspace creation failed"
        }
    }
    
    Write-Host "OSDCloud workspace created successfully" -ForeColor Green
    return $WorkspacePath
}