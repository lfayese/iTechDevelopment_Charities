# Create these PS1 files in the appropriate directories
$requiredFunctions = @{
    'Copy-CustomWimToWorkspace' = 'Private'
    'Copy-WimFileEfficiently' = 'Private'
    'Optimize-ISOSize' = 'Private'
    'New-CustomISO' = 'Private'
    'Show-Summary' = 'Private'
    'Add-CustomWimWithPwsh7' = 'Public'
    'New-CustomOSDCloudISO' = 'Public'
}

foreach ($function in $requiredFunctions.Keys) {
    $dir = Join-Path -Path "/workspaces/iTechDevelopment_Charities/OSDCloudCustomBuilder" -ChildPath $requiredFunctions[$function]
    $path = Join-Path -Path $dir -ChildPath "$function.ps1"
    # Create if doesn't exist
    if (-not (Test-Path $path)) {
        Write-Host "Creating $function in $dir" -ForegroundColor Yellow
    }
}