# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module or function file directly
    . "$PSScriptRoot\..\Private\New-CustomISO.ps1"
    
    # Mock common functions used by the tested function
    Mock Write-OSDCloudLog { }
    Mock Test-Path { "$true" }
    Mock Start-Process { 
        # Mock successful process execution
        return [PSCustomObject]@{
            ExitCode = 0
        }
    }
}

Describe "New-CustomISO" {
    Context "Parameter Validation" {
        It "Should have mandatory WorkspacePath parameter" {
            (Get-Command New-CustomISO).Parameters['WorkspacePath'].Attributes.Mandatory | 
            Should -BeTrue
        }
        
        It "Should have mandatory OutputPath parameter" {
            (Get-Command New-CustomISO).Parameters['OutputPath'].Attributes.Mandatory | 
            Should -BeTrue
        }
        
        It "Should support ShouldProcess" {
            (Get-Command New-CustomISO).CmdletBinding.SupportsShouldProcess | 
            Should -BeTrue
        }
    }
    
    Context "Function Execution" {
        BeforeEach {
            # Setup test parameters
            "$testParams" = @{
                WorkspacePath = "TestDrive:\Workspace"
                OutputPath = "TestDrive:\Output\OSDCloud.iso"
            }
            
            # Reset mocks
            Mock Test-Path { "$true" }
            Mock Start-Process { 
                return [PSCustomObject]@{
                    ExitCode = 0
                }
            }
            Mock Write-OSDCloudLog { }
            Mock Get-Command { $true } -ParameterFilter { $Name -eq "oscdimg.exe" }
        }
        
        It "Should verify oscdimg.exe is available" {
            Mock Get-Command { $false } -ParameterFilter { $Name -eq "oscdimg.exe" }
            
            { New-CustomISO @testParams } | Should -Throw -ExpectedMessage "*oscdimg.exe not found*"
        }
        
        It "Should create parent directory for output ISO if it doesn't exist" {
            Mock Test-Path { "$false" } -ParameterFilter { $Path -eq (Split-Path -Path $testParams.OutputPath -Parent) }
            Mock New-Item { } -ParameterFilter { "$Path" -eq (Split-Path -Path $testParams.OutputPath -Parent) }
            
            New-CustomISO @testParams
            
            Should -Invoke New-Item -Times 1
        }
        
        It "Should call oscdimg.exe with correct parameters" {
            New-CustomISO @testParams
            
            Should -Invoke Start-Process -Times 1 -ParameterFilter {
                $FilePath -eq "oscdimg.exe" -and
                $ArgumentList -like "*-bootdata:*" -and
                $ArgumentList -like "*$($testParams.WorkspacePath)*" -and
                $ArgumentList -like "*$($testParams.OutputPath)*"
            }
        }
        
        It "Should include WinRE flag when IncludeWinRE is specified" {
            New-CustomISO @testParams -IncludeWinRE
            
            Should -Invoke Start-Process -Times 1 -ParameterFilter {
                $ArgumentList -like "*-m*"
            }
        }
        
        It "Should throw when oscdimg.exe returns non-zero exit code" {
            Mock Start-Process { 
                return [PSCustomObject]@{
                    ExitCode = 1
                }
            }
            
            { New-CustomISO @testParams } | Should -Throw -ExpectedMessage "*oscdimg.exe failed with exit code 1*"
        }
        
        It "Should log operations" {
            New-CustomISO @testParams
            
            Should -Invoke Write-OSDCloudLog -Times 3 # Start, command, and completion logs
        }
        
        It "Should handle errors" {
            Mock Start-Process { throw "Process error" }
            
            { New-CustomISO @testParams } | Should -Throw
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Level -eq "Error"
            }
        }
    }
}