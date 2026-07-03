<#
.SYNOPSIS
  Regenerate the vendored, pinned SpecKit skills (Windows twin of
  update-speckit-skills.sh).

.DESCRIPTION
  This is the ONE place SpecKit is ever installed or upgraded. It runs at the
  REPO level on a maintainer's machine (which has network), NOT inside the
  Hermes container and NOT from bootstrap.*. See docs/MOUNTS.md and
  speckit/README.md for why the install is vendored instead of done at
  container-start.

  Steps:
    1. Installs SpecKit *pinned* to speckit/SPECKIT_VERSION via
       `uvx --from git+...@v<version>` — reproducible regardless of whatever
       `specify` happens to be on PATH.
    2. Runs `specify init --integration claude`, which emits the `speckit-*`
       skills under .claude/skills/ plus the .specify/ manifest tree.
    3. Replaces the vendored copy under speckit/ with that output.
    4. Verifies the result is drift-clean (`specify integration status`).

  The output under speckit/ is meant to be committed to git.

.EXAMPLE
  scripts\update-speckit-skills.ps1
  scripts\update-speckit-skills.ps1 -Version 0.12.0
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Version
)

$ErrorActionPreference = 'Stop'

$RootDir     = Split-Path -Parent $PSScriptRoot
$VendorDir   = Join-Path $RootDir 'speckit'
$VersionFile = Join-Path $VendorDir 'SPECKIT_VERSION'
$SpecRepo    = 'https://github.com/github/spec-kit.git'

if (-not $Version) {
  if (Test-Path $VersionFile) {
    $Version = (Get-Content -Raw $VersionFile).Trim()
  } else {
    Write-Error "No version given and $VersionFile is missing. Pass -Version, e.g. -Version 0.11.5"
  }
}

if (-not (Get-Command uvx -ErrorAction SilentlyContinue)) {
  Write-Error "'uvx' not found. Install uv: https://docs.astral.sh/uv/"
}

$fromArg = "git+$SpecRepo@v$Version"

Write-Host "==> Regenerating vendored SpecKit skills at pinned version v$Version"
Write-Host "    vendor dir: $VendorDir"

$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("speckit-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TmpDir | Out-Null
try {
  Push-Location $TmpDir
  try {
    & git init -q .
    Write-Host "==> specify init (integration: claude, script: sh)..."
    & uvx --from $fromArg specify init . --integration claude --script sh --ignore-agent-tools --force
    if ($LASTEXITCODE -ne 0) { Write-Error "specify init failed (exit $LASTEXITCODE)." }
  } finally {
    Pop-Location
  }

  $skillsDir = Join-Path $TmpDir '.claude\skills'
  $hasSkills = (Test-Path $skillsDir) -and `
    ((Get-ChildItem -Path $skillsDir -Directory -Filter 'speckit-*' -ErrorAction SilentlyContinue).Count -gt 0)
  if (-not $hasSkills) {
    Write-Error "init produced no .claude/skills/speckit-* — aborting, vendored copy untouched."
  }

  Write-Host "==> Replacing vendored tree..."
  if (-not (Test-Path $VendorDir)) { New-Item -ItemType Directory -Path $VendorDir | Out-Null }
  foreach ($p in @('.specify', '.claude', 'CLAUDE.md')) {
    $target = Join-Path $VendorDir $p
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
  }
  Copy-Item -Recurse (Join-Path $TmpDir '.specify') (Join-Path $VendorDir '.specify')
  Copy-Item -Recurse (Join-Path $TmpDir '.claude')  (Join-Path $VendorDir '.claude')
  $claudeMd = Join-Path $TmpDir 'CLAUDE.md'
  if (Test-Path $claudeMd) { Copy-Item $claudeMd (Join-Path $VendorDir 'CLAUDE.md') }

  Set-Content -Path $VersionFile -Value $Version -NoNewline

  Write-Host "==> Verifying (specify integration status)..."
  Push-Location $VendorDir
  try {
    & uvx --from $fromArg specify integration status
    if ($LASTEXITCODE -ne 0) { Write-Error "integration status reported a problem (exit $LASTEXITCODE)." }
  } finally {
    Pop-Location
  }

  Write-Host ""
  Write-Host "==> Done. Vendored SpecKit skills at v${Version}:"
  Get-ChildItem -Path (Join-Path $VendorDir '.claude\skills') -Directory |
    ForEach-Object { Write-Host ("      " + $_.Name) }
  Write-Host ""
  Write-Host "    Review and commit:"
  Write-Host "      git add speckit/"
  Write-Host "      git commit -m 'Update vendored SpecKit skills to v$Version'"
}
finally {
  if (Test-Path $TmpDir) { Remove-Item -Recurse -Force $TmpDir }
}
