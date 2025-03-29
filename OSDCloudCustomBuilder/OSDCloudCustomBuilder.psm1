# Import private functions
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" | ForEach-Object {
    . $_.FullName
}

# Import public functions
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" | ForEach-Object {
    . $_.FullName
}

# Export public functions
Export-ModuleMember -Function @(
    'Add-CustomWimWithPwsh7',
    'New-CustomOSDCloudISO'
)