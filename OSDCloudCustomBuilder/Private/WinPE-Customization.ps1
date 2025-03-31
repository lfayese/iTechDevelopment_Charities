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
function Initialize-WinPEMountPoint {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TempPath,
        
        [Parameter()]
        [string]$InstanceId = [Guid]::NewGuid().ToString()
    )
    
    begin {
        # Log operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "Initializing WinPE mount point in $TempPath" -Level Info -Component "Initialize-WinPEMountPoint"
        }
    }
    
    process {
        try {
            # Create unique temporary paths
            $uniqueMountPoint = Join-Path -Path $TempPath -ChildPath "Mount_$InstanceId"
            $ps7TempPath = Join-Path -Path $TempPath -ChildPath "PowerShell7_$InstanceId"
            
            # Create directories
            if (-not (Test-Path -Path $uniqueMountPoint)) {
                New-Item -Path $uniqueMountPoint -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            
            if (-not (Test-Path -Path $ps7TempPath)) {
                New-Item -Path $ps7TempPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            
            # Log success
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "WinPE mount point initialized successfully" -Level Info -Component "Initialize-WinPEMountPoint"
            }
            
            # Return the paths
            return @{
                MountPoint = $uniqueMountPoint
                PS7TempPath = $ps7TempPath
                InstanceId = $InstanceId
            }
        }
        catch {
            $errorMessage = "Failed to initialize WinPE mount point: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Initialize-WinPEMountPoint" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            throw
        }
    }
}

<#
.SYNOPSIS
    Mounts a Windows image (WIM) file for customization.
.DESCRIPTION
    Mounts a Windows image (WIM) file at the specified mount point for customization.
    This function uses retry logic to handle potential file locking issues.
.PARAMETER ImagePath
    The path to the WIM file to mount.
.PARAMETER MountPath
    The path where the WIM file will be mounted.
.PARAMETER Index
    The index of the image within the WIM file to mount. Default is 1.
.EXAMPLE
    Mount-WinPEImage -ImagePath "C:\OSDCloud\boot.wim" -MountPath "C:\Temp\OSDCloud\Mount"
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function Mount-WinPEImage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ImagePath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$MountPath,
        
        [Parameter()]
        [int]$Index = 1
    )
    
    begin {
        # Log operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "Mounting WIM file $ImagePath to $MountPath" -Level Info -Component "Mount-WinPEImage"
        }
        
        # Get retry settings from config if available
        try {
            $config = Get-OSDCloudConfig -ErrorAction SilentlyContinue
            $maxRetries = if ($config -and $config.MaxRetryAttempts) { $config.MaxRetryAttempts } else { 5 }
            $retryDelayBase = if ($config -and $config.RetryDelaySeconds) { $config.RetryDelaySeconds } else { 2 }
        }
        catch {
            $maxRetries = 5
            $retryDelayBase = 2
        }
    }
    
    process {
        try {
            # Use retry logic for mounting
            Invoke-WithRetry -ScriptBlock {
                Mount-WindowsImage -Path $MountPath -ImagePath $ImagePath -Index $Index -ErrorAction Stop
            } -OperationName "Mount-WindowsImage" -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
            
            # Log success
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "WIM file mounted successfully" -Level Info -Component "Mount-WinPEImage"
            }
            
            return $true
        }
        catch {
            $errorMessage = "Failed to mount WIM file: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Mount-WinPEImage" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            throw
        }
    }
}

<#
.SYNOPSIS
    Dismounts a Windows image (WIM) file.
.DESCRIPTION
    Dismounts a Windows image (WIM) file from the specified mount point.
    This function uses retry logic to handle potential file locking issues.
.PARAMETER MountPath
    The path where the WIM file is mounted.
.PARAMETER Save
    If specified, changes made to the mounted image will be saved.
.PARAMETER Discard
    If specified, changes made to the mounted image will be discarded.
.EXAMPLE
    Dismount-WinPEImage -MountPath "C:\Temp\OSDCloud\Mount" -Save
.EXAMPLE
    Dismount-WinPEImage -MountPath "C:\Temp\OSDCloud\Mount" -Discard
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function Dismount-WinPEImage {
    [CmdletBinding(DefaultParameterSetName = 'Save')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$MountPath,
        
        [Parameter(ParameterSetName = 'Save')]
        [switch]$Save = $true,
        
        [Parameter(ParameterSetName = 'Discard')]
        [switch]$Discard
    )
    
    begin {
        # Log operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            $action = if ($Discard) { "discarding" } else { "saving" }
            Invoke-OSDCloudLogger -Message "Dismounting WIM file from $MountPath ($action changes)" -Level Info -Component "Dismount-WinPEImage"
        }
        
        # Get retry settings from config if available
        try {
            $config = Get-OSDCloudConfig -ErrorAction SilentlyContinue
            $maxRetries = if ($config -and $config.MaxRetryAttempts) { $config.MaxRetryAttempts } else { 5 }
            $retryDelayBase = if ($config -and $config.RetryDelaySeconds) { $config.RetryDelaySeconds } else { 2 }
        }
        catch {
            $maxRetries = 5
            $retryDelayBase = 2
        }
    }
    
    process {
        try {
            # Use retry logic for dismounting
            Invoke-WithRetry -ScriptBlock {
                if ($Discard) {
                    Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction Stop
                }
                else {
                    Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop
                }
            } -OperationName "Dismount-WindowsImage" -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
            
            # Log success
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "WIM file dismounted successfully" -Level Info -Component "Dismount-WinPEImage"
            }
            
            return $true
        }
        catch {
            $errorMessage = "Failed to dismount WIM file: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Dismount-WinPEImage" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            throw
        }
    }
}

<#
.SYNOPSIS
    Extracts PowerShell 7 files to a WinPE image.
.DESCRIPTION
    Extracts PowerShell 7 files from a zip archive and copies them to a mounted WinPE image.
    This function handles the extraction and copying process with proper error handling.
.PARAMETER PowerShell7File
    The path to the PowerShell 7 zip archive.
.PARAMETER TempPath
    The temporary path where PowerShell 7 files will be extracted.
.PARAMETER MountPoint
    The path where the WinPE image is mounted.
.EXAMPLE
    Install-PowerShell7ToWinPE -PowerShell7File "C:\Temp\PowerShell-7.3.4-win-x64.zip" -TempPath "C:\Temp\PS7" -MountPoint "C:\Temp\Mount"
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function Install-PowerShell7ToWinPE {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$PowerShell7File,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$TempPath,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$MountPoint
    )
    
    begin {
        # Log operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "Installing PowerShell 7 to WinPE" -Level Info -Component "Install-PowerShell7ToWinPE"
        }
        
        # Get retry settings from config if available
        try {
            $config = Get-OSDCloudConfig -ErrorAction SilentlyContinue
            $maxRetries = if ($config -and $config.MaxRetryAttempts) { $config.MaxRetryAttempts } else { 5 }
            $retryDelayBase = if ($config -and $config.RetryDelaySeconds) { $config.RetryDelaySeconds } else { 2 }
        }
        catch {
            $maxRetries = 5
            $retryDelayBase = 2
        }
    }
    
    process {
        try {
            # Extract PowerShell 7 to the temp path
            Invoke-WithRetry -ScriptBlock {
                Expand-Archive -Path $PowerShell7File -DestinationPath $TempPath -Force -ErrorAction Stop
            } -OperationName "Expand-Archive" -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
            
            # Create PowerShell7 directory in the mount point
            $ps7Directory = Join-Path -Path $MountPoint -ChildPath "Windows\System32\PowerShell7"
            if (-not (Test-Path -Path $ps7Directory)) {
                New-Item -Path $ps7Directory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            
            # Copy PowerShell 7 to the mount point (with mutex protection for shared PE image)
            $mutex = Enter-CriticalSection -Name "WinPE_CustomizeCopy"
            try {
                Invoke-WithRetry -ScriptBlock {
                    Copy-Item -Path "$TempPath\*" -Destination $ps7Directory -Recurse -Force -ErrorAction Stop
                } -OperationName "Copy-PowerShell7Files" -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
            }
            finally {
                Exit-CriticalSection -Mutex $mutex
            }
            
            # Log success
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message "PowerShell 7 installed successfully to WinPE" -Level Info -Component "Install-PowerShell7ToWinPE"
            }
            
            return $true
        }
        catch {
            $errorMessage = "Failed to install PowerShell 7 to WinPE: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Install-PowerShell7ToWinPE" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            throw
        }
    }
}

<#
.SYNOPSIS
    Updates registry settings in a mounted WinPE image.
.DESCRIPTION
    Updates registry settings in a mounted WinPE image to configure PowerShell 7 integration.
    This function handles registry loading, modification, and unloading with proper error handling.
.PARAMETER MountPoint
    The path where the WinPE image is mounted.
.PARAMETER PowerShell7Path
    The path where PowerShell 7 will be installed in the WinPE environment.
.EXAMPLE
    Update-WinPERegistry -MountPoint "C:\Temp\Mount" -PowerShell7Path "X:\Windows\System32\PowerShell7"
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function Update-WinPERegistry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$MountPoint,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PowerShell7Path = "X:\Windows\System32\PowerShell7"
    )
    
    begin {
        # Log operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "Updating WinPE registry settings" -Level Info -Component "Update-WinPERegistry"
        }
    }
    
    process {
        try {
            # Use mutex to protect registry operations
            $mutex = Enter-CriticalSection -Name "WinPE_CustomizeRegistry"
            try {
                # Get current Path and PSModulePath
                $currentPath = "X:\Windows\System32;X:\Windows"
                $currentPSModulePath = "X:\Program Files\WindowsPowerShell\Modules;X:\Windows\System32\WindowsPowerShell\v1.0\Modules"
                
                # Add PowerShell 7 to Path and update PSModulePath
                $newPath = "$currentPath;$PowerShell7Path"
                $newPSModulePath = "$currentPSModulePath;$PowerShell7Path\Modules"
                
                # Update the registry in the mounted WinPE image
                $registryPath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\config\SOFTWARE"
                
                # Load the registry hive
                $result = reg load HKLM\WinPEOffline $registryPath
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to load registry hive: $result"
                }
                
                # Set the updated Path and PSModulePath in the registry
                New-ItemProperty -Path "Registry::HKLM\WinPEOffline\Microsoft\Windows\CurrentVersion\Run" -Name "UpdatePath" -Value "cmd.exe /c set PATH=$newPath" -PropertyType String -Force -ErrorAction Stop | Out-Null
                New-ItemProperty -Path "Registry::HKLM\WinPEOffline\Microsoft\Windows\CurrentVersion\Run" -Name "UpdatePSModulePath" -Value "cmd.exe /c set PSModulePath=$newPSModulePath" -PropertyType String -Force -ErrorAction Stop | Out-Null
                
                # Unload the registry hive
                [gc]::Collect()
                Start-Sleep -Seconds 1
                $result = reg unload HKLM\WinPEOffline
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to unload registry hive: $result"
                }
                
                # Log success
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "WinPE registry updated successfully" -Level Info -Component "Update-WinPERegistry"
                }
                
                return $true
            }
            finally {
                Exit-CriticalSection -Mutex $mutex
            }
        }
        catch {
            $errorMessage = "Failed to update WinPE registry: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Update-WinPERegistry" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            
            # Try to unload the registry hive if it might be loaded
            try {
                reg unload HKLM\WinPEOffline 2>$null
            }
            catch {
                # Ignore errors during cleanup
            }
            
            throw
        }
    }
}

<#
.SYNOPSIS
    Updates the startup configuration in a mounted WinPE image.
.DESCRIPTION
    Updates the startup configuration in a mounted WinPE image to launch PowerShell 7 on startup.
    This function creates or modifies the startnet.cmd file with proper error handling.
.PARAMETER MountPoint
    The path where the WinPE image is mounted.
.PARAMETER PowerShell7Path
    The path where PowerShell 7 will be installed in the WinPE environment.
.EXAMPLE
    Update-WinPEStartup -MountPoint "C:\Temp\Mount" -PowerShell7Path "X:\Windows\System32\PowerShell7"
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function Update-WinPEStartup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$MountPoint,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PowerShell7Path = "X:\Windows\System32\PowerShell7"
    )
    
    begin {
        # Log operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "Updating WinPE startup configuration" -Level Info -Component "Update-WinPEStartup"
        }
    }
    
    process {
        try {
            # Use mutex to protect startnet.cmd file
            $mutex = Enter-CriticalSection -Name "WinPE_CustomizeStartnet"
            try {
                # Create startnet.cmd content
                $startnetContent = @"
@echo off
cd\
set PATH=%PATH%;$PowerShell7Path
$PowerShell7Path\pwsh.exe -NoLogo -NoProfile
"@
                
                # Write the startnet.cmd file
                $startnetPath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\startnet.cmd"
                $startnetContent | Out-File -FilePath $startnetPath -Encoding ascii -Force -ErrorAction Stop
                
                # Log success
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "WinPE startup configuration updated successfully" -Level Info -Component "Update-WinPEStartup"
                }
                
                return $true
            }
            finally {
                Exit-CriticalSection -Mutex $mutex
            }
        }
        catch {
            $errorMessage = "Failed to update WinPE startup configuration: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Update-WinPEStartup" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            throw
        }
    }
}

<#
.SYNOPSIS
    Creates a startup profile directory in a mounted WinPE image.
.DESCRIPTION
    Creates a startup profile directory in a mounted WinPE image for PowerShell 7 configuration.
    This function handles directory creation with proper error handling.
.PARAMETER MountPoint
    The path where the WinPE image is mounted.
.EXAMPLE
    New-WinPEStartupProfile -MountPoint "C:\Temp\Mount"
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function New-WinPEStartupProfile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$MountPoint
    )
    
    begin {
        # Log operation start
        if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
            Invoke-OSDCloudLogger -Message "Creating WinPE startup profile" -Level Info -Component "New-WinPEStartupProfile"
        }
    }
    
    process {
        try {
            # Use mutex to protect directory creation
            $mutex = Enter-CriticalSection -Name "WinPE_CustomizeStartupProfile"
            try {
                # Create StartupProfile directory
                $startupProfilePath = Join-Path -Path $MountPoint -ChildPath "Windows\System32\StartupProfile"
                if (-not (Test-Path -Path $startupProfilePath)) {
                    New-Item -Path $startupProfilePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
                
                # Log success
                if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                    Invoke-OSDCloudLogger -Message "WinPE startup profile created successfully" -Level Info -Component "New-WinPEStartupProfile"
                }
                
                return $true
            }
            finally {
                Exit-CriticalSection -Mutex $mutex
            }
        }
        catch {
            $errorMessage = "Failed to create WinPE startup profile: $_"
            if (Get-Command -Name Invoke-OSDCloudLogger -ErrorAction SilentlyContinue) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "New-WinPEStartupProfile" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            throw
        }
    }
}