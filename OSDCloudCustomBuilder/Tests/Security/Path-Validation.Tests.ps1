Set-StrictMode -Version Latest

BeforeAll {
    # Import the module file directly
    $modulePath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $publicFunctionPath = Join-Path -Path $modulePath -ChildPath "Public\New-CustomOSDCloudISO.ps1"
    . $publicFunctionPath
    
    # Import the functions we'll need for testing
    $helperFunctionsPath = Join-Path -Path $modulePath -ChildPath "Private\Path-Validation.ps1"
    if (Test-Path $helperFunctionsPath) {
        . $helperFunctionsPath
    }
    
    # Mock dependencies
    function Invoke-OSDCloudLogger {}
    function Get-OSDCloudConfig { return @{ ISOOutputPath = "C:\OSDCloud\ISO" } }
}

Describe "Path Validation Security Tests" {
    BeforeEach {
        # Setup default mocks for each test
        Mock Write-Verbose {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock Test-Path { return $false }
        Mock Invoke-OSDCloudLogger {}
        
        # Mock Security.Principal.WindowsPrincipal
        Mock ([Security.Principal.WindowsPrincipal]).GetMethod('IsInRole') { return $true }
    }
    
    Context "When validating paths with special characters" {
        It "Should handle paths with spaces" {
            $testPath = "C:\Path With Spaces\file.iso"
            
            # Mock the necessary functions
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $testPath }
            Mock Get-Item { return [PSCustomObject]@{ FullName = $testPath } }
            
            # Test the function
            $result = New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath $testPath -WhatIf
            
            # Verify the path is handled correctly
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*$testPath*" -and $Level -eq "Info"
            }
        }
        
        It "Should handle paths with quotes" {
            $testPath = 'C:\Path"With"Quotes\file.iso'
            
            # This should be rejected as invalid
            { New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath $testPath -WhatIf } | 
                Should -Throw "*Invalid characters in path*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Invalid characters in path*" -and $Level -eq "Error"
            }
        }
        
        It "Should handle paths with Unicode characters" {
            $testPath = "C:\Path\With\Unicode\Привет\file.iso"
            
            # Test if the function handles Unicode properly
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $testPath }
            Mock Get-Item { return [PSCustomObject]@{ FullName = $testPath } }
            
            $result = New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath $testPath -WhatIf
            
            # Verify the path is handled correctly
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*$testPath*" -and $Level -eq "Info"
            }
        }
    }
    
    Context "When checking for path traversal attacks" {
        It "Should reject paths with directory traversal attempts" {
            $testPath = "C:\OSDCloud\..\..\..\Windows\System32\file.iso"
            
            # This should be rejected as a traversal attempt
            { New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath $testPath -WhatIf } | 
                Should -Throw "*Path traversal detected*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Path traversal detected*" -and $Level -eq "Error"
            }
        }
        
        It "Should reject paths with encoded traversal characters" {
            $testPath = "C:\OSDCloud\%2e%2e\%2e%2e\Windows\file.iso"
            
            # This should be rejected as an encoded traversal attempt
            { New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath $testPath -WhatIf } | 
                Should -Throw "*Invalid characters in path*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Invalid characters in path*" -and $Level -eq "Error"
            }
        }
        
        It "Should validate that paths are normalized" {
            $testPath = "C:\OSDCloud\Folder\.\SubFolder\file.iso"
            $normalizedPath = "C:\OSDCloud\Folder\SubFolder\file.iso"
            
            # Mock the path normalization
            Mock Get-NormalizedPath { return $normalizedPath } -ParameterFilter { $Path -eq $testPath }
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $normalizedPath }
            Mock Get-Item { return [PSCustomObject]@{ FullName = $normalizedPath } }
            
            $result = New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath $testPath -WhatIf
            
            # Verify the path was normalized
            Should -Invoke Get-NormalizedPath -ParameterFilter { $Path -eq $testPath }
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*$normalizedPath*" -and $Level -eq "Info"
            }
        }
    }
    
    Context "When validating file extensions" {
        It "Should reject paths with invalid extensions" {
            $testPath = "C:\OSDCloud\malicious.exe"
            
            # This should be rejected as an invalid extension
            { New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath $testPath -WhatIf } | 
                Should -Throw "*Invalid file extension*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Invalid file extension*" -and $Level -eq "Error"
            }
        }
        
        It "Should accept paths with allowed extensions" {
            $testPath = "C:\OSDCloud\valid.iso"
            
            # Mock the necessary functions
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq $testPath }
            Mock Get-Item { return [PSCustomObject]@{ FullName = $testPath } }
            
            $result = New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath $testPath -WhatIf
            
            # Verify the path is handled correctly
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*$testPath*" -and $Level -eq "Info"
            }
        }
    }
    
    Context "When validating path length" {
        It "Should reject paths that are too long" {
            # Create a path that exceeds the maximum allowed length (260 characters)
            $longFolder = "A" * 250
            $testPath = "C:\$longFolder\file.iso"
            
            # This should be rejected as too long
            { New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath $testPath -WhatIf } | 
                Should -Throw "*Path too long*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Path too long*" -and $Level -eq "Error"
            }
        }
    }
}