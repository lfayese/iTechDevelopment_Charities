<#
.SYNOPSIS
    Module manifest for OSDCloudLogger module
.DESCRIPTION
    This manifest file defines the OSDCloudLogger module and its components
.NOTES
    Created for: Charity OSDCloud Deployment
    Author: iTech Development
    Date: March 30, 2025
#>

@{
    RootModule = 'OSDCloudLogger.psm1'
    ModuleVersion = '1.0.0'
    GUID = '9e8d5e7f-3b4a-4c5d-8d6e-7f8a9b0c1d2e'
    Author = 'iTech Development'
    CompanyName = 'iTech Development for Charities'
    Copyright = '(c) 2025 iTech Development. All rights reserved.'
    Description = 'Centralized logging and error handling module for OSDCloud deployment scripts'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Initialize-OSDCloudLogger',
        'Write-OSDCloudLog',
        'Write-OSDCloudError',
        'Invoke-OSDCloudErrorRecovery',
        'Get-OSDCloudErrorSummary',
        'Test-OSDCloudDependency'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Logging', 'ErrorHandling', 'OSDCloud', 'Charity')
            LicenseUri = ''
            ProjectUri = ''
            ReleaseNotes = 'Initial release of the OSDCloudLogger module'
        }
    }
}