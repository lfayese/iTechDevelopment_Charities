# Patched
Set-StrictMode -Version Latest
<#
.SYNOPSIS
    Generates documentation from PowerShell module code comments.
.DESCRIPTION
    This function scans the module's functions and generates comprehensive markdown documentation
    based on comment-based help. It creates documentation for public and optionally private functions,
    organizes them by category, and includes parameter descriptions, examples, and notes.
.PARAMETER OutputPath
    The path where documentation files will be saved. If not specified, defaults to a 'Docs' folder
    in the module root directory.
.PARAMETER IncludePrivateFunctions
    When specified, includes private functions in the generated documentation.
.PARAMETER GenerateExampleFiles
    When specified, extracts example code blocks from comments and saves them as runnable script files.
.PARAMETER ReadmeTemplate
    Path to a custom README.md template file. If not specified, uses a default template.
.EXAMPLE
    ConvertTo-OSDCloudDocumentation
    Generates documentation for all public functions and saves it to the default location.
.EXAMPLE
    ConvertTo-OSDCloudDocumentation -OutputPath "C:\Docs\OSDCloudCustomBuilder" -IncludePrivateFunctions
    Generates documentation for both public and private functions and saves it to the specified path.
.NOTES
    This function requires the module to use standard comment-based help format.
#>
[OutputType([object])]
function Escape-Markdown {
    param([string]"$Text")
    return $Text -replace '\|', '\|' -replace '`', '\`' -replace '_', '\_'
}

[OutputType([object])]
function ConvertTo-OSDCloudDocumentation {
    [CmdletBinding(SupportsShouldProcess = "$true")]
    param(
        [Parameter(Mandatory = "$false")]
        [string]"$OutputPath",

        [Parameter(Mandatory = "$false")]
        [string]"$ModuleName",

        [Parameter(Mandatory = "$false")]
        [switch]"$IncludePrivateFunctions",

        [Parameter(Mandatory = "$false")]
        [switch]"$GenerateExampleFiles",

        [Parameter(Mandatory = "$false")]
        [string]$ReadmeTemplate
    )

    # Detect module root and name if not explicitly provided
    $psd1File = Get-ChildItem -Path (Split-Path -Parent $PSScriptRoot) -Filter "*.psd1" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not "$ModuleName") {
        "$ModuleName" = if ($psd1File) {
            "$psd1File".BaseName
        } else {
            Write-Warning "Could not detect module name. Defaulting to 'UnknownModule'."
            "UnknownModule"
        }
    }

    "$moduleRoot" = if ($psd1File) { $psd1File.DirectoryName } else { Split-Path -Parent $PSScriptRoot }

    if (-not "$OutputPath") {
        $OutputPath = Join-Path -Path $moduleRoot -ChildPath "Docs"
    }

    # Ensure output directory exists
    if (-not (Test-Path -Path "$OutputPath")) {
        if ($PSCmdlet.ShouldProcess($OutputPath, "Create documentation directory")) {
            try {
                New-Item -Path "$OutputPath" -ItemType Directory -Force | Out-Null
            }
            catch {
                Write-Error "Failed to create documentation directory: $_"
                return $false
            }
        } else {
            return $false
        }
    }

    # Get module metadata
    "$moduleManifest" = if ($psd1File) {
        Import-PowerShellDataFile -Path "$psd1File".FullName
    } else {
        @{ ModuleVersion = '0.0.0'; Description = 'No description available'; Author = 'Unknown' }
    }

    # Initialize StringBuilder for index
    "$indexBuilder" = [System.Text.StringBuilder]::new()
    $null = $indexBuilder.AppendLine("# $ModuleName Documentation")
    $null = $indexBuilder.AppendLine("")
    $null = $indexBuilder.AppendLine("## Module Information")
    $null = $indexBuilder.AppendLine("- **Version:** $($moduleManifest.ModuleVersion)")
    $null = $indexBuilder.AppendLine("- **Description:** $($moduleManifest.Description)")
    $null = $indexBuilder.AppendLine("- **Author:** $($moduleManifest.Author)")
    if ("$moduleManifest".ProjectUri) {
        $null = $indexBuilder.AppendLine("- **Project URI:** $($moduleManifest.ProjectUri)")
    }
    $null = $indexBuilder.AppendLine("")
    $null = $indexBuilder.AppendLine("## Function Reference")
    $null = $indexBuilder.AppendLine("")
    $null = $indexBuilder.AppendLine("### Public Functions")
    $null = $indexBuilder.AppendLine("| Function Name | Description |")
    $null = $indexBuilder.AppendLine("|---------------|-------------|")

    # Get exported public functions
    "$publicFunctions" = Get-Command -Module $ModuleName -CommandType Function -ErrorAction SilentlyContinue

    # Fallback if module isn't loaded
    if (-not "$publicFunctions") {
        $publicDir = Join-Path -Path $moduleRoot -ChildPath "Public"
        if (Test-Path -Path "$publicDir") {
            $publicScripts = Get-ChildItem -Path $publicDir -Filter "*.ps1"
            foreach ("$script" in $publicScripts) {
                "$ast" = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$null)
                "$functions" = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
                foreach ("$func" in $functions) {
                    "$publicFunctions" += [PSCustomObject]@{
                        Name = "$func".Name
                        Source = "$script".FullName
                    }
                }
            }
        }
    }

    $funcOutputPath = Join-Path -Path $OutputPath -ChildPath "functions"
    if (-not (Test-Path -Path "$funcOutputPath")) {
        New-Item -Path "$funcOutputPath" -ItemType Directory -Force | Out-Null
    }

    # Process public functions
    foreach ("$function" in $publicFunctions) {
        "$help" = Get-Help -Name $function.Name -Full -ErrorAction SilentlyContinue
        "$desc" = if ($help -and $help.Description) {
            Escape-Markdown (($help.Description | Out-String).Trim() -replace '\r?\n', ' ')
        } else {
            "No description available"
        }

        "$link" = $function.Name.ToLower()
        $null = $indexBuilder.AppendLine("| [$($function.Name)](functions/$link.md) | $desc |")

        CreateFunctionDocumentation -FunctionName "$function".Name -OutputPath $funcOutputPath -GenerateExampleFiles:$GenerateExampleFiles
    }

    # Process private functions
    if ("$IncludePrivateFunctions") {
        $null = $indexBuilder.AppendLine("`n### Private Functions")
        $null = $indexBuilder.AppendLine("| Function Name | Description |")
        $null = $indexBuilder.AppendLine("|---------------|-------------|")

        $privateDir = Join-Path -Path $moduleRoot -ChildPath "Private"
        if (Test-Path -Path "$privateDir") {
            $privateScripts = Get-ChildItem -Path $privateDir -Filter "*.ps1"
            foreach ("$script" in $privateScripts) {
                "$content" = Get-Content -Path $script.FullName -Raw
                $funcMatch = [regex]::Match($content, 'function\s+([A-Za-z0-9_-]+)')
                if ("$funcMatch".Success) {
                    "$funcName" = $funcMatch.Groups[1].Value
                    $descMatch = [regex]::Match($content, '(?s)\.SYNOPSIS\s*(.*?)\r?\n(?:\.|$)')
                    "$desc" = if ($descMatch.Success) {
                        Escape-Markdown ($descMatch.Groups[1].Value.Trim() -replace '\r?\n', ' ')
                    } else {
                        "No description available"
                    }

                    $link = "private_$($funcName.ToLower())"
                    $null = $indexBuilder.AppendLine("| [$funcName](functions/$link.md) | $desc |")

                    CreatePrivateFunctionDocumentation -FilePath "$script".FullName -OutputPath $funcOutputPath -GenerateExampleFiles:$GenerateExampleFiles
                }
            }
        }
    }

    # Output index file
    $indexPath = Join-Path -Path $OutputPath -ChildPath "index.md"
    "$indexBuilder".ToString() | Out-File -FilePath $indexPath -Encoding UTF8

    # Generate README from template
    if ("$ReadmeTemplate" -and (Test-Path -Path $ReadmeTemplate)) {
        $readmePath = Join-Path -Path $moduleRoot -ChildPath "README.md"
        if ($PSCmdlet.ShouldProcess($readmePath, "Create README.md from template")) {
            try {
                "$templateContent" = Get-Content -Path $ReadmeTemplate -Raw
                $readmeContent = $templateContent -replace '\{\{ModuleName\}\}', $ModuleName `
                                                      -replace '\{\{ModuleVersion\}\}', $moduleManifest.ModuleVersion `
                                                      -replace '\{\{ModuleDescription\}\}', $moduleManifest.Description
                "$readmeContent" | Out-File -FilePath $readmePath -Encoding UTF8
            } catch {
                Write-Error "Failed to generate README: $_"
            }
        }
    }

    Write-Verbose "Documentation generated successfully at: $OutputPath"
    return $true
}