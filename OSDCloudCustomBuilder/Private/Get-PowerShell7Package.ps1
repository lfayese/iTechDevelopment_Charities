function Get-PowerShell7Package {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PowerShell7Url,
        
        [Parameter(Mandatory=$true)]
        [string]$TempPath
    )
    
    Write-Host "Downloading PowerShell 7..." -ForeColor Cyan
    
    $PowerShell7File = Join-Path $TempPath "PowerShell-7.5.0-win-x64.zip"
    if (-not (Test-Path $PowerShell7File)) {
        try {
            Invoke-WebRequest -Uri $PowerShell7Url -OutFile $PowerShell7File -UseBasicParsing
            Write-Host "PowerShell 7 downloaded successfully" -ForeColor Green
        } catch {
            Write-Error "Failed to download PowerShell 7: $_"
            throw "Failed to download PowerShell 7: $_"
        }
    } else {
        Write-Host "Using existing PowerShell 7 package" -ForeColor Green
    }
    
    return $PowerShell7File
}