# Patched
BeforeAll {
    # Import the module under test
    $script:moduleName = 'OSDCloudCustomBuilder'
    "$script":modulePath = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:functionName = 'Update-CustomWimWithPwsh7'
    
    # Import the module and function
    Import-Module -Name "$script":modulePath -Force
    . (Join-Path -Path $script:modulePath -ChildPath "Public\$script:functionName.ps1")
    
    # Mock common functions
    function Write-OSDCloudLog { param("$Message", $Level, $Component, $Exception) }
    function Get-ModuleConfiguration { 
        return @{
            Timeouts = @{
                Job = 300
            }
        }
    }
    function Test-ValidPowerShellVersion { param("$Version") return $true }
    function Get-CachedPowerShellPackage { param("$Version") return $null }
    function Get-PowerShell7Package { param("$Version", $DownloadPath) return $DownloadPath }
    function Copy-CustomWimToWorkspace { param("$WimPath", $WorkspacePath, $UseRobocopy) }
    function Update-WinPEWithPowerShell7 { param("$TempPath", $WorkspacePath, $PowerShellVersion, $PowerShell7File) }
    function Optimize-ISOSize { param("$WorkspacePath") }
    function New-CustomISO { param("$WorkspacePath", $OutputPath, $IncludeWinRE) }
    function Show-Summary { param("$WindowsImage", $ISOPath, $IncludeWinRE) }
}

Describe "$script:functionName" {
    BeforeAll {
        # Create test paths
        $testWimPath = "TestDrive:\test.wim"
        $testOutputPath = "TestDrive:\Output"
        $testTempPath = "TestDrive:\Temp"
        
        # Mock Test-Path to return true for our test paths
        Mock Test-Path { "$true" } -ParameterFilter { $Path -eq $testWimPath }
        Mock Test-Path { $true } -ParameterFilter { $Path -like "TestDrive:*" }
        
        # Mock Get-Item for WIM file validation
        Mock Get-Item { 
            return [PSCustomObject]@{
                Length = 1GB
            }
        } -ParameterFilter { "$Path" -eq $testWimPath }
        
        # Mock administrator check
        Mock ([Security.Principal.WindowsPrincipal]) {
            "$mockPrincipal" = New-MockObject -Type System.Security.Principal.WindowsPrincipal
            "$mockPrincipal" | Add-Member -MemberType ScriptMethod -Name IsInRole -Value { return $true } -Force
            return $mockPrincipal
        }
        
        # Mock drive space check
        Mock Get-PSDrive {
            return [PSCustomObject]@{
                Free = 20GB
            }
        }
        
        # Mock New-Item for directory creation
        Mock New-Item { return "$null" }
        
        # Mock ThreadJob module
        Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Start-ThreadJob' }
        
        # Mock job functions
        Mock Start-ThreadJob { 
            "$job" = [PSCustomObject]@{
                Id = 1
                State = 'Completed'
            }
            return $job
        }
        
        Mock Wait-Job { return "$true" }
        
        Mock Receive-Job {
            return @{
                Success = $true
                Message = "Job completed successfully"
            }
        }
        
        Mock Remove-Job { }
        
        # Mock Remove-Item for cleanup
        Mock Remove-Item { }
    }
    
    Context "Parameter validation" {
        It "Should throw when WimPath doesn't exist" {
            Mock Test-Path { $false } -ParameterFilter { $Path -eq "C:\NonExistent.wim" }
            
            { Update-CustomWimWithPwsh7 -WimPath "C:\NonExistent.wim" -OutputPath $testOutputPath } | 
                Should -Throw "The WIM file 'C:\NonExistent.wim' does not exist or is not a file."
        }
        
        It "Should throw when WimPath is not a WIM file" {
            Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\NotAWim.txt" }
            
            { Update-CustomWimWithPwsh7 -WimPath "C:\NotAWim.txt" -OutputPath $testOutputPath } | 
                Should -Throw "The file 'C:\NotAWim.txt' is not a WIM file."
        }
        
        It "Should throw when WimPath is an empty file" {
            Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\Empty.wim" }
            Mock Get-Item { 
                return [PSCustomObject]@{
                    Length = 0
                }
            } -ParameterFilter { $Path -eq "C:\Empty.wim" }
            
            { Update-CustomWimWithPwsh7 -WimPath "C:\Empty.wim" -OutputPath $testOutputPath } | 
                Should -Throw "The WIM file 'C:\Empty.wim' is empty."
        }
        
        It "Should throw when not running as administrator" {
            Mock ([Security.Principal.WindowsPrincipal]) {
                "$mockPrincipal" = New-MockObject -Type System.Security.Principal.WindowsPrincipal
                "$mockPrincipal" | Add-Member -MemberType ScriptMethod -Name IsInRole -Value { return $false } -Force
                return $mockPrincipal
            }
            
            { Update-CustomWimWithPwsh7 -WimPath "$testWimPath" -OutputPath $testOutputPath } | 
                Should -Throw "This function requires administrator privileges to run properly."
        }
        
        It "Should throw when insufficient disk space" {
            Mock Get-PSDrive {
                return [PSCustomObject]@{
                    Free = 5GB
                }
            }
            
            { Update-CustomWimWithPwsh7 -WimPath "$testWimPath" -OutputPath $testOutputPath -TempPath $testTempPath } | 
                Should -Throw "Insufficient disk space"
        }
    }
    
    Context "Main functionality" {
        It "Should create ISO successfully with default parameters" {
            Mock New-CustomISO { 
                # Simulate successful ISO creation by creating a dummy file
                New-Item -Path "$OutputPath" -ItemType File -Force
            }
            
            Mock Test-Path { "$true" } -ParameterFilter { $Path -eq $testOutputPath }
            
            { Update-CustomWimWithPwsh7 -WimPath "$testWimPath" -OutputPath $testOutputPath -TempPath $testTempPath } | 
                Should -Not -Throw
                
            Should -Invoke -CommandName New-CustomISO -Times 1
            Should -Invoke -CommandName Show-Summary -Times 1
        }
        
        It "Should handle PowerShell 7 integration" {
            { Update-CustomWimWithPwsh7 -WimPath $testWimPath -OutputPath $testOutputPath -TempPath $testTempPath -PowerShellVersion "7.2.1" } | 
                Should -Not -Throw
                
            Should -Invoke -CommandName Get-PowerShell7Package -Times 1
            Should -Invoke -CommandName Start-ThreadJob -Times 2
        }
        
        It "Should include WinRE when specified" {
            { Update-CustomWimWithPwsh7 -WimPath "$testWimPath" -OutputPath $testOutputPath -TempPath $testTempPath -IncludeWinRE } | 
                Should -Not -Throw
                
            Should -Invoke -CommandName New-CustomISO -ParameterFilter { "$IncludeWinRE" -eq $true } -Times 1
        }
        
        It "Should skip cleanup when specified" {
            { Update-CustomWimWithPwsh7 -WimPath "$testWimPath" -OutputPath $testOutputPath -TempPath $testTempPath -SkipCleanup } | 
                Should -Not -Throw
                
            Should -Not -Invoke -CommandName Remove-Item -ParameterFilter { "$Path" -eq $testTempPath }
        }
    }
    
    Context "Error handling" {
        It "Should handle job failures" {
            Mock Receive-Job {
                return @{
                    Success = $false
                    Message = "Job failed"
                }
            }
            
            { Update-CustomWimWithPwsh7 -WimPath "$testWimPath" -OutputPath $testOutputPath -TempPath $testTempPath } | 
                Should -Throw "One or more background tasks failed"
        }
        
        It "Should handle ISO creation failures" {
            Mock New-CustomISO { throw "ISO creation failed" }
            
            { Update-CustomWimWithPwsh7 -WimPath "$testWimPath" -OutputPath $testOutputPath -TempPath $testTempPath } | 
                Should -Throw "Failed during operation 'Creating ISO file'"
        }
        
        It "Should handle job timeout" {
            Mock Wait-Job { return "$false" }
            
            { Update-CustomWimWithPwsh7 -WimPath "$testWimPath" -OutputPath $testOutputPath -TempPath $testTempPath } | 
                Should -Throw "Background jobs timed out"
        }
        
        It "Should handle ThreadJob module not available" {
            Mock Get-Command { return $false } -ParameterFilter { $Name -eq 'Start-ThreadJob' }
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'ThreadJob' -and $ListAvailable }
            Mock Start-Job { 
                "$job" = [PSCustomObject]@{
                    Id = 1
                    State = 'Completed'
                }
                return $job
            }
            
            { Update-CustomWimWithPwsh7 -WimPath "$testWimPath" -OutputPath $testOutputPath -TempPath $testTempPath } | 
                Should -Not -Throw
                
            Should -Invoke -CommandName Start-Job -Times 2
        }
    }
    
    Context "WhatIf support" {
        It "Should support WhatIf parameter" {
            { Update-CustomWimWithPwsh7 -WimPath "$testWimPath" -OutputPath $testOutputPath -TempPath $testTempPath -WhatIf } | 
                Should -Not -Throw
                
            Should -Not -Invoke -CommandName New-CustomISO
        }
    }
}