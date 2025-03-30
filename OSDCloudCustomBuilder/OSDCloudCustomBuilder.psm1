# Set strict mode to catch common issues
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import private functions first
$PrivateFunctions = @()
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Write-Verbose "Importing private function: $($_.FullName)"
        . $_.FullName
        $PrivateFunctions += $_.BaseName
    }
    catch {
        Write-Error "Failed to import private function $($_.FullName): $_"
    }
}

# Import public functions
$PublicFunctions = @()
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Write-Verbose "Importing public function: $($_.FullName)"
        . $_.FullName
        $PublicFunctions += $_.BaseName
    }
    catch {
        Write-Error "Failed to import public function $($_.FullName): $_"
    }
}

# Verify required helper functions exist
$RequiredHelpers = @(
    'Copy-CustomWimToWorkspace',
    'Customize-WinPEWithPowerShell7',
    'Optimize-ISOSize',
    'New-CustomISO',
    'Show-Summary'
)

$MissingHelpers = $RequiredHelpers | Where-Object { $_ -notin $PrivateFunctions -and $_ -notin $PublicFunctions }
if ($MissingHelpers.Count -gt 0) {
    Write-Warning "Missing required helper functions: $($MissingHelpers -join ', ')"
}

# Export only public functions listed in the module manifest
# This ensures consistency between the .psd1 and .psm1 files
$ManifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'OSDCloudCustomBuilder.psd1'
if (Test-Path -Path $ManifestPath) {
    $Manifest = Import-PowerShellDataFile -Path $ManifestPath
    $ExportFunctions = $Manifest.FunctionsToExport
    Export-ModuleMember -Function $ExportFunctions
}
else {
    # Fall back to hardcoded list if manifest can't be loaded
    Export-ModuleMember -Function @(
        'Add-CustomWimWithPwsh7',
        'New-CustomOSDCloudISO'
    )
}