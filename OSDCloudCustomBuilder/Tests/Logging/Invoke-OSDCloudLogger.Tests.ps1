Set-StrictMode -Version Latest

BeforeAll {
    # Import the module file directly
    $modulePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    
    # Import the functions we'll need for testing
    $loggerPath = Join-Path -Path $modulePath -ChildPath "Private\Invoke-OSDCloudLogger.ps1"
    if (Test-Path $loggerPath) {
        . $loggerPath
    }
}

Describe "Logging Tests" {
    BeforeEach {
        # Setup default mocks for each test
        Mock Write-Verbose {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock Write-Host {}
        Mock Out-File {}
        
        # Create a temporary log file path for testing
        $script:TestLogFile = [System.IO.Path]::GetTempFileName()
        
        # Mock Get-OSDCloudLogFile to return our test log file
        Mock Get-OSDCloudLogFile { return $script:TestLogFile }
    }
    
    AfterEach {
        # Clean up the test log file
        if (Test-Path $script:TestLogFile) {
            Remove-Item -Path $script:TestLogFile -Force
        }
    }
    
    Context "When verifying log metadata" {
        It "Should include timestamp in log entries" {
            # Call the logger
            Invoke-OSDCloudLogger -Level Info -Component "Test" -Message "Test message"
            
            # Verify that the log entry includes a timestamp
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"
            }
        }
        
        It "Should include log level in log entries" {
            # Call the logger with different levels
            Invoke-OSDCloudLogger -Level Info -Component "Test" -Message "Info message"
            Invoke-OSDCloudLogger -Level Warning -Component "Test" -Message "Warning message"
            Invoke-OSDCloudLogger -Level Error -Component "Test" -Message "Error message"
            
            # Verify that the log entries include the correct levels
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "INFO"
            }
            
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "WARNING"
            }
            
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "ERROR"
            }
        }
        
        It "Should include component name in log entries" {
            # Call the logger with a specific component
            $testComponent = "TestComponent"
            Invoke-OSDCloudLogger -Level Info -Component $testComponent -Message "Test message"
            
            # Verify that the log entry includes the component
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match $testComponent
            }
        }
        
        It "Should include process ID in log entries" {
            # Call the logger
            Invoke-OSDCloudLogger -Level Info -Component "Test" -Message "Test message"
            
            # Get the current process ID
            $processId = [System.Diagnostics.Process]::GetCurrentProcess().Id
            
            # Verify that the log entry includes the process ID
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "\[$processId\]"
            }
        }
        
        It "Should include thread ID in log entries" {
            # Call the logger
            Invoke-OSDCloudLogger -Level Info -Component "Test" -Message "Test message"
            
            # Verify that the log entry includes a thread ID
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "Thread-\d+"
            }
        }
    }
    
    Context "When testing concurrent logging" {
        It "Should handle concurrent logging from multiple threads" {
            # Create a script block to run in parallel
            $scriptBlock = {
                param($Id, $LoggerPath, $TestLogFile)
                
                # Import the logger function
                . $LoggerPath
                
                # Mock Get-OSDCloudLogFile to return our test log file
                function Get-OSDCloudLogFile { return $TestLogFile }
                
                # Log a message
                Invoke-OSDCloudLogger -Level Info -Component "Thread$Id" -Message "Message from thread $Id"
                
                return "Thread $Id completed"
            }
            
            # Run the script block in multiple jobs
            $jobs = @()
            for ($i = 1; $i -le 10; $i++) {
                $jobs += Start-Job -ScriptBlock $scriptBlock -ArgumentList $i, $loggerPath, $script:TestLogFile
            }
            
            # Wait for all jobs to complete
            $results = $jobs | Wait-Job | Receive-Job
            
            # Clean up the jobs
            $jobs | Remove-Job
            
            # Verify that all threads completed
            $results.Count | Should -Be 10
            
            # Verify that the log file exists and contains entries from all threads
            $logContent = Get-Content -Path $script:TestLogFile -ErrorAction SilentlyContinue
            
            # Check if all threads logged successfully
            for ($i = 1; $i -le 10; $i++) {
                $threadEntries = $logContent | Where-Object { $_ -match "Thread$i" }
                $threadEntries | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context "When testing fallback mechanisms" {
        It "Should fall back to console logging when file logging fails" {
            # Mock Out-File to throw an error
            Mock Out-File { throw "Cannot write to log file" }
            
            # Call the logger
            Invoke-OSDCloudLogger -Level Warning -Component "Test" -Message "Test fallback message"
            
            # Verify that fallback to console occurred
            Should -Invoke Write-Warning -ParameterFilter {
                $Message -like "*Test fallback message*"
            }
            
            # Verify that the fallback was logged
            Should -Invoke Write-Warning -ParameterFilter {
                $Message -like "*Fallback to console logging*"
            }
        }
        
        It "Should attempt to create the log directory if it doesn't exist" {
            # Mock Get-OSDCloudLogFile to return a path in a non-existent directory
            $nonExistentDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "NonExistentDir")
            $nonExistentLogFile = [System.IO.Path]::Combine($nonExistentDir, "test.log")
            Mock Get-OSDCloudLogFile { return $nonExistentLogFile }
            
            # Mock Test-Path to return false for the directory
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $nonExistentDir }
            
            # Mock New-Item to simulate creating the directory
            Mock New-Item { return [PSCustomObject]@{ FullName = $nonExistentDir } } -ParameterFilter { $Path -eq $nonExistentDir -and $ItemType -eq "Directory" }
            
            # Call the logger
            Invoke-OSDCloudLogger -Level Info -Component "Test" -Message "Test directory creation"
            
            # Verify that an attempt was made to create the directory
            Should -Invoke New-Item -ParameterFilter {
                $Path -eq $nonExistentDir -and $ItemType -eq "Directory"
            }
        }
        
        It "Should handle errors during log rotation" {
            # Mock functions related to log rotation
            Mock Get-ChildItem { throw "Error during log enumeration" }
            
            # Call the logger with log rotation
            Invoke-OSDCloudLogger -Level Info -Component "Test" -Message "Test message" -EnableRotation
            
            # Verify that the error was handled and logging continued
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "Test message"
            }
            
            # Verify that the rotation error was logged
            Should -Invoke Write-Warning -ParameterFilter {
                $Message -like "*Failed to rotate logs*"
            }
        }
    }
    
    Context "When testing log levels and filtering" {
        It "Should respect the minimum log level" {
            # Set the minimum log level to Warning
            Mock Get-OSDCloudLogLevel { return "Warning" }
            
            # Call the logger with different levels
            Invoke-OSDCloudLogger -Level Info -Component "Test" -Message "Info message"
            Invoke-OSDCloudLogger -Level Warning -Component "Test" -Message "Warning message"
            Invoke-OSDCloudLogger -Level Error -Component "Test" -Message "Error message"
            
            # Verify that only Warning and Error messages were logged
            Should -Not -Invoke Out-File -ParameterFilter {
                $InputObject -match "INFO.*Info message"
            }
            
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "WARNING.*Warning message"
            }
            
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "ERROR.*Error message"
            }
        }
        
        It "Should support component filtering" {
            # Set up component filtering
            Mock Get-OSDCloudLogComponents { return @("Component1", "Component3") }
            
            # Call the logger with different components
            Invoke-OSDCloudLogger -Level Info -Component "Component1" -Message "Message 1"
            Invoke-OSDCloudLogger -Level Info -Component "Component2" -Message "Message 2"
            Invoke-OSDCloudLogger -Level Info -Component "Component3" -Message "Message 3"
            
            # Verify that only messages from Component1 and Component3 were logged
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "Component1.*Message 1"
            }
            
            Should -Not -Invoke Out-File -ParameterFilter {
                $InputObject -match "Component2.*Message 2"
            }
            
            Should -Invoke Out-File -ParameterFilter {
                $InputObject -match "Component3.*Message 3"
            }
        }
    }
}