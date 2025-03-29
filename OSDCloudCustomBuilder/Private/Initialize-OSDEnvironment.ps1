function Initialize-OSDEnvironment {
    Write-Verbose "Initializing OSDCloud build environment..."
    
    $global:BuildRoot = Join-Path $env:TEMP "OSDCloudBuilder"
    if (!(Test-Path $BuildRoot)) {
        New-Item -ItemType Directory -Path $BuildRoot | Out-Null
    }

    Write-Verbose "Build path: $BuildRoot"
}
