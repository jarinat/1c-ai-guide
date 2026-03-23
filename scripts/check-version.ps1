[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
if ($null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

function Parse-Version([string]$VersionValue, [string]$SourceLabel) {
    if ($VersionValue -notmatch '^(?<year>\d{4})\.(?<month>\d{2})\.(?<day>\d{2})\.(?<counter>\d+)$') {
        Fail "$SourceLabel must use format YYYY.MM.DD.N"
    }

    $datePart = "$($Matches.year).$($Matches.month).$($Matches.day)"

    try {
        $parsedDate = [datetime]::ParseExact($datePart, "yyyy.MM.dd", $null)
    }
    catch {
        Fail "$SourceLabel contains an invalid date: $datePart"
    }

    [pscustomobject]@{
        Value = $VersionValue
        Date = $parsedDate.Date
        Counter = [int]$Matches.counter
    }
}

function Get-GitOutput([string[]]$Arguments, [switch]$AllowFailure) {
    $output = & git -c "safe.directory=$safeRepoRoot" -c core.excludesFile=NUL @Arguments 2>$null
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Fail "Failed to run git $($Arguments -join ' ')"
    }

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return ($output -join "`n").Trim()
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$safeRepoRoot = $repoRoot -replace '\\', '/'
Set-Location $repoRoot

$versionPath = Join-Path $repoRoot "VERSION"
if (-not (Test-Path $versionPath)) {
    Fail "VERSION file is missing."
}

$stagedFiles = Get-GitOutput -Arguments @("diff", "--cached", "--name-only", "--diff-filter=ACMR", "--", "VERSION")
if (-not $stagedFiles) {
    Fail "VERSION is not staged. Update it and run git add VERSION."
}

$stagedVersionRaw = Get-GitOutput -Arguments @("show", ":VERSION")
if (-not $stagedVersionRaw) {
    Fail "Failed to read VERSION from the index."
}

$stagedVersion = Parse-Version -VersionValue $stagedVersionRaw -SourceLabel "VERSION"
$today = (Get-Date).Date
if ($stagedVersion.Date -ne $today) {
    $expectedDate = Get-Date -Format "yyyy.MM.dd"
    Fail "VERSION date must match the commit date: expected $expectedDate"
}

$headVersionRaw = Get-GitOutput -Arguments @("show", "HEAD:VERSION") -AllowFailure
if (-not $headVersionRaw) {
    exit 0
}

$headVersion = Parse-Version -VersionValue $headVersionRaw -SourceLabel "HEAD:VERSION"
if ($headVersion.Value -eq $stagedVersion.Value) {
    Fail "VERSION was not changed relative to HEAD."
}

if ($stagedVersion.Date -lt $headVersion.Date) {
    Fail "New version cannot be older than the version in HEAD."
}

if ($stagedVersion.Date -eq $headVersion.Date -and $stagedVersion.Counter -le $headVersion.Counter) {
    Fail "Version counter must increase within the same day."
}

if ($stagedVersion.Date -gt $headVersion.Date -and $stagedVersion.Counter -ne 1) {
    Fail "Version counter must start from 1 on a new date."
}

exit 0
