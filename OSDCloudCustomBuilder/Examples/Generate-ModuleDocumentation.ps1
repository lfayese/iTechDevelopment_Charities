<#
.SYNOPSIS
    Generates comprehensive documentation for the OSDCloudCustomBuilder module.
.DESCRIPTION
    This example script demonstrates how to generate complete documentation for the
    OSDCloudCustomBuilder module, including function references, examples, and parameter details.
    It also extracts example code from function documentation into runnable script files.
.NOTES
    This script requires the OSDCloudCustomBuilder module to be installed and loaded.
#>

# Import required module
Import-Module OSDCloudCustomBuilder -Force

# Define the output path for documentation
$docsOutputPath = Join-Path -Path $PSScriptRoot -ChildPath "../Docs"

# Create a README template
$readmeTemplatePath = Join-Path -Path $env:TEMP -ChildPath "ReadmeTemplate.md"

@"
# {{ModuleName}}

**Version:** {{ModuleVersion}}

## Description
{{ModuleDescription}}

## Features
- Create custom OSDCloud ISOs with Windows Image (WIM) files
- Add PowerShell 7 support to WinPE environments
- Optimize ISO size for faster deployment
- Comprehensive logging and telemetry system
- Detailed documentation and examples

## Installation
```powershell
# Install from PowerShell Gallery
Install-Module -Name OSDCloudCustomBuilder -Scope CurrentUser

# Or clone the repository
git clone https://github.com/ofayese/OSDCloudCustomBuilder.git
```

## Quick Start
```powershell
# Import the module
Import-Module OSDCloudCustomBuilder

# Create a custom ISO with PowerShell 7
Update-CustomWimWithPwsh7 -WimFile "D:\custom.wim"
New-CustomOSDCloudISO -WimFile "D:\custom.wim" -OutputFolder "D:\ISO"
```

## Documentation
For full documentation, see the [docs folder](./Docs/index.md).

## Telemetry
This module includes optional telemetry to help identify issues in production environments.
Telemetry is disabled by default and can be enabled with `Set-OSDCloudTelemetry`.

## License
See [LICENSE](./LICENSE) file for details.
"@ | Out-File -FilePath $readmeTemplatePath -Encoding UTF8

# Generate the documentation
Write-Host "Generating comprehensive documentation..." -ForegroundColor Cyan
$docParams = @{
    OutputPath = $docsOutputPath
    IncludePrivateFunctions = $true
    GenerateExampleFiles = $true
    ReadmeTemplate = $readmeTemplatePath
    Verbose = $true
}

# Measure the documentation generation process with telemetry
Measure-OSDCloudOperation -Name "Generate Module Documentation" -ScriptBlock {
    $result = ConvertTo-OSDCloudDocumentation @docParams
    
    if ($result) {
        Write-Host "Documentation generated successfully at: $docsOutputPath" -ForegroundColor Green
        Write-Host "- Function reference pages" -ForegroundColor Green
        Write-Host "- Example scripts extracted from documentation" -ForegroundColor Green
        Write-Host "- Module overview and quick start guide" -ForegroundColor Green
    }
    else {
        Write-Warning "Documentation generation completed with warnings or errors."
    }
}

# Clean up the temporary template file
if (Test-Path -Path $readmeTemplatePath) {
    Remove-Item -Path $readmeTemplatePath -Force
}

# Show documentation path
if (Test-Path -Path $docsOutputPath) {
    Write-Host "`nBrowse documentation starting with: $docsOutputPath\index.md" -ForegroundColor Cyan
}