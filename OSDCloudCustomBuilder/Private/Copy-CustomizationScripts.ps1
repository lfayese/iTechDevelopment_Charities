function Get-PWsh7WrappedContent {
    param (
        [Parameter(Mandatory = $true)]
        [string]$OriginalContent
    )
    $wrapper = @"
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
$OriginalContent
"@
    return $wrapper
}
function Copy-CustomizationScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath,
        [Parameter(Mandatory = $true)]
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
                # Copy to OSDCloud directory and Automate directory
                $destinations = @(
                    Join-Path $scriptDestinationPath $script,
                    Join-Path $automateScriptDestinationPath $script
                )
                # Get the original content once
                $origContent = Get-Content -Path $sourcePath -Raw
                $wrappedContent = Get-PWsh7WrappedContent -OriginalContent $origContent
                foreach ($dest in $destinations) {
                    Copy-Item -Path $sourcePath -Destination $dest -Force
                    # Overwrite the script with the wrapped content
                    $wrappedContent | Out-File -FilePath $dest -Encoding utf8 -Force
                }
                Write-Host "Copied and updated $script" -ForeColor Green
            }
            else {
                Write-Warning "Script not found: $sourcePath"
            }
        }
        # Create Autopilot directory structure
        Write-Host "Setting up Autopilot directory structure..." -ForeColor Cyan
        $autopilotSourceDir = Join-Path $ScriptPath "Autopilot"
        $autopilotDestDir = Join-Path $scriptDestinationPath "Autopilot"
        $automateAutopilotDestDir = Join-Path $automateScriptDestinationPath "Autopilot"
        foreach ($dir in @($autopilotDestDir, $automateAutopilotDestDir)) {
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
        }
        # Copy Autopilot files
        if (Test-Path $autopilotSourceDir) {
            $autopilotFiles = Get-ChildItem -Path $autopilotSourceDir -File
            foreach ($file in $autopilotFiles) {
                $destinations = @(
                    Join-Path $autopilotDestDir $file.Name,
                    Join-Path $automateAutopilotDestDir $file.Name
                )
                foreach ($dest in $destinations) {
                    Copy-Item -Path $file.FullName -Destination $dest -Force
                }
                # If the file is a PowerShell script then update it
                if ($file.Extension -eq ".ps1") {
                    $origContent = Get-Content -Path $file.FullName -Raw
                    $wrappedContent = Get-PWsh7WrappedContent -OriginalContent $origContent
                    foreach ($dest in $destinations) {
                        $wrappedContent | Out-File -FilePath $dest -Encoding utf8 -Force
                    }
                }
                Write-Host "Copied Autopilot file: $($file.Name)" -ForeColor Green
            }
        }
        else {
            Write-Warning "Autopilot directory not found: $autopilotSourceDir"
        }
        # Copy additional Autopilot files
        $additionalFiles = @(
            "Autopilot_Upload.7z",
            "7za.exe"
        )
        foreach ($file in $additionalFiles) {
            $sourcePath = Join-Path $ScriptPath $file
            if (Test-Path $sourcePath) {
                $destinations = @(
                    Join-Path $scriptDestinationPath $file,
                    Join-Path $automateScriptDestinationPath $file
                )
                foreach ($dest in $destinations) {
                    Copy-Item -Path $sourcePath -Destination $dest -Force
                }
                Write-Host "Copied $file" -ForeColor Green
            }
            else {
                Write-Warning "Autopilot file not found: $sourcePath. Autopilot functionality may be limited."
            }
        }
        # Create a startup script to launch the iDCMDM UI
        Write-Host "Creating startup script..." -ForeColor Cyan
        $startupPath = Join-Path $WorkspacePath "Startup"
        if (-not (Test-Path $startupPath)) {
            New-Item -Path $startupPath -ItemType Directory -Force | Out-Null
        }
        # Instead of scanning the entire X:\ drive, assume iDCMDMUI.ps1 exists in the OSDCloud directory.
        $potentialScriptPath = Join-Path $scriptDestinationPath "iDCMDMUI.ps1"
        $startupScriptContent = @"
# OSDCloud Startup Script
Write-Host "Starting iDCMDM OSDCloud..." -ForeColor Cyan
if (Test-Path -Path 'X:\Program Files\PowerShell\7\pwsh.exe') {
    Write-Host "Using PowerShell 7..." -ForeColor Green
    if (Test-Path '$potentialScriptPath') {
        Start-Process 'X:\Program Files\PowerShell\7\pwsh.exe' -ArgumentList "-NoL -ExecutionPolicy Bypass -File `"$potentialScriptPath`"" -Wait
    }
    else {
        Write-Warning "iDCMDMUI.ps1 not found at $potentialScriptPath"
    }
}
else {
    Write-Host "Using PowerShell 5..." -ForeColor Yellow
    if (Test-Path '$potentialScriptPath') {
        Start-Process PowerShell -ArgumentList "-NoL -ExecutionPolicy Bypass -File `"$potentialScriptPath`"" -Wait
    }
    else {
        Write-Warning "iDCMDMUI.ps1 not found at $potentialScriptPath"
    }
}
"@
        $startupScriptPath = Join-Path $startupPath "StartOSDCloud.ps1"
        $startupScriptContent | Out-File -FilePath $startupScriptPath -Encoding utf8 -Force
        Write-Host "Customization scripts setup completed" -ForeColor Green
    }
    catch {
        Write-Error "Failed to copy customization scripts: $_"
        throw "Failed to copy customization scripts: $_"
    }
}