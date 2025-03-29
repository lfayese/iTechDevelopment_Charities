# Modules\Deployment.psm1

# Ensure UEFI module is loaded
if (-not (Get-Command Set-UEFIVariable -ErrorAction SilentlyContinue)) {
    Import-Module "$PSScriptRoot\UEFI.psm1" -Force
}

function Set-NetworkFlag {
    [byte[]]$bytes = 1, 0, 0, 0
    Set-UEFIVariable -Namespace "{616e2ea6-af89-7eb3-f2ef-4e47368a657b}" -VariableName "FORCED_NETWORK_FLAG" -ByteArray $bytes
}

function Test-HardwareCompatibility {
    $CPU = Get-CimInstance -ClassName Win32_Processor
    $TPM = Get-CimInstance -Namespace 'root\cimv2\security\microsofttpm' -ClassName Win32_TPM

    $isCompatible = $true

    # Intel CPU Gen check
    if ($CPU.Name -like "Intel(R) Core(TM) i?-[2-7]*") {
        $isCompatible = $false
    }

    # TPM 2.0 Check
    if (-not ($TPM.SpecVersion -like "2.*")) {
        $isCompatible = $false
    }

    return $isCompatible
}

function Get-BootMediaInfo {
    $global:WimFiles = @()
    $global:BootMediaPath = $null
    $global:BootMediaType = "Unknown"

    $drives = Get-PSDrive -PSProvider FileSystem

    foreach ($drive in $drives) {
        $driveRoot = $drive.Root.TrimEnd('\')
        $driveInfo = Get-CimInstance -Class Win32_LogicalDisk -Filter "DeviceID='$driveRoot'"

        # USB Layout
        if (Test-Path "$($drive.Root)OSDCloud\WIM") {
            $wims = Get-ChildItem -Path "$($drive.Root)OSDCloud\WIM" -Filter "*.wim" -ErrorAction SilentlyContinue
            if ($wims.Count -gt 0) {
                $global:BootMediaType = "USB"
                $global:BootMediaPath = $drive.Root
                foreach ($wim in $wims) {
                    $global:WimFiles += [PSCustomObject]@{
                        Name     = $wim.Name
                        FullPath = $wim.FullName
                        Source   = "USB"
                    }
                }
                return "USB"
            }
        }

        # ISO Layout
        if (Test-Path "$($drive.Root)sources") {
            $wims = Get-ChildItem -Path "$($drive.Root)sources" -Filter "*.wim" -ErrorAction SilentlyContinue
            if ($wims.Count -gt 0) {
                $global:BootMediaType = "ISO"
                $global:BootMediaPath = $drive.Root
                foreach ($wim in $wims) {
                    $global:WimFiles += [PSCustomObject]@{
                        Name     = $wim.Name
                        FullPath = $wim.FullName
                        Source   = "ISO"
                    }
                }
                return "ISO"
            }
        }

        # Look for fallback OSDCloud folder
        if (Test-Path "$($drive.Root)OSDCloud" -and -not $global:BootMediaPath) {
            $global:BootMediaType = "Custom"
            $global:BootMediaPath = $drive.Root
        }
    }

    # Recursive fallback search for any .wim
    if ($global:WimFiles.Count -eq 0) {
        foreach ($drive in $drives) {
            $wims = Get-ChildItem -Path $drive.Root -Filter "*.wim" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 10
            foreach ($wim in $wims) {
                $global:WimFiles += [PSCustomObject]@{
                    Name     = $wim.Name
                    FullPath = $wim.FullName
                    Source   = "Other"
                }
            }
        }
    }

    return $global:BootMediaType
}
