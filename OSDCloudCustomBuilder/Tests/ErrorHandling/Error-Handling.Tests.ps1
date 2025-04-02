Set-StrictMode -Version Latest

BeforeAll {
    # Import the module file directly
    $modulePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    
    # Import the functions we'll need for testing
    $errorHandlingPath = Join-Path -Path $modulePath -ChildPath "Private\Error-Handling.ps1"
    if (Test-Path $errorHandlingPath) {
        . $errorHandlingPath
    }
    
    # Mock dependencies
    function Invoke-OSDCloudLogger {}
}

Describe "Error Handling Tests" {
    BeforeEach {
        # Setup default mocks for each test
        Mock Write-Verbose {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock Invoke-OSDCloudLogger {}
    }
    
    Context "When handling various error types" {
        It "Should handle file not found errors consistently" {
            # Define a test function that will throw a file not found error
            function Test-FileNotFoundError {
                param([string]$FilePath)
                
                try {
                    if (-not (Test-Path $FilePath)) {
                        throw [System.IO.FileNotFoundException]::new("File not found: $FilePath", $FilePath)
                    }
                }
                catch {
                    # Call the error handling function
                    Handle-Error -Error $_ -Component "Test-FileNotFoundError" -Message "Failed to process file" -FilePath $FilePath
                    throw  # Re-throw to test exception propagation
                }
            }
            
            # Mock the error handling function
            Mock Handle-Error {}
            
            # Test with a non-existent file
            $testPath = "C:\NonExistent\file.txt"
            { Test-FileNotFoundError -FilePath $testPath } | Should -Throw "*File not found*"
            
            # Verify that the error handler was called with the correct parameters
            Should -Invoke Handle-Error -ParameterFilter {
                $Component -eq "Test-FileNotFoundError" -and 
                $Message -like "*Failed to process file*" -and
                $FilePath -eq $testPath
            }
        }
        
        It "Should handle access denied errors consistently" {
            # Define a test function that will throw an access denied error
            function Test-AccessDeniedError {
                param([string]$FilePath)
                
                try {
                    throw [System.UnauthorizedAccessException]::new("Access denied: $FilePath")
                }
                catch {
                    # Call the error handling function
                    Handle-Error -Error $_ -Component "Test-AccessDeniedError" -Message "Failed to access file" -FilePath $FilePath
                    throw  # Re-throw to test exception propagation
                }
            }
            
            # Mock the error handling function
            Mock Handle-Error {}
            
            # Test with a path
            $testPath = "C:\Protected\file.txt"
            { Test-AccessDeniedError -FilePath $testPath } | Should -Throw "*Access denied*"
            
            # Verify that the error handler was called with the correct parameters
            Should -Invoke Handle-Error -ParameterFilter {
                $Component -eq "Test-AccessDeniedError" -and 
                $Message -like "*Failed to access file*" -and
                $FilePath -eq $testPath
            }
        }
        
        It "Should handle timeout errors consistently" {
            # Define a test function that will throw a timeout error
            function Test-TimeoutError {
                param([string]$Operation)
                
                try {
                    throw [System.TimeoutException]::new("Operation timed out: $Operation")
                }
                catch {
                    # Call the error handling function
                    Handle-Error -Error $_ -Component "Test-TimeoutError" -Message "Operation timed out" -Operation $Operation
                    throw  # Re-throw to test exception propagation
                }
            }
            
            # Mock the error handling function
            Mock Handle-Error {}
            
            # Test with an operation
            $testOperation = "File copy"
            { Test-TimeoutError -Operation $testOperation } | Should -Throw "*timed out*"
            
            # Verify that the error handler was called with the correct parameters
            Should -Invoke Handle-Error -ParameterFilter {
                $Component -eq "Test-TimeoutError" -and 
                $Message -like "*Operation timed out*" -and
                $Operation -eq $testOperation
            }
        }
    }
    
    Context "When handling errors with proper context" {
        It "Should include detailed context in error messages" {
            # Define a test function that includes context in error handling
            function Test-ContextualError {
                param(
                    [string]$FilePath,
                    [string]$Operation,
                    [hashtable]$Context
                )
                
                try {
                    throw [System.Exception]::new("Operation failed")
                }
                catch {
                    # Call the error handling function with context
                    Handle-Error -Error $_ -Component "Test-ContextualError" -Message "Operation failed" -Context $Context
                    throw  # Re-throw to test exception propagation
                }
            }
            
            # Mock the error handling function
            Mock Handle-Error {}
            
            # Test with context
            $testContext = @{
                FilePath = "C:\Test\file.txt"
                Operation = "Copy"
                Timestamp = Get-Date
                User = "TestUser"
                SessionId = "12345"
            }
            
            { Test-ContextualError -Context $testContext } | Should -Throw "*Operation failed*"
            
            # Verify that the error handler was called with the correct context
            Should -Invoke Handle-Error -ParameterFilter {
                $Component -eq "Test-ContextualError" -and 
                $Message -like "*Operation failed*" -and
                $Context.FilePath -eq "C:\Test\file.txt" -and
                $Context.Operation -eq "Copy" -and
                $Context.User -eq "TestUser" -and
                $Context.SessionId -eq "12345"
            }
        }
    }
    
    Context "When propagating errors" {
        It "Should properly propagate errors up the call stack" {
            # Define a nested set of functions to test error propagation
            function Inner-Function {
                param([string]$Message)
                
                throw [System.Exception]::new($Message)
            }
            
            function Middle-Function {
                param([string]$Message)
                
                try {
                    Inner-Function -Message $Message
                }
                catch {
                    # Add context and re-throw
                    $_.ErrorDetails = "Error in Middle-Function: $($_.Exception.Message)"
                    throw
                }
            }
            
            function Outer-Function {
                param([string]$Message)
                
                try {
                    Middle-Function -Message $Message
                }
                catch {
                    # Log and re-throw
                    Invoke-OSDCloudLogger -Level Error -Component "Outer-Function" -Message "Error: $($_.Exception.Message)"
                    throw
                }
            }
            
            # Test the error propagation
            $testMessage = "Test error message"
            { Outer-Function -Message $testMessage } | Should -Throw "*$testMessage*"
            
            # Verify that the error was logged at the outer level
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and 
                $Component -eq "Outer-Function" -and
                $Message -like "*$testMessage*"
            }
        }
    }
    
    Context "When handling non-terminating errors" {
        It "Should properly handle non-terminating errors" {
            # Define a test function that handles non-terminating errors
            function Test-NonTerminatingError {
                [CmdletBinding()]
                param()
                
                # Create a non-terminating error
                Write-Error "Non-terminating error" -ErrorAction Continue
                
                # This should still execute
                return "Function completed"
            }
            
            # Test the function
            $result = Test-NonTerminatingError -ErrorVariable errors -ErrorAction SilentlyContinue
            
            # Verify that the function completed
            $result | Should -Be "Function completed"
            
            # Verify that the error was recorded
            $errors.Count | Should -Be 1
            $errors[0].Exception.Message | Should -Be "Non-terminating error"
        }
    }
    
    Context "When handling errors with retry logic" {
        It "Should retry operations that fail temporarily" {
            # Define a test function with retry logic
            function Test-RetryLogic {
                param(
                    [int]$MaxRetries = 3,
                    [int]$RetryDelayMs = 10
                )
                
                $attempts = 0
                $success = $false
                
                while (-not $success -and $attempts -lt $MaxRetries) {
                    try {
                        $attempts++
                        
                        if ($attempts -lt 3) {
                            # Fail on the first two attempts
                            throw [System.Exception]::new("Temporary failure")
                        }
                        
                        # Succeed on the third attempt
                        $success = $true
                        return "Operation succeeded on attempt $attempts"
                    }
                    catch {
                        if ($attempts -ge $MaxRetries) {
                            Invoke-OSDCloudLogger -Level Error -Component "Test-RetryLogic" -Message "Failed after $attempts attempts: $($_.Exception.Message)"
                            throw
                        }
                        
                        Invoke-OSDCloudLogger -Level Warning -Component "Test-RetryLogic" -Message "Attempt $attempts failed: $($_.Exception.Message). Retrying in $RetryDelayMs ms."
                        Start-Sleep -Milliseconds $RetryDelayMs
                    }
                }
            }
            
            # Test the retry logic
            $result = Test-RetryLogic
            
            # Verify that the operation succeeded after retries
            $result | Should -Be "Operation succeeded on attempt 3"
            
            # Verify that warnings were logged for the failed attempts
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Warning" -and 
                $Component -eq "Test-RetryLogic" -and
                $Message -like "*Attempt 1 failed*"
            }
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Warning" -and 
                $Component -eq "Test-RetryLogic" -and
                $Message -like "*Attempt 2 failed*"
            }
        }
    }
}