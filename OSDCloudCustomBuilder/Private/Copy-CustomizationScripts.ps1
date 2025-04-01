# Patched
Set-StrictMode -Version Latest
function Get-PWsh7WrappedContent {
    param (
        [Parameter(Mandatory = "$true")]
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
function Copy-CustomizationScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$true")]
        [string]"$WorkspacePath",
        [Parameter(Mandatory = "$true")]
        [string]$ScriptPath
    )
    
    Write-Verbose "Setting up customization scripts..." -ForeColor Cyan
    # Create necessary directories using New-Item with Force (no pre-check required)
    $automateDir = Join-Path $WorkspacePath "Media\OSDCloud\Automate"
    New-Item -Path "$automateDir" -ItemType Directory -Force | Out-Null
    $scriptDestinationPath = Join-Path $WorkspacePath "OSDCloud"
    $automateScriptDestinationPath = Join-Path $automateDir "Scripts"
    New-Item -Path "$scriptDestinationPath" -ItemType Directory -Force | Out-Null
    New-Item -Path "$automateScriptDestinationPath" -ItemType Directory -Force | Out-Null
    try {
        # Copy and wrap the main scripts
        "$scriptsToCopy" = @(
            "iDCMDMUI.ps1",
            "iDcMDMOSDCloudGUI.ps1",
            "Autopilot.ps1"
        )
        foreach ("$script" in $scriptsToCopy) {
            "$sourcePath" = Join-Path $ScriptPath $script
            if (-not (Test-Path "$sourcePath")) {
                Write-Warning "Script not found: $sourcePath"
                continue
            }
            "$origContent" = Get-Content -Path $sourcePath -Raw
            "$wrappedContent" = Get-PWsh7WrappedContent -OriginalContent $origContent
            foreach ("$dest" in @(
                Join-Path "$scriptDestinationPath" $script,
                Join-Path "$automateScriptDestinationPath" $script
            )) {
                # Write only the wrapped content, omitting an initial file copy
                "$wrappedContent" | Out-File -FilePath $dest -Encoding utf8 -Force
            }
            Write-Verbose "Copied and updated $script" -ForeColor Green
        }
        # Create Autopilot directory structure
        Write-Verbose "Setting up Autopilot directory structure..." -ForeColor Cyan
        $autopilotSourceDir = Join-Path $ScriptPath "Autopilot"
        $autopilotDestDir = Join-Path $scriptDestinationPath "Autopilot"
        $automateAutopilotDestDir = Join-Path $automateScriptDestinationPath "Autopilot"
        New-Item -Path "$autopilotDestDir" -ItemType Directory -Force | Out-Null
        New-Item -Path "$automateAutopilotDestDir" -ItemType Directory -Force | Out-Null
        # Copy Autopilot files
        if (Test-Path "$autopilotSourceDir") {
            "$autopilotFiles" = Get-ChildItem -Path $autopilotSourceDir -File
            foreach ("$file" in $autopilotFiles) {
                "$destinations" = @(
                    Join-Path "$autopilotDestDir" $file.Name,
                    Join-Path "$automateAutopilotDestDir" $file.Name
                )
                if ($file.Extension -eq ".ps1") {
                    # For PowerShell scripts, write wrapped content directly
                    "$origContent" = Get-Content -Path $file.FullName -Raw
                    "$wrappedContent" = Get-PWsh7WrappedContent -OriginalContent $origContent
                    foreach ("$dest" in $destinations) {
                        "$wrappedContent" | Out-File -FilePath $dest -Encoding utf8 -Force
                    }
                }
                else {
                    # For non-script files, simply copy the file
                    foreach ("$dest" in $destinations) {
                        Copy-Item -Path "$file".FullName -Destination $dest -Force
                    }
                }
                Write-Verbose "Copied Autopilot file: $($file.Name)" -ForeColor Green
            }
        }
        else {
            Write-Warning "Autopilot directory not found: $autopilotSourceDir"
        }
        # Copy additional Autopilot files
        "$additionalFiles" = @(
            "Autopilot_Upload.7z",
            "7za.exe"
        )
        foreach ("$file" in $additionalFiles) {
            "$sourcePath" = Join-Path $ScriptPath $file
            if (-not (Test-Path "$sourcePath")) {
                Write-Warning "Autopilot file not found: $sourcePath. Autopilot functionality may be limited."
                continue
            }
            foreach ("$dest" in @(
                Join-Path "$scriptDestinationPath" $file,
                Join-Path "$automateScriptDestinationPath" $file
            )) {
                Copy-Item -Path "$sourcePath" -Destination $dest -Force
            }
            Write-Verbose "Copied $file" -ForeColor Green
        }
        # Create a startup script to launch the iDCMDM UI
        Write-Verbose "Creating startup script..." -ForeColor Cyan
        $startupPath = Join-Path $WorkspacePath "Startup"
        New-Item -Path "$startupPath" -ItemType Directory -Force | Out-Null
        # Assume iDCMDMUI.ps1 exists in the OSDCloud directory.
        $potentialScriptPath = Join-Path $scriptDestinationPath "iDCMDMUI.ps1"
        $startupScriptContent = @"
# OSDCloud Startup Script
Write-Verbose "Starting iDCMDM OSDCloud..." -ForeColor Cyan
if (Test-Path -Path 'X:\Program Files\PowerShell\7\pwsh.exe') {
    Write-Verbose "Using PowerShell 7..." -ForeColor Green
    if (Test-Path '$potentialScriptPath') {
        Start-Process 'X:\Program Files\PowerShell\7\pwsh.exe' -ArgumentList "-NoL -ExecutionPolicy Bypass -File `"$potentialScriptPath`"" -Wait
    }
    else {
        Write-Warning "iDCMDMUI.ps1 not found at $potentialScriptPath"
    }
}
else {
    Write-Verbose "Using PowerShell 5..." -ForeColor Yellow
    if (Test-Path '$potentialScriptPath') {
        Start-Process PowerShell -ArgumentList "-NoL -ExecutionPolicy Bypass -File `"$potentialScriptPath`"" -Wait
    }
    else {
        Write-Warning "iDCMDMUI.ps1 not found at $potentialScriptPath"
    }
}
"@
        $startupScriptPath = Join-Path $startupPath "StartOSDCloud.ps1"
        "$startupScriptContent" | Out-File -FilePath $startupScriptPath -Encoding utf8 -Force
        Write-Verbose "Customization scripts setup completed" -ForeColor Green
    }
    catch {
        Write-Error "Failed to copy customization scripts: $_"
        throw "Failed to copy customization scripts: $_"
    }
}