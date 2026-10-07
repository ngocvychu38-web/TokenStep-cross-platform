param(
    [Parameter(Mandatory = $true)] [string] $AgentExe,
    [Parameter(Mandatory = $true)] [string] $IngestUrl,
    [ValidateRange(1, 1440)] [int] $IntervalMinutes = 1
)

$ErrorActionPreference = "Stop"
$InstallRoot = Join-Path $env:LOCALAPPDATA "TokenStep\Agent"
$BinDir = Join-Path $InstallRoot "bin"
$StateDir = Join-Path $env:LOCALAPPDATA "TokenStep\agent"
$Snapshot = Join-Path $StateDir "snapshot.json"
$InstalledExe = Join-Path $BinDir "tokenstep-agent.exe"
$Runner = Join-Path $InstallRoot "run-tokenstep-agent.ps1"

New-Item -ItemType Directory -Force -Path $BinDir, $StateDir | Out-Null
Copy-Item -Force $AgentExe $InstalledExe

$Script = @"
`$ErrorActionPreference = "Stop"
& "$InstalledExe" cycle --state-dir "$StateDir" --ingest-url "$IngestUrl"
exit `$LASTEXITCODE
"@
Set-Content -Encoding UTF8 -Path $Runner -Value $Script

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Runner`""
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName "TokenStep Agent" -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null

Write-Host "Installed: $InstalledExe"
Write-Host "Scheduled task: TokenStep Agent (every $IntervalMinutes minute(s))"
Write-Host "Verify with: Get-ScheduledTask -TaskName 'TokenStep Agent'"
