# Initialize logging buffer
$global:LogBuffer = @()
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console with appropriate color
    switch ($Level) {
        'Info'    { Write-Host $logEntry }
        'Warning' { Write-Host $logEntry -ForegroundColor Yellow }
        'Error'   { Write-Host $logEntry -ForegroundColor Red }
    }
    
    # Buffer the log entry in the global array instead of writing immediately to disk
    $global:LogBuffer += $logEntry
}
# At the end of the script, write the entire log buffer to the log file
function Write-Logs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    $global:LogBuffer | Out-File -FilePath $LogFile -Encoding UTF8
}
# Set error action
$ErrorActionPreference = 'Stop'
# Setup logging paths
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path -Path $PWD -ChildPath "Logs"
$logFile = Join-Path -Path $logPath -ChildPath "AzureDeploy-$timestamp.log"
if (-not (Test-Path -Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}
# Import required modules (imported only once)
Import-Module OSDCloudCustomBuilder
Write-Log -Message "Starting Azure VM deployment with OSDCloudCustomBuilder"
Write-Log -Message "ResourceGroup: $ResourceGroupName, Location: $Location, VM Count: $VMCount"
# 1. Check if Azure is connected
Write-Log -Message "Checking Azure connection..."
$azContext = Get-AzContext -ErrorAction SilentlyContinue
if (-not $azContext) {
    Write-Log -Message "Not connected to Azure. Connecting..." -Level Warning
    Connect-AzAccount
    $azContext = Get-AzContext
}
Write-Log -Message "Connected to Azure: $($azContext.Subscription.Name)"
# 2. Create Resource Group if it doesn't exist
Write-Log -Message "Checking if Resource Group exists: $ResourceGroupName"
$resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $resourceGroup) {
    Write-Log -Message "Resource Group not found. Creating new Resource Group..."
    $resourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
    Write-Log -Message "Resource Group created: $($resourceGroup.ResourceGroupName)"
}
else {
    Write-Log -Message "Resource Group already exists: $($resourceGroup.ResourceGroupName)"
}
# 3. Create Virtual Network and Subnet if they don't exist
Write-Log -Message "Checking if VNet exists: $VNetName"
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $vnet) {
    Write-Log -Message "VNet not found. Creating new VNet and Subnet..."
    $subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.0.0/24"
    $vnet = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $subnetConfig
    Write-Log -Message "VNet and Subnet created: $VNetName, $SubnetName"
}
else {
    Write-Log -Message "VNet already exists: $VNetName"
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName -ErrorAction SilentlyContinue
    if (-not $subnet) {
        Write-Log -Message "Subnet not found. Creating new Subnet..."
        Add-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -AddressPrefix "10.0.0.0/24" | Set-AzVirtualNetwork
        $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName
        Write-Log -Message "Subnet created: $SubnetName"
    }
    else {
        Write-Log -Message "Subnet already exists: $SubnetName"
    }
}
# 4. Create Storage Account for custom image
$storageAccountName = "osdcloud" + [System.Guid]::NewGuid().ToString().Substring(0, 8).ToLower()
Write-Log -Message "Creating Storage Account: $storageAccountName"
$storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageAccountName -Location $Location -SkuName Standard_LRS
Write-Log -Message "Storage Account created: $storageAccountName"
# 5. Build Custom OSDCloud ISO and Create Template
Write-Log -Message "Creating custom OSDCloud template..."
# Create workspace directory
$workspacePath = Join-Path -Path $env:TEMP -ChildPath "OSDCloudWorkspace-$timestamp"
New-Item -Path $workspacePath -ItemType Directory -Force | Out-Null
if ($IncludeTelemetry) {
    Write-Log -Message "Configuring telemetry for custom template..."
    Set-OSDCloudTelemetry -Enable -DetailLevel Detailed -StoragePath (Join-Path -Path $workspacePath -ChildPath "Telemetry")
}
Write-Log -Message "Building custom OSDCloud ISO with PowerShell 7..."
$isoParams = @{
    WorkspacePath        = $workspacePath
    TemplateName         = $OSDCloudTemplateName
    IncludePowerShell7   = $true
    PowerShell7Version   = $PowerShell7Version
    NoISO                = $false
}
$customISO = New-CustomOSDCloudISO @isoParams
if (-not $customISO -or -not (Test-Path -Path $customISO.ISOPath)) {
    throw "Failed to create custom OSDCloud ISO"
}
Write-Log -Message "Custom OSDCloud ISO created: $($customISO.ISOPath)"
# 6. Upload custom WIM to Azure Storage
Write-Log -Message "Uploading custom WIM file to Azure Storage..."
$wimPath = $customISO.WimPath
$containerName = "osdcloudimages"
$wimBlobName = "CustomWim-$timestamp.wim"
$ctx = $storageAccount.Context
New-AzStorageContainer -Name $containerName -Context $ctx -Permission Blob | Out-Null
$wimBlob = Set-AzStorageBlobContent -File $wimPath -Container $containerName -Blob $wimBlobName -Context $ctx -Force
Write-Log -Message "WIM file uploaded: $wimBlobName"
$sasToken = New-AzStorageBlobSASToken -Container $containerName -Blob $wimBlobName -Permission r -ExpiryTime (Get-Date).AddHours(12) -Context $ctx
$wimUrl = "$($wimBlob.ICloudBlob.Uri)$sasToken"
# 7. Create Image Definition from the Uploaded WIM
Write-Log -Message "Creating an Image Definition from the custom WIM..."
$galleryName = "OSDCloudGallery$timestamp"
New-AzGallery -ResourceGroupName $ResourceGroupName -Name $galleryName -Location $Location
$imageDefinitionName = "OSDCloud-CustomImage"
New-AzGalleryImageDefinition -ResourceGroupName $ResourceGroupName -GalleryName $galleryName -Name $imageDefinitionName -Location $Location -OsState Specialized -OsType Windows -HyperVGeneration V2
Write-Log -Message "Image Definition created: $imageDefinitionName"
$imageVersionName = "1.0.0"
$imageVersion = New-AzGalleryImageVersion -ResourceGroupName $ResourceGroupName -GalleryName $galleryName -GalleryImageDefinitionName $imageDefinitionName -Name $imageVersionName -Location $Location -SourceImageUri $wimUrl
Write-Log -Message "Image Version created: $($imageVersion.Name)"
# Retrieve credentials once for all VM deployments
Write-Log -Message "Acquiring VM administrator credentials..."
$vmCredential = Get-Credential -Message "Enter admin credentials for the VMs"
# 8. Deploy Virtual Machines using the Custom Image
Write-Log -Message "Deploying $VMCount Virtual Machines..."
for ($i = 1; $i -le $VMCount; $i++) {
    $vmName = "OSDCloud-VM-$i"
    Write-Log -Message "Creating VM: $vmName"
    
    # Create NIC
    $nicName = "$vmName-nic"
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName
    $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $subnet.Id
    
    # Create VM configuration using the stored credential
    $vmConfig = New-AzVMConfig -VMName $vmName -VMSize $VMSize
    $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential $vmCredential -ProvisionVMAgent
    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
    $vmConfig = Set-AzVMSourceImage -VM $vmConfig -Id $imageVersion.Id
    
    # Create the VM
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig
    Write-Log -Message "VM created successfully: $vmName"
}
Write-Log -Message "Azure VM deployment completed successfully!"
Write-Log -Message "Summary:"
Write-Log -Message "- Resource Group: $ResourceGroupName"
Write-Log -Message "- Location: $Location"
Write-Log -Message "- VMs Deployed: $VMCount"
Write-Log -Message "- Custom Image: $imageDefinitionName ($imageVersionName)"
Write-Log -Message "- PowerShell 7 Version: $PowerShell7Version"
Write-Log -Message "- Telemetry Enabled: $($IncludeTelemetry -eq $true)"
Write-Log -Message "- Log File: $logFile"
# Write the entire log buffer to file only once at the end
Write-Logs -LogFile $logFile
# Return deployment info
[PSCustomObject]@{
    ResourceGroupName = $ResourceGroupName
    Location          = $Location
    VMCount           = $VMCount
    VMNames           = (1..$VMCount | ForEach-Object { "OSDCloud-VM-$_" })
    ImageName         = "$imageDefinitionName ($imageVersionName)"
    TelemetryEnabled  = ($IncludeTelemetry -eq $true)
    LogFile           = $logFile
    DeploymentStatus   = "In Progress"
}