function Initialize-OSDCloudTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TempPath
    )
    
    Write-Host "Creating OSDCloud template and workspace..." -ForeColor Cyan
    
    # Step 1: Create a new OSDCloud template
    $templateName = "CustomWIM"
    try {
        New-OSDCloudTemplate -Name $templateName -Verbose
    } catch {
        Write-Error "Failed to create OSDCloud template: $_"
        throw "Failed to create OSDCloud template: $_"
    }
    
    # Step 2: Create a new OSDCloud workspace
    try {
        $workspacePath = Join-Path $TempPath "OSDCloudWorkspace"
        New-OSDCloudWorkspace -WorkspacePath $workspacePath -Verbose
    } catch {
        Write-Error "Failed to create OSDCloud workspace: $_"
        throw "Failed to create OSDCloud workspace: $_"
    }
    
    Write-Host "OSDCloud template and workspace created successfully" -ForeColor Green
    return $workspacePath
}