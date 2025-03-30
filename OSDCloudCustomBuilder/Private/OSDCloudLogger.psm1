<#
.SYNOPSIS
    OSDCloud Logger PowerShell Module
.DESCRIPTION
    This module provides centralized logging and error handling for OSDCloud deployment scripts
.NOTES
    Created for: Charity OSDCloud Deployment
    Author: iTech Development
    Date: March 30, 2025
#>

# Get the directory where this script is located
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Dot source the functions
. "$scriptPath\OSDCloudLogger.ps1"

# Initialize logging with default settings
Initialize-OSDCloudLogger -LogDirectory "$env:TEMP\OSDCloud\Logs" -Level "Info"

# Export the functions
Export-ModuleMember -Function Initialize-OSDCloudLogger, Write-OSDCloudLog, Write-OSDCloudError, 
                              Invoke-OSDCloudErrorRecovery, Get-OSDCloudErrorSummary, Test-OSDCloudDependency