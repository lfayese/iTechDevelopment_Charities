# Tests/Customize-WinPEWithPowerShell7.Tests.ps1

BeforeAll {
    # Import the function
    . "$PSScriptRoot\..\Private\Customize-WinPEWithPowerShell7.ps1"
    
    # Common test setup function
    function Initialize-TestEnvironment {
        param(
            [string]$TestName
        )
        
        $testRoot = Join-Path $TestDrive $TestName
        $tempPath = Join-Path $testRoot "Temp"
        $workspacePath = Join-Path $testRoot "Workspace"
        $ps7Path = Join-Path $testRoot "PS7.zip"
        
        # Create test directories and files
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
        New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null
        New-Item -Path "$workspacePath\Media\Sources" -ItemType Directory -Force | Out-Null
        Set-Content -Path "$workspacePath\Media\Sources\boot.wim" -Value "TestWIM"
        Set-Content -Path $ps7Path -Value "TestZip"
        
        return @{
            TempPath = $tempPath
            WorkspacePath = $workspacePath
            PowerShell7File = $ps7Path
        }
    }
    
    # Common mock setup function
    function Set-CommonMocks {
        param(
            [hashtable]$MockOverrides = @{}
        )
        
        # Default mocks
        $mocks = @{
            'Mount-WindowsImage' = { return $true }
            'Dismount-WindowsImage' = { return $true }
            'Expand-Archive' = { return $true }
            'Copy-Item' = { return $true }
            'reg' = { return $true }
            'New-ItemProperty' = { return $true }
            'Out-File' = { return $true }
            'Test-Path' = { return $true }
            'Get-ItemProperty' = { return @{ Path = "C:\Windows"; PSModulePath = "C:\Modules" } }
            'New-Item' = { return [PSCustomObject]@{ FullName = $Path } }
            'Remove-Item' = { return $true }
            'Get-PSDrive' = { return [PSCustomObject]@{ Name = "C"; Free = 10GB } }
        }
        
        # Apply overrides
        foreach ($key in $MockOverrides.Keys) {
            $mocks[$key] = $MockOverrides[$key]
        }
        
        # Set up all mocks
        foreach ($key in $mocks.Keys) {
            Mock -CommandName $key -MockWith $mocks[$key]
        }
    }
}

Describe "Customize-WinPEWithPowerShell7" {
    Context "Basic functionality" {
        BeforeEach {
            $testEnv = Initialize-TestEnvironment -TestName "BasicFunctionality"
            Set-CommonMocks
        }
        
        It "Should process and return the correct path" {
            # Act
            $result = Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File
            
            # Assert
            $result | Should -Be "$($testEnv.WorkspacePath)\Media\Sources\boot.wim"
            Should -Invoke Mount-WindowsImage -Times 1
            Should -Invoke Dismount-WindowsImage -Times 1
            Should -Invoke Expand-Archive -Times 1
        }
    }
    
    Context "Parameter validation" {
        BeforeEach {
            $testEnv = Initialize-TestEnvironment -TestName "ParameterValidation"
            Set-CommonMocks
        }
        
        It "Should require TempPath parameter" {
            { Customize-WinPEWithPowerShell7 -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File } | 
                Should -Throw "*TempPath*"
        }
        
        It "Should require WorkspacePath parameter" {
            { Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -PowerShell7File $testEnv.PowerShell7File } | 
                Should -Throw "*WorkspacePath*"
        }
        
        It "Should require PowerShell7File parameter" {
            { Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath } | 
                Should -Throw "*PowerShell7File*"
        }
        
        It "Should validate PowerShell7File exists" {
            Set-CommonMocks -MockOverrides @{
                'Test-Path' = { return $false }
            }
            
            { Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File "NonExistentFile.zip" } | 
                Should -Throw "*not found*"
        }
    }
    
    Context "Error handling" {
        BeforeEach {
            $testEnv = Initialize-TestEnvironment -TestName "ErrorHandling"
        }
        
        It "Should handle mounting failures" {
            Set-CommonMocks -MockOverrides @{
                'Mount-WindowsImage' = { throw "Mount failed" }
            }
            
            { Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File } | 
                Should -Throw "Mount failed"
        }
        
        It "Should clean up resources after errors" {
            Set-CommonMocks -MockOverrides @{
                'Mount-WindowsImage' = { throw "Mount failed" }
            }
            
            try {
                Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File
            }
            catch {
                # Ignore the expected error
            }
            
            Should -Invoke Remove-Item -Times 1 -ParameterFilter { $Path -like "*Mount*" }
        }
        
        It "Should handle Expand-Archive failures" {
            Set-CommonMocks -MockOverrides @{
                'Expand-Archive' = { throw "Archive extraction failed" }
            }
            
            { Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File } | 
                Should -Throw "*Archive extraction failed*"
            
            Should -Invoke Dismount-WindowsImage -Times 1 -ParameterFilter {
                $Path -like "*\Mount*" -and $Discard -eq $true
            }
        }
        
        It "Should handle registry failures" {
            Set-CommonMocks -MockOverrides @{
                'reg' = { throw "Registry error" }
            }
            
            { Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File } | 
                Should -Throw "*Registry error*"
            
            Should -Invoke Dismount-WindowsImage -Times 1 -ParameterFilter {
                $Path -like "*\Mount*" -and $Discard -eq $true
            }
        }
    }
    
    Context "Configuration scenarios" {
        BeforeEach {
            $testEnv = Initialize-TestEnvironment -TestName "ConfigScenarios"
            Set-CommonMocks
        }
        
        It "Should configure environment variables correctly" {
            # Arrange
            $startnetContent = $null
            Set-CommonMocks -MockOverrides @{
                'Out-File' = { 
                    # Capture the content being written
                    $script:startnetContent = $InputObject
                }
            }
            
            # Act
            Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File
            
            # Assert
            Should -Invoke New-ItemProperty -Times 1 -ParameterFilter { 
                $Path -like "*Run" -and 
                $Name -eq "UpdatePath" -and 
                $Value -like "*PowerShell7*"
            }
            
            $script:startnetContent | Should -Match "PowerShell7"
            $script:startnetContent | Should -Match "pwsh\.exe"
        }
    }
    
    Context "Edge cases" {
        It "Should handle paths with spaces" -TestCases @(
            @{ TestName = "PathsWithSpaces"; PathSuffix = "Temp Folder"; WorkspaceSuffix = "Work Space"; Ps7Suffix = "PowerShell 7.3.4.zip" },
            @{ TestName = "LongPaths"; PathSuffix = "A"*50 + "\Temp"; WorkspaceSuffix = "A"*50 + "\Workspace"; Ps7Suffix = "PowerShell-7.3.4-win-x64.zip" },
            @{ TestName = "UNCPaths"; PathSuffix = "server\share\temp"; WorkspaceSuffix = "server\share\workspace"; Ps7Suffix = "PowerShell-7.3.4-win-x64.zip" }
        ) {
            param($TestName, $PathSuffix, $WorkspaceSuffix, $Ps7Suffix)
            
            # Setup
            $testRoot = Join-Path $TestDrive $TestName
            $testTempPath = Join-Path $testRoot $PathSuffix
            $testWorkspacePath = Join-Path $testRoot $WorkspaceSuffix
            $testPs7Path = Join-Path $testRoot $Ps7Suffix
            
            Set-CommonMocks
            
            # Act
            $result = Customize-WinPEWithPowerShell7 -TempPath $testTempPath -WorkspacePath $testWorkspacePath -PowerShell7File $testPs7Path
            
            # Assert
            $result | Should -Be "$testWorkspacePath\Media\Sources\boot.wim"
        }
        
        It "Should handle different PowerShell 7 zip naming patterns" -TestCases @(
            @{ ZipName = "PowerShell-7.3.4-win-x64.zip" },
            @{ ZipName = "PowerShell-7.4.0-preview.1-win-x64.zip" },
            @{ ZipName = "pwsh-7.3.0-win-x64.zip" },
            @{ ZipName = "PowerShell-7.0.0-win-x64.zip" }
        ) {
            param($ZipName)
            
            # Setup
            $testEnv = Initialize-TestEnvironment -TestName "PS7Patterns"
            $testPs7Path = Join-Path $TestDrive $ZipName
            Set-Content -Path $testPs7Path -Value "TestZip"
            
            Set-CommonMocks
            
            # Act
            $result = Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testPs7Path
            
            # Assert
            $result | Should -Be "$($testEnv.WorkspacePath)\Media\Sources\boot.wim"
        }
        
        It "Should handle zero-byte PowerShell 7 zip file" {
            # Setup
            $testEnv = Initialize-TestEnvironment -TestName "ZeroByteFile"
            
            Set-CommonMocks -MockOverrides @{
                'Test-Path' = { return $true },
                'Get-Item' = { return [PSCustomObject]@{ Length = 0 } }
            }
            
            # Act & Assert
            { Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File } | 
                Should -Throw "*empty*"
        }
    }
    
    Context "Resource management" {
        BeforeEach {
            $testEnv = Initialize-TestEnvironment -TestName "ResourceManagement"
            Set-CommonMocks
        }
        
        It "Should check for sufficient disk space" {
            Set-CommonMocks -MockOverrides @{
                'Get-PSDrive' = { return [PSCustomObject]@{ Name = "C"; Free = 1MB } }
            }
            
            { Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File } | 
                Should -Throw "*insufficient disk space*"
        }
        
        It "Should create and clean up mount points" {
            # Act
            $result = Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File
            
            # Assert
            Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -like "*\Mount*" }
            Should -Invoke Remove-Item -Times 1 -ParameterFilter { 
                $Path -like "*\Mount*" -and $Recurse -eq $true -and $Force -eq $true
            }
        }
        
        It "Should properly release registry hives" {
            # Act
            $result = Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File
            
            # Assert
            Should -Invoke reg -Times 1 -ParameterFilter { $args[0] -eq "load" }
            Should -Invoke reg -Times 1 -ParameterFilter { $args[0] -eq "unload" }
        }
    }
    
    Context "Performance" {
        BeforeEach {
            $testEnv = Initialize-TestEnvironment -TestName "Performance"
            Set-CommonMocks
        }
        
        It "Should complete within a reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $result = Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File
            
            $stopwatch.Stop()
            $executionTime = $stopwatch.ElapsedMilliseconds
            
            # With mocks, this should be fast
            $executionTime | Should -BeLessThan 5000  # 5 seconds is generous for mocked operations
        }
    }
}

# Skip integration tests if running in CI/CD
# Integration tests - only run when environment supports it
Describe "Customize-WinPEWithPowerShell7 Integration Tests" {
    BeforeAll {
        # Check if we can run integration tests
        $script:canRunIntegration = $false
        
        # Skip integration tests unless explicitly enabled
        if ($env:RUN_INTEGRATION_TESTS -ne "true") {
            return
        }
        
        try {
            # Check if DISM is available
            $dismCheck = Get-Command -Name Dism.exe -ErrorAction SilentlyContinue
            
            # Check if we can create test directories
            $testIntPath = Join-Path $TestDrive "IntegrationTest"
            New-Item -Path $testIntPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            
            # Check for PowerShell 7 zip file
            $ps7Paths = @(
                # Add potential locations for PS7 zip
                "C:\Temp\PowerShell-7.3.4-win-x64.zip",
                "$PSScriptRoot\..\Resources\PowerShell-7.3.4-win-x64.zip",
                "$env:USERPROFILE\Downloads\PowerShell-7.3.4-win-x64.zip"
            )
            
            $script:intPs7Path = $ps7Paths | Where-Object { Test-Path $_ } | Select-Object -First 1
            
            $script:canRunIntegration = ($null -ne $dismCheck) -and ($null -ne $script:intPs7Path)
            
            if ($script:canRunIntegration) {
                # Create test environment
                $script:intTempPath = Join-Path $TestDrive "IntegrationTemp"
                $script:intWorkspacePath = Join-Path $TestDrive "IntegrationWorkspace"
                
                New-Item -Path $script:intTempPath -ItemType Directory -Force | Out-Null
                New-Item -Path "$script:intWorkspacePath\Media\Sources" -ItemType Directory -Force | Out-Null
                
                # Need a boot.wim file - could download a small one or create a minimal one
                # For this example, we'll just check if one exists in a common location
                $bootWimPaths = @(
                    "$PSScriptRoot\..\Resources\boot.wim",
                    "C:\Temp\boot.wim"
                )
                
                $bootWimPath = $bootWimPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
                
                if ($bootWimPath) {
                    Copy-Item -Path $bootWimPath -Destination "$script:intWorkspacePath\Media\Sources\boot.wim" -Force
                }
                else {
                    $script:canRunIntegration = $false
                }
            }
        }
        catch {
            Write-Warning "Integration test setup failed: $_"
            $script:canRunIntegration = $false
        }
    }
    
    It "Should perform actual customization with real files" -Skip:(-not $script:canRunIntegration) {
        # This test only runs if we have all the required components
        
        $result = Customize-WinPEWithPowerShell7 -TempPath $script:intTempPath -WorkspacePath $script:intWorkspacePath -PowerShell7File $script:intPs7Path
        
        # Verify the file exists
        $result | Should -Exist
        
        # Optionally verify PowerShell 7 was integrated by mounting and checking
        if ($script:canRunIntegration -and (Test-Path $result)) {
            $verifyMountPath = Join-Path $script:intTempPath "VerifyMount"
            New-Item -Path $verifyMountPath -ItemType Directory -Force | Out-Null
            
            try {
                Mount-WindowsImage -Path $verifyMountPath -ImagePath $result -Index 1
                
                # Check for PowerShell 7 files
                Test-Path "$verifyMountPath\Windows\System32\PowerShell7\pwsh.exe" | Should -BeTrue
                
                Dismount-WindowsImage -Path $verifyMountPath -Discard
            }
            catch {
                if (Test-Path $verifyMountPath) {
                    Dismount-WindowsImage -Path $verifyMountPath -Discard -ErrorAction SilentlyContinue
                }
                throw
            }
            finally {
                Remove-Item -Path $verifyMountPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# Concurrency tests
Describe "Customize-WinPEWithPowerShell7 Concurrency Tests" {
    BeforeAll {
        $testEnv = Initialize-TestEnvironment -TestName "Concurrency"
        
        # Mock for retry testing
        $script:mountAttempts = 0
        Mock Mount-WindowsImage {
            $script:mountAttempts++
            
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
        # Reset counter
        $script:mountAttempts = 0
        
        $result = Customize-WinPEWithPowerShell7 -TempPath $testEnv.TempPath -WorkspacePath $testEnv.WorkspacePath -PowerShell7File $testEnv.PowerShell7File
        
        # Function should have retried after the first failure
        $script:mountAttempts | Should -BeGreaterThan 1
        $result | Should -Be "$($testEnv.WorkspacePath)\Media\Sources\boot.wim"
    }
    
    It "Should handle multiple simultaneous executions" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
        # This test requires PowerShell 7+ for better parallel processing
        
        # Create a runspace pool with limited concurrency
        $pool = [runspacefactory]::CreateRunspacePool(1, 3)
        $pool.Open()
        
        try {
            # Create runspaces for parallel execution
            $runspaces = @()
            $results = @()
            
            for ($i = 1; $i -le 3; $i++) {
                $ps = [powershell]::Create()
                $ps.RunspacePool = $pool
                
                [void]$ps.AddScript({
                    param($TempPath, $WorkspacePath, $Ps7Path, $ScriptPath)
                    
                    # Import the function in this runspace
                    . $ScriptPath
                    
                    try {
                        # Execute the function
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
            
            # Collect results
            foreach ($rs in $runspaces) {
                $results += $rs.PowerShell.EndInvoke($rs.Handle)
                $rs.PowerShell.Dispose()
            }
            
            # All executions should complete
            $results.Count | Should -Be 3
            
            # At least one should succeed with our retry logic
            ($results | Where-Object { $_.Success -eq $true }).Count | Should -BeGreaterThan 0
        }
        finally {
            # Clean up
            $pool.Close()
            $pool.Dispose()
        }
    }
}