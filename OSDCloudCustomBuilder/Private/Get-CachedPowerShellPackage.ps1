function Get-CachedPowerShellPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )
    
    # Get module configuration
    $config = Get-ModuleConfiguration
    
    # Define cache location
    $cacheRoot = $config.Paths.Cache
    if (-not (Test-Path -Path $cacheRoot)) {
        New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null
    }
    
    $cachedPackagePath = Join-Path -Path $cacheRoot -ChildPath "PowerShell-$Version-win-x64.zip"
    
    # Check if cached package exists and is valid
    if (Test-Path -Path $cachedPackagePath) {
        # Verify the hash if we have it
        if ($config.PowerShellVersions.Hashes.ContainsKey($Version)) {
            $expectedHash = $config.PowerShellVersions.Hashes[$Version]
            $actualHash = (Get-FileHash -Path $cachedPackagePath -Algorithm SHA256).Hash
            
            if ($actualHash -eq $expectedHash) {
                Write-OSDCloudLog -Message "Using cached PowerShell $Version package from $cachedPackagePath" -Level Info -Component "Get-CachedPowerShellPackage"
                return $cachedPackagePath
            }
            else {
                Write-OSDCloudLog -Message "Cached PowerShell $Version package has invalid hash. Expected: $expectedHash, Got: $actualHash" -Level Warning -Component "Get-CachedPowerShellPackage"
                # Delete the invalid file
                Remove-Item -Path $cachedPackagePath -Force
                return $null
            }
        }
        else {
            # If we don't have a hash, just return the cached file
            Write-OSDCloudLog -Message "Using cached PowerShell $Version package from $cachedPackagePath (hash verification skipped)" -Level Info -Component "Get-CachedPowerShellPackage"
            return $cachedPackagePath
        }
    }
    
    return $null
}

# Export the function
Export-ModuleMember -Function Get-CachedPowerShellPackage