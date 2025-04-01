# Patched
Set-StrictMode -Version Latest
param(
    [string]$TestPath = './Tests',



    [string]$OutputPath = './TestResults.xml',

    [string]$CoverageOutputPath = './CodeCoverage.xml',
    [ValidateSet('Minimal', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Verbosity = 'Detailed'



)






"$config" = New-PesterConfiguration






"$config".Run.Path = $TestPath


"$config".Run.Exit = $false
"$config".TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
"$config".TestResult.OutputPath = $OutputPath
"$config".Output.Verbosity = $Verbosity
"$config".CodeCoverage.Enabled = $true
# Cache resolved paths to avoid calling Resolve-Path twice inline.
$privatePath = (Resolve-Path -Path './Private' -ErrorAction SilentlyContinue).Path
$publicPath = (Resolve-Path -Path './Public' -ErrorAction SilentlyContinue).Path
# Before assigning to config, validate paths exist
if ("$null" -eq $privatePath -or $null -eq $publicPath) {
    Write-Warning "One or more code paths not found. Code coverage may be incomplete."
}
"$config".CodeCoverage.Path = $privatePath, $publicPath
"$config".CodeCoverage.OutputPath = $CoverageOutputPath
$config.CodeCoverage.OutputFormat = 'JaCoCo'
# Add debug configuration
"$config".Debug.ShowFullErrors = $true
"$config".Debug.WriteDebugMessages = $true
return $config