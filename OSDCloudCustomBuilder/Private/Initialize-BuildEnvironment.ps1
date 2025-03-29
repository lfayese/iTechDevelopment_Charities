function Initialize-BuildEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    Write-Host "Initializing build environment..." -ForeColor Cyan
    
    # Ensure the OSDCloud module is installed and imported
    if (-not (Get-Module -ListAvailable -Name OSD)) {
        Write-Host "Installing OSD PowerShell Module..." -ForeColor Cyan
        # First check if PowerShellGet is available
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
    
    # Import the OSD module with the -Global parameter if available
    try {
        if (Get-Module -ListAvailable -Name OSD) {
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
    $WinPE_ADK_Path = $ADK_Path + "\Windows Preinstallation Environment"
    $OSCDIMG_Path = $ADK_Path + "\Deployment Tools" + "\amd64\Oscdimg"
    
    if (!(Test-path $ADK_Path)) { 
        Write-Error "ADK Path does not exist. Please install Windows ADK."
        throw "ADK Path does not exist, aborting..."
    }
    
    if (!(Test-path $WinPE_ADK_Path)) { 
        Write-Error "WinPE ADK Path does not exist. Please install Windows ADK with WinPE feature."
        throw "WinPE ADK Path does not exist, aborting..."
    }
    
    if (!(Test-path $OSCDIMG_Path)) { 
        Write-Error "OSCDIMG Path does not exist. Please install Windows ADK with Deployment Tools feature."
        throw "OSCDIMG Path does not exist, aborting..."
    }
    
    Write-Host "Build environment initialized successfully" -ForeColor Green
}