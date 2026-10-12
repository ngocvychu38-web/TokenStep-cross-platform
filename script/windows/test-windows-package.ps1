$ErrorActionPreference = "Stop"
$Package = Join-Path "release/windows" "TokenStep-Agent-0.1.0-windows-x64"
foreach ($File in Get-ChildItem $PSScriptRoot -Filter *.ps1) {
    $Tokens = $null
    $ParseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$Tokens, [ref]$ParseErrors) | Out-Null
    if ($ParseErrors.Count) { throw "PowerShell parse failed: $($File.Name): $ParseErrors" }
}
foreach ($Line in Get-Content (Join-Path $Package "SHA256SUMS.txt")) {
    $Parts = $Line -split '  ', 2
    if ((Get-FileHash (Join-Path $Package $Parts[1]) -Algorithm SHA256).Hash -ne $Parts[0]) {
        throw "Checksum failed: $($Parts[1])"
    }
}
$Agent = (Resolve-Path (Join-Path $Package "tokenstep-agent.exe")).Path
& $Agent --version
if ($LASTEXITCODE -ne 0) { throw "Windows binary failed to start." }
& $Agent vault-check
if ($LASTEXITCODE -ne 0) { throw "Windows Credential Manager round-trip failed." }
$SavedLocalData = $env:LOCALAPPDATA
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ("TokenStep install fixture " + [Guid]::NewGuid())
try {
    $env:LOCALAPPDATA = $TestRoot
    & (Join-Path $Package "install-tokenstep-agent.ps1") -AgentExe $Agent -IngestUrl "https://example.com/functions/v1/ingest-usage"
    $Task = Get-ScheduledTask -TaskName "TokenStep Agent"
    if ($Task.Principal.RunLevel -ne "Limited" -or $Task.Settings.MultipleInstances -ne "IgnoreNew") {
        throw "Scheduled task permissions or concurrency settings are incorrect."
    }
    if ($Task.Triggers[0].Repetition.Interval -ne "PT1M") { throw "Wrong schedule interval." }
    if (-not (Test-Path (Join-Path $TestRoot "TokenStep/Agent/bin/tokenstep-agent.exe"))) { throw "Installed binary missing." }
    $Runner = Join-Path $TestRoot "TokenStep/Agent/run-tokenstep-agent.ps1"
    $Tokens = $null; $ParseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($Runner, [ref]$Tokens, [ref]$ParseErrors) | Out-Null
    if ($ParseErrors.Count) { throw "Generated runner has invalid syntax." }
    & (Join-Path $Package "uninstall.ps1")
    if (Get-ScheduledTask -TaskName "TokenStep Agent" -ErrorAction SilentlyContinue) { throw "Uninstall left scheduled task." }
    Write-Host "Windows package verification passed."
} finally {
    if (Get-ScheduledTask -TaskName "TokenStep Agent" -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName "TokenStep Agent" -Confirm:$false
    }
    $env:LOCALAPPDATA = $SavedLocalData
    if (Test-Path $TestRoot) { Remove-Item $TestRoot -Recurse -Force }
}
