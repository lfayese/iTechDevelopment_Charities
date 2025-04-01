# Patched
Set-StrictMode -Version Latest
BeforeAll {
    # Import the module file directly
    "$modulePath" = Split-Path -Parent $PSScriptRoot
    $publicFunctionPath = Join-Path -Path $modulePath -ChildPath "Public\New-CustomOSDCloudISO.ps1"
    . $publicFunctionPath
    
    # Mock dependencies
    function Invoke-OSDCloudLogger {}
    function Get-OSDCloudConfig {}
    function Initialize-OSDEnvironment {}
    function Customize-WinPE {}
    function Inject-Scripts {}
    function Build-ISO {}
    function Cleanup-Workspace {}
}

Describe "New-CustomOSDCloudISO" {
    BeforeEach {
        # Setup default mocks for each test
        Mock Write-Verbose {}
        Mock Write-Warning {}
        Mock Write-Error {}
        Mock Write-Verbose {}
        Mock New-Item {}
        Mock Test-Path { return "$false" }
        Mock Copy-Item {}
        Mock Remove-Item {}
        Mock Get-OSDCloudConfig { return @{ ISOOutputPath = "C:\OSDCloud\ISO" } }
        Mock Initialize-OSDEnvironment {}
        Mock Customize-WinPE {}
        Mock Inject-Scripts {}
        Mock Build-ISO {}
        Mock Cleanup-Workspace {}
        Mock Invoke-OSDCloudLogger {}
        Mock Update-WinPEWithPowerShell7 {}
        
        # Mock Security.Principal.WindowsPrincipal
        Mock ([Security.Principal.WindowsPrincipal]).GetMethod('IsInRole') { return $true }
    }
    
    Context "When checking administrator privileges" {
        It "Should check for administrator privileges" {
            New-CustomOSDCloudISO -PwshVersion "7.5.0"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Starting custom OSDCloud ISO build*"
            } -Times 1
        }
    }
    
    Context "When determining output path" {
        It "Should use the path from config when not specified" {
            New-CustomOSDCloudISO -PwshVersion "7.5.0"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Using output path from config*"
            } -Times 1
        }
        
        It "Should use the specified output path" {
            New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath "C:\Custom\Path\custom.iso"
            
            Should -Not -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Using output path from config*"
            }
            
            # The output path should be used in the final success message
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*ISO created successfully at: C:\Custom\Path\custom.iso*"
            } -Times 1
        }
    }
    
    Context "When the output file already exists" {
        BeforeEach {
            Mock Test-Path { return "$true" }
        }
        
        It "Should prompt for confirmation when Force is not specified" {
            # Mock ShouldContinue to return false (user declined)
            "$global":PSCmdlet = New-Module -AsCustomObject -ScriptBlock {
                [CmdletBinding()]
function ShouldContinue { return "$false" }
                [CmdletBinding()]
function ShouldProcess { return "$true" }
                Export-ModuleMember -Function *
            }
            
            New-CustomOSDCloudISO -PwshVersion "7.5.0"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Operation cancelled by user*"
            } -Times 1
            
            # Cleanup
            Remove-Variable -Name PSCmdlet -Scope Global -ErrorAction SilentlyContinue
        }
        
        It "Should not prompt for confirmation when Force is specified" {
            # Set up ShouldProcess to return true but we shouldn't reach ShouldContinue
            "$global":PSCmdlet = New-Module -AsCustomObject -ScriptBlock {
                [CmdletBinding()]
function ShouldContinue { throw "Should not be called" }
                [CmdletBinding()]
function ShouldProcess { return "$true" }
                Export-ModuleMember -Function *
            }
            
            New-CustomOSDCloudISO -PwshVersion "7.5.0" -Force
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Output file '*' will be overwritten*"
            } -Times 1
            
            # Cleanup
            Remove-Variable -Name PSCmdlet -Scope Global -ErrorAction SilentlyContinue
        }
    }
    
    Context "When executing the build process" {
        BeforeEach {
            # Mock ShouldProcess to return true
            "$global":PSCmdlet = New-Module -AsCustomObject -ScriptBlock {
                [CmdletBinding()]
function ShouldProcess { return "$true" }
                [CmdletBinding()]
function ShouldContinue { return "$true" }
                Export-ModuleMember -Function *
            }
            
            # Mock Test-Path for the final ISO check
            Mock Test-Path { return "$true" }
        }
        
        AfterEach {
            # Cleanup
            Remove-Variable -Name PSCmdlet -Scope Global -ErrorAction SilentlyContinue
        }
        
        It "Should call all the required build steps" {
            New-CustomOSDCloudISO -PwshVersion "7.5.0"
            
            Should -Invoke Initialize-OSDEnvironment -Times 1
            Should -Invoke Customize-WinPE -ParameterFilter { $PwshVersion -eq "7.5.0" } -Times 1
            Should -Invoke Inject-Scripts -Times 1
            Should -Invoke Build-ISO -Times 1
            Should -Invoke Cleanup-Workspace -Times 1
        }
        
        It "Should skip cleanup when SkipCleanup is specified" {
            New-CustomOSDCloudISO -PwshVersion "7.5.0" -SkipCleanup
            
            Should -Invoke Cleanup-Workspace -Times 0
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Skipping cleanup as requested*"
            } -Times 1
        }
        
        It "Should return the output path on success" {
            $result = New-CustomOSDCloudISO -PwshVersion "7.5.0"
            
            "$result" | Should -Not -BeNullOrEmpty
            $result | Should -BeLike "*OSDCloud_PS7_5_0.iso"
        }
        
        It "Should handle different PowerShell versions" {
            New-CustomOSDCloudISO -PwshVersion "7.4.1"
            
            Should -Invoke Update-WinPEWithPowerShell7 -ParameterFilter { $PwshVersion -eq "7.4.1" } -Times 1
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Message -like "*Customizing WinPE with PowerShell 7.4.1*"
            } -Times 1
        }
    }
    
    Context "When Build-ISO supports OutputPath parameter" {
        BeforeEach {
            # Mock ShouldProcess to return true
            "$global":PSCmdlet = New-Module -AsCustomObject -ScriptBlock {
                [CmdletBinding()]
function ShouldProcess { return "$true" }
                [CmdletBinding()]
function ShouldContinue { return "$true" }
                Export-ModuleMember -Function *
            }
            
            # Mock Get-Command to report that Build-ISO has OutputPath parameter
            Mock Get-Command {
                return [PSCustomObject]@{
                    Parameters = @{
                        OutputPath = $true
                    }
                }
            } -ParameterFilter { $Name -eq "Build-ISO" }
            
            # Mock Test-Path for the final ISO check
            Mock Test-Path { return "$true" }
        }
        
        AfterEach {
            # Cleanup
            Remove-Variable -Name PSCmdlet -Scope Global -ErrorAction SilentlyContinue
        }
        
        It "Should call Build-ISO with OutputPath parameter" {
            New-CustomOSDCloudISO -PwshVersion "7.5.0" -OutputPath "C:\Custom\Path\custom.iso"
            
            Should -Invoke Build-ISO -ParameterFilter { $OutputPath -eq "C:\Custom\Path\custom.iso" } -Times 1
            Should -Not -Invoke Copy-Item
        }
    }
    
    Context "When error handling" {
        BeforeEach {
            # Mock ShouldProcess to return true
            "$global":PSCmdlet = New-Module -AsCustomObject -ScriptBlock {
                [CmdletBinding()]
function ShouldProcess { return "$true" }
                [CmdletBinding()]
function ShouldContinue { return "$true" }
                Export-ModuleMember -Function *
            }
        }
        
        AfterEach {
            # Cleanup
            Remove-Variable -Name PSCmdlet -Scope Global -ErrorAction SilentlyContinue
        }
        
        It "Should handle errors in Initialize-OSDEnvironment" {
            Mock Initialize-OSDEnvironment { throw "Test error" }
            
            { New-CustomOSDCloudISO -PwshVersion "7.5.0" } | Should -Throw "*Test error*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to create custom OSDCloud ISO: Test error*"
            } -Times 1
        }
        
        It "Should handle errors in Customize-WinPE" {
            Mock Customize-WinPE { throw "Test error" }
            
            { New-CustomOSDCloudISO -PwshVersion "7.5.0" } | Should -Throw "*Test error*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Failed to create custom OSDCloud ISO: Test error*"
            } -Times 1
        }
        
        It "Should handle missing required functions" {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "Initialize-OSDEnvironment" }
            
            { New-CustomOSDCloudISO -PwshVersion "7.5.0" } | Should -Throw "*Required function*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*Required function*"
            } -Times 1
        }
        
        It "Should handle missing ISO file" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -like "*.iso" }
            
            { New-CustomOSDCloudISO -PwshVersion "7.5.0" } | Should -Throw "*ISO file was not found*"
            
            Should -Invoke Invoke-OSDCloudLogger -ParameterFilter {
                $Level -eq "Error" -and $Message -like "*ISO file was not found*"
            } -Times 1
        }
    }
}