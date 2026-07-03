<#
.SYNOPSIS
  Fail if the vendored SpecKit skills were hand-edited outside the install
  flow (Windows twin of check-speckit-drift.sh).

.DESCRIPTION
  The vendored tree under speckit/ is a real SpecKit project whose
  .specify/integrations/*.manifest.json record a SHA-256 for every managed
  file. `specify integration status` re-hashes them and reports any that no
  longer match. We reuse that instead of rolling our own hashing.

  Runs at the REPO level (needs network only the first time uvx resolves the
  pinned CLI). Intended for CI and/or a pre-commit/periodic check — NOT part
  of the container or bootstrap.*.

  Exit codes: 0 = clean, 1 = drift/missing detected, 2 = setup error.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RootDir     = Split-Path -Parent $PSScriptRoot
$VendorDir   = Join-Path $RootDir 'speckit'
$VersionFile = Join-Path $VendorDir 'SPECKIT_VERSION'
$SpecRepo    = 'https://github.com/github/spec-kit.git'

function Fail-Setup([string]$msg) { Write-Host $msg -ForegroundColor Red; exit 2 }

if (-not (Test-Path (Join-Path $VendorDir '.specify'))) {
  Fail-Setup "error: $VendorDir\.specify not found — run scripts\update-speckit-skills.ps1 first."
}
if (-not (Test-Path $VersionFile)) {
  Fail-Setup "error: $VersionFile missing — cannot determine the pinned version."
}
if (-not (Get-Command uvx -ErrorAction SilentlyContinue)) {
  Fail-Setup "error: 'uvx' not found. Install uv: https://docs.astral.sh/uv/"
}

$Version = (Get-Content -Raw $VersionFile).Trim()
$fromArg = "git+$SpecRepo@v$Version"

Push-Location $VendorDir
try {
  $statusJson = & uvx --from $fromArg specify integration status --json | Out-String
} finally {
  Pop-Location
}

$status = $statusJson | ConvertFrom-Json
$modified = [int]$status.modified_managed_files
$missing  = [int]$status.missing_managed_files

Write-Host "Pinned SpecKit version : v$Version"
Write-Host "Integration status     : $($status.status)"
Write-Host "Modified managed files : $modified"
Write-Host "Missing managed files  : $missing"

if ($status.status -eq 'ok' -and $modified -eq 0 -and $missing -eq 0) {
  Write-Host "OK: vendored SpecKit skills match the pinned manifest." -ForegroundColor Green
  exit 0
}

Write-Host ""
Write-Host "DRIFT DETECTED: vendored SpecKit skills differ from their pinned manifest." -ForegroundColor Red
Write-Host "Someone edited skill files under speckit/ by hand. Do NOT hand-edit them." -ForegroundColor Red
Write-Host "To pick up an upstream change, run: scripts\update-speckit-skills.ps1" -ForegroundColor Red
Write-Host "and commit the result. Full report:" -ForegroundColor Red
Write-Host $statusJson
exit 1
