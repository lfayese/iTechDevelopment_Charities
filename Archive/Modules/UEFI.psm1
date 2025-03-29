# Modules\UEFI.psm1

$definition = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class UEFINative
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern UInt32 GetFirmwareEnvironmentVariableA(string lpName, string lpGuid, [Out] Byte[] lpBuffer, UInt32 nSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern UInt32 SetFirmwareEnvironmentVariableA(string lpName, string lpGuid, Byte[] lpBuffer, UInt32 nSize);

    [DllImport("ntdll.dll", SetLastError = true)]
    public static extern UInt32 NtEnumerateSystemEnvironmentValuesEx(UInt32 function, [Out] Byte[] lpBuffer, ref UInt32 nSize);
}
'@

$global:uefiNative = Add-Type -TypeDefinition $definition -PassThru

# Global GUIDs
$global:UEFIGlobal = "{8BE4DF61-93CA-11D2-AA0D-00E098032B8C}"
$global:UEFIWindows = "{77FA9ABD-0359-4D32-BD60-28F4E78F784B}"
$global:UEFISurface = "{D2E0B9C9-9860-42CF-B360-F906D5E0077A}"
$global:UEFITesting = "{1801FBE3-AEF7-42A8-B1CD-FC4AFAE14716}"
$global:UEFISecurityDatabase = "{d719b2cb-3d3a-4596-a3bc-dad00e67656f}"

function Set-LHSTokenPrivilege {
    param (
        [string]$Privilege,
        [int]$ProcessId = $pid,
        [switch]$Disable
    )
    $code = @'
    using System;
    using System.Runtime.InteropServices;

    public class AdjPriv {
        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
        [DllImport("advapi32.dll", SetLastError = true)]
        internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        internal struct TokPriv1Luid {
            public int Count;
            public long Luid;
            public int Attr;
        }

        internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
        internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
        internal const int TOKEN_QUERY = 0x00000008;
        internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;

        public static bool EnablePrivilege(long processHandle, string privilege, bool disable) {
            bool retVal;
            TokPriv1Luid tp;
            IntPtr hproc = new IntPtr(processHandle);
            IntPtr htok = IntPtr.Zero;
            retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
            tp.Count = 1;
            tp.Luid = 0;
            tp.Attr = disable ? SE_PRIVILEGE_DISABLED : SE_PRIVILEGE_ENABLED;
            retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
            retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            return retVal;
        }
    }
'@

    $type = Add-Type -TypeDefinition $code -PassThru
    $processHandle = (Get-Process -Id $ProcessId).Handle
    $type[0]::EnablePrivilege($processHandle, $Privilege, $Disable.IsPresent)
}

function Set-UEFIVariable {
    param (
        [string]$Namespace = $global:UEFIGlobal,
        [Parameter(Mandatory)] [string]$VariableName,
        [string]$Value = "",
        [byte[]]$ByteArray
    )
    Set-LHSTokenPrivilege -Privilege SeSystemEnvironmentPrivilege

    if ($Value) {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($Value)
        $uefiNative[0]::SetFirmwareEnvironmentVariableA($VariableName, $Namespace, $bytes, $bytes.Length) | Out-Null
    } elseif ($ByteArray) {
        $uefiNative[0]::SetFirmwareEnvironmentVariableA($VariableName, $Namespace, $ByteArray, $ByteArray.Length) | Out-Null
    }

    Set-LHSTokenPrivilege -Privilege SeSystemEnvironmentPrivilege -Disable
}

function Get-UEFIVariable {
    param (
        [string]$Namespace = $global:UEFIGlobal,
        [Parameter(Mandatory)] [string]$VariableName,
        [switch]$AsByteArray
    )
    Set-LHSTokenPrivilege -Privilege SeSystemEnvironmentPrivilege
    $size = 1024
    $result = New-Object byte[]($size)
    $rc = $uefiNative[0]::GetFirmwareEnvironmentVariableA($VariableName, $Namespace, $result, $size)
    if ($rc -eq 0) {
        Write-Error "Unable to retrieve variable $VariableName"
        return $null
    }
    [System.Array]::Resize([ref]$result, $rc)
    Set-LHSTokenPrivilege -Privilege SeSystemEnvironmentPrivilege -Disable

    if ($AsByteArray) {
        return $result
    }
    return ([System.Text.Encoding]::ASCII).GetString($result)
}
