#!/usr/bin/env bash
# test-reasoning-passthrough.sh — confirm GLM-5.2 reasoning-effort controls
# actually reach Z.AI when routed through the team's LiteLLM proxy, and
# check whether Hermes's own agent.reasoning_effort plumbing survives the
# trip intact (Bash twin of test-reasoning-passthrough.ps1 — see that
# file's header comment for the full rationale of each verdict).
#
# Does NOT touch the running hermes-agent container — plain HTTPS chat
# completion calls, once straight to Z.AI and once through the LiteLLM
# proxy, diffed against each other.
#
# Requires: curl, python3, and Z_AI_API_KEY / GLM_API_KEY / GLM_BASE_URL
# either already exported or present in the repo-root .env.
#
# Cost note: 5 short, non-streaming chat completions against the real
# Z.AI account and the shared LiteLLM proxy — trivial against the team's
# Coding Plan budget, but real spend against the shared pool (see
# config/config.yaml), not a mock.
#
# Exit codes: 0 = proxy transparency confirmed, 1 = proxy passthrough
# mismatch (or a call errored), 2 = setup error.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    if [[ -z "${!key:-}" ]]; then export "$key=$value"; fi
  done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$ENV_FILE")
fi

for v in Z_AI_API_KEY GLM_API_KEY GLM_BASE_URL; do
  if [[ -z "${!v:-}" ]]; then
    echo "error: \$$v is not set (checked process env and $ENV_FILE)." >&2
    exit 2
  fi
done
command -v curl >/dev/null 2>&1 || { echo "error: curl not found." >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found." >&2; exit 2; }

DIRECT_URL="https://api.z.ai/api/paas/v4/chat/completions"
PROXY_URL="${GLM_BASE_URL%/}/chat/completions"
MODEL="glm-5.2"
PROMPT='A train leaves at 2:15pm and travels 3 legs: 45 min, then a 20 min stop, then 1hr 10min. What time does it arrive? Answer with just the final HH:MM.'

echo "Direct Z.AI endpoint  : $DIRECT_URL"
echo "LiteLLM proxy endpoint: $PROXY_URL"
echo "Model                 : $MODEL"
echo

# call NAME URL API_KEY EXTRA_BODY_JSON -> writes /tmp-scratch/<NAME>.json, prints one line
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

call() {
  local name="$1" url="$2" key="$3" extra="$4"
  local body
  body="$(python3 - "$MODEL" "$PROMPT" "$extra" <<'PY'
import json, sys
model, prompt, extra_json = sys.argv[1], sys.argv[2], sys.argv[3]
body = {"model": model, "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 300, "temperature": 0}
body.update(json.loads(extra_json))
print(json.dumps(body))
PY
)"
  local out="$WORKDIR/$name.json"
  local http_code
  http_code="$(curl -sS -o "$out" -w '%{http_code}' -X POST "$url" \
    -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
    -d "$body" --max-time 60 || echo "curl_error")"

  python3 - "$name" "$out" "$http_code" <<'PY'
import json, sys
name, path, code = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = json.load(open(path, encoding="utf-8"))
except Exception as e:
    print(f"{name}\tERROR\thttp={code}\t{e}")
    sys.exit(0)
if "error" in data or not data.get("choices"):
    print(f"{name}\tERROR\thttp={code}\t{data.get('error', data)}")
    sys.exit(0)
msg = data["choices"][0]["message"]
reasoning = msg.get("reasoning_content") or ""
content = " ".join((msg.get("content") or "").split())[:60]
toks = data.get("usage", {}).get("completion_tokens")
print(f"{name}\tOK\treasoning_len={len(reasoning)}\tcompletion_tokens={toks}\t{content!r}")
PY
}

declare -A RESULT
run_case() { # name url key extra_json
  local line
  line="$(call "$1" "$2" "$3" "$4")"
  echo "-> $line"
  RESULT["$1"]="$line"
}

run_case "direct-disabled"     "$DIRECT_URL" "$Z_AI_API_KEY" '{"thinking":{"type":"disabled"}}'
run_case "direct-enabled-high" "$DIRECT_URL" "$Z_AI_API_KEY" '{"thinking":{"type":"enabled"},"reasoning_effort":"high"}'
run_case "proxy-disabled"      "$PROXY_URL"  "$GLM_API_KEY"  '{"thinking":{"type":"disabled"}}'
run_case "proxy-enabled-high"  "$PROXY_URL"  "$GLM_API_KEY"  '{"thinking":{"type":"enabled"},"reasoning_effort":"high"}'
run_case "proxy-hermes-shaped" "$PROXY_URL"  "$GLM_API_KEY"  '{"reasoning":{"enabled":true,"effort":"medium"}}'

reasoning_len() { # name
  local line="${RESULT[$1]:-}"
  [[ "$line" == *$'\t'OK$'\t'* ]] || { echo "-1"; return; }
  echo "$line" | sed -n 's/.*reasoning_len=\([0-9]*\).*/\1/p'
}
is_ok() { [[ "${RESULT[$1]:-}" == *$'\t'OK$'\t'* ]]; }

echo
echo "--- Verdicts ---"
EXIT_CODE=0

if is_ok "direct-disabled" && is_ok "proxy-disabled" && is_ok "direct-enabled-high" && is_ok "proxy-enabled-high"; then
  dd=$(reasoning_len direct-disabled); pd=$(reasoning_len proxy-disabled)
  de=$(reasoning_len direct-enabled-high); pe=$(reasoning_len proxy-enabled-high)
  disabled_match=$([[ ( "$dd" -eq 0 ) == ( "$pd" -eq 0 ) ]] && echo 1 || echo 0)
  enabled_match=$([[ ( "$de" -gt 0 ) == ( "$pe" -gt 0 ) ]] && echo 1 || echo 0)
  if [[ "$disabled_match" == 1 && "$enabled_match" == 1 ]]; then
    echo "PASS: LiteLLM proxy passes thinking/reasoning_effort through unmodified (proxied behavior matches direct Z.AI for both disabled and enabled-high)."
  else
    echo "FAIL: proxy behavior diverges from direct Z.AI for an identical payload -> LiteLLM is altering/dropping thinking/reasoning_effort." >&2
    EXIT_CODE=1
  fi
else
  echo "SKIP verdict 1: one or more calls errored, see lines above." >&2
  EXIT_CODE=1
fi

if is_ok "proxy-disabled" && is_ok "proxy-enabled-high"; then
  pd=$(reasoning_len proxy-disabled); pe=$(reasoning_len proxy-enabled-high)
  if [[ "$pe" -gt 0 && "$pd" -eq 0 ]]; then
    echo "OK: reasoning_effort visibly changes proxied model behavior (disabled -> no reasoning_content, high -> reasoning_content present)."
  else
    echo "NOTE: disabled vs enabled-high did not show the expected reasoning_content on/off difference via the proxy — investigate before trusting the knob."
  fi
fi

if is_ok "proxy-hermes-shaped"; then
  ph=$(reasoning_len proxy-hermes-shaped)
  if [[ "$ph" -eq 0 ]]; then
    echo "CONFIRMED BUG (matches hermes-agent#16533, PR #16592 still unmerged): the payload shape Hermes's zai provider actually sends today (extra_body.reasoning) produces NO reasoning_content via this proxy -> setting agent.reasoning_effort in a profile's config.yaml currently has no effect on Z.AI/GLM." >&2
  else
    echo "Hermes-shaped payload DID produce reasoning_content here — hermes-agent#16533 may be fixed/mitigated in the running image version, or the proxy is normalizing the field. Worth re-checking against the actual image tag in use."
  fi
else
  echo "SKIP verdict 3: proxy-hermes-shaped call errored, see lines above." >&2
fi

exit "$EXIT_CODE"
