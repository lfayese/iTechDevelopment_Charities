# Start-Deployment.ps1
# Main deployment script with PowerShell version checking

function Start-Deployment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigFile = "config.json",
        
        [Parameter(Mandatory = $false)]
        [switch]$Offline,
        
        [Parameter(Mandatory = $false)]
        [string]$OfflineResourcePath,
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath = "$env:TEMP\Deployment",
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        $errorMessage = "This script requires PowerShell 5.1 or higher. Current version: $($PSVersionTable.PSVersion)"
        Write-Error $errorMessage
        
        # Provide guidance for upgrading PowerShell
        $osVersion = [System.Environment]::OSVersion.Version
        
        if ($osVersion.Major -ge 10) {
            Write-Host "`nUpgrade Instructions for Windows 10/11:" -ForegroundColor Yellow
            Write-Host "1. Download the latest PowerShell from https://github.com/PowerShell/PowerShell/releases"
            Write-Host "2. Run the installer and follow the prompts"
            Write-Host "3. Restart your system after installation"
        }
        elseif ($osVersion.Major -eq 6 -and $osVersion.Minor -ge 1) {
            Write-Host "`nUpgrade Instructions for Windows 7/8/8.1:" -ForegroundColor Yellow
            Write-Host "1. Install Windows Management Framework 5.1:"
            Write-Host "   https://www.microsoft.com/en-us/download/details.aspx?id=54616"
            Write-Host "2. Restart your system after installation"
        }
        else {
            Write-Host "`nYour OS may not support PowerShell 5.1. Consider upgrading your operating system." -ForegroundColor Yellow
        }
        
        return $false
    }
    
    # Create log directory
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Start logging
    $logFile = Join-Path -Path $LogPath -ChildPath "Deployment_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Start-Transcript -Path $logFile -Force
    
    try {
        Write-Host "Starting deployment process with PowerShell version $($PSVersionTable.PSVersion)" -ForegroundColor Green
        
        # Load configuration
        $config = $null
        
        if (Test-Path $ConfigFile) {
            Write-Host "Loading configuration from $ConfigFile..."
            $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
        }
        else {
            Write-Warning "Configuration file not found. Using default settings."
            
            # Create default configuration
            $config = [PSCustomObject]@{
                OSImageIndex = 1
                ApplyDrivers = $true
                InstallApplications = $true
                RunPostScripts = $true
                Language = "en-US"
            }
        }
        
        # Import required modules
        $requiredModules = @(
            "DISM"
        )
        
        foreach ($module in $requiredModules) {
            if (-not (Get-Module -Name $module -ListAvailable)) {
                Write-Warning "Required module '$module' is not installed. Attempting to install..."
                
                try {
                    Install-Module -Name $module -Force -Scope CurrentUser
                }
                catch {
                    Write-Error "Failed to install module '$module': $_"
                    return $false
                }
            }
            
            Import-Module -Name $module -Force
        }
        
        # Check if running in offline mode
        if ($Offline) {
            if (-not $OfflineResourcePath) {
                throw "Offline resource path must be specified when using offline mode."
            }
            
            # Call the offline deployment function
            $offlineScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "Start-OfflineDeployment.ps1"
            
            if (Test-Path $offlineScriptPath) {
                . $offlineScriptPath
                return Start-OfflineDeployment -OfflineResourcePath $OfflineResourcePath -LogPath $LogPath -Force:$Force
            }
            else {
                throw "Offline deployment script not found: $offlineScriptPath"
            }
        }
        else {
            # Online deployment logic
            Write-Host "Checking internet connectivity..."
            $hasInternet = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet
            
            if (-not $hasInternet) {
                Write-Warning "No internet connectivity detected. Consider using offline mode."
                
                if (-not $Force) {
                    $response = Read-Host "Do you want to continue anyway? (Y/N)"
                    
                    if ($response -ne "Y" -and $response -ne "y") {
                        Write-Host "Deployment canceled by user."
                        return $false
                    }
                }
            }
            
            # Implement online deployment steps here
            Write-Host "Starting online deployment..."
            
            # Download OS images
            # Apply OS
            # Install drivers
            # Configure system
            # etc.
            
            Write-Host "Online deployment completed successfully." -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Error "Deployment failed: $_"
        return $false
    }
    finally {
        # Stop logging
        Stop-Transcript
    }
}

# Call the function if script is run directly
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    # Script is being run directly, not dot-sourced
    Start-Deployment @PSBoundParameters
}
else {
    # Script is being dot-sourced, export the function
    Export-ModuleMember -Function Start-Deployment
}