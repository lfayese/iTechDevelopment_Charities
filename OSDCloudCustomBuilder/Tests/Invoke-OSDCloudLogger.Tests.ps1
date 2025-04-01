# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module file directly
    "$modulePath" = Split-Path -Parent $PSScriptRoot
    $privateFunctionPath = Join-Path -Path $modulePath -ChildPath "Private\Invoke-OSDCloudLogger.ps1"
    . $privateFunctionPath
    
    # Mock the Get-OSDCloudConfig function
    function Get-OSDCloudConfig {
        return @{
            LogFilePath = "TestDrive:\test.log"
            VerboseLogging = $true
            DebugLogging = $true
        }
    }
}

Describe "Invoke-OSDCloudLogger" {
    BeforeEach {
        # Setup test environment
        Mock Write-Verbose {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock Write-Debug {}
        Mock Write-Verbose {}
        Mock Add-Content {}
        
        # Create test log path
        $null = New-Item -Path "TestDrive:\test.log" -ItemType File -Force
    }
    
    Context "Basic logging functionality" {
        It "Should log an informational message" {
            Invoke-OSDCloudLogger -Message "Test info message" -Level Info -Component "TestComponent"
            
            Should -Invoke Write-Verbose -ParameterFilter {
                $Object -like "*Test info message*"
            } -Times 1
            
            Should -Invoke Add-Content -ParameterFilter {
                $Value -like "*[Info] [TestComponent] Test info message*"
            } -Times 1
        }
        
        It "Should log a warning message" {
            Invoke-OSDCloudLogger -Message "Test warning message" -Level Warning -Component "TestComponent"
            
            Should -Invoke Write-Warning -ParameterFilter {
                $Message -like "*Test warning message*"
            } -Times 1
            
            Should -Invoke Add-Content -ParameterFilter {
                $Value -like "*[Warning] [TestComponent] Test warning message*"
            } -Times 1
        }
        
        It "Should log an error message" {
            Invoke-OSDCloudLogger -Message "Test error message" -Level Error -Component "TestComponent"
            
            Should -Invoke Write-Error -ParameterFilter {
                $Message -like "*Test error message*"
            } -Times 1
            
            Should -Invoke Add-Content -ParameterFilter {
                $Value -like "*[Error] [TestComponent] Test error message*"
            } -Times 1
        }
        
        It "Should log a debug message" {
            Invoke-OSDCloudLogger -Message "Test debug message" -Level Debug -Component "TestComponent"
            
            Should -Invoke Write-Debug -ParameterFilter {
                $Message -like "*Test debug message*"
            } -Times 1
            
            Should -Invoke Add-Content -ParameterFilter {
                $Value -like "*[Debug] [TestComponent] Test debug message*"
            } -Times 1
        }
        
        It "Should log a verbose message" {
            Invoke-OSDCloudLogger -Message "Test verbose message" -Level Verbose -Component "TestComponent"
            
            Should -Invoke Write-Verbose -ParameterFilter {
                $Message -like "*Test verbose message*"
            } -Times 1
            
            Should -Invoke Add-Content -ParameterFilter {
                $Value -like "*[Verbose] [TestComponent] Test verbose message*"
            } -Times 1
        }
    }
    
    Context "Exception handling" {
        It "Should include exception details in the log entry" {
            $testException = [System.Exception]::new("Test exception message")
            Invoke-OSDCloudLogger -Message "Test error with exception" -Level Error -Component "TestComponent" -Exception $testException
            
            Should -Invoke Add-Content -ParameterFilter {
                $Value -like "*Exception: System.Exception: Test exception message*"
            } -Times 1
        }
        
        It "Should handle stack trace information" {
            $testException = [System.Exception]::new("Test exception message")
            $testException.StackTrace = "   at TestMethod() in TestFile.ps1:line 42"
            Invoke-OSDCloudLogger -Message "Test error with stack trace" -Level Error -Component "TestComponent" -Exception $testException
            
            Should -Invoke Add-Content -ParameterFilter {
                $Value -like "*StackTrace:    at TestMethod() in TestFile.ps1:line 42*"
            } -Times 1
        }
    }
    
    Context "Configuration handling" {
        It "Should respect VerboseLogging setting" {
            Mock Get-OSDCloudConfig {
                return @{
                    LogFilePath = "TestDrive:\test.log"
                    VerboseLogging = $false
                    DebugLogging = $true
                }
            }
            
            Invoke-OSDCloudLogger -Message "Test verbose message" -Level Verbose -Component "TestComponent"
            
            Should -Invoke Write-Verbose -Times 0
            Should -Invoke Add-Content -Times 0
        }
        
        It "Should respect DebugLogging setting" {
            Mock Get-OSDCloudConfig {
                return @{
                    LogFilePath = "TestDrive:\test.log"
                    VerboseLogging = $true
                    DebugLogging = $false
                }
            }
            
            Invoke-OSDCloudLogger -Message "Test debug message" -Level Debug -Component "TestComponent"
            
            Should -Invoke Write-Debug -Times 0
            Should -Invoke Add-Content -Times 0
        }
        
        It "Should use default log file path when not specified" {
            Mock Get-OSDCloudConfig {
                return @{}
            }
            
            Mock Add-Content {} -ParameterFilter {
                $Path -like "*\OSDCloudCustomBuilder.log"
            }
            
            Invoke-OSDCloudLogger -Message "Test message with default log path" -Level Info -Component "TestComponent"
            
            Should -Invoke Add-Content -ParameterFilter {
                $Path -like "*\OSDCloudCustomBuilder.log"
            } -Times 1
        }
    }
    
    Context "Console output control" {
        It "Should not write to console when NoConsole is specified" {
            Invoke-OSDCloudLogger -Message "Test message with no console" -Level Info -Component "TestComponent" -NoConsole
            
            Should -Invoke Write-Verbose -Times 0
            Should -Invoke Add-Content -Times 1
        }
    }
    
    Context "Error handling" {
        It "Should handle errors when writing to log file" {
            Mock Add-Content { throw "Access denied" }
            
            # This should not throw, but should warn about the failure
            { Invoke-OSDCloudLogger -Message "Test message with file error" -Level Info -Component "TestComponent" } | Should -Not -Throw
            
            Should -Invoke Write-Warning -ParameterFilter {
                $Message -like "*Failed to write to log file*"
            } -Times 1
        }
    }
}