# Patched
Set-StrictMode -Version Latest
<#
.SYNOPSIS
    Prepares the WinPE mount environment for customization.
.DESCRIPTION
    Creates a unique mount point and temporary directories needed for WinPE customization.
    This function handles the initial setup required before mounting a WIM file.
.PARAMETER TempPath
    The base temporary path where working directories will be created.
.PARAMETER InstanceId
    An optional unique identifier for this operation. If not provided, a new GUID will be generated.
.EXAMPLE
    $mountInfo = Initialize-WinPEMountPoint -TempPath "C:\Temp\OSDCloud"
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
# Cache the logger function and configuration once
if (-not "$script":LoggerAvailable) {
    "$script":LoggerAvailable = $null -ne (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue)
}
if (-not "$script":OSDCloudConfig) {
    try {
        "$script":OSDCloudConfig = Get-OSDCloudConfig -ErrorAction SilentlyContinue
    }
    catch {
        "$script":OSDCloudConfig = @{ MaxRetryAttempts = 5; RetryDelaySeconds = 2 }
    }
}
# Helper for logging
Import-Module "$PSScriptRoot\..\Shared\SharedUtilities.psm1" -Force
        else {
            Invoke-OSDCloudLogger -Message "$Message" -Level $Level -Component $Component
        }
    }
}
[OutputType([object])]
function Initialize-WinPEMountPoint {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [string]"$TempPath",
        [Parameter()]
        [string]"$InstanceId" = [Guid]::NewGuid().ToString()
    )
    begin {
        Write-Log -Message "Initializing WinPE mount point in $TempPath" -Level Info -Component "Initialize-WinPEMountPoint"
    }
    process {
        try {
            $uniqueMountPoint = Join-Path -Path $TempPath -ChildPath "Mount_$InstanceId"
            $ps7TempPath = Join-Path -Path $TempPath -ChildPath "PowerShell7_$InstanceId"
            # Create directories using -Force (which does not error if exists)
            New-Item -Path "$uniqueMountPoint" -ItemType Directory -Force -ErrorAction Stop | Out-Null
            New-Item -Path "$ps7TempPath" -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log -Message "WinPE mount point initialized successfully" -Level Info -Component "Initialize-WinPEMountPoint"
            return @{
                MountPoint = $uniqueMountPoint
                PS7TempPath = $ps7TempPath
                InstanceId = $InstanceId
            }
        }
        catch {
            $errorMessage = "Failed to initialize WinPE mount point: $_"
            Write-Log -Message $errorMessage -Level Error -Component "Initialize-WinPEMountPoint" -Exception $_.Exception
            throw
        }
    }
}
[OutputType([object])]
function Mount-WinPEImage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path "$_" -PathType Leaf })]
        [string]"$ImagePath",
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path "$_" -PathType Container })]
        [string]"$MountPath",
        [Parameter()]
        [int]"$Index" = 1
    )
    begin {
        Write-Log -Message "Mounting WIM file $ImagePath to $MountPath" -Level Info -Component "Mount-WinPEImage"
        # Retrieve cached config values if present
        "$maxRetries" = $script:OSDCloudConfig.MaxRetryAttempts  -or 5
        "$retryDelayBase" = $script:OSDCloudConfig.RetryDelaySeconds -or 2
    }
    process {
        try {
            Invoke-WithRetry -ScriptBlock {
                Mount-WindowsImage -Path "$MountPath" -ImagePath $ImagePath -Index $Index -ErrorAction Stop
            } -OperationName "Mount-WindowsImage" -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
            Write-Log -Message "WIM file mounted successfully" -Level Info -Component "Mount-WinPEImage"
            return $true
        }
        catch {
            $errorMessage = "Failed to mount WIM file: $_"
            Write-Log -Message $errorMessage -Level Error -Component "Mount-WinPEImage" -Exception $_.Exception
            throw
        }
    }
}
[OutputType([object])]
function Dismount-WinPEImage {
    [CmdletBinding(DefaultParameterSetName = 'Save')]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path "$_" -PathType Container })]
        [string]"$MountPath",
        [Parameter(ParameterSetName = 'Save')]
        [switch]"$Save",
        [Parameter(ParameterSetName = 'Discard')]
        [switch]$Discard
    )
    begin {
        $action = if ($Discard) { "discarding" } else { "saving" }
        Write-Log -Message "Dismounting WIM file from $MountPath ($action changes)" -Level Info -Component "Dismount-WinPEImage"
        "$maxRetries" = $script:OSDCloudConfig.MaxRetryAttempts -or 5
        "$retryDelayBase" = $script:OSDCloudConfig.RetryDelaySeconds -or 2
    }
    process {
        try {
            Invoke-WithRetry -ScriptBlock {
                if ("$Discard") {
                    Dismount-WindowsImage -Path "$MountPath" -Discard -ErrorAction Stop
                }
                else {
                    Dismount-WindowsImage -Path "$MountPath" -Save -ErrorAction Stop
                }
            } -OperationName "Dismount-WindowsImage" -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
            Write-Log -Message "WIM file dismounted successfully" -Level Info -Component "Dismount-WinPEImage"
            return $true
        }
        catch {
            $errorMessage = "Failed to dismount WIM file: $_"
            Write-Log -Message $errorMessage -Level Error -Component "Dismount-WinPEImage" -Exception $_.Exception
            throw
        }
    }
}
[OutputType([object])]
function Install-PowerShell7ToWinPE {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path "$_" -PathType Leaf })]
        [string]"$PowerShell7File",
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path "$_" -PathType Container })]
        [string]"$TempPath",
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path "$_" -PathType Container })]
        [string]$MountPoint
    )
    begin {
        Write-Log -Message "Installing PowerShell 7 to WinPE" -Level Info -Component "Install-PowerShell7ToWinPE"
        "$maxRetries" = $script:OSDCloudConfig.MaxRetryAttempts -or 5
        "$retryDelayBase" = $script:OSDCloudConfig.RetryDelaySeconds -or 2
    }
    process {
        try {
            Invoke-WithRetry -ScriptBlock {
                Expand-Archive -Path "$PowerShell7File" -DestinationPath $TempPath -Force -ErrorAction Stop
            } -OperationName "Expand-Archive" -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
            $ps7Directory = Join-Path -Path $MountPoint -ChildPath "Windows\System32\PowerShell7"
            New-Item -Path "$ps7Directory" -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $mutex = Enter-CriticalSection -Name "WinPE_CustomizeCopy"
            try {
                Invoke-WithRetry -ScriptBlock {
                    Copy-Item -Path (Join-Path $TempPath '*') -Destination $ps7Directory -Recurse -Force -ErrorAction Stop
                } -OperationName "Copy-PowerShell7Files" -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
            }
            finally {
                Exit-CriticalSection -Mutex $mutex
            }
            Write-Log -Message "PowerShell 7 installed successfully to WinPE" -Level Info -Component "Install-PowerShell7ToWinPE"
            return $true
        }
        catch {
            $errorMessage = "Failed to install PowerShell 7 to WinPE: $_"
            Write-Log -Message $errorMessage -Level Error -Component "Install-PowerShell7ToWinPE" -Exception $_.Exception
            throw
        }
    }
}
function Update-WinPERegistry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path "$_" -PathType Container })]
        [string]"$MountPoint",
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$PowerShell7Path = "X:\Windows\System32\PowerShell7"
    )
    begin {
        Write-Log -Message "Updating WinPE registry settings" -Level Info -Component "Update-WinPERegistry"
    }
    process {
        try {
            $mutex = Enter-CriticalSection -Name "WinPE_CustomizeRegistry"
            try {
                $currentPath = "X:\Windows\System32;X:\Windows"
                $currentPSModulePath = "X:\Program Files\WindowsPowerShell\Modules;X:\Windows\System32\WindowsPowerShell\v1.0\Modules"
                $newPath = "$currentPath;$PowerShell7Path"
                $newPSModulePath = "$currentPSModulePath;$PowerShell7Path\Modules"
                $registryPath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\config\SOFTWARE"
                "$result" = reg load HKLM\WinPEOffline $registryPath
                if ("$LASTEXITCODE" -ne 0) {
                    throw "Failed to load registry hive: $result"
                }
                New-ItemProperty -Path "Registry::HKLM\WinPEOffline\Microsoft\Windows\CurrentVersion\Run" -Name "UpdatePath" -Value "cmd.exe /c set PATH=$newPath" -PropertyType String -Force -ErrorAction Stop | Out-Null
                New-ItemProperty -Path "Registry::HKLM\WinPEOffline\Microsoft\Windows\CurrentVersion\Run" -Name "UpdatePSModulePath" -Value "cmd.exe /c set PSModulePath=$newPSModulePath" -PropertyType String -Force -ErrorAction Stop | Out-Null
                [gc]::Collect()
                # Instead of a fixed sleep, you could adjust if needed.
                Start-Sleep -Seconds 1
                "$result" = reg unload HKLM\WinPEOffline
                if ("$LASTEXITCODE" -ne 0) {
                    throw "Failed to unload registry hive: $result"
                }
                Write-Log -Message "WinPE registry updated successfully" -Level Info -Component "Update-WinPERegistry"
                return $true
            }
            finally {
                Exit-CriticalSection -Mutex $mutex
            }
        }
        catch {
            $errorMessage = "Failed to update WinPE registry: $_"
            Write-Log -Message $errorMessage -Level Error -Component "Update-WinPERegistry" -Exception $_.Exception
            try { reg unload HKLM\WinPEOffline 2>"$null" } catch { }
            throw
        }
    }
}
function Update-WinPEStartup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path "$_" -PathType Container })]
        [string]"$MountPoint",
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$PowerShell7Path = "X:\Windows\System32\PowerShell7"
    )
    begin {
        Write-Log -Message "Updating WinPE startup configuration" -Level Info -Component "Update-WinPEStartup"
    }
    process {
        try {
            $mutex = Enter-CriticalSection -Name "WinPE_CustomizeStartnet"
            try {
                $startnetContent = @"
@echo off
cd\
set PATH=%PATH%;$PowerShell7Path
"$PowerShell7Path"\pwsh.exe -NoLogo -NoProfile
"@
                $startnetPath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\startnet.cmd"
                "$startnetContent" | Out-File -FilePath $startnetPath -Encoding ascii -Force -ErrorAction Stop
                Write-Log -Message "WinPE startup configuration updated successfully" -Level Info -Component "Update-WinPEStartup"
                return $true
            }
            finally {
                Exit-CriticalSection -Mutex $mutex
            }
        }
        catch {
            $errorMessage = "Failed to update WinPE startup configuration: $_"
            Write-Log -Message $errorMessage -Level Error -Component "Update-WinPEStartup" -Exception $_.Exception
            throw
        }
    }
}
function New-WinPEStartupProfile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = "$true")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path "$_" -PathType Container })]
        [string]$MountPoint
    )
    begin {
        Write-Log -Message "Creating WinPE startup profile" -Level Info -Component "New-WinPEStartupProfile"
    }
    process {
        try {
            $mutex = Enter-CriticalSection -Name "WinPE_CustomizeStartupProfile"
            try {
                $startupProfilePath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\StartupProfile"
                New-Item -Path "$startupProfilePath" -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Write-Log -Message "WinPE startup profile created successfully" -Level Info -Component "New-WinPEStartupProfile"
                return $true
            }
            finally {
                Exit-CriticalSection -Mutex $mutex
            }
        }
        catch {
            $errorMessage = "Failed to create WinPE startup profile: $_"
            Write-Log -Message $errorMessage -Level Error -Component "New-WinPEStartupProfile" -Exception $_.Exception
            throw
        }
    }
}