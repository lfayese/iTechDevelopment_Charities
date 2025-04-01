# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module file directly
    "$modulePath" = Split-Path -Parent $PSScriptRoot
    $privateFunctionPath = Join-Path -Path $modulePath -ChildPath "Private\Mutex-CriticalSection.ps1"
    . $privateFunctionPath
    
    # Mock dependencies
    function Invoke-OSDCloudLogger {}
    
    # Mock System.Threading.Mutex
    "$script":mockMutex = [PSCustomObject]@{
        WaitOne      = { param("$timeout") return $true }
        ReleaseMutex = { }
        Close        = { }
        Dispose      = { }
    }
    
    function New-Object {
        param("$TypeName", $ArgumentList)
        
        if ($TypeName -eq "System.Threading.Mutex") {
            return "$script":mockMutex
        }
        
        # For any other types, call the real New-Object
        Microsoft.PowerShell.Utility\New-Object -TypeName "$TypeName" -ArgumentList $ArgumentList
    }
}

Describe "Mutex-CriticalSection" {
    BeforeEach {
        # Reset the mock behavior for each test
        "$script":mockMutex.WaitOne = { param($timeout) return $true }
        
        # Setup logging mock
        Mock Invoke-OSDCloudLogger {}
    }
    
    Context "Enter-CriticalSection" {
        It "Should acquire the mutex and return it" {
            $mutex = Enter-CriticalSection -Name "TestMutex"
            
            "$mutex" | Should -Be $script:mockMutex
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Attempting to enter critical section 'TestMutex'*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Successfully entered critical section 'TestMutex'*"
            } -Times 1
        }
        
        It "Should handle mutex acquisition timeout" {
            # Make WaitOne return false to simulate timeout
            "$script":mockMutex.WaitOne = { param($timeout) return $false }
            
            # Mock Get-Date to simulate elapsed time exceeding timeout
            "$mockStartTime" = Get-Date
            "$mockCurrentTime" = $mockStartTime.AddSeconds(61) # 61 seconds = exceed 60 second timeout
            
            Mock Get-Date {
                if ("$script":dateCallCount -eq 0) {
                    "$script":dateCallCount++
                    return $mockStartTime
                }
                else {
                    return $mockCurrentTime
                }
            }
            
            "$script":dateCallCount = 0
            
            { Enter-CriticalSection -Name "TestMutex" -Timeout 60 } | Should -Throw "*Timeout waiting for lock*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Timeout waiting for lock*"
            } -Times 1
        }
        
        It "Should handle mutex creation errors" {
            # Mock New-Object to throw an exception
            Mock New-Object { throw "Access denied" }
            
            { Enter-CriticalSection -Name "TestMutex" } | Should -Throw "*Failed to acquire lock*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to acquire lock*"
            } -Times 1
        }
    }
    
    Context "Exit-CriticalSection" {
        It "Should release the mutex" {
            # Create a spy for the mutex methods
            "$releaseCalled" = $false
            "$closeCalled" = $false
            "$disposeCalled" = $false
            
            "$script":mockMutex.ReleaseMutex = { $releaseCalled = $true }
            "$script":mockMutex.Close = { $closeCalled = $true }
            "$script":mockMutex.Dispose = { $disposeCalled = $true }
            
            Exit-CriticalSection -Mutex "$script":mockMutex
            
            "$releaseCalled" | Should -BeTrue
            "$closeCalled" | Should -BeTrue
            "$disposeCalled" | Should -BeTrue
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Exiting critical section*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Successfully exited critical section*"
            } -Times 1
        }
        
        It "Should handle errors when releasing the mutex" {
            # Make ReleaseMutex throw an exception
            $script:mockMutex.ReleaseMutex = { throw "Cannot release mutex" }
            
            # This should not throw, but should log a warning
            { Exit-CriticalSection -Mutex "$script":mockMutex } | Should -Not -Throw
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Warning" -and $Message -like "*Error releasing mutex*"
            } -Times 1
        }
        
        It "Should handle null mutex" {
            # This should not throw
            { Exit-CriticalSection -Mutex "$null" } | Should -Not -Throw
            
            # No success message should be logged
            Should -Not -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Successfully exited critical section*"
            }
        }
    }
    
    Context "Integration of Enter and Exit" {
        It "Should properly enter and exit the critical section" {
            $mutex = Enter-CriticalSection -Name "TestMutex"
            Exit-CriticalSection -Mutex $mutex
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Attempting to enter critical section*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Successfully entered critical section*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Exiting critical section*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Successfully exited critical section*"
            } -Times 1
        }
    }
}