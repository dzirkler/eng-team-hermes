# bootstrap.ps1 — idempotent provisioning for one project's Hermes team.
#
# Usage:
#   .\bootstrap.ps1 -ProjectName token-tracker -RepoPath D:\code\ai-token-tracking
#
# Rewritten 2026-07-03 against a LIVE container (docker exec ... hermes
# --help / kanban --help / profile --help / hermes_cli source), not docs —
# see docs/temp/handoff-2026-07-02.md for the full resolution writeup. Every
# command below was actually run once against a running container before
# being put in this script. Safe to re-run: every step is create-if-missing
# or overwrite-with-template, never destructive.
#
# What changed from the previous (unverified) version:
#   - No such command as `hermes kanban worker-profile apply` — a Kanban
#     "worker" IS a real Hermes profile (`hermes profile create <name>`),
#     confirmed via `hermes kanban assignees` (reads ~/.hermes/profiles/)
#     and `hermes kanban create --assignee <profile>`.
#   - `hermes kanban notify-subscribe` is task-scoped
#     (`notify-subscribe <task-id>`), not board/profile/scope-scoped — it
#     can't run at bootstrap because no task exists yet. Subscribe the
#     orchestrator's top-level task explicitly once real work starts.
#   - `kanban.board` / `kanban.default_workspace` are not config.yaml keys.
#     Board slug and default workspace are set imperatively via
#     `hermes kanban boards create --default-workdir --switch`.
#   - config/config.yaml (and each profiles/<name>/config.yaml) was never
#     actually mounted anywhere — docker-compose.yml bind-mounts the whole
#     /opt/data tree from ./state/data, which starts empty. This script now
#     seeds ./state/data/config.yaml and ./state/data/profiles/<name>/
#     {config.yaml,SOUL.md} from the git-tracked sources before/after
#     container operations, then fixes ownership via `docker exec chown`
#     (docker exec runs as root; files written from a Windows host bind
#     mount don't reliably land as the container's hermes UID).

param(
    [Parameter(Mandatory = $true)][string]$ProjectName,
    [Parameter(Mandatory = $true)][string]$RepoPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $RepoPath)) {
    Write-Error "repo path '$RepoPath' does not exist"
    exit 1
}
$RepoPath = (Resolve-Path $RepoPath).Path -replace '\\', '/'

$RootDir = $PSScriptRoot
Set-Location $RootDir

$ProfileNames = @(
    "orchestrator", "product-manager", "project-manager",
    "senior-engineer", "implementation-engineer", "quality-engineer",
    "debugger", "qa-analyst", "ux-designer"
)
$ProfileDescriptions = @{
    "orchestrator"            = "Pure coordinator - creates and assigns Kanban tasks to specialist profiles, manages checkpoints, never writes code or files directly."
    "product-manager"         = "Owns requirements, prioritization, and product vision - Constitution/Specify/Clarify/Analyze SDD stages. Read-only; drafts nothing directly."
    "project-manager"         = "Owns sprint cadence, branch/PR setup, and gh pr ready conversion. Terminal/git access; never merges."
    "senior-engineer"         = "Owns Plan/Tasks and ad-hoc troubleshooting, fixes, and review - full read/write/terminal access, flagship-tier model."
    "implementation-engineer" = "Implements well-defined, already-scoped Implement-phase tasks only - full read/write/terminal access, cheap-tier model."
    "quality-engineer"        = "Owns test strategy, automation, and quality gates - writes and runs tests."
    "debugger"                = "Investigates bugs and test failures, produces root-cause analysis; diagnoses only, never implements fixes."
    "qa-analyst"              = "Validates the running app via browser automation (Playwright) - functional and UX pass/fail reporting, no code access."
    "ux-designer"             = "Owns the design system and produces UX briefs (user flow, layouts, accessibility) ahead of implementation."
}

Write-Host "==> Bootstrapping Hermes team for project: $ProjectName"
Write-Host "    repo:   $RepoPath"
Write-Host "    state:  $RootDir\state\data (writable, bind-mounted to /opt/data)"
Write-Host "    assets: $RootDir\{skills,profiles,hooks,config} (read-only source, host-versioned)"

function New-RandomSecret([int]$Length = 32) {
    $chars = (48..57) + (65..90) + (97..122)
    -join (1..$Length | ForEach-Object { [char](Get-Random -InputObject $chars) })
}

# ---------------------------------------------------------------------
# 1. Write/refresh .env. Preserves every existing value; only fills in
#    what's missing or still a placeholder. Never clobbers secrets that
#    are already set (the previous version of this script overwrote the
#    whole file with 4 lines, which would have wiped the dashboard auth
#    vars added after this script was first written).
# ---------------------------------------------------------------------
$envValues = [ordered]@{}
if (Test-Path .env) {
    foreach ($line in Get-Content .env) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $k, $v = $line -split '=', 2
        $envValues[$k.Trim()] = $v
    }
}

$envValues["PROJECT_NAME"] = $ProjectName
$envValues["PROJECT_REPO_PATH"] = $RepoPath
if (-not $envValues["Z_AI_API_KEY"]) { $envValues["Z_AI_API_KEY"] = "replace-me" }
if (-not $envValues["HERMES_IMAGE_TAG"]) { $envValues["HERMES_IMAGE_TAG"] = "latest" }
if (-not $envValues["HERMES_DASHBOARD_USERNAME"]) { $envValues["HERMES_DASHBOARD_USERNAME"] = "damon" }
if (-not $envValues["HERMES_DASHBOARD_PASSWORD"] -or $envValues["HERMES_DASHBOARD_PASSWORD"] -eq "replace-me") {
    $envValues["HERMES_DASHBOARD_PASSWORD"] = New-RandomSecret 24
    Write-Host "    Generated a random HERMES_DASHBOARD_PASSWORD."
}
if (-not $envValues["HERMES_DASHBOARD_SECRET"] -or $envValues["HERMES_DASHBOARD_SECRET"] -eq "replace-me-with-a-random-string") {
    $envValues["HERMES_DASHBOARD_SECRET"] = New-RandomSecret 48
    Write-Host "    Generated a random HERMES_DASHBOARD_SECRET."
}

($envValues.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n" |
    Set-Content -Path .env -NoNewline

if ($envValues["Z_AI_API_KEY"] -eq "replace-me") {
    Write-Host "    !! Z_AI_API_KEY not set - edit .env before starting the container."
}

# ---------------------------------------------------------------------
# 2. Seed the root (default profile) config.yaml onto the host side of
#    the bind mount. ./state/data maps 1:1 to /opt/data in the container
#    (see docker-compose.yml) - there is no separate mount for
#    config.yaml, so this copy is what actually makes config/config.yaml
#    take effect. Always overwrites: this repo is the source of truth,
#    not whatever the container last wrote there.
# ---------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path "state/data" | Out-Null
Copy-Item -Path "config/config.yaml" -Destination "state/data/config.yaml" -Force

# ---------------------------------------------------------------------
# 3. Start (or restart) the container.
# ---------------------------------------------------------------------
Write-Host "==> Starting container..."
docker compose up -d
if ($LASTEXITCODE -ne 0) { throw "docker compose up failed (exit $LASTEXITCODE)" }

$Container = "$ProjectName-hermes"

Write-Host "==> Waiting for container to be ready..."
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    docker exec $Container hermes version *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { throw "container did not become ready in time" }

# ---------------------------------------------------------------------
# 4. Create each worker profile (a real `hermes profile create`, not the
#    invented `kanban worker-profile apply`). Idempotent: an existing
#    profile errors with a message containing "already exists", which is
#    filtered out rather than treated as fatal.
# ---------------------------------------------------------------------
Write-Host "==> Ensuring worker profiles exist (orchestrator + 8 specialists)..."
foreach ($p in $ProfileNames) {
    Write-Host "    - $p"
    docker exec $Container hermes profile create $p --description $ProfileDescriptions[$p] --no-alias 2>&1 |
        Where-Object { $_ -notmatch "already exists" }
}

# ---------------------------------------------------------------------
# 5. Overlay each profile's config.yaml + SOUL.md from this repo onto its
#    freshly-created (or pre-existing) directory under state/data/profiles/,
#    then fix ownership from inside the container (docker exec runs as
#    root; files written from the Windows host don't reliably land as the
#    container's `hermes` UID, which would break Hermes's own read/write
#    of config.yaml, e.g. on the next schema-version migration).
# ---------------------------------------------------------------------
Write-Host "==> Syncing per-profile config.yaml + SOUL.md..."
foreach ($p in $ProfileNames) {
    $destDir = "state/data/profiles/$p"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Path "profiles/$p/config.yaml" -Destination "$destDir/config.yaml" -Force
    Copy-Item -Path "profiles/$p/SOUL.md" -Destination "$destDir/SOUL.md" -Force
    docker exec $Container chown hermes:hermes "/opt/data/profiles/$p/config.yaml" "/opt/data/profiles/$p/SOUL.md"
}
docker exec $Container chown hermes:hermes /opt/data/config.yaml

# ---------------------------------------------------------------------
# 6. Kanban board: create (idempotent - re-running prints "already
#    exists" and exits 0, confirmed against a live container), set this
#    project's default task workspace, and switch to it.
# ---------------------------------------------------------------------
Write-Host "==> Ensuring Kanban board '$ProjectName' exists..."
docker exec $Container hermes kanban boards create $ProjectName `
    --default-workdir "/workspace/$ProjectName" --switch

Write-Host "==> Done. Interface: docker exec -it $Container hermes"
Write-Host "    Dashboard: http://127.0.0.1:9119 (user: $($envValues['HERMES_DASHBOARD_USERNAME']))"
Write-Host ""
Write-Host "    NOTE: 'hermes kanban notify-subscribe <task-id>' is task-scoped, not"
Write-Host "    board/profile-scoped - there is no bootstrap-time equivalent. Subscribe"
Write-Host "    the orchestrator's top-level task explicitly once it's created:"
Write-Host "      docker exec -it $Container hermes kanban notify-subscribe <task-id>"
