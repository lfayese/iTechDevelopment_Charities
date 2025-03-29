function Copy-CustomizationScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$WorkspacePath,
        
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath
    )
    
    Write-Host "Setting up customization scripts..." -ForeColor Cyan
    
    # Create Automate directory structure
    $automateDir = Join-Path $WorkspacePath "Media\OSDCloud\Automate"
    if (-not (Test-Path $automateDir)) {
        New-Item -Path $automateDir -ItemType Directory -Force | Out-Null
    }
    
    # Define script destinations
    $scriptDestinationPath = Join-Path $WorkspacePath "OSDCloud"
    $automateScriptDestinationPath = Join-Path $automateDir "Scripts"
    
    if (-not (Test-Path $automateScriptDestinationPath)) {
        New-Item -Path $automateScriptDestinationPath -ItemType Directory -Force | Out-Null
    }
    
    try {
        # Copy the main scripts
        $scriptsToCopy = @(
            "iDCMDMUI.ps1",
            "iDcMDMOSDCloudGUI.ps1",
            "Autopilot.ps1"
        )
        
        foreach ($script in $scriptsToCopy) {
            $sourcePath = Join-Path $ScriptPath $script
            if (Test-Path $sourcePath) {
                # Copy to OSDCloud directory
                Copy-Item -Path $sourcePath -Destination (Join-Path $scriptDestinationPath $script) -Force
                
                # Also copy to Automate directory
                Copy-Item -Path $sourcePath -Destination (Join-Path $automateScriptDestinationPath $script) -Force
                
                # Update script to prefer PowerShell 7
                $scriptContent = Get-Content -Path $sourcePath -Raw
                $pwsh7Wrapper = @"
# PowerShell 7 wrapper
try {
    # Check if PowerShell 7 is available
    if (Test-Path -Path 'X:\Program Files\PowerShell\7\pwsh.exe') {
        # Execute the script in PowerShell 7
        & 'X:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -ExecutionPolicy Bypass -File `$PSCommandPath
        exit `$LASTEXITCODE
    }
} catch {
    Write-Warning "Failed to run with PowerShell 7, falling back to PowerShell 5: `$_"
    # Continue with PowerShell 5
}

# Original script content follows
$scriptContent
"@
                $pwsh7Wrapper | Out-File -FilePath (Join-Path $scriptDestinationPath $script) -Encoding utf8 -Force
                $pwsh7Wrapper | Out-File -FilePath (Join-Path $automateScriptDestinationPath $script) -Encoding utf8 -Force
                
                Write-Host "Copied and updated $script" -ForeColor Green
            } else {
                Write-Warning "Script not found: $sourcePath"
            }
        }
        
        # Create Autopilot directory structure
        Write-Host "Setting up Autopilot directory structure..." -ForeColor Cyan
        $autopilotSourceDir = Join-Path $ScriptPath "Autopilot"
        $autopilotDestDir = Join-Path $scriptDestinationPath "Autopilot"
        $automateAutopilotDestDir = Join-Path $automateScriptDestinationPath "Autopilot"
        
        if (-not (Test-Path $autopilotDestDir)) {
            New-Item -Path $autopilotDestDir -ItemType Directory -Force | Out-Null
        }
        
        if (-not (Test-Path $automateAutopilotDestDir)) {
            New-Item -Path $automateAutopilotDestDir -ItemType Directory -Force | Out-Null
        }
        
        # Copy Autopilot files
        if (Test-Path $autopilotSourceDir) {
            # Copy all files from Autopilot directory
            $autopilotFiles = Get-ChildItem -Path $autopilotSourceDir -File
            
            foreach ($file in $autopilotFiles) {
                # Copy to OSDCloud directory
                Copy-Item -Path $file.FullName -Destination (Join-Path $autopilotDestDir $file.Name) -Force
                
                # Also copy to Automate directory
                Copy-Item -Path $file.FullName -Destination (Join-Path $automateAutopilotDestDir $file.Name) -Force
                
                # Update PowerShell scripts to prefer PowerShell 7
                if ($file.Extension -eq ".ps1") {
                    $scriptContent = Get-Content -Path $file.FullName -Raw
                    $pwsh7Wrapper = @"
# PowerShell 7 wrapper
try {
    # Check if PowerShell 7 is available
    if (Test-Path -Path 'X:\Program Files\PowerShell\7\pwsh.exe') {
        # Execute the script in PowerShell 7
        & 'X:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -ExecutionPolicy Bypass -File `$PSCommandPath
        exit `$LASTEXITCODE
    }
} catch {
    Write-Warning "Failed to run with PowerShell 7, falling back to PowerShell 5: $_"
    # Continue with PowerShell 5
}

# Original script content follows
$scriptContent
"@
                    $pwsh7Wrapper | Out-File -FilePath (Join-Path $autopilotDestDir $file.Name) -Encoding utf8 -Force
                    $pwsh7Wrapper | Out-File -FilePath (Join-Path $automateAutopilotDestDir $file.Name) -Encoding utf8 -Force
                }
                
                Write-Host "Copied Autopilot file: $($file.Name)" -ForeColor Green
            }
        } else {
            Write-Warning "Autopilot directory not found: $autopilotSourceDir"
        }
        
        # Check for Autopilot_Upload.7z and 7za.exe
        $autopilotFiles = @(
            "Autopilot_Upload.7z",
            "7za.exe"
        )
        
        foreach ($file in $autopilotFiles) {
            $sourcePath = Join-Path $ScriptPath $file
            if (Test-Path $sourcePath) {
                # Copy to OSDCloud directory
                Copy-Item -Path $sourcePath -Destination (Join-Path $scriptDestinationPath $file) -Force
                
                # Also copy to Automate directory
                Copy-Item -Path $sourcePath -Destination (Join-Path $automateScriptDestinationPath $file) -Force
                
                Write-Host "Copied $file" -ForeColor Green
            } else {
                Write-Warning "Autopilot file not found: $sourcePath. Autopilot functionality may be limited."
            }
        }
        
        # Create a startup script to launch the iDCMDM UI
        Write-Host "Creating startup script..." -ForeColor Cyan
        $startupPath = Join-Path $WorkspacePath "Startup"
        if (-not (Test-Path $startupPath)) {
            New-Item -Path $startupPath -ItemType Directory -Force | Out-Null
        }
        
        $startupScriptContent = @"
# OSDCloud Startup Script
Write-Host "Starting iDCMDM OSDCloud..." -ForeColor Cyan

# Try to use PowerShell 7 if available
if (Test-Path -Path 'X:\Program Files\PowerShell\7\pwsh.exe') {
    Write-Host "Using PowerShell 7..." -ForeColor Green
    `$scriptPath = Get-ChildItem -Path 'X:\' -Recurse -Filter 'iDCMDMUI.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (`$scriptPath) {
        Start-Process 'X:\Program Files\PowerShell\7\pwsh.exe' -ArgumentList "-NoL -ExecutionPolicy Bypass -File `$scriptPath" -Wait
    } else {
        Write-Warning "iDCMDMUI.ps1 not found in X:\ drive"
    }
} else {
    Write-Host "Using PowerShell 5..." -ForeColor Yellow
    `$scriptPath = Get-ChildItem -Path 'X:\' -Recurse -Filter 'iDCMDMUI.ps1' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (`$scriptPath) {
        Start-Process PowerShell -ArgumentList "-NoL -ExecutionPolicy Bypass -File `$scriptPath" -Wait
    } else {
        Write-Warning "iDCMDMUI.ps1 not found in X:\ drive"
    }
}
"@
        
        $startupScriptPath = Join-Path $startupPath "StartOSDCloud.ps1"
        $startupScriptContent | Out-File -FilePath $startupScriptPath -Encoding utf8 -Force
        
        Write-Host "Customization scripts setup completed" -ForeColor Green
    } catch {
        Write-Error "Failed to copy customization scripts: $_"
        throw "Failed to copy customization scripts: $_"
    }
}