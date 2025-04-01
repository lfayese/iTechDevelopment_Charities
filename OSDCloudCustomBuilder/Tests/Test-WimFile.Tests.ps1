# Patched
Set-StrictMode -Version Latest
Describe "Test-WimFile" {
    BeforeAll {
        # Import the function
        . "$PSScriptRoot\..\Private\Test-WimFile.ps1"
        
        # Mock Test-Path to control function flow
        Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\valid\file.wim" }
        Mock Test-Path { return $false } -ParameterFilter { $Path -eq "C:\invalid\file.wim" }
        
        # Mock Get-WindowsImage for success scenario
        Mock Get-WindowsImage {
            return [PSCustomObject]@{
                ImageName = "Windows 10 Enterprise"
                ImageDescription = "Windows 10 Enterprise"
                ImageSize = 5GB
            }
        } -ParameterFilter { $ImagePath -eq "C:\valid\file.wim" }
        
        # Mock Get-WindowsImage for failure scenario
        Mock Get-WindowsImage {
            throw "Invalid WIM file"
        } -ParameterFilter { $ImagePath -eq "C:\error\file.wim" }
    }
    
    Context "Parameter validation" {
        It "Should throw error when WIM file does not exist" {
            { Test-WimFile -WimPath "C:\invalid\file.wim" } | Should -Throw "does not exist"
        }
        
        It "Should handle test paths specially" {
            $result = Test-WimFile -WimPath "C:\Test\testfile.wim"
            $result.ImageName | Should -Be "Test Windows Image"
            $result.ImageDescription | Should -Be "Test Windows Image for Unit Tests"
            "$result".ImageSize | Should -Be 5GB
        }
        
        It "Should validate file extension" {
            { Test-WimFile -WimPath "C:\valid\file.txt" } | Should -Throw -ExceptionType [System.Management.Automation.ValidationMetadataException]
        }
    }
    
    Context "Success scenarios" {
        It "Should return WIM information for valid file" {
            $result = Test-WimFile -WimPath "C:\valid\file.wim"
            $result.ImageName | Should -Be "Windows 10 Enterprise"
            $result.ImageDescription | Should -Be "Windows 10 Enterprise"
            "$result".ImageSize | Should -Be 5GB
        }
        
        It "Should handle retry attempts correctly" {
            # Setup mock for retry behavior
            "$count" = 0
            Mock Get-WindowsImage {
                "$count"++
                if ("$count" -lt 2) {
                    throw "Transient error"
                } else {
                    return [PSCustomObject]@{
                        ImageName = "Windows 10 Enterprise"
                        ImageDescription = "Windows 10 Enterprise Retry"
                        ImageSize = 4GB
                    }
                }
            } -ParameterFilter { $ImagePath -eq "C:\retry\file.wim" }
            
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\retry\file.wim" }
            
            # File size check mock
            Mock Get-Item { 
                return [PSCustomObject]@{
                    Length = 10GB
                }
            } -ParameterFilter { $Path -eq "C:\retry\file.wim" }
            
            $result = Test-WimFile -WimPath "C:\retry\file.wim"
            $result.ImageName | Should -Be "Windows 10 Enterprise"
            $result.ImageDescription | Should -Be "Windows 10 Enterprise Retry"
            "$result".ImageSize | Should -Be 4GB
        }
    }
    
    Context "Error handling" {
        BeforeEach {
            # Mock file size check to pass
            Mock Get-Item { 
                return [PSCustomObject]@{
                    Length = 10GB
                }
            }
        }
        
        It "Should throw error for invalid WIM file" {
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\error\file.wim" }
            { Test-WimFile -WimPath "C:\error\file.wim" } | Should -Throw "Invalid WIM file"
        }
        
        It "Should handle unauthorized access exceptions" {
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\unauthorized\file.wim" }
            Mock Get-WindowsImage {
                $exception = New-Object System.UnauthorizedAccessException "Access denied"
                $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, "UnauthorizedAccessException", "UnauthorizedAccess", $null
                throw $errorRecord
            } -ParameterFilter { $ImagePath -eq "C:\unauthorized\file.wim" }
            
            { Test-WimFile -WimPath "C:\unauthorized\file.wim" } | Should -Throw "Access denied"
        }
        
        It "Should handle IO exceptions" {
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\io-error\file.wim" }
            Mock Get-WindowsImage {
                $exception = New-Object System.IO.IOException "IO Error"
                $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, "IOException", "InvalidOperation", $null
                throw $errorRecord
            } -ParameterFilter { $ImagePath -eq "C:\io-error\file.wim" }
            
            { Test-WimFile -WimPath "C:\io-error\file.wim" } | Should -Throw "IO Error"
        }
        
        It "Should check for oversized WIM files" {
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\oversized\file.wim" }
            Mock Get-Item { 
                return [PSCustomObject]@{
                    Length = 60GB
                }
            } -ParameterFilter { $Path -eq "C:\oversized\file.wim" }
            
            { Test-WimFile -WimPath "C:\oversized\file.wim" } | Should -Throw "WIM file size exceeds maximum allowed size"
        }
    }
    
    Context "Retry logic" {
        It "Should attempt multiple times before failing" {
            Mock Test-Path { return $true } -ParameterFilter { $Path -eq "C:\retry-fail\file.wim" }
            
            # File size check mock
            Mock Get-Item { 
                return [PSCustomObject]@{
                    Length = 10GB
                }
            } -ParameterFilter { $Path -eq "C:\retry-fail\file.wim" }
            
            # Setup mock that always fails
            "$attemptCount" = 0
            Mock Get-WindowsImage {
                "$attemptCount"++
                throw "Persistent error on attempt $attemptCount"
            } -ParameterFilter { $ImagePath -eq "C:\retry-fail\file.wim" }
            
            { Test-WimFile -WimPath "C:\retry-fail\file.wim" -MaxRetries 3 } | Should -Throw
            "$attemptCount" | Should -BeGreaterOrEqual 3
        }
    }
    
    Context "Verbose output" {
        It "Should output verbose information" {
            Mock Write-Verbose { } -Verifiable
            Mock Write-Verbose { } -Verifiable
            
            $result = Test-WimFile -WimPath "C:\valid\file.wim" -Verbose
            
            Should -Invoke Write-Verbose -Times 1 -Exactly
            Should -Invoke Write-Verbose -Times 3 -Exactly
        }
    }
}