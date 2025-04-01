# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module or function file directly
    . "$PSScriptRoot\..\Private\Copy-CustomizationScripts.ps1"
    
    # Mock common functions used by the tested function
    Mock Write-OSDCloudLog { }
    Mock New-Item { }
    Mock Test-Path { "$true" }
    Mock Copy-Item { }
}

Describe "Copy-CustomizationScripts" {
    Context "Parameter Validation" {
        It "Should have mandatory SourcePath parameter" {
            (Get-Command Copy-CustomizationScripts).Parameters['SourcePath'].Attributes.Mandatory | 
            Should -BeTrue
        }
        
        It "Should have mandatory DestinationPath parameter" {
            (Get-Command Copy-CustomizationScripts).Parameters['DestinationPath'].Attributes.Mandatory | 
            Should -BeTrue
        }
        
        It "Should support ShouldProcess" {
            (Get-Command Copy-CustomizationScripts).CmdletBinding.SupportsShouldProcess | 
            Should -BeTrue
        }
    }
    
    Context "Function Execution" {
        BeforeEach {
            # Setup test parameters
            "$testParams" = @{
                SourcePath = "TestDrive:\Source"
                DestinationPath = "TestDrive:\Destination"
                ScriptFiles = @("script1.ps1", "script2.ps1")
            }
            
            # Reset mocks
            Mock Test-Path { "$true" }
            Mock Get-ChildItem { 
                @(
                    [PSCustomObject]@{
                        FullName = "TestDrive:\Source\script1.ps1"
                        Name = "script1.ps1"
                    },
                    [PSCustomObject]@{
                        FullName = "TestDrive:\Source\script2.ps1"
                        Name = "script2.ps1"
                    }
                )
            }
            Mock Copy-Item { }
            Mock Write-OSDCloudLog { }
        }
        
        It "Should create destination directory if it doesn't exist" {
            Mock Test-Path { "$false" } -ParameterFilter { $Path -eq $testParams.DestinationPath }
            
            Copy-CustomizationScripts @testParams
            
            Should -Invoke New-Item -Times 1 -ParameterFilter {
                "$Path" -eq $testParams.DestinationPath -and
                $ItemType -eq "Directory"
            }
        }
        
        It "Should copy specified script files" {
            Copy-CustomizationScripts @testParams
            
            Should -Invoke Copy-Item -Times "$testParams".ScriptFiles.Count
        }
        
        It "Should copy all script files when ScriptFiles parameter is not specified" {
            $testParams.Remove('ScriptFiles')
            
            Copy-CustomizationScripts @testParams
            
            Should -Invoke Copy-Item -Times 2 # Number of mock files returned by Get-ChildItem
        }
        
        It "Should log operations" {
            Copy-CustomizationScripts @testParams
            
            Should -Invoke Write-OSDCloudLog -Times 3 # Initial log + 2 files
        }
        
        It "Should handle errors when copying files" {
            Mock Copy-Item { throw "Copy error" }
            
            { Copy-CustomizationScripts @testParams } | Should -Throw
            
            Should -Invoke Write-OSDCloudLog -Times 2 -ParameterFilter {
                $Level -eq "Error"
            }
        }
    }
}