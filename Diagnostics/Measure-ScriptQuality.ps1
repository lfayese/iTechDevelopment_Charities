# Measure-ScriptQuality.ps1
# Analyzes PowerShell scripts in OSDCloudCustomBuilder and outputs Excel + SQLite reports with RELATIVE paths

Set-StrictMode -Version Latest

# Validate required modules
$requiredModules = @("PSScriptAnalyzer", "ImportExcel", "PSSQLite")
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Required module '$module' is not installed. Run: Install-Module $module -Scope CurrentUser"
    }
}

if (-not (Get-Command Invoke-SqliteQuery -ErrorAction SilentlyContinue)) {
    throw "PSSQLite module is not available or not imported."
}

function Invoke-ScriptQualityCheck {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$DirectoryPath,
        [Parameter(Mandatory)][string]$ExcelPath,
        [Parameter(Mandatory)][string]$DbPath
    )

    Write-Host "`n🔍 Analyzing scripts in: $DirectoryPath" -ForegroundColor Cyan

    if (-not (Test-Path -Path $DirectoryPath)) {
        Write-Warning "Directory '$DirectoryPath' does not exist."
        return
    }

    $files = Get-ChildItem -Path $DirectoryPath -Recurse -Include *.ps1, *.psm1 -File

    if (-not $files) {
        Write-Warning "No PowerShell script files found in $DirectoryPath."
        return
    }

    $reportSummary = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($file in $files) {
        try {
            $results = Invoke-ScriptAnalyzer -Path $file.FullName -ErrorAction Stop
            $relativePath = $file.FullName.Substring($DirectoryPath.Length).TrimStart('\','/')

            foreach ($result in $results) {
                $reportSummary.Add([PSCustomObject]@{
                    FileName   = $relativePath
                    Issue      = $result.RuleName
                    Suggestion = $result.Message
                })
            }
        } catch {
            Write-Warning "⚠ Failed to analyze '$($file.FullName)': $($_.Exception.Message)"
        }
    }

    if ($reportSummary.Count -eq 0) {
        Write-Warning "✅ No issues found in '$DirectoryPath'."
        return
    }

    # Export to Excel
    try {
        $reportSummary | Export-Excel -Path $ExcelPath -AutoSize -WorksheetName "ScriptAnalysis"
        Write-Host "✔ Excel report exported to $ExcelPath" -ForegroundColor Green
    } catch {
        Write-Warning "⚠ Excel export failed: $($_.Exception.Message)"
    }

    # Export to SQLite
    try {
        Invoke-SqliteQuery -DataSource $DbPath -Query @"
CREATE TABLE IF NOT EXISTS ReportSummary (
    FileName TEXT,
    Issue TEXT,
    Suggestion TEXT
)
"@

        foreach ($entry in $reportSummary) {
            Invoke-SqliteQuery -DataSource $DbPath -Query @"
INSERT INTO ReportSummary (FileName, Issue, Suggestion)
VALUES (
    '$(($entry.FileName -replace "'", "''"))',
    '$(($entry.Issue -replace "'", "''"))',
    '$(($entry.Suggestion -replace "'", "''"))'
)
"@
        }

        Write-Host "✔ Database report saved to $DbPath" -ForegroundColor Green
    } catch {
        Write-Warning "⚠ Database export failed: $($_.Exception.Message)"
    }
}

# --- Define relative paths ---
$basePath     = $PSScriptRoot
$sourceFolder1 = Join-Path $basePath ".\OSDCloud" | Resolve-Path -ErrorAction Stop
$sourceFolder2 = Join-Path $basePath ".\OSDCloudCustomBuilder" | Resolve-Path -ErrorAction Stop
$diagFolder1   = Join-Path $sourceFolder1 "Diagnostics"
$diagFolder2   = Join-Path $sourceFolder2 "Diagnostics"

Invoke-ScriptQualityCheck `
    -DirectoryPath $sourceFolder1 `
    -ExcelPath     (Join-Path $diagFolder1 "OSDCloud_report_summary.xlsx") `
    -DbPath        (Join-Path $diagFolder1 "OSDCloud_report_summary.db")

Invoke-ScriptQualityCheck `
    -DirectoryPath $sourceFolder2 `
    -ExcelPath     (Join-Path $diagFolder2 "OSDCloudCustomBuilder_report_summary.xlsx") `
    -DbPath        (Join-Path $diagFolder2 "OSDCloudCustomBuilder_report_summary.db")

