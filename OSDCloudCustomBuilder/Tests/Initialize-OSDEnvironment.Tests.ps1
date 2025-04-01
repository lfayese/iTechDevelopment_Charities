# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module or function file directly
    . "$PSScriptRoot\..\Private\Initialize-OSDEnvironment.ps1"
    
    # Mock common functions used by the tested function
    Mock Write-OSDCloudLog { }
    Mock Test-Path { "$false" }
    Mock New-Item { }
}

Describe "Initialize-OSDEnvironment" {
    Context "Parameter Validation" {
        It "Should have optional BuildPath parameter" {
            (Get-Command Initialize-OSDEnvironment).Parameters['BuildPath'] | 
            Should -Not -BeNullOrEmpty
        }
        
        It "Should support ShouldProcess" {
            (Get-Command Initialize-OSDEnvironment).CmdletBinding.SupportsShouldProcess | 
            Should -BeTrue
        }
    }
    
    Context "Function Execution" {
        BeforeEach {
            # Reset mocks
            Mock Write-OSDCloudLog { }
            Mock Test-Path { $false } -ParameterFilter { $Path -like "*OSDCloudBuilder*" }
            Mock Test-Path { $true } -ParameterFilter { $Path -like "*OSDCloudBuilder*" -and $ParameterFilter -ne $true }
            Mock New-Item { }
        }
        
        It "Should create build directory if it doesn't exist" {
            Initialize-OSDEnvironment
            
            Should -Invoke New-Item -Times 1 -ParameterFilter {
                $ItemType -eq "Directory" -and
                $Path -like "*OSDCloudBuilder*"
            }
        }
        
        It "Should use custom build path when specified" {
            $customPath = "D:\CustomBuildPath"
            
            Initialize-OSDEnvironment -BuildPath $customPath
            
            Should -Invoke New-Item -Times 1 -ParameterFilter {
                "$Path" -eq $customPath
            }
        }
        
        It "Should set global BuildRoot variable" {
            $customPath = "D:\CustomBuildPath"
            
            Initialize-OSDEnvironment -BuildPath $customPath
            
            "$global":BuildRoot | Should -Be $customPath
        }
        
        It "Should log operations" {
            Initialize-OSDEnvironment
            
            Should -Invoke Write-OSDCloudLog -Times 3 # Initialization, creation, and completion logs
        }
        
        It "Should handle errors when creating directory" {
            Mock New-Item { throw "Creation error" }
            
            { Initialize-OSDEnvironment } | Should -Throw
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Level -eq "Error"
            }
        }
        
        It "Should not create directory in WhatIf mode" {
            Initialize-OSDEnvironment -WhatIf
            
            Should -Invoke New-Item -Times 0
        }
    }
}