function Get-PowerShell7Package {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateScript({
            if (Test-ValidPowerShellVersion -Version $_) { 
                return $true 
            }
            throw "Invalid PowerShell version format. Must be in X.Y.Z format and be a supported version."
        })]
        [string]$Version = "7.3.4",
        
        [Parameter(Mandatory = $true)]
        [string]$DownloadPath
    )
    
    # Get module configuration
    $config = Get-ModuleConfiguration
    
    # Check for cached package first
    $cachedPackage = Get-CachedPowerShellPackage -Version $Version
    if ($cachedPackage) {
        return $cachedPackage
    }
    
    # Verify version has a corresponding hash
    if (-not $config.PowerShellVersions.Hashes.ContainsKey($Version)) {
        $errorMessage = "PowerShell version $Version is not in the verified versions list. Please use a verified version or update the module."
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Get-PowerShell7Package"
        throw $errorMessage
    }
    
    $expectedHash = $config.PowerShellVersions.Hashes[$Version]
    $downloadUrl = $config.DownloadSources.PowerShell -f $Version
    
    try {
        # Set TLS 1.2 for secure downloads
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Create directory if it doesn't exist
        $downloadDir = Split-Path -Path $DownloadPath -Parent
        if (-not (Test-Path -Path $downloadDir)) {
            New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null
        }
        
        Write-OSDCloudLog -Message "Downloading PowerShell $Version from $downloadUrl" -Level Info -Component "Get-PowerShell7Package"
        
        # Download the file
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($downloadUrl, $DownloadPath)
        
        # Verify hash
        $actualHash = (Get-FileHash -Path $DownloadPath -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            Remove-Item -Path $DownloadPath -Force -ErrorAction SilentlyContinue
            $errorMessage = "Hash verification failed for PowerShell $Version package. Expected: $expectedHash, Got: $actualHash"
            Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Get-PowerShell7Package"
            throw $errorMessage
        }
        
        Write-OSDCloudLog -Message "PowerShell $Version downloaded and verified successfully" -Level Info -Component "Get-PowerShell7Package"
        
        # Cache the package for future use
        $cacheRoot = $config.Paths.Cache
        $cachedPackagePath = Join-Path -Path $cacheRoot -ChildPath "PowerShell-$Version-win-x64.zip"
        
        if (-not (Test-Path -Path $cacheRoot)) {
            New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null
        }
        
        Copy-Item -Path $DownloadPath -Destination $cachedPackagePath -Force
        Write-OSDCloudLog -Message "Cached PowerShell $Version package to $cachedPackagePath" -Level Info -Component "Get-PowerShell7Package"
        
        return $DownloadPath
    }
    catch {
        $errorMessage = "Failed to download or verify PowerShell $Version package: $_"
        Write-OSDCloudLog -Message $errorMessage -Level Error -Component "Get-PowerShell7Package" -Exception $_.Exception
        throw $errorMessage
    }
}

# Export the function
Export-ModuleMember -Function Get-PowerShell7Package