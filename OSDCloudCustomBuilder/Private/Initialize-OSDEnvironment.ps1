<#
.SYNOPSIS
    Initializes the OSDCloud environment for building and customizing images.
.DESCRIPTION
    This function sets up the necessary environment variables and directory structure
    for OSDCloud operations. It creates a build directory if it doesn't exist and
    configures global variables needed by other OSDCloud functions.
.PARAMETER BuildPath
    Optional. Specifies the build directory path. If not provided, defaults to
    "$env:TEMP\OSDCloudBuilder".
.EXAMPLE
    Initialize-OSDEnvironment
    # Initializes the OSDCloud environment with default settings
.EXAMPLE
    Initialize-OSDEnvironment -BuildPath "D:\OSDCloud\Builder"
    # Initializes the OSDCloud environment with a custom build path
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function Initialize-OSDEnvironment {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$BuildPath = (Join-Path $env:TEMP "OSDCloudBuilder")
    )
    
    try {
        Write-OSDCloudLog -Message "Initializing OSDCloud build environment..." -Level Info -Component "Initialize-OSDEnvironment"
        
        # Set the global build root variable
        $global:BuildRoot = $BuildPath
        
        # Create the build directory if it doesn't exist
        if (-not (Test-Path -Path $BuildPath -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($BuildPath, "Create directory")) {
                Write-OSDCloudLog -Message "Creating build directory: $BuildPath" -Level Info -Component "Initialize-OSDEnvironment"
                New-Item -ItemType Directory -Path $BuildPath -Force -ErrorAction Stop | Out-Null
            }
        }
        
        # Verify the directory was created successfully
        if (Test-Path -Path $BuildPath -PathType Container) {
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