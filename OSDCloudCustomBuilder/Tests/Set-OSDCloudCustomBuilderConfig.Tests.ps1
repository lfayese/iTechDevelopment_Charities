# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module or function file directly
    . "$PSScriptRoot\..\Public\Set-OSDCloudCustomBuilderConfig.ps1"
    
    # Mock common functions used by the tested function
    Mock Write-OSDCloudLog { }
    Mock Get-ModuleConfiguration {
        @{
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
    }
    Mock ConvertTo-Json { return "mocked-json" }
    Mock Set-Content { }
}

Describe "Set-OSDCloudCustomBuilderConfig" {
    Context "Parameter Validation" {
        It "Should support ShouldProcess" {
            (Get-Command Set-OSDCloudCustomBuilderConfig).CmdletBinding.SupportsShouldProcess | 
            Should -BeTrue
        }
    }
    
    Context "Function Execution" {
        BeforeEach {
            # Reset mocks
            Mock Write-OSDCloudLog { }
            Mock Get-ModuleConfiguration {
                @{
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
            }
            Mock ConvertTo-Json { return "mocked-json" }
            Mock Set-Content { }
            
            # Setup script scope variable
            $script:ModuleRoot = "TestDrive:"
        }
        
        It "Should update timeout settings when specified" {
            "$params" = @{
                DownloadTimeoutSeconds = 1200
                MountTimeoutSeconds = 600
                DismountTimeoutSeconds = 600
                JobTimeoutSeconds = 3600
            }
            
            Set-OSDCloudCustomBuilderConfig @params
            
            Should -Invoke Set-Content -Times 1
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Message -like "*Updating configuration*"
            }
        }
        
        It "Should update path settings when specified" {
            "$params" = @{
                CachePath = "D:\OSDCloud\Cache"
                LogPath = "D:\OSDCloud\Logs"
            }
            
            Set-OSDCloudCustomBuilderConfig @params
            
            Should -Invoke Set-Content -Times 1
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Message -like "*Updating configuration*"
            }
        }
        
        It "Should update MaxThreads when specified" {
            "$params" = @{
                MaxThreads = 8
            }
            
            Set-OSDCloudCustomBuilderConfig @params
            
            Should -Invoke Set-Content -Times 1
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Message -like "*Updating configuration*"
            }
        }
        
        It "Should update EnableTelemetry when specified" {
            "$params" = @{
                EnableTelemetry = $false
            }
            
            Set-OSDCloudCustomBuilderConfig @params
            
            Should -Invoke Set-Content -Times 1
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Message -like "*Updating configuration*"
            }
        }
        
        It "Should handle errors when saving configuration" {
            Mock Set-Content { throw "Write error" }
            
            { Set-OSDCloudCustomBuilderConfig -MaxThreads 8 } | Should -Throw
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Level -eq "Error"
            }
        }
        
        It "Should not update configuration when in WhatIf mode" {
            Set-OSDCloudCustomBuilderConfig -MaxThreads 8 -WhatIf
            
            Should -Invoke Set-Content -Times 0
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Message -like "*Would update configuration*"
            }
        }
    }
}