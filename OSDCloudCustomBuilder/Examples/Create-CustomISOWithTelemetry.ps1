<#
.SYNOPSIS
    Creates a custom OSDCloud ISO with PowerShell 7 and telemetry enabled.
.DESCRIPTION
    This example script demonstrates how to create a custom OSDCloud ISO with 
    PowerShell 7 integration and telemetry enabled. It shows the full workflow
    from initialization to final ISO creation with proper logging and telemetry.
.NOTES
    Run this script with administrator privileges.
#>

# Import required modules
Import-Module OSDCloudCustomBuilder -Force

# Set telemetry with detailed logging to help identify issues
Write-Host "Configuring telemetry for detailed operation logging..." -ForegroundColor Cyan
Set-OSDCloudTelemetry -Enable $true -DetailLevel Detailed

# Define paths and filenames
$customWimPath = "D:\WimFiles\custom.wim"
$isoOutputPath = "D:\ISO"
$isoName = "OSDCloud_PowerShell7_$(Get-Date -Format 'yyyyMMdd').iso"

# Measure the entire process
Measure-OSDCloudOperation -Name "Full ISO Creation Process" -ScriptBlock {
    try {
        # Step 1: Update the custom WIM with PowerShell 7
        Write-Host "Updating custom WIM with PowerShell 7..." -ForegroundColor Cyan
        $wimResult = Update-CustomWimWithPwsh7 -WimFile $customWimPath -Verbose
        
        if (-not $wimResult) {
            throw "Failed to update WIM file with PowerShell 7"
        }
        
        # Step 2: Create a custom OSDCloud ISO with the updated WIM
        Write-Host "Creating custom OSDCloud ISO..." -ForegroundColor Cyan
        $isoParams = @{
            WimFile = $customWimPath
            OutputFolder = $isoOutputPath
            IsoFileName = $isoName
            Verbose = $true
        }
        
        $isoResult = New-CustomOSDCloudISO @isoParams
        
        if (-not $isoResult) {
            throw "Failed to create custom ISO"
        }
        
        Write-Host "Custom OSDCloud ISO created successfully!" -ForegroundColor Green
        Write-Host "ISO Location: $isoOutputPath\$isoName" -ForegroundColor Green
    }
    catch {
        Write-Error "Error creating custom OSDCloud ISO: $_"
        throw
    }
}

# Show telemetry data location
$config = Get-ModuleConfiguration
if ($config.Telemetry -and $config.Telemetry.StoragePath) {
    Write-Host "Telemetry data saved to: $($config.Telemetry.StoragePath)" -ForegroundColor Cyan
    Write-Host "You can analyze this data to identify performance issues or errors." -ForegroundColor Cyan
}