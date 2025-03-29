# Start logging
$Global:Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-AzSpConnect.log"
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD"
if (!(Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path (Join-Path $LogPath $Global:Transcript) -ErrorAction Stop

try {
    # Validate required parameters
    $requiredParams = @{
        ClientId = ""  # Replace with your Client ID
        ClientSecret = ""  # Replace with your Client Secret
        TenantId = ""  # Replace with your Tenant ID
        SubscriptionId = ""  # Replace with your Subscription ID
    }

    foreach ($param in $requiredParams.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace($param.Value)) {
            throw "Required parameter '$($param.Key)' is not set"
        }
    }

    # Set execution policy securely
    Write-Host "Configuring execution policy..."
    try {
        $currentPolicy = Get-ExecutionPolicy -Scope Process -ErrorAction Stop
        if ($currentPolicy -ne 'RemoteSigned') {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction Stop
            Write-Host "Execution policy set to RemoteSigned for current process"
        }
    } catch {
        throw "Failed to configure execution policy: $_"
    }

    # Securely handle credentials
    Write-Host "Preparing service principal credentials..."
    try {
        $secureSecret = ConvertTo-SecureString $requiredParams.ClientSecret -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($requiredParams.ClientId, $secureSecret)
    } catch {
        throw "Failed to prepare credentials: $_"
    }

    # Install required Az module if not present
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        Write-Host "Installing Az.Accounts module..."
        Install-Module -Name Az.Accounts -Force -AllowClobber -Scope AllUsers
    }

    # Authenticate to Azure
    Write-Host "Authenticating to Azure..."
    try {
        # Clear any existing Azure contexts
        Disconnect-AzAccount -ErrorAction SilentlyContinue

        # Connect using service principal
        $connectionResult = Connect-AzAccount -ServicePrincipal `
            -Credential $credential `
            -Tenant $requiredParams.TenantId `
            -ErrorAction Stop

        if (-not $connectionResult) {
            throw "Connection failed - no result returned"
        }

        # Set subscription context
        $context = Set-AzContext -Subscription $requiredParams.SubscriptionId -ErrorAction Stop
        if (-not $context) {
            throw "Failed to set subscription context"
        }

        # Verify connection
        $currentContext = Get-AzContext
        if (-not $currentContext -or $currentContext.Subscription.Id -ne $requiredParams.SubscriptionId) {
            throw "Failed to verify Azure connection context"
        }

        Write-Host "Successfully connected to Azure" -ForegroundColor Green
        Write-Host "Subscription: $($currentContext.Subscription.Name)"
        Write-Host "Tenant: $($currentContext.Tenant.Id)"
        
        # Return the context for use by calling scripts
        return $currentContext

    } catch {
        throw "Azure authentication failed: $_"
    }

} catch {
    Write-Error "Script execution failed: $_"
    exit 1
} finally {
    # Clear sensitive variables
    $secureSecret = $null
    $credential = $null
    [System.GC]::Collect()
    
    Stop-Transcript
}