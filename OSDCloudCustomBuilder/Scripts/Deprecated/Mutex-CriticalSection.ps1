<#
.SYNOPSIS
    Provides mutex functionality for critical sections in PowerShell.
.DESCRIPTION
    This module implements mutex functionality for critical sections in PowerShell.
    It provides functions to enter and exit critical sections, ensuring that only one
    process or thread can execute a specific section of code at a time.
.EXAMPLE
    $mutex = Enter-CriticalSection -Name "MyOperation"
    try {
        # Critical section code here
    }
    finally {
        Exit-CriticalSection -Mutex $mutex
    }
.NOTES
    These functions are used internally by the OSDCloudCustomBuilder module.
#>

<#
.SYNOPSIS
    Enters a critical section by acquiring a named mutex.
.DESCRIPTION
    Enters a critical section by acquiring a named mutex. This ensures that only one
    process or thread can execute the critical section at a time.
.PARAMETER Name
    The name of the mutex to acquire.
.PARAMETER Timeout
    The maximum time in seconds to wait for the mutex to be acquired.
.EXAMPLE
    $mutex = Enter-CriticalSection -Name "MyOperation"
    try {
        # Critical section code here
    }
    finally {
        Exit-CriticalSection -Mutex $mutex
    }
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function Enter-CriticalSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter()]
        [int]$Timeout = 60
    )
    
    begin {
        $mutex = $null
        $startTime = Get-Date
        $gotLock = $false
        
        # Log operation start
        if ($script:LoggerExists) {        # Log operation start
        if ($script:LoggerExists) {
            Invoke-OSDCloudLogger -Message "Attempting to enter critical section '$Name'" -Level Verbose -Component "Enter-CriticalSection"
        }
    }
    
    process {
        try {
            # Create or open existing mutex
            $mutex = New-Object System.Threading.Mutex($false, "Global\$Name")
            
            # Try to acquire the mutex with timeout
            while (-not $gotLock) {
                # Check if we've exceeded timeout
                if ((New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds -gt $Timeout) {
                    $errorMessage = "Timeout waiting for lock on $Name"
                    if ($script:LoggerExists) {
                        Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Enter-CriticalSection"
                    }
                    throw $errorMessage
                }
                
                # Try to acquire with a short timeout to allow for periodic retry
                $gotLock = $mutex.WaitOne(5000)
                
                if (-not $gotLock) {
                    $waitMessage = "Waiting for lock on $Name..."
                    if ($script:LoggerExists) {
                        Invoke-OSDCloudLogger -Message $waitMessage -Level Verbose -Component "Enter-CriticalSection"
                    }
                    else {
                        Write-Verbose $waitMessage
                    }
                    Start-Sleep -Milliseconds 500
                }
            }
            
            # Log success
            if ($script:LoggerExists) {
                Invoke-OSDCloudLogger -Message "Successfully entered critical section '$Name'" -Level Verbose -Component "Enter-CriticalSection"
            }
            
            return $mutex
        }
        catch {
            if ($mutex) { 
                try {
                    $mutex.Close()
                    $mutex.Dispose()
                }
                catch {
                    # Ignore errors during cleanup
                }
            }
            
            $errorMessage = "Failed to acquire lock: $_"
            if ($script:LoggerExists) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Enter-CriticalSection" -Exception $_.Exception
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
    Exits a critical section by releasing a mutex.
.DESCRIPTION
    Exits a critical section by releasing a mutex. This allows other processes or threads
    to enter the critical section.
.PARAMETER Mutex
    The mutex object to release.
.EXAMPLE
    $mutex = Enter-CriticalSection -Name "MyOperation"
    try {
        # Critical section code here
    }
    finally {
        Exit-CriticalSection -Mutex $mutex
    }
.NOTES
    This function is used internally by the OSDCloudCustomBuilder module.
#>
function Exit-CriticalSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Threading.Mutex]$Mutex
    )
    
    begin {
        # Log operation start
        if ($script:LoggerExists) {
            Invoke-OSDCloudLogger -Message "Exiting critical section" -Level Verbose -Component "Exit-CriticalSection"
        }
    }
    
    process {
        if ($Mutex) {
            try {
                $Mutex.ReleaseMutex()
                $Mutex.Close()
                $Mutex.Dispose()
                
                # Log success
                if ($script:LoggerExists) {
                    Invoke-OSDCloudLogger -Message "Successfully exited critical section" -Level Verbose -Component "Exit-CriticalSection"
                }
            }
            catch {
                $errorMessage = "Error releasing mutex: $_"
                if ($script:LoggerExists) {
                    Invoke-OSDCloudLogger -Message $errorMessage -Level Warning -Component "Exit-CriticalSection" -Exception $_.Exception
                }
                else {
                    Write-Warning $errorMessage
                }
            }
        }
    }
}