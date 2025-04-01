function Initialize-BuildEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    Write-Host "Initializing build environment..." -ForeColor Cyan
    # Enforce and confirm TLS 1.2 configuration
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Host "TLS 1.2 configured successfully" -ForeColor Green
    } catch {
        Write-Warning "Failed to configure TLS 1.2: $_"
        Write-Warning "Some network operations may fail"
    }
    # Ensure the OSD module is installed and imported
    $osdModule = Get-Module -ListAvailable -Name OSD
    if (-not $osdModule) {
        Write-Host "Installing OSD PowerShell Module..." -ForeColor Cyan
        # Check if PowerShellGet is available
        if (-not (Get-Module -ListAvailable -Name PowerShellGet)) {
            Write-Warning "PowerShellGet module not available. Attempting to use the module without installing..."
        } else {
            try {
                Install-Module OSD -Force -ErrorAction Stop
            } catch {
                Write-Warning "Could not install OSD module: $_"
                Write-Warning "Will attempt to continue without it..."
            }
        }
    }
    # Import the OSD module globally if available
    try {
        $osdModule = Get-Module -ListAvailable -Name OSD
        if ($osdModule) {
            Import-Module OSD -Global -Force -ErrorAction Stop
            Write-Host "OSD module imported successfully" -ForeColor Green
        } else {
            Write-Warning "OSD module not available. Some functionality may be limited."
        }
    } catch {
        Write-Warning "Failed to import OSD module: $_"
        Write-Warning "Continuing without OSD module. Some functionality may be limited."
    }
    # Validate output path
    if (-not (Test-Path $OutputPath -PathType Container)) {
        try {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
            Write-Host "Created output directory: $OutputPath" -ForeColor Green
        } catch {
            Write-Error "Failed to create output directory: $_"
            throw
        }
    }
    # Validate ADK installation
    $ADK_Path = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
    $WinPE_ADK_Path = Join-Path $ADK_Path "Windows Preinstallation Environment"
    $OSCDIMG_Path = Join-Path -Path (Join-Path $ADK_Path "Deployment Tools\amd64") -ChildPath "Oscdimg"
    if (-not (Test-Path $ADK_Path)) {
        Write-Error "ADK Path does not exist. Please install Windows ADK."
        throw "ADK Path does not exist, aborting..."
    }
    if (-not (Test-Path $WinPE_ADK_Path)) {
        Write-Error "WinPE ADK Path does not exist. Please install Windows ADK with WinPE feature."
        throw "WinPE ADK Path does not exist, aborting..."
    }
    if (-not (Test-Path $OSCDIMG_Path)) {
        Write-Error "OSCDIMG Path does not exist. Please install Windows ADK with Deployment Tools feature."
        throw "OSCDIMG Path does not exist, aborting..."
    }
    Write-Host "Build environment initialized successfully" -ForeColor Green
}