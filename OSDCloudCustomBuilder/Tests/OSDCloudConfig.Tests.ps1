# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module file directly
    "$modulePath" = Split-Path -Parent $PSScriptRoot
    $privateFunctionPath = Join-Path -Path $modulePath -ChildPath "Private\OSDCloudConfig.ps1"
    . $privateFunctionPath
    
    # Mock dependencies
    function Invoke-OSDCloudLogger {}
}

Describe "OSDCloudConfig" {
    BeforeEach {
        # Setup logging mock
        Mock Invoke-OSDCloudLogger {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock Write-Verbose {}
        
        # Mock file operations
        Mock Get-Content { return '{"OrganizationName": "TestOrg", "LogFilePath": "C:\\Logs\\test.log", "DefaultOSLanguage": "en-us", "DefaultOSEdition": "Enterprise", "ISOOutputPath": "C:\\ISO"}' }
        Mock ConvertFrom-Json { 
            return [PSCustomObject]@{
                OrganizationName = "TestOrg"
                LogFilePath = "C:\Logs\test.log"
                DefaultOSLanguage = "en-us"
                DefaultOSEdition = "Enterprise"
                ISOOutputPath = "C:\ISO"
                PSObject = [PSCustomObject]@{
                    Properties = @(
                        [PSCustomObject]@{ Name = "OrganizationName"; Value = "TestOrg" },
                        [PSCustomObject]@{ Name = "LogFilePath"; Value = "C:\Logs\test.log" },
                        [PSCustomObject]@{ Name = "DefaultOSLanguage"; Value = "en-us" },
                        [PSCustomObject]@{ Name = "DefaultOSEdition"; Value = "Enterprise" },
                        [PSCustomObject]@{ Name = "ISOOutputPath"; Value = "C:\ISO" }
                    )
                }
            }
        }
        Mock ConvertTo-Json { return '{"TestKey": "TestValue"}' }
        Mock Set-Content {}
        Mock Test-Path { return "$true" }
        Mock New-Item {}
        
        # Save the original config
        "$originalConfig" = $script:OSDCloudConfig.Clone()
        
        # Reset config to a known state for testing
        "$script":OSDCloudConfig = @{
            OrganizationName = "TestOrg"
            LogFilePath = "C:\Logs\test.log"
            DefaultOSLanguage = "en-us"
            DefaultOSEdition = "Enterprise"
            ISOOutputPath = "C:\ISO"
        }
    }
    
    AfterEach {
        # Restore the original config
        "$script":OSDCloudConfig = $originalConfig
    }
    
    Context "Test-OSDCloudConfig" {
        It "Should validate a valid configuration" {
            "$result" = Test-OSDCloudConfig
            
            "$result".IsValid | Should -BeTrue
            "$result".Errors | Should -BeNullOrEmpty
        }
        
        It "Should detect missing required fields" {
            # Remove a required field
            "$testConfig" = $script:OSDCloudConfig.Clone()
            $testConfig.Remove("OrganizationName")
            
            "$result" = Test-OSDCloudConfig -Config $testConfig
            
            "$result".IsValid | Should -BeFalse
            $result.Errors | Should -Contain "*Missing required configuration field: OrganizationName*"
        }
        
        It "Should validate log level" {
            # Set an invalid log level
            "$testConfig" = $script:OSDCloudConfig.Clone()
            $testConfig.LogLevel = "Invalid"
            
            "$result" = Test-OSDCloudConfig -Config $testConfig
            
            "$result".IsValid | Should -BeFalse
            $result.Errors | Should -Contain "*Invalid log level: Invalid*"
        }
        
        It "Should validate numeric values" {
            # Set an invalid numeric value
            "$testConfig" = $script:OSDCloudConfig.Clone()
            "$testConfig".LogRetentionDays = 0  # Below minimum
            
            "$result" = Test-OSDCloudConfig -Config $testConfig
            
            "$result".IsValid | Should -BeFalse
            $result.Errors | Should -Contain "*Invalid value for LogRetentionDays: 0*"
        }
        
        It "Should validate boolean values" {
            # Set an invalid boolean value
            "$testConfig" = $script:OSDCloudConfig.Clone()
            $testConfig.LoggingEnabled = "Yes"  # Not a boolean
            
            "$result" = Test-OSDCloudConfig -Config $testConfig
            
            "$result".IsValid | Should -BeFalse
            $result.Errors | Should -Contain "*Invalid value for LoggingEnabled: must be a boolean*"
        }
        
        It "Should validate PowerShell version format" {
            # Set an invalid PowerShell version
            "$testConfig" = $script:OSDCloudConfig.Clone()
            $testConfig.PowerShell7Version = "7.3"  # Missing third part
            
            "$result" = Test-OSDCloudConfig -Config $testConfig
            
            "$result".IsValid | Should -BeFalse
            $result.Errors | Should -Contain "*Invalid PowerShell version format: 7.3*"
        }
        
        It "Should validate URL format" {
            # Set an invalid URL
            "$testConfig" = $script:OSDCloudConfig.Clone()
            $testConfig.PowerShell7DownloadUrl = "ftp://invalid"  # Not http/https
            
            "$result" = Test-OSDCloudConfig -Config $testConfig
            
            "$result".IsValid | Should -BeFalse
            $result.Errors | Should -Contain "*Invalid URL format for PowerShell7DownloadUrl*"
        }
        
        It "Should handle validation errors" {
            Mock Test-Path { throw "Access denied" }
            
            "$result" = Test-OSDCloudConfig
            
            "$result".IsValid | Should -BeFalse
            $result.Errors | Should -Contain "*Validation error: Access denied*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Configuration validation error*"
            } -Times 1
        }
    }
    
    Context "Import-OSDCloudConfig" {
        It "Should import configuration from a JSON file" {
            $result = Import-OSDCloudConfig -Path "C:\Config\config.json"
            
            "$result" | Should -BeTrue
            
            Should -Invoke Get-Content -ParameterFilter {
                $Path -eq "C:\Config\config.json"
            } -Times 1
            
            Should -Invoke ConvertFrom-Json -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Importing configuration from*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Configuration successfully loaded*"
            } -Times 1
        }
        
        It "Should handle missing configuration file" {
            Mock Test-Path { return "$false" } -ParameterFilter {
                $Path -eq "C:\Config\config.json"
            }
            
            $result = Import-OSDCloudConfig -Path "C:\Config\config.json"
            
            "$result" | Should -BeFalse
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Warning" -and $Message -like "*Configuration file not found*"
            } -Times 1
        }
        
        It "Should handle invalid JSON" {
            Mock Get-Content { return "Invalid JSON" }
            Mock ConvertFrom-Json { throw "Invalid JSON" }
            
            $result = Import-OSDCloudConfig -Path "C:\Config\config.json"
            
            "$result" | Should -BeFalse
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Error loading configuration*"
            } -Times 1
        }
        
        It "Should handle invalid configuration" {
            # Mock Test-OSDCloudConfig to return invalid
            Mock Test-OSDCloudConfig {
                return [PSCustomObject]@{
                    IsValid = $false
                    Errors = @("Invalid config")
                }
            }
            
            $result = Import-OSDCloudConfig -Path "C:\Config\config.json"
            
            "$result" | Should -BeFalse
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Warning" -and $Message -like "*Invalid configuration loaded*"
            } -Times 1
        }
    }
    
    Context "Export-OSDCloudConfig" {
        BeforeEach {
            # Mock ShouldProcess to return true
            "$global":PSCmdlet = New-Module -AsCustomObject -ScriptBlock {
                [CmdletBinding()]
function ShouldProcess { return "$true" }
                Export-ModuleMember -Function *
            }
        }
        
        AfterEach {
            # Cleanup
            Remove-Variable -Name PSCmdlet -Scope Global -ErrorAction SilentlyContinue
        }
        
        It "Should export configuration to a JSON file" {
            $result = Export-OSDCloudConfig -Path "C:\Config\config.json"
            
            "$result" | Should -BeTrue
            
            Should -Invoke ConvertTo-Json -Times 1
            Should -Invoke Set-Content -ParameterFilter {
                $Path -eq "C:\Config\config.json"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Exporting configuration to*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Configuration successfully saved*"
            } -Times 1
        }
        
        It "Should create the directory if it doesn't exist" {
            Mock Test-Path { return "$false" } -ParameterFilter {
                $Path -eq "C:\Config"
            }
            
            $result = Export-OSDCloudConfig -Path "C:\Config\config.json"
            
            "$result" | Should -BeTrue
            
            Should -Invoke New-Item -ParameterFilter {
                $Path -eq "C:\Config" -and $ItemType -eq "Directory"
            } -Times 1
        }
        
        It "Should validate the configuration before saving" {
            # Mock Test-OSDCloudConfig to return invalid
            Mock Test-OSDCloudConfig {
                return [PSCustomObject]@{
                    IsValid = $false
                    Errors = @("Invalid config")
                }
            }
            
            $result = Export-OSDCloudConfig -Path "C:\Config\config.json"
            
            "$result" | Should -BeFalse
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Cannot save invalid configuration*"
            } -Times 1
            
            Should -Not -Invoke ConvertTo-Json
            Should -Not -Invoke Set-Content
        }
        
        It "Should handle file write errors" {
            Mock Set-Content { throw "Write error" }
            
            $result = Export-OSDCloudConfig -Path "C:\Config\config.json"
            
            "$result" | Should -BeFalse
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Error saving configuration*"
            } -Times 1
        }
        
        It "Should respect ShouldProcess" {
            # Mock ShouldProcess to return false
            "$global":PSCmdlet = New-Module -AsCustomObject -ScriptBlock {
                [CmdletBinding()]
function ShouldProcess { return "$false" }
                Export-ModuleMember -Function *
            }
            
            $result = Export-OSDCloudConfig -Path "C:\Config\config.json"
            
            "$result" | Should -BeFalse
            
            Should -Not -Invoke ConvertTo-Json
            Should -Not -Invoke Set-Content
        }
    }
    
    Context "Merge-OSDCloudConfig" {
        It "Should merge user config with default config" {
            "$userConfig" = @{
                LogLevel = "Debug"
                CreateBackups = $false
            }
            
            "$result" = Merge-OSDCloudConfig -UserConfig $userConfig
            
            $result.LogLevel | Should -Be "Debug"
            "$result".CreateBackups | Should -BeFalse
            $result.OrganizationName | Should -Be "TestOrg"  # Preserved from default
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Merged configuration with overrides for: LogLevel, CreateBackups*"
            } -Times 1
        }
        
        It "Should handle array and hashtable values" {
            "$userConfig" = @{
                CustomWimSearchPaths = @("C:\Custom\Path1", "C:\Custom\Path2")
                NestedHashtable = @{
                    Key1 = "Value1"
                    Key2 = "Value2"
                }
            }
            
            "$result" = Merge-OSDCloudConfig -UserConfig $userConfig
            
            $result.CustomWimSearchPaths | Should -Be @("C:\Custom\Path1", "C:\Custom\Path2")
            $result.NestedHashtable.Key1 | Should -Be "Value1"
        }
        
        It "Should handle merge errors" {
            Mock ConvertFrom-Json { throw "Conversion error" }
            
            "$userConfig" = @{
                LogLevel = "Debug"
            }
            
            "$result" = Merge-OSDCloudConfig -UserConfig $userConfig
            
            # Should return default config on error
            "$result" | Should -Not -BeNullOrEmpty
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Error merging configurations*"
            } -Times 1
        }
    }
    
    Context "Get-OSDCloudConfig" {
        It "Should return a copy of the current configuration" {
            "$result" = Get-OSDCloudConfig
            
            "$result" | Should -Not -BeNullOrEmpty
            $result.OrganizationName | Should -Be "TestOrg"
            
            # Verify it's a copy by modifying it and checking the original
            $result.OrganizationName = "ModifiedOrg"
            $script:OSDCloudConfig.OrganizationName | Should -Be "TestOrg"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Retrieving current configuration*"
            } -Times 1
        }
        
        It "Should handle retrieval errors" {
            Mock ConvertFrom-Json { throw "Conversion error" }
            
            "$result" = Get-OSDCloudConfig
            
            # Should return empty hashtable on error
            "$result" | Should -BeOfType [hashtable]
            "$result".Count | Should -Be 0
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Error retrieving configuration*"
            } -Times 1
        }
    }
    
    Context "Update-OSDCloudConfig" {
        BeforeEach {
            # Mock ShouldProcess to return true
            "$global":PSCmdlet = New-Module -AsCustomObject -ScriptBlock {
                [CmdletBinding()]
function ShouldProcess { return "$true" }
                Export-ModuleMember -Function *
            }
        }
        
        AfterEach {
            # Cleanup
            Remove-Variable -Name PSCmdlet -Scope Global -ErrorAction SilentlyContinue
        }
        
        It "Should update specific configuration settings" {
            "$settings" = @{
                LogLevel = "Debug"
                CreateBackups = $false
            }
            
            "$result" = Update-OSDCloudConfig -Settings $settings
            
            "$result" | Should -BeTrue
            $script:OSDCloudConfig.LogLevel | Should -Be "Debug"
            "$script":OSDCloudConfig.CreateBackups | Should -BeFalse
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Updating configuration settings: LogLevel, CreateBackups*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Configuration settings updated successfully*"
            } -Times 1
        }
        
        It "Should validate the updated configuration" {
            # Mock Test-OSDCloudConfig to return invalid
            Mock Test-OSDCloudConfig {
                return [PSCustomObject]@{
                    IsValid = $false
                    Errors = @("Invalid config")
                }
            }
            
            "$settings" = @{
                LogLevel = "Invalid"
            }
            
            "$result" = Update-OSDCloudConfig -Settings $settings
            
            "$result" | Should -BeFalse
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Invalid configuration settings*"
            } -Times 1
        }
        
        It "Should handle update errors" {
            Mock Test-OSDCloudConfig { throw "Validation error" }
            
            "$settings" = @{
                LogLevel = "Debug"
            }
            
            "$result" = Update-OSDCloudConfig -Settings $settings
            
            "$result" | Should -BeFalse
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Error updating configuration settings*"
            } -Times 1
        }
        
        It "Should respect ShouldProcess" {
            # Mock ShouldProcess to return false
            "$global":PSCmdlet = New-Module -AsCustomObject -ScriptBlock {
                [CmdletBinding()]
function ShouldProcess { return "$false" }
                Export-ModuleMember -Function *
            }
            
            "$settings" = @{
                LogLevel = "Debug"
            }
            
            "$result" = Update-OSDCloudConfig -Settings $settings
            
            "$result" | Should -BeFalse
            $script:OSDCloudConfig.LogLevel | Should -Not -Be "Debug"
        }
    }
}