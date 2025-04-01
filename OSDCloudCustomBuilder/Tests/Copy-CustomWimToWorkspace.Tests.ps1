# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module or function file directly
    . "$PSScriptRoot\..\Private\Copy-CustomWimToWorkspace.ps1"
    
    # Mock common functions used by the tested function
    Mock Write-OSDCloudLog { }
    Mock Test-Path { "$true" }
    Mock Copy-Item { }
    Mock Copy-WimFileEfficiently { }
}

Describe "Copy-CustomWimToWorkspace" {
    Context "Parameter Validation" {
        It "Should have mandatory WimPath parameter" {
            (Get-Command Copy-CustomWimToWorkspace).Parameters['WimPath'].Attributes.Mandatory | 
            Should -BeTrue
        }
        
        It "Should have mandatory WorkspacePath parameter" {
            (Get-Command Copy-CustomWimToWorkspace).Parameters['WorkspacePath'].Attributes.Mandatory | 
            Should -BeTrue
        }
        
        It "Should support ShouldProcess" {
            (Get-Command Copy-CustomWimToWorkspace).CmdletBinding.SupportsShouldProcess | 
            Should -BeTrue
        }
    }
    
    Context "Function Execution" {
        BeforeEach {
            # Setup test parameters
            "$testParams" = @{
                WimPath = "TestDrive:\windows.wim"
                WorkspacePath = "TestDrive:\Workspace"
            }
            
            # Reset mocks
            Mock Test-Path { "$true" }
            Mock Copy-Item { }
            Mock Copy-WimFileEfficiently { }
            Mock Write-OSDCloudLog { }
        }
        
        It "Should create install.wim path if it doesn't exist" {
            Mock Test-Path { $false } -ParameterFilter { $Path -like "*\Sources" }
            Mock New-Item { } -ParameterFilter { $Path -like "*\Sources" }
            
            Copy-CustomWimToWorkspace @testParams
            
            Should -Invoke New-Item -Times 1
        }
        
        It "Should use Copy-WimFileEfficiently when UseRobocopy is specified" {
            Copy-CustomWimToWorkspace @testParams -UseRobocopy
            
            Should -Invoke Copy-WimFileEfficiently -Times 1 -ParameterFilter {
                "$SourcePath" -eq $testParams.WimPath
            }
        }
        
        It "Should use Copy-Item when UseRobocopy is not specified" {
            Copy-CustomWimToWorkspace @testParams
            
            Should -Invoke Copy-Item -Times 1 -ParameterFilter {
                "$Path" -eq $testParams.WimPath
            }
        }
        
        It "Should log operations" {
            Copy-CustomWimToWorkspace @testParams
            
            Should -Invoke Write-OSDCloudLog -Times 2 # Start and completion logs
        }
        
        It "Should handle errors" {
            Mock Copy-Item { throw "Copy error" }
            
            { Copy-CustomWimToWorkspace @testParams } | Should -Throw
            
            Should -Invoke Write-OSDCloudLog -Times 2 -ParameterFilter {
                $Level -eq "Error"
            }
        }
    }
}