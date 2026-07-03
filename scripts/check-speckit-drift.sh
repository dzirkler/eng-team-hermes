#!/usr/bin/env bash
# check-speckit-drift.sh — fail if the vendored SpecKit skills were
# hand-edited outside the install flow.
#
# The vendored tree under speckit/ is a real SpecKit project whose
# .specify/integrations/*.manifest.json record a SHA-256 for every managed
# file. `specify integration status` re-hashes them and reports any that no
# longer match — which is exactly "someone hand-edited a skill instead of
# running scripts/update-speckit-skills.sh". We reuse that instead of
# rolling our own hashing.
#
# Runs at the REPO level (needs network only the first time uvx resolves the
# pinned CLI). Intended for CI and/or a pre-commit/periodic check — NOT part
# of the container or bootstrap.sh.
#
# Exit codes: 0 = clean, 1 = drift or missing files detected, 2 = setup error.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/speckit"
VERSION_FILE="$VENDOR_DIR/SPECKIT_VERSION"
SPEC_REPO="https://github.com/github/spec-kit.git"

if [[ ! -d "$VENDOR_DIR/.specify" ]]; then
  echo "error: $VENDOR_DIR/.specify not found — run scripts/update-speckit-skills.sh first." >&2
  exit 2
fi
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "error: $VERSION_FILE missing — cannot determine the pinned version." >&2
  exit 2
fi
if ! command -v uvx >/dev/null 2>&1; then
  echo "error: 'uvx' not found. Install uv: https://docs.astral.sh/uv/" >&2
  exit 2
fi

VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
SPECIFY=(uvx --from "git+${SPEC_REPO}@v${VERSION}" specify)

STATUS_JSON="$(cd "$VENDOR_DIR" && "${SPECIFY[@]}" integration status --json)"

# Prefer jq; fall back to python (both are commonly present, and one of them
# is guaranteed on any box that has uv).
read_field() { # $1 = json key
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$STATUS_JSON" | jq -r ".$1"
  else
    printf '%s' "$STATUS_JSON" | python -c "import sys,json;print(json.load(sys.stdin).get('$1',''))"
  fi
}

STATUS="$(read_field status)"
MODIFIED="$(read_field modified_managed_files)"
MISSING="$(read_field missing_managed_files)"

echo "Pinned SpecKit version : v${VERSION}"
echo "Integration status     : ${STATUS}"
echo "Modified managed files : ${MODIFIED}"
echo "Missing managed files  : ${MISSING}"

if [[ "$STATUS" == "ok" && "$MODIFIED" == "0" && "$MISSING" == "0" ]]; then
  echo "OK: vendored SpecKit skills match the pinned manifest."
  exit 0
fi

echo "" >&2
echo "DRIFT DETECTED: vendored SpecKit skills differ from their pinned manifest." >&2
echo "Someone edited skill files under speckit/ by hand. Do NOT hand-edit them." >&2
echo "To pick up an upstream change, run: scripts/update-speckit-skills.sh" >&2
echo "and commit the result. Full report:" >&2
echo "$STATUS_JSON" >&2
exit 1
