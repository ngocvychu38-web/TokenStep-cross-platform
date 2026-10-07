$ErrorActionPreference = "Stop"
try {
    $Task = Get-ScheduledTask -TaskName "TokenStep Agent" -ErrorAction SilentlyContinue
    if ($Task) {
        Stop-ScheduledTask -TaskName "TokenStep Agent" -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "TokenStep Agent" -Confirm:$false
    }
    Write-Host "TokenStep background collection stopped and scheduled task removed."
    Write-Host "Local data and device credentials are preserved for reinstallation."
    Write-Host "To revoke cloud upload permission, disable this device in your TokenStep workspace."
    exit 0
} catch {
    Write-Host ("Uninstall failed: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
