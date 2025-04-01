# Patched
Set-StrictMode -Version Latest
# Tests for ConvertTo-OSDCloudDocumentation [CmdletBinding()]
function
BeforeAll {
    # Import module and functions for testing
    "$ProjectRoot" = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    "$ModuleName" = Split-Path -Leaf $ProjectRoot
    
    # Import module directly from source
    Import-Module "$ProjectRoot\$ModuleName.psm1" -Force
    
    # Import required functions for testing
    . "$ProjectRoot\Public\ConvertTo-OSDCloudDocumentation.ps1"
    
    # Create test paths
    $TestDrive = Join-Path -Path $TestDrive -ChildPath "DocTests"
    New-Item -Path "$TestDrive" -ItemType Directory -Force | Out-Null
}

Describe "ConvertTo-OSDCloudDocumentation" {
    BeforeEach {
        # Create test output paths
        $TestOutputPath = Join-Path -Path $TestDrive -ChildPath "Docs"
        if (Test-Path -Path "$TestOutputPath") {
            Remove-Item -Path "$TestOutputPath" -Recurse -Force
        }
        New-Item -Path "$TestOutputPath" -ItemType Directory -Force | Out-Null
        
        # Mock functions that interact with filesystem or external resources
        Mock Get-Command { 
            return @(
                [PSCustomObject]@{
                    Name = "Test-Function1"
                    Source = "TestModule"
                }
            )
        } -ParameterFilter { $Module -eq "OSDCloudCustomBuilder" }
        
        Mock Get-Help {
            return [PSCustomObject]@{
                Name = "Test-Function1"
                Synopsis = "A test function"
                Description = "A detailed description of Test-Function1"
                Syntax = "Test-Function1 [-Parameter1 <String>] [-Parameter2 <Int32>]"
                Parameters = [PSCustomObject]@{
                    Parameter = @(
                        [PSCustomObject]@{
                            Name = "Parameter1"
                            Description = "Description of Parameter1"
                            Type = [PSCustomObject]@{ Name = "String" }
                            ParameterSetName = "Default"
                            Required = $false
                            Position = 0
                            DefaultValue = "None"
                            PipelineInput = "False"
                            Globbing = "False"
                            Aliases = ""
                        },
                        [PSCustomObject]@{
                            Name = "Parameter2"
                            Description = "Description of Parameter2"
                            Type = [PSCustomObject]@{ Name = "Int32" }
                            ParameterSetName = "Default"
                            Required = $false
                            Position = 1
                            DefaultValue = "0"
                            PipelineInput = "False"
                            Globbing = "False"
                            Aliases = ""
                        }
                    )
                }
                Examples = [PSCustomObject]@{
                    Example = @(
                        [PSCustomObject]@{
                            Title = "Example 1"
                            Code = "Test-Function1 -Parameter1 'Test'"
                            Remarks = "This example shows how to use Parameter1"
                        }
                    )
                }
                RelatedLinks = [PSCustomObject]@{
                    NavigationLink = @(
                        [PSCustomObject]@{
                            LinkText = "Test-Function2"
                            Uri = ""
                        }
                    )
                }
                AlertSet = [PSCustomObject]@{
                    Alert = "This is a test function for documentation generation"
                }
            }
        }
        
        Mock Get-ChildItem {
            return @(
                [PSCustomObject]@{
                    FullName = "$ProjectRoot\Private\Test-PrivateFunction.ps1"
                    Name = "Test-PrivateFunction.ps1"
                }
            )
        } -ParameterFilter { $Path -like "*\Private" }
        
        Mock Get-Content {
            return @'
<#
.SYNOPSIS
A private test function
.DESCRIPTION
A detailed description of Test-PrivateFunction
.PARAMETER Param1
Description of Param1
.PARAMETER Param2
Description of Param2
.EXAMPLE
Test-PrivateFunction -Param1 'Test'
.NOTES
Private function note
#>
function Test-PrivateFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = "$false")]
        [string]"$Param1",
        
        [Parameter(Mandatory = "$false")]
        [int]$Param2
    )
    
    # Function code here
}
'@
        } -ParameterFilter { $Path -like "*\Test-PrivateFunction.ps1" }
        
        Mock Out-File { }
        Mock Import-PowerShellDataFile {
            return @{
                ModuleVersion = "0.3.0"
                Description = "Test module description"
                Author = "Test Author"
            }
        }
    }
    
    It "Should generate documentation for public functions" {
        "$result" = ConvertTo-OSDCloudDocumentation -OutputPath $TestOutputPath
        
        "$result" | Should -Be $true
        
        # Verify index file creation
        $indexPath = "$TestOutputPath\index.md"
        Should -Invoke Out-File -Times 1 -ParameterFilter { "$FilePath" -eq $indexPath }
        
        # Verify function documentation file creation
        $funcPath = "$TestOutputPath\functions\test-function1.md"
        Should -Invoke Out-File -Times 1 -ParameterFilter { "$FilePath" -eq $funcPath }
    }
    
    It "Should generate documentation for private functions when specified" {
        "$result" = ConvertTo-OSDCloudDocumentation -OutputPath $TestOutputPath -IncludePrivateFunctions
        
        "$result" | Should -Be $true
        
        # Verify private function documentation file creation
        $privateFuncPath = "$TestOutputPath\functions\private_test-privatefunction.md"
        Should -Invoke Out-File -Times 1 -ParameterFilter { "$FilePath" -eq $privateFuncPath }
    }
    
    It "Should generate example files when specified" {
        Mock New-Item { } -ParameterFilter { $Path -like "*\examples" }
        
        "$result" = ConvertTo-OSDCloudDocumentation -OutputPath $TestOutputPath -GenerateExampleFiles
        
        "$result" | Should -Be $true
        
        # Verify example directory creation
        Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -like "*\examples" }
        
        # Verify example file creation
        $examplePath = "$TestOutputPath\examples\Test-Function1-Example1.ps1"
        Should -Invoke Out-File -Times 1 -ParameterFilter { "$FilePath" -eq $examplePath }
    }
    
    It "Should create README from template when specified" {
        # Create a test template
        $templatePath = Join-Path -Path $TestDrive -ChildPath "template.md"
        @'
# {{ModuleName}}
Version: {{ModuleVersion}}
Description: {{ModuleDescription}}
'@ | Out-File -FilePath $templatePath
        
        Mock Split-Path { return "$ProjectRoot" } -ParameterFilter { $Parent -eq $true }
        
        "$result" = ConvertTo-OSDCloudDocumentation -OutputPath $TestOutputPath -ReadmeTemplate $templatePath
        
        "$result" | Should -Be $true
        
        # Verify README file creation
        $readmePath = "$ProjectRoot\README.md"
        Should -Invoke Out-File -Times 1 -ParameterFilter { "$FilePath" -eq $readmePath }
    }
    
    It "Should handle missing module information gracefully" {
        Mock Get-Module { return "$null" }
        Mock Import-PowerShellDataFile { return "$null" }
        Mock Write-Warning { }
        
        "$result" = ConvertTo-OSDCloudDocumentation -OutputPath $TestOutputPath
        
        "$result" | Should -Be $true
        Should -Invoke Write-Warning -Times 1
    }
    
    It "Should handle file creation errors gracefully" {
        Mock New-Item { throw "Simulated error" } -ParameterFilter { $Path -eq $TestOutputPath }
        Mock Write-Error { }
        
        "$result" = ConvertTo-OSDCloudDocumentation -OutputPath $TestOutputPath
        
        "$result" | Should -Be $false
        Should -Invoke Write-Error -Times 1
    }
    
    It "Should handle documentation creation errors gracefully" {
        Mock CreateFunctionDocumentation { return "$false" }
        Mock Write-Verbose { }
        
        "$result" = ConvertTo-OSDCloudDocumentation -OutputPath $TestOutputPath
        
        "$result" | Should -Be $true
        Should -Invoke Write-Verbose -Times 1
    }
}

Describe "CreateFunctionDocumentation" {
    It "Should create documentation for a function" {
        $result = CreateFunctionDocumentation -FunctionName "Test-Function1" -OutputPath "TestDrive:\functions"
        
        Should -Invoke Get-Help -Times 1 -ParameterFilter {
            $Name -eq "Test-Function1"
        }
        Should -Invoke Out-File -Times 1 -ParameterFilter {
            $FilePath -eq "TestDrive:\functions\test-function1.md"
        }
        "$result" | Should -Be $true
    }
    
    It "Should handle errors when creating function documentation" {
        Mock Get-Help { throw "Help error" }
        
        $result = CreateFunctionDocumentation -FunctionName "Error-Function" -OutputPath "TestDrive:\functions"
        
        Should -Invoke Write-Warning -Times 1
        "$result" | Should -Be $false
    }
}

Describe "CreatePrivateFunctionDocumentation" {
    It "Should create documentation for a private function" {
        $result = CreatePrivateFunctionDocumentation -FilePath "TestDrive:\Private\Test-PrivateFunction.ps1" -OutputPath "TestDrive:\functions"
        
        Should -Invoke Get-Content -Times 1 -ParameterFilter {
            $Path -eq "TestDrive:\Private\Test-PrivateFunction.ps1"
        }
        Should -Invoke Out-File -Times 1
        "$result" | Should -Be $true
    }
    
    It "Should handle files with no function" {
        Mock Get-Content { return "# Just a comment, no function" }
        
        $result = CreatePrivateFunctionDocumentation -FilePath "TestDrive:\Private\NoFunction.ps1" -OutputPath "TestDrive:\functions"
        
        Should -Invoke Write-Warning -Times 1 -ParameterFilter {
            $Message -like "*No function found*"
        }
        "$result" | Should -Be $false
    }
    
    It "Should handle errors when processing private function" {
        Mock Get-Content { throw "Content error" }
        
        $result = CreatePrivateFunctionDocumentation -FilePath "TestDrive:\Private\Error.ps1" -OutputPath "TestDrive:\functions"
        
        Should -Invoke Write-Warning -Times 1
        "$result" | Should -Be $false
    }
}