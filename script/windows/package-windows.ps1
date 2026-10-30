param(
    [string] $AgentExe = "target/release/tokenstep-agent.exe",
    [string] $OutputDirectory = "release/windows"
)
$ErrorActionPreference = "Stop"
$PackageName = "TokenStep-Agent-0.1.0-windows-x64"
$PackageRoot = Join-Path $OutputDirectory $PackageName
New-Item -ItemType Directory -Force -Path $PackageRoot | Out-Null
Copy-Item $AgentExe (Join-Path $PackageRoot "tokenstep-agent.exe") -Force
foreach ($Name in @("setup.ps1", "install.cmd", "install-tokenstep-agent.ps1", "uninstall.ps1", "uninstall.cmd", "README-install.txt")) {
    Copy-Item (Join-Path $PSScriptRoot $Name) (Join-Path $PackageRoot $Name) -Force
}
@{
    enrollment_url = "https://hdizeqfyrdfbqohrnuzt.supabase.co/functions/v1/enroll-device"
    ingest_url = "https://hdizeqfyrdfbqohrnuzt.supabase.co/functions/v1/ingest-usage"
} | ConvertTo-Json | Set-Content (Join-Path $PackageRoot "config.json") -Encoding UTF8
$Manifest = foreach ($File in Get-ChildItem $PackageRoot -File | Where-Object { $_.Name -ne "SHA256SUMS.txt" } | Sort-Object Name) {
    "{0}  {1}" -f (Get-FileHash $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $File.Name
}
$Manifest | Set-Content (Join-Path $PackageRoot "SHA256SUMS.txt") -Encoding ASCII
$Archive = Join-Path $OutputDirectory "$PackageName.zip"
Compress-Archive -Path $PackageRoot -DestinationPath $Archive -Force
Write-Host "Windows installer package: $Archive"
