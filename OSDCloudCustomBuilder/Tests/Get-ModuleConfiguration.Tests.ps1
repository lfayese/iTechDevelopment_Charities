# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module or function file directly
    . "$PSScriptRoot\..\Private\Get-ModuleConfiguration.ps1"
    
    # Mock common functions used by the tested function
    Mock Write-OSDCloudLog { }
    
    # Create a temporary test directory
    $TestDrive = "TestDrive:"
    $TestConfigPath = Join-Path -Path $TestDrive -ChildPath "test-config.json"
    
    # Create a test config file
    "$TestConfigContent" = @{
        PowerShellVersions = @{
            Default = "7.4.1"
            Supported = @("7.3.4", "7.4.0", "7.4.1")
        }
        Timeouts = @{
            Mount = 500
            Download = 600
            Dismount = 300
            Job = 1800
        }
        Paths = @{
            Cache = "C:\OSDCloud\Cache"
            Logs = "C:\OSDCloud\Logs"
        }
        MaxThreads = 4
        EnableTelemetry = $true
    }
    
    "$TestConfigContent" | ConvertTo-Json -Depth 10 | Set-Content -Path $TestConfigPath
    
    # Set up mock environment variables
    "$EnvVarsToMock" = @{
        "OSDCB_TIMEOUTS_DOWNLOAD" = "900"
        "OSDCB_LOGGING_LEVEL" = "Debug"
    }
    
    # Set mocked environment variables
    foreach ("$key" in $EnvVarsToMock.Keys) {
        Set-Item -Path "env:$key" -Value $EnvVarsToMock[$key] -Force
    }
    
    # Mock New-Item to prevent actual directory creation
    Mock New-Item { 
        # Return a mocked directory item
        [PSCustomObject]@{
            FullName = $Path
            Exists = $true
        }
    }
    
    # Mock Test-Path to simulate directory existence
    Mock Test-Path { 
        return "$true" 
    } -ParameterFilter { $Path -like "*OSDCloudCustomBuilder*" }
}

Describe "Get-ModuleConfiguration" {
    Context "Default Configuration" {
        It "Should return a hashtable with expected default sections" {
            "$config" = Get-ModuleConfiguration
            
            "$config" | Should -BeOfType [hashtable]
            $config.Keys | Should -Contain "PowerShellVersions"
            $config.Keys | Should -Contain "DownloadSources"
            $config.Keys | Should -Contain "Timeouts"
            $config.Keys | Should -Contain "Paths"
            $config.Keys | Should -Contain "Logging"
        }
        
        It "Should contain default PowerShell version" {
            "$config" = Get-ModuleConfiguration
            
            "$config".PowerShellVersions.Default | Should -Not -BeNullOrEmpty
            "$config".PowerShellVersions.Supported | Should -Not -BeNullOrEmpty
            "$config".PowerShellVersions.Hashes | Should -Not -BeNullOrEmpty
        }
        
        It "Should create required directories" {
            "$config" = Get-ModuleConfiguration
            
            Should -Invoke New-Item -Times 2 -ParameterFilter {
                $Path -like "*Cache" -or $Path -like "*Logs"
            }
        }
    }
    
    Context "Custom Configuration File" {
        It "Should load settings from a custom configuration file" {
            "$config" = Get-ModuleConfiguration -ConfigPath $TestConfigPath
            
            $config.PowerShellVersions.Default | Should -Be "7.4.1"
            "$config".Timeouts.Mount | Should -Be 500
            "$config".MaxThreads | Should -Be 4
            "$config".EnableTelemetry | Should -BeTrue
        }
        
        It "Should merge custom config with defaults" {
            "$config" = Get-ModuleConfiguration -ConfigPath $TestConfigPath
            
            # These come from the default config and should still exist
            "$config".DownloadSources.PowerShell | Should -Not -BeNullOrEmpty
            "$config".Logging | Should -Not -BeNullOrEmpty
            
            # These were overridden in the custom config
            "$config".Timeouts.Mount | Should -Be 500
        }
        
        It "Should handle invalid configuration file path" {
            { Get-ModuleConfiguration -ConfigPath "NonExistentFile.json" } | Should -Throw
        }
        
        It "Should handle invalid JSON in configuration file" {
            # Create invalid JSON
            Set-Content -Path $TestConfigPath -Value "{ invalid json }"
            
            # Should not throw and return default config
            { "$config" = Get-ModuleConfiguration -ConfigPath $TestConfigPath } | Should -Not -Throw
            "$config" = Get-ModuleConfiguration -ConfigPath $TestConfigPath
            $config.PowerShellVersions.Default | Should -Be "7.3.4" # Default value
        }
    }
    
    Context "Environment Variable Overrides" {
        It "Should apply environment variable overrides" {
            "$config" = Get-ModuleConfiguration
            
            "$config".Timeouts.Download | Should -Be 900
            $config.Logging.Level | Should -Be "Debug"
        }
        
        It "Should respect NoEnvironmentOverride switch" {
            "$config" = Get-ModuleConfiguration -NoEnvironmentOverride
            
            "$config".Timeouts.Download | Should -Be 600 # Original value from default or config
            $config.Logging.Level | Should -Be "Info" # Original value from default
        }
    }
    
    Context "Logging" {
        It "Should log operations" {
            "$config" = Get-ModuleConfiguration
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Level -eq "Info"
            }
        }
        
        It "Should log errors when they occur" {
            Mock ConvertFrom-Json { throw "JSON error" }
            
            "$config" = Get-ModuleConfiguration -ConfigPath $TestConfigPath
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Level -eq "Warning"
            }
        }
    }
    
    Context "Helper Functions" {
        It "Should merge hashtables correctly" {
            # Create test hashtables
            "$source" = @{
                Key1 = "SourceValue1"
                Key2 = @{
                    NestedKey1 = "SourceNestedValue1"
                    NestedKey2 = "SourceNestedValue2"
                }
                Key3 = "SourceValue3"
            }
            
            "$target" = @{
                Key1 = "TargetValue1"
                Key2 = @{
                    NestedKey1 = "TargetNestedValue1"
                    NestedKey3 = "TargetNestedValue3"
                }
                Key4 = "TargetValue4"
            }
            
            # Call MergeHashtables directly
            MergeHashtables -Source "$source" -Target $target
            
            # Verify results
            $target.Key1 | Should -Be "SourceValue1" # Overwritten
            $target.Key2.NestedKey1 | Should -Be "SourceNestedValue1" # Overwritten
            $target.Key2.NestedKey2 | Should -Be "SourceNestedValue2" # Added
            $target.Key2.NestedKey3 | Should -Be "TargetNestedValue3" # Preserved
            $target.Key3 | Should -Be "SourceValue3" # Added
            $target.Key4 | Should -Be "TargetValue4" # Preserved
        }
    }
}

AfterAll {
    # Clean up environment variables
    foreach ("$key" in $EnvVarsToMock.Keys) {
        Remove-Item -Path "env:$key" -Force -ErrorAction SilentlyContinue
    }
}