# Start-OfflineDeployment.ps1
# A tool for offline deployment without internet connectivity

function Start-OfflineDeployment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        [string]$OfflineResourcePath,
        
        [Parameter(Mandatory = $false)]
        [string]$TargetDrive = "C:",
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath = "$env:TEMP\OfflineDeployment",
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigFile = "config.json"
    )
    
    # Create log directory
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Start logging
    $logFile = Join-Path -Path $LogPath -ChildPath "OfflineDeployment_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Start-Transcript -Path $logFile -Force
    
    try {
        # Check if offline resources are available
        Write-Host "Checking offline resources at $OfflineResourcePath..."
        
        $requiredFolders = @(
            "OS", 
            "Drivers", 
            "Applications", 
            "Scripts"
        )
        
        $missingFolders = @()
        foreach ($folder in $requiredFolders) {
            $folderPath = Join-Path -Path $OfflineResourcePath -ChildPath $folder
            if (-not (Test-Path $folderPath)) {
                $missingFolders += $folder
            }
        }
        
        if ($missingFolders.Count -gt 0 -and -not $Force) {
            throw "Missing required folders in offline resources: $($missingFolders -join ', '). Use -Force to continue anyway."
        }
        
        # Load configuration if available
        $configPath = Join-Path -Path $OfflineResourcePath -ChildPath $ConfigFile
        $config = $null
        
        if (Test-Path $configPath) {
            Write-Host "Loading configuration from $configPath..."
            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        }
        else {
            Write-Warning "Configuration file not found. Using default settings."
            
            # Create default configuration
            $config = [PSCustomObject]@{
                OSImageIndex = 1
                ApplyDrivers = $true
                InstallApplications = $true
                RunPostScripts = $true
            }
        }
        
        # Check for OS image
        $osPath = Join-Path -Path $OfflineResourcePath -ChildPath "OS"
        $wimFiles = Get-ChildItem -Path $osPath -Filter "*.wim" -ErrorAction SilentlyContinue
        
        if ($wimFiles.Count -eq 0) {
            throw "No Windows image (WIM) files found in the OS folder."
        }
        
        $selectedWim = $wimFiles[0]
        Write-Host "Using Windows image: $($selectedWim.FullName)"
        
        # Apply OS
        Write-Host "Applying Windows image to $TargetDrive..."
        
        # Get image information
        $imageInfo = Get-WindowsImage -ImagePath $selectedWim.FullName
        
        # Select image index
        $imageIndex = $config.OSImageIndex
        if ($imageIndex -gt $imageInfo.Count) {
            Write-Warning "Specified image index $imageIndex is out of range. Using index 1."
            $imageIndex = 1
        }
        
        # Apply the image
        $applyResult = Expand-WindowsImage -ImagePath $selectedWim.FullName -Index $imageIndex -ApplyPath $TargetDrive -Verify
        
        if (-not $applyResult) {
            throw "Failed to apply Windows image."
        }
        
        # Apply drivers if enabled
        if ($config.ApplyDrivers) {
            $driversPath = Join-Path -Path $OfflineResourcePath -ChildPath "Drivers"
            
            if (Test-Path $driversPath) {
                Write-Host "Applying drivers from $driversPath..."
                
                try {
                    Add-WindowsDriver -Path $TargetDrive -Driver $driversPath -Recurse
                }
                catch {
                    Write-Warning "Error applying drivers: $_"
                }
            }
            else {
                Write-Warning "Drivers folder not found. Skipping driver installation."
            }
        }
        
        # Install applications if enabled
        if ($config.InstallApplications) {
            $appsPath = Join-Path -Path $OfflineResourcePath -ChildPath "Applications"
            
            if (Test-Path $appsPath) {
                Write-Host "Installing applications from $appsPath..."
                
                # Get application installation scripts
                $appScripts = Get-ChildItem -Path $appsPath -Filter "install*.ps1" -Recurse
                
                foreach ($script in $appScripts) {
                    Write-Host "Running application installation script: $($script.Name)"
                    
                    try {
                        # Execute the script with the target drive as parameter
                        & $script.FullName $TargetDrive
                    }
                    catch {
                        Write-Warning "Error running application installation script $($script.Name): $_"
                    }
                }
            }
            else {
                Write-Warning "Applications folder not found. Skipping application installation."
            }
        }
        
        # Run post-deployment scripts if enabled
        if ($config.RunPostScripts) {
            $scriptsPath = Join-Path -Path $OfflineResourcePath -ChildPath "Scripts"
            
            if (Test-Path $scriptsPath) {
                Write-Host "Running post-deployment scripts from $scriptsPath..."
                
                # Get post-deployment scripts
                $postScripts = Get-ChildItem -Path $scriptsPath -Filter "post*.ps1" -Recurse
                
                foreach ($script in $postScripts) {
                    Write-Host "Running post-deployment script: $($script.Name)"
                    
                    try {
                        # Execute the script with the target drive as parameter
                        & $script.FullName $TargetDrive
                    }
                    catch {
                        Write-Warning "Error running post-deployment script $($script.Name): $_"
                    }
                }
            }
            else {
                Write-Warning "Scripts folder not found. Skipping post-deployment scripts."
            }
        }
        
        Write-Host "Offline deployment completed successfully." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Offline deployment failed: $_"
        return $false
    }
    finally {
        # Stop logging
        Stop-Transcript
    }
}

# Export the function
Export-ModuleMember -Function Start-OfflineDeployment