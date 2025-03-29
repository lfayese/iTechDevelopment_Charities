<#
.SYNOPSIS
    Generates a computer name based on device model and manufacturer.
.DESCRIPTION
    Creates a standardized computer name using manufacturer and model information.
    For VMs, generates a name with company prefix and random number.
    Ensures computer name is valid (max 15 chars, no invalid characters).
.NOTES
    Author: OSDCloud Administrator
    Updated: Modern PowerShell best practices implemented
#>

# Start logging with proper path creation
$LogFolder = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD"
if (-not (Test-Path -Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}
$Global:Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-CreateOSDComputerName.log"
Start-Transcript -Path (Join-Path $LogFolder $Global:Transcript) -ErrorAction Stop

function Get-SystemInfo {
    [CmdletBinding()]
    param()

    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        return @{
            Manufacturer = $computerSystem.Manufacturer
            Model = $computerSystem.Model
            Serial = $bios.SerialNumber
        }
    } catch {
        Write-Error "Failed to get system information: $_"
        throw "Unable to retrieve system information. $($_.Exception.Message)"
    }
}

function Format-ComputerName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$name
    )

    # Remove invalid characters (only allow letters, numbers, and hyphens)
    $invalid = '[^a-zA-Z0-9\-]'
    $name = $name -replace $invalid, ''

    # Ensure name length is valid (max 15 chars for NetBIOS compatibility)
    if ($name.Length -gt 15) {
        Write-Warning "Computer name exceeds 15 characters, truncating: $name"
        $name = $name.Substring(0, 15)
    }

    # Ensure name doesn't end with a hyphen (invalid for Windows naming)
    $name = $name -replace '-$', ''

    return $name
}

try {
    Write-Host "Starting computer name generation process..." -ForegroundColor Cyan

    # Try to get Task Sequence environment
    try {
        $tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
        Write-Host "Running in Task Sequence environment" -ForegroundColor Green
    } catch {
        Write-Host "Not running in Task Sequence environment" -ForegroundColor Yellow
        $tsenv = $null
    }

    # Get system information
    $sysInfo = Get-SystemInfo
    $Manufacturer = $sysInfo.Manufacturer
    $Model = $sysInfo.Model
    $Serial = $sysInfo.Serial
    $CompanyName = "iTechCharities"

    Write-Host "System Information:" -ForegroundColor Cyan
    Write-Host "- Manufacturer: $Manufacturer" -ForegroundColor Gray
    Write-Host "- Model: $Model" -ForegroundColor Gray
    Write-Host "- Serial: $Serial" -ForegroundColor Gray

    # Generate computer name based on manufacturer
    $ComputerName = switch -Regex ($Manufacturer) {
        "Lenovo" {
            try {
                $modelVersion = (Get-CimInstance -ClassName Win32_ComputerSystemProduct).Version
                if ($modelVersion) {
                    $modelNumber = $modelVersion.Split(" ")[1]
                    Format-ComputerName "LNV-$modelNumber-$($Serial.Substring(0,4))"
                } else {
                    Format-ComputerName "LNV-$($Model.Substring(0,5))-$($Serial.Substring(0,4))"
                }
            } catch {
                Write-Warning "Failed to parse Lenovo model, using fallback: $_"
                Format-ComputerName "LNV-$($Model.Substring(0,5))-$($Serial.Substring(0,4))"
            }
        }
        "HP|Hewlett-Packard" {
            try {
                # Extract the product name or model
                if ($Model -match '(\w+)\s+(\w+)') {
                    $prefix = ($Matches[1] + $Matches[2]).Substring(0,6)
                    Format-ComputerName "HP-$prefix-$($Serial.Substring(0,4))"
                } else {
                    Format-ComputerName "HP-$($Model.Replace(' ','').Substring(0,6))-$($Serial.Substring(0,4))"
                }
            } catch {
                Write-Warning "Failed to parse HP model, using fallback: $_"
                Format-ComputerName "HP-$($Serial.Substring(0,8))"
            }
        }
        "Dell" {
            if ($Model -match "^(\w+)-(\w+)") {
                $parts = $Model -split "-"
                Format-ComputerName "Dell-$($parts -join '-')"
            } else {
                $parts = $Model.Split(" ") | Select-Object -First 2
                Format-ComputerName "Dell-$($parts -join '-')"
            }
        }
        "Microsoft" {
            if ($Model -match "Virtual") {
                $random = Get-Random -Minimum 10000 -Maximum 99999
                Format-ComputerName "VM-$CompanyName-$random"
            } else {
                Format-ComputerName "MS-$($Model.Replace(' ','-'))-$($Serial.Substring(0,4))"
            }
        }
        default {
            # Fallback to serial number with manufacturer prefix
            $mfrPrefix = $Manufacturer.Substring(0, [Math]::Min(3, $Manufacturer.Length))
            Format-ComputerName "$mfrPrefix-$Serial"
        }
    }

    # Final validation
    if ([string]::IsNullOrEmpty($ComputerName) -or $ComputerName.Length -lt 2) {
        $random = Get-Random -Minimum 10000 -Maximum 99999
        $ComputerName = "PC-$random"
        Write-Warning "Generated computer name was invalid, using fallback: $ComputerName"
    }

    Write-Host "====================================================="
    Write-Host "Generated computer name: $ComputerName" -ForegroundColor Green
    Write-Host "====================================================="

    # Set the computer name in the task sequence if available
    if ($tsenv) {
        $tsenv.Value('OSDComputerName') = $ComputerName
        Write-Host "Set OSDComputerName in task sequence" -ForegroundColor Green
    }

    # Also set the computer name directly if not in a task sequence
    if (-not $tsenv) {
        try {
            Write-Host "Attempting to rename computer directly..." -ForegroundColor Yellow
            Rename-Computer -NewName $ComputerName -ErrorAction Stop
            Write-Host "Computer renamed successfully to $ComputerName" -ForegroundColor Green
        } catch {
            Write-Warning "Could not rename computer directly: $_"
        }
    }

    # Validate the final computer name
    if ($ComputerName.Length -gt 15) {
        throw "Generated computer name exceeds 15 characters: $ComputerName"
    }
    if ($ComputerName -match '[^a-zA-Z0-9\-]') {
        throw "Generated computer name contains invalid characters: $ComputerName"
    }

} catch {
    Write-Error "Failed to generate computer name: $_"
    exit 1
} finally {
    Stop-Transcript
}