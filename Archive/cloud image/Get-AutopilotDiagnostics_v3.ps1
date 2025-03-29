<#PSScriptInfo
.VERSION 5.13
.GUID b45605b6-65aa-45ec-a23c-f5291f9fb519
.AUTHOR AndrewTaylor, Michael Niehaus & Steven van Beek (Modified by ChatGPT)
.COMPANYNAME
.COPYRIGHT GPL
.TAGS
.LICENSEURI https://github.com/andrew-s-taylor/public/blob/main/LICENSE
.PROJECTURI https://github.com/andrew-s-taylor/public
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.RELEASENOTES
Version 5.13: Revised to fix errors, add export logic and zip results to desktop.
.EXAMPLE
.\Get-AutopilotDiagnostics_v2.ps1
#>
<#
.DESCRIPTION
Displays diagnostics information from the current PC or a captured set of logs.
It includes details on Autopilot profile settings, policies, apps, certificate profiles, etc.
Works with Windows 10 1903+ (ARM64 not supported).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $CABFile = $null,
    [Parameter(Mandatory = $false)]
    [string] $ZIPFile = $null,
    [Parameter(Mandatory = $false)]
    [switch] $Online = $false,
    [Parameter(Mandatory = $false)]
    [switch] $AllSessions = $false,
    [Parameter(Mandatory = $false)]
    [switch] $ShowPolicies = $false,
    [Parameter(Mandatory = $false)]
    [string] $Tenant,
    [Parameter(Mandatory = $false)]
    [string] $AppId,
    [Parameter(Mandatory = $false)]
    [string] $AppSecret,
    [Parameter(Mandatory = $false)]
    [string] $bearer
)

Begin {
    # Initialize global variables
    $script:observedTimeline = @()

    # Define lookup hashtables used later
    $script:officeStatus = @{
        "0" = "None"; "10" = "Initialized"; "20" = "Download In Progress"; "25" = "Pending Download Retry";
        "30" = "Download Failed"; "40" = "Download Completed"; "48" = "Pending User Session"; "50" = "Enforcement In Progress";
        "55" = "Pending Enforcement Retry"; "60" = "Enforcement Failed"; "70" = "Success / Enforcement Completed"
    }
    $script:espStatus = @{
        "1" = "Not Installed"; "2" = "Downloading / Installing"; "3" = "Success / Installed"; "4" = "Error / Failed"
    }
    $script:policyStatus = @{ "0" = "Not Processed"; "1" = "Processed" }
    if ($CABFile -or $ZIPFile) {
        $script:useFile = $true
        $tempPath = Join-Path $env:TEMP "ESPStatus.tmp"
        if (-not (Test-Path $tempPath)) {
            New-Item -Path $tempPath -ItemType "directory" | Out-Null
        }
        # Remove previous content
        Remove-Item -Path (Join-Path $tempPath "*") -Force -Recurse
        if ($CABFile) {
            $fileList = @(
                "MdmDiagReport_RegistryDump.reg",
                "microsoft-windows-devicemanagement-enterprise-diagnostics-provider-admin.evtx",
                "microsoft-windows-user device registration-admin.evtx",
                "AutopilotDDSZTDFile.json",
                "*.csv"
            )
            foreach ($file in $fileList) {
                & expand.exe $CABFile -F:$file $tempPath | Out-Null
                $extractedFile = Join-Path $tempPath $file
                if (-not (Test-Path $extractedFile)) {
                    Write-Error "Unable to extract $file from $CABFile"
                }
            }
        }
        else {
            Expand-Archive -Path $ZIPFile -DestinationPath $tempPath -Force
        }
        $csvFile = Get-ChildItem -Path $tempPath -Filter "*.csv" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($csvFile) {
            $csv = Get-Content $csvFile.FullName | ConvertFrom-Csv
            $hash = $csv.'Hardware Hash'
        }
        $regFilePath = Join-Path $tempPath "MdmDiagReport_RegistryDump.reg"
        if (Test-Path $regFilePath) {
            $content = Get-Content -Path $regFilePath
            $content = $content -replace "\[HKEY_CURRENT_USER\\", "[HKEY_CURRENT_USER\ESPStatus.tmp\USER\"
            $content = $content -replace "\[HKEY_LOCAL_MACHINE\\", "[HKEY_CURRENT_USER\ESPStatus.tmp\MACHINE\"
            $content = $content -replace '^ "', '"' -replace '^ @', '@' -replace 'DWORD:', 'dword:'
            $editedContent = "Windows Registry Editor Version 5.00`n" + ($content -join "`n")
            $editedRegPath = Join-Path $tempPath "MdmDiagReport_Edited.reg"
            $editedContent | Set-Content -Path $editedRegPath
            if (Test-Path "HKCU:\ESPStatus.tmp") {
                Remove-Item -Path "HKCU:\ESPStatus.tmp" -Recurse -Force
            }
            & reg.exe IMPORT $editedRegPath 2>&1 | Out-Null
        }
        # Set file-based registry paths
        $script:provisioningPath = "HKCU:\ESPStatus.tmp\MACHINE\software\microsoft\provisioning"
        $script:autopilotDiagPath = "HKCU:\ESPStatus.tmp\MACHINE\software\microsoft\provisioning\Diagnostics\Autopilot"
        $script:omadmPath = "HKCU:\ESPStatus.tmp\MACHINE\software\microsoft\provisioning\OMADM"
        $script:path = "HKCU:\ESPStatus.tmp\MACHINE\Software\Microsoft\Windows\Autopilot\EnrollmentStatusTracking\ESPTrackingInfo\Diagnostics"
        $script:msiPath = "HKCU:\ESPStatus.tmp\MACHINE\Software\Microsoft\EnterpriseDesktopAppManagement"
        $script:officePath = "HKCU:\ESPStatus.tmp\MACHINE\Software\Microsoft\OfficeCSP"
        $script:sidecarPath = "HKCU:\ESPStatus.tmp\MACHINE\Software\Microsoft\IntuneManagementExtension\Win32Apps"
        $script:enrollmentsPath = "HKCU:\ESPStatus.tmp\MACHINE\software\microsoft\enrollments"
    }
    else {
        $script:useFile = $false
        $script:provisioningPath = "HKLM:\software\microsoft\provisioning"
        $script:autopilotDiagPath = "HKLM:\software\microsoft\provisioning\Diagnostics\Autopilot"
        $script:omadmPath = "HKLM:\software\microsoft\provisioning\OMADM"
        $script:path = "HKLM:\Software\Microsoft\Windows\Autopilot\EnrollmentStatusTracking\ESPTrackingInfo\Diagnostics"
        $script:msiPath = "HKLM:\Software\Microsoft\EnterpriseDesktopAppManagement"
        $script:officePath = "HKLM:\Software\Microsoft\OfficeCSP"
        $script:sidecarPath = "HKLM:\Software\Microsoft\IntuneManagementExtension\Win32Apps"
        $script:enrollmentsPath = "HKLM:\Software\Microsoft\enrollments"
        $hash = (Get-CimInstance -Namespace root/cimv2/mdm/dmmap -ClassName MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData
    }
}
Process {
    #######################
    # FUNCTIONS
    #######################
    function Get-AllPagination {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string] $url
        )
        $response = Invoke-MgGraphRequest -Uri $url -Method Get -OutputType PSObject
        $allOutput = $response.value
        $nextLink = $response."@odata.nextLink"
        while ($nextLink) {
            $nextResponse = Invoke-MgGraphRequest -Uri $nextLink -Method Get -OutputType PSObject
            $allOutput += $nextResponse.value
            $nextLink = $nextResponse."@odata.nextLink"
        }
        return $allOutput
    }
    function Connect-ToGraph {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $false)]
            [string] $Tenant,
            [Parameter(Mandatory = $false)]
            [string] $AppId,
            [Parameter(Mandatory = $false)]
            [string] $AppSecret,
            [Parameter(Mandatory = $false)]
            [string] $scopes,
            [Parameter(Mandatory = $false)]
            [string] $bearer
        )
        try {
            Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to import Microsoft.Graph.Authentication module. Please ensure it is installed."
            exit 1
        }
        $version = (Get-Module Microsoft.Graph.Authentication).Version.Major
        if ($AppId) {
            $body = @{
                grant_type    = "client_credentials";
                client_id     = $AppId;
                client_secret = $AppSecret;
                scope         = "https://graph.microsoft.com/.default";
            }
            $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $body
            $accessToken = $response.access_token
            if ($version -eq 2) {
                Write-Host "Version 2 module detected"
                $accesstokenfinal = ConvertTo-SecureString -String $accessToken -AsPlainText -Force
            }
            else {
                Write-Host "Version 1 Module Detected"
                Select-MgProfile -Name Beta
                $accesstokenfinal = $accessToken
            }
            $graph = Connect-MgGraph -AccessToken $accesstokenfinal
            Write-Host "Connected to Intune tenant $Tenant using app-based authentication"
        }
        elseif ($bearer) {
            if ($version -eq 2) {
                Write-Host "Version 2 module detected"
                $accesstokenfinal = ConvertTo-SecureString -String $bearer -AsPlainText -Force
            }
            else {
                Write-Host "Version 1 Module Detected"
                Select-MgProfile -Name Beta
                $accesstokenfinal = $bearer
            }
            $graph = Connect-MgGraph -AccessToken $accesstokenfinal
            Write-Host "Connected to Intune tenant using provided bearer token"
        }
        else {
            if ($version -eq 2) {
                Write-Host "Version 2 module detected"
            }
            else {
                Write-Host "Version 1 Module Detected"
                Select-MgProfile -Name Beta
            }
            $graph = Connect-MgGraph -scopes $scopes
            Write-Host "Connected to Intune tenant $($graph.TenantId)"
        }
        return $graph
    }
    function RecordStatus {
        param(
            [Parameter(Mandatory = $true)] [string] $detail,
            [Parameter(Mandatory = $true)] [string] $status,
            [Parameter(Mandatory = $true)] [string] $color,
            [Parameter(Mandatory = $true)] [datetime] $date
        )
        $found = $script:observedTimeline | Where-Object { $_.Detail -eq $detail -and $_.Status -eq $status }
        if (-not $found) {
            $adjustedDate = if ($status -like "Downloading*") { $date.AddSeconds(1) } else { $date }
            $script:observedTimeline += [PSCustomObject]@{
                Date   = $adjustedDate
                Detail = $detail
                Status = $status
                Color  = $color
            }
        }
    }
    function Add-Display {
        param(
            [Parameter(Mandatory = $true)]
            [ref] $items
        )
        foreach ($item in $items.Value) {
            $item | Add-Member -NotePropertyName display -NotePropertyValue $false -Force
        }
        if ($items.Value.Count -gt 0) {
            $items.Value[$items.Value.Count - 1].display = $true
        }
    }
    function ProcessApps {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [Microsoft.Win32.RegistryKey] $currentKey,
            [Parameter(Mandatory = $true)] $currentUser,
            [Parameter(Mandatory = $true)] [bool] $display
        )
        if ($display) { Write-Host "Apps:" }
        foreach ($prop in $currentKey.Property) {
            if ($display) { Write-Host " $(([datetime]$currentKey.PSChildName).ToString('u'))" }
            if ($prop.StartsWith("./Device/Vendor/MSFT/EnterpriseDesktopAppManagement/MSI/")) {
                $msiKey = [URI]::UnescapeDataString(($prop.Split("/"))[6])
                $fullPath = Join-Path $script:msiPath "$currentUser\MSI\$msiKey"
                $status = (Test-Path $fullPath) ? (Get-ItemProperty -Path $fullPath).Status : 0
                $msiFile = $null
                if (Test-Path $fullPath) {
                    $msiFile = (Get-ItemProperty -Path $fullPath).CurrentDownloadUrl
                }
                if (-not $status) { $status = 0 }
                if ($msiFile -match "IntuneWindowsAgent.msi") {
                    $msiKey = "Intune Management Extensions ($msiKey)"
                }
                elseif ($Online) {
                    $found = $apps | Where-Object { $_.ProductCode -contains $msiKey }
                    if ($found) { $msiKey = "$($found.DisplayName) ($msiKey)" }
                }
                elseif ($currentUser -eq "S-0-0-00-0000000000-0000000000-000000000-000") {
                    $uninstallKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$msiKey"
                    if (Test-Path $uninstallKey) {
                        $displayName = (Get-ItemProperty -Path $uninstallKey).DisplayName
                        $msiKey = "$displayName ($msiKey)"
                    }
                }
                $officeText = ($script:officeStatus.ContainsKey($status.ToString())) ? $script:officeStatus[$status.ToString()] : $status
                if ($status -eq 70) {
                    if ($display) { Write-Host " MSI $msiKey : $status ($officeText)" -ForegroundColor Green }
                    RecordStatus -detail "MSI $msiKey" -status $officeText -color "Green" -date ([datetime]$currentKey.PSChildName)
                }
                elseif ($status -eq 60) {
                    if ($display) { Write-Host " MSI $msiKey : $status ($officeText)" -ForegroundColor Red }
                    RecordStatus -detail "MSI $msiKey" -status $officeText -color "Red" -date ([datetime]$currentKey.PSChildName)
                }
                else {
                    if ($display) { Write-Host " MSI $msiKey : $status ($officeText)" -ForegroundColor Yellow }
                    RecordStatus -detail "MSI $msiKey" -status $officeText -color "Yellow" -date ([datetime]$currentKey.PSChildName)
                }
            }
            elseif ($prop.StartsWith("./Vendor/MSFT/Office/Installation/")) {
                $status = Get-ItemPropertyValue -Path $currentKey.PSPath -Name $prop
                $officeKey = [URI]::UnescapeDataString(($prop.Split("/"))[5])
                $fullPath = Join-Path $script:officePath $officeKey
                if (Test-Path $fullPath) {
                    $oProps = Get-ItemProperty -Path $fullPath
                    $oStatus = $oProps.FinalStatus
                    if (-not $oStatus) {
                        $oStatus = $oProps.Status
                        if (-not $oStatus) { $oStatus = "None" }
                    }
                }
                else { $oStatus = "None" }
                $officeStatusText = ($script:officeStatus.ContainsKey($oStatus.ToString())) ? $script:officeStatus[$oStatus.ToString()] : $oStatus
                if ($status -eq 1) {
                    if ($display) { Write-Host " Office $officeKey : $status ($($script:policyStatus[$status.ToString()]) / $officeStatusText)" -ForegroundColor Green }
                    RecordStatus -detail "Office $officeKey" -status ( ($script:policyStatus.ContainsKey($status.ToString())) ? $script:policyStatus[$status.ToString()] : "$status / $officeStatusText") -color "Green" -date ([datetime]$currentKey.PSChildName)
                }
                else {
                    if ($display) { Write-Host " Office $officeKey : $status ($($script:policyStatus[$status.ToString()]) / $officeStatusText)" -ForegroundColor Yellow }
                    RecordStatus -detail "Office $officeKey" -status ( ($script:policyStatus.ContainsKey($status.ToString())) ? $script:policyStatus[$status.ToString()] : "$status / $officeStatusText") -color "Yellow" -date ([datetime]$currentKey.PSChildName)
                }
            }
            else {
                if ($display) { Write-Host " $prop : Unknown app" }
            }
        }
    }
    function ProcessModernApps {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [Microsoft.Win32.RegistryKey] $currentKey,
            [Parameter(Mandatory = $true)] $currentUser,
            [Parameter(Mandatory = $true)] [bool] $display
        )
        if ($display) { Write-Host "Modern Apps:" }
        foreach ($prop in $currentKey.Property) {
            if ($display) { Write-Host " $(([datetime]$currentKey.PSChildName).ToString('u'))" }
            $status = (Get-ItemPropertyValue -Path $currentKey.PSPath -Name $prop).ToString()
            if ($prop.StartsWith("./User/Vendor/MSFT/EnterpriseModernAppManagement/AppManagement/")) {
                $appID = [URI]::UnescapeDataString(($prop.Split("/"))[7])
                $type = "User UWP"
            }
            elseif ($prop.StartsWith("./Device/Vendor/MSFT/EnterpriseModernAppManagement/AppManagement/")) {
                $appID = [URI]::UnescapeDataString(($prop.Split("/"))[7])
                $type = "Device UWP"
            }
            else {
                $appID = $prop
                $type = "Unknown UWP"
            }
            if ($status -eq "1") {
                if ($display) { Write-Host " $type $appID : $status ($($script:policyStatus[$status]))" -ForegroundColor Green }
                RecordStatus -detail "UWP $appID" -status ( ($script:policyStatus.ContainsKey($status)) ? $script:policyStatus[$status] : $status ) -color "Green" -date ([datetime]$currentKey.PSChildName)
            }
            else {
                if ($display) { Write-Host " $type $appID : $status ($($script:policyStatus[$status]))" -ForegroundColor Yellow }
            }
        }
    }
    function ProcessSidecar {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [Microsoft.Win32.RegistryKey] $currentKey,
            [Parameter(Mandatory = $true)] $currentUser,
            [Parameter(Mandatory = $true)] [bool] $display
        )
        if ($display) { Write-Host "Sidecar apps:" }
        if (-not $script:DOEvents -and (-not $script:useFile)) {
            $script:DOEvents = Get-DeliveryOptimizationLog | Where-Object {
                $_.Function -match "(DownloadStart)|(DownloadCompleted)" -and $_.Message -like "*.intunewin*"
            }
        }
        foreach ($prop in $currentKey.Property) {
            if ($display) { Write-Host " $(([datetime]$currentKey.PSChildName).ToString('u'))" }
            $win32Key = [URI]::UnescapeDataString(($prop.Split("/"))[9])
            $status = Get-ItemPropertyValue -Path $currentKey.PSPath -Name $prop
            if ($Online) {
                $found = $apps | Where-Object { $win32Key -match $_.Id }
                if ($found) { $win32Key = "$($found.DisplayName) ($win32Key)" }
            }
            $appGuid = $win32Key.Substring(9)
            $sidecarApp = Join-Path $script:sidecarPath "$currentUser\$appGuid"
            $exitCode = $null
            if (Test-Path $sidecarApp) {
                $exitCode = (Get-ItemProperty -Path $sidecarApp).ExitCode
            }
            if ($status -eq "3") {
                if ($display) {
                    $msg = ($exitCode) ? "$status ($($script:espStatus[$status]), rc = $exitCode)" : "$status ($($script:espStatus[$status]))"
                    Write-Host " Win32 $win32Key : $msg" -ForegroundColor Green
                }
                RecordStatus -detail "Win32 $win32Key" -status ($script:espStatus.ContainsKey($status.ToString()) ? $script:espStatus[$status.ToString()] : $status) -color "Green" -date ([datetime]$currentKey.PSChildName)
            }
            elseif ($status -eq "4") {
                if ($display) {
                    $msg = ($exitCode) ? "$status ($($script:espStatus[$status]), rc = $exitCode)" : "$status ($($script:espStatus[$status]))"
                    Write-Host " Win32 $win32Key : $msg" -ForegroundColor Red
                }
                RecordStatus -detail "Win32 $win32Key" -status ($script:espStatus.ContainsKey($status.ToString()) ? $script:espStatus[$status.ToString()] : $status) -color "Red" -date ([datetime]$currentKey.PSChildName)
            }
            else {
                if ($display) {
                    $msg = ($exitCode) ? "$status ($($script:espStatus[$status]), rc = $exitCode)" : "$status ($($script:espStatus[$status]))"
                    Write-Host " Win32 $win32Key : $msg" -ForegroundColor Yellow
                }
                if ($status -ne "1") {
                    RecordStatus -detail "Win32 $win32Key" -status ($script:espStatus.ContainsKey($status.ToString()) ? $script:espStatus[$status.ToString()] : $status) -color "Yellow" -date ([datetime]$currentKey.PSChildName)
                }
                if ($status -eq "2") {
                    foreach ($doEvent in $script:DOEvents | Where-Object { $_.Message -ilike "*$appGuid*" }) {
                        RecordStatus -detail "Win32 $win32Key" -status "DO $($doEvent.Function.Substring(32))" -color "Yellow" -date ($doEvent.TimeCreated.ToLocalTime())
                    }
                }
            }
        }
    }
    function ProcessPolicies {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [Microsoft.Win32.RegistryKey] $currentKey,
            [Parameter(Mandatory = $true)] [bool] $display
        )
        if ($display) { Write-Host "Policies:" }
        foreach ($prop in $currentKey.Property) {
            if ($display) { Write-Host " $(([datetime]$currentKey.PSChildName).ToString('u'))" }
            $status = Get-ItemPropertyValue -Path $currentKey.PSPath -Name $prop
            if (-not $status) { $status = "0" }
            $polText = ($script:policyStatus.ContainsKey($status.ToString())) ? $script:policyStatus[$status.ToString()] : $status
            if ($status -eq "1") {
                if ($display) { Write-Host " Policy $prop : $status ($polText)" -ForegroundColor Green }
                RecordStatus -detail "Policy $prop" -status $polText -color "Green" -date ([datetime]$currentKey.PSChildName)
            }
            else {
                if ($display) { Write-Host " Policy $prop : $status ($polText)" -ForegroundColor Yellow }
            }
        }
    }
    function ProcessCerts {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [Microsoft.Win32.RegistryKey] $currentKey,
            [Parameter(Mandatory = $true)] [bool] $display
        )
        if ($display) { Write-Host "Certificates:" }
        foreach ($prop in $currentKey.Property) {
            if ($display) { Write-Host " $(([datetime]$currentKey.PSChildName).ToString('u'))" }
            $certKey = [URI]::UnescapeDataString(($prop.Split("/"))[6])
            $status = Get-ItemPropertyValue -Path $currentKey.PSPath -Name $prop
            if ($Online) {
                $found = $policies | Where-Object { $certKey.Replace("_", "-") -match $_.Id }
                if ($found) { $certKey = "$($found.DisplayName) ($certKey)" }
            }
            $polText = ($script:policyStatus.ContainsKey($status.ToString())) ? $script:policyStatus[$status.ToString()] : $status
            if ($status -eq "1") {
                if ($display) { Write-Host " Cert $certKey : $status ($polText)" -ForegroundColor Green }
                RecordStatus -detail "Cert $certKey" -status $polText -color "Green" -date ([datetime]$currentKey.PSChildName)
            }
            else {
                if ($display) { Write-Host " Cert $certKey : $status ($polText)" -ForegroundColor Yellow }
            }
        }
    }
    function ProcessNodeCache {
        Process {
            $nodeCount = 0
            while ($true) {
                $nodePath = "$($script:provisioningPath)\NodeCache\CSP\Device\MS DM Server\Nodes\$nodeCount"
                $node = Get-ItemProperty -Path $nodePath -ErrorAction SilentlyContinue
                if (-not $node) { break }
                $nodeCount++
                $node | Select-Object NodeUri, ExpectedValue
            }
        }
    }
    function TrimMSI {
        param (
            [object] $eventObj,
            [string] $sidecarProductCode
        )
        if ($eventObj.Properties[0].Value -eq $sidecarProductCode) {
            return "Intune Management Extension"
        }
        elseif ($eventObj.Properties[0].Value.StartsWith("{{")) {
            $r = $eventObj.Properties[0].Value.Substring(1, $eventObj.Properties[0].Value.Length - 2)
        }
        else {
            $r = $eventObj.Properties[0].Value
        }
        $uninstallKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$r"
        if (Test-Path $uninstallKey) {
            $displayName = (Get-ItemProperty -Path $uninstallKey).DisplayName
            return "$displayName ($r)"
        }
        else {
            return $r
        }
    }
    function ProcessEvents {
        Process {
            $productCode = 'IME-Not-Yet-Installed'
            $msiDir = Join-Path $script:msiPath "S-0-0-00-0000000000-0000000000-000000000-000\MSI"
            if (Test-Path $msiDir) {
                foreach ($child in Get-ChildItem -Path $msiDir) {
                    $mProps = Get-ItemProperty -Path $child.PSPath
                    if ($mProps.CurrentDownloadUrl -match "IntuneWindowsAgent.msi") {
                        $productCode = Get-ItemPropertyValue -Path $child.PSPath -Name ProductCode
                    }
                }
            }
            if ($script:useFile) {
                $evtPath = Join-Path $tempPath "microsoft-windows-devicemanagement-enterprise-diagnostics-provider-admin.evtx"
                $filterHash = @{ Path = $evtPath }
            }
            else {
                $filterHash = @{ LogName = "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin" }
            }
            $deviceEventIDs = @(1905, 1906, 1920, 1922, 72, 100, 107, 109, 110, 111)
            try {
                $events = Get-WinEvent -FilterHashtable $filterHash -Oldest | Where-Object { $deviceEventIDs -contains $_.Id }
            }
            catch {
                Write-Error "Error fetching device events: $_"
                $events = @()
            }
            foreach ($event in $events) {
                $message = $event.Message
                $detail = "Sidecar"
                $color = "Yellow"
                switch ($event.Id) {
                    { $_ -in @(110, 109) } {
                        $detail = "Offline Domain Join"
                        switch ($event.Properties[0].Value) {
                            0 { $message = "Offline domain join not configured" }
                            1 { $message = "Waiting for ODJ blob" }
                            2 { $message = "Processed ODJ blob" }
                            3 { $message = "Timed out waiting for ODJ blob or connectivity" }
                        }
                    }
                    111 { $detail = "Offline Domain Join"; $message = "Starting wait for ODJ blob" }
                    107 { $detail = "Offline Domain Join"; $message = "Successfully applied ODJ blob" }
                    100 { $detail = "Offline Domain Join"; $message = "Could not establish connectivity"; $color = "Red" }
                    72  { $detail = "MDM Enrollment" }
                    1905 { $detail = (TrimMSI $event $productCode); $message = "Download started" }
                    1906 { $detail = (TrimMSI $event $productCode); $message = "Download finished" }
                    1920 { $detail = (TrimMSI $event $productCode); $message = "Installation started" }
                    1922 { $detail = (TrimMSI $event $productCode); $message = "Installation finished" }
                }
                RecordStatus -detail $detail -date $event.TimeCreated -status $message -color $color
            }
            if ($script:useFile) {
                $regEvtPath = Join-Path $tempPath "microsoft-windows-user device registration-admin.evtx"
                $regFilter = @{ Path = $regEvtPath }
            }
            else {
                try {
                    $regFilter = @{ LogName = "Microsoft-Windows-User Device Registration/Admin" }
                }
                catch {
                    $regFilter = @{}
                }
            }
            $registrationIDs = @(306, 101)
            try {
                $regEvents = Get-WinEvent -FilterHashtable $regFilter -Oldest | Where-Object { $registrationIDs -contains $_.Id }
            }
            catch {
                $regEvents = @()
            }
            foreach ($event in $regEvents) {
                $message = $event.Message
                $detail = "Device Registration"
                $color = "Yellow"
                switch ($event.Id) {
                    101 { $detail = "Device Registration"; $message = "SCP discovery successful." }
                    304 { $detail = "Device Registration"; $message = "Hybrid AADJ device registration failed." }
                    306 { $detail = "Device Registration"; $message = "Hybrid AADJ device registration succeeded."; $color = "Green" }
                }
                RecordStatus -detail $detail -date $event.TimeCreated -status $message -color $color
            }
        }
    }
    #######################
    # MAIN CODE
    #######################
    if ($Online) {
        Write-Host "Connecting to Graph..."
        if ($AppId -and $AppSecret -and $Tenant) {
            $graph = Connect-ToGraph -Tenant $Tenant -AppId $AppId -AppSecret $AppSecret
            Write-Output "Graph Connection Established"
        }
        elseif ($bearer) {
            $graph = Connect-ToGraph -bearer $bearer
            Write-Output "Graph Connection Established"
        }
        else {
            $graph = Connect-ToGraph -Scopes "DeviceManagementApps.Read.All, DeviceManagementConfiguration.Read.All"
        }
        Write-Host "Connected to tenant $($graph.TenantId)"
        Write-Host "Getting list of apps..."
        $appsuri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"
        $script:apps = Get-AllPagination -url $appsuri
        Write-Host "Getting list of policies..."
        $configuri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
        $script:policies = Get-AllPagination -url $configuri
    }
    Write-Host ""
    Write-Host "AUTOPILOT DIAGNOSTICS" -ForegroundColor Magenta
    Write-Host ""
    $values = Get-ItemProperty $script:autopilotDiagPath
    if (-not $values.CloudAssignedTenantId) {
        Write-Host "This is not an Autopilot device.`n"
        exit 0
    }
    if (-not $script:useFile) {
        $osVersion = (Get-CimInstance -ClassName Win32_OperatingSystem).Version
        Write-Host "OS version: $osVersion"
    }
    Write-Host "Profile: $($values.DeploymentProfileName)"
    Write-Host "TenantDomain: $($values.CloudAssignedTenantDomain)"
    Write-Host "TenantID: $($values.CloudAssignedTenantId)"
    $correlations = Get-ItemProperty "$($script:autopilotDiagPath)\EstablishedCorrelations"
    Write-Host "ZTDID: $($correlations.ZTDRegistrationID)"
    Write-Host "EntDMID: $($correlations.EntDMID)"
    Write-Host "OobeConfig: $($values.CloudAssignedOobeConfig)"

    # Use variables instead of inline if for better clarity.
    $skipKeyboard = (($values.CloudAssignedOobeConfig -band 1024) -gt 0) ? "Yes 1" : "No 0"
    Write-Host " Skip keyboard: $skipKeyboard"
    $enablePatch = (($values.CloudAssignedOobeConfig -band 512) -gt 0) ? "Yes 1" : "No 0"
    Write-Host " Enable patch download: $enablePatch"
    $skipUpgradeUX = (($values.CloudAssignedOobeConfig -band 256) -gt 0) ? "Yes 1" : "No 0"
    Write-Host " Skip Windows upgrade UX: $skipUpgradeUX"
    $tpmRequired = (($values.CloudAssignedOobeConfig -band 128) -gt 0) ? "Yes 1" : "No 0"
    Write-Host " AAD TPM Required: $tpmRequired"
    $aadDeviceAuth = (($values.CloudAssignedOobeConfig -band 64) -gt 0) ? "Yes 1" : "No 0"
    Write-Host " AAD device auth: $aadDeviceAuth"
    $tpmAttestation = (($values.CloudAssignedOobeConfig -band 32) -gt 0) ? "Yes 1" : "No 0"
    Write-Host " TPM attestation: $tpmAttestation"
    $skipEULA = (($values.CloudAssignedOobeConfig -band 16) -gt 0) ? "Yes 1" : "No 0"
    Write-Host " Skip EULA: $skipEULA"
    $skipOEM = (($values.CloudAssignedOobeConfig -band 8) -gt 0) ? "Yes 1" : "No 0"
    Write-Host " Skip OEM registration: $skipOEM"
    $skipExpress = (($values.CloudAssignedOobeConfig -band 4) -gt 0) ? "Yes 1" : "No 0"
    Write-Host " Skip express settings: $skipExpress"
    $disallowAdmin = (($values.CloudAssignedOobeConfig -band 2) -gt 0) ? "Yes 1" : "No 0"
    Write-Host " Disallow admin: $disallowAdmin"
    if ($script:useFile) {
        $jsonFile = Join-Path $tempPath "AutopilotDDSZTDFile.json"
    }
    else {
        $jsonFile = Join-Path $env:WINDIR "ServiceState\wmansvc\AutopilotDDSZTDFile.json"
    }
    if (Test-Path $jsonFile) {
        $json = Get-Content $jsonFile | ConvertFrom-Json
        $date = [datetime]$json.PolicyDownloadDate
        RecordStatus -date $date -detail "Autopilot profile" -status "Profile downloaded" -color "Yellow"
        if ($json.CloudAssignedDomainJoinMethod -eq 1) {
            Write-Host "Scenario: Hybrid Azure AD Join"
            if (Test-Path "$script:omadmPath\SyncML\ODJApplied") {
                Write-Host "ODJ applied: Yes"
            }
            else {
                Write-Host "ODJ applied: No"
            }
            $skipConnectivity = ($json.HybridJoinSkipDCConnectivityCheck -eq 1) ? "Yes" : "No"
            Write-Host "Skip connectivity check: $skipConnectivity"
        }
        else {
            Write-Host "Scenario: Azure AD Join"
        }
    }
    else {
        Write-Host "Scenario: Not available (JSON not found)"
    }
    $enrollmentItems = Get-ChildItem $script:enrollmentsPath | Where-Object { Test-Path "$($_.PSPath)\FirstSync" }
    foreach ($item in $enrollmentItems) {
        $props = Get-ItemProperty "$($item.PSPath)\FirstSync"
        Write-Host "Enrollment status page:"
        Write-Host " Device ESP enabled: $($props.SkipDeviceStatusPage -eq 0)"
        Write-Host " User ESP enabled: $($props.SkipUserStatusPage -eq 0)"
        Write-Host " ESP timeout: $($props.SyncFailureTimeout)"
        if ($props.BlockInStatusPage -eq 0) {
            Write-Host " ESP blocking: No"
        }
        else {
            Write-Host " ESP blocking: Yes"
            if ($props.BlockInStatusPage -band 1) { Write-Host " ESP allow reset: Yes" }
            if ($props.BlockInStatusPage -band 2) { Write-Host " ESP allow try again: Yes" }
            if ($props.BlockInStatusPage -band 4) { Write-Host " ESP continue anyway: Yes" }
        }
    }
    if (-not $script:useFile) {
        $stats = Get-DeliveryOptimizationPerfSnapThisMonth
        if ($stats.DownloadHttpBytes -ne 0) {
            $peerPct = [math]::Round( ($stats.DownloadLanBytes / $stats.DownloadHttpBytes) * 100 )
            $ccPct = [math]::Round( ($stats.DownloadCacheHostBytes / $stats.DownloadHttpBytes) * 100 )
        }
        else {
            $peerPct = 0
            $ccPct = 0
        }
        Write-Host "Delivery Optimization statistics:"
        Write-Host " Total bytes downloaded: $($stats.DownloadHttpBytes)"
        Write-Host " From peers: $peerPct% ($($stats.DownloadLanBytes))"
        Write-Host " From Connected Cache: $ccPct% ($($stats.DownloadCacheHostBytes))"
    }
    $adkPath = Get-ItemPropertyValue "HKLM:\Software\Microsoft\Windows Kits\Installed Roots" -Name KitsRoot10 -ErrorAction SilentlyContinue
    $oa3Tool = Join-Path $adkPath "Assessment and Deployment Kit\Deployment Tools\$($env:PROCESSOR_ARCHITECTURE)\Licensing\OA30\oa3tool.exe"
    if ($hash -and (Test-Path $oa3Tool)) {
        $output = & $oa3Tool "/decodehwhash:$hash"
        $outputText = $output -join "`n"
        try {
            [xml]$hashXML = [xml]$outputText
        }
        catch {
            Write-Host "Error parsing hardware hash XML: $_"
            $hashXML = $null
        }
        if ($hashXML) {
            Write-Host "Hardware information:"
            Write-Host " Operating system build: " ($hashXML.SelectSingleNode("//p[@n='OsBuild']")?.v)
            Write-Host " Manufacturer: " ($hashXML.SelectSingleNode("//p[@n='SmbiosSystemManufacturer']")?.v)
            Write-Host " Model: " ($hashXML.SelectSingleNode("//p[@n='SmbiosSystemProductName']")?.v)
            Write-Host " Serial number: " ($hashXML.SelectSingleNode("//p[@n='SmbiosSystemSerialNumber']")?.v)
            Write-Host " TPM version: " ($hashXML.SelectSingleNode("//p[@n='TPMVersion']")?.v)
        }
    }

    ProcessEvents
    if ($ShowPolicies) {
        Write-Host "`nPOLICIES PROCESSED" -ForegroundColor Magenta
        ProcessNodeCache | Format-Table -Wrap
    }

    if (Test-Path $script:path) {
        Write-Host "`nDEVICE ESP:" -ForegroundColor Magenta
        Write-Host ""
        if (Test-Path "$script:path\ExpectedPolicies") {
            $items = Get-ChildItem "$script:path\ExpectedPolicies"
            Add-Display ([ref]$items)
            $items | ProcessPolicies -display $true
        }
        if (Test-Path "$script:path\ExpectedMSIAppPackages") {
            $items = Get-ChildItem "$script:path\ExpectedMSIAppPackages"
            Add-Display ([ref]$items)
            $items | ProcessApps -currentUser "S-0-0-00-0000000000-0000000000-000000000-000" -display $true
        }
        if (Test-Path "$script:path\ExpectedModernAppPackages") {
            $items = Get-ChildItem "$script:path\ExpectedModernAppPackages"
            Add-Display ([ref]$items)
            $items | ProcessModernApps -currentUser "S-0-0-00-0000000000-0000000000-000000000-000" -display $true
        }
        if (Test-Path "$script:path\Sidecar") {
            $items = Get-ChildItem "$script:path\Sidecar" | Where-Object { $_.Property -match "./Device" -and $_.Name -notmatch "LastLoggedState" }
            Add-Display ([ref]$items)
            $items | ProcessSidecar -currentUser "00000000-0000-0000-0000-000000000000" -display $true
        }
        if (Test-Path "$script:path\ExpectedSCEPCerts") {
            $items = Get-ChildItem "$script:path\ExpectedSCEPCerts"
            Add-Display ([ref]$items)
            $items | ProcessCerts -display $true
        }
        $userSessions = Get-ChildItem $script:path | Where-Object { $_.PSChildName -like "S-*" }
        foreach ($session in $userSessions) {
            $userPath = $session.PSPath
            $userSid = $session.PSChildName
            Write-Host "`nUSER ESP for" $userSid -ForegroundColor Magenta

            Write-Host ""
            if (Test-Path "$userPath\ExpectedPolicies") {
                $items = Get-ChildItem "$userPath\ExpectedPolicies"
                Add-Display ([ref]$items)
                $items | ProcessPolicies -display $true
            }
            if (Test-Path "$userPath\ExpectedMSIAppPackages") {
                $items = Get-ChildItem "$userPath\ExpectedMSIAppPackages"
                Add-Display ([ref]$items)
                $items | ProcessApps -currentUser $userSid -display $true
            }
            if (Test-Path "$userPath\ExpectedModernAppPackages") {
                $items = Get-ChildItem "$userPath\ExpectedModernAppPackages"
                Add-Display ([ref]$items)
                $items | ProcessModernApps -currentUser $userSid -display $true
            }
            if (Test-Path "$userPath\Sidecar") {
                $items = Get-ChildItem "$script:path\Sidecar" | Where-Object { $_.Property -match "./User" }
                Add-Display ([ref]$items)
                $items | ProcessSidecar -currentUser $userSid -display $true
            }
            if (Test-Path "$userPath\ExpectedSCEPCerts") {
                $items = Get-ChildItem "$userPath\ExpectedSCEPCerts"
                Add-Display ([ref]$items)
                $items | ProcessCerts -display $true
            }
        }
    }
    else {
        Write-Host "ESP diagnostics info does not (yet) exist."
    }
    Write-Host "`nOBSERVED TIMELINE:" -ForegroundColor Magenta
    Write-Host ""
    $script:observedTimeline | Sort-Object -Property Date |
        Format-Table @{
            Label = "Date"
            Expression = { $_.Date.ToString("u") }
        }, @{
            Label = "Status"
            Expression = {
                switch ($_.Color) {
                    'Red' { $color = "91" }
                    'Yellow' { $color = "93" }
                    'Green' { $color = "92" }
                    default { $color = "0" }
                }
                $escapeChar = [char]27
                "$escapeChar[${color}m$($_.Status)$escapeChar[0m"
            }
        }, Detail
    Write-Host ""
}
End {
    # Remove temporary registry import if it exists.
    if (Test-Path "HKCU:\ESPStatus.tmp") {
        Remove-Item -Path "HKCU:\ESPStatus.tmp" -Recurse -Force
    }

    # --- Export results ------------------------------------------------
    # Create an export folder in TEMP
    $resultsFolder = Join-Path $env:TEMP "AutopilotDiagnosticsResults"
    if (Test-Path $resultsFolder) {
        Remove-Item -Path $resultsFolder -Recurse -Force
    }
    New-Item -Path $resultsFolder -ItemType Directory | Out-Null
    # Export the observed timeline as a text file.
    $timelineFile = Join-Path $resultsFolder "ObservedTimeline.txt"
    $script:observedTimeline | Sort-Object Date | Format-Table Date, Status, Detail -AutoSize | Out-String | Set-Content $timelineFile
    # (Optional: add additional exported result files here.)

    # Create a zip archive of the results folder.
    $zipFile = Join-Path $env:TEMP "AutopilotDiagnosticsResults.zip"
    if (Test-Path $zipFile) { Remove-Item -Path $zipFile -Force }
    Compress-Archive -Path (Join-Path $resultsFolder "*") -DestinationPath $zipFile
    # Copy the zip file to the logged in user's Desktop.
    $desktopPath = [System.Environment]::GetFolderPath("Desktop")
    Copy-Item -Path $zipFile -Destination $desktopPath -Force
    Write-Host "Export completed: A zipped file 'AutopilotDiagnosticsResults.zip' has been copied to your Desktop."
}
# SIG # Begin signature block
# (Signature block remains unchanged)
# SIG # End signature block