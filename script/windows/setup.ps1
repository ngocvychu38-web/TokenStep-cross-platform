param(
    [string] $EnrollmentCode,
    [ValidateRange(1, 1440)] [int] $IntervalMinutes = 1
)

$ErrorActionPreference = "Stop"
try {
    if (-not [Environment]::Is64BitOperatingSystem) { throw "Windows x64 is required." }
    $Config = Get-Content (Join-Path $PSScriptRoot "config.json") -Raw | ConvertFrom-Json
    $Agent = Join-Path $PSScriptRoot "tokenstep-agent.exe"
    $ExpectedHash = (Get-Content (Join-Path $PSScriptRoot "SHA256SUMS.txt") | Where-Object { $_ -match '  tokenstep-agent.exe$' }) -split '  ', 2
    if (-not $ExpectedHash -or (Get-FileHash $Agent -Algorithm SHA256).Hash -ne $ExpectedHash[0]) {
        throw "Package checksum mismatch. Extract the complete ZIP again."
    }
    & $Agent vault-check
    if ($LASTEXITCODE -ne 0) { throw "Windows Credential Manager check failed." }
    if ([string]::IsNullOrWhiteSpace($EnrollmentCode)) {
        $EnrollmentCode = Read-Host "Enter the one-time TokenStep device enrollment code"
    }
    if ([string]::IsNullOrWhiteSpace($EnrollmentCode)) { throw "Enrollment code is required." }
    & $Agent enroll --enrollment-url $Config.enrollment_url --code $EnrollmentCode
    $EnrollmentCode = $null
    if ($LASTEXITCODE -ne 0) { throw "Device enrollment failed. Obtain a fresh code and retry." }
    & (Join-Path $PSScriptRoot "install-tokenstep-agent.ps1") -AgentExe $Agent -IngestUrl $Config.ingest_url -IntervalMinutes $IntervalMinutes
    if (-not $?) { throw "Scheduled task installation failed." }
    Start-ScheduledTask -TaskName "TokenStep Agent"
    Write-Host "Installation complete. The first collection/upload is running in the background."
    Write-Host "Read logs under: $env:LOCALAPPDATA\TokenStep\agent\logs"
    exit 0
} catch {
    Write-Host ("Installation failed: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
