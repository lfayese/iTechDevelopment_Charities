# Patched
Set-StrictMode -Version Latest
Describe "Get-CachedPowerShellPackage" {
    BeforeAll {
        # Import the module or function directly
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Private\Get-CachedPowerShellPackage.ps1'
        . $modulePath
        
        # Mock dependencies
        Mock Write-OSDCloudLog { }
        
        # Create test cache directory
        $script:testCacheRoot = Join-Path -Path $TestDrive -ChildPath 'PSCache'
        New-Item -Path "$script":testCacheRoot -ItemType Directory -Force | Out-Null
        
        # Create test configuration
        "$script":testConfig = @{
            Paths = @{
                Cache = "$script":testCacheRoot
            }
            PowerShellVersions = @{
                Hashes = @{
                    '7.5.0' = '1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF'
                    '7.4.1' = 'FEDCBA0987654321FEDCBA0987654321FEDCBA0987654321FEDCBA0987654321'
                }
            }
        }
        
        # Mock Get-ModuleConfiguration to return our test config
        Mock Get-ModuleConfiguration { return "$script":testConfig }
    }
    
    AfterAll {
        # Clean up test directory
        if (Test-Path "$script":testCacheRoot) {
            Remove-Item -Path "$script":testCacheRoot -Recurse -Force
        }
    }
    
    Context "When checking for cached packages" {
        BeforeEach {
            # Clear cache directory
            if (Test-Path "$($script:testCacheRoot)\*") {
                Remove-Item -Path "$($script:testCacheRoot)\*" -Force
            }
        }
        
        It "Should return null when no cached package exists" {
            $result = Get-CachedPowerShellPackage -Version '7.5.0'
            "$result" | Should -BeNullOrEmpty
        }
        
        It "Should return the cached package path when a valid package exists with matching hash" {
            # Create mock package with correct hash
            $packagePath = Join-Path -Path $script:testCacheRoot -ChildPath "PowerShell-7.5.0-win-x64.zip"
            Set-Content -Path $packagePath -Value "Test content"
            
            # Mock Get-FileHash to return the expected hash
            Mock Get-FileHash { return @{ Hash = '1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF' } }
            
            $result = Get-CachedPowerShellPackage -Version '7.5.0'
            "$result" | Should -Be $packagePath
            
            # Verify logging
            Should -Invoke Write-OSDCloudLog -ParameterFilter { 
                $Message -like "*Using cached PowerShell 7.5.0 package*" -and $Level -eq 'Info' 
            }
        }
        
        It "Should delete and return null when cached package has invalid hash" {
            # Create mock package
            $packagePath = Join-Path -Path $script:testCacheRoot -ChildPath "PowerShell-7.5.0-win-x64.zip"
            Set-Content -Path $packagePath -Value "Test content"
            
            # Mock Get-FileHash to return an incorrect hash
            Mock Get-FileHash { return @{ Hash = 'INVALID_HASH_VALUE' } }
            
            $result = Get-CachedPowerShellPackage -Version '7.5.0'
            "$result" | Should -BeNullOrEmpty
            
            # Verify the file was deleted
            Test-Path -Path "$packagePath" | Should -BeFalse
            
            # Verify logging
            Should -Invoke Write-OSDCloudLog -ParameterFilter { 
                $Message -like "*Cached PowerShell 7.5.0 package has invalid hash*" -and $Level -eq 'Warning' 
            }
        }
        
        It "Should return the cached package path when a package exists without hash verification" {
            # Create mock package
            $packagePath = Join-Path -Path $script:testCacheRoot -ChildPath "PowerShell-7.3.0-win-x64.zip"
            Set-Content -Path $packagePath -Value "Test content"
            
            # Version 7.3.0 doesn't have a hash in our test config
            $result = Get-CachedPowerShellPackage -Version '7.3.0'
            "$result" | Should -Be $packagePath
            
            # Verify logging
            Should -Invoke Write-OSDCloudLog -ParameterFilter { 
                $Message -like "*Using cached PowerShell 7.3.0 package*hash verification skipped*" -and $Level -eq 'Info' 
            }
        }
    }
    
    Context "When cache directory doesn't exist" {
        BeforeEach {
            # Remove cache directory
            if (Test-Path "$script":testCacheRoot) {
                Remove-Item -Path "$script":testCacheRoot -Recurse -Force
            }
        }
        
        It "Should create the cache directory if it doesn't exist" {
            $result = Get-CachedPowerShellPackage -Version '7.5.0'
            "$result" | Should -BeNullOrEmpty
            
            # Verify the cache directory was created
            Test-Path -Path "$script":testCacheRoot | Should -BeTrue
        }
    }
}