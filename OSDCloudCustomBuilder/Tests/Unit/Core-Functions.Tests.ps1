BeforeAll {
    # Import module for testing - handle both development and installed scenarios
    $ModuleName = 'OSDCloudCustomBuilder'
    $ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    
    # Remove module if already loaded
    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction Ignore
    
    # Import the module directly from the development path
    Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath "$ModuleName.psd1") -Force
}

Describe "Validation Helpers Tests" -Tag "Unit", "Validation" {
    Context "Test-IsAdmin Function" {
        It "Returns boolean value" {
            InModuleScope $ModuleName {
                $result = Test-IsAdmin
                $result | Should -BeOfType [bool]
            }
        }
    }
    
    Context "Test-ValidPath Function" {
        BeforeAll {
            # Create a temporary directory for testing
            $testDir = Join-Path -Path $TestDrive -ChildPath "TestDir"
            $null = New-Item -Path $testDir -ItemType Directory -Force
            
            # Create an invalid path with illegal characters
            $invalidPath = Join-Path -Path $TestDrive -ChildPath "Test`"<>|Dir"
        }
        
        It "Returns true for valid existing path" {
            InModuleScope $ModuleName {
                $testDir = Join-Path -Path $TestDrive -ChildPath "TestDir"
                $result = Test-ValidPath -Path $testDir -MustExist
                $result | Should -BeTrue
            }
        }
        
        It "Returns false for non-existent path with MustExist" {
            InModuleScope $ModuleName {
                $nonExistentPath = Join-Path -Path $TestDrive -ChildPath "NonExistent"
                $result = Test-ValidPath -Path $nonExistentPath -MustExist
                $result | Should -BeFalse
            }
        }
        
        It "Creates directory when CreateIfNotExist is specified" {
            InModuleScope $ModuleName {
                $newDir = Join-Path -Path $TestDrive -ChildPath "NewDir"
                $result = Test-ValidPath -Path $newDir -MustExist -CreateIfNotExist
                $result | Should -BeTrue
                Test-Path -Path $newDir | Should -BeTrue
            }
        }
        
        It "Returns false for path with invalid characters" {
            InModuleScope $ModuleName {
                $invalidPath = Join-Path -Path $TestDrive -ChildPath "Test`"<>|Dir"
                $result = Test-ValidPath -Path $invalidPath
                $result | Should -BeFalse
            }
        }
    }
}

Describe "Configuration Management Tests" -Tag "Unit", "Configuration" {
    BeforeAll {
        # Mock the environment variables
        Mock -ModuleName $ModuleName 'Join-Path' -ParameterFilter { 
            $Path -eq $env:LOCALAPPDATA -and $ChildPath -like "OSDCloudCustomBuilder*"
        } -MockWith {
            return "$TestDrive\$ChildPath"
        }
    }
    
    Context "Initialize-ModuleConfiguration Function" {
        It "Creates configuration with default values" {
            InModuleScope $ModuleName {
                # Reset config
                $script:Config = $null
                
                # Initialize configuration
                Initialize-ModuleConfiguration
                
                # Test defaults
                $script:Config | Should -Not -BeNullOrEmpty
                $script:Config.TelemetryEnabled | Should -BeFalse
                $script:Config.DefaultPowerShellVersion | Should -Be "7.5.0"
                $script:Config.Timeouts.Download | Should -Be 300
            }
        }
    }
    
    Context "Get-ModuleConfiguration Function" {
        It "Returns the entire configuration when no setting specified" {
            InModuleScope $ModuleName {
                $config = Get-ModuleConfiguration
                $config | Should -Not -BeNullOrEmpty
                $config.TelemetryEnabled | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Returns specific setting value when requested" {
            InModuleScope $ModuleName {
                $value = Get-ModuleConfiguration -Setting "DefaultPowerShellVersion"
                $value | Should -Be "7.5.0"
            }
        }
        
        It "Returns null for non-existent setting" {
            InModuleScope $ModuleName {
                $value = Get-ModuleConfiguration -Setting "NonExistentSetting"
                $value | Should -BeNullOrEmpty
            }
        }
    }
    
    Context "Update-ModuleConfiguration Function" {
        It "Updates configuration with new settings" {
            InModuleScope $ModuleName {
                # Update configuration
                Update-ModuleConfiguration -Settings @{ 
                    TelemetryEnabled = $true
                    Timeouts = @{ Download = 600 }
                } -NoSave
                
                # Test updates
                $script:Config.TelemetryEnabled | Should -BeTrue
                $script:Config.Timeouts.Download | Should -Be 600
            }
        }
    }
    
    Context "Reset-ModuleConfiguration Function" {
        It "Resets configuration to defaults" {
            InModuleScope $ModuleName {
                # First modify config
                Update-ModuleConfiguration -Settings @{ 
                    TelemetryEnabled = $true
                    DefaultPowerShellVersion = "7.4.0"
                } -NoSave
                
                # Then reset
                Reset-ModuleConfiguration -NoSave
                
                # Test defaults restored
                $script:Config.TelemetryEnabled | Should -BeFalse
                $script:Config.DefaultPowerShellVersion | Should -Be "7.5.0"
            }
        }
    }
}

AfterAll {
    # Clean up 
    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction Ignore
}
