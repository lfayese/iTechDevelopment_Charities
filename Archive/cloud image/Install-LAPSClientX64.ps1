# LAPS Client x64 Install Script
# Start logging
$Global:Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-LAPSInstall.log"
$ScriptName = "LAPS Client Installer"
$ScriptVersion = "24.02.14.01"

# Initialize logging environment
try {
    $tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment
    $LogFolder = $tsenv.Value('CompanyFolder')
    $CompanyName = $tsenv.Value('CompanyName')
} catch {
    Write-Output "Not running in Task Sequence - using default values"
    $CompanyName = "RecastSoftwareIT"
    $LogFolder = "$env:ProgramData\$CompanyName"
}

$LogFilePath = "$LogFolder\Logs"
if (!(Test-Path -Path $LogFilePath)) {
    New-Item -Path $LogFilePath -ItemType Directory -Force | Out-Null
}
$LogFile = "$LogFilePath\LAPS_Install.log"

function Write-CMTraceLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [string]$ErrorMessage,
        [Parameter(Mandatory=$false)]
        [string]$Component = "LAPSInstall",
        [Parameter(Mandatory=$false)]
        [ValidateSet(1, 2, 3)]
        [int]$Type = 1
    )
    
    $Time = Get-Date -Format "HH:mm:ss.ffffff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    $LogMessage = "<![LOG[$Message $ErrorMessage]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $LogMessage.Replace("`0","") | Out-File -Append -Encoding UTF8 -FilePath $LogFile
}

function Install-LAPS {
    param (
        [Parameter(Mandatory=$true)]
        [string]$InstallerPath
    )
    
    try {
        Write-CMTraceLog -Message "Installing LAPS from: $InstallerPath"
        $process = Start-Process -FilePath $InstallerPath -ArgumentList "/qb! /norestart" -PassThru -Wait
        
        switch ($process.ExitCode) {
            0 { 
                Write-CMTraceLog -Message "LAPS installation completed successfully"
                return $true
            }
            1603 {
                Write-CMTraceLog -Message "Fatal error during installation" -Type 3
                return $false
            }
            3010 {
                Write-CMTraceLog -Message "Installation successful - restart required" -Type 2
                return $true
            }
            default {
                Write-CMTraceLog -Message "Installation failed with exit code: $($process.ExitCode)" -Type 3
                return $false
            }
        }
    } catch {
        Write-CMTraceLog -Message "Error during LAPS installation" -ErrorMessage $_.Exception.Message -Type 3
        return $false
    }
}

# Main execution block
try {
    Write-CMTraceLog -Message "Starting $ScriptName version $ScriptVersion"
    
    # First try local installer
    $LocalLapsPath = "X:\OSDCloud\Software\LAPS\LAPS.x64.msi"
    if (Test-Path -Path $LocalLapsPath) {
        Write-CMTraceLog -Message "Found local LAPS installer"
        if (Install-LAPS -InstallerPath $LocalLapsPath) {
            Write-CMTraceLog -Message "Successfully installed LAPS from local source"
            exit 0
        }
    }
    
    # If local install fails or file not found, try web download
    $FileName = "LAPS.x64.msi"
    $URL = "https://download.microsoft.com/download/C/7/A/C7AAD914-A8A6-4904-88A1-29E657445D03/$FileName"
    $DownloadPath = Join-Path $env:TEMP $FileName
    
    Write-CMTraceLog -Message "Testing download URL accessibility"
    try {
        $testRequest = Invoke-WebRequest -Uri $URL -Method Head -UseBasicParsing
        if ($testRequest.StatusCode -ne 200) {
            throw "URL returned status code: $($testRequest.StatusCode)"
        }
    } catch {
        Write-CMTraceLog -Message "Failed to access download URL" -ErrorMessage $_.Exception.Message -Type 3
        exit 1
    }
    
    Write-CMTraceLog -Message "Downloading LAPS installer"
    try {
        Start-BitsTransfer -Source $URL -Destination $DownloadPath -DisplayName "LAPS Download" -ErrorAction Stop
        
        if (!(Test-Path $DownloadPath)) {
            throw "Download completed but file not found"
        }
        
        # Verify file hash (add proper hash check if available)
        # $expectedHash = "YOUR-EXPECTED-HASH"
        # $actualHash = (Get-FileHash $DownloadPath -Algorithm SHA256).Hash
        # if ($actualHash -ne $expectedHash) {
        #     throw "File hash verification failed"
        # }
        
    } catch {
        Write-CMTraceLog -Message "Failed to download LAPS installer" -ErrorMessage $_.Exception.Message -Type 3
        exit 1
    }
    
    # Install from downloaded file
    if (Install-LAPS -InstallerPath $DownloadPath) {
        Write-CMTraceLog -Message "Successfully installed LAPS from downloaded installer"
        exit 0
    } else {
        Write-CMTraceLog -Message "Failed to install LAPS" -Type 3
        exit 1
    }
    
} catch {
    Write-CMTraceLog -Message "Script execution failed" -ErrorMessage $_.Exception.Message -Type 3
    exit 1
} finally {
    # Cleanup
    if (Test-Path $DownloadPath) {
        Remove-Item -Path $DownloadPath -Force -ErrorAction SilentlyContinue
    }
}
