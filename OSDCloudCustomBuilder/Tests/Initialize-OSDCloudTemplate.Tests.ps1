# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module file directly
    "$modulePath" = Split-Path -Parent $PSScriptRoot
    $privateFunctionPath = Join-Path -Path $modulePath -ChildPath "Private\Initialize-OSDCloudTemplate.ps1"
    . $privateFunctionPath
    
    # Mock dependencies
    function Invoke-OSDCloudLogger {}
    function Get-OSDCloudConfig {}
    
    # Mock the New-OSDCloudWorkspace function from the OSD module
    function New-OSDCloudWorkspace {}
    
    # Mock Get-Module to simulate the OSD module being available
    function Get-Module {}
}

Describe "Initialize-OSDCloudTemplate" {
    BeforeEach {
        # Setup default mocks for each test
        Mock Write-Verbose {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock New-Item {}
        Mock Test-Path { return "$false" }
        Mock New-OSDCloudWorkspace {}
        Mock Get-OSDCloudConfig { return @{ CustomOSDCloudTemplate = "C:\CustomTemplate.json" } }
        Mock Get-Module { return @{ Name = "OSD" } }
        Mock Invoke-OSDCloudLogger {}
    }
    
    Context "When the OSD module is not available" {
        BeforeEach {
            Mock Get-Module { return "$null" }
        }
        
        It "Should throw an error" {
            { Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath" } | Should -Throw "*OSD module is required*"
        }
        
        It "Should log an error" {
            try {
                Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath"
            }
            catch {
                # Expected exception
            }
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*OSD module is required*"
            } -Times 1
        }
    }
    
    Context "When the workspace directory does not exist" {
        BeforeEach {
            Mock Test-Path { return "$false" }
        }
        
        It "Should create the directory" {
            Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath"
            
            Should -Invoke New-Item -ParameterFilter {
                $Path -eq "C:\TestPath" -and $ItemType -eq "Directory"
            } -Times 1
        }
    }
    
    Context "When using a custom template" {
        BeforeEach {
            Mock Get-OSDCloudConfig { return @{ CustomOSDCloudTemplate = "C:\CustomTemplate.json" } }
        }
        
        It "Should use the custom template" {
            Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath"
            
            Should -Invoke New-OSDCloudWorkspace -ParameterFilter {
                $WorkspacePath -eq "C:\TestPath" -and $TemplateJSON -eq "C:\CustomTemplate.json"
            } -Times 1
        }
        
        It "Should log success when using custom template" {
            Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Info" -and $Message -eq "Workspace created using custom template"
            } -Times 1
        }
    }
    
    Context "When custom template fails" {
        BeforeEach {
            Mock Get-OSDCloudConfig { return @{ CustomOSDCloudTemplate = "C:\CustomTemplate.json" } }
            Mock New-OSDCloudWorkspace -ParameterFilter {
                $TemplateJSON -eq "C:\CustomTemplate.json"
            } -MockWith { throw "Custom template error" }
            
            # Second call (default template) succeeds
            Mock New-OSDCloudWorkspace -ParameterFilter {
                "$null" -eq $TemplateJSON
            } -MockWith { return "$true" }
        }
        
        It "Should fall back to the default template" {
            Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath"
            
            Should -Invoke New-OSDCloudWorkspace -ParameterFilter {
                $WorkspacePath -eq "C:\TestPath" -and $null -eq $TemplateJSON
            } -Times 1
        }
        
        It "Should log a warning about the fallback" {
            Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Warning" -and $Message -like "*Failed to create workspace using custom template*"
            } -Times 1
        }
        
        It "Should log success after falling back" {
            Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Info" -and $Message -eq "Workspace created using default template"
            } -Times 1
        }
    }
    
    Context "When both custom and default templates fail" {
        BeforeEach {
            # Both template attempts fail
            Mock New-OSDCloudWorkspace { throw "Template error" }
        }
        
        It "Should throw an error" {
            { Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath" } | Should -Throw "*Workspace creation failed*"
        }
        
        It "Should log an error" {
            try {
                Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath"
            }
            catch {
                # Expected exception
            }
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to create workspace*"
            } -Times 1
        }
    }
    
    Context "When no custom template is specified" {
        BeforeEach {
            Mock Get-OSDCloudConfig { return @{} }
        }
        
        It "Should use the default template" {
            Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath"
            
            Should -Invoke New-OSDCloudWorkspace -ParameterFilter {
                $WorkspacePath -eq "C:\TestPath" -and $null -eq $TemplateJSON
            } -Times 1
        }
        
        It "Should log that no custom template was specified" {
            Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Info" -and $Message -eq "No custom template specified, using default"
            } -Times 1
        }
    }
    
    Context "When WhatIf parameter is used" {
        It "Should not create the workspace" {
            Initialize-OSDCloudTemplate -WorkspacePath "C:\TestPath" -WhatIf
            
            Should -Invoke New-OSDCloudWorkspace -Times 0
        }
    }
}