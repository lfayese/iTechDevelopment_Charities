BeforeAll {
    # Import module for testing
    $ModuleName = 'OSDCloudCustomBuilder'
    $ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    
    # Remove module if already loaded
    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction Ignore
    
    # Import the module directly from the development path
    Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath "$ModuleName.psd1") -Force
}

Describe "Error Handling System Tests" -Tag "Unit", "ErrorHandling" {
    Context "OSDCloudCustomBuilderError Class" {
        It "Creates error object with basic properties" {
            InModuleScope $ModuleName {
                $error = [OSDCloudCustomBuilderError]::new(
                    "Test error message", 
                    [ErrorCategory]::Validation, 
                    "TestSource"
                )
                
                $error.Message | Should -Be "Test error message"
                $error.Category | Should -Be "Validation"
                $error.Source | Should -Be "TestSource"
                $error.ErrorId | Should -Not -BeNullOrEmpty
                $error.AdditionalData | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Creates error object with original error record" {
            InModuleScope $ModuleName {
                # Create a test error record
                $testException = [System.Exception]::new("Original error")
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $testException,
                    "TestErrorId",
                    [System.Management.Automation.ErrorCategory]::NotSpecified,
                    $null
                )
                
                $error = [OSDCloudCustomBuilderError]::new(
                    "Custom message", 
                    [ErrorCategory]::FileSystem, 
                    "TestSource", 
                    $errorRecord
                )
                
                $error.Message | Should -Be "Custom message"
                $error.OriginalError | Should -Not -BeNullOrEmpty
                $error.OriginalError.Exception.Message | Should -Be "Original error"
            }
        }
        
        It "Formats ToString output correctly" {
            InModuleScope $ModuleName {
                $error = [OSDCloudCustomBuilderError]::new(
                    "Test error message", 
                    [ErrorCategory]::Validation, 
                    "TestSource"
                )
                
                $stringOutput = $error.ToString()
                $stringOutput | Should -Match "Validation"
                $stringOutput | Should -Match "TestSource"
                $stringOutput | Should -Match "Test error message"
            }
        }
    }
    
    Context "New-OSDCloudException Function" {
        It "Creates exception with basic info" {
            InModuleScope $ModuleName {
                $error = New-OSDCloudException -Message "Test exception" -Category Network -Source "TestFunction"
                
                $error | Should -BeOfType OSDCloudCustomBuilderError
                $error.Message | Should -Be "Test exception"
                $error.Category | Should -Be "Network"
                $error.Source | Should -Be "TestFunction"
            }
        }
        
        It "Adds additional data to exception" {
            InModuleScope $ModuleName {
                $additionalData = @{
                    Operation = "Download"
                    Target = "https://example.com"
                    RetryCount = 3
                }
                
                $error = New-OSDCloudException -Message "Test exception" -Category Network -Source "TestFunction" -AdditionalData $additionalData
                
                $error.AdditionalData["Operation"] | Should -Be "Download"
                $error.AdditionalData["Target"] | Should -Be "https://example.com"
                $error.AdditionalData["RetryCount"] | Should -Be 3
            }
        }
    }
    
    Context "Write-OSDCloudError Function" {
        BeforeAll {
            # Mock Write-OSDCloudLog to avoid actual logging during tests
            Mock -ModuleName $ModuleName Write-OSDCloudLog {}
            
            # Mock Get-ModuleConfiguration to control test behavior
            Mock -ModuleName $ModuleName Get-ModuleConfiguration {
                return @{
                    ErrorHandling = @{
                        ContinueOnError = $false
                    }
                }
            }
        }
        
        It "Adds error to collection" {
            InModuleScope $ModuleName {
                # Reset error collection
                $script:ErrorCollection = [System.Collections.Generic.List[OSDCloudCustomBuilderError]]::new()
                
                # Create a test error record
                $testException = [System.Exception]::new("Test exception")
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $testException,
                    "TestErrorId",
                    [System.Management.Automation.ErrorCategory]::NotSpecified,
                    $null
                )
                
                # Test function - using try/catch to handle the terminating error
                try {
                    Write-OSDCloudError -ErrorRecord $errorRecord -Message "Custom error message" -Category FileSystem -Source "TestFunction"
                }
                catch {
                    # Expected to throw
                }
                
                # Verify the error was added to collection
                $script:ErrorCollection.Count | Should -Be 1
                $script:ErrorCollection[0].Message | Should -Be "Custom error message"
                $script:ErrorCollection[0].Category | Should -Be "FileSystem"
            }
        }
        
        It "Respects SuppressError switch" {
            InModuleScope $ModuleName {
                # Reset error collection
                $script:ErrorCollection = [System.Collections.Generic.List[OSDCloudCustomBuilderError]]::new()
                
                # Create a test error record
                $testException = [System.Exception]::new("Test exception")
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $testException,
                    "TestErrorId",
                    [System.Management.Automation.ErrorCategory]::NotSpecified,
                    $null
                )
                
                # Test function - should not throw with SuppressError
                { Write-OSDCloudError -ErrorRecord $errorRecord -Message "Custom error message" -Category FileSystem -Source "TestFunction" -SuppressError } | 
                Should -Not -Throw
                
                # Verify the error was added to collection
                $script:ErrorCollection.Count | Should -Be 1
            }
        }
    }
    
    Context "Get-OSDCloudErrors Function" {
        It "Returns all errors and clears with -Clear switch" {
            InModuleScope $ModuleName {
                # Reset error collection with test errors
                $script:ErrorCollection = [System.Collections.Generic.List[OSDCloudCustomBuilderError]]::new()
                
                # Add test errors
                $error1 = [OSDCloudCustomBuilderError]::new("Error 1", [ErrorCategory]::Validation, "Source1")
                $error2 = [OSDCloudCustomBuilderError]::new("Error 2", [ErrorCategory]::Network, "Source2")
                
                $script:ErrorCollection.Add($error1)
                $script:ErrorCollection.Add($error2)
                
                # Get errors with clear
                $errors = Get-OSDCloudErrors -Clear
                
                # Verify results
                $errors.Count | Should -Be 2
                $script:ErrorCollection.Count | Should -Be 0
            }
        }
    }
}

Describe "Advanced Error Handling in Functions" -Tag "Integration", "ErrorHandling" {
    BeforeAll {
        # Mock test functions to simulate errors
        Mock -ModuleName $ModuleName Get-CachedPowerShellPackage { return $null }
        Mock -ModuleName $ModuleName Test-ValidPath { 
            param($Path, $MustExist)
            if ($Path -eq "C:\nonexistent.wim" -and $MustExist) { 
                return $false 
            }
            return $true
        }
        Mock -ModuleName $ModuleName Test-IsAdmin { return $true }
        Mock -ModuleName $ModuleName Write-OSDCloudLog {}
    }
    
    Context "Update-CustomWimWithPwsh7Advanced Function" {
        It "Handles non-existent WIM path" {
            { Update-CustomWimWithPwsh7Advanced -WimPath "C:\nonexistent.wim" -PowerShellVersion "7.5.0" } | 
            Should -Throw -ExpectedMessage "*WIM file not found*"
        }
        
        It "Validates PowerShell version format" {
            { Update-CustomWimWithPwsh7Advanced -WimPath "C:\valid.wim" -PowerShellVersion "invalid" } | 
            Should -Throw -ExpectedMessage "*Invalid PowerShell version format*"
        }
        
        It "Handles PowerShell package retrieval failures" {
            # This will fail because our mock returns null
            $result = Update-CustomWimWithPwsh7Advanced -WimPath "C:\valid.wim" -PowerShellVersion "7.5.0"
            $result | Should -Be $false
        }
    }
}

AfterAll {
    # Clean up 
    Get-Module -Name $ModuleName -All | Remove-Module -Force -ErrorAction Ignore
}