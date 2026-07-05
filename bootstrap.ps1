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
# NOTE: this script performs NO SpecKit install, upgrade, or network fetch of
# skill content — by design. The speckit-* skills are vendored under speckit\
# at a pinned version and bind-mounted read-only (see docker-compose.yml,
# speckit\README.md). Regenerating them is a deliberate repo-level, committed
# operation via scripts\update-speckit-skills.*, never a container-start step.
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
    "debugger", "qa-analyst", "ux-designer", "independent-reviewer"
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
    "independent-reviewer"    = "Fresh-eyes review of spec/plan/tasks/analyze-report before Checkpoint 2 - no memory access, reports findings only, never edits artifacts."
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
# GLM_API_KEY (LiteLLM virtual key, main chat model) and GLM_BASE_URL
# (LiteLLM proxy) — added 2026-07-03, see docker-compose.yml's comment for
# why these are separate from Z_AI_API_KEY (which stays the real Z.AI key
# for the two direct-to-Z.AI MCP tools in config/config.yaml).
if (-not $envValues["GLM_API_KEY"]) { $envValues["GLM_API_KEY"] = "replace-me" }
if (-not $envValues["GLM_BASE_URL"]) { $envValues["GLM_BASE_URL"] = "https://litellm.home.zirkler.com/v1" }
if (-not $envValues["HERMES_IMAGE_TAG"]) { $envValues["HERMES_IMAGE_TAG"] = "latest" }
# MCP servers ported 2026-07-03 from the global VS Code MCP config — see
# config/config.yaml's mcp_servers block and .env.example for details.
if (-not $envValues["GITHUB_TOKEN"]) { $envValues["GITHUB_TOKEN"] = "replace-me" }
if (-not $envValues["FIRECRAWL_API_URL"]) { $envValues["FIRECRAWL_API_URL"] = "https://firecrawl.home.zirkler.com" }
if (-not $envValues["FIRECRAWL_API_KEY"]) { $envValues["FIRECRAWL_API_KEY"] = "replace-me" }
if (-not $envValues["MEMLORD_API_KEY"]) { $envValues["MEMLORD_API_KEY"] = "replace-me" }
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
if ($envValues["GLM_API_KEY"] -eq "replace-me") {
    Write-Host "    !! GLM_API_KEY not set (LiteLLM virtual key) - edit .env before starting the container."
}
if ($envValues["GITHUB_TOKEN"] -eq "replace-me") {
    Write-Host "    !! GITHUB_TOKEN not set - mcp_servers.github will fail to auth. Edit .env if you need it."
}
if ($envValues["FIRECRAWL_API_KEY"] -eq "replace-me") {
    Write-Host "    !! FIRECRAWL_API_KEY not set - mcp_servers.firecrawl will fail to auth. Edit .env if you need it."
}
if ($envValues["MEMLORD_API_KEY"] -eq "replace-me") {
    Write-Host "    !! MEMLORD_API_KEY not set - mcp_servers.memlord will fail to auth. Edit .env if you need it."
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
# 3b. DooD container execution (docs/DOCKER_EXECUTION.md): the docker CLI
#     binary + compose/buildx plugins were copied into the docker-cli-bin
#     volume by the docker-cli-provisioner service (compose already waited
#     for it via depends_on), mounted read-only at /opt/docker-cli. Not on
#     PATH by default, so symlink it into place — idempotent (ln -sf).
# ---------------------------------------------------------------------
Write-Host "==> Wiring up docker CLI (DooD)..."
docker exec $Container ln -sf /opt/docker-cli/bin/docker /usr/local/bin/docker
docker exec $Container mkdir -p /usr/local/libexec/docker/cli-plugins
docker exec $Container sh -c 'for f in /opt/docker-cli/cli-plugins/*; do [ -e "$f" ] && ln -sf "$f" "/usr/local/libexec/docker/cli-plugins/$(basename "$f")"; done; true'

# ---------------------------------------------------------------------
# 3c. Git tree ownership fix (docs/MOUNTS.md, Tier 3 - real incident
#     2026-07-04). Same UID-mismatch problem Tier 2 already had a fix for
#     ("on Windows via Docker Desktop this is not reliably the
#     container's hermes UID") also hits the bind-mounted project repo,
#     which never got the equivalent fix: confirmed live, .git/objects/*
#     subdirs land owned by uid 1000 while the container's hermes user is
#     uid 10000, so hermes can read/list but not write new loose objects
#     - `git commit` fails outright. chown the whole repo, not just
#     .git/, since the working tree needs the same fix (index updates,
#     checkouts, build artifacts). Idempotent, safe to re-run.
# ---------------------------------------------------------------------
Write-Host "==> Fixing git tree ownership..."
docker exec $Container chown -R hermes:hermes "/workspace/$ProjectName"

# ---------------------------------------------------------------------
# 3d. `gh` CLI (docs/MOUNTS.md, Tier 3 - same incident as 3c: the team
#     also could not push/open a PR at all, because the base hermes-agent
#     image ships no `gh` binary - same missing-binary problem `docker`
#     had, fixed the same way above). gh-cli-provisioner copied the
#     binary into the gh-cli-bin volume, mounted read-only at
#     /opt/gh-cli; symlink it into PATH, then run `gh auth setup-git` so
#     plain `git push`/`git pull` over HTTPS work too - no SSH key
#     needed. No `gh auth login` step: GITHUB_TOKEN is already a
#     container-wide env var (for mcp_servers.github), and `gh` auto-auths
#     from GITHUB_TOKEN/GH_TOKEN env vars on every invocation - confirmed
#     live, `gh auth login --with-token` actually *errors* while that env
#     var is set ("The value of the GITHUB_TOKEN environment variable is
#     being used for authentication... first clear the value from the
#     environment"), and is redundant anyway (`gh auth status` already
#     shows "Logged in ... (GITHUB_TOKEN)" with no login step run at all).
#     Skipped (with a warning, not a fatal error) if GITHUB_TOKEN is still
#     the placeholder - same precedent as the other optional-credential
#     warnings above. Idempotent: `gh auth setup-git` overwrites its own
#     credential.helper entries.
# ---------------------------------------------------------------------
Write-Host "==> Wiring up gh CLI..."
docker exec $Container ln -sf /opt/gh-cli/bin/gh /usr/local/bin/gh
if ($envValues["GITHUB_TOKEN"] -eq "replace-me") {
    Write-Host "    !! GITHUB_TOKEN not set - skipping 'gh auth setup-git'."
    Write-Host "       git push / gh pr create will fail until you set it and re-run bootstrap."
} else {
    docker exec $Container gh auth setup-git
}

# ---------------------------------------------------------------------
# 3e. Normalize an SSH-style origin remote to HTTPS (real incident
#     2026-07-04, socialcampaignmanager senior-engineer - see [3d] above
#     for the earlier half of this same incident). `gh auth setup-git`
#     only wires its credential helper into `credential."https://
#     github.com"` - it does nothing for a `git@github.com:...` or
#     `ssh://git@...` remote, which is what a repo cloned via SSH still
#     has. No SSH key is provisioned into these containers (deliberate -
#     one shared GITHUB_TOKEN is much easier to operate than a per-project
#     deploy key), so an SSH remote left in place means `git push` keeps
#     failing with "Permission denied (publickey)" even after 3d has
#     already fixed `gh`. Rewriting origin to the equivalent https:// URL
#     is what actually lets the token from 3d authenticate pushes.
#     Idempotent: no-ops once origin is already https://. Skipped (same
#     GITHUB_TOKEN guard as 3d) since an HTTPS remote with no working
#     credential helper is worse than leaving SSH in place - at least SSH
#     fails the same obvious way it did before.
# ---------------------------------------------------------------------
if ($envValues["GITHUB_TOKEN"] -ne "replace-me") {
    $originUrl = (docker exec $Container sh -c "cd /workspace/$ProjectName && git remote get-url origin" 2>$null)
    if ($originUrl -match '^git@github\.com:(.+)$' -or $originUrl -match '^ssh://git@github\.com/(.+)$') {
        $httpsUrl = "https://github.com/$($Matches[1])"
        Write-Host "==> Normalizing origin remote to HTTPS (was $originUrl)..."
        docker exec $Container sh -c "cd /workspace/$ProjectName && git remote set-url origin '$httpsUrl'"
    }
}

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
# 5b. Holographic memory: pre-create + pre-warm the shared "eng knowledge"
#     store (see profiles/debugger/config.yaml for the full writeup) BEFORE
#     any profile's session can touch it. Empirically confirmed 2026-07-04:
#     two processes racing to create the SAME not-yet-existing SQLite file
#     can hit an unhandled "database is locked" error on the initial WAL
#     pragma (hermes_state.py's WAL-fallback only catches NFS/SMB/FUSE
#     error strings, not ordinary lock contention -- it re-raises). Once
#     the file/schema/WAL mode already exist, concurrent writers are fine
#     (also confirmed empirically). Warming here means the six sharing
#     profiles' first real fact_store call always hits the safe,
#     already-initialized case instead of racing each other on first use.
#     Idempotent: MemoryStore() only creates what's missing.
# ---------------------------------------------------------------------
Write-Host "==> Pre-warming shared Holographic memory store..."
New-Item -ItemType Directory -Force -Path "state/data/shared" | Out-Null
docker exec $Container python3 -c @'
import sys
sys.path.insert(0, "/opt/hermes/plugins/memory/holographic")
from store import MemoryStore
MemoryStore(db_path="/opt/data/shared/eng_memory_store.db")
'@
docker exec $Container chown -R hermes:hermes /opt/data/shared

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
