# Tests if a given PowerShell version string is valid and supported
<#
.SYNOPSIS
    Validates if a PowerShell version string is in the correct format and is supported.
.DESCRIPTION
    This function checks if a PowerShell version string is in the correct X.Y.Z format
    and is a supported version for WinPE integration. It validates both the format and
    whether the version is in the supported range.
.PARAMETER Version
    The PowerShell version string to validate (e.g., "7.3.4").
.EXAMPLE
    Test-ValidPowerShellVersion -Version "7.3.4"
    # Returns $true if the version is valid and supported
.EXAMPLE
    Test-ValidPowerShellVersion -Version "invalid"
    # Returns $false for an invalid version format
.NOTES
    Version: 1.0.0
    Author: OSDCloud Team
#>
function Test-ValidPowerShellVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,
                  Position=0,
                  HelpMessage="PowerShell version to validate (format: X.Y.Z)")]
        [string]$Version
    )
    
    try {
        # Check if the version is in the correct format (X.Y.Z)
        if (-not ($Version -match '^\d+\.\d+\.\d+$')) {
            Write-OSDCloudLog -Message "Invalid PowerShell version format: $Version. Must be in X.Y.Z format." -Level Warning -Component "Test-ValidPowerShellVersion"
            return $false
        }
        
        # Parse version components
        $versionParts = $Version -split '\.' | ForEach-Object { [int]$_ }
        $major = $versionParts[0]
        $minor = $versionParts[1]
        $patch = $versionParts[2]
        
        # Check if it's PowerShell 7.x
        if ($major -ne 7) {
            Write-OSDCloudLog -Message "Unsupported PowerShell major version: $major. Only PowerShell 7.x is supported." -Level Warning -Component "Test-ValidPowerShellVersion"
            return $false
        }
        
        # Check supported minor versions (adjust as needed)
        $supportedMinorVersions = @(0, 1, 2, 3, 4, 5)
        if ($minor -notin $supportedMinorVersions) {
            Write-OSDCloudLog -Message "Unsupported PowerShell minor version: $Version. Supported versions: 7.0.x, 7.1.x, 7.2.x, 7.3.x, 7.4.x, 7.5.x" -Level Warning -Component "Test-ValidPowerShellVersion"
            return $false
        }
        
        # Additional validation could be added here for specific version compatibility
        
        Write-OSDCloudLog -Message "PowerShell version $Version is valid and supported" -Level Info -Component "Test-ValidPowerShellVersion"
        return $true
    }
    catch {
        Write-OSDCloudLog -Message "Error validating PowerShell version: $_" -Level Error -Component "Test-ValidPowerShellVersion" -Exception $_.Exception
        return $false
    }
}

# Export the function
Export-ModuleMember -Function Test-ValidPowerShellVersion