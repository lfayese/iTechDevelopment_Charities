Set-StrictMode -Version Latest

BeforeAll {
    # Import the module file directly
    $modulePath = Split-Path -Parent $PSScriptRoot
    $runTestsPath = Join-Path -Path $modulePath -ChildPath "Run-Tests.ps1"
    
    # Create a function to run the tests
    function Invoke-TestRunner {
        param(
            [string]$TestPath,
            [string]$OutputPath = $null,
            [string]$CoverageOutputPath = $null,
            [string]$Verbosity = 'Detailed',
            [switch]$TestOnly
        )
        
        $params = @{
            TestPath = $TestPath
            Verbosity = $Verbosity
            TestOnly = $TestOnly
        }
        
        if ($OutputPath) {
            $params.OutputPath = $OutputPath
        }
        
        if ($CoverageOutputPath) {
            $params.CoverageOutputPath = $CoverageOutputPath
        }
        
        & $runTestsPath @params
    }
}

Describe "Comprehensive Test Suite" {
    Context "When running security tests" {
        It "Should run path validation security tests" {
            $testPath = Join-Path -Path $PSScriptRoot -ChildPath "Security\Path-Validation.Tests.ps1"
            $outputPath = [System.IO.Path]::GetTempFileName()
            
            $result = Invoke-TestRunner -TestPath $testPath -OutputPath $outputPath -TestOnly
            
            # Verify that the tests ran successfully
            $result.FailedCount | Should -Be 0
            $result.PassedCount | Should -BeGreaterThan 0
            
            # Clean up
            if (Test-Path $outputPath) {
                Remove-Item -Path $outputPath -Force
            }
        }
        
        It "Should run process execution security tests" {
            $testPath = Join-Path -Path $PSScriptRoot -ChildPath "Security\Process-Execution.Tests.ps1"
            $outputPath = [System.IO.Path]::GetTempFileName()
            
            $result = Invoke-TestRunner -TestPath $testPath -OutputPath $outputPath -TestOnly
            
            # Verify that the tests ran successfully
            $result.FailedCount | Should -Be 0
            $result.PassedCount | Should -BeGreaterThan 0
            
            # Clean up
            if (Test-Path $outputPath) {
                Remove-Item -Path $outputPath -Force
            }
        }
    }
    
    Context "When running performance tests" {
        It "Should run parallel processing performance tests" {
            $testPath = Join-Path -Path $PSScriptRoot -ChildPath "Performance\Parallel-Processing.Tests.ps1"
            $outputPath = [System.IO.Path]::GetTempFileName()
            
            $result = Invoke-TestRunner -TestPath $testPath -OutputPath $outputPath -TestOnly
            
            # Verify that the tests ran successfully
            $result.FailedCount | Should -Be 0
            $result.PassedCount | Should -BeGreaterThan 0
            
            # Clean up
            if (Test-Path $outputPath) {
                Remove-Item -Path $outputPath -Force
            }
        }
    }
    
    Context "When running error handling tests" {
        It "Should run error handling tests" {
            $testPath = Join-Path -Path $PSScriptRoot -ChildPath "ErrorHandling\Error-Handling.Tests.ps1"
            $outputPath = [System.IO.Path]::GetTempFileName()
            
            $result = Invoke-TestRunner -TestPath $testPath -OutputPath $outputPath -TestOnly
            
            # Verify that the tests ran successfully
            $result.FailedCount | Should -Be 0
            $result.PassedCount | Should -BeGreaterThan 0
            
            # Clean up
            if (Test-Path $outputPath) {
                Remove-Item -Path $outputPath -Force
            }
        }
    }
    
    Context "When running logging tests" {
        It "Should run logging tests" {
            $testPath = Join-Path -Path $PSScriptRoot -ChildPath "Logging\Invoke-OSDCloudLogger.Tests.ps1"
            $outputPath = [System.IO.Path]::GetTempFileName()
            
            $result = Invoke-TestRunner -TestPath $testPath -OutputPath $outputPath -TestOnly
            
            # Verify that the tests ran successfully
            $result.FailedCount | Should -Be 0
            $result.PassedCount | Should -BeGreaterThan 0
            
            # Clean up
            if (Test-Path $outputPath) {
                Remove-Item -Path $outputPath -Force
            }
        }
    }
    
    Context "When running the complete test suite" {
        It "Should run all tests successfully" {
            $testPath = Join-Path -Path $PSScriptRoot -ChildPath "Security", "Performance", "ErrorHandling", "Logging"
            $outputPath = [System.IO.Path]::GetTempFileName()
            
            $result = Invoke-TestRunner -TestPath $testPath -OutputPath $outputPath -TestOnly
            
            # Verify that the tests ran successfully
            $result.FailedCount | Should -Be 0
            $result.PassedCount | Should -BeGreaterThan 0
            
            # Clean up
            if (Test-Path $outputPath) {
                Remove-Item -Path $outputPath -Force
            }
        }
    }
}