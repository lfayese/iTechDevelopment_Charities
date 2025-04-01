BeforeAll {
    # Import the module or function file directly
    . "$PSScriptRoot\..\Private\Measure-OSDCloudOperation.ps1"
    
    # Mock common functions used by the tested function
    Mock Write-OSDCloudLog { }
    Mock Get-ModuleConfiguration {
        @{
            EnableTelemetry = $true
        }
    }
}

Describe "Measure-OSDCloudOperation" {
    Context "Parameter Validation" {
        It "Should have mandatory OperationName parameter" {
            (Get-Command Measure-OSDCloudOperation).Parameters['OperationName'].Attributes.Mandatory | 
            Should -BeTrue
        }
        
        It "Should have ScriptBlock parameter" {
            (Get-Command Measure-OSDCloudOperation).Parameters['ScriptBlock'] | 
            Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Function Execution" {
        BeforeEach {
            # Setup test parameters
            $testParams = @{
                OperationName = "TestOperation"
                ScriptBlock = { return "Test Result" }
            }
            
            # Reset mocks
            Mock Write-OSDCloudLog { }
            Mock Get-ModuleConfiguration {
                @{
                    EnableTelemetry = $true
                }
            }
        }
        
        It "Should execute the provided script block and return its result" {
            $result = Measure-OSDCloudOperation @testParams
            
            $result | Should -Be "Test Result"
        }
        
        It "Should measure execution time" {
            $result = Measure-OSDCloudOperation @testParams
            
            Should -Invoke Write-OSDCloudLog -Times 2 -ParameterFilter {
                $Message -like "*completed in*" -and $Level -eq "Info"
            }
        }
        
        It "Should handle exceptions in the script block" {
            $errorParams = @{
                OperationName = "ErrorOperation"
                ScriptBlock = { throw "Test Error" }
            }
            
            { Measure-OSDCloudOperation @errorParams } | Should -Throw
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*failed with error*"
            }
        }
        
        It "Should not log telemetry when disabled in configuration" {
            Mock Get-ModuleConfiguration {
                @{
                    EnableTelemetry = $false
                }
            }
            
            $result = Measure-OSDCloudOperation @testParams
            
            Should -Invoke Write-OSDCloudLog -Times 0 -ParameterFilter {
                $Message -like "*Telemetry:*"
            }
        }
        
        It "Should include additional properties in telemetry when provided" {
            $propsParams = @{
                OperationName = "PropsOperation"
                ScriptBlock = { return "Props Result" }
                Properties = @{
                    TestProp1 = "Value1"
                    TestProp2 = 42
                }
            }
            
            $result = Measure-OSDCloudOperation @propsParams
            
            Should -Invoke Write-OSDCloudLog -Times 1 -ParameterFilter {
                $Message -like "*Telemetry:*TestProp1*Value1*" -and
                $Message -like "*TestProp2*42*"
            }
        }
    }
}