Describe "Update-WinPEWithPowerShell7 Concurrency Tests" {
    BeforeAll {
        # Import the required functions from WinPE-PowerShell7.ps1
        $privatePath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "Private"
        $scriptPath = Join-Path -Path $privatePath -ChildPath "WinPE-PowerShell7.ps1"
        . $scriptPath
        
        # Initialize a common test environment
        $script:testEnv = @{
            TempPath = "C:\Test\Temp"
            WorkspacePath = "C:\Test\Workspace"
            PowerShell7File = "C:\Test\PowerShell-7.3.4-win-x64.zip"
        }
        
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
        Mock Get-ItemProperty { return @{ Path = "C:\\Windows"; PSModulePath = "C:\\Modules" } }
        Mock New-Item { return [PSCustomObject]@{ FullName = $Path } }
        Mock Remove-Item { return $true }
        Mock Test-Path { return $true }
        Mock Write-OSDCloudLog {}
        Mock Test-ValidPowerShellVersion { return $true }
        Mock Get-PowerShell7Package { param($Version, $DownloadPath) return "C:\Test\PowerShell-7.3.4-win-x64.zip" }
        Mock Initialize-WinPEMountPoint { 
            return @{
                MountPoint = "C:\Test\Temp\Mount_1234"
                PS7TempPath = "C:\Test\Temp\PS7_1234"
                InstanceId = "1234"
            }
        }
        Mock Install-PowerShell7ToWinPE { return $true }
        Mock Update-WinPERegistry { return $true }
        Mock Update-WinPEStartup { return $true }
        Mock New-WinPEStartupProfile { return $true }
    }
    
    It "Should implement retry logic for transient failures" {
        # Reset the counter
        $script:mountAttempts = 0
        
        # Execute function under test
        $result = Update-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File
        
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
                    
                    # Import the function 
                    . $ScriptPath
                    
                    try {
                        $result = Update-WinPEWithPowerShell7 -TempPath $TempPath -WorkspacePath $WorkspacePath -PowerShell7File $Ps7Path
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
                    ScriptPath = $scriptPath
                })
                
                $handle = $ps.BeginInvoke()
                
                $runspaces += @{
                    PowerShell = $ps
                    Handle = $handle
                }
            }
            
            # Wait for all runspaces to complete and collect results
            foreach ($runspace in $runspaces) {
                $results += $runspace.PowerShell.EndInvoke($runspace.Handle)
                $runspace.PowerShell.Dispose()
            }
            
            # Verify results
            $results.Count | Should -Be 3
            $results | ForEach-Object {
                $_.Success | Should -BeTrue
                $_.Result | Should -Not -BeNullOrEmpty
                $_.Error | Should -BeNullOrEmpty
            }
        }
        catch {
            # Ensure proper logging of any errors during the test
            Write-Warning "Error in concurrent execution test: $_"
            throw
        }
        finally {
            # Ensure proper cleanup of all resources
            if ($runspaces) {
                foreach ($runspace in $runspaces) {
                    if ($runspace.PowerShell) {
                        try {
                            if ($runspace.Handle -and -not $runspace.Handle.IsCompleted) {
                                # Stop any still-running runspaces
                                $runspace.PowerShell.Stop()
                            }
                            $runspace.PowerShell.Dispose()
                        }
                        catch {
                            Write-Warning "Failed to dispose runspace: $_"
                        }
                    }
                }
            }
            
            # Close and dispose the runspace pool
            if ($pool) {
                try {
                    $pool.Close()
                    $pool.Dispose()
                }
                catch {
                    Write-Warning "Failed to dispose runspace pool: $_"
                }
            }
            
            # Force garbage collection to free memory
            [System.GC]::Collect()
        }
    }
    
    # Test backward compatibility with alias
    It "Should support backward compatibility with Customize-WinPEWithPowerShell7 alias" {
        # Reset the counter
        $script:mountAttempts = 0
        
        # Test if the alias exists
        $alias = Get-Alias -Name Customize-WinPEWithPowerShell7 -ErrorAction SilentlyContinue
        $alias | Should -Not -BeNullOrEmpty
        $alias.ResolvedCommand.Name | Should -Be "Update-WinPEWithPowerShell7"
        
        # This should call Update-WinPEWithPowerShell7 via the alias
        Mock Update-WinPEWithPowerShell7 { return "$($WorkspacePath)\Media\Sources\boot.wim" }
        
        $result = Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File
        
        # Verify alias worked
        Should -Invoke Update-WinPEWithPowerShell7 -Times 1
        $result | Should -Be "$($testEnv.WorkspacePath)\Media\Sources\boot.wim"
    }
}