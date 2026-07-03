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

PROJECT_NAME="${1:?Usage: ./bootstrap.sh <project-name> <repo-path>}"
REPO_PATH="${2:?Usage: ./bootstrap.sh <project-name> <repo-path>}"

if [[ ! -d "$REPO_PATH" ]]; then
  echo "error: repo path '$REPO_PATH' does not exist or is not a directory" >&2
  exit 1
fi
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PROFILE_NAMES=(orchestrator product-manager project-manager senior-engineer \
               implementation-engineer quality-engineer debugger qa-analyst ux-designer)

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
  esac
}

random_secret() {
  local length="${1:-32}"
  LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
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
: "${env_values[HERMES_IMAGE_TAG]:=latest}"
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
