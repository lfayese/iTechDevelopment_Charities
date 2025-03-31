<#
.SYNOPSIS
    Functions for customizing WinPE with PowerShell 7 support.
.DESCRIPTION
    This file contains modular functions for working with WinPE and adding PowerShell 7 support.
.NOTES
    Version: 0.2.0
    Author: OSDCloud Team
#>

function Initialize-WinPEMountPoint {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter()]
        [string]$InstanceId = [Guid]::NewGuid().ToString()
    )
    try {
        if (-not (Test-Path -Path $TempPath -PathType Container)) {
            New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        }
        
        $mountPoint = Join-Path -Path $TempPath -ChildPath "Mount_$InstanceId"
        New-Item -Path $mountPoint -ItemType Directory -Force | Out-Null
        return $mountPoint
    }
    catch {
        Write-Error "Failed to initialize WinPE mount point: $_"
        throw
    }
}

function Get-PowerShell7Package {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidatePattern('^(\d+\.\d+\.\d+)$')]
        [string]$Version = "7.5.0",
        
        [Parameter()]
        [string]$DownloadPath
    )
    $downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-win-x64.zip"
    
    try {
        Write-Verbose "Downloading PowerShell $Version from $downloadUrl"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $DownloadPath -UseBasicParsing
        
        if (Test-Path -Path $DownloadPath -PathType Leaf) {
            Write-Verbose "Successfully downloaded PowerShell 7 to $DownloadPath"
        } else {
            throw "Download completed but file not found at expected location"
        }
    }
    catch {
        throw "Failed to download PowerShell 7: $_"
    }
}

function Mount-WinPEImage {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
        [string]$ImagePath,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPath,
        
        [Parameter()]
        [int]$Index = 1,
        
        [Parameter()]
        [int]$MaxRetries = 3
    )
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            Mount-WindowsImage -ImagePath $ImagePath -Index $Index -Path $MountPath
            return
        }
        catch {
            if ($i -eq $MaxRetries - 1) {
                Write-Error "Failed to mount WinPE image after $MaxRetries attempts: $_"
                throw
            }
            Start-Sleep -Seconds 2
        }
    }
}

function Install-PowerShell7ToWinPE {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
        [string]$PowerShell7File,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint
    )
    $pwsh7Destination = Join-Path -Path $MountPoint -ChildPath "Windows\System32\PowerShell7"
    if (-not (Test-Path -Path $pwsh7Destination)) {
        New-Item -Path $pwsh7Destination -ItemType Directory -Force | Out-Null
    }
    
    Write-Verbose "Extracting PowerShell 7 from $PowerShell7File to $pwsh7Destination"
    Expand-Archive -Path $PowerShell7File -DestinationPath $pwsh7Destination -Force
}

function Update-WinPEStartup {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint,
        
        [Parameter()]
        [string]$PowerShell7Path = "X:\Windows\System32\PowerShell7"
    )
    $startupScriptPath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\StartNet.cmd"
    $startupScriptContent = @"
@echo off
set PATH=%PATH%;$PowerShell7Path
$PowerShell7Path\pwsh.exe -NoLogo -Command "Write-Host 'PowerShell 7 is initialized and ready.' -ForegroundColor Green"
"@
    Add-Content -Path $startupScriptPath -Value $startupScriptContent -Force
}

function Dismount-WinPEImage {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint,
        
        [Parameter()]
        [switch]$Save = $true,
        
        [Parameter()]
        [int]$MaxRetries = 3
    )
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            Dismount-WindowsImage -Path $MountPoint -Save:$Save
            return
        }
        catch {
            if ($i -eq $MaxRetries - 1) {
                Write-Error "Failed to dismount WinPE image after $MaxRetries attempts: $_"
                throw
            }
            Start-Sleep -Seconds 2
        }
    }
}

function Customize-WinPEWithPowerShell7 {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkspacePath,
        
        [Parameter()]
        [ValidatePattern('^(\d+\.\d+\.\d+)$')]
        [string]$PowerShellVersion = "7.5.0",
        
        [Parameter()]
        [string]$PowerShell7File
    )
    try {
        $mountPoint = Initialize-WinPEMountPoint -TempPath $TempPath
        
        if (-not $PowerShell7File) {
            $PowerShell7File = Join-Path -Path $TempPath -ChildPath "PowerShell-$PowerShellVersion-win-x64.zip"
            Get-PowerShell7Package -Version $PowerShellVersion -DownloadPath $PowerShell7File
        }
        
        $wimPath = Join-Path -Path $WorkspacePath -ChildPath "Media\Sources\boot.wim"
        if (-not (Test-Path -Path $wimPath)) {
            throw "WinPE image not found at path: $wimPath"
        }
        
        if ($PSCmdlet.ShouldProcess("$wimPath", "Mount and customize with PowerShell 7")) {
            Mount-WinPEImage -ImagePath $wimPath -MountPath $mountPoint
            Install-PowerShell7ToWinPE -PowerShell7File $PowerShell7File -TempPath $TempPath -MountPoint $mountPoint
            Update-WinPEStartup -MountPoint $mountPoint
            Dismount-WinPEImage -MountPoint $mountPoint -Save
            Write-Verbose "PowerShell 7 integration complete"
            return $wimPath
        }
    }
    catch {
        Write-Error "Failed to customize WinPE with PowerShell 7: $_"
        throw
    }
    finally {
        if (Test-Path -Path $mountPoint) {
            Remove-Item -Path $mountPoint -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

# For backward compatibility
Set-Alias -Name Update-WinPEWithPowerShell7 -Value Customize-WinPEWithPowerShell7

# Export all functions and aliases
Export-ModuleMember -Function * -Alias *