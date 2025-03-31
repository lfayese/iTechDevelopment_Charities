Describe "Customize-WinPEWithPowerShell7 Concurrency Tests" {
    BeforeAll {
        # Initialize a common test environment
        $script:testEnv = Initialize-TestEnvironment -TestName "Concurrency"
        # Reset counter for retry logic
        $script:mountAttempts = 0
        # Set up the mocks
        Mock Mount-WindowsImage {
            $script:mountAttempts++
            # Simulate a transient error on the first attempt
            if ($script:mountAttempts -eq 1) {
                throw "The process cannot access the file because it is being used by another process."
            }
            return $true
        }
        Mock Dismount-WindowsImage { return $true }
        Mock Expand-Archive { return $true }
        Mock Copy-Item { return $true }
        Mock reg { return $true }
        Mock New-ItemProperty { return $true }
        Mock Out-File { return $true }
        Mock Get-ItemProperty { return @{ Path = "C:\Windows"; PSModulePath = "C:\Modules" } }
        Mock New-Item { return [PSCustomObject]@{ FullName = $Path } }
        Mock Remove-Item { return $true }
        Mock Test-Path { return $true }
    }
    It "Should implement retry logic for transient failures" {
        # Reset the counter
        $script:mountAttempts = 0
        $result = Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File
        # Ensure that the Mount-WindowsImage function retried (i.e. was invoked more than once)
        $script:mountAttempts | Should -BeGreaterThan 1
        # Verify that the result (boot.wim path) is as expected
        $result | Should -Be "$($testEnv.WorkspacePath)\Media\Sources\boot.wim"
    }
    It "Should handle multiple simultaneous executions" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        # Create a runspace pool with limited concurrency
        $pool = [runspacefactory]::CreateRunspacePool(1, 3)
        $pool.Open()
        try {
            $runspaces = @()
            $results = @()
            for ($i = 1; $i -le 3; $i++) {
                $ps = [powershell]::Create()
                $ps.RunspacePool = $pool
                [void]$ps.AddScript({
                    param($TempPath, $WorkspacePath, $Ps7Path, $ScriptPath)
                    # Import the function (in production, consider converting this to a module import)
                    . $ScriptPath
                    try {
                        $result = Customize-WinPEWithPowerShell7 -TempPath $TempPath -WorkspacePath $WorkspacePath -PowerShell7File $Ps7Path
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
                            Error = $_.Exception.Message
                        }
                    }
                })
                [void]$ps.AddParameters(@{
                    TempPath = "$($testEnv.TempPath)_$i"
                    WorkspacePath = "$($testEnv.WorkspacePath)_$i"
                    Ps7Path = $testEnv.PowerShell7File
                    ScriptPath = "$PSScriptRoot\..\Private\Customize-WinPEWithPowerShell7.ps1"
                })
                $handle = $ps.BeginInvoke()
                $runspaces += @{
                    PowerShell = $ps
                    Handle = $handle
                }
            }
            foreach ($rs in $runspaces) {
                $results += $rs.PowerShell.EndInvoke($rs.Handle)
                $rs.PowerShell.Dispose()
            }
            # Verify that exactly three executions completed
            $results.Count | Should -Be 3
            # Verify that at least one returned successfully (the retry logic succeeded)
            ($results | Where-Object { $_.Success -eq $true }).Count | Should -BeGreaterThan 0
        }
        finally {
            $pool.Close()
            $pool.Dispose()
        }
    }
}