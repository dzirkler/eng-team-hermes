#!/usr/bin/env bash
# update-speckit-skills.sh — regenerate the vendored, pinned SpecKit skills.
#
# This is the ONE place SpecKit is ever installed or upgraded. It runs at the
# REPO level on a maintainer's machine (which has network), NOT inside the
# Hermes container and NOT from bootstrap.sh. See docs/MOUNTS.md and
# speckit/README.md for why the install is vendored instead of done at
# container-start.
#
# What it does:
#   1. Installs SpecKit *pinned* to speckit/SPECKIT_VERSION via
#      `uvx --from git+...@v<version>` — reproducible regardless of whatever
#      `specify` happens to be on PATH.
#   2. Runs `specify init --integration claude`, which emits the `speckit-*`
#      skills under .claude/skills/ plus the .specify/ manifest tree.
#   3. Replaces the vendored copy under speckit/ with that output.
#   4. Verifies the result is drift-clean (`specify integration status`).
#
# The output under speckit/ is meant to be committed to git, so every SpecKit
# update is a normal, reviewable, revertable commit.
#
# Usage:
#   scripts/update-speckit-skills.sh              # regenerate at the pinned version
#   scripts/update-speckit-skills.sh 0.12.0       # bump the pin, then regenerate
#
# After running, review `git diff speckit/` and commit.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/speckit"
VERSION_FILE="$VENDOR_DIR/SPECKIT_VERSION"
SPEC_REPO="https://github.com/github/spec-kit.git"

# ---------------------------------------------------------------------
# Resolve the pinned version: CLI arg wins (a deliberate bump), else the
# tracked SPECKIT_VERSION file, which is the source of truth.
# ---------------------------------------------------------------------
if [[ "${1:-}" != "" ]]; then
  VERSION="$1"
elif [[ -f "$VERSION_FILE" ]]; then
  VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
else
  echo "error: no version given and $VERSION_FILE is missing." >&2
  echo "       Pass an explicit version, e.g.: $0 0.11.5" >&2
  exit 1
fi

if ! command -v uvx >/dev/null 2>&1; then
  echo "error: 'uvx' not found. Install uv: https://docs.astral.sh/uv/" >&2
  exit 1
fi

SPECIFY=(uvx --from "git+${SPEC_REPO}@v${VERSION}" specify)

echo "==> Regenerating vendored SpecKit skills at pinned version v${VERSION}"
echo "    vendor dir: $VENDOR_DIR"

# ---------------------------------------------------------------------
# Generate into a throwaway temp project, then swap it in. Initing into a
# clean dir keeps the .specify/ manifest paths relative and avoids merge
# semantics against a stale vendored copy.
# ---------------------------------------------------------------------
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

( cd "$TMP_DIR" && git init -q . )

echo "==> specify init (integration: claude, script: sh)..."
( cd "$TMP_DIR" && "${SPECIFY[@]}" init . \
    --integration claude --script sh --ignore-agent-tools --force )

# Sanity: the skills must actually be there before we clobber the vendored copy.
if [[ ! -d "$TMP_DIR/.claude/skills" ]] || \
   ! ls -d "$TMP_DIR"/.claude/skills/speckit-* >/dev/null 2>&1; then
  echo "error: init produced no .claude/skills/speckit-* — aborting, vendored copy untouched." >&2
  exit 1
fi

# ---------------------------------------------------------------------
# Swap in the freshly generated tree. Preserve the repo-authored files we
# keep alongside the generated output (README.md, SPECKIT_VERSION).
# ---------------------------------------------------------------------
echo "==> Replacing vendored tree..."
mkdir -p "$VENDOR_DIR"
rm -rf "$VENDOR_DIR/.specify" "$VENDOR_DIR/.claude" "$VENDOR_DIR/CLAUDE.md"
cp -R "$TMP_DIR/.specify" "$VENDOR_DIR/.specify"
cp -R "$TMP_DIR/.claude"  "$VENDOR_DIR/.claude"
[[ -f "$TMP_DIR/CLAUDE.md" ]] && cp "$TMP_DIR/CLAUDE.md" "$VENDOR_DIR/CLAUDE.md"

echo "$VERSION" > "$VERSION_FILE"

# ---------------------------------------------------------------------
# Verify the vendored copy is drift-clean against its own manifest.
# ---------------------------------------------------------------------
echo "==> Verifying (specify integration status)..."
( cd "$VENDOR_DIR" && "${SPECIFY[@]}" integration status )

echo ""
echo "==> Done. Vendored SpecKit skills at v${VERSION}:"
ls -1 "$VENDOR_DIR/.claude/skills" | sed 's/^/      /'
echo ""
echo "    Review and commit:"
echo "      git add speckit/"
echo "      git commit -m 'Update vendored SpecKit skills to v${VERSION}'"
