# Modules\Utils.psm1

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = "[iTechDc][$Level]"
    Write-Host "$timestamp $prefix $Message"
}

function Show-MessageBox {
    param (
        [string]$Message,
        [string]$Title = "iTechDc",
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Type = "Info"
    )

    Add-Type -AssemblyName Microsoft.VisualBasic
    switch ($Type) {
        "Info"    { $icon = [Microsoft.VisualBasic.MsgBoxStyle]::Information }
        "Warning" { $icon = [Microsoft.VisualBasic.MsgBoxStyle]::Exclamation }
        "Error"   { $icon = [Microsoft.VisualBasic.MsgBoxStyle]::Critical }
    }

    [Microsoft.VisualBasic.Interaction]::MsgBox($Message, $icon, $Title) | Out-Null
}
