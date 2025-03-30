function Get-PowerShell7Package {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PowerShell7Url,
        [Parameter(Mandatory = $true)]
        [string]$TempPath,
        [Parameter()]
        [string]$PackageName = "PowerShell-7.5.0-win-x64.zip",
        [Parameter()]
        [int]$TimeoutSec = 300
    )
    Write-Verbose "Processing download of PowerShell 7 package from $PowerShell7Url..."
    
    $PowerShell7File = Join-Path $TempPath $PackageName
    if (-not (Test-Path $PowerShell7File)) {
        try {
            Write-Verbose "Downloading PowerShell 7..."
            Invoke-WebRequest -Uri $PowerShell7Url -OutFile $PowerShell7File -TimeoutSec $TimeoutSec
            Write-Verbose "PowerShell 7 downloaded successfully."
        }
        catch {
            $errorMsg = "Failed to download PowerShell 7 from $PowerShell7Url. Error: $_"
            Write-Error $errorMsg
            throw [System.Exception]$errorMsg
        }
    }
    else {
        Write-Verbose "Using existing PowerShell 7 package at $PowerShell7File."
    }
    return $PowerShell7File
}