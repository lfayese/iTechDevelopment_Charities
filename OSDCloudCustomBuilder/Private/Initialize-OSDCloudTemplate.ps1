<#
.SYNOPSIS
    Initializes an OSDCloud template workspace.
.DESCRIPTION
    This function initializes an OSDCloud template workspace at the specified path.
    It attempts to create the workspace using a custom template first, and falls back
    to the default template if the custom template fails.
.PARAMETER WorkspacePath
    The path where the OSDCloud workspace will be created.
.EXAMPLE
    Initialize-OSDCloudTemplate -WorkspacePath "C:\OSDCloud\Workspace"
    Creates an OSDCloud workspace at the specified path.
.NOTES
    This function requires the OSD module to be installed.
#>
function Initialize-OSDCloudTemplate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkspacePath
    )
    
    begin {
        # Log operation start
        if ($script:LoggerExists) {
            Invoke-OSDCloudLogger -Message "Initializing OSDCloud template at $WorkspacePath" -Level Info -Component "Initialize-OSDCloudTemplate"
        }
        
        # Check if OSD module is available
        if (-not (Get-Module -Name OSD -ListAvailable)) {
            $errorMessage = "OSD module is required but not installed. Please install it using 'Install-Module OSD -Force'"
            if ($script:LoggerExists) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Initialize-OSDCloudTemplate"
            }
            else {
                Write-Error $errorMessage
            }
            throw $errorMessage
        }
    }
    
    process {
        try {
            # Ensure workspace directory exists
            if (-not (Test-Path -Path $WorkspacePath)) {
                if ($PSCmdlet.ShouldProcess($WorkspacePath, "Create directory")) {
                    New-Item -Path $WorkspacePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
            }
            
            # Try to create the workspace with custom template
            if ($PSCmdlet.ShouldProcess($WorkspacePath, "Create OSDCloud workspace with custom template")) {
                Write-Host "Creating OSDCloud workspace..." -ForeColor Cyan
                
                try {
                    # Get configuration if available
                    $config = Get-OSDCloudConfig -ErrorAction SilentlyContinue
                    
                    # Try to create with custom template first
                    if ($config -and $config.CustomOSDCloudTemplate) {
                        if ($script:LoggerExists) {
                            Invoke-OSDCloudLogger -Message "Attempting to create workspace using custom template" -Level Info -Component "Initialize-OSDCloudTemplate"
                        }
                        
                        New-OSDCloudWorkspace -WorkspacePath $WorkspacePath -TemplateJSON $config.CustomOSDCloudTemplate -ErrorAction Stop
                        
                        if ($script:LoggerExists) {
                            Invoke-OSDCloudLogger -Message "Workspace created using custom template" -Level Info -Component "Initialize-OSDCloudTemplate"
                        }
                    }
                    else {
                        # No custom template specified, use default
                        if ($script:LoggerExists) {
                            Invoke-OSDCloudLogger -Message "No custom template specified, using default" -Level Info -Component "Initialize-OSDCloudTemplate"
                        }
                        
                        New-OSDCloudWorkspace -WorkspacePath $WorkspacePath -ErrorAction Stop
                        
                        if ($script:LoggerExists) {
                            Invoke-OSDCloudLogger -Message "Workspace created using default template" -Level Info -Component "Initialize-OSDCloudTemplate"
                        }
                    }
                }
                catch {
                    $warningMessage = "Failed to create workspace using custom template, trying default..."
                    if ($script:LoggerExists) {
                        Invoke-OSDCloudLogger -Message $warningMessage -Level Warning -Component "Initialize-OSDCloudTemplate" -Exception $_.Exception
                    }
                    else {
                        Write-Warning $warningMessage
                    }
                    
                    try {
                        New-OSDCloudWorkspace -WorkspacePath $WorkspacePath -ErrorAction Stop
                        
                        $successMessage = "Workspace created using default template"
                        if ($script:LoggerExists) {
                            Invoke-OSDCloudLogger -Message $successMessage -Level Info -Component "Initialize-OSDCloudTemplate"
                        }
                        else {
                            Write-Host $successMessage -ForegroundColor Green
                        }
                    }
                    catch {
                        $errorMessage = "Failed to create workspace: $_"
                        if ($script:LoggerExists) {
                            Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Initialize-OSDCloudTemplate" -Exception $_.Exception
                        }
                        else {
                            Write-Error $errorMessage
                        }
                        throw "Workspace creation failed: $_"
                    }
                }
            }
            
            $successMessage = "OSDCloud workspace created successfully"
            if ($script:LoggerExists) {
                Invoke-OSDCloudLogger -Message $successMessage -Level Info -Component "Initialize-OSDCloudTemplate"
            }
            else {
                Write-Host $successMessage -ForeColor Green
            }
            
            return $WorkspacePath
        }
        catch {
            $errorMessage = "Failed to initialize OSDCloud template: $_"
            if ($script:LoggerExists) {
                Invoke-OSDCloudLogger -Message $errorMessage -Level Error -Component "Initialize-OSDCloudTemplate" -Exception $_.Exception
            }
            else {
                Write-Error $errorMessage
            }
            throw
        }
    }
}