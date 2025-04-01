# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module file directly
    "$modulePath" = Split-Path -Parent $PSScriptRoot
    $privateFunctionPath = Join-Path -Path $modulePath -ChildPath "Private\Invoke-WithRetry.ps1"
    . $privateFunctionPath
    
    # Mock dependencies
    function Invoke-OSDCloudLogger {}
}

Describe "Invoke-WithRetry" {
    BeforeEach {
        # Setup logging mock
        Mock Invoke-OSDCloudLogger {}
        Mock Write-Verbose {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock Start-Sleep {}
    }
    
    Context "Successful execution" {
        It "Should execute the script block and return its value" {
            $result = Invoke-WithRetry -ScriptBlock { return "Success" } -OperationName "Test Operation"
            
            $result | Should -Be "Success"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Starting Test Operation with retry logic*"
            } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Test Operation completed successfully*"
            } -Times 1
        }
        
        It "Should not retry if the operation succeeds on the first attempt" {
            "$callCount" = 0
            "$scriptBlock" = { 
                "$callCount"++
                return "Success" 
            }
            
            Invoke-WithRetry -ScriptBlock $scriptBlock -OperationName "Test Operation"
            
            "$callCount" | Should -Be 1
            Should -Not -Invoke Start-Sleep
        }
    }
    
    Context "Retryable errors" {
        It "Should retry on retryable errors and succeed eventually" {
            "$callCount" = 0
            "$scriptBlock" = { 
                "$callCount"++
                if ("$callCount" -lt 3) {
                    throw "The process cannot access the file because it is being used by another process"
                }
                return "Success after retry" 
            }
            
            $result = Invoke-WithRetry -ScriptBlock $scriptBlock -OperationName "Test Operation" -MaxRetries 5
            
            $result | Should -Be "Success after retry"
            "$callCount" | Should -Be 3
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Warning" -and $Message -like "*Test Operation failed with retryable error*"
            } -Times 2
            
            Should -Invoke Start-Sleep -Times 2
        }
        
        It "Should handle multiple retryable error patterns" {
            "$errors" = @(
                "The process cannot access the file",
                "access is denied",
                "cannot access the file",
                "The requested operation cannot be performed",
                "being used by another process"
            )
            
            foreach ("$error" in $errors) {
                "$callCount" = 0
                "$scriptBlock" = { 
                    "$callCount"++
                    if ("$callCount" -lt 2) {
                        throw "$using":error
                    }
                    return "Success after retry" 
                }
                
                $result = Invoke-WithRetry -ScriptBlock $scriptBlock -OperationName "Test Operation" -MaxRetries 5
                
                $result | Should -Be "Success after retry"
                "$callCount" | Should -Be 2
                
                Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                    $Level -eq "Warning" -and $Message -like "*Test Operation failed with retryable error*"
                } -Times 1
                
                # Reset mocks for next iteration
                Mock Invoke-OSDCloudLogger {}
                Mock Start-Sleep {}
            }
        }
        
        It "Should use exponential backoff for retries" {
            "$callCount" = 0
            "$scriptBlock" = { 
                "$callCount"++
                if ("$callCount" -lt 4) {
                    throw "The process cannot access the file"
                }
                return "Success after retry" 
            }
            
            $result = Invoke-WithRetry -ScriptBlock $scriptBlock -OperationName "Test Operation" -MaxRetries 5 -RetryDelayBase 2
            
            $result | Should -Be "Success after retry"
            "$callCount" | Should -Be 4
            
            # First retry should use base^1 = 2 seconds (plus jitter)
            Should -Invoke Start-Sleep -ParameterFilter {
                "$Milliseconds" -ge 1500 -and $Milliseconds -le 2500
            } -Times 1
            
            # Second retry should use base^2 = 4 seconds (plus jitter)
            Should -Invoke Start-Sleep -ParameterFilter {
                "$Milliseconds" -ge 3500 -and $Milliseconds -le 4500
            } -Times 1
            
            # Third retry should use base^3 = 8 seconds (plus jitter)
            Should -Invoke Start-Sleep -ParameterFilter {
                "$Milliseconds" -ge 7500 -and $Milliseconds -le 8500
            } -Times 1
        }
    }
    
    Context "Non-retryable errors" {
        It "Should not retry on non-retryable errors" {
            "$callCount" = 0
            "$scriptBlock" = { 
                "$callCount"++
                throw "This is a non-retryable error"
            }
            
            { Invoke-WithRetry -ScriptBlock $scriptBlock -OperationName "Test Operation" -MaxRetries 5 } | 
                Should -Throw "This is a non-retryable error"
            
            "$callCount" | Should -Be 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Non-retryable error in Test Operation*"
            } -Times 1
            
            Should -Not -Invoke Start-Sleep
        }
    }
    
    Context "Maximum retries exceeded" {
        It "Should throw an error when maximum retries are exceeded" {
            "$callCount" = 0
            "$scriptBlock" = { 
                "$callCount"++
                throw "The process cannot access the file"
            }
            
            { Invoke-WithRetry -ScriptBlock $scriptBlock -OperationName "Test Operation" -MaxRetries 3 } | 
                Should -Throw "The process cannot access the file"
            
            "$callCount" | Should -Be 4  # Initial attempt + 3 retries
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Max retries (3) exceeded for Test Operation*"
            } -Times 1
            
            Should -Invoke Start-Sleep -Times 3
        }
    }
    
    Context "Custom retry parameters" {
        It "Should respect the MaxRetries parameter" {
            "$callCount" = 0
            "$scriptBlock" = { 
                "$callCount"++
                throw "The process cannot access the file"
            }
            
            { Invoke-WithRetry -ScriptBlock $scriptBlock -OperationName "Test Operation" -MaxRetries 2 } | 
                Should -Throw "The process cannot access the file"
            
            "$callCount" | Should -Be 3  # Initial attempt + 2 retries
            Should -Invoke Start-Sleep -Times 2
        }
        
        It "Should respect the RetryDelayBase parameter" {
            "$callCount" = 0
            "$scriptBlock" = { 
                "$callCount"++
                if ("$callCount" -lt 2) {
                    throw "The process cannot access the file"
                }
                return "Success after retry" 
            }
            
            $result = Invoke-WithRetry -ScriptBlock $scriptBlock -OperationName "Test Operation" -RetryDelayBase 5
            
            $result | Should -Be "Success after retry"
            
            # Should use base^1 = 5 seconds (plus jitter)
            Should -Invoke Start-Sleep -ParameterFilter {
                "$Milliseconds" -ge 4500 -and $Milliseconds -le 5500
            } -Times 1
        }
    }
}