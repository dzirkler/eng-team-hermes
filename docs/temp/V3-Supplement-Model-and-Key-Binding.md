# Supplemental V3 Note — Model Selection & Per-Project Key Binding

**Owner:** Damon Zirkler
**Date:** 2026-07-03
**Type:** Supplement (additive) to `Quota-Block-Resilience-Plan.md` (§11) and `eng-team-plugin-hermes-migration-plan.md` (§8).
**Why a supplement:** Claude Code has already scaffolded/implemented the currently-documented plan, so those docs are a baseline of record. This note captures decisions made *after* that scaffold rather than retro-editing it.

---

## 0. Scope correction — runtime vs. tooling

**Runtimes are now confirmed:**

- **V2 runtime:** GitHub Copilot / VS Code (shared plugin).
- **V3 runtime:** **Hermes Agent** (per `eng-team-plugin-hermes-migration-plan.md`).

**Claude Code is a build tool here, not a runtime.** It is used only to generate the V3 (Hermes) scaffold and scripts. It is **not** the harness for V2 or V3.

Consequence: any Claude-Code-specific mechanism referenced during design discussion (`ANTHROPIC_DEFAULT_SONNET_MODEL`, subagent `model:` aliases, etc.) was **illustrative of the pattern only.** The concrete V3 binding is expressed in **Hermes terms** below: model tier set per **worker profile**, per-project key set at the **Hermes profile / container** level.

## 1. GLM context windows (corrected)

| Model | Context window | Notes |
|---|---|---|
| GLM-5.2 | **1,000,000** tokens | Flagship; ~5× GLM-4.7 |
| GLM-4.7 | **200,000** tokens | (128K is its *max output*, not context — supersedes the "128K" figure in resilience-plan §11) |

Implications for the model split:

- **Routing criterion:** send work with a *large working set* — whole-repo reasoning, big multi-file refactors, Plan/Tasks holding many files — to 5.2 (1M). Small, single-concern tasks fit 4.7's 200K comfortably.
- **Constraint (softened):** the cheap-tier (4.7) dispatch — stable prefix (constitution + plan + conventions) plus the task — must fit 200K with working room. 200K is roomy for well-scoped tasks, so this only bites if scope creeps (which the checkpoint/wave discipline already prevents). Keep the shared prefix artifact-pointer-based rather than inlined.

## 2. V2 is out of scope for model selection

Confirmed empirically: only 5 calls to GLM-4.7 in a full week, despite per-agent `model:` fields set. Root cause (per VS Code Copilot docs): the shared plugin path plus a picker-global model means per-agent `model:` fields are effectively ignored — the whole team runs on the single picker-selected model, and per-project model binding is only achievable by manually switching the picker.

**Therefore: model selection is a V3-only capability.** V2 stays "one model per session, switch the picker per project." Do not invest further in per-agent model routing in V2. (This is itself a concrete point in V3's favor on the trial scorecard.)

## 3. The binding pattern (Hermes)

Separate two concerns that V2 fatally conflated. In Hermes this maps directly onto its two-level structure — **worker profiles** (per persona) inside a **Hermes profile / container** (per project):

- **Model tier lives in the worker-profile config — per persona.** Each persona's worker profile sets its own model (GLM-5.2 for flagship personas, GLM-4.7 for cheap ones). Same worker-profile definitions across every project; the model id is a fixed tier choice, not project-specific.
- **Per-project key + Z.ai endpoint live at the Hermes-profile / container level.** The project's virtual key (`ANTHROPIC_AUTH_TOKEN`) and base URL (`https://api.z.ai/api/anthropic`) are injected as container env, shared by all worker profiles in that container. Each worker profile's model setting then selects GLM-5.2 vs GLM-4.7 as the request parameter under that one key.

Result: **shared worker-profile definitions, per-project virtual keys, and per-persona model tiers — all at once.** This is precisely the combination the V2 shared plugin could not provide.

Because a Hermes worker profile *is* the model context, the SpecKit-inheritance ambiguity from earlier dissolves: whatever worker profile runs a SpecKit stage uses that profile's model. Senior Engineer profile (5.2) → `speckit.plan`/`speckit.tasks` at 5.2; Implementation Engineer profile (4.7) → `speckit.implement` at 4.7. No separate subagent model-resolution step to reason about.

## 4. Isolation boundary = one container per project (expands migration §8)

The per-project isolation boundary (one **Hermes profile / `HERMES_HOME`** per project, per migration §8) now carries **three** things, not two:

1. That project's **virtual API key** + Z.ai endpoint (for per-project spend attribution).
2. **Skills/memory** isolation (migration-plan §5/§8).
3. The set of **worker profiles with their model tiers** (§3).

**Recommendation: one Docker container per project**, each holding that project's `HERMES_HOME`, as the clean hard boundary — separate filesystem/workspace, separate env (key + endpoint), separate MCP/config — mapping 1:1 to a project. This is the cleanest way to inject a per-project key and satisfies the isolation intent of migration §8 better than a shared instance.

**Keys:** one virtual key per project is sufficient — the model is a request parameter, so a single key calls both GLM-5.2 and GLM-4.7. This collapses the current VS-Code-era "multiple keys, one per model" hack. Per-model spend breakdown remains available from the proxy's per-call `model` field. Use two keys per project *only* if you want the proxy to bucket 5.2 vs 4.7 spend separately.

*Verify:* confirm the virtual keys are not model-bound in the proxy (standard Z.ai keys are not), so one-key-per-project holds.

## 5. Tier map (V3 / Hermes worker profiles)

This map applies to **Hermes worker profiles only** — it is not implementable in V2 (see §2). Note the migration-plan §2 profile list expands: `full-stack-engineer` splits into **senior-engineer** (flagship) and **implementation-engineer** (cheap).

| Worker profile | Tier | Model |
|---|---|---|
| Orchestrator | flagship | GLM-5.2 |
| Senior Engineer (Plan/Tasks + ad-hoc, troubleshooting, fixes, review) | flagship | GLM-5.2 |
| Product Manager | flagship | GLM-5.2 |
| UX Designer | flagship | GLM-5.2 |
| Debugger | flagship | GLM-5.2 |
| Implementation Engineer (well-defined Implement-phase tasks only) | cheap | GLM-4.7 |
| QA Analyst | cheap | GLM-4.7 |
| Quality Engineer | cheap | GLM-4.7 |
| Project Manager | cheap | GLM-4.7 |
| SpecKit stages | — | run under the invoking worker profile's model (§3) |

## 6. First V3 trial step — model-attribution smoke test

Before building on the binding, prove it in **Hermes**: run one cheap-tier worker profile through a real task and confirm via the proxy's per-call `model` field that the calls bill as GLM-4.7 (not a silent fallback to flagship), and that a flagship profile routes to GLM-5.2. This is the Hermes analog of the V2 attribution test — and validates that per-worker-profile model config actually reaches Z.ai before anything is built on it.

## 7. Open items

- ~~Confirm the **Hermes worker-profile model-config field/mechanism** and wire the §5 tiers into it.~~ **Done 2026-07-03**: `model:` is a real per-profile `config.yaml` section (`provider`/`default`/`api_key_env`/`base_url`); §5 tiers wired into all 9 profiles and verified live (see §6 result below).
- ~~Verify virtual keys are not model-bound (enables one-key-per-project, §4).~~ **Corrected 2026-07-03**: the same `Z_AI_API_KEY` works against *both* the standard endpoint and the Coding Plan endpoint (§8) — confirmed live, no auth error on either. (`hermes_cli/auth.py`'s `ZAI_ENDPOINTS` prober exists to handle accounts where a key is *not* portable across endpoints, but that isn't this account's situation — don't assume the prober's existence implies the restriction applies here.)
- Confirm how the **Hermes profile / container** injects the per-project key + Z.ai base URL (env vs config.yaml), and standardize the container template. *(Still open — see §4/§8: key is env, endpoint is now `model.base_url` in config.yaml, both confirmed working, but not yet folded into a single documented container template.)*

## 8. Z.AI Coding Plan endpoint (2026-07-03 addendum)

This team qualifies for Z.AI's **GLM Coding Plan** (subscription quota rather than pay-per-token API billing), so every profile's `model.base_url` was pointed at the coding endpoint instead of the standard one:

| | `base_url` |
|---|---|
| Standard (previous default) | `https://api.z.ai/api/paas/v4` |
| **Coding Plan (current)** | `https://api.z.ai/api/coding/paas/v4` |

`model.base_url` is a real config.yaml field that overrides the built-in `zai` provider's hardcoded base URL (confirmed by reading `providers/base.py` and `hermes_cli/config.py`'s config-migration code inside a live container — `plugins/model-providers/zai/__init__.py` hardcodes the standard URL as a default, and `model.base_url` takes precedence over it). Set identically in `config/config.yaml` (root/default profile) and all 9 `profiles/*/config.yaml` files.

**Same key, both endpoints:** verified live 2026-07-03 — a `senior-engineer` (glm-5.2) call and an `implementation-engineer` (glm-4.7) call both billed with `billing_base_url: https://api.z.ai/api/coding/paas/v4` using the one shared `Z_AI_API_KEY`, no auth error on either. This confirms the §4 "one virtual key per project" design holds under the coding-plan endpoint too — no separate key needed.

**Correction (2026-07-03, same day): `model.base_url` alone is not reliable — pin `GLM_BASE_URL` too.** Repeated live testing surfaced a real race: `hermes_cli/auth.py`'s `_resolve_zai_base_url()` runs a background Z.AI endpoint auto-probe (global/cn/coding-global/coding-cn, in that order) on every agent init, logged as `Z.AI: auto-detected endpoint ...`. Usually the explicit `model.base_url` still won the actual API call, but in 1 of 4 live calls the probe's own result (`China`, `https://open.bigmodel.cn/api/paas/v4` — not even the coding endpoint) won instead, silently overriding the configured value for that one call. This is a genuine precedence bug/race in Hermes, not a config mistake.

Fix: `_resolve_zai_base_url()` checks the `GLM_BASE_URL` env var *first* and returns immediately if set (`if env_override: return env_override`), skipping the probe entirely. Added `GLM_BASE_URL=${GLM_BASE_URL:-https://api.z.ai/api/coding/paas/v4}` to `docker-compose.yml`'s container-wide `environment:` block (applies to every profile in the container, alongside `Z_AI_API_KEY`). Verified live: 9 consecutive calls across both `senior-engineer` and `implementation-engineer` post-fix show zero `auto-detected endpoint` log lines and 100% correct `base_url` — the env var fully short-circuits the race. Keep `model.base_url` in each profile's config.yaml too (harmless belt-and-suspenders / self-documenting), but treat `GLM_BASE_URL` as the actually load-bearing pin.

Later same-day follow-up (§9) traced the *why* precisely: reading `hermes_cli/runtime_provider.py`'s generic API-key-provider branch shows `model.base_url` **does** correctly win over the probed URL whenever `model.provider` matches — the probe (`_resolve_zai_base_url`) still runs unconditionally every time (hence the log lines), but its result is discarded in favor of `model_cfg.base_url` at the call site. The observed 1-in-4 race was therefore likely a second, different resolution path (not yet fully isolated) rather than a flaw in that specific branch — moot in practice, since `GLM_BASE_URL` short-circuits the probe before either path runs and has shown 0 failures across 15+ live calls since.

## 9. Routing through a LiteLLM proxy for per-team token tracking (2026-07-03, same day)

The team qualifies for centralized per-team token-usage tracking via LiteLLM virtual keys, so the main chat model was re-routed a second time: from Z.AI's Coding Plan endpoint directly, to the team's LiteLLM proxy (`https://litellm.home.zirkler.com/v1`) which fronts Z.AI/GLM and issues per-project virtual keys. Two things had to be verified live before treating "just change the URL and key" as safe, per the same "verify, don't assume" discipline as §8:

**1. `model.api_key_env` is decorative for the built-in `zai` provider — confirmed by direct test.** Pointed `senior-engineer`'s `api_key_env` at a nonexistent env var (`BOGUS_UNSET_KEY_VAR`); the call still succeeded. Reading `hermes_cli/auth.py`'s `resolve_api_key_provider_credentials()` confirms why: the API key always comes from `PROVIDER_REGISTRY["zai"].api_key_env_vars`, a hardcoded tuple `(GLM_API_KEY, ZAI_API_KEY, Z_AI_API_KEY)` tried in that order, first usable one wins — `model.api_key_env` in config.yaml is never consulted at all.

**2. That fixed priority order solved a real conflict** rather than being incidental: `config/config.yaml`'s `mcp_servers.zai-vision` and `zai-web-search` reference `${Z_AI_API_KEY}` directly against *real* Z.AI endpoints (not proxied through LiteLLM). If `Z_AI_API_KEY` had been overwritten with the LiteLLM virtual key, those two MCP tools would have broken. Since `GLM_API_KEY` is checked *before* `Z_AI_API_KEY`, it was used for the LiteLLM virtual key instead — `Z_AI_API_KEY` stays untouched as the real Z.AI key, and both concerns are satisfied simultaneously without a new mechanism.

Final wiring (`docker-compose.yml`, container-wide `environment:`):
- `Z_AI_API_KEY` — unchanged, the real Z.AI key, used only by the two direct MCP tools.
- `GLM_API_KEY` — the project's LiteLLM virtual key; used by the main chat model (checked first in the priority order above).
- `GLM_BASE_URL` — now `https://litellm.home.zirkler.com/v1` instead of the Coding Plan URL.

Every profile's `config.yaml` `model.base_url` was updated to match (documentation/belt-and-suspenders, per the §8 correction — `GLM_BASE_URL` remains the actually load-bearing value).

**Verified live 2026-07-03:** with a real per-project LiteLLM virtual key set as `GLM_API_KEY`, both `senior-engineer` (glm-5.2) and `implementation-engineer` (glm-4.7) calls succeeded with `billing_base_url: https://litellm.home.zirkler.com/v1`, no auth error, and zero Z.AI auto-probe log lines (picked up the new URL immediately via `GLM_BASE_URL`, same as §8's fix). Model names required no remapping — the team's LiteLLM `model_list` registers GLM models under the same names Hermes already sends (`glm-5.2`, `glm-4.7`).
