# Start logging
$Global:Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-AzKvSpConnect.log"
$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD"
if (!(Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path (Join-Path $LogPath $Global:Transcript) -ErrorAction Stop

try {
    ###############################################################################################################
    ######                                         Set Variables                                               ######
    ###############################################################################################################
    
    # Required parameters validation
    $requiredParams = @{
        tenantId = ""
        appId = ""
        vaultName = ""
        certName = ""
    }

    foreach ($param in $requiredParams.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace($param.Value)) {
            throw "Required parameter '$($param.Key)' is not set"
        }
    }

    ###############################################################################################################
    ######                                         Install Modules                                             ######
    ###############################################################################################################
    
    function Install-RequiredModule {
        param(
            [Parameter(Mandatory=$true)]
            [string]$ModuleName,
            [string]$RequiredVersion,
            [string]$Scope = "AllUsers"
        )
        
        try {
            $module = Get-Module -Name $ModuleName -ListAvailable
            if (-not $module) {
                Write-Host "Installing $ModuleName module..."
                $params = @{
                    Name = $ModuleName
                    Scope = $Scope
                    Force = $true
                    AllowClobber = $true
                    ErrorAction = "Stop"
                }
                if ($RequiredVersion) {
                    $params.Add("RequiredVersion", $RequiredVersion)
                }
                Install-Module @params
                Write-Host "$ModuleName module installed successfully" -ForegroundColor Green
            } elseif ($RequiredVersion -and -not ($module.Version -eq $RequiredVersion)) {
                Write-Host "Updating $ModuleName to version $RequiredVersion..."
                Install-Module -Name $ModuleName -RequiredVersion $RequiredVersion -Force -AllowClobber -Scope $Scope
                Write-Host "$ModuleName module updated successfully" -ForegroundColor Green
            }
        } catch {
            throw "Failed to install/update $ModuleName module: $_"
        }
    }

    # Ensure NuGet provider is available
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Host "Installing NuGet provider..."
        Install-PackageProvider -Name NuGet -ForceBootstrap -Scope AllUsers -Force
    }

    # Install required modules
    $modules = @(
        @{Name = "Microsoft.Graph.Authentication"},
        @{Name = "Az.Accounts"; RequiredVersion = "2.12.1"},
        @{Name = "Az.KeyVault"; RequiredVersion = "4.9.2"}
    )

    foreach ($module in $modules) {
        Install-RequiredModule @module
    }

    # Import modules
    Write-Host "Importing required modules..."
    $modules | ForEach-Object {
        Import-Module $_.Name -Force -ErrorAction Stop
    }

    ###############################################################################################################
    ######                                            Connect                                                  ######
    ###############################################################################################################

    # Get Azure context using service principal
    Write-Host "Connecting to Azure..."
    $azConnectScript = "X:\OSDCloud\Scripts\AzSpConnect-AzAccount.ps1"
    if (-not (Test-Path $azConnectScript)) {
        throw "Azure connection script not found at: $azConnectScript"
    }
    
    $AzureContext = & $azConnectScript
    if (-not $AzureContext) {
        throw "Failed to get Azure context"
    }

    # Set Azure context to specific subscription
    Write-Host "Setting Azure context..."
    Set-AzContext -Subscription "4dc12530-2664-4d5a-853b-c32a1c90b2da" -ErrorAction Stop

    # Get certificate from Key Vault
    Write-Host "Retrieving certificate from Key Vault..."
    $certBase64 = Get-AzKeyVaultCertificate -VaultName $vaultName -Name $certName -ErrorAction Stop
    if (-not $certBase64) {
        throw "Failed to retrieve certificate from Key Vault"
    }
    $thumbprint = $certBase64.Thumbprint

    # Connect to Microsoft Graph
    Write-Host "Connecting to Microsoft Graph..."
    $graphParams = @{
        TenantId = $tenantId
        ClientId = $appId
        CertificateThumbprint = $thumbprint
        ContextScope = "Process"
        ErrorAction = "Stop"
    }
    
    Connect-MgGraph @graphParams
    
    # Verify connection
    $context = Get-MgContext
    if (-not $context) {
        throw "Failed to establish Microsoft Graph connection"
    }
    
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
    Write-Host "Connected as: $($context.Account)"
    Write-Host "Tenant ID: $($context.TenantId)"

} catch {
    Write-Error "Script execution failed: $_"
    exit 1
} finally {
    Stop-Transcript
}