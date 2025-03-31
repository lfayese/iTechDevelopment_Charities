function Test-ValidPowerShellVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )
    
    # Get the module configuration
    $config = Get-ModuleConfiguration
    
    # Validate version format (should be X.Y.Z)
    if (-not ($Version -match '^\d+\.\d+\.\d+$')) {
        Write-OSDCloudLog -Message "Invalid PowerShell version format: $Version. Must be in X.Y.Z format." -Level Warning -Component "Test-ValidPowerShellVersion"
        return $false
    }
    
    # Check if version is in allowed list
    $isValid = $config.PowerShellVersions.Supported -contains $Version
    
    if (-not $isValid) {
        Write-OSDCloudLog -Message "PowerShell version $Version is not in the supported versions list." -Level Warning -Component "Test-ValidPowerShellVersion"
    }
    
    return $isValid
}

# Export the function
Export-ModuleMember -Function Test-ValidPowerShellVersion