function Customize-WinPEWithPowerShell7 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TempPath,
        
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath,
        
        [Parameter(Mandatory = $true)]
        [string]$PowerShell7File
    )
    
    # Generate a unique ID for this execution instance
    $instanceId = [Guid]::NewGuid().ToString()
    $uniqueMountPoint = Join-Path -Path $TempPath -ChildPath "Mount_$instanceId"
    $lockFile = Join-Path -Path $env:TEMP -ChildPath "WinPE_Customize_Lock.mutex"
    $maxRetries = 5
    $retryDelayBase = 2
    
    # Helper function for retries with exponential backoff
    function Invoke-WithRetry {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [scriptblock]$ScriptBlock,
            
            [Parameter()]
            [string]$OperationName = "Operation",
            
            [Parameter()]
            [int]$MaxRetries = 5,
            
            [Parameter()]
            [int]$RetryDelayBase = 2
        )
        
        $retryCount = 0
        $completed = $false
        $returnValue = $null
        
        do {
            try {
                Write-Verbose "Attempting $OperationName (Attempt $(($retryCount + 1)))"
                $returnValue = & $ScriptBlock
                $completed = $true
            }
            catch {
                $retryCount++
                $ex = $_
                
                # Determine if error is retryable - extend this list as needed
                $retryableErrors = @(
                    "being used by another process",
                    "access is denied",
                    "cannot access the file",
                    "The process cannot access",
                    "The requested operation cannot be performed"
                )
                
                $isRetryable = $false
                foreach ($errorPattern in $retryableErrors) {
                    if ($ex.Exception.Message -match $errorPattern) {
                        $isRetryable = $true
                        break
                    }
                }
                
                if ($isRetryable -and $retryCount -lt $MaxRetries) {
                    # Calculate delay with jitter for exponential backoff
                    $delay = [math]::Pow($RetryDelayBase, $retryCount)
                    $jitter = Get-Random -Minimum -500 -Maximum 500
                    $delayMs = [math]::Max(1, ($delay * 1000) + $jitter)
                    
                    Write-Warning "$OperationName failed with retryable error: $($ex.Exception.Message)"
                    Write-Verbose "Retrying in $($delayMs / 1000) seconds..."
                    Start-Sleep -Milliseconds $delayMs
                }
                else {
                    # Not retryable or max retries exceeded
                    if ($retryCount -ge $MaxRetries) {
                        Write-Error "Max retries ($MaxRetries) exceeded for $OperationName"
                    }
                    else {
                        Write-Error "Non-retryable error in ${OperationName}: $($ex.Exception.Message)"
                    }
                    throw $ex
                }
            }
        } while (-not $completed)
        
        return $returnValue
    }
    
    # Mutex implementation for PowerShell (for critical sections)
    function Enter-CriticalSection {
        param([string]$Name, [int]$Timeout = 60)
        
        $mutex = $null
        $startTime = Get-Date
        $gotLock = $false
        
        try {
            # Create or open existing mutex
            $mutex = New-Object System.Threading.Mutex($false, "Global\$Name")
            
            # Try to acquire the mutex with timeout
            while (-not $gotLock) {
                # Check if we've exceeded timeout
                if ((New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds -gt $Timeout) {
                    throw "Timeout waiting for lock on $Name"
                }
                
                # Try to acquire with a short timeout to allow for periodic retry
                $gotLock = $mutex.WaitOne(5000)
                
                if (-not $gotLock) {
                    Write-Verbose "Waiting for lock on $Name..."
                    Start-Sleep -Milliseconds 500
                }
            }
            
            return $mutex
        }
        catch {
            if ($mutex) { $mutex.Close(); $mutex.Dispose() }
            throw "Failed to acquire lock: $_"
        }
    }
    
    function Exit-CriticalSection {
        param($Mutex)
        
        if ($Mutex) {
            try {
                $Mutex.ReleaseMutex()
                $Mutex.Close()
                $Mutex.Dispose()
            }
            catch {
                Write-Warning "Error releasing mutex: $_"
            }
        }
    }
    
    # Main execution starts here
    try {
        # Verify PowerShell 7 file exists
        if (-not (Test-Path -Path $PowerShell7File)) {
            throw "PowerShell 7 file not found at path: $PowerShell7File"
        }
        
        # Create unique temporary paths
        New-Item -Path $uniqueMountPoint -ItemType Directory -Force | Out-Null
        $ps7TempPath = Join-Path -Path $TempPath -ChildPath "PowerShell7_$instanceId"
        New-Item -Path $ps7TempPath -ItemType Directory -Force | Out-Null
        
        # Create StartupProfile folder (with mutex protection)
        $mutex = Enter-CriticalSection -Name "WinPE_CustomizeStartupProfile"
        try {
            $StartupProfilePath = Join-Path -Path $uniqueMountPoint -ChildPath "Windows\System32\StartupProfile"
            New-Item -Path $StartupProfilePath -ItemType Directory -Force | Out-Null
        }
        finally {
            Exit-CriticalSection -Mutex $mutex
        }
        
        # Mount WinPE Image (protected with retry logic due to potential file locking)
        $wimPath = Join-Path -Path $WorkspacePath -ChildPath "Media\Sources\boot.wim"
        Invoke-WithRetry -OperationName "Mount-WindowsImage" -ScriptBlock {
            Mount-WindowsImage -Path $uniqueMountPoint -ImagePath $wimPath -Index 1
        } -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
        
        # Extract PowerShell 7 to the mount point with retry logic
        Invoke-WithRetry -OperationName "Expand-Archive" -ScriptBlock {
            Expand-Archive -Path $PowerShell7File -DestinationPath $ps7TempPath -Force
            
            # Copy PowerShell 7 to the mount point (with mutex protection for shared PE image)
            $mutex = Enter-CriticalSection -Name "WinPE_CustomizeCopy"
            try {
                Copy-Item -Path "$ps7TempPath\*" -Destination "$uniqueMountPoint\Windows\System32\PowerShell7" -Recurse -Force
            }
            finally {
                Exit-CriticalSection -Mutex $mutex
            }
        } -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
        
        # Update registry and environment (with mutex protection)
        $mutex = Enter-CriticalSection -Name "WinPE_CustomizeRegistry"
        try {
            # Get current Path and PSModulePath
            $currentPath = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name Path).Path
            $currentPSModulePath = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PSModulePath).PSModulePath
            
            # Add PowerShell 7 to Path and update PSModulePath
            $newPath = "$currentPath;X:\Windows\System32\PowerShell7"
            $newPSModulePath = "$currentPSModulePath;X:\Windows\System32\PowerShell7\Modules"
            
            # Update the registry in the mounted WinPE image
            reg load HKLM\WinPEOffline "$uniqueMountPoint\Windows\System32\config\SOFTWARE"
            
            # Set the updated Path and PSModulePath in the registry
            New-ItemProperty -Path "Registry::HKLM\WinPEOffline\Microsoft\Windows\CurrentVersion\Run" -Name "UpdatePath" -Value "cmd.exe /c set PATH=$newPath" -PropertyType String -Force
            New-ItemProperty -Path "Registry::HKLM\WinPEOffline\Microsoft\Windows\CurrentVersion\Run" -Name "UpdatePSModulePath" -Value "cmd.exe /c set PSModulePath=$newPSModulePath" -PropertyType String -Force
            
            # Unload the registry hive
            reg unload HKLM\WinPEOffline
        }
        finally {
            Exit-CriticalSection -Mutex $mutex
        }
        
        # Add startnet.cmd to run PowerShell 7 on startup
        $startnetContent = @"
@echo off
cd\
set PATH=%PATH%;X:\Windows\System32\PowerShell7
X:\Windows\System32\PowerShell7\pwsh.exe -NoLogo -NoProfile
"@
        
        # Write the startnet.cmd file (with mutex protection)
        $mutex = Enter-CriticalSection -Name "WinPE_CustomizeStartnet"
        try {
            $startnetContent | Out-File -FilePath "$uniqueMountPoint\Windows\System32\startnet.cmd" -Encoding ascii -Force
        }
        finally {
            Exit-CriticalSection -Mutex $mutex
        }
        
        # Dismount WinPE Image with retry for locked files
        Invoke-WithRetry -OperationName "Dismount-WindowsImage" -ScriptBlock {
            Dismount-WindowsImage -Path $uniqueMountPoint -Save
        } -MaxRetries $maxRetries -RetryDelayBase $retryDelayBase
        
        # Return the boot.wim path
        return $wimPath
    }
    catch {
        Write-Error "Failed to customize WinPE: $_"
        
        # Try to dismount if mounted (don't save changes)
        try {
            if (Test-Path -Path $uniqueMountPoint) {
                Dismount-WindowsImage -Path $uniqueMountPoint -Discard -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "Error during cleanup: $_"
        }
        
        throw
    }
    finally {
        # Clean up temporary resources
        try {
            if (Test-Path -Path $uniqueMountPoint) {
                Remove-Item -Path $uniqueMountPoint -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            if (Test-Path -Path $ps7TempPath) {
                Remove-Item -Path $ps7TempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "Error cleaning up temporary resources: $_"
        }
    }
}