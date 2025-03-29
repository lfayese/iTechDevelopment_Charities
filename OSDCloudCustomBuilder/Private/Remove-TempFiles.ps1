function Remove-TempFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TempPath
    )
    
    Write-Host "Cleaning up temporary files..." -ForeColor Cyan
    
    try {
        Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Temporary files cleaned up" -ForeColor Green
    } catch {
        Write-Warning "Failed to clean up temporary files: $_"
    }
}