function New-WorkspaceDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    Write-Host "Creating workspace directory..." -ForeColor Cyan
    
    # Create a temporary directory for our workspace
    $tempWorkspacePath = Join-Path $OutputPath "TempWorkspace"
    if (Test-Path $tempWorkspacePath) {
        Remove-Item -Path $tempWorkspacePath -Recurse -Force
    }
    New-Item -Path $tempWorkspacePath -ItemType Directory -Force | Out-Null
    
    Write-Host "Workspace directory created: $tempWorkspacePath" -ForeColor Green
    return $tempWorkspacePath
}