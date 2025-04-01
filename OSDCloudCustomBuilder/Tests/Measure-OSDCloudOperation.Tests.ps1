# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module or function file directly
    . "$PSScriptRoot\..\Private\Measure-OSDCloudOperation.ps1"
    
    # Mock common functions used by the tested function
    Mock Write-OSDCloudLog { }
    Mock Get-ModuleConfiguration {
        @{
            Telemetry = @{
                Enabled = $true
            }
        }
    }
    Mock Add-PerformanceLogEntry { }
}

Describe "Measure-OSDCloudOperation" {
    Context "Parameter Validation" {
        It "Should have mandatory Name parameter" {
            (Get-Command Measure-OSDCloudOperation).Parameters['Name'].Attributes |
                Where-Object { "$_" -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -First 1 |
                ForEach-Object { "$_".Mandatory } | Should -BeTrue
        }
        
        It "Should have mandatory ScriptBlock parameter" {
            (Get-Command Measure-OSDCloudOperation).Parameters['ScriptBlock'].Attributes |
                Where-Object { "$_" -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -First 1 |
                ForEach-Object { "$_".Mandatory } | Should -BeTrue
        }
        
        It "Should have optional ArgumentList parameter" {
            (Get-Command Measure-OSDCloudOperation).Parameters['ArgumentList'] | 
                Should -Not -BeNullOrEmpty
            
            (Get-Command Measure-OSDCloudOperation).Parameters['ArgumentList'].Attributes |
                Where-Object { "$_" -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -First 1 |
                ForEach-Object { "$_".Mandatory } | Should -BeFalse
        }
        
        It "Should have optional WarningThresholdMs parameter with default value" {
            (Get-Command Measure-OSDCloudOperation).Parameters['WarningThresholdMs'] | 
                Should -Not -BeNullOrEmpty
            
            (Get-Command Measure-OSDCloudOperation).Parameters['WarningThresholdMs'].ParameterSets.Values |
                ForEach-Object { "$_".DefaultValue } | Should -Be 1000
        }
        
        It "Should have optional DisableTelemetry switch parameter" {
            (Get-Command Measure-OSDCloudOperation).Parameters['DisableTelemetry'] | 
                Should -Not -BeNullOrEmpty
            
            (Get-Command Measure-OSDCloudOperation).Parameters['DisableTelemetry'].SwitchParameter | 
                Should -BeTrue
        }
    }
    
    Context "Function Execution" {
        BeforeEach {
            # Setup test parameters
            "$testParams" = @{
                Name = "TestOperation"
                ScriptBlock = { return "Test Result" }
            }
            
            # Reset mocks
            Mock Write-OSDCloudLog { }
            Mock Get-ModuleConfiguration {
                @{
                    Telemetry = @{
                        Enabled = $true
                    }
                }
            }
            Mock Add-PerformanceLogEntry { }
            Mock Write-Warning { }
        }
        
        It "Should execute the provided script block and return its result" {
            "$result" = Measure-OSDCloudOperation @testParams
            
            $result | Should -Be "Test Result"
        }
        
        It "Should pass arguments to the script block" {
            "$argsParams" = @{
                Name = "ArgsOperation"
                ScriptBlock = { param($arg1, $arg2) return "$arg1-$arg2" }
                ArgumentList = @("Value1", "Value2")
            }
            
            "$result" = Measure-OSDCloudOperation @argsParams
            
            $result | Should -Be "Value1-Value2"
        }
        
        It "Should measure execution time and log performance data" {
            "$result" = Measure-OSDCloudOperation @testParams
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Message -like "*Starting operation: 'TestOperation'*" -and $Level -eq "Debug"
            }
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Message -like "*Operation 'TestOperation' completed in*" -and $Level -eq "Debug"
            }
            
            Should -Invoke Add-PerformanceLogEntry -Times 1 -ParameterFilter {
                $OperationName -eq "TestOperation" -and $Outcome -eq "Success"
            }
        }
        
        It "Should handle exceptions in the script block" {
            "$errorParams" = @{
                Name = "ErrorOperation"
                ScriptBlock = { throw "Test Error" }
            }
            
            { Measure-OSDCloudOperation @errorParams } | Should -Throw "Test Error"
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Level -eq "Warning" -and $Message -like "*Error: Test Error*"
            }
            
            Should -Invoke Add-PerformanceLogEntry -Times 1 -ParameterFilter {
                $OperationName -eq "ErrorOperation" -and $Outcome -eq "Failure"
            }
        }
        
        It "Should issue warning when operation exceeds threshold" {
            "$longParams" = @{
                Name = "LongOperation"
                ScriptBlock = { Start-Sleep -Milliseconds 20; return "Slow Result" }
                WarningThresholdMs = 10
            }
            
            "$result" = Measure-OSDCloudOperation @longParams
            
            Should -Invoke Write-Warning -Times 1 -ParameterFilter {
                $Message -like "*Operation 'LongOperation' took longer than expected*"
            }
        }
        
        It "Should not log telemetry when disabled via parameter" {
            "$noTelemetryParams" = @{
                Name = "NoTelemetryOperation"
                ScriptBlock = { return "No Telemetry" }
                DisableTelemetry = $true
            }
            
            "$result" = Measure-OSDCloudOperation @noTelemetryParams
            
            Should -Invoke Write-OSDCloudLog -Times 0
            Should -Invoke Add-PerformanceLogEntry -Times 0
        }
        
        It "Should not log telemetry when disabled in configuration" {
            Mock Get-ModuleConfiguration {
                @{
                    Telemetry = @{
                        Enabled = $false
                    }
                }
            }
            
            "$result" = Measure-OSDCloudOperation @testParams
            
            Should -Invoke Write-OSDCloudLog -Times 0
            Should -Invoke Add-PerformanceLogEntry -Times 0
        }
        
        It "Should continue execution when logging fails" {
            Mock Write-OSDCloudLog { throw "Logging Error" }
            
            # Should not throw despite the logging error
            { "$result" = Measure-OSDCloudOperation @testParams } | Should -Not -Throw
            
            $result | Should -Be "Test Result"
        }
        
        It "Should track memory usage" {
            "$result" = Measure-OSDCloudOperation @testParams
            
            Should -Invoke Add-PerformanceLogEntry -Times 1 -ParameterFilter {
                $ResourceUsage.ContainsKey('MemoryDeltaMB')
            }
        }
    }
}