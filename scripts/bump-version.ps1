[CmdletBinding()]
param(
    [switch]$Stage
)

$ErrorActionPreference = "Stop"
if ($null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$safeRepoRoot = $repoRoot -replace '\\', '/'
$versionPath = Join-Path $repoRoot "VERSION"
$today = Get-Date -Format "yyyy.MM.dd"
$nextCounter = 1

if (Test-Path $versionPath) {
    $currentVersion = (Get-Content -Raw $versionPath).Trim()

    if ($currentVersion -match '^(?<date>\d{4}\.\d{2}\.\d{2})\.(?<counter>\d+)$') {
        if ($Matches.date -eq $today) {
            $nextCounter = [int]$Matches.counter + 1
        }
    }
}

$nextVersion = "$today.$nextCounter"
Set-Content -Path $versionPath -Value $nextVersion -NoNewline

if ($Stage) {
    & git -c "safe.directory=$safeRepoRoot" -c core.excludesFile=NUL add VERSION
}

Write-Output $nextVersion
