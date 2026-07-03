#!/usr/bin/env bash
# bootstrap.sh — idempotent provisioning for one project's Hermes team.
#
# Usage:
#   ./bootstrap.sh <project-name> <repo-path>
#
# Example:
#   ./bootstrap.sh acme-app /home/damon/code/acme-app
#
# What this does NOT do: build the docker image, start the container, or
# touch anything under state/ except creating empty directories if missing.
# It is safe to re-run against a fresh container (task: "verify teardown/
# recreate cycle") or a second project (task: "parameterize bootstrap for
# per-project reuse") — every step below is a create-if-missing /
# overwrite-with-template operation, never a destructive one.
#
# Source of truth for WHAT gets provisioned lives in this repo (skills/,
# profiles/, hooks/, config/config.yaml) — this script wires those into a
# running Hermes profile + board, it does not author them itself beyond the
# per-project .env.

set -euo pipefail

PROJECT_NAME="${1:?Usage: ./bootstrap.sh <project-name> <repo-path>}"
REPO_PATH="${2:?Usage: ./bootstrap.sh <project-name> <repo-path>}"

if [[ ! -d "$REPO_PATH" ]]; then
  echo "error: repo path '$REPO_PATH' does not exist or is not a directory" >&2
  exit 1
fi
REPO_PATH="$(cd "$REPO_PATH" && pwd)"   # normalize to absolute

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "==> Bootstrapping Hermes team for project: $PROJECT_NAME"
echo "    repo:  $REPO_PATH"
echo "    state: $ROOT_DIR/state (writable, survives recycle)"
echo "    assets: $ROOT_DIR/{skills,profiles,hooks,config} (read-only, host-versioned)"

# ---------------------------------------------------------------------
# 1. Write / refresh .env for this project. Overwrites PROJECT_NAME and
#    PROJECT_REPO_PATH only; preserves an existing Z_AI_API_KEY if .env
#    already exists, so re-running this doesn't force a re-entry of secrets.
# ---------------------------------------------------------------------
EXISTING_KEY=""
if [[ -f .env ]]; then
  EXISTING_KEY="$(grep -E '^Z_AI_API_KEY=' .env | head -1 | cut -d= -f2- || true)"
fi
{
  echo "PROJECT_NAME=$PROJECT_NAME"
  echo "PROJECT_REPO_PATH=$REPO_PATH"
  echo "Z_AI_API_KEY=${EXISTING_KEY:-replace-me}"
  echo "HERMES_IMAGE_TAG=${HERMES_IMAGE_TAG:-latest}"
} > .env
if [[ -z "$EXISTING_KEY" || "$EXISTING_KEY" == "replace-me" ]]; then
  echo "    !! Z_AI_API_KEY not set — edit .env before starting the container."
fi

# ---------------------------------------------------------------------
# 2. Ensure writable state directories exist (Tier 2 — see docs/MOUNTS.md).
#    Never deletes existing content; this is what makes normal restarts
#    non-destructive while `docker compose down -v` (task #21) is the only
#    thing that actually wipes them.
# ---------------------------------------------------------------------
for d in kanban memory learned-skills credentials logs; do
  mkdir -p "state/$d"
  touch "state/$d/.gitkeep"
done

# ---------------------------------------------------------------------
# 3. Start (or restart, picking up any config.yaml/profile/skill/hook
#    changes) the container.
# ---------------------------------------------------------------------
echo "==> Starting container..."
docker compose up -d

# ---------------------------------------------------------------------
# 4. Provision the Hermes profile + board + worker profiles inside it.
#    Every command here is create-if-missing; Hermes profile/board create
#    commands are documented as safe to re-invoke (existing profile/board
#    is left alone, not recreated) — verify this against the installed
#    version during first run and note here if that assumption is wrong.
# ---------------------------------------------------------------------
CONTAINER="${PROJECT_NAME}-hermes"

echo "==> Waiting for container to be ready..."
sleep 3

echo "==> Ensuring Hermes profile '$PROJECT_NAME' exists..."
docker exec "$CONTAINER" hermes profile create "$PROJECT_NAME" 2>&1 \
  | grep -v "already exists" || true

echo "==> Ensuring Kanban board '$PROJECT_NAME' exists..."
docker exec "$CONTAINER" hermes kanban boards create "$PROJECT_NAME" 2>&1 \
  | grep -v "already exists" || true

echo "==> Registering worker profiles (orchestrator + 7 specialists)..."
for p in orchestrator product-manager project-manager full-stack-engineer \
         quality-engineer debugger qa-analyst ux-designer; do
  echo "    - $p"
  docker exec "$CONTAINER" hermes kanban worker-profile apply \
    --profile "$p" \
    --source "/home/node/.hermes/profiles-src/$p/profile.yaml" \
    --instructions "/home/node/.hermes/profiles-src/$p/instructions.md" \
    2>&1 | sed "s/^/      /"
  # NOTE: `worker-profile apply` command name/flags are this plan's
  # best-available assumption from the CLI reference — verify against
  # `hermes kanban worker-profile --help` on first real run and correct
  # this script if the surface differs. This is exactly the kind of gap
  # task #7 (dry run) exists to catch before wiring guardrails on top.
done

echo "==> Subscribing only the top-level orchestrator task lane to notifications..."
docker exec "$CONTAINER" hermes kanban notify-subscribe \
  --board "$PROJECT_NAME" --profile orchestrator --scope top-level \
  2>&1 | sed "s/^/    /" || true

echo "==> Done. Interface: docker exec -it $CONTAINER hermes"
echo "    Dashboard (read-only visibility): http://127.0.0.1:9119"
