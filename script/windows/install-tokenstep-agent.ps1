param(
    [Parameter(Mandatory = $true)] [string] $AgentExe,
    [Parameter(Mandatory = $true)] [string] $IngestUrl,
    [ValidateRange(1, 1440)] [int] $IntervalMinutes = 1
)

$ErrorActionPreference = "Stop"
$Endpoint = [Uri] $IngestUrl
if (-not $Endpoint.IsAbsoluteUri -or $Endpoint.Scheme -ne "https" -or $Endpoint.UserInfo) {
    throw "IngestUrl must be HTTPS without embedded credentials."
}
$ExistingTask = Get-ScheduledTask -TaskName "TokenStep Agent" -ErrorAction SilentlyContinue
if ($ExistingTask) {
    Stop-ScheduledTask -TaskName "TokenStep Agent"
    $Deadline = (Get-Date).AddSeconds(30)
    while ((Get-ScheduledTask -TaskName "TokenStep Agent").State -eq "Running") {
        if ((Get-Date) -gt $Deadline) { throw "Existing collector did not stop. Retry installation later." }
        Start-Sleep -Milliseconds 250
    }
}
$InstallRoot = Join-Path $env:LOCALAPPDATA "TokenStep\Agent"
$BinDir = Join-Path $InstallRoot "bin"
$StateDir = Join-Path $env:LOCALAPPDATA "TokenStep\agent"
$LogDir = Join-Path $StateDir "logs"
$InstalledExe = Join-Path $BinDir "tokenstep-agent.exe"
$Runner = Join-Path $InstallRoot "run-tokenstep-agent.ps1"

New-Item -ItemType Directory -Force -Path $BinDir, $StateDir, $LogDir | Out-Null
if ([IO.Path]::GetFullPath((Resolve-Path $AgentExe).Path) -ne [IO.Path]::GetFullPath($InstalledExe)) {
    Copy-Item -Force $AgentExe $InstalledExe
}

$Template = @'
$ErrorActionPreference = "Stop"
$LogDir = '__LOG_DIR__'
$OutputLog = Join-Path $LogDir 'agent.log'
$ErrorLog = Join-Path $LogDir 'agent-error.log'
foreach ($Log in @($OutputLog, $ErrorLog)) {
    if ((Test-Path $Log) -and (Get-Item $Log).Length -gt 1MB) {
        Move-Item $Log ($Log + '.previous') -Force
    }
}
& '__EXE__' cycle --state-dir '__STATE_DIR__' --ingest-url '__INGEST_URL__' 1>> $OutputLog 2>> $ErrorLog
exit $LASTEXITCODE
'@
$Script = $Template.Replace('__LOG_DIR__', $LogDir.Replace("'", "''")).Replace('__EXE__', $InstalledExe.Replace("'", "''")).Replace('__STATE_DIR__', $StateDir.Replace("'", "''")).Replace('__INGEST_URL__', $IngestUrl.Replace("'", "''"))
Set-Content -Encoding UTF8 -Path $Runner -Value $Script

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Runner`""
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
$CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$Principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
Register-ScheduledTask -TaskName "TokenStep Agent" -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null

Write-Host "Installed: $InstalledExe"
Write-Host "Scheduled task: TokenStep Agent (every $IntervalMinutes minute(s))"
Write-Host "Verify with: Get-ScheduledTask -TaskName 'TokenStep Agent'"
Write-Host "Logs: $LogDir"
