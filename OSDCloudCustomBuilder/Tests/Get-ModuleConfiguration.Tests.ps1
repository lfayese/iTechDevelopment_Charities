BeforeAll {
    # Import the module or function file directly
    . "$PSScriptRoot\..\Private\Get-ModuleConfiguration.ps1"
    
    # Mock common functions used by the tested function
    Mock Write-OSDCloudLog { }
}

Describe "Get-ModuleConfiguration" {
    Context "Configuration Loading" {
        BeforeEach {
            # Setup test environment
            $script:ModuleRoot = "TestDrive:"
            $configPath = Join-Path -Path $script:ModuleRoot -ChildPath "config.json"
            
            # Create a test configuration file
            $testConfig = @{
                Timeouts = @{
                    Download = 600
                    Mount = 300
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
            
            $testConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath
        }
        
        It "Should load configuration from file when it exists" {
            $config = Get-ModuleConfiguration
            
            $config.Timeouts.Download | Should -Be 600
            $config.Timeouts.Mount | Should -Be 300
            $config.Paths.Cache | Should -Be "C:\OSDCloud\Cache"
            $config.MaxThreads | Should -Be 4
            $config.EnableTelemetry | Should -BeTrue
        }
        
        It "Should create default configuration when file doesn't exist" {
            # Remove the config file
            Remove-Item -Path (Join-Path -Path $script:ModuleRoot -ChildPath "config.json") -Force
            
            $config = Get-ModuleConfiguration
            
            $config.Timeouts.Download | Should -Be 600 # Default value
            $config.Timeouts.Mount | Should -Be 300 # Default value
            $config.MaxThreads | Should -Be 4 # Default value
        }
        
        It "Should handle invalid JSON in configuration file" {
            # Create invalid JSON
            Set-Content -Path (Join-Path -Path $script:ModuleRoot -ChildPath "config.json") -Value "{ invalid json }"
            
            $config = Get-ModuleConfiguration
            
            # Should return default config
            $config.Timeouts.Download | Should -Be 600
        }
        
        It "Should log operations" {
            $config = Get-ModuleConfiguration
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Level -eq "Info"
            }
        }
        
        It "Should log errors when they occur" {
            Mock ConvertFrom-Json { throw "JSON error" }
            
            $config = Get-ModuleConfiguration
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Level -eq "Warning"
            }
        }
    }
}