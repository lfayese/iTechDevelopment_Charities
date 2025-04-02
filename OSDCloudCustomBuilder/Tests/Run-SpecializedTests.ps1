Set-StrictMode -Version Latest

# This script runs all the specialized test categories for the OSDCloudCustomBuilder module
# It's designed to verify the security, performance, error handling, and logging improvements

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('All', 'Security', 'Performance', 'ErrorHandling', 'Logging')]
    [string[]]$Categories = 'All',
    
    [Parameter()]
    [switch]$GenerateReport,
    
    [Parameter()]
    [string]$OutputPath = './TestResults-Specialized.xml',
    
    [Parameter()]
    [string]$CoverageOutputPath = './CodeCoverage-Specialized.xml',
    
    [Parameter()]
    [ValidateSet('Minimal', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Verbosity = 'Detailed'
)

# Determine which tests to run based on the specified categories
$testPaths = @()

if ($Categories -contains 'All' -or $Categories -contains 'Security') {
    $testPaths += './Tests/Security'
}

if ($Categories -contains 'All' -or $Categories -contains 'Performance') {
    $testPaths += './Tests/Performance'
}

if ($Categories -contains 'All' -or $Categories -contains 'ErrorHandling') {
    $testPaths += './Tests/ErrorHandling'
}

if ($Categories -contains 'All' -or $Categories -contains 'Logging') {
    $testPaths += './Tests/Logging'
}

# If no specific categories were selected or found, run the comprehensive test suite
if ($testPaths.Count -eq 0) {
    $testPaths += './Tests/Comprehensive-TestSuite.Tests.ps1'
}

# Import required modules
if (-not (Get-Module -Name Pester -ListAvailable)) {
    Write-Warning "Pester module not found. Installing..."
    Install-Module -Name Pester -Force -SkipPublisherCheck
}

# Import the module to test
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\OSDCloudCustomBuilder.psm1'
if (Test-Path -Path $modulePath) {
    Import-Module -Name $modulePath -Force
}
else {
    Write-Error "Module file not found at $modulePath"
    exit 1
}

# Get the Pester configuration
$configPath = Join-Path -Path $PSScriptRoot -ChildPath '..\pester.config.ps1'
if (-not (Test-Path -Path $configPath)) {
    Write-Error "Pester configuration file not found at $configPath"
    exit 1
}

# Create configuration with our parameters
$config = & $configPath -TestPath $testPaths -OutputPath $OutputPath -CoverageOutputPath $CoverageOutputPath -Verbosity $Verbosity

# Run the tests
$results = Invoke-Pester -Configuration $config

# Display test summary
Write-Host "`nSpecialized Test Summary:" -ForegroundColor Cyan
Write-Host "  Passed: $($results.PassedCount)" -ForegroundColor Green
Write-Host "  Failed: $($results.FailedCount)" -ForegroundColor Red
Write-Host "  Skipped: $($results.SkippedCount)" -ForegroundColor Yellow
Write-Host "  Total: $($results.TotalCount)" -ForegroundColor Cyan
Write-Host "  Duration: $($results.Duration.TotalSeconds) seconds`n" -ForegroundColor Cyan

# Generate HTML report if requested
if ($GenerateReport) {
    if (Test-Path -Path $CoverageOutputPath) {
        Write-Host "Generating HTML report..." -ForegroundColor Cyan
        
        # Check if ReportGenerator is available
        $reportModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Tools\ReportGenerator'
        if (Test-Path -Path $reportModulePath) {
            $reportGeneratorPath = Join-Path -Path $reportModulePath -ChildPath 'ReportGenerator.exe'
            if (Test-Path -Path $reportGeneratorPath) {
                $reportOutputPath = Join-Path -Path $PSScriptRoot -ChildPath '..\SpecializedTestReport'
                & $reportGeneratorPath "-reports:$CoverageOutputPath" "-targetdir:$reportOutputPath" "-reporttypes:Html"
                
                # Open the report in the default browser
                $indexPath = Join-Path -Path $reportOutputPath -ChildPath 'index.htm'
                if (Test-Path -Path $indexPath) {
                    Start-Process $indexPath
                    Write-Host "Report generated at: $indexPath" -ForegroundColor Green
                }
            }
            else {
                Write-Warning "ReportGenerator not found. Install it to view HTML coverage reports."
            }
        }
        else {
            Write-Warning "ReportGenerator module not found. Install it to view HTML coverage reports."
        }
    }
    else {
        Write-Warning "Code coverage report not found at $CoverageOutputPath"
    }
}

# Return the results for use in scripts
return $results