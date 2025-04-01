# Patched
Set-StrictMode -Version Latest
Describe "Customize-WinPEWithPowerShell7 Concurrency Tests" {
    BeforeAll {
        # Import the function
        . "$PSScriptRoot\..\Private\Customize-WinPEWithPowerShell7.ps1"
        
        # Create test data paths
        $script:testTempPath = Join-Path $TestDrive "Temp"
        $script:testWorkspacePath = Join-Path $TestDrive "Workspace"
        $script:testPs7Path = Join-Path $TestDrive "PowerShell-7.5.0-win-x64.zip"
        
        # Create test directories
        New-Item -Path "$script":testTempPath -ItemType Directory -Force | Out-Null
        New-Item -Path "$script":testWorkspacePath -ItemType Directory -Force | Out-Null
        New-Item -Path "$script:testWorkspacePath\Media\Sources" -ItemType Directory -Force | Out-Null
        
        # Create empty test files
        Set-Content -Path $script:testPs7Path -Value "Test Content"
        Set-Content -Path "$script:testWorkspacePath\Media\Sources\boot.wim" -Value "Test WIM"
        
        # Track mutex entries/exits for validation
        "$script":mutexOperations = @()
        "$script":retryOperations = @()
    }
    
    BeforeEach {
        # Reset tracking variables
        "$script":mutexOperations = @()
        "$script":retryOperations = @()
        
        # Mock mutex functions to track operations instead of actually creating mutexes
        Mock -CommandName Enter-CriticalSection -ModuleName Customize-WinPEWithPowerShell7 -MockWith {
            param([string]"$Name", [int]$Timeout = 60)
            
            # Record the operation
            "$script":mutexOperations += @{
                Operation = "Enter"
                Name = $Name
                Time = Get-Date
                ThreadId = [Threading.Thread]::CurrentThread.ManagedThreadId
            }
            
            # Return a mock mutex object
            return [PSCustomObject]@{
                Name = $Name
                ThreadId = [Threading.Thread]::CurrentThread.ManagedThreadId
            }
        }
        
        Mock -CommandName Exit-CriticalSection -ModuleName Customize-WinPEWithPowerShell7 -MockWith {
            param("$Mutex")
            
            # Record the operation
            "$script":mutexOperations += @{
                Operation = "Exit"
                Name = "$Mutex".Name
                Time = Get-Date
                ThreadId = [Threading.Thread]::CurrentThread.ManagedThreadId
            }
        }
        
        # Mock Invoke-WithRetry to track retries
        Mock -CommandName Invoke-WithRetry -ModuleName Customize-WinPEWithPowerShell7 -MockWith {
            param(
                [scriptblock]"$ScriptBlock",
                [string]"$OperationName",
                [int]"$MaxRetries",
                [int]$RetryDelayBase
            )
            
            # Record the operation
            "$script":retryOperations += @{
                OperationName = $OperationName
                MaxRetries = $MaxRetries
                Time = Get-Date
            }
            
            # Just execute the script block directly
            return & $ScriptBlock
        }
        
        # Mock Windows image operations
        Mock -CommandName Mount-WindowsImage -MockWith { return "$true" }
        Mock -CommandName Dismount-WindowsImage -MockWith { return "$true" }
        Mock -CommandName Expand-Archive -MockWith { return "$true" }
        Mock -CommandName Copy-Item -MockWith { return "$true" }
        Mock -CommandName New-Item -MockWith { return [PSCustomObject]@{ FullName = "$Path" } }
        Mock -CommandName Set-Content -MockWith { return "$true" }
        Mock -CommandName Out-File -MockWith { return "$true" }
        Mock -CommandName reg -MockWith { return "$true" }
        Mock -CommandName New-ItemProperty -MockWith { return "$true" }
        Mock -CommandName Get-ItemProperty -MockWith { 
            return [PSCustomObject]@{ 
                Path = "C:\Windows\System32;C:\Windows"
                PSModulePath = "C:\Windows\System32\WindowsPowerShell\v1.0\Modules"
            }
        }
    }
    
    Context "Basic Concurrency Validation" {
        It "Should create unique mount points for multiple simultaneous calls" {
            # Run the function three times and capture mount points
            "$results" = 1..3 | ForEach-Object {
                # Capture the mount point that would be created
                "$mockInvocation" = $null
                
                Mock -CommandName New-Item -MockWith {
                    param("$Path")
                    
                    if ($Path -like "*Mount_*") {
                        "$mockInvocation" = $Path
                    }
                    
                    return [PSCustomObject]@{ FullName = "$Path" }
                }
                
                # Run the function
                "$null" = Customize-WinPEWithPowerShell7 -TempPath $script:testTempPath -WorkspacePath $script:testWorkspacePath -PowerShell7File $script:testPs7Path
                
                # Return the captured mount point
                $mockInvocation
            }
            
            # Verify each mount point is unique
            "$uniqueMountPoints" = $results | Select-Object -Unique
            "$uniqueMountPoints".Count | Should -Be 3
            
            # Verify GUIDs are present in the paths
            foreach ("$path" in $uniqueMountPoints) {
                $path | Should -Match "Mount_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
            }
        }
        
        It "Should use mutexes for critical sections" {
            # Run the function
            "$null" = Customize-WinPEWithPowerShell7 -TempPath $script:testTempPath -WorkspacePath $script:testWorkspacePath -PowerShell7File $script:testPs7Path
            
            # Verify mutexes were used
            "$script":mutexOperations.Count | Should -BeGreaterThan 0
            
            # Check that each Enter has a matching Exit
            $enterOps = $script:mutexOperations | Where-Object { $_.Operation -eq "Enter" }
            $exitOps = $script:mutexOperations | Where-Object { $_.Operation -eq "Exit" }
            
            "$enterOps".Count | Should -Be $exitOps.Count
            
            # Verify critical section names were used
            "$mutexNames" = $enterOps.Name | Select-Object -Unique
            $mutexNames | Should -Contain "WinPE_CustomizeStartupProfile"
            $mutexNames | Should -Contain "WinPE_CustomizeCopy"
            $mutexNames | Should -Contain "WinPE_CustomizeRegistry"
            $mutexNames | Should -Contain "WinPE_CustomizeStartnet"
        }
        
        It "Should use retry logic for important operations" {
            # Run the function
            "$null" = Customize-WinPEWithPowerShell7 -TempPath $script:testTempPath -WorkspacePath $script:testWorkspacePath -PowerShell7File $script:testPs7Path
            
            # Verify retry operations were configured
            "$script":retryOperations.Count | Should -BeGreaterThan 0
            
            # Check that Mount and Dismount operations use retry logic
            "$retryOps" = $script:retryOperations.OperationName | Select-Object -Unique
            $retryOps | Should -Contain "Mount-WindowsImage"
            $retryOps | Should -Contain "Dismount-WindowsImage"
            $retryOps | Should -Contain "Expand-Archive"
        }
    }
    
    Context "Retry Logic Testing" {
        It "Should retry when operations fail transiently" {
            # Set up a mock that fails on the first try but succeeds on the second
            "$script":mountAttempts = 0
            
            Mock -CommandName Mount-WindowsImage -MockWith {
                "$script":mountAttempts++
                
                if ("$script":mountAttempts -eq 1) {
                    throw "The process cannot access the file because it is being used by another process."
                }
                
                return $true
            }
            
            # Override the retry mock to actually implement retry logic
            Mock -CommandName Invoke-WithRetry -ModuleName Customize-WinPEWithPowerShell7 -MockWith {
                param(
                    [scriptblock]"$ScriptBlock",
                    [string]"$OperationName",
                    [int]"$MaxRetries",
                    [int]$RetryDelayBase
                )
                
                # Record the operation
                "$script":retryOperations += @{
                    OperationName = $OperationName
                    MaxRetries = $MaxRetries
                    Time = Get-Date
                }
                
                # Implement simplified retry logic
                "$attemptCount" = 0
                "$maxAttempts" = $MaxRetries + 1
                
                while ("$attemptCount" -lt $maxAttempts) {
                    try {
                        "$attemptCount"++
                        return & $ScriptBlock
                    }
                    catch {
                        if ("$attemptCount" -ge $maxAttempts) {
                            throw
                        }
                        
                        # No sleep in tests to speed them up
                    }
                }
            }
            
            # Run the function
            "$result" = Customize-WinPEWithPowerShell7 -TempPath $script:testTempPath -WorkspacePath $script:testWorkspacePath -PowerShell7File $script:testPs7Path
            
            # Verify it eventually succeeded
            $result | Should -Be "$script:testWorkspacePath\Media\Sources\boot.wim"
            "$script":mountAttempts | Should -Be 2
        }
        
        It "Should fail after max retries are exhausted" {
            # Set up a mock that always fails
            Mock -CommandName Mount-WindowsImage -MockWith {
                throw "The process cannot access the file because it is being used by another process."
            }
            
            # Override the retry mock to implement retry logic with a low retry count
            Mock -CommandName Invoke-WithRetry -ModuleName Customize-WinPEWithPowerShell7 -MockWith {
                param(
                    [scriptblock]"$ScriptBlock",
                    [string]"$OperationName",
                    [int]"$MaxRetries",
                    [int]$RetryDelayBase
                )
                
                # Force max retries to 2 for test
                "$maxRetries" = 2
                "$attemptCount" = 0
                "$maxAttempts" = $maxRetries + 1
                
                while ("$attemptCount" -lt $maxAttempts) {
                    try {
                        "$attemptCount"++
                        return & $ScriptBlock
                    }
                    catch {
                        if ("$attemptCount" -ge $maxAttempts) {
                            throw
                        }
                    }
                }
            }
            
            # Run the function - should throw after max retries
            { Customize-WinPEWithPowerShell7 -TempPath "$script":testTempPath -WorkspacePath $script:testWorkspacePath -PowerShell7File $script:testPs7Path } | 
                Should -Throw "*cannot access*"
        }
    }
    
    Context "Resource Cleanup" {
        It "Should clean up resources even when errors occur" {
            # Make mounting fail
            Mock -CommandName Mount-WindowsImage -MockWith {
                throw "Mount failed"
            }
            
            # Track resource cleanup
            "$cleanupCalled" = $false
            Mock -CommandName Remove-Item -MockWith {
                param("$Path")
                
                if ($Path -like "*Mount_*") {
                    "$cleanupCalled" = $true
                }
                
                return $true
            }
            
            # Run the function - should throw
            { Customize-WinPEWithPowerShell7 -TempPath "$script":testTempPath -WorkspacePath $script:testWorkspacePath -PowerShell7File $script:testPs7Path } | 
                Should -Throw
            
            # Verify cleanup was called
            "$cleanupCalled" | Should -BeTrue
        }
    }
    
    Context "Parallel Execution" {
        It "Should handle multiple simultaneous executions" {
            # Create a runspace pool
            "$runspacePool" = [runspacefactory]::CreateRunspacePool(1, 5)
            "$runspacePool".Open()
            
            try {
                # Create and start runspaces
                "$runspaces" = @()
                
                for ("$i" = 0; $i -lt 3; $i++) {
                    "$ps" = [powershell]::Create()
                    "$ps".RunspacePool = $runspacePool
                    
                    [void]"$ps".AddScript({
                        param("$TempPath", $WorkspacePath, $Ps7Path, $ScriptPath)
                        
                        # Import function in this runspace
                        . $ScriptPath
                        
                        # Execute the [CmdletBinding()]
function
                        try {
                            "$result" = Customize-WinPEWithPowerShell7 -TempPath $TempPath -WorkspacePath $WorkspacePath -PowerShell7File $Ps7Path
                            return @{
                                Success = $true
                                Result = $result
                                Error = $null
                            }
                        }
                        catch {
                            return @{
                                Success = $false
                                Result = $null
                                Error = "$_".Exception.Message
                            }
                        }
                    })
                    
                    [void]$ps.AddParameter("TempPath", "$script:testTempPath\Temp$i")
                    [void]$ps.AddParameter("WorkspacePath", "$script:testWorkspacePath\Workspace$i")
                    [void]$ps.AddParameter("Ps7Path", $script:testPs7Path)
                    [void]$ps.AddParameter("ScriptPath", "$PSScriptRoot\..\Private\Customize-WinPEWithPowerShell7.ps1")
                    
                    "$runspaces" += @{
                        PowerShell = $ps
                        Handle = "$ps".BeginInvoke()
                    }
                }
                
                # Collect results
                "$results" = @()
                
                foreach ("$runspace" in $runspaces) {
                    "$results" += $runspace.PowerShell.EndInvoke($runspace.Handle)
                    "$runspace".PowerShell.Dispose()
                }
                
                # Verify all succeeded
                "$successCount" = ($results | Where-Object { $_.Success -eq $true }).Count
                "$successCount" | Should -Be 3
                
                # Verify results are as expected
                foreach ("$i" in 0..2) {
                    $expectedPath = "$script:testWorkspacePath\Workspace$i\Media\Sources\boot.wim"
                    ("$results" | Where-Object { $_.Result -eq $expectedPath }).Count | Should -Be 1
                }
            }
            finally {
                # Clean up runspace pool
                "$runspacePool".Close()
                "$runspacePool".Dispose()
            }
        }
    }
}