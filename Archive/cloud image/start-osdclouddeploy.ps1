# Set execution policy for the current process to Bypass
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
# Check if the computer model is virtual and set display resolution
if ((Get-MyComputerModel) -match 'Virtual') {
    Write-Host -ForegroundColor Cyan "Setting Display resolution to 1600x"
    Set-DisRes 1600
}
# Prepare logging parameters
$transcriptFile = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Start-CloudImage.log"
$logPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD"
if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}
$transcriptFullPath = Join-Path $logPath $transcriptFile
try {
    Start-Transcript -Path $transcriptFullPath -ErrorAction Stop
} catch {
    Write-Error "Failed to start transcript: $_"
        exit 1
    }
function Test-AdminRights {
        $isAdmin = ([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This script requires Administrator privileges"
    }
}
function Show-Menu {
    $header = @"
================ Main Menu ==================
Welcome To Workplace OSDCloud Image
=============================================
=============================================

"@
    $menu = @(
        "1: Start the OSDCloud process with FindImageFile parameter",
        "2: Start the OSDCloud Wim (Start-OSDCloudWim)",
        "3: Start the graphical OSDCloud (Start-OSDCloudGUI)",
        "0: Exit",
        "99: Reload !!!"
    )

    Write-Host $header -ForegroundColor Yellow
    $menu | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    Write-Host "`n DISCLAIMER: USE AT YOUR OWN RISK - Going further will erase all data on your disk !`n" -ForegroundColor Red -BackgroundColor Black
}

function Start-OSDCloudProcess {
    param(
        [string]$Option
    )

    try {
        switch ($Option) {
            '1' {
                Write-Host "Starting OSDCloud with FindImageFile parameter..." -ForegroundColor Cyan
                Start-OSDCloud -FindImageFile -ErrorAction Stop
            }
            '2' {
                Write-Host "Starting OSDCloudWim..." -ForegroundColor Cyan
                Start-OSDCloudWim -ErrorAction Stop
            }
            '3' {
                Write-Host "Starting OSDCloud GUI..." -ForegroundColor Cyan
                Start-OSDCloudGUI -ErrorAction Stop
            }
            '0' {
                Write-Host "Exiting..." -ForegroundColor Yellow
                return $false
            }
            '99' {
                Write-Host "Reloading from USB drive..." -ForegroundColor Cyan
                $usbScript = 'X:\Scripts\Start-osdclouddeploy.ps1'
                if (Test-Path $usbScript) {
                    & $usbScript
                } else {
                    throw "USB script not found at: $usbScript"
                }
            }
            default {
                throw "Invalid option: $Option"
            }
        }
        Write-Host "OSDCloud process completed successfully" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to execute OSDCloud process: $_"
        return $false
    }
}

function Restart-WinPE {
    try {
        Write-Host "Initiating WinPE reboot..." -ForegroundColor Cyan
        Stop-Transcript
        Start-Sleep -Seconds 3  # Give time for transcript to complete
        wpeutil reboot
    } catch {
        Write-Error "Failed to reboot WinPE: $_. Please reboot manually."
    }
}

# Main execution block
try {
    # Check admin rights
    Test-AdminRights

    # Import OSDCloud module
    try {
        Write-Host "Importing OSDCloud module..." -ForegroundColor Cyan
        Import-Module OSDCloud -Force -ErrorAction Stop
        Write-Host "OSDCloud module imported successfully" -ForegroundColor Green
    } catch {
        throw "Failed to import OSDCloud module: $_"
    }

    # Show menu and get user input
    do {
        Show-Menu
        $userInput = Read-Host "Please make a selection"

        if ($userInput -eq '0') {
            Write-Host "Exiting..." -ForegroundColor Yellow
            break
        }

        if (Start-OSDCloudProcess -Option $userInput) {
            Restart-WinPE
            break
        }

        Write-Host "Press Enter to continue..." -ForegroundColor Yellow
        $null = Read-Host
        Clear-Host
    } while ($true)

} catch {
    Write-Error "Script execution failed: $_"
    exit 1
} finally {
    Stop-Transcript
}
