#!/usr/bin/env bash
# bootstrap.sh — idempotent provisioning for one project's Hermes team.
#
# Usage:
#   ./bootstrap.sh <project-name> <repo-path>
#
# Rewritten 2026-07-03 against a LIVE container (docker exec ... hermes
# --help / kanban --help / profile --help / hermes_cli source), not docs —
# see docs/temp/handoff-2026-07-02.md for the full resolution writeup. Every
# command below was actually run once against a running container before
# being put in this script. Safe to re-run: every step is create-if-missing
# or overwrite-with-template, never destructive.
#
# NOTE: this script performs NO SpecKit install, upgrade, or network fetch of
# skill content — by design. The speckit-* skills are vendored under speckit/
# at a pinned version and bind-mounted read-only (see docker-compose.yml,
# speckit/README.md). Regenerating them is a deliberate repo-level, committed
# operation via scripts/update-speckit-skills.*, never a container-start step.
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
#     (docker exec runs as root; files written from the host don't
#     reliably land as the container's hermes UID).

set -euo pipefail

# Git-Bash/MSYS rewrites absolute-looking POSIX paths (e.g. /opt/data/...)
# passed to a Windows exe like docker.exe into host paths (e.g.
# "C:/Program Files/Git/opt/data/..."), breaking every `docker exec ...
# <container-side path>` call below on Windows. No-op on real POSIX
# systems (Linux/macOS containers there don't have MSYS installed).
export MSYS_NO_PATHCONV=1

PROJECT_NAME="${1:?Usage: ./bootstrap.sh <project-name> <repo-path>}"
REPO_PATH="${2:?Usage: ./bootstrap.sh <project-name> <repo-path>}"

if [[ ! -d "$REPO_PATH" ]]; then
  echo "error: repo path '$REPO_PATH' does not exist or is not a directory" >&2
  exit 1
fi
REPO_PATH="$(cd "$REPO_PATH" && pwd)"
if command -v cygpath > /dev/null 2>&1; then
  # Git-Bash/MSYS on Windows: `pwd` above just gave the POSIX form
  # (/d/code/...). That happens to get silently reinterpreted by Docker
  # Desktop today when it reaches docker-compose.yml's Tier 3 bind mount
  # or gets forwarded into the container as PROJECT_REPO_PATH for
  # sibling-container mounts (see docs/DOCKER_EXECUTION.md) — but that's
  # relying on undocumented path translation, not a guaranteed contract.
  # Convert explicitly to the same Windows-style forward-slash form
  # (D:/code/...) that bootstrap.ps1 already produces (its
  # `-replace '\\', '/'`) and that .env.example documents as the expected
  # format, so both entry points agree and nothing depends on Docker
  # Desktop's implicit translation.
  REPO_PATH="$(cygpath -m "$REPO_PATH")"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PROFILE_NAMES=(orchestrator product-manager project-manager senior-engineer \
               implementation-engineer quality-engineer debugger qa-analyst ux-designer \
               independent-reviewer)

profile_description() {
  case "$1" in
    orchestrator) echo "Pure coordinator - creates and assigns Kanban tasks to specialist profiles, manages checkpoints, never writes code or files directly." ;;
    product-manager) echo "Owns requirements, prioritization, and product vision - Constitution/Specify/Clarify/Analyze SDD stages. Read-only; drafts nothing directly." ;;
    project-manager) echo "Owns sprint cadence, branch/PR setup, and gh pr ready conversion. Terminal/git access; never merges." ;;
    senior-engineer) echo "Owns Plan/Tasks and ad-hoc troubleshooting, fixes, and review - full read/write/terminal access, flagship-tier model." ;;
    implementation-engineer) echo "Implements well-defined, already-scoped Implement-phase tasks only - full read/write/terminal access, cheap-tier model." ;;
    quality-engineer) echo "Owns test strategy, automation, and quality gates - writes and runs tests." ;;
    debugger) echo "Investigates bugs and test failures, produces root-cause analysis; diagnoses only, never implements fixes." ;;
    qa-analyst) echo "Validates the running app via browser automation (Playwright) - functional and UX pass/fail reporting, no code access." ;;
    ux-designer) echo "Owns the design system and produces UX briefs (user flow, layouts, accessibility) ahead of implementation." ;;
    independent-reviewer) echo "Fresh-eyes review of spec/plan/tasks/analyze-report before Checkpoint 2 - no memory access, reports findings only, never edits artifacts." ;;
  esac
}

random_secret() {
  local length="${1:-32}"
  local out
  # head closing early after $length bytes sends SIGPIPE to tr, which under
  # `set -o pipefail` makes this pipeline's exit status 141 and kills the
  # script (set -e) — disable pipefail just for this call.
  set +o pipefail
  out="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")"
  set -o pipefail
  printf '%s' "$out"
}

echo "==> Bootstrapping Hermes team for project: $PROJECT_NAME"
echo "    repo:   $REPO_PATH"
echo "    state:  $ROOT_DIR/state/data (writable, bind-mounted to /opt/data)"
echo "    assets: $ROOT_DIR/{skills,profiles,hooks,config} (read-only source, host-versioned)"

# ---------------------------------------------------------------------
# 1. Write/refresh .env. Preserves every existing value; only fills in
#    what's missing or still a placeholder — never clobbers secrets that
#    are already set (the previous version of this script overwrote the
#    whole file with 4 lines, which would have wiped the dashboard auth
#    vars added after this script was first written).
# ---------------------------------------------------------------------
declare -A env_values
if [[ -f .env ]]; then
  while IFS='=' read -r k v; do
    [[ -z "$k" || "$k" == \#* ]] && continue
    env_values["$k"]="$v"
  done < .env
fi

env_values["PROJECT_NAME"]="$PROJECT_NAME"
env_values["PROJECT_REPO_PATH"]="$REPO_PATH"
: "${env_values[Z_AI_API_KEY]:=replace-me}"
# GLM_API_KEY (LiteLLM virtual key, main chat model) and GLM_BASE_URL
# (LiteLLM proxy) — added 2026-07-03, see docker-compose.yml's comment for
# why these are separate from Z_AI_API_KEY (which stays the real Z.AI key
# for the two direct-to-Z.AI MCP tools in config/config.yaml).
: "${env_values[GLM_API_KEY]:=replace-me}"
: "${env_values[GLM_BASE_URL]:=https://litellm.home.zirkler.com/v1}"
: "${env_values[HERMES_IMAGE_TAG]:=latest}"
# MCP servers ported 2026-07-03 from the global VS Code MCP config — see
# config/config.yaml's mcp_servers block and .env.example for details.
: "${env_values[GITHUB_TOKEN]:=replace-me}"
: "${env_values[FIRECRAWL_API_URL]:=https://firecrawl.home.zirkler.com}"
: "${env_values[FIRECRAWL_API_KEY]:=replace-me}"
: "${env_values[MEMLORD_API_KEY]:=replace-me}"
: "${env_values[HERMES_DASHBOARD_USERNAME]:=damon}"

if [[ -z "${env_values[HERMES_DASHBOARD_PASSWORD]:-}" || "${env_values[HERMES_DASHBOARD_PASSWORD]}" == "replace-me" ]]; then
  env_values["HERMES_DASHBOARD_PASSWORD"]="$(random_secret 24)"
  echo "    Generated a random HERMES_DASHBOARD_PASSWORD."
fi
if [[ -z "${env_values[HERMES_DASHBOARD_SECRET]:-}" || "${env_values[HERMES_DASHBOARD_SECRET]}" == "replace-me-with-a-random-string" ]]; then
  env_values["HERMES_DASHBOARD_SECRET"]="$(random_secret 48)"
  echo "    Generated a random HERMES_DASHBOARD_SECRET."
fi

: > .env
for k in "${!env_values[@]}"; do
  echo "$k=${env_values[$k]}" >> .env
done

if [[ "${env_values[Z_AI_API_KEY]}" == "replace-me" ]]; then
  echo "    !! Z_AI_API_KEY not set — edit .env before starting the container."
fi
if [[ "${env_values[GLM_API_KEY]}" == "replace-me" ]]; then
  echo "    !! GLM_API_KEY not set (LiteLLM virtual key) — edit .env before starting the container."
fi
if [[ "${env_values[GITHUB_TOKEN]}" == "replace-me" ]]; then
  echo "    !! GITHUB_TOKEN not set — mcp_servers.github will fail to auth. Edit .env if you need it."
fi
if [[ "${env_values[FIRECRAWL_API_KEY]}" == "replace-me" ]]; then
  echo "    !! FIRECRAWL_API_KEY not set — mcp_servers.firecrawl will fail to auth. Edit .env if you need it."
fi
if [[ "${env_values[MEMLORD_API_KEY]}" == "replace-me" ]]; then
  echo "    !! MEMLORD_API_KEY not set — mcp_servers.memlord will fail to auth. Edit .env if you need it."
fi

# ---------------------------------------------------------------------
# 2. Seed the root (default profile) config.yaml onto the host side of
#    the bind mount. ./state/data maps 1:1 to /opt/data in the container
#    (see docker-compose.yml) — there is no separate mount for
#    config.yaml, so this copy is what actually makes config/config.yaml
#    take effect. Always overwrites: this repo is the source of truth,
#    not whatever the container last wrote there.
# ---------------------------------------------------------------------
mkdir -p state/data
cp config/config.yaml state/data/config.yaml

# ---------------------------------------------------------------------
# 3. Start (or restart) the container.
# ---------------------------------------------------------------------
echo "==> Starting container..."
docker compose up -d

CONTAINER="${PROJECT_NAME}-hermes"

echo "==> Waiting for container to be ready..."
ready=false
for i in $(seq 1 20); do
  if docker exec "$CONTAINER" hermes version > /dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
if [[ "$ready" != true ]]; then
  echo "error: container did not become ready in time" >&2
  exit 1
fi

# ---------------------------------------------------------------------
# 3b. DooD container execution (docs/DOCKER_EXECUTION.md): the docker CLI
#     binary + compose/buildx plugins were copied into the docker-cli-bin
#     volume by the docker-cli-provisioner service (compose already waited
#     for it via depends_on), mounted read-only at /opt/docker-cli. Not on
#     PATH by default, so symlink it into place — idempotent (ln -sf).
# ---------------------------------------------------------------------
echo "==> Wiring up docker CLI (DooD)..."
docker exec "$CONTAINER" ln -sf /opt/docker-cli/bin/docker /usr/local/bin/docker
docker exec "$CONTAINER" mkdir -p /usr/local/libexec/docker/cli-plugins
docker exec "$CONTAINER" sh -c \
  'for f in /opt/docker-cli/cli-plugins/*; do [ -e "$f" ] && ln -sf "$f" "/usr/local/libexec/docker/cli-plugins/$(basename "$f")"; done; true'

# ---------------------------------------------------------------------
# 4. Create each worker profile (a real `hermes profile create`, not the
#    invented `kanban worker-profile apply`). Idempotent: an existing
#    profile errors with a message containing "already exists", which is
#    filtered out rather than treated as fatal.
# ---------------------------------------------------------------------
echo "==> Ensuring worker profiles exist (orchestrator + 8 specialists)..."
for p in "${PROFILE_NAMES[@]}"; do
  echo "    - $p"
  docker exec "$CONTAINER" hermes profile create "$p" \
    --description "$(profile_description "$p")" --no-alias 2>&1 \
    | grep -v "already exists" || true
done

# ---------------------------------------------------------------------
# 5. Overlay each profile's config.yaml + SOUL.md from this repo onto its
#    freshly-created (or pre-existing) directory under state/data/profiles/,
#    then fix ownership from inside the container (docker exec runs as
#    root; files written from the host don't reliably land as the
#    container's `hermes` UID, which would break Hermes's own read/write
#    of config.yaml, e.g. on the next schema-version migration).
# ---------------------------------------------------------------------
echo "==> Syncing per-profile config.yaml + SOUL.md..."
for p in "${PROFILE_NAMES[@]}"; do
  dest_dir="state/data/profiles/$p"
  mkdir -p "$dest_dir"
  cp "profiles/$p/config.yaml" "$dest_dir/config.yaml"
  cp "profiles/$p/SOUL.md" "$dest_dir/SOUL.md"
  docker exec "$CONTAINER" chown hermes:hermes \
    "/opt/data/profiles/$p/config.yaml" "/opt/data/profiles/$p/SOUL.md"
done
docker exec "$CONTAINER" chown hermes:hermes /opt/data/config.yaml

# ---------------------------------------------------------------------
# 5b. Holographic memory: pre-create + pre-warm the shared "eng knowledge"
#     store (see profiles/debugger/config.yaml for the full writeup) BEFORE
#     any profile's session can touch it. Empirically confirmed 2026-07-04:
#     two processes racing to create the SAME not-yet-existing SQLite file
#     can hit an unhandled "database is locked" error on the initial WAL
#     pragma (hermes_state.py's WAL-fallback only catches NFS/SMB/FUSE
#     error strings, not ordinary lock contention — it re-raises). Once the
#     file/schema/WAL mode already exist, concurrent writers are fine
#     (also confirmed empirically). Warming here means the six sharing
#     profiles' first real fact_store call always hits the safe,
#     already-initialized case instead of racing each other on first use.
#     Idempotent: MemoryStore() only creates what's missing.
# ---------------------------------------------------------------------
echo "==> Pre-warming shared Holographic memory store..."
mkdir -p state/data/shared
docker exec "$CONTAINER" python3 -c "
import sys
sys.path.insert(0, '/opt/hermes/plugins/memory/holographic')
from store import MemoryStore
MemoryStore(db_path='/opt/data/shared/eng_memory_store.db')
"
docker exec "$CONTAINER" chown -R hermes:hermes /opt/data/shared

# ---------------------------------------------------------------------
# 6. Kanban board: create (idempotent — re-running prints "already
#    exists" and exits 0, confirmed against a live container), set this
#    project's default task workspace, and switch to it.
# ---------------------------------------------------------------------
echo "==> Ensuring Kanban board '$PROJECT_NAME' exists..."
docker exec "$CONTAINER" hermes kanban boards create "$PROJECT_NAME" \
  --default-workdir "/workspace/$PROJECT_NAME" --switch

echo "==> Done. Interface: docker exec -it $CONTAINER hermes"
echo "    Dashboard: http://127.0.0.1:9119 (user: ${env_values[HERMES_DASHBOARD_USERNAME]})"
echo ""
echo "    NOTE: 'hermes kanban notify-subscribe <task-id>' is task-scoped, not"
echo "    board/profile-scoped — there is no bootstrap-time equivalent. Subscribe"
echo "    the orchestrator's top-level task explicitly once it's created:"
echo "      docker exec -it $CONTAINER hermes kanban notify-subscribe <task-id>"
