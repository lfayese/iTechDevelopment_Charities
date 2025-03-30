<#
.SYNOPSIS
    Configuration settings for OSDCloud Deployment for Charities
.DESCRIPTION
    This file contains centralized configuration settings for the OSDCloud Deployment solution.
    Modify these settings to customize the behavior of the deployment process.
.NOTES
    Created for: Charity OSDCloud Deployment
    Author: iTech Development
    Date: March 30, 2025
#>

# General settings
$OSDCloudConfig = @{
    # Organization settings
    OrganizationName = "Charity Organization"
    OrganizationContact = "IT Support"
    OrganizationEmail = "support@charity.org"
    
    # Logging settings
    LoggingEnabled = $true
    LogLevel = "Info"  # Debug, Info, Warning, Error, Fatal
    LogRetentionDays = 30
    LogPath = "$env:TEMP\OSDCloud\Logs"
    
    # Default deployment settings
    DefaultOSLanguage = "en-us"
    DefaultOSEdition = "Enterprise"
    DefaultOSLicense = "Volume"
    
    # Recovery settings
    MaxRetryAttempts = 3
    RetryDelaySeconds = 5
    EnableAutoRecovery = $true
    CreateBackups = $true
    
    # Customization settings
    CustomWimSearchPaths = @(
        "X:\OSDCloud\custom.wim",
        "C:\OSDCloud\custom.wim",
        "D:\OSDCloud\custom.wim",
        "E:\OSDCloud\custom.wim"
    )
    
    # PowerShell 7 settings
    PowerShell7Version = "7.3.4"
    PowerShell7Modules = @(
        "OSD",
        "Microsoft.Graph.Intune",
        "WindowsAutopilotIntune"
    )
    
    # Autopilot settings
    AutopilotEnabled = $true
    SkipAutopilotOOBE = $true
    
    # Hardware compatibility settings
    RequireTPM20 = $true
    MinimumCPUGeneration = 8  # For Intel CPUs
    
    # ISO building settings
    ISOOutputPath = "C:\OSDCloud\ISO"
    TempWorkspacePath = "$env:TEMP\OSDCloudWorkspace"
    CleanupTempFiles = $true
    IncludeWinRE = $true
    OptimizeISOSize = $true
}

# Export the configuration
Export-ModuleMember -Variable OSDCloudConfig