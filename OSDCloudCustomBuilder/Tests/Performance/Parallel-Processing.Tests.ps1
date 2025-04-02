Set-StrictMode -Version Latest

BeforeAll {
    # Import the module file directly
    $modulePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    
    # Import the functions we'll need for testing
    $parallelPath = Join-Path -Path $modulePath -ChildPath "Private\Copy-FilesInParallel.ps1"
    if (Test-Path $parallelPath) {
        . $parallelPath
    }
    
    # Mock dependencies
    function Invoke-OSDCloudLogger {}
}

Describe "Performance Tests" {
    BeforeEach {
        # Setup default mocks for each test
        Mock Write-Verbose {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock Test-Path { return $true }
        Mock Invoke-OSDCloudLogger {}
        Mock Copy-Item {}
        Mock Get-Item { 
            return [PSCustomObject]@{ 
                FullName = "TestFile.txt"
                Length = 1024
            } 
        }
        Mock Measure-Command { 
            return [PSCustomObject]@{ 
                TotalMilliseconds = 100 
            } 
        }
    }
    
    Context "When copying files in parallel" {
        It "Should handle large numbers of files efficiently" {
            # Create a large list of test files
            $sourceFiles = @()
            for ($i = 1; $i -le 1000; $i++) {
                $sourceFiles += "C:\Source\file$i.txt"
            }
            $destination = "D:\Destination"
            
            # Test the function
            $result = Copy-FilesInParallel -SourceFiles $sourceFiles -Destination $destination -ThrottleLimit 16
            
            # Verify that the function processed all files
            $result.Count | Should -Be 1000
            
            # Verify that the function used parallel processing
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Using parallel processing*" -and $Level -eq "Info"
            }
        }
        
        It "Should fall back to sequential processing when appropriate" {
            # Create a small list of test files (should use sequential)
            $sourceFiles = @("C:\Source\file1.txt", "C:\Source\file2.txt")
            $destination = "D:\Destination"
            
            # Test the function
            $result = Copy-FilesInParallel -SourceFiles $sourceFiles -Destination $destination
            
            # Verify that the function processed all files
            $result.Count | Should -Be 2
            
            # Verify that the function used sequential processing
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Using sequential processing*" -and $Level -eq "Info"
            }
        }
        
        It "Should respect the throttle limit parameter" {
            # Create a large list of test files
            $sourceFiles = @()
            for ($i = 1; $i -le 100; $i++) {
                $sourceFiles += "C:\Source\file$i.txt"
            }
            $destination = "D:\Destination"
            $throttleLimit = 8
            
            # Test the function
            $result = Copy-FilesInParallel -SourceFiles $sourceFiles -Destination $destination -ThrottleLimit $throttleLimit
            
            # Verify that the function processed all files
            $result.Count | Should -Be 100
            
            # Verify that the function used the specified throttle limit
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Using throttle limit: $throttleLimit*" -and $Level -eq "Info"
            }
        }
    }
    
    Context "When handling string operations" {
        It "Should efficiently process string operations" {
            # Mock a function that uses string operations
            function Test-StringPerformance {
                param([int]$Iterations = 1000)
                
                $start = Get-Date
                
                # Direct variable usage (optimized)
                for ($i = 0; $i -lt $Iterations; $i++) {
                    $path = "C:\Temp\file$i.txt"
                    $dirname = Split-Path -Parent $path
                    $basename = Split-Path -Leaf $path
                }
                
                $optimizedTime = (Get-Date) - $start
                
                $start = Get-Date
                
                # String interpolation (less optimized)
                for ($i = 0; $i -lt $Iterations; $i++) {
                    $path = "C:\Temp\file$i.txt"
                    $dirname = Split-Path -Parent "$path"
                    $basename = Split-Path -Leaf "$path"
                }
                
                $interpolationTime = (Get-Date) - $start
                
                return @{
                    OptimizedTime = $optimizedTime.TotalMilliseconds
                    InterpolationTime = $interpolationTime.TotalMilliseconds
                    Improvement = [math]::Round(($interpolationTime.TotalMilliseconds / $optimizedTime.TotalMilliseconds), 2)
                }
            }
            
            # Test the function
            $result = Test-StringPerformance -Iterations 1000
            
            # Verify that direct variable usage is faster
            $result.OptimizedTime | Should -BeLessThan $result.InterpolationTime
            
            # Verify that there's a measurable improvement
            $result.Improvement | Should -BeGreaterThan 1.0
        }
    }
    
    Context "When handling cancellation of operations" {
        It "Should support cancellation of long-running operations" {
            # Create a mock function that supports cancellation
            function Test-Cancellation {
                param(
                    [System.Threading.CancellationToken]$CancellationToken
                )
                
                $result = @{
                    Completed = 0
                    Cancelled = $false
                }
                
                for ($i = 0; $i -lt 100; $i++) {
                    if ($CancellationToken.IsCancellationRequested) {
                        $result.Cancelled = $true
                        break
                    }
                    
                    # Simulate work
                    Start-Sleep -Milliseconds 10
                    $result.Completed++
                }
                
                return $result
            }
            
            # Create a cancellation token and source
            $cts = New-Object System.Threading.CancellationTokenSource
            
            # Start the operation in a background job
            $job = Start-Job -ScriptBlock {
                param($cts)
                
                # Wait a bit then cancel
                Start-Sleep -Milliseconds 50
                $cts.Cancel()
                
                return "Cancelled"
            } -ArgumentList $cts
            
            # Run the test function
            $result = Test-Cancellation -CancellationToken $cts.Token
            
            # Wait for the cancellation job to complete
            $jobResult = Receive-Job -Job $job -Wait
            Remove-Job -Job $job
            
            # Verify that the operation was cancelled
            $result.Cancelled | Should -Be $true
            
            # Verify that not all iterations were completed
            $result.Completed | Should -BeLessThan 100
            
            # Clean up
            $cts.Dispose()
        }
    }
}