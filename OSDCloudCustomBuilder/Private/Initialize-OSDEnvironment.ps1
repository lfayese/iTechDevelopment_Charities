function Initialize-OSDEnvironment {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$BuildPath = (Join-Path $env:TEMP "OSDCloudBuilder")
    )
    try {
        Write-OSDCloudLog -Message "Initializing OSDCloud build environment..." -Level Info -Component "Initialize-OSDEnvironment"
        # Set the global build root variable
        $global:BuildRoot = $BuildPath
        # Check if the build directory exists.
        $dirExists = Test-Path -Path $BuildPath -PathType Container
        # Create the build directory if it doesn't exist and if ShouldProcess approves.
        if (-not $dirExists -and $PSCmdlet.ShouldProcess($BuildPath, "Create directory")) {
            Write-OSDCloudLog -Message "Creating build directory: $BuildPath" -Level Info -Component "Initialize-OSDEnvironment"
            New-Item -ItemType Directory -Path $BuildPath -Force -ErrorAction Stop | Out-Null
            $dirExists = Test-Path -Path $BuildPath -PathType Container
        }
        
        # Verify the directory was created successfully.
        if ($dirExists) {
            Write-OSDCloudLog -Message "Build environment initialized successfully at: $BuildPath" -Level Info -Component "Initialize-OSDEnvironment"
            return $true
        }
        else {
            throw "Failed to verify build directory creation"
        }
    }
    catch {
        Write-OSDCloudLog -Message "Failed to initialize OSDCloud environment: $_" -Level Error -Component "Initialize-OSDEnvironment" -Exception $_.Exception
        throw
    }
}