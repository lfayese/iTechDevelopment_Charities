Set-StrictMode -Version Latest

BeforeAll {
    # Import the module file directly
    $modulePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    
    # Import the functions we'll need for testing
    $helperFunctionsPath = Join-Path -Path $modulePath -ChildPath "Private\Process-Execution.ps1"
    if (Test-Path $helperFunctionsPath) {
        . $helperFunctionsPath
    }
    
    $copyWimPath = Join-Path -Path $modulePath -ChildPath "Public\Copy-CustomWimToWorkspace.ps1"
    if (Test-Path $copyWimPath) {
        . $copyWimPath
    }
    
    # Mock dependencies
    function Invoke-OSDCloudLogger {}
}

Describe "Process Execution Security Tests" {
    BeforeEach {
        # Setup default mocks for each test
        Mock Write-Verbose {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock Test-Path { return $true }
        Mock Invoke-OSDCloudLogger {}
        Mock Start-Process { return [PSCustomObject]@{ ExitCode = 0 } }
        
        # Mock Security.Principal.WindowsPrincipal
        Mock ([Security.Principal.WindowsPrincipal]).GetMethod('IsInRole') { return $true }
    }
    
    Context "When executing external processes" {
        It "Should properly escape command arguments with spaces" {
            $wimPath = "C:\Path With Spaces\install.wim"
            $workspacePath = "D:\Target Path\Workspace"
            
            Copy-CustomWimToWorkspace -WimPath $wimPath -WorkspacePath $workspacePath -WhatIf
            
            # Verify the process is executed with properly escaped arguments
            Should -Invoke Start-Process -ParameterFilter {
                $ArgumentList -match '"C:\\Path With Spaces\\install.wim"' -and 
                $ArgumentList -match '"D:\\Target Path\\Workspace"'
            }
        }
        
        It "Should properly escape command arguments with quotes" {
            $wimPath = 'C:\Path"With"Quotes\install.wim'
            $workspacePath = "D:\Target\Workspace"
            
            # This should handle the quotes properly
            Copy-CustomWimToWorkspace -WimPath $wimPath -WorkspacePath $workspacePath -WhatIf
            
            # Verify the process is executed with properly escaped arguments
            Should -Invoke Start-Process -ParameterFilter {
                $ArgumentList -match 'C:\\Path\"With\"Quotes\\install.wim' -or
                $ArgumentList -match '"C:\\Path""With""Quotes\\install.wim"'
            }
        }
        
        It "Should properly escape command arguments with special characters" {
            $wimPath = "C:\Path&With|Special>Characters\install.wim"
            $workspacePath = "D:\Target\Workspace"
            
            Copy-CustomWimToWorkspace -WimPath $wimPath -WorkspacePath $workspacePath -WhatIf
            
            # Verify the process is executed with properly escaped arguments
            Should -Invoke Start-Process -ParameterFilter {
                $ArgumentList -match '"C:\\Path&With|Special>Characters\\install.wim"'
            }
        }
    }
    
    Context "When validating process execution parameters" {
        It "Should validate that file paths exist before execution" {
            $wimPath = "C:\NonExistent\install.wim"
            $workspacePath = "D:\Target\Workspace"
            
            # Mock Test-Path to return false for the non-existent file
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq $wimPath }
            
            # This should throw an error because the file doesn't exist
            { Copy-CustomWimToWorkspace -WimPath $wimPath -WorkspacePath $workspacePath } | 
                Should -Throw "*WIM file not found*"
            
            # Verify the error is logged
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*WIM file not found*" -and $Level -eq "Error"
            }
        }
        
        It "Should validate that destination paths are writable" {
            $wimPath = "C:\Source\install.wim"
            $workspacePath = "D:\ReadOnly\Workspace"
            
            # Mock Test-Path to return true for both paths
            Mock Test-Path { return $true }
            
            # Mock to simulate a read-only destination
            Mock Test-WriteAccess { return $false } -ParameterFilter { $Path -eq $workspacePath }
            
            # This should throw an error because the destination is read-only
            { Copy-CustomWimToWorkspace -WimPath $wimPath -WorkspacePath $workspacePath } | 
                Should -Throw "*Cannot write to destination*"
            
            # Verify the error is logged
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Cannot write to destination*" -and $Level -eq "Error"
            }
        }
    }
    
    Context "When handling command injection attempts" {
        It "Should prevent command injection in process arguments" {
            $wimPath = "C:\Source\install.wim; whoami"
            $workspacePath = "D:\Target\Workspace"
            
            # This should handle the injection attempt properly
            Copy-CustomWimToWorkspace -WimPath $wimPath -WorkspacePath $workspacePath -WhatIf
            
            # Verify the process is executed with properly sanitized arguments
            Should -Invoke Start-Process -ParameterFilter {
                # The semicolon should be treated as part of the filename, not a command separator
                $ArgumentList -match '"C:\\Source\\install.wim; whoami"'
            }
        }
        
        It "Should prevent command injection using environment variables" {
            $wimPath = "C:\Source\install.wim"
            $workspacePath = "D:\Target\Workspace"
            $env:MALICIOUS = "malicious command"
            
            # This should handle the injection attempt properly
            Copy-CustomWimToWorkspace -WimPath $wimPath -WorkspacePath $workspacePath -WhatIf
            
            # Verify the process is executed with a clean environment
            Should -Invoke Start-Process -ParameterFilter {
                # The environment should not contain the malicious variable
                ($null -eq $env) -or (-not $env.ContainsKey("MALICIOUS"))
            }
            
            # Clean up
            Remove-Item Env:\MALICIOUS -ErrorAction SilentlyContinue
        }
    }
    
    Context "When checking for privilege escalation" {
        It "Should require administrator privileges for sensitive operations" {
            # Mock IsInRole to return false (not admin)
            Mock ([Security.Principal.WindowsPrincipal]).GetMethod('IsInRole') { return $false }
            
            $wimPath = "C:\Source\install.wim"
            $workspacePath = "D:\Target\Workspace"
            
            # This should throw an error because admin privileges are required
            { Copy-CustomWimToWorkspace -WimPath $wimPath -WorkspacePath $workspacePath } | 
                Should -Throw "*Administrator privileges required*"
            
            # Verify the error is logged
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Administrator privileges required*" -and $Level -eq "Error"
            }
        }
    }
}